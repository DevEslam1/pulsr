// android/app/src/main/cpp/AAudioSink.cpp
#include "AAudioSink.h"

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

int32_t ContainerBytesPerFrame(AAudioSink::Encoding encoding, int32_t channels) {
    int32_t sampleBytes;
    switch (encoding) {
        case AAudioSink::Encoding::Int16: sampleBytes = 2; break;
        case AAudioSink::Encoding::Float: sampleBytes = 4; break;
        case AAudioSink::Encoding::I24Packed: sampleBytes = 3; break;
        default: return 0;
    }
    return sampleBytes * channels;
}

aaudio_format_t ToAaudioFormat(AAudioSink::Encoding encoding) {
    switch (encoding) {
        case AAudioSink::Encoding::Int16: return AAUDIO_FORMAT_PCM_I16;
        case AAudioSink::Encoding::Float: return AAUDIO_FORMAT_PCM_FLOAT;
        case AAudioSink::Encoding::I24Packed: return AAUDIO_FORMAT_PCM_I24_PACKED;
    }
    return AAUDIO_FORMAT_UNSPECIFIED;
}

}  // namespace

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
        const int32_t capacity = static_cast<int32_t>(
            (static_cast<int64_t>(config_.sampleRate) *
             config_.targetBufferMs) / 1000);
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
    if (bitPerfect_ && AAudioStream_getSharingMode(stream) != AAUDIO_SHARING_MODE_EXCLUSIVE) {
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
    bytesPerFrame_ =
        ContainerBytesPerFrame(config_.encoding, config_.channelCount);
    if (config_.targetBufferMs > 0) {
        const int32_t capacity = static_cast<int32_t>(
            (static_cast<int64_t>(config_.sampleRate) *
             config_.targetBufferMs) / 1000);
        AAudioStream_setBufferSizeInFrames(stream, capacity);
    }
    exclusive_ =
        AAudioStream_getSharingMode(stream) == AAUDIO_SHARING_MODE_EXCLUSIVE;
    if (recoverPrevFramesWritten != nullptr && recoverPrevWrittenBase != nullptr) {
        framesWritten_ = *recoverPrevFramesWritten;
        framesWrittenBase_ = *recoverPrevWrittenBase;
        readBase_ = AAudioStream_getFramesRead(stream);
        // Buffered frames from the disconnected stream cannot be drained.
        // Account for them as discarded so pending-data/EOS cannot hang.
        readOffset_ = *recoverPrevFramesWritten - *recoverPrevWrittenBase;
    } else {
        framesWritten_ = 0;
        framesWrittenBase_ = 0;
        readBase_ = 0;
        readOffset_ = 0;
    }
    lastXRunCount_.store(AAudioStream_getXRunCount(stream), std::memory_order_relaxed);
    disconnected_.store(false, std::memory_order_release);
    lastWriteResult_.store(AAUDIO_OK, std::memory_order_relaxed);

    // Pre-allocate volume scratch buffer under streamMutex_ to prevent audio-thread allocation
    volumeScratch_.resize(static_cast<size_t>(bytesPerFrame_ * config_.sampleRate));

    const aaudio_result_t sr = AAudioStream_requestStart(stream);
    if (sr != AAUDIO_OK) {
        lastError_ =
            std::string("requestStart: ") + AAudio_convertResultToText(sr);
        AAudioStream_close(stream);
        return false;
    }
    stream_.store(stream, std::memory_order_release);
    LOGI("AAudio stream open: rate=%d ch=%d enc=%d exclusive=%d xrun=%d",
         AAudioStream_getSampleRate(stream), config_.channelCount,
         static_cast<int>(config_.encoding), exclusive_ ? 1 : 0,
         AAudioStream_getXRunCount(stream));
    return true;
}

