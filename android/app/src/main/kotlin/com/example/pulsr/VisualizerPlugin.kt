package com.example.pulsr

import android.media.audiofx.Visualizer
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

    companion object {
        const val METHOD_CHANNEL = "com.example.pulsr/visualizer"
        const val EVENT_CHANNEL = "com.example.pulsr/visualizer_stream"

        fun registerWith(flutterEngine: FlutterEngine) {
            val plugin = VisualizerPlugin()
            plugin.methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            plugin.methodChannel.setMethodCallHandler(plugin)

            plugin.eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            plugin.eventChannel.setStreamHandler(plugin)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopVisualizer()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "start" -> {
                val audioSessionId = call.argument<Int>("audioSessionId") ?: 0
                val success = startVisualizer(audioSessionId)
                if (success) {
                    result.success(true)
                } else {
                    result.error("VISUALIZER_ERROR", "Failed to start visualizer", null)
                }
            }
            "stop" -> {
                stopVisualizer()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startVisualizer(audioSessionId: Int): Boolean {
        stopVisualizer()
        return try {
            val vis = Visualizer(audioSessionId)
            val captureSizeRange = Visualizer.getCaptureSizeRange()
            if (captureSizeRange != null && captureSizeRange.size >= 2) {
                vis.captureSize = captureSizeRange[1] // Use max capture size
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
                    if (fft == null || eventSink == null) return
                    val n = fft.size
                    if (n < 2) return

                    // Process FFT magnitudes: fft[0]=DC, fft[1]=Nyquist
                    // fft[2*i] = real, fft[2*i+1] = imag
                    val numBands = n / 2
                    val magnitudes = DoubleArray(numBands)
                    magnitudes[0] = Math.abs(fft[0].toInt()).toDouble()

                    for (i in 1 until numBands) {
                        val real = fft[2 * i].toDouble()
                        val imag = fft[2 * i + 1].toDouble()
                        magnitudes[i] = hypot(real, imag)
                    }

                    // Normalize values between 0.0 and 1.0
                    val normalized = List(numBands) { idx ->
                        (magnitudes[idx] / 128.0).coerceIn(0.0, 1.0)
                    }

                    eventSink?.success(normalized)
                }
            }, Visualizer.getMaxCaptureRate() / 2, false, true)

            vis.enabled = true
            visualizer = vis
            true
        } catch (e: Exception) {
            android.util.Log.w("VisualizerPlugin", "Hardware visualizer unavailable on this device/emulator: ${e.message}")
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
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopVisualizer()
    }
}
