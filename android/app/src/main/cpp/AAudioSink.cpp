// android/app/src/main/cpp/AAudioSink.cpp
#include "AAudioSink.h"
#include "AudioDspEngine.h"

#include <android/api-level.h>
#include <android/log.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <thread>
#include <time.h>

#define LOG_TAG "PulsrAAudio"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace pulsr {

namespace {

constexpr int64_t kWriteTimeoutNs = 50LL * 1000 * 1000;  // 50 ms per attempt

// Upper bound for the pre-stop drain in CloseLocked(): waiting for the device
// tail is worth it, stalling a control thread is not. 250 ms covers the default
// 150 ms target, a deeper target gets twice its own buffer, and nothing waits
// longer than 500 ms.
int64_t DrainBudgetMs(int32_t targetBufferMs) {
    return std::min<int64_t>(
        std::max<int64_t>(250, static_cast<int64_t>(targetBufferMs) * 2), 500);
}

int32_t ContainerBytesPerFrame(AAudioSink::Encoding encoding, int32_t channels) {
    int32_t sampleBytes;
    switch (encoding) {
        case AAudioSink::Encoding::Int16: sampleBytes = 2; break;
        case AAudioSink::Encoding::Float: sampleBytes = 4; break;
        case AAudioSink::Encoding::I24Packed: sampleBytes = 3; break;
        case AAudioSink::Encoding::Int32: sampleBytes = 4; break;
        default: return 0;
    }
    return sampleBytes * channels;
}

aaudio_format_t ToAaudioFormat(AAudioSink::Encoding encoding) {
    switch (encoding) {
        case AAudioSink::Encoding::Int16: return AAUDIO_FORMAT_PCM_I16;
        case AAudioSink::Encoding::Float: return AAUDIO_FORMAT_PCM_FLOAT;
        case AAudioSink::Encoding::I24Packed: return AAUDIO_FORMAT_PCM_I24_PACKED;
        case AAudioSink::Encoding::Int32: return AAUDIO_FORMAT_PCM_I32;
    }
    return AAUDIO_FORMAT_UNSPECIFIED;
}

}  // namespace

AAudioSink::AAudioSink() {
    // Fixed 64 KB scratch: enough for 2048 frames at 8ch/float32, and never
    // resized while the stream is live.
    volumeScratch_.resize(64 * 1024, 0);
}

