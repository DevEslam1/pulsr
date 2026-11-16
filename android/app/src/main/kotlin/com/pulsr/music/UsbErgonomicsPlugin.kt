package com.pulsr.music

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

private const val TAG = "UsbErgonomicsPlugin"

/** sysfs root that publishes the negotiated speed of every USB device. */
private const val SYS_USB_DEVICES = "/sys/bus/usb/devices"

/** Receiver declared in AndroidManifest and already used by the app widget. */
private const val MEDIA_BUTTON_RECEIVER = "androidx.media.session.MediaButtonReceiver"

/** UAC interface subclass that carries the isochronous audio endpoints. */
private const val AUDIO_SUBCLASS_STREAMING = 2

private const val MAX_SILENCE_MS = 2500
private const val MAX_BUFFER_MS = 500
private const val MIN_TRANSFER_BYTES = 512
private const val MAX_TRANSFER_BYTES = 65536

private const val MIN_REPORT_BYTES = 8
private const val TRANSFER_TIMEOUT_MS = 250
private const val FAILURE_BACKOFF_MS = 50L
private const val REPEAT_GUARD_MS = 120L

private const val PREF_VID = "vid"
private const val PREF_PID = "pid"
private const val PREF_SILENCE_MS = "silenceMs"
private const val PREF_FORCE_16 = "force16Bit"
private const val PREF_ALT_RESET = "altResetOnStop"
private const val PREF_HID_ENABLED = "hidEnabled"
private const val PREF_TRANSFER_BYTES = "transferSizeBytes"
private const val PREF_BUFFER_MS = "bufferMs"
private const val PREF_UPDATED_AT = "updatedAtMs"

/**
 * USB ergonomics plugin: remembers the per-device quirk profile where a native
 * audio path can read it, measures the USB bus speed, and optionally takes over
 * the DAC's HID consumer-control interface to turn its media buttons into the
 * same `ACTION_MEDIA_BUTTON` broadcasts the app's media session already handles.
 *
 * SCOPE (honest):
 *  - The profile is persisted to [PREFS_NAME] and is the process-level default a
 *    native audio path reads through [readPersistedQuirk]. It is *advice*: this
 *    plugin never opens the AudioStreaming interface for streaming and never
 *    writes PCM.
 *  - Bus speed comes from `/sys/bus/usb/devices/<dev>/speed`. Android's
 *    `UsbDevice` API does not publish it, so sysfs is the only source; some
 *    kernels and locked-down builds do not expose the file.
 *  - The HID claim force-detaches the kernel HID driver for that interface only
 *    (never the audio interface). While claimed, the DAC's media buttons reach
 *    this plugin instead of the generic HID input path.
 *  - Consumer report layouts differ per device. Reports are decoded both as an
 *    array of consumer usage ids and as a usage bitmap (see
 *    [UsbConsumerUsage.decode]); a DAC using report IDs or a vendor page will
 *    not decode until a matching layout exists.
 *
 * Device-unverified: it compiles against platform APIs this app already uses,
 * but no DAC has exercised it on hardware yet.
 */
