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
import android.media.AudioDeviceInfo
import android.media.AudioManager
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

        /** Per-device quirk profiles, keyed `vid:pid`, JSON document values. */
        private const val QUIRK_PREFS = "pulsr_usb_quirks_v1"

        /** Upper bound on the pre-stream silence a quirk may request. */
        private const val MAX_QUIRK_SILENCE_MS = 2_000

        /** 0 = best effort, 1 = bit-perfect, 2 = ASRC, 3 = native DSD. */
        private const val MAX_RENDER_MODE = 3

        /** `UsbRenderMode::DsdNative` on the native side (UsbAudioSink.h). */
        private const val RENDER_MODE_DSD = 3

        /**
         * Wire shape UsbAudioSink::CheckStreamShape admits for native DSD:
         * stereo DSD_U32 (4-byte subslot, 32 valid bits) at the alternate
         * setting's framesPerSecond. Anything else is refused before the device
         * is touched.
         */
        private const val DSD_CHANNELS = 2
        private const val DSD_BYTES_PER_SAMPLE = 4
        private const val DSD_VALID_BIT_DEPTH = 32

        /** framesPerSecond of DSD64/128/256/512 packed as DSD_U32. */
        private val DSD_U32_RATES = intArrayOf(88200, 176400, 352800, 705600)

        /** `UsbAudioSink::kMaxDsdBytesPerCall` — 1-bit payload bytes per channel. */
        private const val MAX_DSD_BYTES_PER_CALL = 1 shl 20

        /**
         * Producer id used when the caller supplies none. The sink rejects 0
         * (EINVAL) and admits one producer per stream, so this is a fixed
         * non-zero constant rather than a per-call value.
         */
        private const val DSD_PRODUCER_ID = 0x50554C53L  // "PULS"

        /** UAC2 class-specific control: CS_VOLUME in wValue's high byte. */
        private const val UAC_CS_VOLUME = 0x02
        private const val UAC_SET_CUR = 0x01
        private const val UAC_GET_CUR = 0x81
        private const val UAC_GET_MIN = 0x82
        private const val UAC_GET_MAX = 0x83
        private const val UAC_GET_RES = 0x84

        /** UAC2 GET_RANGE shares GET_MIN's request code; the payload differs. */
        private const val UAC_GET_RANGE = 0x82

        /** One probed native-DSD alternate setting, in flattened 7-tuple order. */
        internal data class DsdAltSettingTuple(
            val interfaceNumber: Int,
            val altSetting: Int,
            val endpointAddress: Int,
            val channels: Int,
            val bytesPerSample: Int,
            val framesPerSecond: Int,
            val dsdRate: Int,
        ) {
            val flattened: List<Int>
                get() = listOf(
                    interfaceNumber, altSetting, endpointAddress,
                    channels, bytesPerSample, framesPerSecond, dsdRate,
                )
        }

        /**
         * The live plugin instance. HiResDacPlugin owns the DAC capability
         * facade, but the JNI symbol for the DSD probe is bound to THIS class
         * (Java_com_pulsr_music_UsbExclusivePlugin_nativeProbeDsdAltSettings),
         * so the probe has to run on an instance of this class. One engine owns
         * one USB DAC, the same assumption [directOwner] already makes.
         */
        @Volatile private var probeHost: UsbExclusivePlugin? = null

        /**
         * Probes a raw configuration descriptor blob for native-DSD alternate
         * settings. Null means "the probe could not answer" (no instance, no
         * native library, unusable blob, JNI failure); an empty list means
         * "parsed, no provable DSD" — the same contract as the JNI entry point.
         */
        internal fun probeDsdAltSettings(rawConfig: ByteArray?): List<DsdAltSettingTuple>? =
            probeHost?.probeDsdAltSettingsInternal(rawConfig)

        /**
         * UAC2 volume entry points for the `pulsr/hires_dac` facade. The
         * control transfers run on the USB worker thread (they block) and the
         * answer is delivered on the main thread; a missing owner or a throwing
         * transfer resolves to null/false, never to an exception.
         */
        internal fun uac2VolumeRange(deliver: (Map<String, Any?>?) -> Unit) =
            dispatchToOwner(null, deliver) { it.getUac2VolumeRangeInternal() }

        internal fun uac2HardwareVolume(deliver: (Map<String, Any?>?) -> Unit) =
            dispatchToOwner(null, deliver) { it.getUac2HardwareVolumeInternal() }

        internal fun setUac2HardwareVolume(position: Double, deliver: (Boolean) -> Unit) =
            dispatchToOwner(false, deliver) { it.setUac2HardwareVolumeInternal(position) }

        /** Runs [block] off the main thread and delivers its result back on it. */
        private fun <T> dispatchToOwner(
            fallback: T,
            deliver: (T) -> Unit,
            block: (UsbExclusivePlugin) -> T,
        ) {
            val owner = probeHost
            if (owner == null) {
                try { deliver(fallback) } catch (_: Throwable) {}
                return
            }
            val posted = try {
                owner.workerHandler.post {
                    val value = try { block(owner) } catch (_: Throwable) { fallback }
                    try {
                        owner.mainHandler.post { try { deliver(value) } catch (_: Throwable) {} }
                    } catch (_: Throwable) {}
                }
            } catch (_: Throwable) {
                false
            }
            if (!posted) {
                try { deliver(fallback) } catch (_: Throwable) {}
            }
        }
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
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

    /**
     * Playback rates this DAC has actually advertised, cached so status polling
     * does not issue a control transfer per call. Empty means "unknown" - a rate
     * the device never claimed is never added here.
     */
    private var advertisedRates: List<Int> = emptyList()

    private var hardwareVolume: UsbHardwareVolume? = null
    private var lastVolumeRefreshAtMs = 0L

    /** UAC2 GET_MIN/GET_MAX/GET_RES, read once per device. */
    private var uac2RangeSnapshot: Uac2RangeSnapshot? = null
    private var uac2RangeDeviceId: Int = -1

    private var nativeLoaded = false
    @Volatile private var streaming = false
    @Volatile private var streamFormat: UsbAudioProtocol.StreamFormat? = null
    @Volatile private var directStatus: DirectStreamStatus? = null
    private var claimedStreamingInterface: UsbInterface? = null
    private var claimedControlInterface: UsbInterface? = null

    /**
     * True when the native sink refused to confirm that every submitted URB was
     * reaped. The interfaces and the open connection are then deliberately kept:
     * releasing them or issuing USBDEVFS_CONNECT with URBs still in flight would
     * hand a half-torn-down pipe back to `snd-usb-audio`. Cleared by the next
     * stop that drains successfully.
     */
    @Volatile private var drainPending = false

    /**
     * Lifecycle of the current exclusive session. The USB worker thread owns
     * every transition, but the permission receiver runs on the main thread, so
     * access is serialised on [sessionLock] rather than assumed thread-confined.
     */
    private val session = UsbSessionStateMachine()
    private val sessionLock = Any()

    /** Redacting, bounded (500 events) ring: bug reports and `getDiagnostics`. */
    private val usbEventLog = UsbEventLog()

    // Quirk state resolved for the last start. Published in status so a quirk
    // that changes bit-perfect semantics is never silent.
    @Volatile private var quirkApplied: List<String> = emptyList()
    @Volatile private var quirkRejected: Map<String, String> = emptyMap()
    @Volatile private var quirkNotApplicable: Map<String, String> = emptyMap()
    @Volatile private var quirkBitPerfectAffected: Boolean = false
    @Volatile private var quirkBitPerfectReason: String? = null

    /** Parameters actually applied to the live stream (null when none). */
    @Volatile private var activeQuirks: ResolvedStreamParams? = null

    /** Render mode the live native sink was opened with (0 = best effort). */
    @Volatile private var activeRenderMode: Int = 0
    @Volatile private var streamAltSetting: Int = 0
    @Volatile private var streamEndpoint: Int = 0

    /** Last stream request, replayed as the facts baseline for profile previews. */
    @Volatile private var lastRequestedRate: Int = 48_000
    @Volatile private var lastRequestedDepth: Int = 16
    @Volatile private var lastRequestedChannels: Int = 2

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
    private external fun nativeUsbStreamStartWithFormat(
        fd: Int, endpoint: Int, interfaceNumber: Int, altSetting: Int,
        sampleRate: Int, channels: Int, bytesPerSample: Int, validBitDepth: Int,
        renderMode: Int,
    ): Int
    private external fun nativeUsbStreamStop(): Boolean

    /** DSD feed: LSB-first payload, one producer per stream (id 0 is refused). */
    private external fun nativeUsbStreamWriteDsd(
        left: ByteArray, right: ByteArray, bytesPerChannel: Int, producerId: Long,
    ): Boolean

    /** Raw configuration descriptor -> flattened DSD alt-setting 7-tuples. */
    private external fun nativeProbeDsdAltSettings(rawConfig: ByteArray): IntArray?

    /**
     * Forced teardown for a caller that already decided to release the interface
     * and close the connection because [nativeUsbStreamStop] reported URBs it
     * could not prove reaped. The native side stops its worker, deliberately
     * leaks the URB headers/packet buffers the kernel may still write to,
     * withdraws the sink-depth / direct-USB publication and resets fd_ plus the
     * exclusive flag so the next Open starts clean instead of draining a dead
     * descriptor forever.
     */
    private external fun nativeUsbStreamAbandon()
    private external fun nativeUsbRebindInterface(fd: Int, interfaceNumber: Int): Boolean
    private external fun nativeUsbStreamIsActive(): Boolean
    private external fun nativeUsbStreamGetRawPcmBitDepth(): Int
    private external fun nativeUsbStreamGetLastError(): Int

    private fun safeRawPcmBitDepth(): Int = if (streaming && safeIsStreamActive()) {
        try { nativeUsbStreamGetRawPcmBitDepth() } catch (_: Throwable) { 0 }
    } else 0
    private external fun nativeUsbStreamGetUnderrunCount(): Long
    private external fun nativeUsbStreamGetOverrunCount(): Long
    private external fun nativeUsbStreamGetBufferedMs(): Double

    /** 0 unknown, 1 bitPerfectLocked, 2 asrc, 3 bestEffort (native clock domain). */
    private external fun nativeUsbStreamGetClockDomain(): Int
    private external fun nativeUsbStreamGetClockDriftPpm(): Int
    private external fun nativeUsbStreamGetRingFillMs(): Int
    private external fun nativeUsbStreamGetFeedbackPresent(): Boolean

    /** Optional reader-thread PCM source for the pull renderer. */
    private external fun nativeUsbStreamStartPcmFile(path: String): Boolean
    private external fun nativeUsbStreamStopPcmFile()
    private external fun nativeUsbStreamHasPcmFile(): Boolean

    /** Transfer size / buffer target / explicit-feedback policy for the sink. */
    private external fun nativeUsbSetStreamTuning(
        transferSizeBytes: Int,
        bufferMs: Int,
        disableFeedback: Boolean,
    )

    private external fun nativeUsbGetProducerChannels(): Int
    private external fun nativeUsbStreamGetChannelMismatchFrames(): Long
    private external fun nativeUsbStreamResetChannelMismatchFrames()

    @Volatile private var lastStreamResultCode: Int? = null
    private var lastStreamDiagLogMs = 0L
    @Volatile private var lastRateVerified: Boolean = false

    private fun safeGetLastError(): Int = if (nativeLoaded) try { nativeUsbStreamGetLastError() } catch (_: Throwable) { 0 } else 0
    private fun safeGetUnderrunCount(): Long = if (nativeLoaded) try { nativeUsbStreamGetUnderrunCount() } catch (_: Throwable) { 0L } else 0L
    private fun safeGetOverrunCount(): Long = if (nativeLoaded) try { nativeUsbStreamGetOverrunCount() } catch (_: Throwable) { 0L } else 0L
    private fun safeGetBufferedMs(): Double = if (nativeLoaded) try { nativeUsbStreamGetBufferedMs() } catch (_: Throwable) { 0.0 } else 0.0
    private fun safeIsStreamActive(): Boolean = if (nativeLoaded) try { nativeUsbStreamIsActive() } catch (_: Throwable) { false } else false
    private fun safeGetProducerChannels(): Int = if (nativeLoaded) try { nativeUsbGetProducerChannels() } catch (_: Throwable) { 0 } else 0
    private fun safeGetChannelMismatchFrames(): Long = if (nativeLoaded) try { nativeUsbStreamGetChannelMismatchFrames() } catch (_: Throwable) { 0L } else 0L
    private fun safeResetChannelMismatchFrames() { if (nativeLoaded) try { nativeUsbStreamResetChannelMismatchFrames() } catch (_: Throwable) {} }

    // ---- session state machine / structured event log ----

    private fun sessionNow(): Long = SystemClock.elapsedRealtime()

    private fun sessionStateIs(vararg states: UsbSessionState): Boolean =
        synchronized(sessionLock) { session.state in states }

    private fun sessionStateName(): String = synchronized(sessionLock) { session.state.name }

    private fun sessionReset() = synchronized(sessionLock) { session.reset(sessionNow()) }

    /**
     * Runs one state-machine step. The machine is deliberately strict, so a
     * caller that reaches a step in the wrong state must never take the audio
     * path down with it: the violation is recorded as `state_invariant` and the
     * machine is parked in ERROR, while the stream keeps its own separately
     * tracked state.
     */
    private fun sessionStep(action: String, step: (UsbSessionStateMachine, Long) -> Unit) {
        synchronized(sessionLock) {
            try {
                step(session, sessionNow())
            } catch (e: IllegalStateException) {
                Log.w(TAG, "USB session invariant at $action: ${e.message}")
                recordEvent(lastError = "state_invariant:$action", resultCode = -1)
                forceSessionErrorLocked("state_invariant")
            }
        }
    }

    /** Parks the machine in ERROR from whatever state it is in, without throwing. */
    private fun forceSessionErrorLocked(code: String) {
        try {
            session.reset(sessionNow())
            session.onPermissionRequested(sessionNow())
            session.onError(code, sessionNow())
        } catch (_: Throwable) {
            // Nothing left to try; the audio path is unaffected either way.
        }
    }

    /**
     * Reports a failed start/stop attempt. IDLE is ramped through PERMISSION so
     * the failure is visible as ERROR instead of a silent "nothing happened";
     * DRAINING/ABANDONED are left to the teardown path that owns them.
     */
    private fun failSession(code: String) {
        synchronized(sessionLock) {
            val now = sessionNow()
            try {
                when (session.state) {
                    UsbSessionState.IDLE -> {
                        session.onPermissionRequested(now)
                        session.onError(code, now)
                    }

                    UsbSessionState.DRAINING, UsbSessionState.ABANDONED -> Unit
                    else -> session.onError(code, now)
                }
            } catch (_: IllegalStateException) {
                forceSessionErrorLocked(code)
            }
        }
    }

    private fun sessionPermissionRequested() = sessionStep("permission_requested") { machine, now ->
        machine.onPermissionRequested(now)
    }

    private fun sessionPermissionGranted() = sessionStep("permission_granted") { machine, now ->
        machine.onPermissionGranted(now)
    }

    private fun sessionPermissionDenied() = sessionStep("permission_denied") { machine, now ->
        machine.onPermissionDenied(now)
    }

    private fun sessionOpened() = sessionStep("open_succeeded") { machine, now ->
        machine.onOpenSucceeded(now)
    }

    private fun sessionClaimed() = sessionStep("claim_succeeded") { machine, now ->
        machine.onClaimSucceeded(now)
    }

    private fun sessionConfigured() = sessionStep("configure_succeeded") { machine, now ->
        machine.onConfigureSucceeded(now)
    }

    private fun sessionStarted() = sessionStep("stream_started") { machine, now ->
        machine.onStreamStarted(now)
    }

    /**
     * A failed start: the session is marked ERROR, the reason is recorded and
     * the caller gets the existing failure map (unchanged shape).
     */
    private fun startFailure(reason: String): Map<String, Any?> {
        failSession(reason)
        recordEvent(lastError = reason)
        return failure(reason)
    }

    // ---- clock-domain / sink telemetry ----

    private fun clockDomainLabel(raw: Int): String = when (raw) {
        1 -> "bitPerfectLocked"
        2 -> "asrc"
        3 -> "bestEffort"
        else -> "unknown"
    }

    /** True while the native sink owns a stream; telemetry is meaningless otherwise. */
    private fun streamLive(): Boolean = nativeLoaded && (streaming || isNativeActive())

    private fun safeGetClockDomain(): String =
        if (!streamLive()) "unknown" else clockDomainLabel(
            try { nativeUsbStreamGetClockDomain() } catch (_: Throwable) { 0 },
        )

    private fun safeGetClockDriftPpm(): Int =
        if (!streamLive()) 0 else try { nativeUsbStreamGetClockDriftPpm() } catch (_: Throwable) { 0 }

    private fun safeGetRingFillMs(): Int =
        if (!streamLive()) 0 else try { nativeUsbStreamGetRingFillMs() } catch (_: Throwable) { 0 }

    /**
     * Explicit-feedback capability: measured natively while streaming, and the
     * descriptor fact before that (a quirk profile is resolved from descriptors
     * too, so the same answer is used consistently).
     */
    private fun safeGetFeedbackPresent(): Boolean {
        if (streamLive()) {
            return try { nativeUsbStreamGetFeedbackPresent() } catch (_: Throwable) { false }
        }
        val parsed = parsedResult ?: return false
        return parsed.feedbackEndpoint != null ||
            parsed.altSettingFormats.any { it.feedbackEndpointAddress != null }
    }

    /** Always called before a native start, so a previous profile cannot leak. */
    private fun applyStreamTuning(params: ResolvedStreamParams?) {
        if (!nativeLoaded) return
        try {
            nativeUsbSetStreamTuning(
                params?.transferSizeBytes ?: 0,
                params?.bufferMs ?: 0,
                params?.disableExplicitFeedback ?: false,
            )
        } catch (e: Throwable) {
            Log.w(TAG, "USB stream tuning unavailable: ${e.message}")
        }
    }

    /** Selects alternate setting 0 on the streaming interface, best effort. */
    private fun resetStreamingAlt(conn: UsbDeviceConnection, iface: UsbInterface): Boolean {
        val device = openedDevice ?: return false
        val idle = (0 until device.interfaceCount).map { device.getInterface(it) }
            .firstOrNull { it.id == iface.id && it.alternateSetting == 0 } ?: return false
        return try { conn.setInterface(idle) } catch (_: Exception) { false }
    }

    // ---- quirk profiles ----

    private fun quirkKey(vid: Int, pid: Int): String = "$vid:$pid"

    /**
     * The quirk document from a MethodCall, tolerating both call shapes:
     * the raw map and a `{"profile": {...}}` envelope. Values are kept as-is so
     * [UsbQuirkResolver] can reject a wrong type instead of this reader silently
     * coercing it.
     */
    private fun quirkProfileArgument(call: MethodCall): Map<String, Any?> {
        val arguments = call.arguments as? Map<*, *> ?: return emptyMap()
        val nested = arguments["profile"]
        val source = if (nested is Map<*, *>) nested else arguments
        val profile = LinkedHashMap<String, Any?>(source.size)
        for ((key, value) in source) {
            val name = key as? String ?: continue
            profile[name] = value
        }
        return profile
    }

    private fun quirkPrefs() = context.getSharedPreferences(QUIRK_PREFS, Context.MODE_PRIVATE)

    /** The stored profile for one DAC, or an empty map (never throws). */
    private fun loadQuirkProfile(vid: Int, pid: Int): Map<String, Any?> = try {
        UsbQuirkResolver.fromJson(quirkPrefs().getString(quirkKey(vid, pid), null))
    } catch (_: Throwable) {
        emptyMap()
    }

    private fun deviceFacts(
        device: UsbDevice,
        parsed: UsbAudioControlParser.Result,
        rate: Int,
        depth: Int,
        channels: Int,
    ): UsbDeviceFacts = UsbDeviceFacts(
        vid = device.vendorId,
        pid = device.productId,
        uacVersion = parsed.uacVersion,
        // Unknown stays unknown: a UAC2 rate table is only readable once the
        // Audio Control interface is claimed, and an empty list must never be
        // turned into "nothing is supported".
        supportedRates = advertisedRates,
        requestedRate = rate,
        requestedDepth = depth,
        requestedChannels = channels,
        feedbackPresent = parsed.feedbackEndpoint != null ||
            parsed.altSettingFormats.any { it.feedbackEndpointAddress != null },
    )

    private fun resolveQuirks(device: UsbDevice, facts: UsbDeviceFacts): ResolvedStreamParams {
        val profile = loadQuirkProfile(device.vendorId, device.productId)
        return try {
            UsbQuirkResolver.resolve(profile, facts)
        } catch (_: Throwable) {
            UsbQuirkResolver.resolve(emptyMap(), facts)
        }
    }

    /**
     * Publishes the resolved quirk outcome for status/diagnostics and records
     * rejected entries. Nothing here may block streaming: a rejected quirk only
     * means the affected parameter keeps its request/default value.
     */
    private fun publishQuirks(parsed: UsbAudioControlParser.Result, resolved: ResolvedStreamParams) {
        val applied = resolved.appliedQuirks.toMutableList()
        val notApplicable = LinkedHashMap<String, String>()
        if (UsbQuirkResolver.KEY_UAC1_REASSERT_AFTER_ALT in applied &&
            parsed.uacVersion != UsbAudioControlParser.UAC1
        ) {
            // UAC1 already writes its rate after setInterface(); on UAC2 the
            // quirk has no meaning and must not be reported as applied.
            applied.remove(UsbQuirkResolver.KEY_UAC1_REASSERT_AFTER_ALT)
            notApplicable[UsbQuirkResolver.KEY_UAC1_REASSERT_AFTER_ALT] = "not_applicable"
        }
        if (UsbQuirkResolver.KEY_DISABLE_UAC2_CLOCK_SWITCH in applied &&
            parsed.uacVersion != UsbAudioControlParser.UAC2
        ) {
            // There is no UAC2 clock entity to leave alone on a UAC1 device.
            applied.remove(UsbQuirkResolver.KEY_DISABLE_UAC2_CLOCK_SWITCH)
            notApplicable[UsbQuirkResolver.KEY_DISABLE_UAC2_CLOCK_SWITCH] = "not_applicable"
        }
        quirkApplied = applied
        quirkNotApplicable = notApplicable
        quirkRejected = resolved.rejected.filterKeys { it != "rate" }
        quirkBitPerfectAffected = resolved.bitPerfectAffected
        quirkBitPerfectReason = resolved.bitPerfectReason
        for ((key, reason) in resolved.rejected) {
            // "rate" is the resolver's answer about the *request*, not a quirk;
            // selectFormat refuses an unsupported format on its own.
            if (key == "rate") continue
            recordEvent(lastError = "quirk_rejected:$key=$reason", resultCode = 0)
        }
    }

    // ---- structured events ----

    /**
     * Appends one [UsbEvent] with the real fields of the moment. Redaction and
     * bounds live in [UsbEventLog]; no path, serial or descriptor dump is passed.
     */
    private fun recordEvent(
        lastError: String? = null,
        resultCode: Int = lastStreamResultCode ?: 0,
        format: UsbAudioProtocol.StreamFormat? = streamFormat,
        rate: Int = format?.sampleRate ?: 0,
        depth: Int = format?.wireBitDepth ?: 0,
        channels: Int = format?.wireChannels ?: 0,
        interfaceNumber: Int = streamInterfaceNumber ?: 0,
        altSetting: Int = streamAltSetting,
        endpoint: Int = streamEndpoint,
        selectorPin: Int = activeQuirks?.preferredSelectorPin ?: 0,
        drainPending: Boolean = this.drainPending,
    ) {
        val device = openedDevice
        try {
            usbEventLog.record(
                UsbEvent(
                    timestampMs = SystemClock.elapsedRealtime(),
                    build = safeBuildLabel(),
                    deviceModel = safeDeviceModel(),
                    androidVersion = safeAndroidVersion(),
                    vid = device?.vendorId ?: 0,
                    pid = device?.productId ?: 0,
                    uacVersion = uacVersion,
                    interfaceNumber = interfaceNumber,
                    altSetting = altSetting,
                    endpoint = endpoint,
                    rate = rate,
                    depth = depth,
                    channels = channels,
                    clockSource = parsedResult?.clockSource?.clockId ?: 0,
                    selectorPin = selectorPin,
                    feedbackPresent = safeGetFeedbackPresent(),
                    clockDriftPpm = safeGetClockDriftPpm().toDouble(),
                    ringFillMs = safeGetRingFillMs().toLong(),
                    underrunCount = safeGetUnderrunCount(),
                    overrunCount = safeGetOverrunCount(),
                    lastError = lastError,
                    drainPending = drainPending,
                    resultCode = resultCode,
                ),
            )
        } catch (_: Throwable) {
            // The log is diagnostics, never part of the audio path.
        }
    }

    private fun eventsAsMaps(events: List<UsbEvent>): List<Map<String, Any?>> = events.map { event ->
        mapOf(
            "timestampMs" to event.timestampMs,
            "build" to event.build,
            "deviceModel" to event.deviceModel,
            "androidVersion" to event.androidVersion,
            "vid" to event.vid,
            "pid" to event.pid,
            "uacVersion" to event.uacVersion,
            "interfaceNumber" to event.interfaceNumber,
            "altSetting" to event.altSetting,
            "endpoint" to event.endpoint,
            "rate" to event.rate,
            "depth" to event.depth,
            "channels" to event.channels,
            "clockSource" to event.clockSource,
            "selectorPin" to event.selectorPin,
            "feedbackPresent" to event.feedbackPresent,
            "clockDriftPpm" to event.clockDriftPpm,
            "ringFillMs" to event.ringFillMs,
            "underrunCount" to event.underrunCount,
            "overrunCount" to event.overrunCount,
            "lastError" to event.lastError,
            "drainPending" to event.drainPending,
            "resultCode" to event.resultCode,
        )
    }

    private fun safeBuildLabel(): String = try { Build.DISPLAY ?: "unknown" } catch (_: Throwable) { "unknown" }

    private fun safeAndroidVersion(): String = try {
        Build.VERSION.RELEASE ?: "unknown"
    } catch (_: Throwable) { "unknown" }

    private fun safeDeviceModel(): String = try {
        listOfNotNull(Build.MANUFACTURER, Build.MODEL).joinToString(" ").trim()
            .ifEmpty { "unknown" }
    } catch (_: Throwable) { "unknown" }

    // ---- quirk profile persistence (no dependency: tiny JSON writer) ----

    private fun setQuirkProfileInternal(profile: Map<String, Any?>): Map<String, Any?> {
        val device = openedDevice ?: findAudioDevice()
            ?: return mapOf(
                "ok" to false,
                "error" to "no_usb_device",
                "applied" to emptyList<String>(),
                "rejected" to emptyMap<String, String>(),
                "bitPerfectAffected" to false,
                "bitPerfectReason" to null,
            )
        val stored = try {
            quirkPrefs().edit()
                .putString(quirkKey(device.vendorId, device.productId), encodeJsonObject(profile))
                .commit()
        } catch (_: Throwable) {
            false
        }
        if (!stored) {
            return mapOf(
                "ok" to false,
                "error" to "profile_store_failed",
                "applied" to emptyList<String>(),
                "rejected" to emptyMap<String, String>(),
                "bitPerfectAffected" to false,
                "bitPerfectReason" to null,
            )
        }
        val parsed = parsedResult ?: parseViaInterfaces(device).also { applyParsed(it) }
        val resolved = UsbQuirkResolver.resolve(
            profile,
            deviceFacts(device, parsed, lastRequestedRate, lastRequestedDepth, lastRequestedChannels),
        )
        // The synthetic "rate" rejection belongs to a stream request, not to the
        // profile: previewing a profile must not look like a bad key.
        val rejected = resolved.rejected.filterKeys { it != "rate" }
        recordEvent(lastError = null, resultCode = 0)
        return mapOf(
            "ok" to true,
            "vid" to device.vendorId,
            "pid" to device.productId,
            "applied" to resolved.appliedQuirks,
            "rejected" to rejected,
            "bitPerfectAffected" to resolved.bitPerfectAffected,
            "bitPerfectReason" to resolved.bitPerfectReason,
        )
    }

    private fun encodeJsonObject(profile: Map<String, Any?>): String = buildString {
        append('{')
        var first = true
        for ((key, value) in profile) {
            if (!first) append(',')
            first = false
            appendJsonString(key)
            append(':')
            appendJsonValue(value)
        }
        append('}')
    }

    private fun StringBuilder.appendJsonValue(value: Any?) {
        when (value) {
            null -> append("null")
            is Boolean -> append(value)
            is Int, is Long, is Short, is Byte -> append(value.toString())
            is Double -> if (value.isFinite()) append(value.toString()) else append("null")
            is Float -> if (value.isFinite()) append(value.toDouble().toString()) else append("null")
            is String -> appendJsonString(value)
            is Map<*, *> -> {
                append('{')
                var first = true
                for ((k, v) in value) {
                    if (!first) append(',')
                    first = false
                    appendJsonString(k as? String ?: k.toString())
                    append(':')
                    appendJsonValue(v)
                }
                append('}')
            }

            is Iterable<*> -> {
                append('[')
                var first = true
                for (item in value) {
                    if (!first) append(',')
                    first = false
                    appendJsonValue(item)
                }
                append(']')
            }

            else -> append("null")
        }
    }

    private fun StringBuilder.appendJsonString(value: String) {
        append('"')
        for (ch in value) {
            when (ch) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (ch < ' ') append(' ') else append(ch)
            }
        }
        append('"')
    }
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var permissionReceiver: BroadcastReceiver? = null
    private var pendingPermissionTimeout: Runnable? = null

    private fun cancelPermissionTimeout() {
        pendingPermissionTimeout?.let { mainHandler.removeCallbacks(it) }
        pendingPermissionTimeout = null
    }

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
                            sessionStep("detached") { machine, now -> machine.onDetached(now) }
                            recordEvent(lastError = "device_detached")
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
        probeHost = this
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
                "resetHardwareVolume" -> {
                    runAsync(call.method, result) { resetHardwareVolumeInternal() }
                }
                "startStreaming" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val channels = call.argument<Int>("channels") ?: 2
                    val bitDepth = call.argument<Int>("bitDepth") ?: 16
                    val strict = call.argument<Boolean>("strict") ?: false
                    // 0 = best effort, 1 = bit-perfect, 2 = ASRC. An unknown or
                    // out-of-range value degrades to best effort and is recorded
                    // rather than silently accepted as a mode the sink never got.
                    val rawRenderMode = call.argument<Int>("renderMode")
                    val renderMode = (rawRenderMode ?: 0).coerceIn(0, MAX_RENDER_MODE)
                    runAsync(call.method, result) {
                        if (call.hasArgument("renderMode") && rawRenderMode != renderMode) {
                            recordEvent(lastError = "render_mode_clamped:$rawRenderMode", resultCode = 0)
                        }
                        startStreamingInternal(sampleRate, channels, bitDepth, strict, renderMode)
                    }
                }
                "stopStreaming" -> runAsync(call.method, result) { stopStreamingInternal() }
                // Native DSD (DSD_U32). The alt setting comes from the
                // descriptor probe (`getDopCapabilities` -> nativeDsdAltSetting),
                // never from a rate/depth guess: the sink admits exactly one
                // wire shape per alternate setting.
                "startDsdStreaming" -> {
                    val tuple = DsdAltSettingTuple(
                        interfaceNumber = call.argument<Int>("interfaceNumber") ?: -1,
                        altSetting = call.argument<Int>("altSetting") ?: -1,
                        endpointAddress = call.argument<Int>("endpoint") ?: 0,
                        channels = call.argument<Int>("channels") ?: DSD_CHANNELS,
                        bytesPerSample = call.argument<Int>("bytesPerSample") ?: DSD_BYTES_PER_SAMPLE,
                        framesPerSecond = call.argument<Int>("framesPerSecond") ?: 0,
                        dsdRate = call.argument<Int>("dsdRate") ?: 0,
                    )
                    val dsdStrict = call.argument<Boolean>("strict") ?: true
                    runAsync(call.method, result) { startDsdStreamingInternal(tuple, dsdStrict) }
                }
                "writeDsd" -> {
                    val left = call.argument<ByteArray>("left")
                    val right = call.argument<ByteArray>("right")
                    val producerId = call.argument<Long>("producerId") ?: DSD_PRODUCER_ID
                    runAsync(call.method, result) {
                        writeDsd(
                            left ?: ByteArray(0),
                            right ?: ByteArray(0),
                            producerId,
                        )
                    }
                }
                "isDsdActive" -> runAsync(call.method, result) { isDsdActive }
                "getUac2VolumeRange" -> runAsync(call.method, result) {
                    getUac2VolumeRangeInternal()
                }
                "getUac2HardwareVolume" -> runAsync(call.method, result) {
                    getUac2HardwareVolumeInternal()
                }
                "setUac2HardwareVolume" -> {
                    val position = call.argument<Double>("position") ?: 0.0
                    runAsync(call.method, result) { setUac2HardwareVolumeInternal(position) }
                }
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
                    // safeGetBufferedMs() reaches UsbAudioSink::GetBufferedMs(),
                    // which waits on the native control mutex that Close() can
                    // hold for up to 2 s while it drains. Never measure that on
                    // the main thread: route it through the worker like
                    // getStatus(). The returned map only grows with diagnostics.
                    runAsync(call.method, result) {
                        mapOf(
                            "lastError" to safeGetLastError(),
                            "underrunCount" to safeGetUnderrunCount(),
                            "overrunCount" to safeGetOverrunCount(),
                            "channelMismatchFrames" to safeGetChannelMismatchFrames(),
                            "isStreamActive" to safeIsStreamActive(),
                            "bufferedMs" to safeGetBufferedMs(),
                            "events" to eventsAsMaps(usbEventLog.snapshot()),
                            "sessionState" to sessionStateName(),
                            "drainPending" to drainPending,
                            "clockDomain" to safeGetClockDomain(),
                            "clockDriftPpm" to safeGetClockDriftPpm(),
                            "ringFillMs" to safeGetRingFillMs(),
                            "feedbackPresent" to safeGetFeedbackPresent(),
                            "quirkApplied" to quirkApplied,
                            "quirkRejected" to quirkRejected,
                            "quirkNotApplicable" to quirkNotApplicable,
                            "quirkBitPerfectAffected" to quirkBitPerfectAffected,
                            "quirkBitPerfectReason" to quirkBitPerfectReason,
                        )
                    }
                }
                "startPcmFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        runAsync(call.method, result) { nativeUsbStreamStartPcmFile(path) }
                    }
                }
                "stopPcmFile" -> runAsync(call.method, result) {
                    nativeUsbStreamStopPcmFile()
                    true
                }
                "hasPcmFileSource" -> runAsync(call.method, result) {
                    nativeUsbStreamHasPcmFile()
                }
                "getUsbEvents" -> runAsync(call.method, result) {
                    eventsAsMaps(usbEventLog.snapshot())
                }
                "setQuirkProfile" -> {
                    // Two shapes are accepted: the raw document as the arguments
                    // (`invokeMethod('setQuirkProfile', profile)`, what the Dart
                    // service sends) and the `{"profile": {...}}` envelope.
                    val profile = quirkProfileArgument(call)
                    runAsync(call.method, result) { setQuirkProfileInternal(profile) }
                }
                "getBufferedMs" -> runAsync(call.method, result) { safeGetBufferedMs() }
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
        cancelPermissionTimeout()
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
        if (probeHost === this) probeHost = null
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
            // Route-aware choice: two DACs can be attached at once and only one
            // of them is the routed output. Returning merely the first audio
            // device would stream to the non-routed DAC (silent while the
            // status still looks active). Ask the parser which attached device
            // the routed USB output names. A device whose permission is not
            // granted yet is still returned - the caller prompts for it.
            routeAwareAudioDevice(devices)?.let { return it }
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
     * The USB output the platform is currently routing media to, if any.
     *
     * `GET_DEVICES_OUTPUTS` lists every attached output without saying which
     * one is live, so the measured app stream (PulsrOutputRouting) wins; with no
     * measured stream the first USB output is used only as a capability hint.
     * While direct streaming owns the DAC, `snd-usb-audio` is detached and this
     * correctly reports nothing.
     */
    private fun routedUsbOutput(): AudioDeviceInfo? {
        val am = audioManager ?: return null
        val outputs = try {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        } catch (_: Throwable) {
            return null
        }
        val usbOutputs = outputs.filter {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }
        if (usbOutputs.isEmpty()) return null
        val measuredId = try {
            com.ryanheise.just_audio.PulsrOutputRouting.snapshot()[0]
        } catch (_: Throwable) {
            0
        }
        return usbOutputs.firstOrNull { it.id == measuredId } ?: usbOutputs.first()
    }

    /**
     * Route-aware DAC choice: maps the routed USB output's product name and
     * (API 28+) address onto the attached USB devices and returns the matching
     * one. The selection requires a real route match ([requireRouteMatch]), so a
     * route hint naming none of the attached devices yields null and the caller
     * keeps its existing audio-class / vendor ordering instead of silently
     * streaming to the other attached DAC. An already opened device is returned
     * by findAudioDevice() before this runs, so an open (streaming) device is
     * never swapped here.
     */
    private fun routeAwareAudioDevice(devices: Collection<UsbDevice>): UsbDevice? {
        if (audioManager == null) return null
        val route = routedUsbOutput() ?: return null
        val routeAddress = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            route.address
        } else {
            null
        }
        val summaries = devices.map { device ->
            UsbAudioControlParser.UsbDeviceSummary(
                id = device.deviceId,
                vendorId = device.vendorId,
                productId = device.productId,
                manufacturerName = device.manufacturerName,
                productName = device.productName,
                interfaces = (0 until device.interfaceCount).map { idx ->
                    val iface = device.getInterface(idx)
                    UsbAudioControlParser.InterfaceSignature(
                        iface.interfaceClass,
                        iface.interfaceSubclass,
                        iface.interfaceProtocol,
                    )
                },
            )
        }
        val preferred = UsbAudioControlParser.selectPreferredAudioDevice(
            devices = summaries,
            routeProductName = route.productName?.toString(),
            routeAddress = routeAddress,
            // The standard-audio bonus only ranks candidates, it is not a route
            // match: without this a hint naming no attached device would still
            // return the first audio-class DAC.
            requireRouteMatch = true,
        ) ?: return null
        return devices.firstOrNull { it.deviceId == preferred.id }
    }

    /**
     * A vendor-specific (0xFF) device only counts as audio when it shows BOTH
     * an audio-shaped control and an audio-shaped streaming interface, so an
     * ADB/debug accessory (also 0xFF) can never match on one stray interface.
     */
    private fun hasVendorAudioPair(device: UsbDevice): Boolean =
        UsbAudioControlParser.hasAudioControlAndStreamingPair(
            interfaces = (0 until device.interfaceCount).map { idx ->
                val iface = device.getInterface(idx)
                UsbAudioControlParser.InterfaceSignature(
                    iface.interfaceClass,
                    iface.interfaceSubclass,
                    iface.interfaceProtocol,
                )
            },
            vendorOnly = true,
        )

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
        // UAC1 rates come from the FORMAT_TYPE descriptors; UAC2 alt settings
        // carry none, so its list stays empty until the clock range is read.
        advertisedRates = parsed.supportedRates
    }

    /**
     * Reads the playback rates the attached DAC actually advertises and caches
     * them: UAC1 FORMAT_TYPE descriptor rates, or the UAC2 Clock Source range
     * (readable only while the Audio Control interface is claimed). A refused or
     * unsupported query leaves an empty list rather than a fabricated one.
     * Never fails the caller: rates are diagnostics, not a streaming decision.
     */
    private fun refreshAdvertisedRates(conn: UsbDeviceConnection): List<Int> {
        val parsed = parsedResult
        val queried = try {
            if (parsed != null) {
                UsbAudioProtocol.queryPlaybackRates(transport(conn), parsed)
            } else {
                emptyList()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Playback rate query failed: ${e.message}")
            emptyList<Int>()
        }
        advertisedRates = when {
            queried.isNotEmpty() -> queried
            // Descriptor-declared UAC1 rates are still a device claim even when
            // the live query is refused.
            parsed != null && parsed.uacVersion == UsbAudioControlParser.UAC1 -> parsed.supportedRates
            // UAC2/UAC3 without a readable clock range: unknown, not guessed.
            else -> emptyList()
        }
        return advertisedRates
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
        if (openedDevice != null) {
            val stillAttached = usbManager?.deviceList?.values?.any {
                it.deviceId == openedDevice?.deviceId
            } == true
            if (!stillAttached) closeLocked()
        }
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
            // The sink died on its own. Releasing the interfaces is only safe
            // once the native teardown confirms every URB was reaped; when it
            // cannot, the claims stay and the status reports drainPending.
            Log.w(TAG, "USB streaming sink inactive; bounded drain before release")
            if (!clearStreaming()) {
                Log.w(TAG, "USB drain incomplete; interfaces stay claimed, no kernel rebind")
            }
        }
        if (streaming) {
            val diagNow = SystemClock.elapsedRealtime()
            if (diagNow - lastStreamDiagLogMs >= 10_000L) {
                lastStreamDiagLogMs = diagNow
                Log.i(TAG, "streaming: rate=${streamFormat?.sampleRate} " +
                    "depth=${streamFormat?.wireBitDepth} bufferedMs=${safeGetBufferedMs()} " +
                    "underruns=${safeGetUnderrunCount()} overruns=${safeGetOverrunCount()} " +
                    "mismatch=${safeGetChannelMismatchFrames()} " +
                    "lastError=${safeGetLastError()} resultCode=$lastStreamResultCode")
            }
        }
        val directCapable = parsed.uacVersion in 1..2 && parsed.altSettingFormats.isNotEmpty()
        directStreamingSupported = nativeLoaded && directCapable
        refreshHardwareVolumeIfNeeded()
        val hasVolume = permitted && hardwareVolume?.ready == true
        // Prefer the rates the device was actually asked for; fall back to the
        // descriptor list only when nothing has been queried yet.
        val rates = advertisedRates.ifEmpty { parsed.supportedRates }
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
            "dsdActive" to isDsdActive,
            "drainPending" to drainPending,
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
            "supportedRates" to rates,
            "lastError" to safeGetLastError(),
            "resultCode" to lastStreamResultCode,
            "underrunCount" to safeGetUnderrunCount(),
            "overrunCount" to safeGetOverrunCount(),
            "channelMismatchFrames" to safeGetChannelMismatchFrames(),
            "bufferedMs" to safeGetBufferedMs(),
            "rateVerified" to (streaming && lastRateVerified),
            // Clock-domain telemetry: cheap native getters, no USB transfer, so
            // status polling gains no new blocking work.
            "clockDomain" to safeGetClockDomain(),
            "clockDriftPpm" to safeGetClockDriftPpm(),
            "ringFillMs" to safeGetRingFillMs(),
            "feedbackPresent" to safeGetFeedbackPresent(),
            "sessionState" to sessionStateName(),
            "quirkApplied" to quirkApplied,
            "quirkRejected" to quirkRejected,
            "quirkNotApplicable" to quirkNotApplicable,
            "quirkBitPerfectAffected" to quirkBitPerfectAffected,
            "quirkBitPerfectReason" to quirkBitPerfectReason,
            "advertisedFormats" to parsed.altSettingFormats.map { fmt ->
                mapOf(
                    "interfaceNumber" to fmt.interfaceNumber,
                    "altSetting" to fmt.altSetting,
                    "subslotSize" to fmt.subslotSize,
                    "bitResolution" to fmt.bitResolution,
                    "channels" to fmt.channels,
                    // UAC1 declares rates per alternate setting; a UAC2 clock
                    // range is device-wide, so every alt carries the same list.
                    "supportedRates" to if (parsed.uacVersion == UsbAudioControlParser.UAC2) {
                        rates
                    } else {
                        fmt.supportedRates
                    },
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
        "dsdActive" to false,
        "drainPending" to false,
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
        // Always present so the Dart parser never sees a missing key.
        "clockDomain" to "unknown",
        "clockDriftPpm" to 0,
        "ringFillMs" to 0,
        "feedbackPresent" to false,
        "sessionState" to sessionStateName(),
        "quirkApplied" to emptyList<String>(),
        "quirkRejected" to emptyMap<String, String>(),
        "quirkNotApplicable" to emptyMap<String, String>(),
        "quirkBitPerfectAffected" to false,
        "quirkBitPerfectReason" to null,
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
        // A prompt raised mid-stream must not reset a live session: only an
        // idle/failed/abandoned machine is admitted here.
        if (sessionStateIs(UsbSessionState.IDLE, UsbSessionState.ERROR, UsbSessionState.ABANDONED)) {
            sessionPermissionRequested()
            recordEvent(resultCode = 0)
        }
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
        val timeout = Runnable {
            pendingPermissionTimeout = null
            if (pendingPermissionResult != null) {
                Log.w(TAG, "USB permission request timed out after 60s")
                finishPermission(false)
            }
        }
        pendingPermissionTimeout = timeout
        mainHandler.postDelayed(timeout, 60_000L)
        usbManager?.requestPermission(device, pi)
    }

    private fun finishPermission(granted: Boolean) {
        cancelPermissionTimeout()
        val r = pendingPermissionResult
        pendingPermissionResult = null
        permissionReceiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        permissionReceiver = null
        if (sessionStateIs(UsbSessionState.PERMISSION)) {
            if (granted) {
                sessionPermissionGranted()
                recordEvent(resultCode = 0)
            } else {
                sessionPermissionDenied()
                recordEvent(lastError = "permission_denied", resultCode = 1)
            }
        }
        emitState()
        try { r?.success(granted) } catch (_: Exception) {}
    }

    // ---- exclusive claim ----

    private fun setExclusiveInternal(enabled: Boolean): Map<String, Any?> {
        val device = findAudioDevice() ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        if (!enabled) {
            if (streaming) {
                return failure("streaming_active")
            }
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

    private fun applyHardwareVolumeDb(rawTargetDb: Double): Map<String, Any?> {
        hardwareVolume?.invalidate()
        val device = openedDevice ?: findAudioDevice() ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        ensureConnection(device) ?: return failure("open_failed")
        val volume = hardwareVolume ?: return failure("no_usable_volume_control")
        val ok = volume.setDb(rawTargetDb)
        val status = buildStatus()
        emitState()
        return status + mapOf(
            "success" to (ok && volume.applied),
            "error" to if (ok && volume.applied) null else "volume_not_verified",
        )
    }

    private fun setHardwareVolumeInternal(db: Double): Map<String, Any?> {
        val device = openedDevice ?: findAudioDevice() ?: return failure("no_usb_device")
        val offset = getVolumeCalibrationOffset(device.vendorId, device.productId)
        return applyHardwareVolumeDb(db + offset)
    }

    private fun resetHardwareVolumeInternal(): Map<String, Any?> {
        val device = openedDevice ?: findAudioDevice() ?: return failure("no_usb_device")
        if (usbManager?.hasPermission(device) != true) return failure("permission_required")
        ensureConnection(device) ?: return failure("open_failed")
        val volume = hardwareVolume ?: return failure("no_usable_volume_control")
        val unityDb = 0.0.coerceIn(volume.minDb, volume.maxDb)
        return applyHardwareVolumeDb(unityDb)
    }

    // ---- UAC2 hardware volume (Contract B) ----
    //
    // UAC2 volume is a signed 16-bit 1/256 dB value on the wire. The Control
    // Selector sits in the high byte of wValue (CS_VOLUME = 0x02; 0x01 is
    // CS_MUTE) and the channel in the low byte; wIndex carries the Feature
    // Unit's Entity ID in its high byte and the Audio Control interface number
    // in its low byte. GET_MIN/GET_MAX/GET_RES are read once per device and the
    // 0..1 UI position is mapped through those values, never through an assumed
    // 0..-60 dB range.

    private data class Uac2RangeSnapshot(
        val minQ8: Int,
        val maxQ8: Int,
        val resQ8: Int,
        val unitId: Int,
        val interfaceNumber: Int,
        val channels: List<Int>,
        val fromRangeRequest: Boolean,
    )

    private fun clearUac2RangeCache() {
        uac2RangeSnapshot = null
        uac2RangeDeviceId = -1
    }

    /** Little-endian unsigned 16-bit read. */
    private fun le16(data: ByteArray, offset: Int = 0): Int =
        (data[offset].toInt() and 0xFF) or ((data[offset + 1].toInt() and 0xFF) shl 8)

    /** Little-endian signed 16-bit read (Q8.8 dB). */
    private fun le16Signed(data: ByteArray, offset: Int = 0): Int =
        le16(data, offset).toShort().toInt()

    /**
     * One class-specific request on the Audio Control interface. `wValue`
     * carries the Control Selector and channel, `wIndex` the entity and
     * interface. Never throws: a refused transfer answers -1.
     */
    private fun uac2Transfer(
        conn: UsbDeviceConnection,
        requestType: Int,
        request: Int,
        unitId: Int,
        interfaceNumber: Int,
        channel: Int,
        data: ByteArray,
    ): Int = try {
        conn.controlTransfer(
            requestType,
            request,
            (UAC_CS_VOLUME shl 8) or channel,
            (unitId shl 8) or interfaceNumber,
            data,
            data.size,
            CTRL_TIMEOUT_MS,
        )
    } catch (_: Throwable) {
        -1
    }

    private fun uac2ReadQ8(
        conn: UsbDeviceConnection,
        request: Int,
        unitId: Int,
        interfaceNumber: Int,
        channel: Int,
    ): Int? {
        val data = ByteArray(2)
        if (uac2Transfer(conn, 0xA1, request, unitId, interfaceNumber, channel, data) != 2) {
            return null
        }
        return le16Signed(data)
    }

    /** UAC1-style GET_MIN / GET_MAX / GET_RES: exactly one range. */
    private fun uac2MinMaxResRange(
        conn: UsbDeviceConnection,
        unit: UsbAudioControlParser.FeatureUnitVolume,
        interfaceNumber: Int,
        channels: List<Int>,
    ): Uac2RangeSnapshot? {
        val channel = channels.firstOrNull() ?: return null
        val min = uac2ReadQ8(conn, UAC_GET_MIN, unit.unitId, interfaceNumber, channel) ?: return null
        val max = uac2ReadQ8(conn, UAC_GET_MAX, unit.unitId, interfaceNumber, channel) ?: return null
        val res = uac2ReadQ8(conn, UAC_GET_RES, unit.unitId, interfaceNumber, channel) ?: return null
        if (min >= max) return null
        return Uac2RangeSnapshot(min, max, res and 0xFFFF, unit.unitId, interfaceNumber, channels, false)
    }

    /**
     * UAC2 GET_RANGE: wNumSubRanges followed by (wMIN, wMAX, wRES) triplets.
     * Firmware that only answers the UAC1 shape fails the count check here and
     * falls back to [uac2MinMaxResRange].
     */
    private fun uac2SubRangeRange(
        conn: UsbDeviceConnection,
        unit: UsbAudioControlParser.FeatureUnitVolume,
        interfaceNumber: Int,
        channels: List<Int>,
    ): Uac2RangeSnapshot? {
        val channel = channels.firstOrNull() ?: return null
        val header = ByteArray(2)
        if (uac2Transfer(conn, 0xA1, UAC_GET_RANGE, unit.unitId, interfaceNumber, channel, header) != 2) {
            return null
        }
        val count = le16(header)
        if (count !in 1..64) return null
        val data = ByteArray(2 + count * 6)
        if (uac2Transfer(conn, 0xA1, UAC_GET_RANGE, unit.unitId, interfaceNumber, channel, data) != data.size) {
            return null
        }
        if (le16(data) != count) return null
        for (index in 0 until count) {
            val at = 2 + index * 6
            val min = le16Signed(data, at)
            val max = le16Signed(data, at + 2)
            if (min >= max) continue
            return Uac2RangeSnapshot(
                min, max, le16(data, at + 4), unit.unitId, interfaceNumber, channels, true,
            )
        }
        return null
    }

    /** Reads the range once per device; null when the DAC exposes no volume control. */
    private fun ensureUac2Range(
        conn: UsbDeviceConnection,
        device: UsbDevice,
        parsed: UsbAudioControlParser.Result,
    ): Uac2RangeSnapshot? {
        val cached = uac2RangeSnapshot
        if (cached != null && uac2RangeDeviceId == device.deviceId) return cached
        val unit = parsed.volumeUnit ?: return null
        val interfaceNumber = unit.interfaceNumber.takeIf { it >= 0 } ?: parsed.controlInterface
        if (interfaceNumber < 0) return null
        val channels = unit.controlChannels.take(8)
        if (channels.isEmpty()) return null
        val snapshot = if (parsed.uacVersion == UsbAudioControlParser.UAC2) {
            uac2SubRangeRange(conn, unit, interfaceNumber, channels)
                ?: uac2MinMaxResRange(conn, unit, interfaceNumber, channels)
        } else {
            uac2MinMaxResRange(conn, unit, interfaceNumber, channels)
                ?: uac2SubRangeRange(conn, unit, interfaceNumber, channels)
        } ?: return null
        uac2RangeSnapshot = snapshot
        uac2RangeDeviceId = device.deviceId
        return snapshot
    }

    /** Kotlin mirror of pulsr::Uac2VolumePositionToQ8 (Uac2Volume.cpp). */
    private fun uac2PositionToQ8(position: Double, range: Uac2RangeSnapshot): Int {
        val min = range.minQ8
        val max = range.maxQ8
        if (min >= max) return if (max < min) max else min
        val step = if (range.resQ8 > 0) range.resQ8 else 1
        var clamped = position
        if (clamped.isNaN()) clamped = 0.0
        clamped = clamped.coerceIn(0.0, 1.0)
        val target = min.toDouble() + clamped * (max - min).toDouble()
        val steps = roundHalfAwayFromZero((target - min) / step)
        var snapped = min + steps * step
        if (snapped < min) snapped = min
        if (snapped > max) snapped = max
        return snapped
    }

    /** Kotlin mirror of pulsr::Uac2VolumeQ8ToPosition — clamped, not snapped. */
    private fun uac2Q8ToPosition(q8: Int, range: Uac2RangeSnapshot): Double {
        val min = range.minQ8
        val max = range.maxQ8
        if (min >= max) return 0.0
        val position = (q8 - min).toDouble() / (max - min).toDouble()
        if (!(position >= 0.0)) return 0.0
        return if (position > 1.0) 1.0 else position
    }

    /** std::llround: rounds half away from zero. */
    private fun roundHalfAwayFromZero(value: Double): Int =
        if (value >= 0.0) (value + 0.5).toInt() else -((-value + 0.5).toInt())

    private fun getUac2VolumeRangeInternal(): Map<String, Any?>? {
        return try {
            val device = openedDevice ?: findAudioDevice() ?: return null
            if (usbManager?.hasPermission(device) != true) return null
            val conn = ensureConnection(device) ?: return null
            val parsed = parsedResult ?: return null
            val range = ensureUac2Range(conn, device, parsed) ?: return null
            mapOf(
                "minQ8" to range.minQ8,
                "maxQ8" to range.maxQ8,
                "resQ8" to range.resQ8,
                "minDb" to range.minQ8 / 256.0,
                "maxDb" to range.maxQ8 / 256.0,
                "resDb" to range.resQ8 / 256.0,
                "unitId" to range.unitId,
                "interfaceNumber" to range.interfaceNumber,
                "channels" to range.channels,
                "source" to if (range.fromRangeRequest) "get_range" else "get_min_max_res",
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun getUac2HardwareVolumeInternal(): Map<String, Any?>? {
        return try {
            val device = openedDevice ?: findAudioDevice() ?: return null
            if (usbManager?.hasPermission(device) != true) return null
            val conn = ensureConnection(device) ?: return null
            val parsed = parsedResult ?: return null
            val range = ensureUac2Range(conn, device, parsed) ?: return null
            val channel = range.channels.firstOrNull() ?: return null
            val q8 = uac2ReadQ8(conn, UAC_GET_CUR, range.unitId, range.interfaceNumber, channel)
                ?: return null
            mapOf(
                "q8" to q8,
                "db" to q8 / 256.0,
                "position" to uac2Q8ToPosition(q8, range),
                "minQ8" to range.minQ8,
                "maxQ8" to range.maxQ8,
                "resQ8" to range.resQ8,
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun setUac2HardwareVolumeInternal(position: Double): Boolean {
        return try {
            val device = openedDevice ?: findAudioDevice() ?: return false
            if (usbManager?.hasPermission(device) != true) return false
            val conn = ensureConnection(device) ?: return false
            val parsed = parsedResult ?: return false
            val range = ensureUac2Range(conn, device, parsed) ?: return false
            val target = uac2PositionToQ8(position, range)
            val payload = byteArrayOf(
                (target and 0xFF).toByte(),
                ((target shr 8) and 0xFF).toByte(),
            )
            for (channel in range.channels) {
                val sent = uac2Transfer(
                    conn, 0x21, UAC_SET_CUR, range.unitId, range.interfaceNumber, channel, payload,
                )
                if (sent != payload.size) return false
            }
            // Same tolerance as the db path: +/-1 LSB (1/256 dB) is device
            // quantisation, a whole resolution step is a refused write.
            for (channel in range.channels) {
                val readBack = uac2ReadQ8(
                    conn, UAC_GET_CUR, range.unitId, range.interfaceNumber, channel,
                )
                if (readBack == null || (readBack - target) !in -1..1) return false
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ---- native DSD (DSD_U32 over the isochronous OUT endpoint) ----

    /** True while the live stream was opened as native DSD and the sink is up. */
    val isDsdActive: Boolean
        get() = streaming && activeRenderMode == RENDER_MODE_DSD && isNativeActive()

    /**
     * Probes one raw configuration descriptor blob for native-DSD alternate
     * settings. Never throws: a missing native library or a JNI failure answers
     * null, and an output length that is not a multiple of 7 answers null too
     * rather than reporting a half-parsed tuple.
     */
    private fun probeDsdAltSettingsInternal(rawConfig: ByteArray?): List<DsdAltSettingTuple>? {
        if (!nativeLoaded || rawConfig == null || rawConfig.isEmpty()) return null
        return try {
            val flat = nativeProbeDsdAltSettings(rawConfig) ?: return null
            if (flat.isEmpty()) return emptyList()
            if (flat.size % 7 != 0) return null
            val tuples = ArrayList<DsdAltSettingTuple>(flat.size / 7)
            var index = 0
            while (index + 6 < flat.size) {
                tuples.add(
                    DsdAltSettingTuple(
                        interfaceNumber = flat[index],
                        altSetting = flat[index + 1],
                        endpointAddress = flat[index + 2],
                        channels = flat[index + 3],
                        bytesPerSample = flat[index + 4],
                        framesPerSecond = flat[index + 5],
                        dsdRate = flat[index + 6],
                    ),
                )
                index += 7
            }
            tuples
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Feeds one stereo native-DSD block (DSF order, LSB-first). The sink accepts
     * at most 1 MiB per channel per call and refuses a block that does not fit
     * the ring whole, so false means "retry later", not a fault. Safe to call
     * from any thread; never throws.
     */
    fun writeDsd(left: ByteArray, right: ByteArray, producerId: Long = DSD_PRODUCER_ID): Boolean {
        if (!nativeLoaded || !isDsdActive) return false
        if (left.isEmpty() || left.size != right.size) return false
        if (left.size > MAX_DSD_BYTES_PER_CALL) return false
        val id = if (producerId != 0L) producerId else DSD_PRODUCER_ID
        return try {
            nativeUsbStreamWriteDsd(left, right, left.size, id)
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Opens the sink in native-DSD mode. Mirrors [startStreamingInternal]'s
     * ordering — single-owner guard, drain, claim, alt setting, clock, native
     * start — with the wire shape fixed by the prober's tuple: the alternate
     * setting is selected before Open() and the clock is programmed to its
     * framesPerSecond through the same [setDacSampleRate] path, so a duplicate
     * SET_INTERFACE never resets the DAC clock.
     */
    private fun startDsdStreamingInternal(
        tuple: DsdAltSettingTuple,
        strict: Boolean = true,
    ): Map<String, Any?> {
        val sampleRate = tuple.framesPerSecond
        // Admission before any device state is touched: UsbAudioSink::CheckStreamShape
        // would otherwise reject the shape only after the interface was claimed
        // and the DAC clock had already been reprogrammed.
        if (tuple.channels != DSD_CHANNELS ||
            tuple.bytesPerSample != DSD_BYTES_PER_SAMPLE ||
            (tuple.endpointAddress and 0x80) != 0 ||
            sampleRate !in DSD_U32_RATES ||
            tuple.dsdRate <= 0
        ) {
            lastStreamResultCode = 3
            Log.w(TAG, "Step dsd_probe: refused DSD tuple $tuple")
            return startFailure("dsd_format_unsupported")
        }
        val owner = directOwner
        if (owner != null && owner !== this) {
            lastStreamResultCode = -1
            Log.w(TAG, "Step owner: direct streaming is owned by another plugin instance")
            return startFailure("direct_owner_busy")
        }
        // Same single-owner rule as PCM: one stream, one mode, one owner.
        if (streaming && activeRenderMode == RENDER_MODE_DSD &&
            streamFormat?.matches(sampleRate, DSD_VALID_BIT_DEPTH, DSD_CHANNELS, isNativeActive()) == true
        ) {
            val current = buildStatus()
            if (current["streamingActive"] == true) {
                lastStreamResultCode = 0
                cachedStatus = current
                emitState()
                return current + mapOf("success" to true, "resultCode" to 0)
            }
        }
        if (!clearStreaming()) {
            Log.w(TAG, "Step drain: previous USB stream still has outstanding URBs; forcing teardown")
            if (!clearStreaming(releaseOnDrainFailure = true)) {
                lastStreamResultCode = -1
                Log.w(TAG, "Step drain: forced teardown could not release the previous USB stream")
                return startFailure("usb_drain_incomplete")
            }
            Log.i(TAG, "Step drain: forced teardown released the stale USB stream")
        }
        sessionReset()
        if (!nativeLoaded) {
            lastStreamResultCode = -1
            Log.w(TAG, "Step native: native library not available")
            return startFailure("native_unavailable")
        }
        val device = findAudioDevice() ?: run {
            lastStreamResultCode = -1
            Log.w(TAG, "Step device: no USB audio device found")
            return startFailure("no_usb_device")
        }
        if (usbManager?.hasPermission(device) != true) {
            lastStreamResultCode = 1
            Log.w(TAG, "Step permission: USB access permission required")
            return startFailure("permission_required")
        }
        sessionPermissionRequested()
        sessionPermissionGranted()
        val conn = ensureConnection(device) ?: run {
            lastStreamResultCode = 1
            Log.w(TAG, "Step open: failed to open USB device connection")
            return startFailure("open_failed")
        }
        sessionOpened()
        recordEvent(resultCode = 0)
        val parsed = parseViaRawDescriptors(conn) ?: run {
            lastStreamResultCode = 3
            Log.w(TAG, "Step descriptors: format descriptors required")
            return startFailure("format_descriptors_required")
        }
        if (parsed.uacVersion == UsbAudioControlParser.UAC3) {
            lastStreamResultCode = 3
            Log.w(TAG, "Step uac: UAC3 is not supported for native DSD")
            return startFailure("uac3_unsupported")
        }
        var iface: UsbInterface? = null
        for (index in 0 until device.interfaceCount) {
            val candidate = device.getInterface(index)
            if (candidate.id == tuple.interfaceNumber && candidate.alternateSetting == tuple.altSetting) {
                iface = candidate
                break
            }
        }
        val streamingIface = iface ?: run {
            lastStreamResultCode = 5
            Log.w(TAG, "Step alt_setting: probed DSD interface/alt not found (result 5)")
            return startFailure("streaming_interface_not_found")
        }
        // The parser's own record of this alt setting when it saw one (it does
        // for FORMAT_TYPE_I 32-bit alts); otherwise the probed values are the
        // only description available.
        val altFormat = parsed.altSettingFormats.firstOrNull {
            it.interfaceNumber == tuple.interfaceNumber &&
                it.altSetting == tuple.altSetting &&
                it.endpointAddress == tuple.endpointAddress
        } ?: UsbAudioControlParser.AltSettingFormat(
            interfaceNumber = tuple.interfaceNumber,
            altSetting = tuple.altSetting,
            endpointAddress = tuple.endpointAddress,
            maxPacketSize = 0,
            subslotSize = DSD_BYTES_PER_SAMPLE,
            bitResolution = DSD_VALID_BIT_DEPTH,
            channels = DSD_CHANNELS,
            feedbackEndpointAddress = null,
            supportedRates = emptyList(),
        )
        var started = false
        try {
            releaseClaim()
            try {
                com.ryanheise.just_audio.PulsrOutputRouting.select(null)
            } catch (_: Throwable) {}
            val claimed = try { conn.claimInterface(streamingIface, true) } catch (_: Exception) { false }
            if (!claimed) {
                lastStreamResultCode = 1
                Log.w(TAG, "Step claim: failed to claim DSD streaming interface (result 1)")
                rebindKernelDriver(conn, streamingIface, null)
                return startFailure("claim_failed")
            }
            claimedStreamingInterface = streamingIface
            streamAltSetting = tuple.altSetting
            streamEndpoint = tuple.endpointAddress
            sessionClaimed()
            claimControlInterface(conn, device, parsed)
            refreshAdvertisedRates(conn)
            if (!conn.setInterface(streamingIface)) {
                lastStreamResultCode = 2
                Log.w(TAG, "Step alt_setting: failed to set DSD alternate setting (result 2)")
                return startFailure("alt_setting_failed")
            }
            when (setDacSampleRate(conn, parsed, altFormat, sampleRate, null)) {
                UsbAudioProtocol.RateSetResult.SELECTOR_RESTORE_FAILED -> {
                    lastStreamResultCode = 3
                    Log.w(TAG, "Step clock: clock selector could not be restored (result 3)")
                    return startFailure("clock_selector_restore_failed")
                }

                UsbAudioProtocol.RateSetResult.FAILED -> {
                    lastStreamResultCode = 3
                    Log.w(TAG, "Step clock: clock not verified (result 3)")
                    return startFailure("clock_not_verified")
                }

                UsbAudioProtocol.RateSetResult.UNVERIFIED_READBACK_UNSUPPORTED -> {
                    Log.i(TAG, "Step clock: UAC1 rate set succeeded, readback unsupported")
                    if (strict) {
                        lastStreamResultCode = 3
                        Log.w(TAG, "Step clock: strict DSD refused unverified readback (result 3)")
                        return startFailure("uac1_rate_readback_unsupported")
                    }
                    lastRateVerified = false
                }

                UsbAudioProtocol.RateSetResult.VERIFIED -> {
                    lastRateVerified = true
                    recordEvent(
                        resultCode = 0,
                        rate = sampleRate,
                        depth = DSD_VALID_BIT_DEPTH,
                        channels = DSD_CHANNELS,
                        interfaceNumber = tuple.interfaceNumber,
                        altSetting = tuple.altSetting,
                        endpoint = tuple.endpointAddress,
                        selectorPin = 0,
                    )
                }
            }
            sessionConfigured()
            refreshAdvertisedRates(conn)
            val fd = conn.fileDescriptor
            if (fd < 0) {
                lastStreamResultCode = 5
                Log.w(TAG, "Step native_start: invalid file descriptor (result 5)")
                return startFailure("no_fd")
            }
            // 0/0/false: DSD never inherits a quirk profile's transfer tuning.
            applyStreamTuning(null)
            val resultCode = try {
                nativeUsbStreamStartWithFormat(
                    fd, tuple.endpointAddress, tuple.interfaceNumber, tuple.altSetting,
                    sampleRate, DSD_CHANNELS, DSD_BYTES_PER_SAMPLE, DSD_VALID_BIT_DEPTH,
                    RENDER_MODE_DSD,
                )
            } catch (_: Throwable) {
                -1
            }
            lastStreamResultCode = resultCode
            if (resultCode != 0 || !isNativeActive()) {
                Log.w(TAG, "Step native_start: native DSD start failed with result $resultCode")
                return startFailure("native_stream_not_active") + mapOf("resultCode" to resultCode)
            }
            streamFormat = UsbAudioProtocol.StreamFormat(
                sampleRate, DSD_VALID_BIT_DEPTH, DSD_CHANNELS,
                wireBitDepth = DSD_VALID_BIT_DEPTH, wireChannels = DSD_CHANNELS,
            )
            streaming = true
            activeRenderMode = RENDER_MODE_DSD
            activeQuirks = null
            directStatus = DirectStreamStatus(
                device.deviceId, deviceLabel(device), sampleRate, DSD_VALID_BIT_DEPTH, DSD_CHANNELS,
            )
            directOwner = this
            sessionStarted()
            recordEvent(resultCode = 0)
            val status = buildStatus()
            started = status["streamingActive"] == true && isNativeActive()
            if (!started) return startFailure("native_stream_not_active")
            emitState()
            return status + mapOf("success" to true, "resultCode" to 0)
        } catch (e: Throwable) {
            Log.w(TAG, "USB DSD startup failed: ${e.message}")
            lastStreamResultCode = -1
            return startFailure("stream_start_failed")
        } finally {
            if (!started) clearStreaming()
        }
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
            "drainPending" to drainPending,
        )

    // ---- raw UAC2 isochronous streaming ----

    private fun startStreamingInternal(
        sampleRate: Int,
        channels: Int,
        bitDepth: Int = 16,
        strict: Boolean = false,
        renderMode: Int = 0,
    ): Map<String, Any?> {
        val mode = renderMode.coerceIn(0, MAX_RENDER_MODE)
        if (mode == RENDER_MODE_DSD) {
            // Native DSD needs the prober's alternate setting; a plain PCM
            // start never has one, so it must not open mode 3 with a PCM shape.
            lastStreamResultCode = 3
            return startFailure("dsd_requires_alt_setting")
        }
        lastRequestedRate = sampleRate
        lastRequestedDepth = bitDepth
        lastRequestedChannels = channels
        val owner = directOwner
        if (owner != null && owner !== this) {
            lastStreamResultCode = -1
            Log.w(TAG, "Step owner: direct streaming is owned by another plugin instance")
            return startFailure("direct_owner_busy")
        }
        // A restart is only skipped for the same format *and* the same render
        // mode: switching bit-perfect on for an already-open stream has to
        // reopen it, otherwise the sink keeps the mode it was opened with.
        if (streaming && activeRenderMode == mode &&
            streamFormat?.matches(sampleRate, bitDepth, channels, isNativeActive()) == true
        ) {
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
        // A previous stream must be fully drained before any interface is
        // reclaimed: releasing or rebinding with outstanding URBs corrupts the
        // kernel driver's view of the endpoint. Refuse the start instead.
        if (!clearStreaming()) {
            // The previous stream's URBs could not be reaped, so its interface
            // claims were kept. Recovery path: abandon that unprovable native
            // state once so the claims can be released and this start can claim
            // the endpoint again. Never forced on a healthy start.
            Log.w(TAG, "Step drain: previous USB stream still has outstanding URBs; forcing teardown")
            if (!clearStreaming(releaseOnDrainFailure = true)) {
                lastStreamResultCode = -1
                Log.w(TAG, "Step drain: forced teardown could not release the previous USB stream")
                return startFailure("usb_drain_incomplete")
            }
            Log.i(TAG, "Step drain: forced teardown released the stale USB stream")
        }
        // A start always begins a fresh session. The previous one may have been
        // left ERROR/ABANDONED by a fault; nothing is claimed at this point
        // (clearStreaming above released it), so IDLE is the honest state.
        sessionReset()
        if (!nativeLoaded) {
            lastStreamResultCode = -1
            Log.w(TAG, "Step native: native library not available")
            return startFailure("native_unavailable")
        }
        val device = findAudioDevice() ?: run {
            lastStreamResultCode = -1
            Log.w(TAG, "Step device: no USB audio device found")
            return startFailure("no_usb_device")
        }
        if (usbManager?.hasPermission(device) != true) {
            lastStreamResultCode = 1
            Log.w(TAG, "Step permission: USB access permission required")
            return startFailure("permission_required")
        }
        // The permission grant survives from an earlier prompt; model the
        // admission so the machine reaches OPENING legally.
        sessionPermissionRequested()
        sessionPermissionGranted()
        val conn = ensureConnection(device) ?: run {
            lastStreamResultCode = 1
            Log.w(TAG, "Step open: failed to open USB device connection")
            return startFailure("open_failed")
        }
        sessionOpened()
        recordEvent(resultCode = 0)
        val parsed = parseViaRawDescriptors(conn) ?: run {
            lastStreamResultCode = 3
            Log.w(TAG, "Step descriptors: format descriptors required")
            return startFailure("format_descriptors_required")
        }
        if (parsed.uacVersion == UsbAudioControlParser.UAC3) {
            lastStreamResultCode = 3
            Log.w(TAG, "Step uac: UAC3 is not supported for bit-perfect streaming")
            return startFailure("uac3_unsupported")
        }
        // Quirks are resolved *before* the alt setting is chosen: force16Bit
        // has to change the request, or a 24-bit FORMAT_TYPE would be selected
        // and the quirk would silently do nothing. A rejected entry only lands
        // in the event log; it never blocks the stream.
        val facts = deviceFacts(device, parsed, sampleRate, bitDepth, channels)
        val resolved = resolveQuirks(device, facts)
        publishQuirks(parsed, resolved)
        val effectiveRate = resolved.effectiveRate
        val effectiveDepth = resolved.effectiveDepth
        val effectiveChannels = resolved.effectiveChannels
        // Strict mode promises the source unchanged. A quirk that truncates the
        // depth or leaves the DAC clock unprogrammed cannot keep that promise,
        // so refuse before opening instead of starting a stream the contract
        // does not cover.
        if (strict && effectiveDepth < bitDepth) {
            lastStreamResultCode = 3
            Log.w(TAG, "Step quirk: strict mode refuses force16Bit truncation")
            return startFailure("format_unsupported")
        }
        if (strict && resolved.disableUac2ClockSwitch &&
            parsed.uacVersion == UsbAudioControlParser.UAC2
        ) {
            lastStreamResultCode = 3
            Log.w(TAG, "Step quirk: strict mode refuses an unprogrammed UAC2 clock")
            return startFailure("clock_not_verified")
        }
        val selected = UsbAudioProtocol.selectFormat(
            parsed, effectiveRate, effectiveDepth, effectiveChannels,
        ) ?: run {
            lastStreamResultCode = 3
            Log.w(TAG, "Step selectFormat: format unsupported: rate=$effectiveRate, " +
                "depth=$effectiveDepth, channels=$effectiveChannels")
            return startFailure("format_unsupported")
        }
        val epAddress = selected.endpointAddress
        val epInterface = selected.interfaceNumber
        val epAlt = selected.altSetting
        val streamBytes = selected.subslotSize
        val wireChannels = selected.channels.takeIf { it > 0 } ?: effectiveChannels

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
            return startFailure("streaming_interface_not_found")
        }

        releaseClaim()
        // Unpin ExoPlayer's silent pacing AudioTrack from the USB HAL before
        // detaching snd-usb-audio: if it stayed pinned to the stolen USB device,
        // AudioFlinger HAL write timeouts would throttle ExoPlayer's playback
        // thread and starve the USB ring (glitchy/slow audio).
        try {
            com.ryanheise.just_audio.PulsrOutputRouting.select(null)
        } catch (_: Throwable) {}
        val claimed = try { conn.claimInterface(iface, true) } catch (_: Exception) { false }
        if (!claimed) {
            lastStreamResultCode = 1
            Log.w(TAG, "Step claim: failed to claim streaming interface (result 1)")
            rebindKernelDriver(conn, iface, null)
            return startFailure("claim_failed")
        }
        claimedStreamingInterface = iface
        streamAltSetting = epAlt
        streamEndpoint = epAddress
        sessionClaimed()
        claimControlInterface(conn, device, parsed)
        // Audio Control is claimed now, so a UAC2 clock range can be read. A
        // refusal must never fail the stream: it only means "unknown".
        refreshAdvertisedRates(conn)
        var started = false
        try {
            if (!conn.setInterface(iface)) {
                lastStreamResultCode = 2
                Log.w(TAG, "Step alt_setting: failed to set alternate setting (result 2)")
                return startFailure("alt_setting_failed")
            }
            // A profile may deliberately leave the DAC's clock switch alone
            // (broken UAC2 clock graphs switch the whole device off when
            // reprogrammed). The rate is then simply not verified.
            val clockSkipped = resolved.disableUac2ClockSwitch &&
                parsed.uacVersion == UsbAudioControlParser.UAC2
            val rateResult = if (clockSkipped) {
                lastRateVerified = false
                Log.i(TAG, "Step clock: UAC2 clock switching disabled by quirk profile")
                recordEvent(
                    lastError = "clock_switch_disabled",
                    resultCode = 0,
                    rate = effectiveRate,
                    depth = effectiveDepth,
                    channels = wireChannels,
                    interfaceNumber = epInterface,
                    altSetting = epAlt,
                    endpoint = epAddress,
                    selectorPin = resolved.preferredSelectorPin ?: 0,
                )
                null
            } else {
                setDacSampleRate(conn, parsed, selected, effectiveRate, resolved.preferredSelectorPin)
            }
            if (rateResult == UsbAudioProtocol.RateSetResult.SELECTOR_RESTORE_FAILED) {
                // The clock selector was left pointing at the source that just
                // failed and both restore attempts were refused: this is not a
                // "rate unsupported" answer, the DAC's clock is now misrouted.
                lastStreamResultCode = 3
                Log.w(TAG, "Step clock: clock selector could not be restored (result 3)")
                return startFailure("clock_selector_restore_failed")
            }
            if (rateResult == UsbAudioProtocol.RateSetResult.FAILED) {
                lastStreamResultCode = 3
                Log.w(TAG, "Step clock: clock not verified (result 3)")
                return startFailure("clock_not_verified")
            }
            if (rateResult == UsbAudioProtocol.RateSetResult.UNVERIFIED_READBACK_UNSUPPORTED) {
                Log.i(TAG, "Step clock: UAC1 sample-rate set succeeded, readback unsupported")
                if (strict) {
                    lastStreamResultCode = 3
                    Log.w(TAG, "Step clock: strict mode refused unverified readback (result 3)")
                    return startFailure("uac1_rate_readback_unsupported")
                }
                lastRateVerified = false
            } else if (rateResult != null) {
                lastRateVerified = true
            }
            if (rateResult != null) {
                recordEvent(
                    resultCode = 0,
                    rate = effectiveRate,
                    depth = effectiveDepth,
                    channels = wireChannels,
                    interfaceNumber = epInterface,
                    altSetting = epAlt,
                    endpoint = epAddress,
                    selectorPin = resolved.preferredSelectorPin ?: 0,
                )
            }
            sessionConfigured()
            // Clock programmed: re-read the advertised rates (a UAC2 range is
            // only readable while the AC interface is claimed). Best effort.
            refreshAdvertisedRates(conn)
            val fd = conn.fileDescriptor
            if (fd < 0) {
                lastStreamResultCode = 5
                Log.w(TAG, "Step native_start: invalid file descriptor (result 5)")
                return startFailure("no_fd")
            }
            // Always pushed - 0/0/false when no profile is stored - so a profile
            // from a previous device can never leak into this stream.
            applyStreamTuning(resolved)
            val silenceMs = resolved.silenceMs.coerceIn(0, MAX_QUIRK_SILENCE_MS)
            if (silenceMs > 0) {
                Log.i(TAG, "Quirk silence: waiting ${silenceMs}ms before native start")
                try {
                    Thread.sleep(silenceMs.toLong())
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
            val resultCode = nativeUsbStreamStartWithFormat(
                fd, epAddress, epInterface, epAlt, effectiveRate, wireChannels, streamBytes,
                selected.bitResolution, mode,
            )
            lastStreamResultCode = resultCode
            if (resultCode != 0 || !isNativeActive()) {
                Log.w(TAG, "Step native_start: native start failed with result $resultCode")
                return startFailure("native_stream_not_active") + mapOf("resultCode" to resultCode)
            }
            // The request is remembered as the request (see StreamFormat): a
            // 16-bit track whose endpoint was opened at 24-bit must be
            // recognised as the same stream on the next track change. The
            // *effective* depth is stored, so a force16Bit profile keeps
            // matching 16-bit requests instead of reopening on every track.
            streamFormat = UsbAudioProtocol.StreamFormat(
                effectiveRate, effectiveDepth, effectiveChannels,
                wireBitDepth = selected.bitResolution, wireChannels = wireChannels,
            )
            streaming = true
            activeRenderMode = mode
            activeQuirks = resolved
            directStatus = DirectStreamStatus(device.deviceId, deviceLabel(device),
                effectiveRate, selected.bitResolution, wireChannels)
            directOwner = this
            sessionStarted()
            recordEvent(resultCode = 0)
            val status = buildStatus()
            started = status["streamingActive"] == true && isNativeActive()
            if (!started) return startFailure("native_stream_not_active")
            emitState()
            return status + mapOf("success" to true, "resultCode" to 0)
        } catch (e: Throwable) {
            Log.w(TAG, "USB streaming startup failed: ${e.message}")
            lastStreamResultCode = -1
            return startFailure("stream_start_failed")
        } finally {
            // An incomplete drain here sets drainPending and keeps the claims;
            // the next start then refuses with usb_drain_incomplete.
            if (!started) clearStreaming()
        }
    }

    /**
     * Programs the playback sample clock through the protocol layer, which
     * resolves the clock actually wired to the playback terminal, checks its
     * validity and can switch a UAC2 Clock Selector pin when the current source
     * cannot deliver [sampleRate] (the original pin is restored on failure).
     * UAC1 has no clock entity and keeps its endpoint SET_CUR path.
     */
    private fun setDacSampleRate(
        conn: UsbDeviceConnection,
        parsed: UsbAudioControlParser.Result,
        selected: UsbAudioControlParser.AltSettingFormat,
        sampleRate: Int,
        preferredSelectorPin: Int? = null,
    ): UsbAudioProtocol.RateSetResult {
        val fixedUac1 = selected.supportedRates.size == 1 || !selected.sampleRateControlSupported
        return UsbAudioProtocol.programPlaybackClock(
            transport(conn), parsed, selected.endpointAddress, sampleRate, fixedUac1,
            preferredSelectorPin,
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

    /**
     * Releases claimed streaming and control interfaces cleanly and re-attaches
     * Linux's `snd-usb-audio` driver in probe order:
     *  1. Select alt-setting 0 on AudioStreaming while still claimed so the DAC
     *     closes its isochronous OUT pipe cleanly.
     *  2. Release AudioStreaming and AudioControl from usbfs.
     *  3. Issue `USBDEVFS_CONNECT` on AudioControl FIRST (snd-usb-audio's
     *     primary probe interface, which re-claims all streaming interfaces),
     *     then on AudioStreaming as a fallback.
     */
    private fun rebindKernelDriver(
        conn: UsbDeviceConnection,
        streamingIface: UsbInterface?,
        controlIface: UsbInterface?,
    ) {
        val device = openedDevice
        if (streamingIface != null) {
            if (device != null) {
                val idle = (0 until device.interfaceCount).map { device.getInterface(it) }
                    .firstOrNull { it.id == streamingIface.id && it.alternateSetting == 0 }
                if (idle != null) try { conn.setInterface(idle) } catch (_: Exception) {}
            }
            try { conn.releaseInterface(streamingIface) } catch (_: Exception) {}
        }
        if (controlIface != null) {
            try { conn.releaseInterface(controlIface) } catch (_: Exception) {}
        }
        if (nativeLoaded) {
            val fd = try { conn.fileDescriptor } catch (_: Exception) { -1 }
            if (fd >= 0) {
                if (controlIface != null) {
                    try { nativeUsbRebindInterface(fd, controlIface.id) } catch (_: Throwable) {}
                }
                if (streamingIface != null) {
                    try { nativeUsbRebindInterface(fd, streamingIface.id) } catch (_: Throwable) {}
                }
            }
        }
    }

    /**
     * Stops the native isochronous sink, then releases the claimed interfaces
     * and re-attaches `snd-usb-audio` only when the bounded teardown confirmed
     * that every submitted URB was reaped.
     *
     * `nativeUsbStreamStop()` returns false when URBs are still outstanding; the
     * sink then keeps its URB storage and HAL exclusivity. Releasing the
     * interface or issuing USBDEVFS_CONNECT in that state would hand a
     * half-torn-down pipe to the kernel driver, so the claims and the open
     * connection are kept and [drainPending] is set instead - the next stop
     * retries. Only [releaseOnDrainFailure] (dispose / detach / close) forces the
     * release, because the process or the device is going away anyway; it first
     * abandons the unprovable native sink state so the next Open starts clean.
     *
     * @return true when the drain succeeded (or the sink was abandoned) and the
     *     exclusive path was released, false when outstanding URBs block a clean
     *     release.
     */
    private fun clearStreaming(releaseOnDrainFailure: Boolean = false): Boolean {
        val previousFormat = streamFormat
        val previousQuirks = activeQuirks
        val sessionWasStreaming = sessionStateIs(UsbSessionState.STREAMING)
        if (sessionWasStreaming) {
            // The stop is requested before the (blocking) native drain: the
            // machine must not keep claiming STREAMING while the endpoint closes.
            sessionStep("stop_requested") { machine, now -> machine.onStopRequested(now) }
            recordEvent(resultCode = 0, format = previousFormat)
        }
        val sessionDraining = sessionWasStreaming || sessionStateIs(UsbSessionState.DRAINING)
        // A missing native library means nothing was ever submitted, so the
        // drain is trivially complete. A throwing JNI call is not evidence that
        // the URBs were reaped and is treated as a failed drain.
        val drained = if (nativeLoaded) {
            try { nativeUsbStreamStop() } catch (_: Throwable) { false }
        } else {
            true
        }
        // Logical streaming state goes away either way: the sink is no longer
        // producing audio even when its URBs could not be reaped.
        directStatus = null
        if (directOwner === this) directOwner = null
        streaming = false
        streamFormat = null
        lastRateVerified = false
        if (!drained && !releaseOnDrainFailure) {
            drainPending = true
            if (sessionDraining) {
                sessionStep("drain_failed") { machine, now -> machine.onDrainFailed(now) }
            }
            recordEvent(lastError = "drain_incomplete", format = previousFormat)
            Log.w(TAG, "USB stream stop left URBs outstanding; keeping interfaces claimed")
            return false
        }
        var abandoned = false
        if (!drained) {
            // The caller is about to release the interface and close the
            // connection, so nothing on this fd can ever be reaped. Abandon()
            // deliberately leaks that URB storage, withdraws the sink-depth /
            // direct-USB publication and resets fd_/exclusive_; without it every
            // later Open would drain the dead fd and fail with ClaimFailed. A
            // throwing call leaves the sink in its retained state, which is the
            // honest outcome.
            abandoned = if (nativeLoaded) {
                try {
                    nativeUsbStreamAbandon()
                    true
                } catch (e: Throwable) {
                    Log.w(TAG, "USB stream abandon failed: ${e.message}")
                    false
                }
            } else {
                false
            }
            Log.w(
                TAG,
                if (abandoned) {
                    "USB stream stop left URBs outstanding; abandoned native sink, releasing on teardown"
                } else {
                    "USB stream stop left URBs outstanding; releasing on teardown anyway"
                },
            )
        }
        val iface = claimedStreamingInterface
        claimedStreamingInterface = null
        val control = claimedControlInterface
        claimedControlInterface = null
        val conn = connection
        // altResetOnStop: close the DAC's isochronous pipe with an explicit
        // SET_INTERFACE(alt 0) before the claim is released. Best effort - the
        // interface is about to be handed back either way - but the outcome is
        // recorded, because a DAC that ignores it can click on every stop.
        if (previousQuirks?.altResetOnStop == true && iface != null && conn != null) {
            val reset = resetStreamingAlt(conn, iface)
            Log.i(TAG, "altResetOnStop: alternate setting 0 " +
                (if (reset) "selected before release" else "refused before release"))
            recordEvent(
                lastError = if (reset) null else "alt_reset_on_stop_failed",
                format = previousFormat,
            )
        }
        if ((iface != null || control != null) && conn != null) {
            rebindKernelDriver(conn, iface, control)
        }
        // An abandoned sink holds no URBs and no fd, so nothing is pending
        // any more; only a forced teardown that could not abandon stays flagged.
        drainPending = !drained && !abandoned
        if (sessionDraining) {
            when {
                abandoned -> {
                    // The native sink was abandoned because its URBs could not be
                    // reaped; the session ends ABANDONED, not cleanly drained.
                    sessionStep("abandon") { machine, now -> machine.onAbandon(now) }
                    recordEvent(resultCode = 0, format = previousFormat)
                }

                drained -> sessionStep("drain_succeeded") { machine, now ->
                    machine.onDrainSucceeded(now)
                }

                else -> sessionStep("drain_failed") { machine, now -> machine.onDrainFailed(now) }
            }
        }
        activeQuirks = null
        activeRenderMode = 0
        streamAltSetting = 0
        streamEndpoint = 0
        if (previousFormat != null || sessionDraining || previousQuirks != null) {
            // Only a teardown that actually had something to tear down is worth
            // an event; the no-op probe at the top of every start stays silent.
            recordEvent(
                lastError = if (drained || abandoned) null else "drain_pending",
                format = previousFormat,
            )
        }
        // A forced teardown that could not abandon leaves the native sink
        // retaining URBs: the interfaces are released, but the next Open would
        // still fail, so report that instead of claiming a clean teardown.
        return drained || abandoned
    }

    /**
     * After re-attaching `snd-usb-audio`, Android's `UsbAlsaManager` and
     * `AudioFlinger` re-enumerate the USB output device asynchronously
     * (typically 100-400 ms). Waiting briefly on the worker thread before
     * returning from `stopStreaming` ensures the AudioTrack rebuild finds the
     * live ALSA USB endpoint instead of opening into silence.
     */
    private fun awaitAlsaUsbRecovery(timeoutMs: Long = 600L) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val am = audioManager ?: return
        // Only wait when the physical USB device is still attached.
        val attached = openedDevice?.let { open ->
            usbManager?.deviceList?.values?.any { it.deviceId == open.deviceId } == true
        } ?: false
        if (!attached) return
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            val hasUsb = try {
                am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        it.type == AudioDeviceInfo.TYPE_USB_HEADSET
                }
            } catch (_: Throwable) {
                true
            }
            if (hasUsb) {
                // Give AudioFlinger one brief tick to finish activating the route.
                try { Thread.sleep(40L) } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
                return
            }
            try {
                Thread.sleep(25L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
    }

    private fun stopStreamingInternal(): Map<String, Any?> {
        val hadClaims = claimedStreamingInterface != null || claimedControlInterface != null
        val drained = clearStreaming()
        lastStreamResultCode = null
        if (!drained) {
            // Interfaces and the connection are still held: waiting for ALSA to
            // recover would look at a device the kernel driver has not been
            // given back, so report the honest failure instead.
            emitState()
            return failure("usb_drain_incomplete")
        }
        if (hadClaims) {
            awaitAlsaUsbRecovery()
        }
        emitState()
        return buildStatus() + mapOf("success" to true)
    }

    /**
     * Blocking: opens the device, asks the DAC itself for its playback rates
     * (UAC1 FORMAT_TYPE descriptors / UAC2 clock range) and returns only what
     * was actually reported. Always invoked on the worker thread via runAsync.
     */
    private fun querySupportedRatesInternal(): List<Int> {
        val device = openedDevice ?: findAudioDevice()
        if (device == null || usbManager?.hasPermission(device) != true) {
            return advertisedRates
        }
        val conn = ensureConnection(device) ?: return advertisedRates
        return refreshAdvertisedRates(conn)
    }

    @Synchronized
    private fun closeLocked() {
        // Teardown path (detach / dispose / device swap): release even when the
        // drain cannot be confirmed, otherwise the claim would outlive us.
        clearStreaming(releaseOnDrainFailure = true)
        directStreamingSupported = false
        releaseClaim()
        try { connection?.close() } catch (_: Exception) {}
        connection = null
        openedDevice = null
        volumeUnit = null
        uacVersion = UsbAudioControlParser.UAC_NONE
        streamInterfaceNumber = null
        parsedResult = null
        advertisedRates = emptyList()
        hardwareVolume?.invalidate()
        hardwareVolume = null
        clearUac2RangeCache()
        cachedStatus = baseStatus(attached = false, permitted = false, device = null)
            .toMutableMap()
            .also { it["drainPending"] = drainPending }
    }
}

