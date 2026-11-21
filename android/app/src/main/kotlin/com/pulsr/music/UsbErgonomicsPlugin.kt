package com.pulsr.music

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbRequest
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
import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val TAG = "UsbErgonomicsPlugin"

/** sysfs root that publishes the negotiated speed of every USB device. */
private const val SYS_USB_DEVICES = "/sys/bus/usb/devices"

/** Receiver declared in AndroidManifest and already used by the app widget. */
private const val MEDIA_BUTTON_RECEIVER = "androidx.media.session.MediaButtonReceiver"

/** UAC interface subclass that carries the isochronous audio endpoints. */
private const val AUDIO_SUBCLASS_STREAMING = 2

private const val MIN_REPORT_BYTES = 8
// Item 5: UsbRequest.requestWait() has no timeout parameter (it returns when the
// request completes, is cancelled, or the device goes away), so the old 250 ms
// bulkTransfer timeout is gone. The wait is now event-driven instead of a 4 Hz
// poll, and the failure backoff below still applies to every failed queue/wait.
private const val FAILURE_BACKOFF_MS = 50L
private const val REPEAT_GUARD_MS = 120L

private const val ARG_VID = "vid"
private const val ARG_PID = "pid"
private const val ARG_DEVICE_ID = "deviceId"
private const val ARG_HID_ENABLED = "hidEnabled"

