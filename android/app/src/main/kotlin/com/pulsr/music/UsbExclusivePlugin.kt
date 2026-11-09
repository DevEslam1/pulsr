package com.pulsr.music

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * USB Audio Class exclusive-path plugin.
 *
 * SCOPE (honest):
 *  - Reads the attached DAC's advertised UAC version and Audio Control
 *    descriptors (Feature Unit / Volume control) from the raw configuration
 *    descriptors returned by UsbDeviceConnection.
 *  - Controls the DAC's *hardware* volume directly through UAC class-specific
 *    GET/SET_CUR requests. This is the same low-distortion hardware attenuation
 *    path UAPP/Poweramp use. Whether those requests are answered while
 *    Android's `snd-usb-audio` driver still owns the AudioControl interface is
 *    not assumed: usbfs may reply EBUSY, so a volume or clock is only ever
 *    reported as applied when the exact value comes back (see
 *    [UsbHardwareVolume.applied] and [UsbAudioProtocol.setSampleRate]).
 *  - Can optionally claim the AudioStreaming interface for an exclusive path.
 *    The claim is non-forced: if Android's kernel audio driver already owns the
 *    interface (the normal case) the claim fails cleanly and audio is left
 *    untouched. We never force-detach the kernel driver, which would silence the
 *    device.
 *  - Raw isochronous UAC2/UAC1 streaming IS implemented (see the direct
 *    isochronous sink in UsbAudioSink.cpp): on startStreaming the plugin
 *    force-claims the AudioStreaming interface, selects the alternate setting
 *    whose FORMAT_TYPE_I matches the requested rate + bit depth, programs the
 *    DAC's sample clock (UAC2 Clock-Source SET_CUR / UAC1 endpoint SET_CUR),
 *    and hands the usbfs fd to the native sink which drives the iso OUT endpoint
 *    directly. It still requires validation against physical hardware. Native
 *    DSD512 over DoP flows through the same PCM sink; it is not a separate path.
 */
class UsbExclusivePlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "UsbExclusivePlugin"
        const val METHOD_CHANNEL = "com.pulsr.music/usb_exclusive"
        const val EVENT_CHANNEL = "com.pulsr.music/usb_exclusive_events"
        private const val ACTION_USB_PERMISSION = "com.pulsr.music.USB_PERMISSION"

        /**
         * Cross-plugin snapshot for [HiResDacPlugin]: the direct UAC2
         * isochronous sink is streaming / the attached DAC exposes a streaming
         * endpoint. Bit-Perfect uses this as its fallback when Android does not
         * advertise exclusive mixer attributes for the DAC.
         */
        internal data class DirectStreamStatus(
            val deviceId: Int, val deviceName: String,
            val sampleRate: Int, val bitDepth: Int, val channels: Int,
        )
        @Volatile private var directOwner: UsbExclusivePlugin? = null
        internal fun confirmedDirectStream(): DirectStreamStatus? {
            val owner = directOwner ?: return null
            val status = owner.directStatus ?: return null
            return status.takeIf { owner.isNativeActive() && owner.directStatus === status }
        }
        val directStreamingActive: Boolean get() = confirmedDirectStream() != null
        @Volatile var directStreamingSupported: Boolean = false

        private const val CTRL_TIMEOUT_MS = 1000

        /** Minimum gap between hardware-volume range reads during polling. */
        private const val VOLUME_REFRESH_INTERVAL_MS = 2000L
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    @Volatile private var eventSink: EventChannel.EventSink? = null
    private var connection: UsbDeviceConnection? = null
    private var openedDevice: UsbDevice? = null
    private var volumeUnit: UsbAudioControlParser.FeatureUnitVolume? = null
    private var claimedInterface: UsbInterface? = null
    private var uacVersion: Int = UsbAudioControlParser.UAC_NONE
    private var streamInterfaceNumber: Int? = null
    private var parsedResult: UsbAudioControlParser.Result? = null

    private var hardwareVolume: UsbHardwareVolume? = null
    private var lastVolumeRefreshAtMs = 0L

    private var nativeLoaded = false
    @Volatile private var streaming = false
    @Volatile private var streamFormat: UsbAudioProtocol.StreamFormat? = null
    @Volatile private var directStatus: DirectStreamStatus? = null
    private var claimedStreamingInterface: UsbInterface? = null
    private var claimedControlInterface: UsbInterface? = null

    // Blocking USB control transfers, raw-descriptor parsing and native sink
    // start/stop/query must never run on the main thread (ANR). All such work
    // is serialized onto this single worker thread; MethodChannel replies are
    // posted back to the main thread. getStatus() measures a fresh status on
    // this worker (a caller that just started or stopped a stream must not be
    // handed a stale cache) and updates [cachedStatus] on the way out; the
    // event stream replays that cache when a listener subscribes.
    private val workerThread = HandlerThread("UsbExclusiveWorker").apply { start() }
    private val workerHandler = Handler(workerThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var cachedStatus: Map<String, Any?> =
        baseStatus(attached = false, permitted = false, device = null)

    // Raw UAC2 isochronous streaming, implemented in UsbAudioSink.cpp.
    private external fun nativeUsbStreamStart(
        fd: Int, endpoint: Int, interfaceNumber: Int, altSetting: Int,
        sampleRate: Int, channels: Int,
    ): Int
    private external fun nativeUsbStreamStartWithFormat(
        fd: Int, endpoint: Int, interfaceNumber: Int, altSetting: Int,
        sampleRate: Int, channels: Int, bytesPerSample: Int, validBitDepth: Int,
    ): Int
    private external fun nativeUsbStreamStop()
    private external fun nativeUsbStreamIsActive(): Boolean
    private external fun nativeUsbStreamGetRawPcmBitDepth(): Int
    private external fun nativeUsbStreamGetLastError(): Int

    private fun safeRawPcmBitDepth(): Int = if (streaming && safeIsStreamActive()) {
        try { nativeUsbStreamGetRawPcmBitDepth() } catch (_: Throwable) { 0 }
    } else 0
    private external fun nativeUsbStreamGetUnderrunCount(): Long
    private external fun nativeUsbStreamGetOverrunCount(): Long
    private external fun nativeUsbStreamGetBufferedMs(): Double
    private external fun nativeUsbQuerySupportedRates(fd: Int, interfaceNumber: Int): IntArray
    private external fun nativeUsbGetProducerChannels(): Int
    private external fun nativeUsbStreamGetChannelMismatchFrames(): Long
    private external fun nativeUsbStreamResetChannelMismatchFrames()

    @Volatile private var lastStreamResultCode: Int? = null
    @Volatile private var lastRateVerified: Boolean = false

    private fun safeGetLastError(): Int = if (nativeLoaded) try { nativeUsbStreamGetLastError() } catch (_: Throwable) { 0 } else 0
    private fun safeGetUnderrunCount(): Long = if (nativeLoaded) try { nativeUsbStreamGetUnderrunCount() } catch (_: Throwable) { 0L } else 0L
    private fun safeGetOverrunCount(): Long = if (nativeLoaded) try { nativeUsbStreamGetOverrunCount() } catch (_: Throwable) { 0L } else 0L
    private fun safeGetBufferedMs(): Double = if (nativeLoaded) try { nativeUsbStreamGetBufferedMs() } catch (_: Throwable) { 0.0 } else 0.0
    private fun safeIsStreamActive(): Boolean = if (nativeLoaded) try { nativeUsbStreamIsActive() } catch (_: Throwable) { false } else false
    private fun safeGetProducerChannels(): Int = if (nativeLoaded) try { nativeUsbGetProducerChannels() } catch (_: Throwable) { 0 } else 0
    private fun safeGetChannelMismatchFrames(): Long = if (nativeLoaded) try { nativeUsbStreamGetChannelMismatchFrames() } catch (_: Throwable) { 0L } else 0L
    private fun safeResetChannelMismatchFrames() { if (nativeLoaded) try { nativeUsbStreamResetChannelMismatchFrames() } catch (_: Throwable) {} }
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var permissionReceiver: BroadcastReceiver? = null

    private val deviceReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val detached: UsbDevice? = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }
                    // closeLocked() stops the native sink and closes the USB
                    // connection (blocking); run it off the main thread.
                    workerHandler.post {
                        if (detached == null || detached.deviceId == openedDevice?.deviceId) {
                            closeLocked()
                        }
                        emitState()
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> emitState()
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registerDeviceReceiver()
        nativeLoaded = try {
            System.loadLibrary("pulsr_dsp")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "Native DSP library unavailable: ${e.message}")
            false
        }
    }

    private fun registerDeviceReceiver() {
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        try {
            ContextCompat.registerReceiver(
                context,
                deviceReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register USB device receiver: ${e.message}")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getStatus" -> {
                    runAsync(call.method, result) { buildStatus().also { cachedStatus = it } }
                }
                "requestPermission" -> requestPermission(result)
                "setExclusive" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runAsync(call.method, result) { setExclusiveInternal(enabled) }
                }
                "setHardwareVolume" -> {
                    val db = call.argument<Double>("db") ?: 0.0
                    runAsync(call.method, result) { setHardwareVolumeInternal(db) }
                }
                "startStreaming" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val channels = call.argument<Int>("channels") ?: 2
                    val bitDepth = call.argument<Int>("bitDepth") ?: 16
                    val strict = call.argument<Boolean>("strict") ?: false
                    runAsync(call.method, result) { startStreamingInternal(sampleRate, channels, bitDepth, strict) }
                }
                "stopStreaming" -> runAsync(call.method, result) { stopStreamingInternal() }
                "resetChannelMismatchFrames" -> {
                    safeResetChannelMismatchFrames()
                    result.success(true)
                }
                "isStreamingSupported" -> {
                    // openedDevice is mutated on workerThread; reading it on the
                    // main thread is a data race. Dispatch to the worker thread.
                    runAsync(call.method, result) {
                        val device = openedDevice ?: findAudioDevice()
                        nativeLoaded && device != null &&
                            device.streamingInterfaces().isNotEmpty()
                    }
                }
                "getDiagnostics" -> {
                    val diag = mapOf(
                        "lastError" to safeGetLastError(),
                        "underrunCount" to safeGetUnderrunCount(),
                        "overrunCount" to safeGetOverrunCount(),
                        "channelMismatchFrames" to safeGetChannelMismatchFrames(),
                        "isStreamActive" to safeIsStreamActive(),
                        "bufferedMs" to safeGetBufferedMs()
                    )
                    result.success(diag)
                }
                "getBufferedMs" -> {
                    result.success(safeGetBufferedMs())
                }
                "getProducerChannels" -> {
                    result.success(safeGetProducerChannels())
                }
                "setVolumeCalibrationOffset" -> {
                    val offsetDb = call.argument<Double>("offsetDb") ?: 0.0
                    // openedDevice is mutated on workerThread; dispatch there to
                    // avoid a data race and so emitState() runs on the worker.
                    runAsync(call.method, result) {
                        val device = openedDevice ?: findAudioDevice()
                        if (device != null) {
                            setVolumeCalibrationOffset(device.vendorId, device.productId, offsetDb)
                            emitState()
                            true
                        } else {
                            false
                        }
                    }
                }
                "getVolumeCalibrationOffset" -> {
                    // openedDevice is mutated on workerThread; dispatch there to
                    // avoid a data race.
                    runAsync(call.method, result) {
                        val device = openedDevice ?: findAudioDevice()
                        if (device != null) {
                            getVolumeCalibrationOffset(device.vendorId, device.productId)
                        } else 0.0
                    }
                }
                "querySupportedRates" -> runAsync(call.method, result) { querySupportedRatesInternal() }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MethodChannel error handling ${call.method}: ${e.message}", e)
            result.error("USB_EXCLUSIVE_ERROR", e.message, null)
        }
    }

    /**
     * Runs blocking USB work on the dedicated worker thread and delivers the
     * MethodChannel reply back on the main thread. Exactly one of
     * result.success/result.error is invoked on every path.
     */
    private fun runAsync(method: String, result: MethodChannel.Result, block: () -> Any?) {
        workerHandler.post {
            try {
                val value = block()
                mainHandler.post {
                    try { result.success(value) } catch (_: Exception) {}
                }
            } catch (e: Throwable) {
                mainHandler.post {
                    Log.e(TAG, "MethodChannel error handling $method: ${e.message}", e)
                    try { result.error("USB_EXCLUSIVE_ERROR", e.message, null) } catch (_: Exception) {}
                }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitState()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        // A permission prompt the user never answered still has to be answered:
        // the Dart caller awaits requestPermission(), and tearing the plugin
        // down underneath it would leave that future pending forever.
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        try {
            permissionReceiver?.let {
                try { context.unregisterReceiver(it) } catch (_: Exception) {}
            }
            try { context.unregisterReceiver(deviceReceiver) } catch (_: Exception) {}
        } catch (_: Exception) {}
        permissionReceiver = null
        try { pending?.success(false) } catch (_: Exception) {}
        try { methodChannel.setMethodCallHandler(null) } catch (_: Exception) {}
        try { eventChannel.setStreamHandler(null) } catch (_: Exception) {}
        // closeLocked() closes the native sink and the usbfs connection, which
        // can block; keep it off the main thread. quitSafely() runs queued work
        // before the looper exits.
        val posted = try {
            workerHandler.post {
                try { closeLocked() } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            false
        }
        if (!posted) {
            try { closeLocked() } catch (_: Exception) {}
        }
        try { workerThread.quitSafely() } catch (_: Exception) {}
    }

    // ---- device discovery / descriptor parsing ----

    private fun findAudioDevice(): UsbDevice? =
        try {
            val devices = usbManager?.deviceList?.values ?: return null
            // A device this plugin already opened stays preferred while it is
            // still attached: re-discovery must never swap the DAC out from
            // under an open connection.
            openedDevice?.let { open ->
                if (devices.any { it.deviceId == open.deviceId }) return open
            }
            // An explicitly audio-classed device beats the vendor-specific
            // (0xFF) shape, and a device the user already granted permission
            // for beats one that would trigger a new dialog. Devices without
            // any AudioStreaming interface have no playback pipe and are never
            // candidates.
            var audioClass: UsbDevice? = null
            var audioClassPermitted: UsbDevice? = null
            var vendorAudio: UsbDevice? = null
            var vendorAudioPermitted: UsbDevice? = null
            for (device in devices) {
                if (device.streamingInterfaces().isEmpty()) continue
                var isAudio = false
                var isVendor = false
                for (index in 0 until device.interfaceCount) {
                    val iface = device.getInterface(index)
                    if (!UsbAudioControlParser.isAudioFunctionInterface(
                            iface.interfaceClass,
                            iface.interfaceSubclass,
                            iface.interfaceProtocol,
                        )
                    ) {
                        continue
                    }
                    if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO) isAudio = true
                    else isVendor = true
                }
                val permitted = usbManager?.hasPermission(device) == true
                if (isAudio) {
                    if (permitted && audioClassPermitted == null) audioClassPermitted = device
                    else if (audioClass == null) audioClass = device
                } else if (isVendor && hasVendorAudioPair(device)) {
                    if (permitted && vendorAudioPermitted == null) vendorAudioPermitted = device
                    else if (vendorAudio == null) vendorAudio = device
                }
            }
            audioClassPermitted ?: audioClass ?: vendorAudioPermitted ?: vendorAudio
        } catch (_: Throwable) {
            null
        }

    /**
     * A vendor-specific (0xFF) device only counts as audio when it shows BOTH
     * an audio-shaped control and an audio-shaped streaming interface, so an
     * ADB/debug accessory (also 0xFF) can never match on one stray interface.
     */
    private fun hasVendorAudioPair(device: UsbDevice): Boolean {
        var control = false
        var streaming = false
        for (index in 0 until device.interfaceCount) {
            val iface = device.getInterface(index)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_AUDIO) continue
            if (UsbAudioControlParser.isAudioControlInterface(
                    iface.interfaceClass, iface.interfaceSubclass, iface.interfaceProtocol,
                )
            ) {
                control = true
            }
            if (UsbAudioControlParser.isAudioStreamingInterface(
                    iface.interfaceClass, iface.interfaceSubclass, iface.interfaceProtocol,
                )
            ) {
                streaming = true
            }
        }
        return control && streaming
    }

    /** Interfaces of [device] that are AudioStreaming interfaces. */
    private fun UsbDevice.streamingInterfaces(): List<UsbInterface> =
        (0 until interfaceCount).map { getInterface(it) }.filter { iface ->
            UsbAudioControlParser.isAudioStreamingInterface(
                iface.interfaceClass, iface.interfaceSubclass, iface.interfaceProtocol,
            )
        }

    /** Interface-only fallback used before a device connection is available. */
    private fun parseViaInterfaces(device: UsbDevice): UsbAudioControlParser.Result {
        val streaming = device.streamingInterfaces().firstOrNull()?.id
        val pairs = ArrayList<Pair<Int, Int>>(device.interfaceCount)
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (!UsbAudioControlParser.isAudioFunctionInterface(
                    iface.interfaceClass, iface.interfaceSubclass, iface.interfaceProtocol,
                )
            ) continue
            pairs.add(Pair(iface.interfaceSubclass, iface.interfaceProtocol))
        }
        val uac = try {
            UsbDacDiagnostics.uacVersionFromUsbInterfaces(pairs)
        } catch (_: Throwable) {
            UsbAudioControlParser.UAC_NONE
        }
        return UsbAudioControlParser.Result(uac, null, streaming)
    }

    /** Parses raw configuration descriptors from an open connection. */
    private fun parseViaRawDescriptors(
        conn: UsbDeviceConnection,
    ): UsbAudioControlParser.Result? {
        val raw = try { conn.rawDescriptors } catch (_: Exception) { null } ?: return null
        val parsed = UsbAudioControlParser.parse(raw)
        return if (parsed.uacVersion != UsbAudioControlParser.UAC_NONE ||
            parsed.volumeUnit != null
        ) parsed else null
    }

    private fun applyParsed(parsed: UsbAudioControlParser.Result) {
        parsedResult = parsed
        uacVersion = parsed.uacVersion
        streamInterfaceNumber = parsed.streamingInterface
        volumeUnit = parsed.volumeUnit
    }

    private fun ensureConnection(device: UsbDevice): UsbDeviceConnection? {
        connection?.let {
            if (openedDevice?.deviceId == device.deviceId) return it
            closeLocked()
        }
        val conn = try { usbManager?.openDevice(device) } catch (_: Exception) { null }
            ?: return null
        connection = conn
        openedDevice = device
        val parsed = parseViaRawDescriptors(conn) ?: parseViaInterfaces(device)
        applyParsed(parsed)
        hardwareVolume = parsed.volumeUnit?.let { UsbHardwareVolume(parsed.uacVersion, it, transport(conn)) }
        lastVolumeRefreshAtMs = SystemClock.elapsedRealtime()
        hardwareVolume?.refresh()
        return conn
    }

    /**
     * Reading a volume range is several control transfers with a 1 s timeout
     * each, all on the single USB worker thread, so status polling re-reads it
     * at most every [VOLUME_REFRESH_INTERVAL_MS]. An invalidated cache (device
     * change, refused write, new connection) always re-reads.
     */
    private fun refreshHardwareVolumeIfNeeded() {
        val volume = hardwareVolume ?: return
        val now = SystemClock.elapsedRealtime()
        if (volume.ready && now - lastVolumeRefreshAtMs < VOLUME_REFRESH_INTERVAL_MS) return
        lastVolumeRefreshAtMs = now
        volume.refresh()
    }

    private fun buildStatus(): Map<String, Any?> {
        if (openedDevice != null && usbManager?.deviceList?.values?.none {
                it.deviceId == openedDevice?.deviceId
            } != false) closeLocked()
        val device = openedDevice ?: findAudioDevice()
        if (device == null) {
            return baseStatus(attached = false, permitted = false, device = null)
        }
        val permitted = usbManager?.hasPermission(device) == true
        if (!permitted && connection != null) closeLocked()
        // Keep the FULL parsed result: reconstructing it from the cached summary
        // fields dropped `streamingEndpoint`, so `streamingSupported` was always
        // false once a connection was open and the direct bit-perfect toggle
        // never appeared.
        val parsed: UsbAudioControlParser.Result = if (permitted) {
            ensureConnection(device)
            parsedResult ?: parseViaInterfaces(device).also { applyParsed(it) }
        } else {
            parseViaInterfaces(device).also { applyParsed(it) }
        }
        if (streaming && !isNativeActive()) {
            Log.w(TAG, "USB streaming sink inactive; releasing the interface")
            clearStreaming()
        }
        val directCapable = parsed.uacVersion in 1..2 && parsed.altSettingFormats.isNotEmpty()
        directStreamingSupported = nativeLoaded && directCapable
        refreshHardwareVolumeIfNeeded()
        val hasVolume = permitted && hardwareVolume?.ready == true
        return mapOf(
            "attached" to true,
            "permitted" to permitted,
            "deviceName" to deviceLabel(device),
            "deviceId" to device.deviceId,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "uacVersion" to parsed.uacVersion,
            "uacLabel" to uacLabel(parsed.uacVersion),
            "hasVolumeControl" to hasVolume,
            "exclusiveActive" to (claimedInterface != null),
            "exclusiveSupported" to hasVolume,
            "streamingActive" to streaming,
            "streamingSupported" to (nativeLoaded && directCapable),
            "streamingSampleRate" to (streamFormat?.sampleRate ?: 0),
            "streamingBitDepth" to (streamFormat?.wireBitDepth ?: 0),
            "rawPcmBitDepth" to safeRawPcmBitDepth(),
            "streamingChannels" to (streamFormat?.wireChannels ?: 0),
            "hardwareVolumeDb" to hardwareVolume?.currentDb,
            "hardwareVolumeApplied" to (hardwareVolume?.applied == true),
            "minVolumeDb" to hardwareVolume?.minDb,
            "maxVolumeDb" to hardwareVolume?.maxDb,
            "interfaceNumber" to parsed.streamingInterface,
            "supportedRates" to parsed.supportedRates,
            "lastError" to safeGetLastError(),
            "resultCode" to lastStreamResultCode,
            "underrunCount" to safeGetUnderrunCount(),
            "overrunCount" to safeGetOverrunCount(),
            "channelMismatchFrames" to safeGetChannelMismatchFrames(),
            "bufferedMs" to safeGetBufferedMs(),
            "rateVerified" to (streaming && lastRateVerified),
            "advertisedFormats" to parsed.altSettingFormats.map { fmt ->
                mapOf(
                    "interfaceNumber" to fmt.interfaceNumber,
                    "altSetting" to fmt.altSetting,
                    "subslotSize" to fmt.subslotSize,
                    "bitResolution" to fmt.bitResolution,
                    "channels" to fmt.channels,
                    "supportedRates" to fmt.supportedRates,
                )
            },
            "volumeCalibrationOffsetDb" to getVolumeCalibrationOffset(device.vendorId, device.productId),
        )
    }

    private fun baseStatus(
        attached: Boolean,
        permitted: Boolean,
        device: UsbDevice?,
    ): Map<String, Any?> = mapOf(
        "attached" to attached,
        "permitted" to permitted,
        "deviceName" to (device?.let { deviceLabel(it) }),
        "deviceId" to device?.deviceId,
        "vendorId" to device?.vendorId,
        "productId" to device?.productId,
        "uacVersion" to UsbAudioControlParser.UAC_NONE,
        "uacLabel" to "none",
        "hasVolumeControl" to false,
        "exclusiveActive" to false,
        "exclusiveSupported" to false,
        "streamingActive" to false,
        "streamingSupported" to false,
        "streamingSampleRate" to 0,
        "streamingBitDepth" to 0,
        "rawPcmBitDepth" to 0,
        "streamingChannels" to 0,
        "hardwareVolumeDb" to null,
        "hardwareVolumeApplied" to false,
        "minVolumeDb" to null,
        "maxVolumeDb" to null,
        "interfaceNumber" to null,
        "supportedRates" to emptyList<Int>(),
        "lastError" to null,
        "resultCode" to null,
        "underrunCount" to 0L,
        "overrunCount" to 0L,
        "channelMismatchFrames" to 0L,
        "bufferedMs" to 0.0,
        "rateVerified" to false,
        "advertisedFormats" to emptyList<Map<String, Any?>>(),
        "volumeCalibrationOffsetDb" to (device?.let { getVolumeCalibrationOffset(it.vendorId, it.productId) } ?: 0.0),
    )

    private fun getVolumeCalibrationOffset(vendorId: Int, productId: Int): Double {
        val prefs = context.getSharedPreferences("pulsr_usb_vol_prefs", Context.MODE_PRIVATE)
        return prefs.getFloat("cal_${vendorId}_${productId}", 0.0f).toDouble()
    }

    private fun setVolumeCalibrationOffset(vendorId: Int, productId: Int, offsetDb: Double) {
        val prefs = context.getSharedPreferences("pulsr_usb_vol_prefs", Context.MODE_PRIVATE)
        prefs.edit().putFloat("cal_${vendorId}_${productId}", offsetDb.toFloat()).apply()
    }

    private fun deviceLabel(device: UsbDevice): String =
        listOfNotNull(device.manufacturerName, device.productName)
            .joinToString(" ").trim().ifEmpty { "USB Audio Device" }

    private fun uacLabel(version: Int): String = when (version) {
        UsbAudioControlParser.UAC1 -> "UAC1"
        UsbAudioControlParser.UAC2 -> "UAC2"
        UsbAudioControlParser.UAC3 -> "UAC3"
        else -> "none"
    }

    private fun emitState() {
        // buildStatus() issues blocking control transfers; run it on the worker
        // thread, cache the result, then push to the event sink on the main
        // thread. The cache always refreshes so getStatus can reply instantly.
        workerHandler.post {
            val status = try {
                buildStatus()
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to build USB state: ${e.message}")
                return@post
            }
            cachedStatus = status
            if (eventSink != null) {
                mainHandler.post {
                    val sink = eventSink ?: return@post
                    try {
                        sink.success(status)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to emit USB state: ${e.message}")
                    }
                }
            }
        }
    }

    // ---- permission ----

    private fun requestPermission(result: MethodChannel.Result) {
        val device = findAudioDevice()
        if (device == null) {
            result.success(false)
            return
        }
        if (usbManager?.hasPermission(device) == true) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("USB_PERMISSION_PENDING", "A permission request is already in flight", null)
            return
        }
        pendingPermissionResult = result
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action != ACTION_USB_PERMISSION) return
                // The boolean extra is spoofable/ambiguous on some OEM builds;
                // the permission grant state is the authoritative answer.
                val granted = usbManager?.hasPermission(device) == true
                finishPermission(granted)
            }
        }
        permissionReceiver = receiver
        try {
            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(ACTION_USB_PERMISSION),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register permission receiver: ${e.message}")
            finishPermission(false)
            return
        }
        // The intent is already explicit (setPackage below). Android 12+ needs
        // MUTABLE for UsbManager to attach the permission result to it.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        val pi = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION).setPackage(context.packageName),
            flags,
        )
        usbManager?.requestPermission(device, pi)
    }

    private fun finishPermission(granted: Boolean) {
        val r = pendingPermissionResult
        pendingPermissionResult = null
        permissionReceiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        permissionReceiver = null
        emitState()
        try { r?.success(granted) } catch (_: Exception) {}
    }

    // ---- exclusive claim ----

    private fun setExclusiveInternal(enabled: Boolean): Map<String, Any?> {
        val device = findAudioDevice() ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        if (!enabled) {
            releaseClaim()
            return buildStatus()
        }
        if (claimedInterface != null) return buildStatus()

        val conn = ensureConnection(device) ?: return failure("open_failed")
        val ifaceNumber = streamInterfaceNumber ?: return failure("no_streaming_interface")
        var iface: UsbInterface? = null
        for (i in 0 until device.interfaceCount) {
            val candidate = device.getInterface(i)
            if (candidate.id == ifaceNumber) {
                iface = candidate
                break
            }
        }
        iface ?: return failure("streaming_interface_not_found")

        // Non-forced claim: never detach Android's kernel audio driver.
        val claimed = try { conn.claimInterface(iface, false) } catch (_: Exception) { false }
        if (!claimed) {
            return failure("interface_busy")
        }
        claimedInterface = iface
        emitState()
        return buildStatus()
    }

    private fun releaseClaim() {
        val iface = claimedInterface ?: return
        try { connection?.releaseInterface(iface) } catch (_: Exception) {}
        claimedInterface = null
        emitState()
    }

    // ---- hardware volume ----

    private fun transport(conn: UsbDeviceConnection) = UsbControlTransfer { type, request, value, index, data ->
        conn.controlTransfer(type, request, value, index, data, data.size, CTRL_TIMEOUT_MS)
    }

    private fun setHardwareVolumeInternal(db: Double): Map<String, Any?> {
        hardwareVolume?.invalidate()
        val device = openedDevice ?: findAudioDevice() ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        ensureConnection(device) ?: return failure("open_failed")
        val volume = hardwareVolume ?: return failure("no_usable_volume_control")
        val offset = getVolumeCalibrationOffset(device.vendorId, device.productId)
        val ok = volume.setDb(db + offset)
        val status = buildStatus()
        emitState()
        return status + mapOf(
            "success" to (ok && volume.applied),
            "error" to if (ok && volume.applied) null else "volume_not_verified",
        )
    }

    private fun failure(reason: String): Map<String, Any?> =
        mapOf(
            "success" to false,
            "error" to reason,
            "exclusiveActive" to (claimedInterface != null),
            "deviceId" to openedDevice?.deviceId,
            "hasVolumeControl" to (hardwareVolume?.ready == true),
            "hardwareVolumeDb" to hardwareVolume?.currentDb,
            "hardwareVolumeApplied" to (hardwareVolume?.applied == true),
            "streamingActive" to (streaming && isNativeActive()),
            "streamingSampleRate" to (streamFormat?.sampleRate ?: 0),
            "streamingBitDepth" to (streamFormat?.wireBitDepth ?: 0),
            "rawPcmBitDepth" to safeRawPcmBitDepth(),
            "streamingChannels" to (streamFormat?.wireChannels ?: 0),
        )

    // ---- raw UAC2 isochronous streaming ----

    private fun startStreamingInternal(sampleRate: Int, channels: Int, bitDepth: Int = 16, strict: Boolean = false): Map<String, Any?> {
        if (streaming && streamFormat?.matches(sampleRate, bitDepth, channels, isNativeActive()) == true) {
            if (strict && !lastRateVerified) {
                lastStreamResultCode = 3
                Log.w(TAG, "Step clock: strict mode refused unverified readback on existing stream")
                return failure("uac1_rate_readback_unsupported")
            }
            val status = buildStatus()
            if (status["streamingActive"] == true) {
                lastStreamResultCode = 0
                // Update the cache and notify listeners so the event stream
                // reflects the current state even on the early-return path.
                cachedStatus = status
                emitState()
                return status + mapOf("success" to true, "resultCode" to 0)
            }
        }
        clearStreaming()
        if (!nativeLoaded) {
            lastStreamResultCode = -1
            Log.w(TAG, "Step native: native library not available")
            return failure("native_unavailable")
        }
        val device = findAudioDevice() ?: run {
            lastStreamResultCode = -1
            Log.w(TAG, "Step device: no USB audio device found")
            return failure("no_usb_device")
        }
        if (usbManager?.hasPermission(device) != true) {
            lastStreamResultCode = 1
            Log.w(TAG, "Step permission: USB access permission required")
            return failure("permission_required")
        }
        val conn = ensureConnection(device) ?: run {
            lastStreamResultCode = 1
            Log.w(TAG, "Step open: failed to open USB device connection")
            return failure("open_failed")
        }
        val parsed = parseViaRawDescriptors(conn) ?: run {
            lastStreamResultCode = 3
            Log.w(TAG, "Step descriptors: format descriptors required")
            return failure("format_descriptors_required")
        }
        if (parsed.uacVersion == UsbAudioControlParser.UAC3) {
            lastStreamResultCode = 3
            Log.w(TAG, "Step uac: UAC3 is not supported for bit-perfect streaming")
            return failure("uac3_unsupported")
        }
        val selected = UsbAudioProtocol.selectFormat(parsed, sampleRate, bitDepth, channels) ?: run {
            lastStreamResultCode = 3
            Log.w(TAG, "Step selectFormat: format unsupported: rate=$sampleRate, depth=$bitDepth, channels=$channels")
            return failure("format_unsupported")
        }
        val epAddress = selected.endpointAddress
        val epInterface = selected.interfaceNumber
        val epAlt = selected.altSetting
        val streamBytes = selected.subslotSize
        val wireChannels = selected.channels.takeIf { it > 0 } ?: channels

        var iface: UsbInterface? = null
        for (i in 0 until device.interfaceCount) {
            val c = device.getInterface(i)
            if (c.id == epInterface && c.alternateSetting == epAlt) {
                iface = c
                break
            }
        }
        iface ?: run {
            lastStreamResultCode = 5
            Log.w(TAG, "Step alt_setting: streaming interface not found (result 5)")
            return failure("streaming_interface_not_found")
        }

        releaseClaim()
        val claimed = try { conn.claimInterface(iface, true) } catch (_: Exception) { false }
        if (!claimed) {
            lastStreamResultCode = 1
            Log.w(TAG, "Step claim: failed to claim streaming interface (result 1)")
            rebindKernelDriver(conn, iface)
            return failure("claim_failed")
        }
        claimedStreamingInterface = iface
        claimControlInterface(conn, device, parsed)
        var started = false
        try {
            if (!conn.setInterface(iface)) {
                lastStreamResultCode = 2
                Log.w(TAG, "Step alt_setting: failed to set alternate setting (result 2)")
                return failure("alt_setting_failed")
            }
            val rateResult = setDacSampleRate(conn, parsed, selected, sampleRate)
            if (rateResult == UsbAudioProtocol.RateSetResult.FAILED) {
                lastStreamResultCode = 3
                Log.w(TAG, "Step clock: clock not verified (result 3)")
                return failure("clock_not_verified")
            }
            if (rateResult == UsbAudioProtocol.RateSetResult.UNVERIFIED_READBACK_UNSUPPORTED) {
                Log.i(TAG, "Step clock: UAC1 sample-rate set succeeded, readback unsupported")
                if (strict) {
                    lastStreamResultCode = 3
                    Log.w(TAG, "Step clock: strict mode refused unverified readback (result 3)")
                    return failure("uac1_rate_readback_unsupported")
                }
                lastRateVerified = false
            } else {
                lastRateVerified = true
            }
            val fd = conn.fileDescriptor
            if (fd < 0) {
                lastStreamResultCode = 5
                Log.w(TAG, "Step native_start: invalid file descriptor (result 5)")
                return failure("no_fd")
            }
            val resultCode = nativeUsbStreamStartWithFormat(
                fd, epAddress, epInterface, epAlt, sampleRate, wireChannels, streamBytes,
                selected.bitResolution,
            )
            lastStreamResultCode = resultCode
            if (resultCode != 0 || !isNativeActive()) {
                Log.w(TAG, "Step native_start: native start failed with result $resultCode")
                return failure("native_stream_not_active") + mapOf("resultCode" to resultCode)
            }
            // The request is remembered as the request (see StreamFormat): a
            // 16-bit track whose endpoint was opened at 24-bit must be
            // recognised as the same stream on the next track change.
            streamFormat = UsbAudioProtocol.StreamFormat(
                sampleRate, bitDepth, channels,
                wireBitDepth = selected.bitResolution, wireChannels = wireChannels,
            )
            streaming = true
            directStatus = DirectStreamStatus(device.deviceId, deviceLabel(device),
                sampleRate, selected.bitResolution, wireChannels)
            directOwner = this
            val status = buildStatus()
            started = status["streamingActive"] == true && isNativeActive()
            if (!started) return failure("native_stream_not_active")
            emitState()
            return status + mapOf("success" to true, "resultCode" to 0)
        } catch (e: Throwable) {
            Log.w(TAG, "USB streaming startup failed: ${e.message}")
            lastStreamResultCode = -1
            return failure("stream_start_failed")
        } finally {
            if (!started) clearStreaming()
        }
    }

    private fun setDacSampleRate(
        conn: UsbDeviceConnection,
        parsed: UsbAudioControlParser.Result,
        selected: UsbAudioControlParser.AltSettingFormat,
        sampleRate: Int,
    ): UsbAudioProtocol.RateSetResult {
        val clock = UsbAudioProtocol.resolveActiveClock(transport(conn), parsed)
        return UsbAudioProtocol.setSampleRateWithResult(
            transport(conn), parsed.uacVersion, clock, selected.endpointAddress,
            sampleRate, selected.supportedRates.size == 1,
        )
    }

    /**
     * Clock and volume requests address the Audio Control interface. usbfs
     * refuses interface-recipient requests (EBUSY) for an interface it neither
     * owns nor sees unbound, so while direct streaming owns the device this
     * claims it too. Best effort: a refusal is logged and the verification steps
     * (clock read-back, volume read-back) still report the real outcome.
     */
    private fun claimControlInterface(
        conn: UsbDeviceConnection,
        device: UsbDevice,
        parsed: UsbAudioControlParser.Result,
    ) {
        if (claimedControlInterface != null) return
        val acNumber = parsed.controlInterface.takeIf { it >= 0 }
            ?: parsed.clockSource?.controlInterface
            ?: parsed.volumeUnit?.interfaceNumber
            ?: return
        for (i in 0 until device.interfaceCount) {
            val candidate = device.getInterface(i)
            if (candidate.id != acNumber || candidate.alternateSetting != 0) continue
            val ok = try { conn.claimInterface(candidate, true) } catch (_: Exception) { false }
            if (ok) {
                claimedControlInterface = candidate
                hardwareVolume?.refresh()
            } else {
                Log.w(TAG, "Could not claim Audio Control interface $acNumber")
            }
            return
        }
    }

    private fun isNativeActive(): Boolean = nativeLoaded && try {
        nativeUsbStreamIsActive()
    } catch (_: Throwable) { false }

    private fun rebindKernelDriver(conn: UsbDeviceConnection, iface: UsbInterface) {
        val device = openedDevice
        if (device != null) {
            val idle = (0 until device.interfaceCount).map { device.getInterface(it) }
                .firstOrNull { it.id == iface.id && it.alternateSetting == 0 }
            if (idle != null) try { conn.setInterface(idle) } catch (_: Exception) {}
        }
        try { conn.releaseInterface(iface) } catch (_: Exception) {}
    }

    private fun clearStreaming() {
        directStatus = null
        if (directOwner === this) directOwner = null
        streaming = false
        streamFormat = null
        lastRateVerified = false
        if (nativeLoaded) try { nativeUsbStreamStop() } catch (_: Throwable) {}
        val iface = claimedStreamingInterface
        claimedStreamingInterface = null
        val control = claimedControlInterface
        claimedControlInterface = null
        val conn = connection
        if (iface != null && conn != null) rebindKernelDriver(conn, iface)
        if (control != null && conn != null) {
            try { conn.releaseInterface(control) } catch (_: Exception) {}
        }
    }

    private fun stopStreamingInternal(): Map<String, Any?> {
        clearStreaming()
        lastStreamResultCode = null
        emitState()
        return buildStatus() + mapOf("success" to true)
    }

    /**
     * Blocking: opens the device, issues a native rate query and parses the raw
     * descriptors. Always invoked on the worker thread via runAsync.
     */
    private fun querySupportedRatesInternal(): List<Int> {
        val device = openedDevice ?: findAudioDevice()
        if (device == null || usbManager?.hasPermission(device) != true) {
            return emptyList()
        }
        val conn = ensureConnection(device) ?: return emptyList()
        val fd = try { conn.fileDescriptor } catch (_: Exception) { -1 }
        val ifaceNum = streamInterfaceNumber ?: 1
        val nativeRates = if (nativeLoaded && fd >= 0) {
            try {
                nativeUsbQuerySupportedRates(fd, ifaceNum).toList()
            } catch (e: Throwable) {
                Log.w(TAG, "nativeUsbQuerySupportedRates failed: ${e.message}")
                emptyList<Int>()
            }
        } else {
            emptyList<Int>()
        }
        val parsed = parseViaRawDescriptors(conn)
        val descriptorRates = parsed?.supportedRates ?: emptyList<Int>()
        return (nativeRates + descriptorRates).distinct().sorted()
    }

    @Synchronized
    private fun closeLocked() {
        clearStreaming()
        directStreamingSupported = false
        releaseClaim()
        try { connection?.close() } catch (_: Exception) {}
        connection = null
        openedDevice = null
        volumeUnit = null
        uacVersion = UsbAudioControlParser.UAC_NONE
        streamInterfaceNumber = null
        parsedResult = null
        hardwareVolume?.invalidate()
        hardwareVolume = null
        cachedStatus = baseStatus(attached = false, permitted = false, device = null)
    }
}