bool AAudioSink::TryOpen(aaudio_sharing_mode_t sharing,
                         aaudio_performance_mode_t perf,
                         int64_t* recoverPrevFramesWritten,
                         int64_t* recoverPrevWrittenBase) {
    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t r = AAudio_createStreamBuilder(&builder);
    if (r != AAUDIO_OK) {
        lastError_ = std::string("createStreamBuilder: ") +
                     AAudio_convertResultToText(r);
        return false;
    }
    AAudioStreamBuilder_setDeviceId(builder, config_.deviceId);
    AAudioStreamBuilder_setFormat(builder, ToAaudioFormat(config_.encoding));
    AAudioStreamBuilder_setSampleRate(builder, config_.sampleRate);
    AAudioStreamBuilder_setChannelCount(builder, config_.channelCount);
    AAudioStreamBuilder_setSharingMode(builder, sharing);
    AAudioStreamBuilder_setPerformanceMode(builder, perf);
    AAudioStreamBuilder_setContentType(builder,
                                       AAUDIO_CONTENT_TYPE_MUSIC);
    AAudioStreamBuilder_setUsage(builder, AAUDIO_USAGE_MEDIA);
    if (config_.targetBufferMs > 0) {
        const int32_t capacity =
            ComputeStreamCapacityFrames(config_.sampleRate, config_.targetBufferMs);
        if (capacity > 0) {
            AAudioStreamBuilder_setBufferCapacityInFrames(builder, capacity);
        }
    }

    AAudioStreamBuilder_setErrorCallback(builder, ErrorCallback, this);

    AAudioStream* stream = nullptr;
    r = AAudioStreamBuilder_openStream(builder, &stream);
    AAudioStreamBuilder_delete(builder);
    if (r != AAUDIO_OK) {
        lastError_ = std::string("openStream: ") + AAudio_convertResultToText(r);
        return false;
    }
    if (AAudioStream_getFormat(stream) != ToAaudioFormat(config_.encoding)) {
        lastError_ = "negotiated format mismatch";
        AAudioStream_close(stream);
        return false;
    }
    // Exclusive is mandatory whenever the caller asked for it (preferExclusive)
    // or asserts bit-exact output (bitPerfect): a SHARED stream is resampled by
    // AudioFlinger and voids both claims.
    const bool requireExclusive = config_.preferExclusive || config_.bitPerfect;
    if (requireExclusive && AAudioStream_getSharingMode(stream) != AAUDIO_SHARING_MODE_EXCLUSIVE) {
        lastError_ = "bit-perfect output requires exclusive sharing";
        AAudioStream_close(stream);
        return false;
    }
    // Direct/bit-perfect output has no OS resampler, and position/timing math
    // below uses config_.sampleRate. If the device silently substituted a
    // different rate or channel count, keeping the requested value would drift
    // pitch and timing. Reject instead so the Open() ladder falls through to a
    // SHARED rung (AudioFlinger resamples there) rather than playing distorted.
    const int32_t negotiatedRate = AAudioStream_getSampleRate(stream);
    if (negotiatedRate != config_.sampleRate) {
        lastError_ = "negotiated sample-rate mismatch";
        AAudioStream_close(stream);
        return false;
    }
    const int32_t negotiatedCh = AAudioStream_getChannelCount(stream);
    if (negotiatedCh != config_.channelCount) {
        lastError_ = "negotiated channel-count mismatch";
        AAudioStream_close(stream);
        return false;
    }
    const int32_t frameBytes =
        ContainerBytesPerFrame(config_.encoding, config_.channelCount);
    // Size the initial buffer with healthy headroom so exclusive streams fed
    // from non-RT threads do not xrun immediately at start/seek.
    const int32_t targetFrames = config_.targetBufferMs > 0
        ? static_cast<int32_t>(
              (static_cast<int64_t>(config_.sampleRate) *
               config_.targetBufferMs) / 1000)
        : 0;
    int32_t initialBuffer = 0;
    {
        const int32_t burst = AAudioStream_getFramesPerBurst(stream);
        const int32_t capacity = AAudioStream_getBufferCapacityInFrames(stream);
        const int32_t requested =
            ComputeInitialBufferFrames(burst, capacity, targetFrames);
        if (requested > 0) {
            const int32_t applied =
                AAudioStream_setBufferSizeInFrames(stream, requested);
            if (applied > 0) {
                // The HAL may clamp the request (MMAP granularity, minimum
                // burst count), so publish what it actually gave us. The
                // governor's shrink floor is this value: keeping the request
                // would let ShrinkBufferIfStable "shrink" to a size the
                // buffer never had.
                initialBuffer = applied;
            } else {
                if (applied < 0) {
                    // Negative is AAudio's error return. Say it once per open
                    // attempt instead of silently believing the request.
                    LOGW("AAudio setBufferSizeInFrames(%d) failed: %s",
                         requested, AAudio_convertResultToText(
                             static_cast<aaudio_result_t>(applied)));
                }
                const int32_t readBack =
                    AAudioStream_getBufferSizeInFrames(stream);
                initialBuffer = readBack > 0 ? readBack : requested;
            }
        }
    }
    const bool exclusive =
        AAudioStream_getSharingMode(stream) == AAUDIO_SHARING_MODE_EXCLUSIVE;

    // Stage all sink state locally. Nothing below is published until
    // requestStart() succeeds: a failed start must not clear the disconnected
    // flag or re-base the frame counters.
    AAudioOpenState staged{};
    if (recoverPrevFramesWritten != nullptr && recoverPrevWrittenBase != nullptr) {
        staged.framesWritten = *recoverPrevFramesWritten;
        staged.framesWrittenBase = *recoverPrevWrittenBase;
        staged.readBase = AAudioStream_getFramesRead(stream);
        // Buffered frames from the disconnected stream cannot be drained.
        // Account for them as discarded so pending-data/EOS cannot hang.
        staged.readOffset = *recoverPrevFramesWritten - *recoverPrevWrittenBase;
    }
    staged.lastXRunCount = AAudioStream_getXRunCount(stream);
    staged.initialBufferFrames = std::max(initialBuffer, 0);
    staged.connected = true;

    const aaudio_result_t sr = AAudioStream_requestStart(stream);
    if (sr != AAUDIO_OK) {
        lastError_ =
            std::string("requestStart: ") + AAudio_convertResultToText(sr);
        AAudioStream_close(stream);
        return false;
    }

    AAudioOpenState live{};
    CommitOpenState(/*startSucceeded=*/true, staged, live);
    bytesPerFrame_.store(frameBytes, std::memory_order_release);
    activeSampleRate_.store(config_.sampleRate, std::memory_order_release);
    activeChannelCount_.store(config_.channelCount, std::memory_order_release);
    activeEncoding_.store(static_cast<int32_t>(config_.encoding), std::memory_order_release);
    activeTargetBufferMs_.store(config_.targetBufferMs, std::memory_order_release);
    exclusive_.store(exclusive, std::memory_order_release);
    // Publish the unity-only verdicts for THIS stream. Only an exclusive open
    // can honour them, so a bit-perfect request that ended up on a SHARED rung
    // keeps bitPerfect_ false and the sink stays honest about it.
    bitPerfect_.store(exclusive && config_.bitPerfect, std::memory_order_release);
    dop_.store(exclusive && config_.dop, std::memory_order_release);
    framesWritten_.store(live.framesWritten, std::memory_order_relaxed);
    framesWrittenBase_.store(live.framesWrittenBase, std::memory_order_relaxed);
    readBase_.store(live.readBase, std::memory_order_relaxed);
    readOffset_.store(live.readOffset, std::memory_order_relaxed);
    lastXRunCount_.store(live.lastXRunCount, std::memory_order_relaxed);
    governorLastXRunCount_.store(live.lastXRunCount, std::memory_order_relaxed);
    initialBufferFrames_.store(live.initialBufferFrames, std::memory_order_release);
    {
        const int64_t nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        lastXRunTimestampMs_.store(nowMs, std::memory_order_release);
        lastShrinkTimestampMs_.store(nowMs, std::memory_order_release);
    }
    recovery_.markConnected();
    lastWriteResult_.store(AAUDIO_OK, std::memory_order_relaxed);
    stream_.store(stream, std::memory_order_release);
    // The container that actually opened is the grid the engine must shape onto.
    // Float output reports 32: the next conversion belongs to the platform and
    // the app cannot observe its depth, so nothing is gained by shaping for it.
    // Registry, not the control singleton: the depth must reach the engines that
    // actually render (the singleton never runs processInterleaved).
    DspEngineRegistry::instance().setSinkBitDepth(
        config_.encoding == Encoding::Int16
            ? 16
            : (config_.encoding == Encoding::I24Packed ? 24 : 32));
    LOGI("AAudio stream open: rate=%d ch=%d enc=%d exclusive=%d xrun=%d",
         AAudioStream_getSampleRate(stream), config_.channelCount,
         static_cast<int>(config_.encoding), exclusive ? 1 : 0,
         AAudioStream_getXRunCount(stream));
    return true;
}

bool AAudioSink::Open(const Config& config, std::string* error) {
    std::lock_guard<std::mutex> lock(streamMutex_);
    // Repeated Open() must not leak the previous stream or let TryOpen resize
    // scratch state under an active writer. Drain writers first (this is a
    // control-thread call, not the audio thread).
    CloseLocked(/* waitForWriters = */ true);
    return OpenLocked(config, error);
}

