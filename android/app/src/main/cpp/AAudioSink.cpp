// android/app/src/main/cpp/AAudioSink.cpp
#include "AAudioSink.h"

#include <android/log.h>

#include <chrono>
#include <cstring>
#include <thread>

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
                         aaudio_performance_mode_t perf) {
    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t r = AAudio_createStreamBuilder(&builder);
    if (r != AAUDIO_OK) {
        lastError_ = std::string("createStreamBuilder: ") +
                     AAudio_convertResultToText(r);
        return false;
    }
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
    stream_ = stream;
    bytesPerFrame_ =
        ContainerBytesPerFrame(config_.encoding, config_.channelCount);
    if (config_.targetBufferMs > 0) {
        const int32_t capacity = static_cast<int32_t>(
            (static_cast<int64_t>(config_.sampleRate) *
             config_.targetBufferMs) / 1000);
        AAudioStream_setBufferSizeInFrames(stream_, capacity);
    }
    exclusive_ =
        AAudioStream_getSharingMode(stream_) == AAUDIO_SHARING_MODE_EXCLUSIVE;
    framesWritten_ = 0;
    framesWrittenBase_ = 0;
    readBase_ = 0;
    const aaudio_result_t sr = AAudioStream_requestStart(stream_);
    if (sr != AAUDIO_OK) {
        lastError_ =
            std::string("requestStart: ") + AAudio_convertResultToText(sr);
        AAudioStream_close(stream_);
        stream_ = nullptr;
        return false;
    }
    LOGI("AAudio stream open: rate=%d ch=%d enc=%d exclusive=%d xrun=%d",
         AAudioStream_getSampleRate(stream_), config_.channelCount,
         static_cast<int>(config_.encoding), exclusive_ ? 1 : 0,
         AAudioStream_getXRunCount(stream_));
    return true;
}

bool AAudioSink::Open(const Config& config, std::string* error) {
    std::lock_guard<std::mutex> lock(streamMutex_);
    config_ = config;
    bytesPerFrame_ =
        ContainerBytesPerFrame(config_.encoding, config_.channelCount);
    bitPerfect_ = config_.encoding == Encoding::I24Packed;
    if (bytesPerFrame_ <= 0 || config_.sampleRate <= 0 ||
        config_.channelCount <= 0 || config_.channelCount > 8) {
        lastError_ = "invalid config";
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (config_.preferExclusive &&
        TryOpen(AAUDIO_SHARING_MODE_EXCLUSIVE, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY)) {
        if (error != nullptr) error->clear();
        return true;
    }
    if (config_.preferExclusive) {
        LOGW("EXCLUSIVE open failed (%s), falling back to SHARED",
             lastError_.c_str());
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

void AAudioSink::CloseLocked() {
    if (stream_ != nullptr) {
        AAudioStream_requestStop(stream_);
        AAudioStream_close(stream_);
        stream_ = nullptr;
    }
}

void AAudioSink::Close() {
    releasing_.store(true);
    std::lock_guard<std::mutex> lock(streamMutex_);
    CloseLocked();
    releasing_.store(false);
}

int32_t AAudioSink::Write(const uint8_t* data, int32_t sizeBytes) {
    if (stream_ == nullptr || bytesPerFrame_ <= 0) return -1;
    if (sizeBytes < 0 || (sizeBytes % bytesPerFrame_) != 0) return -1;

    const uint8_t* src = data;
    int32_t remaining = sizeBytes;
    std::lock_guard<std::mutex> lock(streamMutex_);
    if (releasing_.load() || stream_ == nullptr) return -1;

    // Volume path: only for gain-adjustable encodings; never mutates the
    // caller's buffer (scratch copy).
    if (!bitPerfect_ && volume_ != 1.0f) {
        volumeScratch_.resize(static_cast<size_t>(remaining));
        std::memcpy(volumeScratch_.data(), src, static_cast<size_t>(remaining));
        if (config_.encoding == Encoding::Float) {
            float* f = reinterpret_cast<float*>(volumeScratch_.data());
            const int n = remaining / static_cast<int32_t>(sizeof(float));
            for (int i = 0; i < n; ++i) f[i] *= volume_;
        } else {
            int16_t* s = reinterpret_cast<int16_t*>(volumeScratch_.data());
            const int n = remaining / static_cast<int32_t>(sizeof(int16_t));
            for (int i = 0; i < n; ++i) {
                float v = static_cast<float>(s[i]) * volume_;
                v = v < -32768.0f ? -32768.0f
                                  : (v > 32767.0f ? 32767.0f : v);
                s[i] = static_cast<int16_t>(v);
            }
        }
        src = volumeScratch_.data();
    }

    int32_t framesLeft = remaining / bytesPerFrame_;
    const uint8_t* cursor = src;
    int retries = 0;
    constexpr int kMaxRetries = 10;
    while (framesLeft > 0) {
        if (releasing_.load() || stream_ == nullptr) return -1;
        aaudio_result_t w = AAudioStream_write(stream_, cursor, framesLeft,
                                               kWriteTimeoutNs);
        if (w > 0) {
            cursor += w * bytesPerFrame_;
            framesLeft -= w;
            framesWritten_ += w;
            retries = 0;
        } else if (w == AAUDIO_ERROR_TIMEOUT) {
            if (++retries > kMaxRetries) break;
            continue;  // loop re-checks releasing_ so Close() is never blocked
        } else {
            lastError_ = std::string("write: ") + AAudio_convertResultToText(w);
            LOGE("AAudio write failed: %s", lastError_.c_str());
            return -1;
        }
    }
    return sizeBytes;
}

void AAudioSink::Play() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    if (stream_ != nullptr) AAudioStream_requestStart(stream_);
}

void AAudioSink::Pause() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    if (stream_ != nullptr) AAudioStream_requestPause(stream_);
}

void AAudioSink::Flush() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    if (stream_ == nullptr) return;
    AAudioStream_requestPause(stream_);
    // requestFlush is unsupported on some MMAP streams; ignore the result.
    AAudioStream_requestFlush(stream_);
    readBase_ = AAudioStream_getFramesRead(stream_);
    framesWrittenBase_ = framesWritten_;
    AAudioStream_requestStart(stream_);
}

void AAudioSink::SetVolume(float volume) {
    if (bitPerfect_) return;  // DoP carrier must stay bit-perfect
    volume_ = volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume);
}

int64_t AAudioSink::FramesRead() const {
    // Intentionally lock-free: called from the position-queried thread while
    // the writer thread may hold the mutex inside a blocking write.
    if (stream_ == nullptr) return 0;
    const int64_t read = AAudioStream_getFramesRead(stream_);
    return read > readBase_ ? read - readBase_ : 0;
}

int64_t AAudioSink::FramesWritten() const {
    return framesWritten_ > framesWrittenBase_ ? framesWritten_ - framesWrittenBase_
                                               : 0;
}

bool AAudioSink::HasPendingData() const {
    return stream_ != nullptr && FramesWritten() > FramesRead();
}

int32_t AAudioSink::XRunCount() const {
    if (stream_ == nullptr) return 0;
    return AAudioStream_getXRunCount(stream_);
}

int32_t AAudioSink::BufferCapacityFrames() const {
    if (stream_ == nullptr) return 0;
    return AAudioStream_getBufferCapacityInFrames(stream_);
}

}  // namespace pulsr
