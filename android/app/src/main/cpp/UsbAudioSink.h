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
// When that teardown is forced (the caller releases the interface and closes
// the connection itself), Abandon() drops the dead stream for good and leaks
// whatever the kernel might still write to, so the next Open starts clean.
#ifndef PULSR_USB_AUDIO_SINK_H_
#define PULSR_USB_AUDIO_SINK_H_

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "SinkQuantizer.h"
#include "DopGapSilence.h"
#include "UsbGapFader.h"
#include "UsbPullRenderer.h"
#include "UsbAsrcClockSync.h"
#include "UsbClockDomain.h"

namespace pulsr {

class UsbPcmProducer;

enum class UsbStreamResult : int32_t {
    Ok = 0,
    ClaimFailed = 1,
    AltSettingFailed = 2,
    RateUnsupported = 3,
    SubmitFailed = 4,
    InvalidArgs = 5
};

// How the USB worker obtains frames. These values are a wire contract with
// Kotlin/Dart (lib/features/usb_tools/usb_stream_mode.dart sends the same
// numbers), so they must never be renumbered.
//
//   BestEffort     - the existing real-time producer ring: float or raw PCM is
//                    packed on the producer thread and steered by the feedback
//                    endpoint or, when there is none, by ring fill.
//   BitPerfectPull - whole frames are pulled from UsbPullRenderer and handed to
//                    the wire untouched, so payloads stay bit-exact.
//   ClockSyncAsrc  - decoded float is resampled by UsbAsrcClockSync to follow
//                    the DAC clock. Never bit-perfect by construction.
//
//   DsdNative      - native DSD transport (DSD_U32). The producer hands over one
//                    1-bit payload per channel and the sink packs it into 32-bit
//                    little-endian words (pulsr::PackDsdBitsToWords) with no
//                    dither, no software gain and no float roundtrip, so the
//                    payload reaches the wire bit-for-bit. BitPerfect-shaped:
//                    no ASRC and no pull reservoir. Payloads travel through the
//                    same ring/URB path as BestEffort, but an underrun is filled
//                    with the DC-neutral DSD silence pattern instead of PCM
//                    zeroes, and UsbGapFader stays out of the path (it fades PCM
//                    words). Admitted only for a 4-byte subslot, 32 valid bits,
//                    two channels and a framesPerSecond on the DSD64/128/256/512
//                    U32 ladder (see CheckStreamShape).
//
// Open() starts BitPerfectPull/ClockSyncAsrc only when their engines are part
// of the link. They are not yet: UsbPullRenderer.cpp and UsbAsrcClockSync.cpp
// are absent from DSP_CORE_SOURCES (main/cpp/CMakeLists.txt) and from DSP_SRCS
// (test/cpp/CMakeLists.txt), while this sink lives in UsbAudioSink.cpp.
// Calling those engines from here would leave the host tests unlinked and make
// the Android library fail to dlopen, so Open() fails both modes closed with
// InvalidArgs instead of silently streaming something the caller did not ask
// for. Tuning, status and domain derivation are already wired so that adding
// the two translation units is all the engines need to go live.
enum class UsbRenderMode : int32_t {
    BestEffort = 0,
    BitPerfectPull = 1,
    ClockSyncAsrc = 2,
    DsdNative = 3,
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
    // alreadyConfigured: true when the caller (UsbExclusivePlugin) already
    // claimed the interface, selected altSetting, and programmed/verified the
    // DAC sample clock — skips redundant USBDEVFS_CLAIMINTERFACE and
    // USBDEVFS_SETINTERFACE ioctls that reset the hardware clock on UAC1/UAC2
    // DACs, and leaves kernel driver rebind order to the caller.
    // renderMode: a UsbRenderMode value. Only BestEffort (0, the default) is
    // startable in this build; see the UsbRenderMode note above. An unknown
    // value is rejected like any other bad geometry.
    UsbStreamResult Open(int fd, int endpointAddress, int interfaceNumber, int altSetting,
                         int sampleRate, int channels, int bytesPerSample,
                         int validBitDepth = 0, bool alreadyConfigured = false,
                         int renderMode = 0);
    // Stops the worker and tears the stream down. Returns false when submitted
    // URBs could not be reaped inside the bounded drain window (lastError_ =
    // ETIMEDOUT): URB storage, the claimed interface and HAL exclusivity are
    // retained so no kernel-owned transfer is ever freed; the next Open then
    // refuses to start rather than reusing a half-torn-down sink. Abandon() is
    // the only escape from that state, and only after the caller has closed the
    // connection itself.
    bool Close();
    // Forced teardown for a caller that already released the interface and
    // closed the usbfs connection because Close() reported a failed drain.
    // Nothing on that dead fd can ever be reaped, so this stops the worker,
    // withdraws the sink-depth / direct-USB publication, deliberately leaks the
    // URB headers and packet buffers the kernel may still write to, and returns
    // the sink to its pristine pre-Open state: no outstanding URBs, fd_ = -1, no
    // claim, exclusive_ = false and lastError_ cleared, so a completed forced
    // teardown is never reported as a live fault. Without it every later Open
    // would drain a dead fd and fail with ClaimFailed for the rest of the
    // process. Safe to call more than once.
    void Abandon();
    // Re-attaches the kernel driver (snd-usb-audio) to interfaceNumber on fd
    // via USBDEVFS_IOCTL(USBDEVFS_CONNECT). Must be called after releasing the
    // interface; for USB audio devices, rebind AudioControl (interface 0) first
    // so snd-usb-audio probes the card and claims its streaming interfaces.
    static bool RebindKernelDriver(int fd, int interfaceNumber);
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
    // Bounded backpressure check: returns 0 when `frames` fit in the ring,
    // 1 when active & exclusive but full after `maxWaitMs`, or -1 when
    // inactive/closed/unbounded so callers can route through normal error handling.
    int WaitForWriteSpace(int frames, int maxWaitMs);