bool AAudioSink::OpenLocked(const Config& config, std::string* error,
                            int64_t* recoverPrevFramesWritten,
                            int64_t* recoverPrevWrittenBase) {
    // streamMutex_ is held by the caller, which has already closed the previous
    // stream: everything below validates the config and walks the ladder, so
    // Flush() can rebuild a stream under the same lock instead of dropping it
    // and racing Close()/Open() in between. recoverPrev* are forwarded verbatim
    // to every rung so a rebuild keeps framesWritten_ continuous.
    recoveryAttempts_ = 0;
    config_ = config;
    const int32_t frameBytes =
        ContainerBytesPerFrame(config_.encoding, config_.channelCount);
    bytesPerFrame_.store(frameBytes, std::memory_order_release);
    activeSampleRate_.store(config_.sampleRate, std::memory_order_release);
    activeChannelCount_.store(config_.channelCount, std::memory_order_release);
    activeEncoding_.store(static_cast<int32_t>(config_.encoding), std::memory_order_release);
    activeTargetBufferMs_.store(config_.targetBufferMs, std::memory_order_release);
    // Only an explicit bit-perfect request implies unity gain; preferExclusive
    // keeps its historical EXCLUSIVE-only ladder without forcing unity. The
    // unity verdict itself is published by TryOpen() once the stream's sharing
    // mode is known: a SHARED stream is resampled by AudioFlinger, so it may
    // never carry the gate. Both flags start clean and VolumeWasRejected()
    // describes the stream about to open.
    bitPerfect_.store(false, std::memory_order_release);
    dop_.store(false, std::memory_order_release);
    volumeRejected_.store(false, std::memory_order_release);
    if (config_.encoding == Encoding::Int32 && android_get_device_api_level() < 31) {
        lastError_ = "AAUDIO_FORMAT_PCM_I32 requires Android 12 (API 31)+";
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (frameBytes <= 0 || config_.sampleRate <= 0 ||
        config_.channelCount <= 0 || config_.channelCount > 8) {
        lastError_ = "invalid config";
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (config_.preferExclusive || config_.bitPerfect) {
        // Prefer LOW_LATENCY for wired/short bursts unless a deep buffer is
        // requested (>= 50 ms); fall back to PERFORMANCE_MODE_NONE in
        // EXCLUSIVE so DACs/HALs that only grant exclusive mode on NONE still
        // receive a bit-perfect stream.
        const bool preferDeepExclusive =
            ShouldPreferDeepBuffer(config_.targetBufferMs, config_.lowLatency);
        if ((!preferDeepExclusive &&
             TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                     recoverPrevFramesWritten, recoverPrevWrittenBase)) ||
            TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_NONE,
                    recoverPrevFramesWritten, recoverPrevWrittenBase) ||
            (preferDeepExclusive &&
             TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                     recoverPrevFramesWritten, recoverPrevWrittenBase))) {
            if (error != nullptr) error->clear();
            return true;
        }
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (config_.lowLatency &&
        config_.targetBufferMs < 180 &&
        TryOpen(AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                recoverPrevFramesWritten, recoverPrevWrittenBase)) {
        if (error != nullptr) error->clear();
        return true;
    }
    if (TryOpen(AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_NONE,
                recoverPrevFramesWritten, recoverPrevWrittenBase)) {
        if (error != nullptr) error->clear();
        return true;
    }
    LOGE("AAudio open failed on every ladder rung: %s", lastError_.c_str());
    if (error != nullptr) *error = lastError_;
    return false;
}

void AAudioSink::ErrorCallback(AAudioStream* stream, void* userData, aaudio_result_t error) {
    (void)stream;
    auto* sink = reinterpret_cast<AAudioSink*>(userData);
    if (!sink) return;
    LOGW("AAudio stream error callback: %s (%d)", AAudio_convertResultToText(error), error);
    if (error == AAUDIO_ERROR_DISCONNECTED) {
        sink->recovery_.markDisconnected();
    }
}

bool AAudioSink::RecoverDisconnected() {
    LOGW("Attempting to recover disconnected AAudio stream...");
    // A live SetBitPerfect() is the caller's current intent and is not part of
    // config_ (which only carries the open-time request). CloseLocked clears
    // both verdicts, so capture them before the reopen and re-assert them on
    // the replacement stream; otherwise a reconnect would silently drop the
    // unity-only guarantee while Java still believes bit-perfect is engaged.
    // A live DoP carrier counts as exclusive too: its words are DSD payload, and
    // a SHARED stream is resampled by AudioFlinger, so recovering it there
    // would corrupt the bitstream as well as the unity claim.
    const bool liveBitPerfect = bitPerfect_.load(std::memory_order_acquire);
    const bool liveDop = dop_.load(std::memory_order_acquire);
    const bool requireExclusive = config_.preferExclusive || config_.bitPerfect ||
                                  liveBitPerfect || liveDop;
    // Current writer thread is active, so do not wait for writers here
    CloseLocked(/* waitForWriters = */ false, /* drainTail = */ false);
    // The disconnected flag is deliberately not cleared here. TryOpen clears
    // it only after a stream is actually live; if the whole ladder fails the
    // flag must stay set so Write keeps retrying with backoff.
    int64_t prevFramesWritten = framesWritten_;
    int64_t prevWrittenBase = framesWrittenBase_;

    // Mirror the Open() rung order. A recovery that picks a different rung than
    // the original open silently changes latency and exclusivity, and the old
    // ladder had no EXCLUSIVE+NONE rung even though Open() does: a HAL that only
    // grants exclusive mode on PERFORMANCE_MODE_NONE could open but never
    // recover. NONE comes first for a deep buffer (>= 50 ms target), exactly
    // as in Open().
    const bool preferDeepExclusive =
        ShouldPreferDeepBuffer(config_.targetBufferMs, config_.lowLatency);
    const bool recovered = recovery_.attempt([&]() {
        if (requireExclusive) {
            const bool exclusiveOk =
                (!preferDeepExclusive &&
                 TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                         &prevFramesWritten, &prevWrittenBase)) ||
                TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_NONE,
                        &prevFramesWritten, &prevWrittenBase) ||
                (preferDeepExclusive &&
                 TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                         &prevFramesWritten, &prevWrittenBase));
            if (exclusiveOk) {
                LOGI("Recovered AAudio stream in EXCLUSIVE mode");
                return true;
            }
            // Neither an exclusive request nor a bit-perfect/DoP assertion may
            // fall back to SHARED: a resampled stream would silently void the
            // contract.
            return false;
        }
        if (config_.lowLatency && config_.targetBufferMs < 180 &&
            TryOpen(AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                    &prevFramesWritten, &prevWrittenBase)) {
            LOGI("Recovered AAudio stream in SHARED low-latency mode");
            return true;
        }
        if (TryOpen(AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_NONE,
                    &prevFramesWritten, &prevWrittenBase)) {
            LOGI("Recovered AAudio stream in SHARED mode");
            return true;
        }
        LOGE("Failed to recover disconnected AAudio stream");
        return false;
    });
    if (recovered && (liveBitPerfect || liveDop)) {
        if (!SetBitPerfect(liveBitPerfect, liveDop) && liveBitPerfect) {
            LOGE("Recovered stream refused the live bit-perfect assertion");
        }
    }
    return recovered;
}