bool AAudioSink::Open(const Config& config, std::string* error) {
    std::lock_guard<std::mutex> lock(streamMutex_);
    config_ = config;
    bytesPerFrame_ =
        ContainerBytesPerFrame(config_.encoding, config_.channelCount);
    bitPerfect_ = config_.preferExclusive;
    if (bytesPerFrame_ <= 0 || config_.sampleRate <= 0 ||
        config_.channelCount <= 0 || config_.channelCount > 8) {
        lastError_ = "invalid config";
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (bitPerfect_ &&
        TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY)) {
        if (error != nullptr) error->clear();
        return true;
    }
    if (bitPerfect_) {
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (config_.lowLatency &&
        TryOpen(AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY)) {
        if (error != nullptr) error->clear();
        return true;
    }
    if (TryOpen(AAUDIO_SHARING_MODE_SHARED, AAUDIO_PERFORMANCE_MODE_NONE)) {
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
        sink->disconnected_.store(true, std::memory_order_release);
    }
}

bool AAudioSink::RecoverDisconnected() {
    LOGW("Attempting to recover disconnected AAudio stream...");
    // Current writer thread is active, so do not wait for writers here
    CloseLocked(/* waitForWriters = */ false);
    disconnected_.store(false, std::memory_order_release);
    int64_t prevFramesWritten = framesWritten_;
    int64_t prevWrittenBase = framesWrittenBase_;

    if (bitPerfect_ &&
        TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY,
                &prevFramesWritten, &prevWrittenBase)) {
        LOGI("Recovered AAudio stream in EXCLUSIVE mode");
        return true;
    }
    if (bitPerfect_) return false;
    if (config_.lowLatency &&
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
}

void AAudioSink::CloseLocked(bool waitForWriters) {
    AAudioStream* st = stream_.exchange(nullptr, std::memory_order_acq_rel);
    if (st != nullptr) {
        // Request stop immediately so any in-flight write unblocks without blocking Close
        AAudioStream_requestStop(st);
        // Wait for any in-flight lock-free queries to finish before closing
        while (activeReaders_.load(std::memory_order_acquire) > 0) {
            std::this_thread::yield();
        }
        if (waitForWriters) {
            while (activeWriters_.load(std::memory_order_acquire) > 0) {
                std::this_thread::yield();
            }
        }
        AAudioStream_close(st);
    }
}

void AAudioSink::Close() {
    releasing_.store(true, std::memory_order_release);
    std::lock_guard<std::mutex> lock(streamMutex_);
    CloseLocked();
    releasing_.store(false, std::memory_order_release);
}

int32_t AAudioSink::Write(const uint8_t* data, int32_t sizeBytes) {
    if (bytesPerFrame_ <= 0) return -1;
    if (sizeBytes < 0 || (sizeBytes % bytesPerFrame_) != 0) return -1;

    // Register as an in-flight writer *before* checking releasing_ so
    // CloseLocked() cannot observe zero writers and close the stream while we
    // are about to enter (check-then-increment TOCTOU).
    activeWriters_.fetch_add(1, std::memory_order_acquire);
    struct WriterGuard {
        std::atomic<int32_t>& ref;
        ~WriterGuard() { ref.fetch_sub(1, std::memory_order_release); }
    } guard{activeWriters_};

    if (releasing_.load(std::memory_order_acquire)) return -1;

    if (disconnected_.load(std::memory_order_acquire)) {
        std::unique_lock<std::mutex> lock(streamMutex_, std::try_to_lock);
        if (!lock.owns_lock() || releasing_.load(std::memory_order_acquire)) {
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

    AAudioStream* st = stream_.load(std::memory_order_acquire);
    if (st == nullptr || releasing_.load(std::memory_order_acquire)) return -1;

    const float curVol = volume_.load(std::memory_order_relaxed);
    const bool applyVol =
        (!bitPerfect_ && config_.encoding != Encoding::I24Packed && curVol != 1.0f);

    alignas(16) uint8_t stackScratch[2048];
    uint8_t* scratchPtr = nullptr;
    int32_t maxChunkFrames = 0;

    if (applyVol) {
        if (volumeScratch_.size() >= static_cast<size_t>(bytesPerFrame_)) {
            scratchPtr = volumeScratch_.data();
            maxChunkFrames = static_cast<int32_t>(volumeScratch_.size() / bytesPerFrame_);
        } else {
            scratchPtr = stackScratch;
            maxChunkFrames = static_cast<int32_t>(sizeof(stackScratch) / bytesPerFrame_);
        }
    }

    const int32_t totalFrames = sizeBytes / bytesPerFrame_;
    int32_t framesLeft = totalFrames;
    const uint8_t* inCursor = data;
    int retries = 0;
    // Cap the total stall at ~150 ms (3 x 50 ms). The caller handles partial
    // writes, and a 500 ms block here also delayed Close/release behind the
    // lifecycle lock.
    constexpr int kMaxRetries = 3;

    while (framesLeft > 0) {
        if (releasing_.load(std::memory_order_acquire) || stream_.load(std::memory_order_acquire) == nullptr) break;

        const uint8_t* writeSrc = inCursor;
        int32_t framesToWrite = framesLeft;

        if (applyVol && maxChunkFrames > 0) {
            framesToWrite = std::min(framesLeft, maxChunkFrames);
            const int32_t chunkBytes = framesToWrite * bytesPerFrame_;
            std::memcpy(scratchPtr, inCursor, static_cast<size_t>(chunkBytes));

            if (config_.encoding == Encoding::Float) {
                float* f = reinterpret_cast<float*>(scratchPtr);
                const int n = chunkBytes / static_cast<int32_t>(sizeof(float));
                for (int i = 0; i < n; ++i) {
                    f[i] *= curVol;
                }
            } else if (config_.encoding == Encoding::Int16) {
                int16_t* s = reinterpret_cast<int16_t*>(scratchPtr);
                const int n = chunkBytes / static_cast<int32_t>(sizeof(int16_t));
                for (int i = 0; i < n; ++i) {
                    float v = static_cast<float>(s[i]) * curVol;
                    v = std::clamp(v, -32768.0f, 32767.0f);
                    s[i] = static_cast<int16_t>(std::lrintf(v));
                }
            } else if (config_.encoding == Encoding::I24Packed) {
                const int numSamples = chunkBytes / 3;
                for (int i = 0; i < numSamples; ++i) {
                    uint8_t* p = scratchPtr + i * 3;
                    const int32_t raw = static_cast<int32_t>(p[0]) |
                                        (static_cast<int32_t>(p[1]) << 8) |
                                        (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
                    float v = static_cast<float>(raw) * curVol;
                    v = std::clamp(v, -8388608.0f, 8388607.0f);
                    const int32_t scaled = std::lrintf(v);
                    p[0] = static_cast<uint8_t>(scaled & 0xFF);
                    p[1] = static_cast<uint8_t>((scaled >> 8) & 0xFF);
                    p[2] = static_cast<uint8_t>((scaled >> 16) & 0xFF);
                }
            }
            writeSrc = scratchPtr;
        }

        aaudio_result_t w = AAudioStream_write(st, writeSrc, framesToWrite, kWriteTimeoutNs);
        if (w > 0) {
            inCursor += w * bytesPerFrame_;
            framesLeft -= w;
            framesWritten_.fetch_add(w, std::memory_order_relaxed);
            retries = 0;
        } else if (w == AAUDIO_ERROR_TIMEOUT) {
            CheckAndAdaptBuffer(st);
            if (++retries > kMaxRetries) break;
            continue;  // loop re-checks releasing_ so Close() is never blocked
        } else if (w == AAUDIO_ERROR_DISCONNECTED) {
            disconnected_.store(true, std::memory_order_release);
            break;
        } else {
            lastWriteResult_.store(w, std::memory_order_relaxed);
            break;
        }
    }

    const int32_t framesWritten = totalFrames - framesLeft;
    return framesWritten > 0 ? (framesWritten * bytesPerFrame_) : (framesLeft == 0 ? sizeBytes : -1);
}

void AAudioSink::Play() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    if (st != nullptr) AAudioStream_requestStart(st);
}

void AAudioSink::Pause() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    if (st != nullptr) AAudioStream_requestPause(st);
}

void AAudioSink::Flush() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    if (st == nullptr) return;
    AAudioStream_requestPause(st);
    aaudio_stream_state_t nextState = AAUDIO_STREAM_STATE_UNINITIALIZED;
    AAudioStream_waitForStateChange(st, AAUDIO_STREAM_STATE_PAUSING, &nextState, 100000000LL);
    // requestFlush is unsupported on some MMAP streams; ignore the result.
    if (AAudioStream_requestFlush(st) == AAUDIO_OK) {
        AAudioStream_waitForStateChange(st, AAUDIO_STREAM_STATE_FLUSHING, &nextState, 50000000LL);
    }
    readBase_ = AAudioStream_getFramesRead(st);
    readOffset_ = 0;
    framesWrittenBase_ = framesWritten_.load(std::memory_order_relaxed);
}

void AAudioSink::SetVolume(float volume) {
    if (bitPerfect_) return;  // DoP carrier must stay bit-perfect
    volume_.store(volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume),
                  std::memory_order_relaxed);
}

