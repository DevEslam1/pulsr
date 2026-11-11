package com.pulsr.music

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Phase 5 (room correction): raw microphone capture for the stepped-sine
 * measurement. Streams mono 16-bit PCM blocks over an EventChannel; all
 * analysis (per-tone RMS, response fit) happens Dart-side so the math is
 * unit-testable. UNPROCESSED source is preferred when available so the
 * measurement is not colored by platform AGC/NS; falls back to MIC.
 */
class RoomCorrectionPlugin private constructor(private val appContext: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private val capturing = AtomicBoolean(false)
    private var currentSampleRate: Int = 0
    private val backgroundExecutor = java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PulsrRoomCorrection-bg").apply { isDaemon = true }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCapture" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                startRecording(sampleRate, result)
            }
            "stopCapture" -> {
                stopRecording()
                result.success(true)
            }
            "isCapturing" -> result.success(capturing.get())
            "hasRecordPermission" -> {
                val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                    appContext, android.Manifest.permission.RECORD_AUDIO
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            else -> result.notImplemented()
        }
    }

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    @SuppressLint("MissingPermission")
    private fun startRecording(sampleRate: Int, result: MethodChannel.Result) {
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                appContext, android.Manifest.permission.RECORD_AUDIO
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "PERMISSION_DENIED",
                "RECORD_AUDIO permission is required for room correction",
                null
            )
            return
        }
        if (capturing.get()) {
            val record = audioRecord
            if (currentSampleRate == sampleRate && record != null && record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                result.success(true)
                return
            }
            stopRecording()
        }
        try {
            val minBuf = AudioRecord.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBuf <= 0) {
                result.error("CAPTURE_UNAVAILABLE", "AudioRecord minBufferSize <= 0", null)
                return
            }
            val bufSize = maxOf(minBuf * 4, 16384)
            val supportsUnprocessed = Build.VERSION.SDK_INT >= 24 && runCatching {
                val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                am?.getProperty(android.media.AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
            }.getOrDefault(false)

            fun createRecord(source: Int): AudioRecord? = try {
                AudioRecord(
                    source, sampleRate, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, bufSize
                )
            } catch (_: Throwable) {
                null
            }

            var record: AudioRecord? = if (supportsUnprocessed) {
                createRecord(MediaRecorder.AudioSource.UNPROCESSED)
            } else {
                null
            }
            // A source can be advertised and still fail to initialize on some
            // HALs; only keep UNPROCESSED when it actually reached INITIALIZED.
            if (record != null && record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                record = null
            }
            if (record == null) {
                record = createRecord(MediaRecorder.AudioSource.MIC)
            }
            if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
                record?.release()
                result.error("CAPTURE_UNAVAILABLE", "AudioRecord not initialized (permission?)", null)
                return
            }
            try {
                record.startRecording()
            } catch (e: Throwable) {
                runCatching { record.release() }
                result.error("CAPTURE_FAILED", e.message, null)
                return
            }
            audioRecord = record
            capturing.set(true)
            currentSampleRate = sampleRate
            captureThread = Thread {
                val buf = ByteArray(8192)
                var overrunCount = 0
                try {
                    while (capturing.get() && !Thread.currentThread().isInterrupted) {
                        val n = try {
                            record.read(buf, 0, buf.size)
                        } catch (_: Throwable) {
                            break
                        }
                        if (n < 0) {
                            when (n) {
                                AudioRecord.ERROR_DEAD_OBJECT,
                                AudioRecord.ERROR_INVALID_OPERATION,
                                AudioRecord.ERROR_BAD_VALUE -> {
                                    val code = n
                                    mainHandler.post {
                                        try {
                                            eventSink?.error(
                                                "CAPTURE_ERROR",
                                                "AudioRecord read failed ($code)",
                                                null
                                            )
                                        } catch (_: Exception) {
                                        }
                                    }
                                    break
                                }
                                else -> overrunCount++
                            }
                        } else if (n > 0 && capturing.get()) {
                            val payload = mapOf(
                                "pcm" to buf.copyOf(n),
                                "frames" to n / 2,
                                "overruns" to overrunCount
                            )
                            mainHandler.post {
                                if (capturing.get()) {
                                    try {
                                        eventSink?.success(payload)
                                    } catch (_: Exception) {}
                                }
                            }
                        }
                    }
                } finally {
                    capturing.set(false)
                }
            }.apply {
                name = "PulsrRoomCapture"
                priority = Thread.NORM_PRIORITY + 1
                start()
            }
            result.success(true)
        } catch (e: Throwable) {
            Log.w(TAG, "startCapture failed: ${e.message}")
            capturing.set(false)
            val record = audioRecord
            audioRecord = null
            runCatching { record?.release() }
            result.error("CAPTURE_FAILED", e.message, null)
        }
    }

    private fun stopRecording() {
        capturing.set(false)
        currentSampleRate = 0
        val record = audioRecord
        audioRecord = null

        val thread = captureThread
        captureThread = null
        try {
            thread?.interrupt()
        } catch (_: Throwable) {}

        backgroundExecutor.execute {
            try {
                record?.stop()
            } catch (_: Throwable) {}
            try {
                record?.release()
            } catch (_: Throwable) {}
            try {
                thread?.join(500)
            } catch (_: Throwable) {}
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopRecording()
    }

    fun registerWith(
        flutterEngine: FlutterEngine,
        messenger: BinaryMessenger,
    ): RoomCorrectionPlugin {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(messenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
        return this
    }

    fun cleanup() {
        stopRecording()
        eventSink = null
        if (::methodChannel.isInitialized) methodChannel.setMethodCallHandler(null)
        if (::eventChannel.isInitialized) eventChannel.setStreamHandler(null)
        runCatching { backgroundExecutor.shutdown() }
    }

    companion object {
        const val METHOD_CHANNEL = "com.pulsr.music/room_correction"
        const val EVENT_CHANNEL = "com.pulsr.music/room_correction_pcm"
        const val TAG = "RoomCorrectionPlugin"

        fun registerWith(flutterEngine: FlutterEngine, appContext: Context): RoomCorrectionPlugin {
            val plugin = RoomCorrectionPlugin(appContext)
            return plugin.registerWith(flutterEngine, flutterEngine.dartExecutor.binaryMessenger)
        }
    }
}