void AAudioSink::CloseLocked(bool waitForWriters, bool drainTail) {
    AAudioStream* st = stream_.exchange(nullptr, std::memory_order_seq_cst);
    if (st != nullptr) {
        // This stream was the sink the engines were shaping for; the next one
        // (usually the Java fallback) decides its own depth. Registry, not the
        // control singleton, so every render engine clears.
        DspEngineRegistry::instance().setSinkBitDepth(0);
        // Drain before stop: requestStop() discards whatever the device has not
        // consumed yet, which is exactly the up-to-targetBufferMs cut a
        // hand-over used to produce (AAudio -> AudioTrack goes through Close()
        // from the Java release path). 1 ms polling steps, no allocation, and
        // no writeMutex_ here — a writer parked on that lock still counts as
        // active, so taking it under streamMutex_ would risk a cycle; the loop
        // only reads AAudio counters.
        //
        // `releasing_` is deliberately not an up-front skip: Close() sets it
        // before calling in, so gating on it would make this drain unreachable
        // on the very path it exists for. The error paths are excluded by
        // `drainTail` (flush and disconnect recovery pass false) and by the
        // state check: a disconnected or paused stream never advances
        // framesRead, so waiting on it would only burn the budget.
        if (drainTail && !recovery_.isDisconnected()) {
            const int64_t budgetMs = DrainBudgetMs(config_.targetBufferMs);
            int64_t waitedMs = 0;
            while (waitedMs < budgetMs &&
                   AAudioStream_getState(st) == AAUDIO_STREAM_STATE_STARTED &&
                   AAudioStream_getFramesRead(st) <
                       AAudioStream_getFramesWritten(st)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                ++waitedMs;
            }
        }
        // Request stop immediately so any in-flight write unblocks without blocking Close
        AAudioStream_requestStop(st);
        // Wait for any in-flight lock-free queries to finish before closing
        while (activeReaders_.load(std::memory_order_seq_cst) > 0) {
            std::this_thread::yield();
        }
        if (waitForWriters) {
            while (activeWriters_.load(std::memory_order_seq_cst) > 0) {
                std::this_thread::yield();
            }
        }
        AAudioStream_close(st);
    }
    // No live stream: the sharing mode is unknown again until the next open, so
    // IsExclusiveStream() must not keep reporting the closed stream's mode, and
    // the unity-only verdicts die with the stream that carried them.
    exclusive_.store(false, std::memory_order_release);
    bitPerfect_.store(false, std::memory_order_release);
    dop_.store(false, std::memory_order_release);
}

void AAudioSink::Close() {
    releasing_.store(true, std::memory_order_seq_cst);
    std::lock_guard<std::mutex> lock(streamMutex_);
    CloseLocked();
    releasing_.store(false, std::memory_order_seq_cst);
}