class UsbErgonomicsPlugin private constructor(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    private val usbManager: UsbManager? =
        context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerThread = HandlerThread("UsbErgonomicsIo").apply { start() }
    private val workerHandler = Handler(workerThread.looper)
    private val hidLock = Any()
    private val lastBroadcastAtMs = java.util.concurrent.ConcurrentHashMap<Int, Long>()

    @Volatile private var hidThread: HandlerThread? = null
    @Volatile private var hidConnection: UsbDeviceConnection? = null
    @Volatile private var hidDevice: UsbDevice? = null
    @Volatile private var hidClaimed = false
    @Volatile private var consumerSeen = false
    @Volatile private var lastUsageName: String? = null
    @Volatile private var hidDetail: String? = null
    @Volatile private var hidStop = true
    @Volatile private var disposed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("disposed", "USB ergonomics plugin is disposed", null)
            return
        }
        when (call.method) {
            METHOD_APPLY -> handleApplyQuirks(call, result)
            METHOD_PROBE -> handleProbeBusSpeed(call, result)
            METHOD_HID -> result.success(hidStatusMap())
            METHOD_RESET_ALT -> handleResetAltSetting(call, result)
            else -> result.notImplemented()
        }
    }

    /** Stops the HID reader and the worker thread. Safe to call twice. */
    fun dispose() {
        disposed = true
        synchronized(hidLock) { stopHidLocked() }
        try {
            channel.setMethodCallHandler(null)
        } catch (e: Exception) {
            Log.w(TAG, "Detaching the method channel handler failed: ${e.message}")
        }
        try {
            workerThread.quitSafely()
        } catch (e: Exception) {
            Log.w(TAG, "Stopping the ergonomics worker failed: ${e.message}")
        }
    }

    // ---- applyQuirks ----

    private fun handleApplyQuirks(call: MethodCall, result: MethodChannel.Result) {
        val vid = call.argument<Int>(PREF_VID)
        val pid = call.argument<Int>(PREF_PID)
        val requestedTransfer = call.argument<Int>(PREF_TRANSFER_BYTES) ?: 0
        val quirk = QuirkConfig(
            vid = vid,
            pid = pid,
            silenceMs = boundedInt(call, PREF_SILENCE_MS, 0, MAX_SILENCE_MS),
            force16Bit = call.argument<Boolean>(PREF_FORCE_16) == true,
            altResetOnStop = call.argument<Boolean>(PREF_ALT_RESET) == true,
            hidEnabled = call.argument<Boolean>(PREF_HID_ENABLED) == true,
            transferSizeBytes = if (requestedTransfer == 0) {
                0
            } else {
                requestedTransfer.coerceIn(MIN_TRANSFER_BYTES, MAX_TRANSFER_BYTES)
            },
            bufferMs = boundedInt(call, PREF_BUFFER_MS, 0, MAX_BUFFER_MS),
        )
        UsbQuirkPrefs.persist(prefs, quirk)
        runAsync(result) {
            applyHid(quirk)
            mapOf<String, Any?>(
                "ok" to true,
                "persisted" to true,
                "hid" to hidStatusMap(),
            )
        }
    }

    // ---- probeBusSpeed ----

    private fun handleProbeBusSpeed(call: MethodCall, result: MethodChannel.Result) {
        val vid = call.argument<Int>(PREF_VID)
        val pid = call.argument<Int>(PREF_PID)
        runAsync(result) { UsbSysfs.busSpeedMbps(vid, pid) }
    }

    // ---- resetAltSetting ----

    private fun handleResetAltSetting(call: MethodCall, result: MethodChannel.Result) {
        val vid = call.argument<Int>(PREF_VID)
        val pid = call.argument<Int>(PREF_PID)
        runAsync(result) { usbResetAltSetting(usbManager, vid, pid) }
    }

    // ---- HID consumer control ----

    private fun applyHid(quirk: QuirkConfig) {
        synchronized(hidLock) {
            stopHidLocked()
            if (!quirk.hidEnabled) {
                hidDetail = "disabled"
                return
            }
            hidStop = false
            hidDetail = "starting"
            val thread = HandlerThread("UsbErgonomicsHid").apply { start() }
            hidThread = thread
            Handler(thread.looper).post { claimAndRead(quirk) }
        }
    }

    private fun stopHidLocked() {
        hidStop = true
        // Closing the connection is what unblocks a pending interrupt transfer.
        try {
            hidConnection?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Closing the HID connection failed: ${e.message}")
        }
        hidConnection = null
        hidDevice = null
        hidClaimed = false
        val thread = hidThread
        hidThread = null
        try {
            thread?.quitSafely()
        } catch (e: Exception) {
            Log.w(TAG, "Stopping the HID thread failed: ${e.message}")
        }
    }

    private fun markHidStopped(detail: String) {
        hidClaimed = false
        hidDetail = detail
    }

    private fun claimAndRead(quirk: QuirkConfig) {
        val device = UsbDeviceLookup.audioDevice(usbManager, quirk.vid, quirk.pid)
        if (device == null) {
            markHidStopped("no_audio_device")
            return
        }
        if (usbManager?.hasPermission(device) != true) {
            markHidStopped("permission_required")
            return
        }
        val hidInterface = UsbDeviceLookup.hidInterface(device)
        if (hidInterface == null) {
            markHidStopped("no_hid_interface")
            return
        }
        val endpoint = UsbDeviceLookup.interruptInput(hidInterface)
        if (endpoint == null) {
            markHidStopped("no_hid_input_endpoint")
            return
        }
        val connection = try {
            usbManager?.openDevice(device)
        } catch (e: Exception) {
            Log.w(
                TAG,
                "Opening the HID side of vid=${device.vendorId} pid=${device.productId} " +
                    "failed: ${e.message}",
            )
            null
        }
        if (connection == null) {
            markHidStopped("open_failed")
            return
        }
        val claimed = try {
            // Force-claim the HID interface only: the generic HID driver has to
            // let go for the reports to reach us, and this interface carries no
            // audio.
            connection.claimInterface(hidInterface, true)
        } catch (e: Exception) {
            Log.w(TAG, "Claiming HID interface ${hidInterface.id} failed: ${e.message}")
            false
        }
        if (!claimed) {
            try {
                connection.close()
            } catch (e: Exception) {
                Log.w(TAG, "Closing the unclaimed HID connection failed: ${e.message}")
            }
            markHidStopped("hid_interface_busy")
            return
        }
        hidConnection = connection
        hidDevice = device
        hidClaimed = true
        hidDetail = null
        lastUsageName = null
        try {
            readReports(connection, endpoint, device)
        } catch (e: Exception) {
            Log.w(TAG, "The HID report loop failed: ${e.message}")
            hidDetail = "read_failed"
        } finally {
            hidClaimed = false
            try {
                connection.releaseInterface(hidInterface)
            } catch (e: Exception) {
                Log.w(TAG, "Releasing the HID interface failed: ${e.message}")
            }
            try {
                connection.close()
            } catch (e: Exception) {
                Log.w(TAG, "Closing the HID connection failed: ${e.message}")
            }
            hidConnection = null
            hidDevice = null
        }
    }

    private fun readReports(
        connection: UsbDeviceConnection,
        endpoint: UsbEndpoint,
        device: UsbDevice,
    ) {
        val buffer = ByteArray(maxOf(endpoint.maxPacketSize, MIN_REPORT_BYTES))
        var previous = ByteArray(0)
        while (!hidStop) {
            if (usbManager?.deviceList?.containsValue(device) != true) {
                hidDetail = "device_detached"
                return
            }
            val read = try {
                connection.bulkTransfer(endpoint, buffer, buffer.size, TRANSFER_TIMEOUT_MS)
            } catch (e: Exception) {
                Log.w(TAG, "HID transfer failed: ${e.message}")
                -1
            }
            if (hidStop) return
            if (read <= 0) {
                try {
                    Thread.sleep(FAILURE_BACKOFF_MS)
                } catch (e: InterruptedException) {
                    Log.w(TAG, "HID backoff was interrupted: ${e.message}")
                    Thread.currentThread().interrupt()
                    return
                }
                continue
            }
            val report = buffer.copyOf(read)
            dispatchReport(report, previous)
            previous = report
        }
    }

    /**
     * Broadcasts the media key for every consumer usage that appeared in this
     * report and was not in the previous one.
     */
    private fun dispatchReport(report: ByteArray, previous: ByteArray) {
        val pressed = UsbConsumerUsage.decode(report)
        if (pressed.isEmpty()) return
        val before = UsbConsumerUsage.decode(previous)
        for (usage in pressed) {
            if (before.contains(usage)) continue
            val keyCode = UsbConsumerUsage.keyCodeFor(usage) ?: continue
            val now = SystemClock.elapsedRealtime()
            val last = lastBroadcastAtMs[keyCode] ?: 0L
            if (now - last < REPEAT_GUARD_MS) continue
            lastBroadcastAtMs[keyCode] = now
            consumerSeen = true
            lastUsageName = UsbConsumerUsage.nameOf(usage)
            broadcastMediaButton(keyCode)
        }
    }

    /**
     * Sends ACTION_MEDIA_BUTTON to the same receiver the widgets use, so the
     * existing audio-service session handles a DAC button exactly like a headset
     * button.
     */
    private fun broadcastMediaButton(keyCode: Int) {
        try {
            val down = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(context, MEDIA_BUTTON_RECEIVER))
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            context.sendBroadcast(down)
            val up = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(context, MEDIA_BUTTON_RECEIVER))
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
            }
            context.sendBroadcast(up)
        } catch (e: Exception) {
            Log.w(TAG, "Broadcasting media key $keyCode failed: ${e.message}")
        }
    }

    private fun hidStatusMap(): Map<String, Any?> = mapOf(
        "claimed" to hidClaimed,
        "consumerControl" to consumerSeen,
        "lastButton" to lastUsageName,
        "detail" to hidDetail,
    )

    // ---- plumbing ----

    private fun boundedInt(call: MethodCall, key: String, min: Int, max: Int): Int {
        val value = call.argument<Int>(key) ?: min
        return value.coerceIn(min, max)
    }

    /** Runs [block] on the IO worker and replies on the main thread. */
    private fun runAsync(result: MethodChannel.Result, block: () -> Map<String, Any?>) {
        workerHandler.post {
            val payload = try {
                block()
            } catch (e: Exception) {
                Log.w(TAG, "A USB ergonomics worker step failed: ${e.message}")
                mapOf<String, Any?>("error" to (e.message ?: "worker_failed"))
            }
            mainHandler.post { result.success(payload) }
        }
    }

    companion object {
        /** Method channel name handled by this plugin. */
        const val METHOD_CHANNEL = "com.pulsr.music/usb_ergonomics"

        /**
         * SharedPreferences file that holds the process-level quirk. A native
         * audio path reads the same keys through [readPersistedQuirk].
         */
        const val PREFS_NAME = "pulsr_usb_ergonomics"

        private const val METHOD_APPLY = "applyQuirks"
        private const val METHOD_PROBE = "probeBusSpeed"
        private const val METHOD_HID = "getHidStatus"
        private const val METHOD_RESET_ALT = "resetAltSetting"

        /**
         * Registers the plugin on [engine]. Engine-scoped, matching the other
         * USB/audio plugins: the caller keeps the instance for cleanup.
         */
        @JvmStatic
        fun register(engine: FlutterEngine, context: Context): UsbErgonomicsPlugin {
            val appContext = context.applicationContext ?: context
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            val plugin = UsbErgonomicsPlugin(appContext, channel)
            channel.setMethodCallHandler(plugin)
            return plugin
        }

        /**
         * Reads the last applied quirk without instantiating the plugin, for the
         * native audio path. Returns -1 for an unknown device id, and null when
         * nothing has ever been applied.
         */
        @JvmStatic
        fun readPersistedQuirk(context: Context): Map<String, Any?>? =
            UsbQuirkPrefs.read(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE))
    }
}

