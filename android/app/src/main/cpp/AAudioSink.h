// android/app/src/main/cpp/AAudioSink.h
//
// Pulsr native AAudio output sink ("Direct" mode).
//
// Requests a per-stream sample rate through AAudio. Exclusive mode is required
// when requested; shared mode makes no guarantee about downstream resampling.
// Uses LOW_LATENCY performance mode and
// and a blocking write path owned by the caller's thread (ExoPlayer's audio
// rendering thread).
//
// Bit-perfect rule: a stream opened with Config::bitPerfect, and a stream the
// caller declared a DoP carrier (Config::dop / SetBitPerfect), run at unity
// gain — SetVolume() stores 1.0f instead of the requested value, warns once
// and flags the rejection, and Write() never scales samples on those paths.
// Both flags are honoured only on an EXCLUSIVE stream; the packed 24-bit
// container is no longer treated as a DoP tell, so ordinary 24-bit PCM keeps
// its volume. Every other configuration applies volume on a scratch copy;
// caller buffers are never mutated.
//
// Threading: one writer thread max. Close() may be called from any thread
// and is ordered via an atomic flag so a blocked write exits promptly.
#ifndef PULSR_AAUDIO_SINK_H_
#define PULSR_AAUDIO_SINK_H_

#include <aaudio/AAudio.h>

#include "AAudioSinkSupport.h"

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
        Int32 = 4,       // AAUDIO_FORMAT_PCM_I32 (API 31+)
    };

    struct Config {
        int32_t sampleRate = 48000;
        int32_t channelCount = 2;
        Encoding encoding = Encoding::Int16;
        // Caller asserts bit-exact output: the stream is opened EXCLUSIVE or not
        // at all, and volume stays at unity (SetVolume() rejects anything else).
        bool bitPerfect = false;
        // Caller declares this stream a DoP carrier: the words are DSD payload,
        // not PCM, so they must never be scaled. Only honoured when the open
        // stream is EXCLUSIVE; SetBitPerfect() can re-assert it live.
        bool dop = false;
        // Prefer EXCLUSIVE sharing and refuse the SHARED ladder rungs. On its own
        // it no longer implies unity gain — that is bitPerfect's job.
        bool preferExclusive = true;
        bool lowLatency = true;        // PERFORMANCE_MODE_LOW_LATENCY on SHARED
        int32_t deviceId = 0;          // 0 follows platform policy
        int32_t targetBufferMs = 150;  // 0 => device default capacity
    };

    AAudioSink();

    // Requires EXCLUSIVE for bit-perfect/DoP; otherwise uses the shared ladder.
    // Returns false and fills `error` on failure. Closes any previous stream
    // before applying the new configuration.
    bool Open(const Config& config, std::string* error);

    // Blocks until the stream is released. Safe from any thread.
    void Close();

    // Consumes exactly `sizeBytes` from `data` (blocking until accepted).
    // Returns bytes consumed, or -1 on error/close.
    int32_t Write(const uint8_t* data, int32_t sizeBytes);

    void Play();
    void Pause();
    // Best-effort flush (pause + requestFlush + restart); rebases the position
    // counters so position math stays monotonic per configuration. Some MMAP /
    // exclusive HALs refuse requestFlush; rebasing over an untouched device
    // buffer would replay pre-seek audio, so the stream is rebuilt at the same
    // config instead. A rebuild that fails leaves the sink closed: Write() then
    // reports -1 and the caller's AudioTrack fallback ladder engages.
    void Flush();

    // Unity-only while the sink is bit-perfect or a DoP carrier: the requested
    // value is rejected, 1.0f is stored instead, VolumeWasRejected() latches
    // true until the next Open(), and the first rejection is logged once per
    // stream so a dead volume slider is never silent to the caller.
    void SetVolume(float volume);

    // Re-asserts the live bit-perfect / DoP verdict without reopening the
    // stream. Returns false, leaving bitPerfect_ false, when bit-perfect is
    // requested on a non-EXCLUSIVE stream: a SHARED stream is resampled by
    // AudioFlinger, so the claim could not be honoured.
    bool SetBitPerfect(bool bitPerfect, bool dop);

    int64_t FramesRead() const;      // device-consumed frames since flush base
    int64_t FramesWritten() const;   // app-written frames since flush base
    int32_t XRunCount() const;
    int32_t XRunDelta() const;
    bool IsExclusive() const { return exclusive_.load(std::memory_order_acquire); }
    // True when the stream last opened by Open() was EXCLUSIVE. Reads a member
    // published at open/close instead of querying the AAudio stream, so it is
    // safe to call from any thread.
    bool IsExclusiveStream() const { return exclusive_.load(std::memory_order_acquire); }
    // True while this stream actually is bit-perfect: Config::bitPerfect (or
    // SetBitPerfect()) asserted it AND the open stream is EXCLUSIVE. Nothing
    // else publishes true, so a SHARED fallback can never claim it.
    bool IsBitPerfectSink() const { return bitPerfect_.load(std::memory_order_acquire); }
    // Latched by SetVolume() when a non-unity volume was refused because the
    // stream is unity-only. Cleared by the next Open(), so it describes the
    // current stream.
    bool VolumeWasRejected() const { return volumeRejected_.load(std::memory_order_acquire); }
    int32_t BufferCapacityFrames() const;
    int32_t FramesPerBurst() const;
    int32_t DeviceId() const;
    int64_t GetTimestampLatencyFrames() const;
    double GetOutputLatencyMs() const;
    int32_t SampleRate() const { return config_.sampleRate; }
    int32_t ChannelCount() const { return config_.channelCount; }
    bool HasPendingData() const;