int32_t AAudioSink::Write(const uint8_t* data, int32_t sizeBytes) {
    // Register as an in-flight writer *before* checking releasing_ (Dekker seq_cst
    // barrier) so CloseLocked() cannot observe zero writers and close the stream
    // while we are about to enter.
    activeWriters_.fetch_add(1, std::memory_order_seq_cst);
    struct WriterGuard {
        std::atomic<int32_t>& ref;
        ~WriterGuard() { ref.fetch_sub(1, std::memory_order_seq_cst); }
    } guard{activeWriters_};

    if (releasing_.load(std::memory_order_seq_cst) ||
        flushing_.load(std::memory_order_acquire)) {
        return 0;
    }

    const int32_t frameBytes = bytesPerFrame_.load(std::memory_order_acquire);
    if (frameBytes <= 0) return -1;
    if (sizeBytes < 0 || (sizeBytes % frameBytes) != 0) return -1;

    if (recovery_.isDisconnected()) {
        std::unique_lock<std::mutex> lock(streamMutex_, std::try_to_lock);
        if (!lock.owns_lock() || releasing_.load(std::memory_order_seq_cst) ||
            flushing_.load(std::memory_order_acquire)) {
            return -1;
        }
        const auto now = std::chrono::steady_clock::now();
        const auto msSinceLast = std::chrono::duration_cast<std::chrono::milliseconds>(
            now - lastRecoveryAttempt_).count();
        const int64_t backoffMs = (recoveryAttempts_ >= 5) ? 1000 : 250;
        if (msSinceLast < backoffMs) {
            return -1;
        }
        lastRecoveryAttempt_ = now;
        recoveryAttempts_++;
        if (!RecoverDisconnected()) {
            return -1;
        }
        recoveryAttempts_ = 0;
    }

    // Serialize concurrent Write()/Flush() access to shared volumeScratch_, sinkDither_,
    // and framesWritten_ / Flush() rebase synchronization.
    std::lock_guard<std::mutex> writeLock(writeMutex_);

    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    if (st == nullptr || releasing_.load(std::memory_order_seq_cst) ||
        flushing_.load(std::memory_order_acquire)) {
        return -1;
    }
    const int32_t writeFrameBytes = bytesPerFrame_.load(std::memory_order_acquire);
    const int32_t channels = activeChannelCount_.load(std::memory_order_acquire);
    const Encoding encoding =
        static_cast<Encoding>(activeEncoding_.load(std::memory_order_acquire));
    if (writeFrameBytes <= 0 || channels <= 0 || sizeBytes < 0 ||
        (sizeBytes % writeFrameBytes) != 0) {
        return -1;
    }

    const float curVol = volume_.load(std::memory_order_relaxed);
    // Bit-perfect output and an explicitly declared DoP carrier are unity-only:
    // scaling them would void the sample-identical claim (and destroy the DoP
    // markers), so no volume is applied there even if a stale value reached
    // volume_. The gate is keyed on the flags, not on the packed 24-bit
    // container, so ordinary 24-bit PCM keeps its volume. Every other
    // configuration passes samples untouched at unity and is scaled on a
    // scratch copy below it.
    const bool unityOnly = !SinkVolumeAllowed(
        bitPerfect_.load(std::memory_order_relaxed),
        dop_.load(std::memory_order_relaxed));
    if (unityOnly) {
        // Byte-exact delivery: never scale, and drop the ramp state a previous
        // volume-scaled configuration may have left behind, so the next mode
        // flip back to scaled output starts from unity instead of a multiplier
        // that no longer describes the signal.
        appliedVolume_ = 1.0f;
    }
    // Ramp start for this call: the gain the previous call ended on. volume_
    // is sampled once per Write(), so applying it as one constant factor turns
    // a slider drag into one hard step per buffer (5-20 ms) — zipper noise.
    const float rampStart = appliedVolume_;
    const bool applyVol = !unityOnly && (curVol != 1.0f || rampStart != 1.0f);

    alignas(16) uint8_t stackScratch[2048];
    uint8_t* scratchPtr = nullptr;
    int32_t maxChunkFrames = 0;

    if (applyVol) {
        if (volumeScratch_.size() >= static_cast<size_t>(writeFrameBytes)) {
            scratchPtr = volumeScratch_.data();
            maxChunkFrames = static_cast<int32_t>(volumeScratch_.size() / writeFrameBytes);
        } else {
            scratchPtr = stackScratch;
            maxChunkFrames = static_cast<int32_t>(sizeof(stackScratch) / writeFrameBytes);
        }
    }

    const int32_t totalFrames = sizeBytes / writeFrameBytes;
    int32_t framesLeft = totalFrames;
    const uint8_t* inCursor = data;
    int retries = 0;
    // Cap the total stall at ~150 ms (3 x 50 ms). The caller handles partial
    // writes, and a 500 ms block here also delayed Close/release behind the
    // lifecycle lock.
    constexpr int kMaxRetries = 3;

    while (framesLeft > 0) {
        if (releasing_.load(std::memory_order_seq_cst) ||
            flushing_.load(std::memory_order_acquire) ||
            stream_.load(std::memory_order_seq_cst) == nullptr) {
            break;
        }

        const uint8_t* writeSrc = inCursor;
        int32_t framesToWrite = framesLeft;

        if (applyVol && maxChunkFrames > 0) {
            framesToWrite = std::min(framesLeft, maxChunkFrames);
            const int32_t chunkBytes = framesToWrite * writeFrameBytes;
            std::memcpy(scratchPtr, inCursor, static_cast<size_t>(chunkBytes));

            // Spread the ramp over the whole call, not per chunk: a 16 ms call
            // split into two 8 ms chunks would otherwise ramp twice from
            // rampStart and stop half way. framesDone is the offset of this
            // chunk inside the call, so the chunks concatenate into one line.
            const int32_t framesDone = totalFrames - framesLeft;
            const float gainStart = rampStart +
                (curVol - rampStart) * static_cast<float>(framesDone) /
                    static_cast<float>(totalFrames);
            const float gainEnd = rampStart +
                (curVol - rampStart) * static_cast<float>(framesDone + framesToWrite) /
                    static_cast<float>(totalFrames);

            if (encoding == Encoding::Float) {
                float* f = reinterpret_cast<float*>(scratchPtr);
                const float step =
                    (gainEnd - gainStart) / static_cast<float>(framesToWrite);
                float gain = gainStart;
                for (int32_t fr = 0; fr < framesToWrite; ++fr) {
                    // One gain per frame keeps the channels of a frame
                    // identical, so the ramp cannot shift the stereo image.
                    float* frame = f + static_cast<size_t>(fr) * channels;
                    for (int32_t c = 0; c < channels; ++c) frame[c] *= gain;
                    gain += step;
                }
            } else if (encoding == Encoding::Int16) {
                ApplyI16VolumeRamp(reinterpret_cast<int16_t*>(scratchPtr), framesToWrite,
                                   channels, gainStart, gainEnd, sinkDither_);
            } else if (encoding == Encoding::I24Packed) {
                ApplyI24PackedVolumeRamp(scratchPtr, framesToWrite, channels,
                                         gainStart, gainEnd, sinkDither_);
            } else if (encoding == Encoding::Int32) {
                ApplyI32VolumeRamp(reinterpret_cast<int32_t*>(scratchPtr), framesToWrite,
                                   channels, gainStart, gainEnd, sinkDither_);
            }
            writeSrc = scratchPtr;
        }

        aaudio_result_t w = AAudioStream_write(st, writeSrc, framesToWrite, kWriteTimeoutNs);
        if (w > 0) {
            inCursor += w * writeFrameBytes;
            framesLeft -= w;
            framesWritten_.fetch_add(w, std::memory_order_relaxed);
            retries = 0;
        } else if (w == AAUDIO_ERROR_TIMEOUT) {
            // A write timeout only delays this block; it is not evidence of an
            // underrun. Buffer growth is driven exclusively by real xruns in
            // UpdateBufferGovernor(), otherwise a briefly busy device ratchets latency up
            // permanently.
            if (++retries >= kMaxRetries) break;
            continue;  // loop re-checks releasing_ so Close() is never blocked
        } else if (w == AAUDIO_ERROR_DISCONNECTED) {
            recovery_.markDisconnected();
            break;
        } else {
            lastWriteResult_.store(w, std::memory_order_relaxed);
            break;
        }
    }

    // Persist the ramp endpoint: the next Write() continues from exactly where
    // this one stopped, so a chunked block or a short write leaves no seam. A
    // fully written block ends exactly on volume_, which is what lets a settled
    // slider become bit-exact again (unity stops scaling and stops touching
    // scratch).
    if (!unityOnly) {
        const int32_t writtenFrames = totalFrames - framesLeft;
        appliedVolume_ = (writtenFrames >= totalFrames)
            ? curVol
            : rampStart + (curVol - rampStart) *
                  (static_cast<float>(writtenFrames) / static_cast<float>(totalFrames));
    }

    // Feed the buffer governor from the writer thread independently of XRunDelta()
    // telemetry so writing audio never swallows xrun counts from Java callers.
    UpdateBufferGovernor(st);

    const int32_t framesWritten = totalFrames - framesLeft;
    if (framesWritten > 0) {
        return framesWritten * writeFrameBytes;
    }
    if (framesLeft == 0) {
        return sizeBytes;
    }
    if (recovery_.isDisconnected() ||
        lastWriteResult_.load(std::memory_order_relaxed) != AAUDIO_OK) {
        return -1;
    }
    // A write timeout with 0 frames written is not a fatal failure: return 0 so
    // the caller can yield and retry the buffer without triggering a Media3 WriteException.
    return 0;
}

