// android/app/src/main/cpp/AAudioSink.h
//
// Pulsr native AAudio output sink ("Direct" mode).
//
// Bypasses AudioFlinger's mixer via AAudio: per-stream sample rate (no OS
// resampling), EXCLUSIVE sharing attempt with LOW_LATENCY performance mode,
// and a blocking write path owned by the caller's thread (ExoPlayer's audio
// rendering thread).
//
// Bit-perfect rule: 24-bit packed output (the DoP carrier format) never has
// volume applied - any gain would corrupt DoP marker bytes. I16/FLOAT apply
// volume in a scratch copy so the caller's buffer is never mutated.
//
// Threading: one writer thread max. Close() may be called from any thread
// and is ordered via an atomic flag so a blocked write exits promptly.
#ifndef PULSR_AAUDIO_SINK_H_
#define PULSR_AAUDIO_SINK_H_

#include <aaudio/AAudio.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace pulsr {

class AAudioSink {
public:
    enum class Encoding : int32_t {
        Int16 = 1,       // AAUDIO_FORMAT_PCM_I16
        Float = 2,       // AAUDIO_FORMAT_PCM_FLOAT
        I24Packed = 3,   // AAUDIO_FORMAT_PCM_I24_PACKED (DoP carrier)
    };

    struct Config {
        int32_t sampleRate = 48000;
        int32_t channelCount = 2;
        Encoding encoding = Encoding::Int16;
        bool preferExclusive = true;   // try EXCLUSIVE first, then SHARED ladder
        bool lowLatency = true;        // PERFORMANCE_MODE_LOW_LATENCY on SHARED
        int32_t targetBufferMs = 150;  // 0 => device default capacity
    };

    // Opens the stream via the EXCLUSIVE -> SHARED(low latency) -> SHARED
    // fallback ladder. Returns false and fills `error` on failure.
    bool Open(const Config& config, std::string* error);

    // Blocks until the stream is released. Safe from any thread.
    void Close();

    // Consumes exactly `sizeBytes` from `data` (blocking until accepted).
    // Returns bytes consumed, or -1 on error/close.
    int32_t Write(const uint8_t* data, int32_t sizeBytes);

    void Play();
    void Pause();
    // Best-effort flush (pause + requestFlush + restart); rebases the
    // position counters so position math stays monotonic per configuration.
    void Flush();

    void SetVolume(float volume);  // ignored for I24Packed (bit-perfect)

    int64_t FramesRead() const;      // device-consumed frames since flush base
    int64_t FramesWritten() const;   // app-written frames since flush base
    int32_t XRunCount() const;
    int32_t XRunDelta() const;
    bool IsExclusive() const { return exclusive_; }
    int32_t BufferCapacityFrames() const;
    int32_t FramesPerBurst() const;
    int64_t GetTimestampLatencyFrames() const;
    double GetOutputLatencyMs() const;
    int32_t SampleRate() const { return config_.sampleRate; }
    int32_t ChannelCount() const { return config_.channelCount; }
    bool HasPendingData() const;

private:
    bool TryOpen(aaudio_sharing_mode_t sharing, aaudio_performance_mode_t perf);
    void CloseLocked(bool waitForWriters = true);
    static void ErrorCallback(AAudioStream* stream, void* userData, aaudio_result_t error);
    bool RecoverDisconnected();

    Config config_{};
    std::atomic<AAudioStream*> stream_{nullptr};
    std::mutex streamMutex_;
    mutable std::atomic<int32_t> activeReaders_{0};
    mutable std::atomic<int32_t> activeWriters_{0};
    std::atomic<bool> releasing_{false};
    std::atomic<bool> disconnected_{false};
    bool exclusive_ = false;
    bool bitPerfect_ = false;           // true for I24Packed (no volume)
    int32_t bytesPerFrame_ = 0;
    int64_t framesWrittenBase_ = 0;     // written-frame counter at last flush
    std::atomic<int64_t> framesWritten_{0}; // total written since open
    int64_t readBase_ = 0;              // device read counter at last flush
    mutable std::atomic<int32_t> lastXRunCount_{0};
    std::atomic<float> volume_{1.0f};
    std::string lastError_;
    std::vector<uint8_t> volumeScratch_;
    std::chrono::steady_clock::time_point lastRecoveryAttempt_{};
    int recoveryAttempts_ = 0;
};

}  // namespace pulsr

#endif  // PULSR_AAUDIO_SINK_H_
