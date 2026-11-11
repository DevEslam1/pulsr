// android/app/src/main/cpp/UsbAudioSink.h
//
// Experimental UAC2 isochronous USB audio sink.
//
// Android's public UsbRequest API has no isochronous transfer support, so this
// drives the usbfs interface directly (the same approach UAPP/Poweramp use):
// the Kotlin layer opens the device, force-claims the AudioStreaming interface,
// selects the alternate setting whose FORMAT_TYPE_I matches the requested
// rate+depth, and programs the DAC sample clock; it then hands the raw usbfs
// file descriptor and the isochronous OUT endpoint address to this sink.
//
// A worker thread keeps a small pool of isochronous URBs submitted. Audio
// frames arrive as float [-1,1] and are packed to the DAC's wire format -
// S16_LE (2-byte subslot), S24_3LE (3-byte) or S32_LE (4-byte) per the selected
// alt setting - and copied from a bounded ring buffer. On underrun the missing
// frames are emitted as silence so timing never stalls. If the DAC exposes an
// asynchronous feedback IN endpoint, the sink reads it and nudges the OUT
// per-packet sample counts toward the DAC's clock to limit drift.
//
// HONEST SCOPE: this is unvalidated against physical hardware. It is only
// activated by the explicit "USB Bit-Perfect Streaming" action. Startup failure
// restores HAL only after submitted USB ownership has been drained; a failed
// drain retains buffers and HAL exclusivity until control teardown succeeds.
#ifndef PULSR_USB_AUDIO_SINK_H_
#define PULSR_USB_AUDIO_SINK_H_

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

#include "SinkQuantizer.h"
#include "UsbGapFader.h"

namespace pulsr {

enum class UsbStreamResult : int32_t {
    Ok = 0,
    ClaimFailed = 1,
    AltSettingFailed = 2,
    RateUnsupported = 3,
    SubmitFailed = 4,
    InvalidArgs = 5
};

static_assert(std::atomic<int64_t>::is_always_lock_free &&
              std::atomic<uint64_t>::is_always_lock_free &&
              std::atomic<uint32_t>::is_always_lock_free,
              "USB render admission/status must use lock-free atomics");

class UsbAudioSink {
public:
    static UsbAudioSink& instance();

    // fd: usbfs fd from UsbDeviceConnection.getFileDescriptor().
    // endpointAddress: isochronous OUT endpoint (bit 7 clear).
    // interfaceNumber/altSetting: the claimed AudioStreaming interface.
    UsbStreamResult Open(int fd, int endpointAddress, int interfaceNumber, int altSetting,
                         int sampleRate, int channels, int bytesPerSample,
                         int validBitDepth = 0);
    void Close();
    bool IsActive() const;
    // HAL exclusivity lasts until control teardown drains USB ownership, even
    // if the worker self-exits. Faults must not silently leak to normal output.
    bool IsExclusive() const { return exclusive_.load(std::memory_order_acquire); }
    int GetLastError() const { return lastError_.load(std::memory_order_acquire); }
    uint64_t GetUnderrunCount() const { return underrunCount_.load(std::memory_order_relaxed); }
    uint64_t GetOverrunCount() const { return overrunCount_.load(std::memory_order_relaxed); }
    // Frames written while the producer's channel count differed from the sink's.
    // Non-zero means the wire data is not sample-identical to the engine blocks
    // (channels were duplicated, silenced or dropped), so status must surface it.
    uint64_t GetChannelMismatchFrames() const { return channelMismatchFrames_.load(std::memory_order_relaxed); }
    void ResetChannelMismatchFrames() { channelMismatchFrames_.store(0, std::memory_order_relaxed); }
    double GetBufferedMs();

    // Queries supported sample rates for the AudioStreaming interface using USBDEVFS_CONTROL.
    static std::vector<int> QuerySupportedRates(int fd, int interfaceNumber);

    // Parses supported sample rates from raw configuration descriptors (UAC1 Format Type I).
    static std::vector<int> ParseSupportedRatesFromDescriptors(const uint8_t* desc, size_t len, int targetInterface = -1);