void AAudioSink::Play() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    if (st == nullptr) return;
    {
        // A (re)started stream carries no gain history: begin the next block at
        // the stored volume instead of ramping up from whatever the previous
        // stream ended on. Java calls play() right after a flush/reopen, which
        // makes this the point where the ramp is re-seeded — a stale endpoint
        // here would fade the first blocks back in from an old slider position.
        // Lock order is streamMutex_ -> writeMutex_, same as Flush().
        std::lock_guard<std::mutex> writeLock(writeMutex_);
        const float stored = volume_.load(std::memory_order_relaxed);
        appliedVolume_ =
            SinkVolumeAllowed(bitPerfect_.load(std::memory_order_relaxed),
                              dop_.load(std::memory_order_relaxed))
                ? stored
                : 1.0f;
    }
    AAudioStream_requestStart(st);
}

void AAudioSink::Pause() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    if (st != nullptr) AAudioStream_requestPause(st);
}

void AAudioSink::Flush() {
    flushing_.store(true, std::memory_order_release);
    std::lock_guard<std::mutex> lock(streamMutex_);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    bool flushRefused = false;
    bool wasRunning = false;
    if (st != nullptr) {
        wasRunning = AAudioStream_getState(st) == AAUDIO_STREAM_STATE_STARTED;
        AAudioStream_requestPause(st);
        aaudio_stream_state_t nextState = AAUDIO_STREAM_STATE_UNINITIALIZED;
        AAudioStream_waitForStateChange(st, AAUDIO_STREAM_STATE_PAUSING, &nextState, 100000000LL);
        const aaudio_result_t flushResult = AAudioStream_requestFlush(st);
        if (flushResult == AAUDIO_OK) {
            AAudioStream_waitForStateChange(st, AAUDIO_STREAM_STATE_FLUSHING, &nextState, 50000000LL);
        } else {
            // requestFlush is unsupported on some MMAP/exclusive streams. The
            // old code ignored this and rebased the counters anyway, which left
            // the device buffer untouched and let pre-seek audio replay from it.
            // Rebuild the stream instead: a fresh stream is empty by
            // construction, so the counter rebase below is truthful.
            LOGW("AAudio requestFlush failed (%s); rebuilding the stream",
                 AAudio_convertResultToText(flushResult));
            flushRefused = true;
        }
    }
    if (flushRefused) {
        // Capture what CloseLocked() clears and what a reopen must continue:
        // the live unity verdicts (a seek must not silently drop bit-perfect or
        // the DoP carrier) and the written-frame counter (so FramesWritten()
        // does not jump backwards under Java's position math).
        const bool liveBitPerfect = bitPerfect_.load(std::memory_order_acquire);
        const bool liveDop = dop_.load(std::memory_order_acquire);
        const Config reopenConfig = config_;
        int64_t prevFramesWritten = framesWritten_.load(std::memory_order_relaxed);
        int64_t prevWrittenBase = framesWrittenBase_.load(std::memory_order_relaxed);
        // CloseLocked(true) spins on activeWriters_ while a writer parked on
        // writeMutex_ still counts as active, so it must run with that lock
        // released (Flush takes writeMutex_ exactly once, at the rebase below).
        CloseLocked(/* waitForWriters = */ true, /* drainTail = */ false);
        std::string reopenError;
        const bool reopened = OpenLocked(reopenConfig, &reopenError,
                                         &prevFramesWritten, &prevWrittenBase);
        if (!reopened) {
            // stream_ stays null: Write() returns -1 and Java's AudioTrack
            // fallback ladder engages, which is the contract for any failed
            // open. flushing_ still has to clear or the writer stays parked.
            LOGE("AAudio flush rebuild failed: %s", reopenError.c_str());
            st = nullptr;
        } else {
            st = stream_.load(std::memory_order_acquire);
            if ((liveBitPerfect || liveDop) &&
                !SetBitPerfect(liveBitPerfect, liveDop)) {
                LOGE("Rebuilt stream refused the live unity-only assertion");
            }
            // A rebuild starts the replacement (TryOpen calls requestStart).
            // Park it again when the sink was not running before the flush: a
            // seek made while paused would otherwise leave an empty STARTED
            // stream underrunning into XRunCount and inflating the buffer
            // governor on the next write. Best effort — Java re-issues play()
            // itself whenever it is playing.
            if (!wasRunning && st != nullptr) AAudioStream_requestPause(st);
        }
    }
    // Wait for any in-flight writer holding writeMutex_ to exit before rebasing
    // counters, and rebase only against a stream that is actually live. With no
    // stream the counters are left alone: FramesRead() falls back to
    // FramesWritten(), so pending-data/EOS checks still terminate.
    {
        std::lock_guard<std::mutex> writeLock(writeMutex_);
        if (st != nullptr) {
            readBase_ = AAudioStream_getFramesRead(st);
            readOffset_ = 0;
            framesWrittenBase_ = framesWritten_.load(std::memory_order_relaxed);
        }
    }
    flushing_.store(false, std::memory_order_release);
}