/** Validated quirk values as understood by this plugin. */
private data class QuirkConfig(
    val vid: Int?,
    val pid: Int?,
    val silenceMs: Int,
    val force16Bit: Boolean,
    val altResetOnStop: Boolean,
    val hidEnabled: Boolean,
    val transferSizeBytes: Int,
    val bufferMs: Int,
)

/**
 * Writes and reads the quirk document in [UsbErgonomicsPlugin.PREFS_NAME].
 *
 * The keys are the contract a native audio path depends on: `vid`, `pid`,
 * `silenceMs`, `force16Bit`, `altResetOnStop`, `hidEnabled`,
 * `transferSizeBytes`, `bufferMs`, plus `updatedAtMs` as the "written at least
 * once" stamp. Writes use `apply()` so a channel call never blocks on disk.
 */
private object UsbQuirkPrefs {

    fun persist(prefs: SharedPreferences, quirk: QuirkConfig) {
        try {
            prefs.edit()
                .putInt(PREF_VID, quirk.vid ?: -1)
                .putInt(PREF_PID, quirk.pid ?: -1)
                .putInt(PREF_SILENCE_MS, quirk.silenceMs)
                .putBoolean(PREF_FORCE_16, quirk.force16Bit)
                .putBoolean(PREF_ALT_RESET, quirk.altResetOnStop)
                .putBoolean(PREF_HID_ENABLED, quirk.hidEnabled)
                .putInt(PREF_TRANSFER_BYTES, quirk.transferSizeBytes)
                .putInt(PREF_BUFFER_MS, quirk.bufferMs)
                .putLong(PREF_UPDATED_AT, System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            Log.w(
                TAG,
                "Persisting the quirk for vid=${quirk.vid} pid=${quirk.pid} failed: ${e.message}",
            )
        }
    }

    fun read(prefs: SharedPreferences): Map<String, Any?>? {
        if (!prefs.contains(PREF_UPDATED_AT)) return null
        return mapOf(
            PREF_VID to prefs.getInt(PREF_VID, -1),
            PREF_PID to prefs.getInt(PREF_PID, -1),
            PREF_SILENCE_MS to prefs.getInt(PREF_SILENCE_MS, 0),
            PREF_FORCE_16 to prefs.getBoolean(PREF_FORCE_16, false),
            PREF_ALT_RESET to prefs.getBoolean(PREF_ALT_RESET, false),
            PREF_HID_ENABLED to prefs.getBoolean(PREF_HID_ENABLED, false),
            PREF_TRANSFER_BYTES to prefs.getInt(PREF_TRANSFER_BYTES, 0),
            PREF_BUFFER_MS to prefs.getInt(PREF_BUFFER_MS, 0),
            PREF_UPDATED_AT to prefs.getLong(PREF_UPDATED_AT, 0L),
        )
    }
}

/**
 * Reads the negotiated link speed for one device from sysfs.
 *
 * Best effort by design: a missing file, an unreadable directory or a kernel
 * that does not publish `speed` all report "not published" instead of failing
 * the channel call. Every IO failure is logged once.
 */
private object UsbSysfs {