/**
 * USB ergonomics plugin: measures the USB bus speed, returns the device to
 * alternate setting 0, and optionally takes over the DAC's HID
 * consumer-control interface to turn its media buttons into the same
 * `ACTION_MEDIA_BUTTON` broadcasts the app's media session already handles.
 *
 * SCOPE (honest):
 *  - Only knobs with a real consumer are exposed: the HID consumer-control
 *    claim. The former silence/buffer/transfer-size/16-bit/alt-reset-on-stop
 *    values were persisted but no audio path ever read them, so they were
 *    removed instead of staying write-only.
 *  - Bus speed comes from `/sys/bus/usb/devices/<dev>/speed`, resolved through
 *    the selected [UsbDevice]'s bus/dev address. Android's `UsbDevice` API does
 *    not publish the speed, so sysfs is the only source; some kernels and
 *    locked-down builds do not expose the file, in which case the probe reports
 *    "unknown" instead of borrowing another device's speed.
 *  - The HID claim force-detaches the kernel HID driver for that interface only
 *    (never the audio interface). While claimed, the DAC's media buttons reach
 *    this plugin instead of the generic HID input path.
 *  - HID sessions are generation-tagged. A stale reader thread can never
 *    resurrect or tear down a newer claim: only the owning session may mutate
 *    the shared connection state, and its reports are decoded as either an
 *    array report or a bitmap report (never both, which double-counted).
 *  - Consumer report layouts differ per device. A DAC using report IDs or a
 *    vendor page will not decode until a matching layout exists.
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
    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerThread = HandlerThread("UsbErgonomicsIo").apply { start() }
    private val workerHandler = Handler(workerThread.looper)
    private val hidLock = Any()
    private val lastBroadcastAtMs = java.util.concurrent.ConcurrentHashMap<Int, Long>()

    /** Generation of the live HID session; incremented by every stop. */
    @Volatile private var hidSession: Long = 0L

    @Volatile private var hidThread: HandlerThread? = null
    @Volatile private var hidConnection: UsbDeviceConnection? = null
    // Item 5: the pending interrupt IN request. Closed from the teardown path so a
    // blocked requestWait() returns instead of pinning the reader thread.
    @Volatile private var hidRequest: UsbRequest? = null
    @Volatile private var hidDevice: UsbDevice? = null
    @Volatile private var hidClaimed = false
    @Volatile private var consumerSeen = false
    @Volatile private var lastUsageName: String? = null
    @Volatile private var hidDetail: String? = null
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

    /** Stops the HID reader (closing the live claim) and the worker thread. */
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
        val quirk = QuirkConfig(
            vid = call.argument<Int>(ARG_VID),
            pid = call.argument<Int>(ARG_PID),
            hidEnabled = call.argument<Boolean>(ARG_HID_ENABLED) == true,
        )
        runAsync(result) {
            applyHid(quirk)
            mapOf<String, Any?>(
                "ok" to true,
                "hid" to hidStatusMap(),
            )
        }
    }

    // ---- probeBusSpeed ----

    private fun handleProbeBusSpeed(call: MethodCall, result: MethodChannel.Result) {
        val vid = call.argument<Int>(ARG_VID)
        val pid = call.argument<Int>(ARG_PID)
        val deviceId = call.argument<Int>(ARG_DEVICE_ID)
        runAsync(result) {
            // Prefer the exact UsbDevice id the Dart side resolved from the
            // status stream; fall back to the vid/pid match only when absent.
            val device = UsbDeviceLookup.audioDeviceById(usbManager, deviceId)
                ?: UsbDeviceLookup.audioDevice(usbManager, vid, pid)
                ?: return@runAsync mapOf("mbps" to null, "detail" to "no_audio_device")
            UsbSysfs.busSpeedMbps(device)
        }
    }

    // ---- resetAltSetting ----

    private fun handleResetAltSetting(call: MethodCall, result: MethodChannel.Result) {
        val vid = call.argument<Int>(ARG_VID)
        val pid = call.argument<Int>(ARG_PID)
        runAsync(result) { usbResetAltSetting(usbManager, vid, pid) }
    }

    // ---- HID consumer control ----

    /**
     * Invalidates the previous session, then starts a new one when enabled.
     *
     * The generation bump happens before the old thread is told to stop, so the
     * old reader can never pass an ownership check afterwards.
     */
    private fun applyHid(quirk: QuirkConfig) {
        synchronized(hidLock) {
            stopHidLocked()
            if (disposed) {
                hidDetail = "disposed"
                return
            }
            if (!quirk.hidEnabled) {
                hidDetail = "disabled"
                return
            }
            val session = hidSession
            hidDetail = "starting"
            val thread = HandlerThread("UsbErgonomicsHid").apply { start() }
            hidThread = thread
            Handler(thread.looper).post { claimAndRead(quirk, session) }
        }
    }

    /**
     * Ends the current HID session: invalidates its generation, closes the live
     * claim (which unblocks a pending interrupt transfer) and stops its thread.
     * Must be called with [hidLock] held.
     */
    private fun stopHidLocked() {
        hidSession += 1
        val connection = hidConnection
        val thread = hidThread
        val request = hidRequest
        hidConnection = null
        hidDevice = null
        hidClaimed = false
        hidThread = null
        hidRequest = null
        // Item 5: cancel and close the pending request BEFORE the connection, so a
        // reader blocked in requestWait() wakes up and observes the dead session.
        if (request != null) {
            try {
                request.cancel()
            } catch (e: Exception) {
                Log.w(TAG, "Cancelling the HID request failed: ${e.message}")
            }
            try {
                request.close()
            } catch (e: Exception) {
                Log.w(TAG, "Closing the HID request failed: ${e.message}")
            }
        }
        closeQuietly(connection)
        try {
            thread?.quitSafely()
        } catch (e: Exception) {
            Log.w(TAG, "Stopping the HID thread failed: ${e.message}")
        }
    }

    /** Whether [session] still owns the shared HID state. */
    private fun isCurrentSession(session: Long): Boolean =
        !disposed && hidSession == session

    /** Marks the session stopped without letting a stale session write. */
    private fun markHidStopped(session: Long, detail: String) {
        synchronized(hidLock) {
            if (hidSession != session) return
            hidClaimed = false
            hidDetail = detail
        }
    }

    private fun claimAndRead(quirk: QuirkConfig, session: Long) {
        if (!isCurrentSession(session)) return
        val device = UsbDeviceLookup.audioDevice(usbManager, quirk.vid, quirk.pid)
        if (device == null) {
            markHidStopped(session, "no_audio_device")
            return
        }
        if (usbManager?.hasPermission(device) != true) {
            markHidStopped(session, "permission_required")
            return
        }
        val hidInterface = UsbDeviceLookup.hidInterface(device)
        if (hidInterface == null) {
            markHidStopped(session, "no_hid_interface")
            return
        }
        val endpoint = UsbDeviceLookup.interruptInput(hidInterface)
        if (endpoint == null) {
            markHidStopped(session, "no_hid_input_endpoint")
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
            markHidStopped(session, "open_failed")
            return
        }
        if (!isCurrentSession(session)) {
            closeQuietly(connection)
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
            closeQuietly(connection)
            markHidStopped(session, "hid_interface_busy")
            return
        }
        val registered = synchronized(hidLock) {
            if (hidSession != session || disposed) {
                false
            } else {
                hidConnection = connection
                hidDevice = device
                hidClaimed = true
                hidDetail = null
                lastUsageName = null
                true
            }
        }
        if (!registered) {
            // A newer session (or dispose) won the race: drop our claim only.
            releaseAndClose(connection, hidInterface)
            return
        }
        try {
            readReports(connection, endpoint, device, session)
        } catch (e: Exception) {
            Log.w(TAG, "The HID report loop failed: ${e.message}")
            markHidStopped(session, "read_failed")
        } finally {
            synchronized(hidLock) {
                if (hidSession == session) {
                    hidClaimed = false
                    hidConnection = null
                    hidDevice = null
                    hidThread = null
                    hidRequest = null
                }
            }
            releaseAndClose(connection, hidInterface)
        }
    }

    private fun readReports(
        connection: UsbDeviceConnection,
        endpoint: UsbEndpoint,
        device: UsbDevice,
        session: Long,
    ) {
        // Item 5: kernels >= 4.9 reject BULK URBs submitted to an INTERRUPT
        // endpoint (usb_urb_ep_type_check), so the old bulkTransfer() call could
        // never have worked on a real DAC. UsbRequest submits an URB with the
        // endpoint's own transfer type, which is what the HID class requires.
        val request = UsbRequest()
        if (!request.initialize(connection, endpoint)) {
            try {
                request.close()
            } catch (e: Exception) {
                Log.w(TAG, "Closing an unusable HID request failed: ${e.message}")
            }
            markHidStopped(session, "hid_request_unsupported")
            return
        }
        val capacity = maxOf(endpoint.maxPacketSize, MIN_REPORT_BYTES)
        val buffer = ByteBuffer.allocateDirect(capacity).order(ByteOrder.nativeOrder())
        val registered = synchronized(hidLock) {
            if (hidSession != session || disposed) {
                false
            } else {
                hidRequest = request
                true
            }
        }
        if (!registered) {
            // A newer session (or dispose) won the race: drop only our request.
            try {
                request.close()
            } catch (e: Exception) {
                Log.w(TAG, "Closing a stale HID request failed: ${e.message}")
            }
            return
        }
        var previous = ByteArray(0)
        try {
            while (isCurrentSession(session)) {
                if (usbManager?.deviceList?.containsValue(device) != true) {
                    markHidStopped(session, "device_detached")
                    return
                }
                // The framework writes at position 0 and advances the position by
                // the number of bytes received, so clear() before every queue and
                // read position() after the wait.
                buffer.clear()
                val queued = try {
                    request.queue(buffer, capacity)
                } catch (e: Exception) {
                    Log.w(TAG, "Queueing the HID request failed: ${e.message}")
                    false
                }
                if (!isCurrentSession(session)) return
                if (!queued) {
                    if (!backoffHid(session)) return
                    continue
                }
                val completed = try {
                    // Blocks until the report arrives, the request is closed by the
                    // teardown path, or the device is detached. Cancelling/closing
                    // the request from stopHidLocked() is what unblocks it.
                    connection.requestWait()
                } catch (e: Exception) {
                    Log.w(TAG, "HID transfer failed: ${e.message}")
                    null
                }
                if (!isCurrentSession(session)) return
                if (completed !== request) {
                    // Cancelled/no data: preserve the old failure backoff instead
                    // of spinning on a device that keeps refusing the transfer.
                    if (!backoffHid(session)) return
                    continue
                }
                val read = buffer.position()
                if (read <= 0) {
                    if (!backoffHid(session)) return
                    continue
                }
                val report = ByteArray(read)
                buffer.flip()
                buffer.get(report, 0, read)
                dispatchReport(report, previous, session)
                previous = report
            }
        } finally {
            synchronized(hidLock) {
                if (hidRequest === request) hidRequest = null
            }
            try {
                request.close()
            } catch (e: Exception) {
                Log.w(TAG, "Closing the HID request failed: ${e.message}")
            }
        }
    }

    /** Sleeps the failure backoff; false when the session ended meanwhile. */
    private fun backoffHid(session: Long): Boolean {
        try {
            Thread.sleep(FAILURE_BACKOFF_MS)
        } catch (e: InterruptedException) {
            Log.w(TAG, "HID backoff was interrupted: ${e.message}")
            Thread.currentThread().interrupt()
            return false
        }
        return isCurrentSession(session)
    }

    /**
     * Broadcasts the media key for every consumer usage that appeared in this
     * report and was not in the previous one. Only the owning session may
     * update the diagnostics state.
     */
    private fun dispatchReport(report: ByteArray, previous: ByteArray, session: Long) {
        if (!isCurrentSession(session)) return
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
            if (!isCurrentSession(session)) return
            consumerSeen = true
            lastUsageName = UsbConsumerUsage.nameOf(usage)
            broadcastMediaButton(keyCode)
        }
    }

    /**
     * Sends ACTION_MEDIA_BUTTON to the same receiver the widgets use, so the
     * existing audio-service session handles a DAC button exactly like a headset
     * button. The key events carry [KeyEvent.FLAG_FROM_SYSTEM] so the receiver
     * treats them as hardware input instead of an app-internal broadcast.
     */
    private fun broadcastMediaButton(keyCode: Int) {
        try {
            val down = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(context, MEDIA_BUTTON_RECEIVER))
                putExtra(Intent.EXTRA_KEY_EVENT, systemKeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            context.sendBroadcast(down)
            val up = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(context, MEDIA_BUTTON_RECEIVER))
                putExtra(Intent.EXTRA_KEY_EVENT, systemKeyEvent(KeyEvent.ACTION_UP, keyCode))
            }
            context.sendBroadcast(up)
        } catch (e: Exception) {
            Log.w(TAG, "Broadcasting media key $keyCode failed: ${e.message}")
        }
    }

    private fun systemKeyEvent(action: Int, keyCode: Int): KeyEvent =
        KeyEvent.changeFlags(
            KeyEvent(action, keyCode),
            KeyEvent.FLAG_FROM_SYSTEM,
        )

    private fun closeQuietly(connection: UsbDeviceConnection?) {
        if (connection == null) return
        try {
            connection.close()
        } catch (e: Exception) {
            Log.w(TAG, "Closing the HID connection failed: ${e.message}")
        }
    }

    private fun releaseAndClose(
        connection: UsbDeviceConnection,
        hidInterface: UsbInterface,
    ) {
        try {
            connection.releaseInterface(hidInterface)
        } catch (e: Exception) {
            Log.w(TAG, "Releasing the HID interface failed: ${e.message}")
        }
        closeQuietly(connection)
    }

    private fun hidStatusMap(): Map<String, Any?> = mapOf(
        "claimed" to hidClaimed,
        "consumerControl" to consumerSeen,
        "lastButton" to lastUsageName,
        "detail" to hidDetail,
    )

    // ---- plumbing ----

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
    }
}