    // Lock-free check used by the ExoPlayer tap to avoid stalling behind a full
    // silent AudioTrack while the Direct USB ring/reservoir still needs frames
    // to reach or maintain its prefill cushion.
    bool NeedsPrefillCushion() const;

    // ---- Stream shape and clock-domain telemetry --------------------------
    // Control-thread configuration for the NEXT Open(); it never mutates a live
    // stream. Callers (UsbExclusivePlugin) set it before starting.
    //   transferSizeBytes       > 0 batches packet sizing into
    //                           clamp(bytes / maxBytesPerPacket, 1, 64) packets
    //                           per URB instead of deriving it from
    //                           kTargetUrbDurationUs. A value too small to fill
    //                           one packet, or <= 0, keeps the automatic sizing.
    //   bufferMs                > 0 records the pull-renderer buffer target,
    //                           capped at 10000 ms. 0 = automatic (3000 ms for a
    //                           pull stream). Only the pull path consumes it; the
    //                           BestEffort ring keeps its own sizing.
    //   disableExplicitFeedback true ignores an advertised feedback IN endpoint
    //                           (no feedback URBs are submitted) and lets ring
    //                           steering own the packet cadence.
    void SetStreamTuning(int transferSizeBytes, int bufferMs, bool disableExplicitFeedback);

    // Reader-thread source for the pull renderer: a local PCM WAV whose format
    // exactly matches the open stream. Only valid in BitPerfectPull mode; the
    // producer fills the multi-second reservoir ahead of the USB worker, which
    // is what a real-time ExoPlayer producer cannot do. Returns false on a
    // format mismatch, a non-pull stream, or an unreadable file.
    bool StartPcmFile(const std::string& path);
    void StopPcmFile();
    bool HasPcmFileSource() const;

    // Live transport status for the Kotlin/Dart telemetry surfaces. Unknown
    // whenever no stream is running, including after a failed Open. Serialises
    // with control teardown (the same mutex Open/Close take) instead of reading
    // half-updated geometry; never called from the worker.
    UsbClockStatus GetClockStatus() const;

    // Pure policy: which clock domain a stream is actually in. Public so the
    // host tests can pin the contract without a device. A pull stream only
    // earns BitPerfectLocked while it is eligible, has never underrun and has
    // never seen a channel mismatch; everything else degrades to BestEffort.
    static UsbClockDomain DeriveClockDomain(UsbRenderMode mode, bool active,
                                            bool bitPerfectEligible, uint64_t underruns,
                                            uint64_t channelMismatch);

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
    // Steers nominal packet cadence within +/-1% based on ring fill when the
    // DAC exposes no async feedback IN endpoint, limiting clock-drift underruns
    // or overruns without touching sample bits. That range must cover the real
    // crystal error of cheap feedback-less DACs (0.2-0.6%): a +/-0.1% window
    // saturates immediately and leaves the ring to gap-fill every ~80 s.
    static int SteerPacketRateForRingFill(int currentRatePerSec, int nominalRate,
                                          size_t occupiedBytes, size_t capacityBytes);