private:
    // Open() body with streamMutex_ already held (Open() = lock + CloseLocked +
    // OpenLocked). Flush() reuses it to rebuild a stream whose requestFlush was
    // refused, without unlocking and racing Close()/Open() in between.
    // recoverPrev* forward TryOpen's recovery counters so a rebuild keeps
    // framesWritten_ continuous instead of jumping back to zero.
    bool OpenLocked(const Config& config, std::string* error,
                    int64_t* recoverPrevFramesWritten = nullptr,
                    int64_t* recoverPrevWrittenBase = nullptr);
    bool TryOpen(aaudio_sharing_mode_t sharing, aaudio_performance_mode_t perf,
                 int64_t* recoverPrevFramesWritten = nullptr,
                 int64_t* recoverPrevWrittenBase = nullptr);
    // drainTail: wait (bounded) for the device to consume frames it has already
    // accepted before requestStop() discards them. True for a live hand-over
    // (Close()/Open()), false when the queued tail is supposed to disappear
    // (Flush()) or cannot be consumed at all (disconnect recovery).
    void CloseLocked(bool waitForWriters = true, bool drainTail = true);
    static void ErrorCallback(AAudioStream* stream, void* userData, aaudio_result_t error);
    bool RecoverDisconnected();
    // Item 12: the buffer governor is a query-and-adjust helper that touches only
    // atomics and the AAudio C API, so it is const. That removes the const_cast
    // from XRunDelta() (whose JNI call site keeps its identical signature).
    void CheckAndAdaptBuffer(AAudioStream* st) const;
    void ShrinkBufferIfStable(AAudioStream* st) const;

    Config config_{};
    std::atomic<AAudioStream*> stream_{nullptr};
    std::mutex streamMutex_;
    std::mutex writeMutex_;
    mutable std::atomic<int32_t> activeReaders_{0};
    mutable std::atomic<int32_t> activeWriters_{0};
    std::atomic<bool> releasing_{false};
    std::atomic<bool> flushing_{false};
    AAudioRecoveryState recovery_;
    std::atomic<bool> exclusive_{false};
    // Bit-perfect sink: unity gain and no SHARED fallback. Atomic because
    // Write() reads it on the writer thread while Open() publishes a new value.
    // Only an EXCLUSIVE open publishes true; CloseLocked() clears it.
    std::atomic<bool> bitPerfect_{false};
    // DoP carrier (DSD words packed as 24-bit PCM): unity gain like bitPerfect_,
    // but independent of it, so 24-bit PCM is no longer mistaken for DoP.
    std::atomic<bool> dop_{false};
    std::atomic<bool> volumeRejected_{false};
    int32_t bytesPerFrame_ = 0;
    // TPDF state for the sink-side volume requantization (shared mode only).
    // Kept per stream instance so the sequence does not restart every block.
    SinkDitherState sinkDither_;
    std::atomic<int64_t> framesWrittenBase_{0}; // written-frame counter at last flush
    std::atomic<int64_t> framesWritten_{0}; // total written since open
    std::atomic<int64_t> readBase_{0}; // device read counter at last flush
    std::atomic<int64_t> readOffset_{0}; // timeline carried across disconnect recovery
    mutable std::atomic<int32_t> lastXRunCount_{0};
    std::atomic<int32_t> initialBufferFrames_{0};
    mutable std::atomic<int64_t> lastXRunTimestampMs_{0};
    mutable std::atomic<int64_t> lastShrinkTimestampMs_{0};
    std::atomic<float> volume_{1.0f};
    // Gain the writer thread actually ended the previous Write() on. Protected
    // by writeMutex_ (plain float, not atomic: it is only touched under that
    // lock). Write() ramps from here to volume_ across the whole call and stores
    // the endpoint, so a slider drag becomes one continuous ramp instead of a
    // hard step per buffer; Play() and SetBitPerfect() snap it so no stale
    // multiplier survives a flush/reopen or a mode flip.
    float appliedVolume_ = 1.0f;
    std::atomic<aaudio_result_t> lastWriteResult_{AAUDIO_OK};
    std::string lastError_;
    // Preallocated once in the constructor (64 KB). TryOpen never resizes it
    // while a writer may be active.
    std::vector<uint8_t> volumeScratch_;
    std::chrono::steady_clock::time_point lastRecoveryAttempt_{};
    int recoveryAttempts_ = 0;
};

}  // namespace pulsr

#endif  // PULSR_AAUDIO_SINK_H_
