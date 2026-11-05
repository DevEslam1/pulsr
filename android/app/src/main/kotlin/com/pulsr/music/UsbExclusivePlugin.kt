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
 *    path UAPP/Poweramp use; it does not require claiming an interface.
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

    private var nativeLoaded = false
    @Volatile private var streaming = false
    @Volatile private var streamFormat: UsbAudioProtocol.StreamFormat? = null
    @Volatile private var directStatus: DirectStreamStatus? = null
    private var claimedStreamingInterface: UsbInterface? = null

    // Blocking USB control transfers, raw-descriptor parsing and native sink
    // start/stop/query must never run on the main thread (ANR). All such work
    // is serialized onto this single worker thread; MethodChannel replies are
    // posted back to the main thread. getStatus returns the last cached status
    // immediately and refreshes asynchronously.
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
        sampleRate: Int, channels: Int, bytesPerSample: Int,
    ): Int
    private external fun nativeUsbStreamStop()
    private external fun nativeUsbStreamIsActive(): Boolean
    private external fun nativeUsbStreamGetLastError(): Int
    private external fun nativeUsbStreamGetUnderrunCount(): Long
    private external fun nativeUsbStreamGetOverrunCount(): Long
    private external fun nativeUsbStreamGetBufferedMs(): Double
    private external fun nativeUsbQuerySupportedRates(fd: Int, interfaceNumber: Int): IntArray

    @Volatile private var lastStreamResultCode: Int? = null
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
                    runAsync(call.method, result) { startStreamingInternal(sampleRate, channels, bitDepth) }
                }
                "stopStreaming" -> runAsync(call.method, result) { stopStreamingInternal() }
                "isStreamingSupported" -> {
                    val device = openedDevice ?: findAudioDevice()
                    val supported = nativeLoaded && device != null &&
                        (0 until device.interfaceCount).any { i ->
                            device.getInterface(i).interfaceSubclass == 0x02
                        }
                    result.success(supported)
                }
                "getDiagnostics" -> {
                    val diag = mapOf(
                        "lastError" to if (nativeLoaded) nativeUsbStreamGetLastError() else 0,
                        "underrunCount" to if (nativeLoaded) nativeUsbStreamGetUnderrunCount() else 0L,
                        "overrunCount" to if (nativeLoaded) nativeUsbStreamGetOverrunCount() else 0L,
                        "isStreamActive" to if (nativeLoaded) nativeUsbStreamIsActive() else false,
                        "bufferedMs" to if (nativeLoaded) nativeUsbStreamGetBufferedMs() else 0.0
                    )
                    result.success(diag)
                }
                "getBufferedMs" -> {
                    result.success(if (nativeLoaded) nativeUsbStreamGetBufferedMs() else 0.0)
                }
                "setVolumeCalibrationOffset" -> {
                    val offsetDb = call.argument<Double>("offsetDb") ?: 0.0
                    val device = openedDevice ?: findAudioDevice()
                    if (device != null) {
                        setVolumeCalibrationOffset(device.vendorId, device.productId, offsetDb)
                        emitState()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "getVolumeCalibrationOffset" -> {
                    val device = openedDevice ?: findAudioDevice()
                    val offset = if (device != null) {
                        getVolumeCalibrationOffset(device.vendorId, device.productId)
                    } else 0.0
                    result.success(offset)
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
        try {
            permissionReceiver?.let {
                try { context.unregisterReceiver(it) } catch (_: Exception) {}
            }
            try { context.unregisterReceiver(deviceReceiver) } catch (_: Exception) {}
        } catch (_: Exception) {}
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
            usbManager?.deviceList?.values?.firstOrNull { device ->
                (0 until device.interfaceCount).any {
                    val cls = device.getInterface(it).interfaceClass
                    cls == UsbConstants.USB_CLASS_AUDIO || cls == 0xFF
                }
            }
        } catch (_: Throwable) {
            null
        }

    /** Interface-only fallback used before a device connection is available. */
    private fun parseViaInterfaces(device: UsbDevice): UsbAudioControlParser.Result {
        var streaming: Int? = null
        val pairs = ArrayList<Pair<Int, Int>>(device.interfaceCount)
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            pairs.add(Pair(iface.interfaceSubclass, iface.interfaceProtocol))
            if (streaming == null && iface.interfaceSubclass == 0x02) {
                streaming = iface.id
            }
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
        hardwareVolume?.refresh()
        return conn
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
        hardwareVolume?.refresh()
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
            "streamingBitDepth" to (streamFormat?.bitDepth ?: 0),
            "streamingChannels" to (streamFormat?.channels ?: 0),
            "hardwareVolumeDb" to hardwareVolume?.currentDb,
            "hardwareVolumeApplied" to (hardwareVolume?.applied == true),
            "minVolumeDb" to hardwareVolume?.minDb,
            "maxVolumeDb" to hardwareVolume?.maxDb,
            "interfaceNumber" to parsed.streamingInterface,
            "supportedRates" to parsed.supportedRates,
            "lastError" to if (nativeLoaded) nativeUsbStreamGetLastError() else 0,
            "resultCode" to lastStreamResultCode,
            "underrunCount" to if (nativeLoaded) nativeUsbStreamGetUnderrunCount() else 0L,
            "overrunCount" to if (nativeLoaded) nativeUsbStreamGetOverrunCount() else 0L,
            "bufferedMs" to if (nativeLoaded) nativeUsbStreamGetBufferedMs() else 0.0,
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
        "streamingChannels" to 0,
        "hardwareVolumeDb" to null,
        "hardwareVolumeApplied" to false,
        "minVolumeDb" to null,
        "maxVolumeDb" to null,
        "interfaceNumber" to null,
        "supportedRates" to emptyList<Int>(),
        "bufferedMs" to 0.0,
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
            "streamingBitDepth" to (streamFormat?.bitDepth ?: 0),
            "streamingChannels" to (streamFormat?.channels ?: 0),
        )

    // ---- raw UAC2 isochronous streaming ----

    private fun startStreamingInternal(sampleRate: Int, channels: Int, bitDepth: Int = 16): Map<String, Any?> {
        if (streaming && streamFormat?.matches(sampleRate, bitDepth, channels, isNativeActive()) == true) {
            val status = buildStatus()
            if (status["streamingActive"] == true) {
                lastStreamResultCode = 0
                return status + mapOf("success" to true, "resultCode" to 0)
            }
        }
        clearStreaming()
        if (bitDepth == 32) {
            lastStreamResultCode = 3
            return failure("source_32bit_float_conversion_not_lossless")
        }
        if (!nativeLoaded) {
            lastStreamResultCode = -1
            return failure("native_unavailable")
        }
        val device = findAudioDevice() ?: run {
            lastStreamResultCode = -1
            return failure("no_usb_device")
        }
        if (usbManager?.hasPermission(device) != true) {
            lastStreamResultCode = 1
            return failure("permission_required")
        }
        val conn = ensureConnection(device) ?: run {
            lastStreamResultCode = 1
            return failure("open_failed")
        }
        val parsed = parseViaRawDescriptors(conn) ?: return failure("format_descriptors_required")
        val selected = UsbAudioProtocol.selectFormat(parsed, sampleRate, bitDepth, channels) ?: run {
            lastStreamResultCode = 3
            return failure("format_unsupported")
        }
        val epAddress = selected.endpointAddress
        val epInterface = selected.interfaceNumber
        val epAlt = selected.altSetting
        val streamBytes = selected.subslotSize

        // Prefer the exact (interface, alternate setting) pair that exposes the
        // selected isochronous OUT endpoint.
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
            return failure("streaming_interface_not_found")
        }

        releaseClaim()
        val claimed = try { conn.claimInterface(iface, true) } catch (_: Exception) { false }
        if (!claimed) {
            lastStreamResultCode = 1
            rebindKernelDriver(conn, iface)
            return failure("claim_failed")
        }
        claimedStreamingInterface = iface
        var started = false
        try {
            if (!conn.setInterface(iface)) {
                lastStreamResultCode = 2
                return failure("alt_setting_failed")
            }
            if (!setDacSampleRate(conn, parsed, selected, sampleRate)) {
                lastStreamResultCode = 3
                return failure("clock_not_verified")
            }
            val fd = conn.fileDescriptor
            if (fd < 0) {
                lastStreamResultCode = 5
                return failure("no_fd")
            }
            val resultCode = nativeUsbStreamStartWithFormat(
                fd, epAddress, epInterface, epAlt, sampleRate, channels, streamBytes,
            )
            lastStreamResultCode = resultCode
            if (resultCode != 0 || !isNativeActive()) {
                return failure("native_stream_not_active") + mapOf("resultCode" to resultCode)
            }
            streamFormat = UsbAudioProtocol.StreamFormat(sampleRate, selected.bitResolution, selected.channels)
            streaming = true
            directStatus = DirectStreamStatus(device.deviceId, deviceLabel(device),
                sampleRate, selected.bitResolution, selected.channels)
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
    ): Boolean = UsbAudioProtocol.setSampleRate(
        transport(conn), parsed.uacVersion, parsed.clockSource, selected.endpointAddress,
        sampleRate, selected.supportedRates.size == 1,
    )

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
        if (nativeLoaded) try { nativeUsbStreamStop() } catch (_: Throwable) {}
        val iface = claimedStreamingInterface
        claimedStreamingInterface = null
        val conn = connection
        if (iface != null && conn != null) rebindKernelDriver(conn, iface)
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