    // Audio-thread call: packs float [-1,1] to the configured interleaved wire
    // format (S16_LE / S24_3LE / S32_LE per bytesPerSample_) and appends to the
    // ring. Non-blocking; excess data is dropped (never blocks playback).
    bool WriteInterleaved(const float* buffer, int frames, int channels,
                          int sampleRate, int64_t producerId);
    bool WritePcm(const uint8_t* buffer, int frames, int channels,
                  int sourceBitDepth, int sampleRate, int64_t producerId);
    // Native DSD (DsdNative) producer call. `bytesPerChannel` is the 1-bit
    // payload size per channel, NOT a PCM sample count: each byte carries 8 DSD
    // samples, LSB-first (DSF bit order; DFF is MSB-first and must be
    // bit-reversed upstream). The sink packs each channel into 4-byte
    // little-endian words (pulsr::PackDsdBitsToWords), so `bytesPerChannel`
    // bytes become ceil(bytesPerChannel / 4) stereo frames and a trailing
    // partial word is zero-padded on its high side. No dither, no gain and no
    // float conversion: the payload reaches the wire bit-for-bit.
    //
    // Same transport semantics as WritePcm: all-or-nothing (a block that does
    // not fit the ring is refused whole, with overrunCount and ENOSPC, never
    // partially delivered), the same producer admission gate, and ordering is
    // preserved across refused blocks. Returns false in every PCM mode, when no
    // DSD stream is open, and for a payload larger than kMaxDsdBytesPerCall.
    bool WriteDsd(const uint8_t* left, const uint8_t* right, int bytesPerChannel,
                  int64_t producerId);
    // True only while a native-DSD stream is open and live. Telemetry only; it
    // is lock-free and answers false in every PCM mode and after teardown.
    bool IsDsdActive() const;
    // Upper bound on one WriteDsd call, per channel (1 MiB of 1-bit payload -
    // ~23 s of DSD64, far beyond any decoder block). Enforced here and mirrored
    // by the JNI array copy so a bogus Kotlin length is rejected before it can
    // size a buffer.
    static constexpr int kMaxDsdBytesPerCall = 1 << 20;
    // Native-DSD gap silence: alternating 0x69 / 0x96 bytes, LSB-first, as a
    // continuous byte stream. Both bytes carry exactly four 1-bits out of eight,
    // so every byte - and therefore every 32-bit word built from four of them -
    // is exactly 50 % bit density: zero DC after the DAC's low-pass, with the
    // alternation keeping the idle pattern off a standing DC and sharing the
    // quantisation noise across the band. `firstPhase` is kDsdSilenceByteA or
    // kDsdSilenceByteB; the return value is the phase the next call must use.
    static constexpr uint8_t kDsdSilenceByteA = 0x69;
    static constexpr uint8_t kDsdSilenceByteB = 0x96;
    static uint8_t FillDsdSilence(uint8_t* dst, int bytes, uint8_t firstPhase);
    // Pure stream-shape admission policy (no device access), so the PCM/DSD
    // geometry matrix has exactly one implementation and is host-testable.
    // Returns Ok when `mode` can carry this geometry, InvalidArgs when it
    // cannot, and RateUnsupported when the geometry fits but framesPerSecond is
    // off the mode's ladder (for DsdNative the DSD64/128/256/512 U32 rungs, via
    // pulsr::DsdRateForAltSetting). An unknown mode value is InvalidArgs.
    static UsbStreamResult CheckStreamShape(UsbRenderMode mode, int channels,
                                            int bytesPerSample, int validBitDepth,
                                            int framesPerSecond);
    // Item 3: per-producer DoP marker flag. The JNI direct-USB tap sets this from
    // `engine->getParams()->bitPerfect.isDop` before WritePcm(); the USB worker
    // reads it so an underrun gap is filled with valid DoP silence (zero payload
    // + alternating 0x05/0xFA markers) instead of raw zeros, which would destroy
    // the marker stream and make a DoP-capable DAC lose lock. Single writer (the
    // JNI tap), atomic so the worker never observes a torn value.
    void SetProducerDop(bool isDop) {
        producerIsDop_.store(isDop, std::memory_order_relaxed);
    }
    bool IsProducerDop() const {
        return producerIsDop_.load(std::memory_order_relaxed);
    }
    void ReleaseProducer(int64_t id);
    void SetPaused(bool paused);
    bool IsPaused() const { return paused_.load(std::memory_order_acquire); }
    void FlushStream();
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
    size_t fillPacketFromRing(uint8_t* dst, int framesInPacket, size_t& readFrame,
                              int& rawDepth, uint64_t& deliveryEpoch);
    // Packet fill for the pull modes. Returns the packet length in bytes and
    // updates rawDepth (0 for the ASRC path, validBitDepth_ for raw pull).
    size_t fillPullPacket(uint8_t* dst, int framesInPacket, int& rawDepth);
    size_t fillAsrcPacket(uint8_t* dst, int framesInPacket, int& rawDepth);
    // Live clock-drift ratio for ClockSyncAsrc (worker-thread only, lock-free).
    // Uses feedbackRatePerSec_ / sampleRate_ when an explicit feedback endpoint
    // is active, or proportional reservoir fillMs vs midpoint when feedback is
    // absent; always clamped to [UsbAsrcClockSync::kMinRatio, kMaxRatio].
    double computeAsrcRatio() const;
    // Sizes ASRC staging buffers against maxFramesPerPacket_ (with a 2048-frame
    // floor) so high-rate 10 ms packets cannot overflow asrcPack_/asrcOut_.
    void allocateAsrcBuffers();
    // Parses and validates the feedback endpoint descriptor, applying
    // disableExplicitFeedback_ only after validation succeeds so malformed
    // descriptors are never masked and feedbackPacketSize_ is cleanly zeroed.
    bool configureFeedbackFromDescriptor(const uint8_t* config, size_t len);
    using UrbSubmit = int (*)(int fd, void* urb);
    static int submitUsbfsUrb(int fd, void* urb);
    // Establishes startup exclusivity before submitting; injectable syscall for
    // host ownership regressions (production always uses usbfs).
    bool submitAll(UrbSubmit submit = submitUsbfsUrb);
    // False => USB ownership was not drained. Kernel-owned URB buffers, the
    // claimed interface and exclusive_ all stay live for a later teardown.
    bool releaseResources();
    // Injectable non-blocking reap so the bounded-drain deadline is host
    // testable. Production always reaps through reapUsbfsUrb.
    using UrbReap = int (*)(int fd, void** urb);
    // USBDEVFS_REAPURBNDELAY on Linux/Android. On other hosts there is no usbfs
    // endpoint, so it answers exactly like an idle one: errno = EAGAIN, -1.
    static int reapUsbfsUrb(int fd, void** urb);
    // Bounded teardown: polls `reap` with a 1 ms backoff against a steady_clock
    // deadline instead of blocking forever in USBDEVFS_REAPURB. The deadline is
    // re-checked before every reap, so a queue that keeps reporting duplicate or
    // foreign completions is bounded exactly like an idle one. On timeout it sets
    // lastError_ = ETIMEDOUT and returns false, leaving every buffer and the
    // interface claim in place. timeoutMs = 0 budgets no reaps at all, so it can
    // only succeed when nothing is outstanding. The loop is not #if'd out, so
    // host builds exercise the deadline itself.
    bool drainUrbCompletions(int timeoutMs = 2000, UrbReap reap = reapUsbfsUrb);
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
    std::atomic<bool> paused_{false};
    std::atomic<int> lastError_{0};
    std::atomic<int64_t> lastFaultLogNs_{0};
    std::atomic<int64_t> lastRejectLogNs_{0};
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
    // Item 3: true while the producer is handing us DoP words (raw, marker in
    // the MSB). Read only by the USB worker; written by the JNI tap.
    std::atomic<bool> producerIsDop_{false};
    // Native-DSD admission latch, published by Open() and cleared by
    // releaseResources()/Abandon(). Lock-free so the PCM-API refusal in
    // writeBlock(), the DSD gap fill and IsDsdActive() telemetry never touch the
    // control mutex (a producer must never contend with teardown).
    std::atomic<bool> dsdMode_{false};
    // Worker-only phase of the DSD gap pattern, so the alternation stays
    // continuous across packets and URBs (0x69 first, then 0x96, ...).
    uint8_t dsdSilencePhase_ = kDsdSilenceByteA;
    // Marker the next synthesized DoP gap frame must use. Worker-thread-only:
    // it is re-derived from the last real frame of every packet, so a mid-stream
    // restart or a producer phase change cannot desynchronise the alternation.
    uint8_t dopMarkerPhase_ = kDopMarkerA;
    std::atomic<uint64_t> rawPcmStatus_{0}; // delivery epoch in high bits, depth in low byte
    std::atomic<uint64_t> deliveryEpoch_{0};
    // Open/Close/Abandon plus the status getters; never render/worker.
    // Mutable so the const status getter can serialise with control teardown.
    mutable std::mutex controlMutex_;
    bool sinkDepthPublished_ = false;