    // Pure USB-sizing math, split out so it is host-verifiable without a device.
    //
    // DecodeFeedbackRatePerSec decodes one async-feedback sample and returns the
    // clamped OUT rate (samples/sec) to steer toward, or 0 to mean "ignore this
    // sample, keep the current rate." 3-byte samples are Q10.14 per 1 ms frame;
    // 4-byte samples are Q16.16 per 125 us microframe. A decode outside +/-10%
    // of nominal is rejected (buggy device / wrong fixed-point format); an
    // accepted decode is hard-clamped to +/-0.1% of nominal.
    static int DecodeFeedbackRatePerSec(const uint8_t* data, int len, int nominalRate);

    struct EndpointTiming {
        int intervalUs = 0;
        int maxPacketBytes = 0;
    };

    static EndpointTiming ParseEndpointTiming(const uint8_t* desc, size_t len,
                                              int interfaceNumber, int altSetting,
                                              int endpointAddress, int usbSpeed);
    static int NextPacketFrames(uint64_t& accumulator, uint32_t ratePerSec,
                                int intervalUs, int maxFramesPerPacket);
    // Steers nominal packet cadence within +/-0.1% based on ring fill when the
    // DAC exposes no async feedback IN endpoint, limiting clock-drift underruns
    // or overruns without touching sample bits.
    static int SteerPacketRateForRingFill(int currentRatePerSec, int nominalRate,
                                          size_t occupiedBytes, size_t capacityBytes);

    // Audio-thread call: packs float [-1,1] to the configured interleaved wire
    // format (S16_LE / S24_3LE / S32_LE per bytesPerSample_) and appends to the
    // ring. Non-blocking; excess data is dropped (never blocks playback).
    bool WriteInterleaved(const float* buffer, int frames, int channels,
                          int sampleRate, int64_t producerId);
    bool WritePcm(const uint8_t* buffer, int frames, int channels,
                  int sourceBitDepth, int sampleRate, int64_t producerId);
    void ReleaseProducer(int64_t id);
    void ReportWriteError(int error);
    int GetRawPcmBitDepth() const {
        const uint64_t status = rawPcmStatus_.load(std::memory_order_acquire);
        return (status >> 8) == deliveryEpoch_.load(std::memory_order_acquire)
            ? static_cast<int>(status & 0xff) : 0;
    }

    int sampleRate() const { return sampleRate_; }
    int channels() const { return channels_; }

private:
    UsbAudioSink() = default;
    ~UsbAudioSink();
    UsbAudioSink(const UsbAudioSink&) = delete;
    UsbAudioSink& operator=(const UsbAudioSink&) = delete;

    void workerLoop();
    using UrbSubmit = int (*)(int fd, void* urb);
    static int submitUsbfsUrb(int fd, void* urb);
    // Establishes startup exclusivity before submitting; injectable syscall for
    // host ownership regressions (production always uses usbfs).
    bool submitAll(UrbSubmit submit = submitUsbfsUrb);
    void releaseResources();
    bool drainUrbCompletions();
    bool beginWrite(int64_t producerId);
    void endWrite();
    bool writeBlock(const float* floats, const uint8_t* pcm, int frames,
                    int channels, int sourceBitDepth, int sampleRate, int64_t producerId);
    bool markReaped(void* urb, bool* feedback, size_t* index);
    bool hasOutstandingUrbs() const;
    bool submitUrb(void* urb, bool feedback, size_t index,
                   UrbSubmit submit = submitUsbfsUrb);
    static int completionError(const void* urb, bool feedback, int packets, int maxBytes);
    friend struct UsbAudioSinkTestAccess;

    // --- Async feedback (anti-drift) support, FIX 2 ---
    // Open fetches configuration descriptors once for timing and feedback.
    static std::vector<uint8_t> fetchConfigDescriptor(int fd);
    // Parses that complete configuration: endpoint address when found, 0 only
    // for proven absence, or -1 for malformed/truncated/missing interface data.
    // *outPacketSize receives wMaxPacketSize only on a successful parse.
    static int findFeedbackEndpoint(const uint8_t* config, size_t len,
                                    int interfaceNumber, int altSetting,
                                    int* outPacketSize);
    // Allocates/submits feedback. A failure fails startup; unified teardown
    // cancels and reaps both pools by identity before any buffers can be freed.
    bool setupFeedbackUrbs();
    // Decodes one feedback sample and updates feedbackRatePerSec_ (worker only).
    void applyFeedback(const uint8_t* data, int len);
    // Frees the feedback URB buffers/vectors. Callers must have cancelled+reaped
    // the feedback URBs first (drainUrbCompletions / setup rollback).
    void freeFeedbackResources();