/** Validated quirk values as understood by this plugin. */
private data class QuirkConfig(
    val vid: Int?,
    val pid: Int?,
    val hidEnabled: Boolean,
)

/**
 * Reads the negotiated link speed for one device from sysfs.
 *
 * The device is located by its own bus/device address (derived from
 * `UsbDevice.deviceName`) instead of matching the first sysfs directory with
 * the same vendor/product ids, so two identical DACs cannot report each
 * other's speed. A device whose address cannot be resolved, or a kernel that
 * does not publish `speed`, reports "unknown" instead of guessing.
 */
internal object UsbSysfs {

    fun busSpeedMbps(device: UsbDevice, sysfsRoot: File = File(SYS_USB_DEVICES)): Map<String, Any?> {
        val address = busAndDeviceAddress(device)
            ?: return mapOf("mbps" to null, "detail" to "device_address_unknown")
        val entries = try {
            sysfsRoot.listFiles()
        } catch (e: IOException) {
            Log.w(TAG, "Listing ${sysfsRoot.path} failed: ${e.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "Listing ${sysfsRoot.path} was denied: ${e.message}")
            null
        }
        if (entries == null) {
            return mapOf("mbps" to null, "detail" to "sysfs_not_readable")
        }
        for (entry in entries) {
            if (!entry.isDirectory) continue
            if (readDecimal(File(entry, "busnum")) != address.first) continue
            if (readDecimal(File(entry, "devnum")) != address.second) continue
            val speed = readDouble(File(entry, "speed"))
                ?: return mapOf("mbps" to null, "detail" to "speed_not_published")
            return mapOf("mbps" to speed)
        }
        return mapOf("mbps" to null, "detail" to "speed_not_published")
    }

    /** Bus and device numbers parsed from `/dev/bus/usb/<bus>/<device>`. */
    private fun busAndDeviceAddress(device: UsbDevice): Pair<Int, Int>? {
        val name = try {
            device.deviceName
        } catch (e: Exception) {
            Log.w(TAG, "Reading the USB device name failed: ${e.message}")
            null
        } ?: return null
        val match = BUS_DEVICE_PATTERN.find(name) ?: return null
        val bus = match.groupValues[1].toIntOrNull() ?: return null
        val dev = match.groupValues[2].toIntOrNull() ?: return null
        return Pair(bus, dev)
    }

    private val BUS_DEVICE_PATTERN = Regex("""bus/usb/(\d+)/(\d+)""")

    private fun readDecimal(file: File): Int? {
        val text = readTextFile(file) ?: return null
        val parsed = text.trim().toIntOrNull()
        if (parsed == null) {
            Log.w(TAG, "Reading ${file.name} produced an unexpected value: ${text.trim()}")
        }
        return parsed
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

    /** Exact device by `UsbDevice.deviceId`; null when absent or not audio. */
    fun audioDeviceById(usbManager: UsbManager?, deviceId: Int?): UsbDevice? {
        if (deviceId == null) return null
        val device = usbManager?.deviceList?.values
            ?.firstOrNull { it.deviceId == deviceId }
            ?: return null
        return if (hasAudioInterface(device)) device else null
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
 * usage `i * 8 + n`. Exactly one layout is decoded per report: decoding both
 * made a bitmap byte that happens to equal a usage id register as a second,
 * phantom button.
 */
private object UsbConsumerUsage {

    fun keyCodeFor(usage: Int): Int? = KEY_CODES[usage]

    fun nameOf(usage: Int): String = USAGE_NAMES[usage] ?: "usage_0x${usage.toString(16)}"

    fun decode(report: ByteArray): Set<Int> {
        val array = arrayUsages(report)
        if (array.isNotEmpty()) return array
        return bitmapUsages(report)
    }

    private fun arrayUsages(report: ByteArray): Set<Int> {
        val usages = HashSet<Int>()
        for (byte in report) {
            val value = byte.toInt() and 0xFF
            if (value != 0 && KEY_CODES.containsKey(value)) usages.add(value)
        }
        return usages
    }

    private fun bitmapUsages(report: ByteArray): Set<Int> {
        val usages = HashSet<Int>()
        for (index in report.indices) {
            val value = report[index].toInt() and 0xFF
            if (value == 0) continue
            for (bit in 0 until 8) {
                if (value and (1 shl bit) == 0) continue
                val usage = index * 8 + bit
                if (KEY_CODES.containsKey(usage)) usages.add(usage)
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
