// android/app/src/main/cpp/UsbAudioSink.h
//
// Experimental UAC2 isochronous USB audio sink.
//
// Android's public UsbRequest API has no isochronous transfer support, so this
// drives the usbfs interface directly (the same approach UAPP/Poweramp use):
// the Kotlin layer opens the device, force-claims the AudioStreaming interface
// and selects its alternate setting, then hands the raw usbfs file descriptor
// and the isochronous OUT endpoint address to this sink.
//
// A worker thread keeps a small pool of isochronous URBs submitted; audio
// frames are converted to interleaved S16_LE and copied from a bounded ring
// buffer. On underrun the missing frames are emitted as silence so timing never
// stalls.
//
// HONEST SCOPE: this is unvalidated against physical hardware. It is only
// activated by the explicit "USB Bit-Perfect Streaming" action, and any open
// failure releases the interface and leaves the normal HAL path untouched.
#ifndef PULSR_USB_AUDIO_SINK_H_
#define PULSR_USB_AUDIO_SINK_H_

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

namespace pulsr {

enum class UsbStreamResult : int32_t {
    Ok = 0,
    ClaimFailed = 1,
    AltSettingFailed = 2,
    RateUnsupported = 3,
    SubmitFailed = 4,
    InvalidArgs = 5
};

class UsbAudioSink {
public:
    static UsbAudioSink& instance();

    // fd: usbfs fd from UsbDeviceConnection.getFileDescriptor().
    // endpointAddress: isochronous OUT endpoint (bit 7 clear).
    // interfaceNumber/altSetting: the claimed AudioStreaming interface.
    UsbStreamResult Open(int fd, int endpointAddress, int interfaceNumber, int altSetting,
                         int sampleRate, int channels, int bytesPerSample);
    void Close();
    bool IsActive() const;
    int GetLastError() const { return lastError_.load(std::memory_order_acquire); }
    uint64_t GetUnderrunCount() const { return underrunCount_.load(std::memory_order_relaxed); }
    uint64_t GetOverrunCount() const { return overrunCount_.load(std::memory_order_relaxed); }
    double GetBufferedMs();

    // Queries supported sample rates for the AudioStreaming interface using USBDEVFS_CONTROL.
    static std::vector<int> QuerySupportedRates(int fd, int interfaceNumber);

    // Parses supported sample rates from raw configuration descriptors (UAC1 Format Type I).
    static std::vector<int> ParseSupportedRatesFromDescriptors(const uint8_t* desc, size_t len, int targetInterface = -1);

    // Audio-thread call: converts float [-1,1] to interleaved S16_LE and appends
    // to the ring. Non-blocking; excess data is dropped (never blocks playback).
    void WriteInterleaved(const float* buffer, int frames, int channels);

    int sampleRate() const { return sampleRate_; }
    int channels() const { return channels_; }

private:
    UsbAudioSink() = default;
    ~UsbAudioSink();
    UsbAudioSink(const UsbAudioSink&) = delete;
    UsbAudioSink& operator=(const UsbAudioSink&) = delete;

    void workerLoop();
    bool submitAll();
    void releaseResources();

    std::atomic<bool> active_{false};
    std::atomic<bool> running_{false};
    std::atomic<int> lastError_{0};
    std::atomic<uint64_t> underrunCount_{0};
    std::atomic<uint64_t> overrunCount_{0};

    int fd_ = -1;
    int endpoint_ = 0;
    int interfaceNumber_ = -1;
    int altSetting_ = 0;
    int sampleRate_ = 48000;
    int channels_ = 2;
    int bytesPerSample_ = 2;  // 2=S16, 3=S24_3LE, 4=S32
    bool claimed_ = false;

    int packetsPerUrb_ = 8;
    int bytesPerPacket_ = 0;
    int bytesPerUrb_ = 0;

    std::thread worker_;

    // Preallocated URB storage + buffers (1 URB header + N packet descriptors).
    std::vector<uint8_t> urbStorage_;
    std::vector<uint8_t*> urbBuffers_;
    std::vector<void*> urbs_;
    size_t urbStride_ = 0;
    int numUrbs_ = 0;

    // Lock-free single-producer single-consumer (SPSC) byte ring buffer.
    // Audio thread produces; USB worker thread consumes. Wait-free for audio thread.
    std::vector<uint8_t> ring_;
    size_t ringMask_ = 0;
    alignas(64) std::atomic<size_t> ringWrite_{0};
    alignas(64) std::atomic<size_t> ringRead_{0};
};

} // namespace pulsr

#endif // PULSR_USB_AUDIO_SINK_H_
