package com.pulsr.music

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.ByteOrder
import kotlin.math.sqrt

/// Decodes a local audio file to PCM and returns [count] peak-normalized RMS
/// buckets in 0..1, so the seek bar can draw a waveform that reflects the real
/// signal instead of a value fabricated from the song id.
class WaveformPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private val backgroundExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/waveform"
        private const val TAG = "WaveformPlugin"
        private const val DEQUEUE_TIMEOUT_US = 10_000L

        fun registerWith(flutterEngine: FlutterEngine, context: Context): WaveformPlugin {
            val plugin = WaveformPlugin()
            plugin.context = context
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    fun cleanup() {
        if (::channel.isInitialized) channel.setMethodCallHandler(null)
        backgroundExecutor.shutdown()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "decode" -> {
                val path = call.argument<String>("path")
                val count = (call.argument<Int>("count") ?: 60).coerceIn(8, 512)
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                    return
                }
                backgroundExecutor.execute {
                    try {
                        val buckets = decodeToBuckets(path, count)
                        postSuccess(result, buckets.toList())
                    } catch (e: Exception) {
                        Log.w(TAG, "Waveform decode failed for $path: ${e.message}")
                        postError(result, "DECODE_ERROR", e.message)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun decodeToBuckets(path: String, count: Int): DoubleArray {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            setDataSource(extractor, path)

            var trackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    inputFormat = f
                    break
                }
            }
            val format = inputFormat ?: throw IllegalStateException("No audio track found")
            extractor.selectTrack(trackIndex)

            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            var channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
            } else 2

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val sumSq = DoubleArray(count)
            val cnt = LongArray(count)
            // Used only when the container reports no duration: we cannot map by
            // time, so we collect per-buffer RMS and resample it to [count].
            val fallbackRms = ArrayList<Double>()
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT

            val bufferInfo = MediaCodec.BufferInfo()
            var sawInputEOS = false
            var sawOutputEOS = false

            while (!sawOutputEOS) {
                if (!sawInputEOS) {
                    val inIndex = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)
                        val sampleSize = if (inBuf != null) extractor.readSampleData(inBuf, 0) else -1
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEOS = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
                when {
                    outIndex >= 0 -> {
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) sawOutputEOS = true
                        if (bufferInfo.size > 0 && bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            val outBuf = codec.getOutputBuffer(outIndex)
                            if (outBuf != null) {
                                outBuf.position(bufferInfo.offset)
                                outBuf.limit(bufferInfo.offset + bufferInfo.size)
                                outBuf.order(ByteOrder.nativeOrder())

                                var frameSumSq = 0.0
                                var frames = 0
                                if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
                                    val fb = outBuf.asFloatBuffer()
                                    val n = fb.remaining()
                                    var i = 0
                                    while (i < n) {
                                        var acc = 0.0
                                        var c = 0
                                        while (c < channelCount && i < n) { acc += fb.get(i); i++; c++ }
                                        val v = acc / c
                                        frameSumSq += v * v
                                        frames++
                                    }
                                } else {
                                    val sb = outBuf.asShortBuffer()
                                    val n = sb.remaining()
                                    var i = 0
                                    while (i < n) {
                                        var acc = 0.0
                                        var c = 0
                                        while (c < channelCount && i < n) { acc += sb.get(i) / 32768.0; i++; c++ }
                                        val v = acc / c
                                        frameSumSq += v * v
                                        frames++
                                    }
                                }

                                if (frames > 0) {
                                    if (durationUs > 0) {
                                        val bucket = ((bufferInfo.presentationTimeUs.toDouble() / durationUs) * count)
                                            .toInt().coerceIn(0, count - 1)
                                        sumSq[bucket] += frameSumSq
                                        cnt[bucket] += frames
                                    } else {
                                        fallbackRms.add(sqrt(frameSumSq / frames))
                                    }
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val of = codec.outputFormat
                        if (of.containsKey(MediaFormat.KEY_PCM_ENCODING)) pcmEncoding = of.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) channelCount = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                    }
                }
            }

            val rms = DoubleArray(count)
            if (durationUs > 0) {
                for (b in 0 until count) rms[b] = if (cnt[b] > 0) sqrt(sumSq[b] / cnt[b]) else Double.NaN
                fillGaps(rms)
            } else {
                if (fallbackRms.isEmpty()) throw IllegalStateException("No PCM data decoded")
                for (b in 0 until count) {
                    val start = (b.toDouble() / count * fallbackRms.size).toInt()
                    val end = (((b + 1).toDouble()) / count * fallbackRms.size).toInt()
                        .coerceAtLeast(start + 1).coerceAtMost(fallbackRms.size)
                    var s = 0.0
                    var k = 0
                    for (j in start until end) { s += fallbackRms[j]; k++ }
                    rms[b] = if (k > 0) s / k else 0.0
                }
            }

            var maxV = 0.0
            for (v in rms) if (v > maxV) maxV = v
            val out = DoubleArray(count)
            for (b in 0 until count) {
                val norm = if (maxV > 1e-9) rms[b] / maxV else 0.0
                out[b] = norm.coerceIn(0.04, 1.0)
            }
            return out
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private fun setDataSource(extractor: MediaExtractor, path: String) {
        when {
            path.startsWith("content:") -> {
                val ctx = context ?: throw IllegalStateException("No context for content URI")
                extractor.setDataSource(ctx, Uri.parse(path), null)
            }
            path.startsWith("file://") -> extractor.setDataSource(Uri.parse(path).path ?: path)
            else -> extractor.setDataSource(path)
        }
    }

    /// Buckets with no decoded frames land as NaN; fill them from the nearest
    /// populated neighbour so the drawn waveform has no zero-height dropouts.
    private fun fillGaps(a: DoubleArray) {
        val n = a.size
        var last = Double.NaN
        for (i in 0 until n) {
            if (!a[i].isNaN()) last = a[i] else if (!last.isNaN()) a[i] = last
        }
        var next = Double.NaN
        for (i in n - 1 downTo 0) {
            if (!a[i].isNaN()) next = a[i] else if (!next.isNaN()) a[i] = next
        }
        for (i in 0 until n) if (a[i].isNaN()) a[i] = 0.0
    }

    private fun postSuccess(result: Result, value: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { runCatching { result.success(value) } }
    }

    private fun postError(result: Result, code: String, message: String?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { runCatching { result.error(code, message, null) } }
    }
}
