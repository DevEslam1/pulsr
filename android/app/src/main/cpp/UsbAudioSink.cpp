// android/app/src/main/cpp/UsbAudioSink.cpp
#include "UsbAudioSink.h"

#include <linux/usbdevice_fs.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstring>
#include <new>

namespace pulsr {

namespace {
constexpr int kNumUrbs = 4;
constexpr int kPacketsPerUrb = 8; // 8 ms of 1 ms isochronous packets

// Clamp float to [-1, 1]
inline float clampF(float v) {
    if (v > 1.0f) return 1.0f;
    if (v < -1.0f) return -1.0f;
    return v;
}

// Pack one float sample into dst[] in the given bytesPerSample format (LE).
// Returns bytesPerSample.
inline int packSample(float v, uint8_t* dst, int bytesPerSample) {
    v = clampF(v);
    if (bytesPerSample == 2) {
        // S16_LE
        int16_t s = static_cast<int16_t>(std::lround(v * 32767.0f));
        dst[0] = static_cast<uint8_t>(s & 0xFF);
        dst[1] = static_cast<uint8_t>((s >> 8) & 0xFF);
    } else if (bytesPerSample == 3) {
        // S24_3LE (packed 24-bit, no padding)
        int32_t s = static_cast<int32_t>(std::lround(v * 8388607.0));
        dst[0] = static_cast<uint8_t>(s & 0xFF);
        dst[1] = static_cast<uint8_t>((s >> 8) & 0xFF);
        dst[2] = static_cast<uint8_t>((s >> 16) & 0xFF);
    } else {
        // S32_LE
        int32_t s = static_cast<int32_t>(std::lround(v * 2147483647.0));
        dst[0] = static_cast<uint8_t>(s & 0xFF);
        dst[1] = static_cast<uint8_t>((s >> 8) & 0xFF);
        dst[2] = static_cast<uint8_t>((s >> 16) & 0xFF);
        dst[3] = static_cast<uint8_t>((s >> 24) & 0xFF);
    }
    return bytesPerSample;
}
} // namespace

UsbAudioSink& UsbAudioSink::instance() {
    static UsbAudioSink sink;
    return sink;
}

UsbAudioSink::~UsbAudioSink() {
    Close();
}

bool UsbAudioSink::IsActive() const {
    return active_.load(std::memory_order_acquire);
}

bool UsbAudioSink::submitAll() {
    for (void* raw : urbs_) {
        auto* urb = reinterpret_cast<struct usbdevfs_urb*>(raw);
        if (ioctl(fd_, USBDEVFS_SUBMITURB, urb) < 0) {
            return false;
        }
    }
    return true;
}

bool UsbAudioSink::Open(int fd, int endpointAddress, int interfaceNumber,
                        int altSetting, int sampleRate, int channels,
                        int bytesPerSample) {
    if (fd < 0 || sampleRate <= 0 || channels <= 0 || bytesPerSample <= 0) {
        return false;
    }
    // Never tear down a live sink implicitly; caller must Stop first.
    if (active_.load()) return false;

    fd_ = fd;
    endpoint_ = endpointAddress;
    interfaceNumber_ = interfaceNumber;
    altSetting_ = altSetting;
    sampleRate_ = sampleRate;
    channels_ = channels;
    bytesPerSample_ = std::clamp(bytesPerSample, 2, 4);

    // Claim the AudioStreaming interface (force: detaches the kernel audio
    // driver so the HAL can no longer own the endpoint) and select the alt
    // setting that exposes the isochronous OUT endpoint.
    int iface = interfaceNumber_;
    if (ioctl(fd_, USBDEVFS_CLAIMINTERFACE, &iface) < 0) {
        releaseResources();
        return false;
    }
    claimed_ = true;

    struct usbdevfs_setinterface si {};
    si.interface = static_cast<unsigned int>(interfaceNumber_);
    si.altsetting = static_cast<unsigned int>(altSetting_);
    // Best-effort: some HALs already selected the alt setting.
    ioctl(fd_, USBDEVFS_SETINTERFACE, &si);

    const int framesPerPacket = std::max(1, sampleRate_ / 1000);
    bytesPerPacket_ = framesPerPacket * channels_ * bytesPerSample_;
    packetsPerUrb_ = kPacketsPerUrb;
    bytesPerUrb_ = bytesPerPacket_ * packetsPerUrb_;

    // ~3 URBs of slack in bytes; enough to absorb scheduling jitter.
    const size_t ringBytes = static_cast<size_t>(bytesPerUrb_) * 3;
    ring_.assign(ringBytes, 0);
    ringRead_ = ringWrite_ = ringCount_ = 0;

    urbStride_ = sizeof(struct usbdevfs_urb) +
                 static_cast<size_t>(packetsPerUrb_) *
                     sizeof(struct usbdevfs_iso_packet_desc);
    // Keep each URB header 8-byte aligned within the storage block.
    urbStride_ = (urbStride_ + 7u) & ~static_cast<size_t>(7u);

    numUrbs_ = kNumUrbs;
    urbStorage_.assign(urbStride_ * numUrbs_, 0);
    urbBuffers_.assign(numUrbs_, nullptr);
    urbs_.assign(numUrbs_, nullptr);

    for (int i = 0; i < numUrbs_; ++i) {
        auto* urb = reinterpret_cast<struct usbdevfs_urb*>(
            urbStorage_.data() + static_cast<size_t>(i) * urbStride_);
        urbBuffers_[i] = new (std::nothrow) uint8_t[bytesPerUrb_]();
        if (!urbBuffers_[i]) {
            releaseResources();
            return false;
        }
        std::memset(urb, 0, sizeof(struct usbdevfs_urb));
        urb->type = USBDEVFS_URB_TYPE_ISO;
        urb->endpoint = static_cast<unsigned char>(endpoint_);
        urb->flags = USBDEVFS_URB_ISO_ASAP;
        urb->buffer = urbBuffers_[i];
        urb->buffer_length = static_cast<int>(bytesPerUrb_);
        urb->number_of_packets = packetsPerUrb_;
        urb->usercontext = urb;
        for (int p = 0; p < packetsPerUrb_; ++p) {
            urb->iso_frame_desc[p].length = static_cast<unsigned int>(bytesPerPacket_);
            urb->iso_frame_desc[p].actual_length = 0;
            urb->iso_frame_desc[p].status = 0;
        }
        urbs_[i] = urb;
    }

    if (!submitAll()) {
        releaseResources();
        return false;
    }

    running_.store(true, std::memory_order_release);
    active_.store(true, std::memory_order_release);
    worker_ = std::thread([this] { workerLoop(); });
    return true;
}

void UsbAudioSink::Close() {
    if (!active_.load() && !running_.load()) {
        releaseResources();
        return;
    }
    running_.store(false, std::memory_order_release);

    if (worker_.joinable()) {
        worker_.join();
    }

    for (void* raw : urbs_) {
        if (raw == nullptr || fd_ < 0) continue;
        ioctl(fd_, USBDEVFS_DISCARDURB, raw);
    }

    if (fd_ >= 0 && claimed_) {
        int iface = interfaceNumber_;
        ioctl(fd_, USBDEVFS_RELEASEINTERFACE, &iface);
    }

    active_.store(false, std::memory_order_release);
    releaseResources();
}

void UsbAudioSink::releaseResources() {
    for (uint8_t* b : urbBuffers_) {
        delete[] b;
    }
    urbBuffers_.clear();
    urbs_.clear();
    urbStorage_.clear();
    urbBuffers_.shrink_to_fit();
    urbs_.shrink_to_fit();
    urbStorage_.shrink_to_fit();
    claimed_ = false;
    fd_ = -1;
    active_.store(false, std::memory_order_release);
    running_.store(false, std::memory_order_release);
}

void UsbAudioSink::workerLoop() {
    while (running_.load(std::memory_order_acquire)) {
        struct usbdevfs_urb* urb = nullptr;
        int r = ioctl(fd_, USBDEVFS_REAPURBNDELAY, &urb);
        if (r < 0) {
            if (errno == EAGAIN || errno == EINPROGRESS) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
            // ESHUTDOWN / ENOENT / device gone: stop cleanly.
            break;
        }
        if (urb == nullptr) continue;

        uint8_t* buf = reinterpret_cast<uint8_t*>(urb->buffer);
        const size_t bytesPerPkt = static_cast<size_t>(bytesPerPacket_);
        {
            std::lock_guard<std::mutex> lock(ringMutex_);
            for (int p = 0; p < packetsPerUrb_; ++p) {
                uint8_t* dst = buf + static_cast<size_t>(p) * bytesPerPkt;
                if (ringCount_ >= bytesPerPkt) {
                    for (size_t i = 0; i < bytesPerPkt; ++i) {
                        dst[i] = ring_[ringRead_];
                        ringRead_ = (ringRead_ + 1) % ring_.size();
                    }
                    ringCount_ -= bytesPerPkt;
                } else {
                    std::memset(dst, 0, bytesPerPkt);
                }
                urb->iso_frame_desc[p].length =
                    static_cast<unsigned int>(bytesPerPkt);
                urb->iso_frame_desc[p].actual_length = 0;
                urb->iso_frame_desc[p].status = 0;
            }
        }

        if (ioctl(fd_, USBDEVFS_SUBMITURB, urb) < 0) {
            break;
        }
    }
}

void UsbAudioSink::WriteInterleaved(const float* buffer, int frames,
                                    int channels) {
    if (!active_.load(std::memory_order_acquire) || buffer == nullptr ||
        frames <= 0 || channels <= 0) {
        return;
    }
    const int bps = bytesPerSample_;
    const size_t totalSamples = static_cast<size_t>(frames) * channels;
    std::lock_guard<std::mutex> lock(ringMutex_);
    const size_t cap = ring_.size();
    for (size_t s = 0; s < totalSamples && ringCount_ + bps <= cap; ++s) {
        uint8_t packed[4];
        packSample(buffer[s], packed, bps);
        for (int b = 0; b < bps; ++b) {
            ring_[ringWrite_] = packed[b];
            ringWrite_ = (ringWrite_ + 1) % cap;
        }
        ringCount_ += bps;
    }
}

} // namespace pulsr
