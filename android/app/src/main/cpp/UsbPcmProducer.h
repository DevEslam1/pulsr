// android/app/src/main/cpp/UsbPcmProducer.h
//
// Reader-thread producer for the pull-based USB renderer.
//
// The pull renderer removes producer-clock steering, but a real-time producer
// (ExoPlayer's audio thread) can never fill a multi-second reservoir ahead of
// playback. This class is the missing half: a dedicated reader thread that
// decodes a local PCM WAV file and keeps the reservoir near full, while the USB
// worker pulls at the DAC's rate.
//
// SCOPE, HONESTLY:
//   * PCM WAV only. RIFF/WAVE, integer PCM, 16/24/32-bit, including
//     WAVE_FORMAT_EXTENSIBLE with a 24-in-32 container. No compressed formats:
//     FLAC/ALAC/Opus need a decoder adapter that produces the same frames.
//   * Bit-perfect only. The file format must equal the open stream format
//     (rate, channels, container bytes, valid bits). Anything else is refused;
//     this class never resamples, remaps or requantizes.
//   * The reader thread allocates once (open) and never in its loop. It writes
//     whole frames into the supplied UsbPullRenderer and sleeps when the
//     reservoir is full, so it cannot outrun the USB worker's memory bound.
//
// THREADING:
//   * open()/close()/seekToFrame() are control-thread operations. seekToFrame()
//     flushes the renderer, so the caller must have quiesced consumption (the
//     same rule as UsbPullRenderer::flush()).
//   * start() launches one reader thread; stop() joins it. setPaused() only
//     flips an atomic.
#ifndef PULSR_USB_PCM_PRODUCER_H_
#define PULSR_USB_PCM_PRODUCER_H_

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "UsbPullRenderer.h"

namespace pulsr {

/// Wire format a pull stream expects. `validBits` may be narrower than
/// `containerBytes * 8` (24-in-32); the producer refuses any mismatch.
struct UsbPcmFormat {
    int sampleRate = 0;
    int channels = 0;
    int containerBytes = 0;
    int validBits = 0;

    bool operator==(const UsbPcmFormat& other) const {
        return sampleRate == other.sampleRate && channels == other.channels &&
               containerBytes == other.containerBytes &&
               validBits == other.validBits;
    }
    bool operator!=(const UsbPcmFormat& other) const { return !(*this == other); }
};

class UsbPcmProducer {
public:
    UsbPcmProducer() = default;
    ~UsbPcmProducer();
    UsbPcmProducer(const UsbPcmProducer&) = delete;
    UsbPcmProducer& operator=(const UsbPcmProducer&) = delete;

    /// Opens `path`, validates the WAV against `target`, configures `out` with
    /// `bufferMs` and prepares the reader. Does not start the thread.
    /// Returns false and sets lastError() on any mismatch or malformed file.
    /// `configureRenderer` is false when the caller already configured `out`
    /// for this stream (the sink does it in Open): reconfiguring a live ring
    /// would race the USB worker.
    bool open(const std::string& path, const UsbPcmFormat& target,
              UsbPullRenderer& out, int bufferMs = 3000,
              bool configureRenderer = true);

    /// Stops the reader (if running) and releases the file/buffers. The
    /// renderer is left configured and is not reset.
    void close();

    void start();
    void stop();

    /// Pauses/resumes filling. Already-buffered audio may still be consumed.
    void setPaused(bool paused) { paused_.store(paused, std::memory_order_release); }
    bool paused() const { return paused_.load(std::memory_order_acquire); }

    /// Drops the reservoir and continues at `frame`. Control thread only; the
    /// caller must have quiesced consumption (see file header).
    bool seekToFrame(uint64_t frame);

    bool isOpen() const { return file_ != nullptr; }
    bool finished() const { return finished_.load(std::memory_order_acquire); }
    uint64_t framesRead() const { return framesRead_.load(std::memory_order_relaxed); }
    uint64_t framesWritten() const { return framesWritten_.load(std::memory_order_relaxed); }
    uint64_t totalFrames() const { return totalFrames_; }
    int fillMs() const { return renderer_ != nullptr ? renderer_->fillMs() : 0; }
    const std::string& lastError() const { return lastError_; }

private:
    void threadMain();
    bool parseWav();
    bool readFrameChunk(uint8_t* dst, int maxFrames, int* gotFrames);

    static constexpr int kChunkFrames = 2048;
    static constexpr int kIdleSleepMs = 2;

    UsbPullRenderer* renderer_ = nullptr;
    std::FILE* file_ = nullptr;
    UsbPcmFormat format_{};
    int frameBytes_ = 0;
    uint64_t dataOffset_ = 0;
    uint64_t dataBytes_ = 0;
    uint64_t totalFrames_ = 0;

    std::vector<uint8_t> buffer_;
    std::thread thread_;
    mutable std::mutex fileMutex_;
    std::atomic<bool> running_{false};
    std::atomic<bool> paused_{false};
    std::atomic<bool> finished_{false};
    std::atomic<uint64_t> seekRequest_{UINT64_MAX};
    std::atomic<uint64_t> framesRead_{0};
    std::atomic<uint64_t> framesWritten_{0};
    std::string lastError_;
};

}  // namespace pulsr

#endif  // PULSR_USB_PCM_PRODUCER_H_
