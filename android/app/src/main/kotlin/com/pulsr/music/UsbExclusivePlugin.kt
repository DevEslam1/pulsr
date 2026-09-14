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
 *  - Raw isochronous UAC2 streaming (true bit-perfect DSD512) is NOT
 *    implemented; playback still goes through Android's audio HAL.
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

        // UAC class-specific request codes / audio control selectors.
        private const val REQ_SET_CUR = 0x01
        private const val REQ_GET_CUR = 0x81
        private const val REQ_GET_MIN = 0x82
        private const val REQ_GET_MAX = 0x83
        private const val REQ_GET_RES = 0x84
        private const val SELECTOR_VOLUME = 0x02
        private const val BM_GET = 0xA1 // device-to-host, class, interface
        private const val BM_SET = 0x21 // host-to-device, class, interface
        private const val CTRL_TIMEOUT_MS = 1000
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    private var eventSink: EventChannel.EventSink? = null
    private var connection: UsbDeviceConnection? = null
    private var openedDevice: UsbDevice? = null
    private var volumeUnit: UsbAudioControlParser.FeatureUnitVolume? = null
    private var claimedInterface: UsbInterface? = null
    private var uacVersion: Int = UsbAudioControlParser.UAC_NONE
    private var streamInterfaceNumber: Int? = null

    private var minRaw: Int? = null
    private var maxRaw: Int? = null
    private var resRaw: Int? = null

    private var nativeLoaded = false
    private var streaming = false
    private var claimedStreamingInterface: UsbInterface? = null

    // Raw UAC2 isochronous streaming, implemented in UsbAudioSink.cpp.
    private external fun nativeUsbStreamStart(
        fd: Int, endpoint: Int, interfaceNumber: Int, altSetting: Int,
        sampleRate: Int, channels: Int,
    ): Boolean
    private external fun nativeUsbStreamStop()
    private external fun nativeUsbStreamIsActive(): Boolean

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
                    if (detached == null || detached.deviceId == openedDevice?.deviceId) {
                        closeLocked()
                    }
                    emitState()
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
                "getStatus" -> result.success(buildStatus())
                "requestPermission" -> requestPermission(result)
                "setExclusive" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(setExclusiveInternal(enabled))
                }
                "setHardwareVolume" -> {
                    val db = call.argument<Double>("db") ?: 0.0
                    result.success(setHardwareVolumeInternal(db))
                }
                "startStreaming" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val channels = call.argument<Int>("channels") ?: 2
                    result.success(startStreamingInternal(sampleRate, channels))
                }
                "stopStreaming" -> result.success(stopStreamingInternal())
                "isStreamingSupported" -> {
                    val device = openedDevice ?: findAudioDevice()
                    val supported = nativeLoaded && device != null &&
                        (0 until device.interfaceCount).any { i ->
                            device.getInterface(i).interfaceSubclass == 0x02
                        }
                    result.success(supported)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MethodChannel error handling ${call.method}: ${e.message}", e)
            result.error("USB_EXCLUSIVE_ERROR", e.message, null)
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
        closeLocked()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
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
        uacVersion = parsed.uacVersion
        streamInterfaceNumber = parsed.streamingInterface
        volumeUnit = parsed.volumeUnit
    }

    private fun ensureConnection(device: UsbDevice): UsbDeviceConnection? {
        connection?.let { return it }
        val conn = try { usbManager?.openDevice(device) } catch (_: Exception) { null }
            ?: return null
        connection = conn
        openedDevice = device
        val parsed = parseViaRawDescriptors(conn) ?: parseViaInterfaces(device)
        applyParsed(parsed)
        refreshVolumeRange()
        return conn
    }

    private fun buildStatus(): Map<String, Any?> {
        val device = openedDevice ?: findAudioDevice()
        if (device == null) {
            return baseStatus(attached = false, permitted = false, device = null)
        }
        val permitted = usbManager?.hasPermission(device) == true
        val parsed: UsbAudioControlParser.Result = if (permitted) {
            val conn = ensureConnection(device)
            if (conn != null) {
                UsbAudioControlParser.Result(uacVersion, volumeUnit, streamInterfaceNumber)
            } else {
                parseViaInterfaces(device).also { applyParsed(it) }
            }
        } else {
            parseViaInterfaces(device).also { applyParsed(it) }
        }
        val hasVolume = parsed.volumeUnit != null &&
            (parsed.uacVersion == UsbAudioControlParser.UAC1 ||
                parsed.uacVersion == UsbAudioControlParser.UAC2)
        return mapOf(
            "attached" to true,
            "permitted" to permitted,
            "deviceName" to deviceLabel(device),
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "uacVersion" to parsed.uacVersion,
            "uacLabel" to uacLabel(parsed.uacVersion),
            "hasVolumeControl" to hasVolume,
            "exclusiveActive" to (claimedInterface != null),
            "exclusiveSupported" to hasVolume,
            "streamingActive" to streaming,
            "streamingSupported" to (nativeLoaded && parsed.streamingEndpoint != null),
            "hardwareVolumeDb" to currentVolumeDb(),
            "minVolumeDb" to (minRaw?.let { rawToDb(it) }),
            "maxVolumeDb" to (maxRaw?.let { rawToDb(it) }),
            "interfaceNumber" to parsed.streamingInterface,
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
        "vendorId" to device?.vendorId,
        "productId" to device?.productId,
        "uacVersion" to UsbAudioControlParser.UAC_NONE,
        "uacLabel" to "none",
        "hasVolumeControl" to false,
        "exclusiveActive" to false,
        "exclusiveSupported" to false,
        "streamingActive" to false,
        "streamingSupported" to false,
        "hardwareVolumeDb" to null,
        "minVolumeDb" to null,
        "maxVolumeDb" to null,
        "interfaceNumber" to null,
    )

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
        val sink = eventSink ?: return
        try {
            sink.success(buildStatus())
        } catch (e: Exception) {
            Log.w(TAG, "Failed to emit USB state: ${e.message}")
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
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
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
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_IMMUTABLE else 0)
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

    private fun setHardwareVolumeInternal(db: Double): Map<String, Any?> {
        val device = openedDevice ?: findAudioDevice()
            ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        val conn = ensureConnection(device) ?: return failure("open_failed")
        val unit = volumeUnit ?: return failure("no_volume_control")
        if (uacVersion != UsbAudioControlParser.UAC1 &&
            uacVersion != UsbAudioControlParser.UAC2
        ) {
            return failure("unsupported_uac")
        }
        refreshVolumeRange()
        val target = db.coerceIn(minDb(), maxDb())
        val raw = dbToRaw(target)
        val bytes = rawToBytes(raw)
        val ok = transfer(conn, BM_SET, REQ_SET_CUR, unit, 0, bytes)
        if (!ok) return failure("control_transfer_failed")
        emitState()
        return buildStatus()
    }

    private fun currentVolumeDb(): Double? {
        val conn = connection ?: return null
        val unit = volumeUnit ?: return null
        val buf = ByteArray(volumeSize())
        val ok = transfer(conn, BM_GET, REQ_GET_CUR, unit, 0, buf)
        if (!ok) return null
        return rawToDb(bytesToRaw(buf))
    }

    private fun refreshVolumeRange() {
        val conn = connection ?: return
        val unit = volumeUnit ?: return
        minRaw = readRaw(conn, unit, REQ_GET_MIN)
        maxRaw = readRaw(conn, unit, REQ_GET_MAX)
        resRaw = readRaw(conn, unit, REQ_GET_RES)
    }

    private fun readRaw(
        conn: UsbDeviceConnection,
        unit: UsbAudioControlParser.FeatureUnitVolume,
        request: Int,
    ): Int? {
        val buf = ByteArray(volumeSize())
        val ok = transfer(conn, BM_GET, request, unit, 0, buf)
        return if (ok) bytesToRaw(buf) else null
    }

    /** UAC2 volume is a 16.16 fixed-point 32-bit value; UAC1 is 16-bit. */
    private fun volumeSize(): Int =
        if (uacVersion == UsbAudioControlParser.UAC2) 4 else 2

    /** Issues a class-specific control transfer against a Feature Unit. */
    private fun transfer(
        conn: UsbDeviceConnection,
        requestType: Int,
        request: Int,
        unit: UsbAudioControlParser.FeatureUnitVolume,
        channel: Int,
        buffer: ByteArray,
    ): Boolean {
        return try {
            val wValue = (SELECTOR_VOLUME shl 8) or (channel and 0xFF)
            val wIndex = (unit.unitId shl 8) or (unit.interfaceNumber and 0xFF)
            val sent = conn.controlTransfer(
                requestType,
                request,
                wValue,
                wIndex,
                buffer,
                buffer.size,
                CTRL_TIMEOUT_MS,
            )
            sent >= 0
        } catch (e: Exception) {
            Log.w(TAG, "Control transfer failed: ${e.message}")
            false
        }
    }

    private fun minDb(): Double = minRaw?.let { rawToDb(it) } ?: -60.0
    private fun maxDb(): Double = maxRaw?.let { rawToDb(it) } ?: 0.0

    /** UAC1 stores 1/256 dB signed 16-bit; UAC2 uses 16.16 fixed-point dB. */
    private fun rawToDb(raw: Int): Double = when (uacVersion) {
        UsbAudioControlParser.UAC2 -> raw / 65536.0
        else -> raw / 256.0
    }

    private fun dbToRaw(db: Double): Int = when (uacVersion) {
        UsbAudioControlParser.UAC2 -> (db * 65536.0).toInt()
        else -> (db * 256.0).toInt()
    }

    private fun bytesToRaw(buf: ByteArray): Int {
        return if (uacVersion == UsbAudioControlParser.UAC2 && buf.size >= 4) {
            (buf[0].toInt() and 0xFF) or
                ((buf[1].toInt() and 0xFF) shl 8) or
                ((buf[2].toInt() and 0xFF) shl 16) or
                ((buf[3].toInt() and 0xFF) shl 24)
        } else {
            val u16 = (buf[0].toInt() and 0xFF) or ((buf[1].toInt() and 0xFF) shl 8)
            if (u16 and 0x8000 != 0) u16 - 0x10000 else u16
        }
    }

    private fun rawToBytes(raw: Int): ByteArray =
        if (uacVersion == UsbAudioControlParser.UAC2) {
            byteArrayOf(
                (raw and 0xFF).toByte(),
                ((raw shr 8) and 0xFF).toByte(),
                ((raw shr 16) and 0xFF).toByte(),
                ((raw shr 24) and 0xFF).toByte(),
            )
        } else {
            byteArrayOf(
                (raw and 0xFF).toByte(),
                ((raw shr 8) and 0xFF).toByte(),
            )
        }

    private fun failure(reason: String): Map<String, Any?> =
        mapOf(
            "success" to false,
            "error" to reason,
            "exclusiveActive" to (claimedInterface != null),
        )

    // ---- raw UAC2 isochronous streaming ----

    private fun startStreamingInternal(sampleRate: Int, channels: Int): Map<String, Any?> {
        if (streaming) return buildStatus() + mapOf("success" to true)
        if (!nativeLoaded) return failure("native_unavailable")
        val device = findAudioDevice() ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        val conn = ensureConnection(device) ?: return failure("open_failed")
        val parsed = parseViaRawDescriptors(conn) ?: parseViaInterfaces(device)
        val ep = parsed.streamingEndpoint
            ?: return failure("no_iso_out_endpoint")
        if (ep.interfaceNumber < 0) return failure("no_streaming_interface")

        // Prefer the exact (interface, alternate setting) pair that exposes the
        // isochronous OUT endpoint.
        var iface: UsbInterface? = null
        for (i in 0 until device.interfaceCount) {
            val c = device.getInterface(i)
            if (c.id == ep.interfaceNumber && c.alternateSetting == ep.altSetting) {
                iface = c
                break
            }
        }
        if (iface == null) {
            for (i in 0 until device.interfaceCount) {
                val c = device.getInterface(i)
                if (c.id == ep.interfaceNumber) {
                    iface = c
                    break
                }
            }
        }
        iface ?: return failure("streaming_interface_not_found")

        // Force-claim detaches Android's kernel audio driver from this
        // interface so the exclusive endpoint is ours.
        val claimed = try { conn.claimInterface(iface, true) } catch (_: Exception) { false }
        if (!claimed) return failure("claim_failed")
        try { conn.setInterface(iface) } catch (_: Exception) {}

        val fd = try { conn.fileDescriptor } catch (_: Exception) { -1 }
        if (fd < 0) {
            try { conn.releaseInterface(iface) } catch (_: Exception) {}
            return failure("no_fd")
        }
        val ok = try {
            nativeUsbStreamStart(
                fd, ep.address, ep.interfaceNumber, ep.altSetting,
                sampleRate, channels,
            )
        } catch (e: Exception) {
            Log.w(TAG, "nativeUsbStreamStart failed: ${e.message}")
            false
        }
        if (!ok) {
            try { conn.releaseInterface(iface) } catch (_: Exception) {}
            return failure("native_start_failed")
        }
        streaming = true
        claimedStreamingInterface = iface
        emitState()
        return buildStatus() + mapOf("success" to true)
    }

    private fun stopStreamingInternal(): Map<String, Any?> {
        if (nativeLoaded) {
            try { nativeUsbStreamStop() } catch (_: Exception) {}
        }
        streaming = false
        val iface = claimedStreamingInterface
        if (iface != null) {
            try { connection?.releaseInterface(iface) } catch (_: Exception) {}
        }
        claimedStreamingInterface = null
        emitState()
        return buildStatus() + mapOf("success" to true)
    }

    private fun closeLocked() {
        if (streaming) {
            if (nativeLoaded) {
                try { nativeUsbStreamStop() } catch (_: Exception) {}
            }
            streaming = false
            claimedStreamingInterface = null
        }
        releaseClaim()
        try { connection?.close() } catch (_: Exception) {}
        connection = null
        openedDevice = null
        volumeUnit = null
        uacVersion = UsbAudioControlParser.UAC_NONE
        streamInterfaceNumber = null
        minRaw = null
        maxRaw = null
        resRaw = null
    }
}
