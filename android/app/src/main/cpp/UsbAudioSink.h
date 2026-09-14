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

class UsbAudioSink {
public:
    static UsbAudioSink& instance();

    // fd: usbfs fd from UsbDeviceConnection.getFileDescriptor().
    // endpointAddress: isochronous OUT endpoint (bit 7 clear).
    // interfaceNumber/altSetting: the claimed AudioStreaming interface.
    bool Open(int fd, int endpointAddress, int interfaceNumber, int altSetting,
              int sampleRate, int channels, int bytesPerSample);
    void Close();
    bool IsActive() const;

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

    int fd_ = -1;
    int endpoint_ = 0;
    int interfaceNumber_ = -1;
    int altSetting_ = 0;
    int sampleRate_ = 48000;
    int channels_ = 2;
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

    // Bounded S16 ring buffer, guarded by ringMutex_.
    std::mutex ringMutex_;
    std::vector<int16_t> ring_;
    size_t ringRead_ = 0;
    size_t ringWrite_ = 0;
    size_t ringCount_ = 0;
};

} // namespace pulsr

#endif // PULSR_USB_AUDIO_SINK_H_