    fun busSpeedMbps(vid: Int?, pid: Int?): Map<String, Any?> {
        val entries = try {
            File(SYS_USB_DEVICES).listFiles()
        } catch (e: IOException) {
            Log.w(TAG, "Listing $SYS_USB_DEVICES failed: ${e.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "Listing $SYS_USB_DEVICES was denied: ${e.message}")
            null
        }
        if (entries == null) {
            return mapOf("mbps" to null, "detail" to "sysfs_not_readable")
        }
        for (entry in entries) {
            if (!entry.isDirectory) continue
            val deviceVid = readHex(File(entry, "idVendor")) ?: continue
            val devicePid = readHex(File(entry, "idProduct")) ?: continue
            if (vid != null && deviceVid != vid) continue
            if (pid != null && devicePid != pid) continue
            val speed = readDouble(File(entry, "speed")) ?: continue
            return mapOf("mbps" to speed)
        }
        return mapOf("mbps" to null, "detail" to "speed_not_published")
    }

    private fun readHex(file: File): Int? {
        val text = readTextFile(file) ?: return null
        return try {
            text.trim().toInt(16)
        } catch (e: NumberFormatException) {
            Log.w(TAG, "Reading ${file.name} produced an unexpected value: ${e.message}")
            null
        }
    }

    private fun readDouble(file: File): Double? {
        val text = readTextFile(file) ?: return null
        return try {
            text.trim().toDouble()
        } catch (e: NumberFormatException) {
            Log.w(TAG, "Reading ${file.name} produced an unexpected value: ${e.message}")
            null
        }
    }

    private fun readTextFile(file: File): String? {
        return try {
            if (!file.isFile) null else file.readText()
        } catch (e: IOException) {
            Log.w(TAG, "Reading ${file.name} failed: ${e.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "Reading ${file.name} was denied: ${e.message}")
            null
        }
    }
}

/** Finds the attached USB audio device and its HID consumer interface. */
private object UsbDeviceLookup {

    fun audioDevice(usbManager: UsbManager?, vid: Int?, pid: Int?): UsbDevice? {
        val devices = usbManager?.deviceList ?: return null
        for (device in devices.values) {
            if (vid != null && device.vendorId != vid) continue
            if (pid != null && device.productId != pid) continue
            if (hasAudioInterface(device)) return device
        }
        return null
    }

    fun hidInterface(device: UsbDevice): UsbInterface? {
        for (index in 0 until device.interfaceCount) {
            val iface = device.getInterface(index)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_HID) return iface
        }
        return null
    }

    fun interruptInput(iface: UsbInterface): UsbEndpoint? {
        for (index in 0 until iface.endpointCount) {
            val endpoint = iface.getEndpoint(index)
            if (endpoint.direction == UsbConstants.USB_DIR_IN &&
                endpoint.type == UsbConstants.USB_ENDPOINT_XFER_INT
            ) {
                return endpoint
            }
        }
        return null
    }

    private fun hasAudioInterface(device: UsbDevice): Boolean {
        for (index in 0 until device.interfaceCount) {
            if (device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_AUDIO) {
                return true
            }
        }
        return false
    }
}

/**
 * Consumer-page (0x0C) usage decoding for one HID report.
 *
 * Two layouts are covered because cheap DACs use both: an array report whose
 * bytes are usage ids, and a bitmap report where bit n of byte i stands for
 * usage `i * 8 + n`. A report that matches neither yields no usages.
 */
private object UsbConsumerUsage {

