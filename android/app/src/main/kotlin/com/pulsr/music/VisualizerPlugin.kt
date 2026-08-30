package com.pulsr.music

import android.Manifest
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.hypot

class VisualizerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var visualizer: Visualizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var context: android.content.Context? = null

    companion object {
        const val METHOD_CHANNEL = "com.pulsr.music/visualizer"
        const val EVENT_CHANNEL = "com.pulsr.music/visualizer_stream"

        fun registerWith(flutterEngine: FlutterEngine): VisualizerPlugin {
            val plugin = VisualizerPlugin()
            plugin.methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            plugin.methodChannel.setMethodCallHandler(plugin)

            plugin.eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            plugin.eventChannel.setStreamHandler(plugin)
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    fun cleanup() {
        stopVisualizer()
        if (::methodChannel.isInitialized) {
            methodChannel.setMethodCallHandler(null)
        }
        if (::eventChannel.isInitialized) {
            eventChannel.setStreamHandler(null)
        }
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "start", "setAudioSessionId" -> {
                val audioSessionId = call.argument<Int>("audioSessionId") ?: 0
                // Permission pre-check: Visualizer requires RECORD_AUDIO
                val ctx = context
                if (ctx == null) {
                    result.error("NO_CONTEXT", "Context unavailable (plugin detached)", null)
                    return
                }
                if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    result.error("PERMISSION_DENIED", "RECORD_AUDIO permission not granted", null)
                    return
                }
                stopVisualizer()
                val success = startVisualizer(audioSessionId)
                if (success) {
                    result.success(true)
                } else {
                    // Try global audio session 0 fallback if specific session failed (only if permission still granted)
                    if (audioSessionId != 0) {
                        val fallbackSuccess = startVisualizer(0)
                        if (fallbackSuccess) {
                            result.success(true)
                            return
                        }
                    }
                    result.error("VISUALIZER_UNAVAILABLE", "Failed to start visualizer for session $audioSessionId", null)
                }
            }
            "stop", "releaseVisualizer" -> {
                stopVisualizer()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private var currentSessionId: Int = 0

    private fun startVisualizer(audioSessionId: Int): Boolean {
        // Guard against teardown race where context was nulled
        val ctx = context ?: run {
            android.util.Log.w("VisualizerPlugin", "Context is null, cannot start visualizer")
            return false
        }
        // Early permission guard at start path as well
        if (audioSessionId != 0 && ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            android.util.Log.w("VisualizerPlugin", "RECORD_AUDIO permission not granted, cannot start visualizer")
            return false
        }
        stopVisualizer()
        currentSessionId = audioSessionId
        return try {
            val vis = Visualizer(audioSessionId)
            val captureSizeRange = Visualizer.getCaptureSizeRange()
            if (captureSizeRange != null && captureSizeRange.size >= 2) {
                try {
                    vis.captureSize = captureSizeRange[1] // Use max capture size
                } catch (_: Exception) {
                    try {
                        vis.captureSize = captureSizeRange[0]
                    } catch (_: Exception) {}
                }
            }
            vis.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(
                    visualizer: Visualizer?,
                    waveform: ByteArray?,
                    samplingRate: Int
                ) {}

                override fun onFftDataCapture(
                    visualizer: Visualizer?,
                    fft: ByteArray?,
                    samplingRate: Int
                ) {
                    if (fft == null || fft.size < 4 || eventSink == null) return
                    val n = fft.size
                    val rawBins = n / 2
                    val rawMagnitudes = DoubleArray(rawBins)
                    rawMagnitudes[0] = kotlin.math.abs(fft[0].toInt()).toDouble()

                    for (i in 1 until rawBins) {
                        val real = fft[2 * i].toDouble()
                        val imag = fft[2 * i + 1].toDouble()
                        rawMagnitudes[i] = hypot(real, imag)
                    }

                    // Map raw FFT bins to 32 logarithmic perceptual frequency bands
                    val numBands = 32
                    val bandValues = DoubleArray(numBands)
                    for (b in 0 until numBands) {
                        val bFraction = b.toDouble() / numBands
                        val nextFraction = (b + 1).toDouble() / numBands
                        val startFraction = bFraction * bFraction
                        val endFraction = nextFraction * nextFraction
                        val startBin = (startFraction * (rawBins - 1)).toInt().coerceIn(0, rawBins - 1)
                        val endBin = (endFraction * rawBins).toInt().coerceIn(startBin + 1, rawBins)

                        var sum = 0.0
                        var count = 0
                        for (bin in startBin until endBin) {
                            sum += rawMagnitudes[bin]
                            count++
                        }
                        val avg = if (count > 0) sum / count else 0.0

                        // High-frequency pre-emphasis tilt (+dB slope for higher bands)
                        val tiltMultiplier = 1.0 + (b.toDouble() / numBands) * 1.8
                        val scaled = (avg * tiltMultiplier) / 72.0
                        bandValues[b] = scaled.coerceIn(0.0, 1.0)
                    }

                    val normalizedList = bandValues.toList()
                    mainHandler.post {
                        try {
                            eventSink?.success(normalizedList)
                        } catch (_: Throwable) {}
                    }
                }
            }, Visualizer.getMaxCaptureRate() / 2, false, true)

            vis.enabled = true
            visualizer = vis
            true
        } catch (e: SecurityException) {
            android.util.Log.w("VisualizerPlugin", "Visualizer SecurityException (permission) for session $audioSessionId: ${e.message}")
            false
        } catch (e: Throwable) {
            android.util.Log.w("VisualizerPlugin", "Hardware visualizer unavailable for session $audioSessionId: ${e.message}")
            // Avoid recursive double fallback – caller already tries session 0
            false
        }
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
        } finally {
            visualizer = null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (visualizer == null) {
            startVisualizer(currentSessionId)
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopVisualizer()
    }
}