int64_t AAudioSink::FramesRead() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    int64_t result = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_acquire)) {
        const int64_t read = AAudioStream_getFramesRead(st);
        const int64_t base = readBase_.load(std::memory_order_relaxed);
        result = readOffset_.load(std::memory_order_relaxed) + (read > base ? read - base : 0);
    }
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return result;
}

int64_t AAudioSink::FramesWritten() const {
    const int64_t written = framesWritten_.load(std::memory_order_relaxed);
    const int64_t base = framesWrittenBase_.load(std::memory_order_relaxed);
    return written > base ? written - base
                          : 0;
}

bool AAudioSink::HasPendingData() const {
    return FramesWritten() > FramesRead();
}

int32_t AAudioSink::XRunCount() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    int32_t xruns = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_acquire)) {
        xruns = AAudioStream_getXRunCount(st);
    }
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return xruns;
}

void AAudioSink::CheckAndAdaptBuffer(AAudioStream* st) {
    if (st == nullptr || releasing_.load(std::memory_order_acquire)) return;
    const int32_t currentSize = AAudioStream_getBufferSizeInFrames(st);
    const int32_t capacity = AAudioStream_getBufferCapacityInFrames(st);
    const int32_t burst = AAudioStream_getFramesPerBurst(st);
    if (burst <= 0 || currentSize >= capacity) return;

    // Expand buffer by 2 bursts to prevent recurring xruns on lower-power SoCs (MediaTek/Exynos)
    const int32_t step = std::max(burst * 2, burst);
    const int32_t newSize = std::min(currentSize + step, capacity);
    if (newSize > currentSize) {
        const int32_t applied = AAudioStream_setBufferSizeInFrames(st, newSize);
        LOGI("AAudio adaptive governor: expanded buffer: %d -> %d frames (capacity=%d)",
             currentSize, applied, capacity);
    }
}