    // Requested shape of the live stream (UsbRenderMode). Reset on teardown so
    // a stale mode cannot colour the status of the next stream.
    int renderMode_ = 0;
    // SetStreamTuning() values, applied by the next Open().
    int tunedTransferSizeBytes_ = 0;
    int tunedBufferMs_ = 0;
    bool disableExplicitFeedback_ = false;
    // Raw PCM blocks refused by the float-only ClockSyncAsrc path. Reported as
    // part of overrunCount so the UI can see that the producer handed the wrong
    // kind of data instead of a silent format change. Zero on every other path.
    std::atomic<uint64_t> asrcRawPcmRejected_{0};

    // Pull-based renderer used by BitPerfectPull (wire-format bytes) and by
    // ClockSyncAsrc (float frames). Configured once in Open, written by the
    // producer, read only by the USB worker; no lock in the hot path.
    UsbPullRenderer pullRenderer_;
    // Staging for a raw block whose source depth is narrower than the opened
    // wire container (16-in-24, 24-in-32). Sized in Open; the common equal-depth
    // case writes the producer buffer straight through.
    std::vector<uint8_t> pullPack_;
    size_t pullPackFrames_ = 0;
    // Optional file-backed producer feeding pullRenderer_ (pull mode only).
    std::unique_ptr<UsbPcmProducer> pcmProducer_;
    // Polyphase ASRC for ClockSyncAsrc. Configured in Open; setRatio() and
    // process() both run on the USB worker, so no cross-thread filter state.
    UsbAsrcClockSync asrc_;
    // Sticky for the session: false as soon as a float block, wrong depth/rate
    // or a short pull proves the payload is not a byte-for-byte source copy.
    // `disqualified` is the latch that keeps a later clean block from restoring
    // eligibility after a fault.
    std::atomic<bool> bitPerfectEligible_{false};
    std::atomic<bool> bitPerfectDisqualified_{false};
    // Worker-only ASRC staging. Sized in Open to hold one packet plus the
    // resampler lookahead, so the packet loop never allocates.
    std::vector<float> asrcIn_;
    std::vector<float> asrcOut_;
    std::vector<float> asrcPack_;
    int asrcOutAvail_ = 0;
    size_t asrcInputCapacityFrames_ = 0;
    // Raw integer producer blocks are converted here before entering the float
    // reservoir. Sized in Open; a block larger than this is refused (never
    // allocated on the audio thread).
    std::vector<float> asrcRawScratch_;
    size_t asrcRawScratchFrames_ = 0;

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
    // sample rate the feedback endpoint (or ring steering) last asked for
    // (== sampleRate_ until a feedback sample arrives). Atomic because the
    // status getter reads it from the control/JNI side while the worker steers.
    uint64_t frameAccumulator_ = 0;
    int serviceIntervalUs_ = 0;
    int maxFramesPerPacket_ = 0;
    std::atomic<int> feedbackRatePerSec_{0};

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

    // Lock-free single-producer single-consumer (SPSC) frame ring buffer.
    // Audio thread produces; USB worker thread consumes. Wait-free for audio thread.
    std::vector<uint8_t> ring_;
    // Source bit depth per frame (1 byte per frame, 1/frameBytes memory vs byte ring). 0 = float.
    std::vector<uint8_t> ringRawDepth_;
    size_t ringFrameMask_ = 0;
    // Frames that must be buffered before the DAC worker starts draining. The
    // producer writes at ~real time, so without a cushion the ring hovers near
    // zero and every scheduler jitter turns into gap-filled packets (audible
    // drops). Set from the sample rate in Open().
    size_t prefillFrames_ = 0;
    alignas(64) std::atomic<size_t> ringWrite_{0}; // cumulative frame write count
    alignas(64) std::atomic<size_t> ringRead_{0};  // cumulative frame read count
};

} // namespace pulsr

#endif // PULSR_USB_AUDIO_SINK_H_