void AAudioSink::SetVolume(float volume) {
    const float clamped =
        volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume);
    // Bit-perfect output and an explicitly declared DoP carrier are unity-only.
    // Storing a requested attenuation would break the sample-identical contract,
    // so the request is refused, 1.0f is kept, and VolumeWasRejected() reports
    // it; the first refusal is logged once per stream so a dead volume slider is
    // never silent. Other configurations store the requested value (and Write()
    // applies it). Keyed on the flags, so 24-bit PCM is unaffected.
    if (!SinkVolumeAllowed(bitPerfect_.load(std::memory_order_acquire),
                           dop_.load(std::memory_order_acquire))) {
        volume_.store(1.0f, std::memory_order_relaxed);
        if (clamped != 1.0f) {
            // Exchange, not store: the warning belongs to the transition into
            // "rejected", and the caller keeps pushing slider values.
            if (!volumeRejected_.exchange(true, std::memory_order_acq_rel)) {
                LOGW("AAudio volume %.3f rejected: unity-only stream "
                     "(bit-perfect=%d dop=%d)",
                     static_cast<double>(clamped),
                     bitPerfect_.load(std::memory_order_relaxed) ? 1 : 0,
                     dop_.load(std::memory_order_relaxed) ? 1 : 0);
            }
        }
        return;
    }
    volume_.store(clamped, std::memory_order_relaxed);
    // An accepted value clears the diagnostic latch: the next refusal belongs
    // to the next unity-only transition, not to a stale earlier stream state.
    volumeRejected_.store(false, std::memory_order_release);
}

bool AAudioSink::SetBitPerfect(bool bitPerfect, bool dop) {
    // Only an EXCLUSIVE stream can honour either claim: a SHARED stream is
    // resampled by AudioFlinger, so bit-exactness and the DoP carrier both die
    // there. Refuse the request instead of pretending, and leave the gate off.
    if ((bitPerfect || dop) && !IsExclusive()) {
        bitPerfect_.store(false, std::memory_order_release);
        dop_.store(false, std::memory_order_release);
        return false;
    }
    bitPerfect_.store(bitPerfect, std::memory_order_release);
    dop_.store(dop, std::memory_order_release);
    if (!SinkVolumeAllowed(bitPerfect, dop)) {
        // Entering unity-only: snap the writer's ramp state now, so no stale
        // multiplier survives even if the next Write() is the one that flips
        // the gate (Write() snaps it too, on the writer thread).
        std::lock_guard<std::mutex> writeLock(writeMutex_);
        appliedVolume_ = 1.0f;
    }
    return true;
}

int64_t AAudioSink::FramesRead() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    int64_t result = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_seq_cst)) {
        const int64_t read = AAudioStream_getFramesRead(st);
        const int64_t base = readBase_.load(std::memory_order_relaxed);
        result = readOffset_.load(std::memory_order_relaxed) + (read > base ? read - base : 0);
    } else {
        // When stream is closed or releasing, report all written frames as read
        // to prevent hasPendingData drain loops from hanging indefinitely (B6)
        result = FramesWritten();
    }
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return result;
}

int64_t AAudioSink::FramesWritten() const {
    const int64_t written = framesWritten_.load(std::memory_order_relaxed);
    const int64_t base = framesWrittenBase_.load(std::memory_order_relaxed);
    return written > base ? written - base
                          : 0;
}

bool AAudioSink::HasPendingData() const {
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    if (st == nullptr || releasing_.load(std::memory_order_seq_cst)) {
        return false;
    }
    return FramesWritten() > FramesRead();
}

int32_t AAudioSink::XRunCount() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    int32_t xruns = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_seq_cst)) {
        xruns = AAudioStream_getXRunCount(st);
    }
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return xruns;
}

void AAudioSink::CheckAndAdaptBuffer(AAudioStream* st) const {
    if (st == nullptr || releasing_.load(std::memory_order_seq_cst)) return;
    const int32_t currentSize = AAudioStream_getBufferSizeInFrames(st);
    const int32_t capacity = AAudioStream_getBufferCapacityInFrames(st);
    const int32_t burst = AAudioStream_getFramesPerBurst(st);
    if (burst <= 0 || currentSize >= capacity) return;

    // Expand buffer by 2 bursts to prevent recurring xruns on lower-power SoCs (MediaTek/Exynos)
    const int32_t step = std::max(burst * 2, burst);
    const int32_t newSize = std::min(currentSize + step, capacity);
    if (newSize > currentSize) {
        (void)AAudioStream_setBufferSizeInFrames(st, newSize);
    }
}