int32_t AAudioSink::XRunDelta() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    int32_t delta = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_acquire)) {
        const int32_t cur = AAudioStream_getXRunCount(st);
        const int32_t prev = lastXRunCount_.exchange(cur, std::memory_order_relaxed);
        delta = cur > prev ? (cur - prev) : 0;
        if (delta > 0) {
            const_cast<AAudioSink*>(this)->CheckAndAdaptBuffer(st);
        }
    }
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return delta;
}

int32_t AAudioSink::BufferCapacityFrames() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    int32_t cap = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_acquire)) {
        cap = AAudioStream_getBufferCapacityInFrames(st);
    }
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return cap;
}

int32_t AAudioSink::DeviceId() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    const int32_t id = st != nullptr && !releasing_.load(std::memory_order_acquire)
        ? AAudioStream_getDeviceId(st) : 0;
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return id;
}

int32_t AAudioSink::FramesPerBurst() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    int32_t burst = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_acquire)) {
        burst = AAudioStream_getFramesPerBurst(st);
    }
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return burst;
}

int64_t AAudioSink::GetTimestampLatencyFrames() const {
    activeReaders_.fetch_add(1, std::memory_order_acquire);
    AAudioStream* st = stream_.load(std::memory_order_acquire);
    int64_t latency = 0;
    if (st != nullptr && !releasing_.load(std::memory_order_acquire)) {
        int64_t framePosition = 0;
        int64_t timeNanoseconds = 0;
        aaudio_result_t res = AAudioStream_getTimestamp(st, CLOCK_MONOTONIC, &framePosition, &timeNanoseconds);
        if (res == AAUDIO_OK) {
            timespec ts{};
            clock_gettime(CLOCK_MONOTONIC, &ts);
            const int64_t nowNs = static_cast<int64_t>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
            const int64_t elapsedNs = nowNs - timeNanoseconds;
            const int32_t sr = config_.sampleRate > 0 ? config_.sampleRate : 48000;
            const int64_t elapsedFrames = (elapsedNs > 0)
                ? static_cast<int64_t>(static_cast<double>(elapsedNs) * 1e-9 * sr)
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
        latency = -static_cast<int64_t>((static_cast<int64_t>(config_.sampleRate) * std::max(config_.targetBufferMs, 20)) / 1000);
    }
    activeReaders_.fetch_sub(1, std::memory_order_release);
    return latency;
}

double AAudioSink::GetOutputLatencyMs() const {
    const int32_t sr = config_.sampleRate > 0 ? config_.sampleRate : 48000;
    const int64_t latencyFrames = GetTimestampLatencyFrames();
    if (latencyFrames < 0) {
        const int64_t cap = -latencyFrames;
        return (static_cast<double>(cap) / static_cast<double>(sr)) * 1000.0;
    }
    return (static_cast<double>(latencyFrames) / static_cast<double>(sr)) * 1000.0;
}

}  // namespace pulsr