    fun keyCodeFor(usage: Int): Int? = KEY_CODES[usage]

    fun nameOf(usage: Int): String = USAGE_NAMES[usage] ?: "usage_0x${usage.toString(16)}"

    fun decode(report: ByteArray): Set<Int> {
        val usages = HashSet<Int>()
        for (index in report.indices) {
            val value = report[index].toInt() and 0xFF
            if (value == 0) continue
            if (KEY_CODES.containsKey(value)) usages.add(value)
            for (bit in 0 until 8) {
                if (value and (1 shl bit) != 0) {
                    val usage = index * 8 + bit
                    if (KEY_CODES.containsKey(usage)) usages.add(usage)
                }
            }
        }
        return usages
    }

    private val KEY_CODES: Map<Int, Int> = mapOf(
        0xCD to KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
        0xB5 to KeyEvent.KEYCODE_MEDIA_NEXT,
        0xB6 to KeyEvent.KEYCODE_MEDIA_PREVIOUS,
        0xE9 to KeyEvent.KEYCODE_VOLUME_UP,
        0xEA to KeyEvent.KEYCODE_VOLUME_DOWN,
    )

    private val USAGE_NAMES: Map<Int, String> = mapOf(
        0xCD to "play_pause",
        0xB5 to "next",
        0xB6 to "previous",
        0xE9 to "volume_up",
        0xEA to "volume_down",
    )
}

/**
 * Returns the AudioStreaming interface to alternate setting 0.
 *
 * The interface is claimed *without* forcing, so a live kernel driver (the normal
 * case while audio plays) is left alone and the attempt reports failure instead
 * of detaching it and silencing the DAC.
 */
private fun usbResetAltSetting(
    usbManager: UsbManager?,
    vid: Int?,
    pid: Int?,
): Map<String, Any?> {
    val manager = usbManager ?: return mapOf("ok" to false, "detail" to "usb_unavailable")
    val device = UsbDeviceLookup.audioDevice(manager, vid, pid)
        ?: return mapOf("ok" to false, "detail" to "no_audio_device")
    if (!manager.hasPermission(device)) {
        return mapOf("ok" to false, "detail" to "permission_required")
    }
    val connection = try {
        manager.openDevice(device)
    } catch (e: Exception) {
        Log.w(TAG, "Opening vid=${device.vendorId} pid=${device.productId} failed: ${e.message}")
        null
    }
    if (connection == null) {
        return mapOf("ok" to false, "detail" to "open_failed")
    }
    var applied = 0
    var busy = 0
    try {
        for (index in 0 until device.interfaceCount) {
            val iface = device.getInterface(index)
            if (iface.interfaceClass != UsbConstants.USB_CLASS_AUDIO) continue
            if (iface.interfaceSubclass != AUDIO_SUBCLASS_STREAMING) continue
            if (iface.alternateSetting != 0) continue
            val claimed = try {
                connection.claimInterface(iface, false)
            } catch (e: Exception) {
                Log.w(TAG, "Claiming audio interface ${iface.id} failed: ${e.message}")
                false
            }
            if (!claimed) {
                busy++
                continue
            }
            val ok = try {
                connection.setInterface(iface)
            } catch (e: Exception) {
                Log.w(TAG, "Resetting interface ${iface.id} failed: ${e.message}")
                false
            }
            try {
                connection.releaseInterface(iface)
            } catch (e: Exception) {
                Log.w(TAG, "Releasing interface ${iface.id} failed: ${e.message}")
            }
            if (ok) applied++
        }
    } finally {
        try {
            connection.close()
        } catch (e: Exception) {
            Log.w(TAG, "Closing the reset connection failed: ${e.message}")
        }
    }
    return when {
        applied > 0 -> mapOf("ok" to true, "detail" to "alt_zero_applied")
        busy > 0 -> mapOf("ok" to false, "detail" to "interface_busy")
        else -> mapOf("ok" to false, "detail" to "no_streaming_interface")
    }
}