void AAudioSink::UpdateBufferGovernor(AAudioStream* st) const {
    if (st == nullptr || releasing_.load(std::memory_order_seq_cst)) return;
    const int32_t cur = AAudioStream_getXRunCount(st);
    const int32_t prev = governorLastXRunCount_.exchange(cur, std::memory_order_relaxed);
    const int32_t delta = cur > prev ? (cur - prev) : 0;
    const int64_t nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    if (delta > 0) {
        lastXRunTimestampMs_.store(nowMs, std::memory_order_release);
        CheckAndAdaptBuffer(st);
    } else {
        // Slow shrink-back: after 30 s with no underruns, give back two
        // bursts, at most once per 30 s, never below the initial size.
        const int64_t lastXRun = lastXRunTimestampMs_.load(std::memory_order_acquire);
        const int64_t lastShrink = lastShrinkTimestampMs_.load(std::memory_order_acquire);
        if (lastXRun > 0 && nowMs - lastXRun >= 30000 && nowMs - lastShrink >= 30000) {
            lastShrinkTimestampMs_.store(nowMs, std::memory_order_release);
            ShrinkBufferIfStable(st);
        }
    }
}

int32_t AAudioSink::XRunDelta() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    int32_t delta = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_seq_cst)) {
        const int32_t cur = AAudioStream_getXRunCount(st);
        const int32_t prev = lastXRunCount_.exchange(cur, std::memory_order_relaxed);
        delta = cur > prev ? (cur - prev) : 0;
    }
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return delta;
}

void AAudioSink::ShrinkBufferIfStable(AAudioStream* st) const {
    if (st == nullptr || releasing_.load(std::memory_order_seq_cst)) return;
    const int32_t currentSize = AAudioStream_getBufferSizeInFrames(st);
    const int32_t burst = AAudioStream_getFramesPerBurst(st);
    const int32_t initial = initialBufferFrames_.load(std::memory_order_acquire);
    if (burst <= 0 || currentSize <= initial) return;
    const int32_t newSize = std::max(initial, currentSize - burst * 2);
    if (newSize >= currentSize) return;
    (void)AAudioStream_setBufferSizeInFrames(st, newSize);
}

int32_t AAudioSink::BufferCapacityFrames() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    int32_t cap = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_seq_cst)) {
        cap = AAudioStream_getBufferCapacityInFrames(st);
    }
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return cap;
}

int32_t AAudioSink::DeviceId() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    const int32_t id = st != nullptr && !releasing_.load(std::memory_order_seq_cst)
        ? AAudioStream_getDeviceId(st) : 0;
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return id;
}

int32_t AAudioSink::FramesPerBurst() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    int32_t burst = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_seq_cst)) {
        burst = AAudioStream_getFramesPerBurst(st);
    }
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return burst;
}

int64_t AAudioSink::GetTimestampLatencyFrames() const {
    activeReaders_.fetch_add(1, std::memory_order_seq_cst);
    AAudioStream* st = stream_.load(std::memory_order_seq_cst);
    int64_t latency = 0;
    const int32_t sr = activeSampleRate_.load(std::memory_order_acquire);
    const int32_t effSr = sr > 0 ? sr : 48000;
    if (st != nullptr && !releasing_.load(std::memory_order_seq_cst)) {
        int64_t framePosition = 0;
        int64_t timeNanoseconds = 0;
        aaudio_result_t res = AAudioStream_getTimestamp(st, CLOCK_MONOTONIC, &framePosition, &timeNanoseconds);
        if (res == AAUDIO_OK) {
            timespec ts{};
            clock_gettime(CLOCK_MONOTONIC, &ts);
            const int64_t nowNs = static_cast<int64_t>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
            const int64_t elapsedNs = nowNs - timeNanoseconds;
            const int64_t elapsedFrames = (elapsedNs > 0)
                ? static_cast<int64_t>(static_cast<double>(elapsedNs) * 1e-9 * effSr)
                : 0;
            const int64_t dacPos = framePosition + elapsedFrames;
            const int64_t netWritten = FramesWritten();
            const int64_t base = readBase_.load(std::memory_order_relaxed);
            const int64_t offset = readOffset_.load(std::memory_order_relaxed);
            const int64_t effectiveDacPos = offset + ((dacPos > base) ? (dacPos - base) : 0);
            latency = (netWritten > effectiveDacPos) ? (netWritten - effectiveDacPos) : 0;
        } else {
            // Negative capacity fallback when timestamp is unavailable
            latency = -static_cast<int64_t>(AAudioStream_getBufferCapacityInFrames(st));
        }
    } else {
        const int32_t targetMs = activeTargetBufferMs_.load(std::memory_order_acquire);
        latency = -static_cast<int64_t>((static_cast<int64_t>(effSr) * std::max(targetMs, 20)) / 1000);
    }
    activeReaders_.fetch_sub(1, std::memory_order_seq_cst);
    return latency;
}

double AAudioSink::GetOutputLatencyMs() const {
    const int32_t rawSr = activeSampleRate_.load(std::memory_order_acquire);
    const int32_t sr = rawSr > 0 ? rawSr : 48000;
    const int64_t latencyFrames = GetTimestampLatencyFrames();
    if (latencyFrames < 0) {
        const int64_t cap = -latencyFrames;
        return (static_cast<double>(cap) / static_cast<double>(sr)) * 1000.0;
    }
    return (static_cast<double>(latencyFrames) / static_cast<double>(sr)) * 1000.0;
}

}  // namespace pulsr