    std::atomic<bool> active_{false};
    std::atomic<bool> exclusive_{false};
    std::atomic<bool> running_{false};
    std::atomic<int> lastError_{0};
    std::atomic<uint64_t> underrunCount_{0};
    std::atomic<uint64_t> overrunCount_{0};
    std::atomic<uint64_t> channelMismatchFrames_{0};
    // One atomic gate covers admission AND teardown. Bit 0 = admitted writer,
    // bit 1 = closed. Closing cannot miss a producer between check and entry.
    static constexpr uint32_t kWriterBusy = 1;
    static constexpr uint32_t kWriterClosed = 2;
    std::atomic<uint32_t> writerGate_{kWriterClosed};
    std::atomic<int64_t> producerOwner_{0};
    std::atomic<int> producerRawDepth_{0};
    std::atomic<uint64_t> rawPcmStatus_{0}; // delivery epoch in high bits, depth in low byte
    std::atomic<uint64_t> deliveryEpoch_{0};
    std::mutex controlMutex_; // Open/Close only; never render/worker
    bool sinkDepthPublished_ = false;

    int fd_ = -1;
    int endpoint_ = 0;
    int interfaceNumber_ = -1;
    int altSetting_ = 0;
    int sampleRate_ = 48000;
    int channels_ = 2;
    int bytesPerSample_ = 2;  // wire subslot bytes
    int validBitDepth_ = 16;
    // TPDF state for the packing step. Persists across blocks on purpose: a
    // per-call state would restart the sequence every block and make the dither
    // noise periodic, which is a tonal artifact instead of a noise floor.
    SinkDitherState producerDither_;
    SinkDitherState workerDither_;
    // Rides the output to silence on a ring underrun and back up on resume, so
    // neither boundary is a step. Inert (pass-through) while the ring has data.
    UsbGapFader gapFader_;
    bool claimed_ = false;

    int packetsPerUrb_ = 8;
    int bytesPerPacket_ = 0;
    int bytesPerUrb_ = 0;

    // Worker-thread-only packet sizing state (FIX 2). frameAccumulator_ carries
    // the fractional samples-per-packet remainder (e.g. 44.1 kHz -> 44/45 frame
    // packets); maxFramesPerPacket_ caps a packet so feedback can never overflow
    // the preallocated URB buffer. feedbackRatePerSec_ is the clamped target
    // sample rate the feedback endpoint last reported (== sampleRate_ until a
    // feedback sample arrives).
    uint64_t frameAccumulator_ = 0;
    int serviceIntervalUs_ = 0;
    int maxFramesPerPacket_ = 0;
    int feedbackRatePerSec_ = 0;

    // Async feedback IN endpoint (0 => DAC has no feedback endpoint).
    int feedbackEndpoint_ = 0;
    int feedbackPacketSize_ = 0;
    int feedbackPacketsPerUrb_ = 0;
    int numFeedbackUrbs_ = 0;
    std::vector<uint8_t> feedbackUrbStorage_;
    std::vector<uint8_t*> feedbackBuffers_;
    std::vector<void*> feedbackUrbs_;
    std::vector<uint8_t> feedbackOwned_;
    size_t feedbackUrbStride_ = 0;

    std::thread worker_;

    // Preallocated URB storage + buffers (1 URB header + N packet descriptors).
    std::vector<uint8_t> urbStorage_;
    std::vector<uint8_t*> urbBuffers_;
    std::vector<void*> urbs_;
    std::vector<uint8_t> urbOwned_;
    std::vector<int> urbRawDepth_;
    std::vector<uint64_t> urbDeliveryEpoch_;
    size_t urbStride_ = 0;
    int numUrbs_ = 0;

    // Lock-free single-producer single-consumer (SPSC) byte ring buffer.
    // Audio thread produces; USB worker thread consumes. Wait-free for audio thread.
    std::vector<uint8_t> ring_;
    // Depth at each frame's first byte, published with ringWrite_. 0 = float.
    std::vector<uint8_t> ringRawDepth_;
    size_t ringMask_ = 0;
    alignas(64) std::atomic<size_t> ringWrite_{0};
    alignas(64) std::atomic<size_t> ringRead_{0};
};

} // namespace pulsr

#endif // PULSR_USB_AUDIO_SINK_H_
