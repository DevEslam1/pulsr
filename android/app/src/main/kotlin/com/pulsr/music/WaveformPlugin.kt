package com.pulsr.music

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.net.URI
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/// Decodes a local audio file to PCM and returns [count] peak-normalized RMS
/// buckets in 0..1, so the seek bar can draw a waveform that reflects the real
/// signal instead of a value fabricated from the song id.
class WaveformPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    @Volatile
    private var backgroundExecutor: ExecutorService = newExecutor()

    private val activeDecodes = java.util.concurrent.ConcurrentHashMap<String, AtomicBoolean>()

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/waveform"
        private const val TAG = "WaveformPlugin"
        private const val DEQUEUE_TIMEOUT_US = 10_000L
        private const val SPARSE_MIN_DURATION_US = 600_000_000L // 10 minutes
        private const val SPARSE_WINDOW_US = 100_000L          // ~100 ms per bucket

        private fun newExecutor(): ExecutorService =
            Executors.newFixedThreadPool(2) { runnable ->
                Thread(runnable, "PulsrWaveform").apply { isDaemon = true }
            }

        fun registerWith(flutterEngine: FlutterEngine, context: Context): WaveformPlugin {
            val plugin = WaveformPlugin()
            plugin.context = context
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    private fun ensureExecutor(): ExecutorService {
        val current = backgroundExecutor
        if (!current.isShutdown) return current
        synchronized(this) {
            if (backgroundExecutor.isShutdown) {
                backgroundExecutor = newExecutor()
            }
            return backgroundExecutor
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        ensureExecutor()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    fun cleanup() {
        if (::channel.isInitialized) channel.setMethodCallHandler(null)
        // Cancel every in-flight decode first: shutdownNow interrupts the
        // workers, and the codec loops check these flags between buffers.
        for (flag in activeDecodes.values) flag.set(true)
        backgroundExecutor.shutdownNow()
        activeDecodes.clear()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "decode" -> {
                val path = call.argument<String>("path")
                val count = (call.argument<Int>("count") ?: 60).coerceIn(8, 512)
                val timeoutMs = (call.argument<Int>("timeoutMs") ?: 30_000).toLong().coerceIn(5_000L, 120_000L)
                val decodeId = call.argument<String>("decodeId") ?: java.util.UUID.randomUUID().toString()

                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                    return
                }

                val cancellationFlag = AtomicBoolean(false)
                // A duplicate decodeId cancels the previous task. Its finally
                // block uses the 2-arg remove, so it cannot evict this new flag.
                activeDecodes.put(decodeId, cancellationFlag)?.set(true)

                val executor = ensureExecutor()
                try {
                    executor.execute {
                        if (cancellationFlag.get()) {
                            activeDecodes.remove(decodeId, cancellationFlag)
                            postError(result, "CANCELLED", "Waveform decode cancelled for $path")
                            return@execute
                        }
                        try {
                            val buckets = decodeToBuckets(path, count, timeoutMs, cancellationFlag)
                            postSuccess(result, buckets.toList())
                        } catch (e: java.util.concurrent.CancellationException) {
                            postError(result, "CANCELLED", "Waveform decode cancelled for $path")
                        } catch (e: Exception) {
                            Log.w(TAG, "Waveform decode failed for $path: ${e.message}")
                            postError(result, "DECODE_ERROR", e.message)
                        } finally {
                            activeDecodes.remove(decodeId, cancellationFlag)
                        }
                    }
                } catch (_: RejectedExecutionException) {
                    activeDecodes.remove(decodeId, cancellationFlag)
                    postError(result, "PLUGIN_DISPOSED", "Waveform plugin is shutting down")
                }
            }
            "cancelDecode" -> {
                val decodeId = call.argument<String>("decodeId")
                if (decodeId != null) {
                    activeDecodes[decodeId]?.set(true)
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun decodeToBuckets(
        path: String,
        count: Int,
        timeoutMs: Long = 30_000L,
        cancellationFlag: AtomicBoolean? = null
    ): DoubleArray {
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
            val mime = format.getString(MediaFormat.KEY_MIME) ?: throw IllegalStateException("No audio MIME type found")
            extractor.selectTrack(trackIndex)

            var formatDurationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            var sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE).coerceAtLeast(1) else 44100
            var channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
            } else 2

            codec = MediaCodec.createDecoderByType(mime)
            // Prefer float output on API 24+; the output-format callback below
            // remains authoritative if the codec ignores the request.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                runCatching {
                    format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_FLOAT)
                }
            }
            codec.configure(format, null, null, 0)
            codec.start()
            val activeCodec = codec

            val sumSq = DoubleArray(count)
            val cnt = LongArray(count)
            var totalFramesDecoded = 0L
            // Used only when the container reports no duration: we cannot map by
            // time, so we collect per-buffer RMS and resample it to [count].
            val fallbackRms = ArrayList<Double>()
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            val bufferInfo = MediaCodec.BufferInfo()

            var sawInputEOS = false
            var sawOutputEOS = false
            var channelIndex = 0
            var channelAcc = 0.0
            var lastOutputPtsUs = -1L
            var iterations = 0
            val maxIterations = 5_000_000
            val deadline = SystemClock.elapsedRealtime() + timeoutMs

            // Per-output-buffer state.
            var framesInBuffer = 0L
            var bufferSumSq = 0.0
            var bufferFrames = 0L

            fun checkAbort(iterationBudget: Int) {
                if (cancellationFlag?.get() == true) {
                    throw java.util.concurrent.CancellationException("Decode was cancelled")
                }
                if (SystemClock.elapsedRealtime() > deadline) {
                    Log.w(TAG, "Waveform decode exceeded ${timeoutMs}ms timeout for $path; aborting")
                    throw java.util.concurrent.TimeoutException("Waveform decode exceeded ${timeoutMs}ms timeout")
                }
                if (++iterations > iterationBudget) {
                    throw IllegalStateException("Exceeded maximum decode iterations ($iterationBudget)")
                }
            }

            fun resetStreamState() {
                sawInputEOS = false
                sawOutputEOS = false
                channelIndex = 0
                channelAcc = 0.0
                lastOutputPtsUs = -1L
            }

            fun updateOutputFormat() {
                val of = activeCodec.outputFormat
                if (of.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    pcmEncoding = of.getInteger(MediaFormat.KEY_PCM_ENCODING)
                }
                if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    channelCount = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                }
                if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE).coerceAtLeast(1)
                }
                channelAcc = 0.0
                channelIndex = 0
            }

            fun feedInput() {
                if (sawInputEOS) return
                val inIndex = activeCodec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                if (inIndex >= 0) {
                    val inBuf = activeCodec.getInputBuffer(inIndex)
                    val sampleSize = if (inBuf != null) extractor.readSampleData(inBuf, 0) else -1
                    if (sampleSize < 0) {
                        activeCodec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        sawInputEOS = true
                    } else {
                        activeCodec.queueInputBuffer(inIndex, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            fun accumulateFrame(frameValue: Double, frameIndex: Long) {
                totalFramesDecoded++
                if (formatDurationUs > 0) {
                    val bufferPts = bufferInfo.presentationTimeUs.coerceAtLeast(0L)
                    val frameTimeUs = bufferPts + (frameIndex * 1_000_000L) / sampleRate
                    val bucket = ((frameTimeUs.toDouble() / formatDurationUs) * count)
                        .toInt().coerceIn(0, count - 1)
                    sumSq[bucket] += frameValue * frameValue
                    cnt[bucket]++
                } else {
                    bufferSumSq += frameValue * frameValue
                    bufferFrames++
                }
            }

            fun pushSample(raw: Double) {
                val v = if (raw.isFinite()) raw else 0.0
                channelAcc += v
                channelIndex++
                if (channelIndex == channelCount) {
                    accumulateFrame(channelAcc / channelCount, framesInBuffer)
                    framesInBuffer++
                    channelAcc = 0.0
                    channelIndex = 0
                }
            }

            fun handleOutputBuffer(outIndex: Int) {
                try {
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEOS = true
                    }
                    if (bufferInfo.size <= 0 ||
                        bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    ) {
                        return
                    }
                    val outBuf = activeCodec.getOutputBuffer(outIndex) ?: return
                    outBuf.position(bufferInfo.offset)
                    outBuf.limit(bufferInfo.offset + bufferInfo.size)
                    outBuf.order(ByteOrder.nativeOrder())
                    if (bufferInfo.presentationTimeUs >= 0) {
                        lastOutputPtsUs = bufferInfo.presentationTimeUs
                    }

                    framesInBuffer = 0L
                    bufferSumSq = 0.0
                    bufferFrames = 0L

                    when (pcmEncoding) {
                        AudioFormat.ENCODING_PCM_FLOAT -> {
                            val fb = outBuf.asFloatBuffer()
                            val n = fb.remaining()
                            for (i in 0 until n) pushSample(fb.get(i).toDouble())
                        }
                        AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                            val base = outBuf.position()
                            val n = outBuf.remaining() / 3
                            for (i in 0 until n) {
                                val o = base + i * 3
                                val b0 = outBuf.get(o).toInt() and 0xFF
                                val b1 = outBuf.get(o + 1).toInt() and 0xFF
                                val b2 = outBuf.get(o + 2).toInt() // signed: sign-extends << 16
                                val raw = b0 or (b1 shl 8) or (b2 shl 16)
                                pushSample(raw / 8388608.0)
                            }
                        }
                        AudioFormat.ENCODING_PCM_32BIT -> {
                            val ib = outBuf.asIntBuffer()
                            val n = ib.remaining()
                            for (i in 0 until n) pushSample(ib.get(i) / 2147483648.0)
                        }
                        AudioFormat.ENCODING_PCM_8BIT -> {
                            val base = outBuf.position()
                            val n = outBuf.remaining()
                            for (i in 0 until n) {
                                val b = outBuf.get(base + i).toInt() and 0xFF
                                pushSample((b - 128) / 128.0)
                            }
                        }
                        else -> {
                            // ENCODING_PCM_16BIT is the universal fallback.
                            val sb = outBuf.asShortBuffer()
                            val n = sb.remaining()
                            for (i in 0 until n) pushSample(sb.get(i) / 32768.0)
                        }
                    }

                    if (formatDurationUs <= 0 && bufferFrames > 0) {
                        fallbackRms.add(sqrt(bufferSumSq / bufferFrames))
                    }
                } finally {
                    activeCodec.releaseOutputBuffer(outIndex, false)
                }
            }

            fun drainOutput() {
                val outIndex = activeCodec.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
                when {
                    outIndex >= 0 -> handleOutputBuffer(outIndex)
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> updateOutputFormat()
                    else -> Unit
                }
            }

            fun decodeLinear() {
                while (!sawOutputEOS) {
                    checkAbort(maxIterations)
                    feedInput()
                    drainOutput()
                }
            }

            /**
             * Samples [count] evenly spaced ~100 ms windows. Returns false when
             * the extractor cannot seek; the caller then restarts linearly.
             */
            fun decodeSparse(): Boolean {
                var lastSeekUs = Long.MIN_VALUE
                var lastSampleTime = Long.MIN_VALUE
                var anyFrames = false
                for (b in 0 until count) {
                    checkAbort(maxIterations)
                    var targetUs = (b.toLong() * formatDurationUs) / count
                    if (lastSeekUs != Long.MIN_VALUE && targetUs <= lastSeekUs) {
                        targetUs = lastSeekUs + 1
                    }
                    val seeked = runCatching {
                        extractor.seekTo(targetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                    }.isSuccess
                    if (!seeked) return false
                    val actualUs = extractor.sampleTime
                    if (actualUs < 0) return false
                    // A seek that does not move forward (or jumps far behind the
                    // target) means this source cannot do random access.
                    if (b > 0 && actualUs <= lastSampleTime) return false
                    if (b > 0 && actualUs < targetUs - 2_000_000L) return false
                    lastSeekUs = targetUs
                    lastSampleTime = actualUs

                    val flushed = runCatching { activeCodec.flush() }.isSuccess
                    if (!flushed) return false
                    resetStreamState()

                    val windowEndUs = actualUs + SPARSE_WINDOW_US
                    val framesBefore = totalFramesDecoded
                    while (true) {
                        checkAbort(maxIterations)
                        feedInput()
                        drainOutput()
                        if (lastOutputPtsUs >= windowEndUs) break
                        if (sawOutputEOS) break
                    }
                    if (totalFramesDecoded > framesBefore) anyFrames = true
                    if (sawOutputEOS) break
                }
                return anyFrames
            }

            if (formatDurationUs >= SPARSE_MIN_DURATION_US && formatDurationUs > 0) {
                val sparseOk = try {
                    decodeSparse()
                } catch (e: java.util.concurrent.CancellationException) {
                    throw e
                } catch (e: java.util.concurrent.TimeoutException) {
                    throw e
                } catch (e: Exception) {
                    Log.w(TAG, "Sparse waveform seek failed for $path; falling back to linear: ${e.message}")
                    false
                }
                if (!sparseOk) {
                    java.util.Arrays.fill(sumSq, 0.0)
                    java.util.Arrays.fill(cnt, 0L)
                    fallbackRms.clear()
                    totalFramesDecoded = 0
                    runCatching { activeCodec.flush() }
                    runCatching { extractor.seekTo(0, MediaExtractor.SEEK_TO_PREVIOUS_SYNC) }
                    resetStreamState()
                    decodeLinear()
                }
            } else {
                decodeLinear()
            }

            if (channelIndex > 0) {
                val v = channelAcc / channelIndex
                totalFramesDecoded++
                val lastBucket = count - 1
                if (formatDurationUs > 0) {
                    sumSq[lastBucket] += v * v
                    cnt[lastBucket] += 1
                } else {
                    fallbackRms.add(sqrt(v * v))
                }
            }

            val effectiveDurationUs = if (formatDurationUs > 0) {
                formatDurationUs
            } else if (totalFramesDecoded > 0 && sampleRate > 0) {
                (totalFramesDecoded * 1_000_000L) / sampleRate
            } else {
                0L
            }

            val rms = DoubleArray(count)
            if (effectiveDurationUs > 0) {
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
            if (maxV <= 1e-9) {
                return out
            }
            for (b in 0 until count) {
                val norm = rms[b] / maxV
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
        val ctx = context
        when {
            path.startsWith("content:") -> {
                if (ctx != null) {
                    extractor.setDataSource(ctx, Uri.parse(path), null)
                } else {
                    throw IllegalStateException("No context for content URI")
                }
            }
            path.startsWith("file://") -> {
                val filePath = runCatching { File(URI(path)).absolutePath }
                    .getOrElse { Uri.parse(path).path ?: path }
                extractor.setDataSource(filePath)
            }
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
