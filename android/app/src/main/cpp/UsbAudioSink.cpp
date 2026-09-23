// android/app/src/main/cpp/UsbAudioSink.cpp
#include "UsbAudioSink.h"

#if defined(__linux__) || defined(__ANDROID__)
#include <linux/usbdevice_fs.h>
#include <sys/ioctl.h>
#include <unistd.h>
#else
// Non-Linux mock definitions for host compilation and tests
struct usbdevfs_urb {
    unsigned char type;
    unsigned char endpoint;
    int status;
    unsigned int flags;
    void* buffer;
    int buffer_length;
    int actual_length;
    int start_frame;
    int number_of_packets;
    int error_count;
    unsigned int signr;
    void* usercontext;
    struct usbdevfs_iso_packet_desc {
        unsigned int length;
        unsigned int actual_length;
        unsigned int status;
    } iso_frame_desc[1];
};
struct usbdevfs_setinterface {
    unsigned int interface;
    unsigned int altsetting;
};
struct usbdevfs_ctrltransfer {
    uint8_t bRequestType;
    uint8_t bRequest;
    uint16_t wValue;
    uint16_t wIndex;
    uint16_t wLength;
    uint32_t timeout;
    void* data;
};
#define USBDEVFS_URB_TYPE_ISO 0
#define USBDEVFS_URB_ISO_ASAP 2
#define USBDEVFS_CLAIMINTERFACE 0
#define USBDEVFS_RELEASEINTERFACE 0
#define USBDEVFS_SETINTERFACE 0
#define USBDEVFS_SUBMITURB 0
#define USBDEVFS_DISCARDURB 0
#define USBDEVFS_REAPURBNDELAY 0
#define USBDEVFS_CONTROL 0
inline int ioctl(int, unsigned long, ...) { return -1; }
#endif

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
#if defined(__linux__) || defined(__ANDROID__)
    for (void* raw : urbs_) {
        auto* urb = reinterpret_cast<struct usbdevfs_urb*>(raw);
        if (ioctl(fd_, USBDEVFS_SUBMITURB, urb) < 0) {
            return false;
        }
    }
#endif
    return true;
}

UsbStreamResult UsbAudioSink::Open(int fd, int endpointAddress, int interfaceNumber,
                                   int altSetting, int sampleRate, int channels,
                                   int bytesPerSample) {
    if (fd < 0 || channels <= 0 || bytesPerSample <= 0) {
        lastError_.store(EINVAL, std::memory_order_relaxed);
        return UsbStreamResult::InvalidArgs;
    }
    if (sampleRate <= 0) {
        lastError_.store(EINVAL, std::memory_order_relaxed);
        return UsbStreamResult::RateUnsupported;
    }
    static const int kValidRates[] = {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
    bool validRate = false;
    for (int r : kValidRates) {
        if (sampleRate == r) {
            validRate = true;
            break;
        }
    }
    if (!validRate) {
        lastError_.store(EINVAL, std::memory_order_relaxed);
        return UsbStreamResult::RateUnsupported;
    }

    // Never tear down a live sink implicitly; caller must Stop first.
    if (active_.load()) {
        return UsbStreamResult::ClaimFailed;
    }

    lastError_.store(0, std::memory_order_relaxed);
    underrunCount_.store(0, std::memory_order_relaxed);
    overrunCount_.store(0, std::memory_order_relaxed);

    fd_ = fd;
    endpoint_ = endpointAddress;
    interfaceNumber_ = interfaceNumber;
    altSetting_ = altSetting;
    sampleRate_ = sampleRate;
    channels_ = channels;
    bytesPerSample_ = std::clamp(bytesPerSample, 2, 4);

#if defined(__linux__) || defined(__ANDROID__)
    // Claim the AudioStreaming interface (force: detaches the kernel audio
    // driver so the HAL can no longer own the endpoint) and select the alt
    // setting that exposes the isochronous OUT endpoint.
    int iface = interfaceNumber_;
    if (ioctl(fd_, USBDEVFS_CLAIMINTERFACE, &iface) < 0) {
        lastError_.store(errno, std::memory_order_relaxed);
        releaseResources();
        return UsbStreamResult::ClaimFailed;
    }
    claimed_ = true;

    struct usbdevfs_setinterface si {};
    si.interface = static_cast<unsigned int>(interfaceNumber_);
    si.altsetting = static_cast<unsigned int>(altSetting_);
    // Best-effort: some HALs already selected the alt setting.
    if (ioctl(fd_, USBDEVFS_SETINTERFACE, &si) < 0) {
        if (errno != 0 && errno != EBUSY && altSetting_ > 0) {
            lastError_.store(errno, std::memory_order_relaxed);
            releaseResources();
            return UsbStreamResult::AltSettingFailed;
        }
    }

    const int framesPerPacket = std::max(1, sampleRate_ / 1000);
    bytesPerPacket_ = framesPerPacket * channels_ * bytesPerSample_;
    packetsPerUrb_ = kPacketsPerUrb;
    bytesPerUrb_ = bytesPerPacket_ * packetsPerUrb_;

    // Power-of-two ring buffer capacity for mask-based indexing (~4 URBs slack).
    const size_t targetRingBytes = static_cast<size_t>(bytesPerUrb_) * 4;
    size_t cap = 2048;
    while (cap < targetRingBytes) cap <<= 1;
    ring_.assign(cap, 0);
    ringMask_ = cap - 1;
    ringRead_.store(0, std::memory_order_relaxed);
    ringWrite_.store(0, std::memory_order_relaxed);

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
            lastError_.store(ENOMEM, std::memory_order_relaxed);
            releaseResources();
            return UsbStreamResult::SubmitFailed;
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
        lastError_.store(errno, std::memory_order_relaxed);
        releaseResources();
        return UsbStreamResult::SubmitFailed;
    }

    running_.store(true, std::memory_order_release);
    active_.store(true, std::memory_order_release);
    worker_ = std::thread([this] { workerLoop(); });
    return UsbStreamResult::Ok;
#else
    running_.store(true, std::memory_order_release);
    active_.store(true, std::memory_order_release);
    return UsbStreamResult::Ok;
#endif
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
    if (claimed_ && fd_ >= 0) {
        int iface = interfaceNumber_;
        ioctl(fd_, USBDEVFS_RELEASEINTERFACE, &iface);
    }
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
            lastError_.store(errno, std::memory_order_release);
            break;
        }
        if (urb == nullptr) continue;

        uint8_t* buf = reinterpret_cast<uint8_t*>(urb->buffer);
        const size_t bytesPerPkt = static_cast<size_t>(bytesPerPacket_);
        const size_t mask = ringMask_;
        size_t readPos = ringRead_.load(std::memory_order_relaxed);
        for (int p = 0; p < packetsPerUrb_; ++p) {
            uint8_t* dst = buf + static_cast<size_t>(p) * bytesPerPkt;
            const size_t w = ringWrite_.load(std::memory_order_acquire);
            const size_t avail = (w >= readPos) ? (w - readPos) : 0;
            if (avail >= bytesPerPkt) {
                for (size_t i = 0; i < bytesPerPkt; ++i) {
                    dst[i] = ring_[(readPos + i) & mask];
                }
                readPos += bytesPerPkt;
            } else {
                std::memset(dst, 0, bytesPerPkt);
                underrunCount_.fetch_add(1, std::memory_order_relaxed);
            }
            urb->iso_frame_desc[p].length =
                static_cast<unsigned int>(bytesPerPkt);
            urb->iso_frame_desc[p].actual_length = 0;
            urb->iso_frame_desc[p].status = 0;
        }
        ringRead_.store(readPos, std::memory_order_release);

        if (ioctl(fd_, USBDEVFS_SUBMITURB, urb) < 0) {
            lastError_.store(errno, std::memory_order_release);
            break;
        }
    }
    // Critical: set running_ and active_ to false on exit so sink never stays
    // in a zombie "playing but silent" state when the worker thread terminates.
    running_.store(false, std::memory_order_release);
    active_.store(false, std::memory_order_release);
}

void UsbAudioSink::WriteInterleaved(const float* buffer, int frames,
                                    int channels) {
    if (!active_.load(std::memory_order_acquire) || buffer == nullptr ||
        frames <= 0 || channels <= 0) {
        return;
    }
    const int bps = bytesPerSample_;
    const size_t totalSamples = static_cast<size_t>(frames) * channels;
    const size_t cap = ring_.size();
    const size_t mask = ringMask_;
    if (cap == 0) return;

    size_t w = ringWrite_.load(std::memory_order_relaxed);
    size_t r = ringRead_.load(std::memory_order_acquire);
    size_t availSpace = (cap > (w - r)) ? (cap - (w - r) - 1) : 0;

    size_t s = 0;
    for (; s < totalSamples && availSpace >= static_cast<size_t>(bps); ++s) {
        uint8_t packed[4];
        packSample(buffer[s], packed, bps);
        for (int b = 0; b < bps; ++b) {
            ring_[(w + b) & mask] = packed[b];
        }
        w += bps;
        availSpace -= bps;
    }
    ringWrite_.store(w, std::memory_order_release);

    if (s < totalSamples) {
        // Track overrun (dropped frames)
        const size_t droppedSamples = totalSamples - s;
        overrunCount_.fetch_add(droppedSamples / channels, std::memory_order_relaxed);
    }
}

double UsbAudioSink::GetBufferedMs() {
    if (!active_.load(std::memory_order_acquire)) return 0.0;
    const size_t w = ringWrite_.load(std::memory_order_acquire);
    const size_t r = ringRead_.load(std::memory_order_relaxed);
    const size_t count = (w >= r) ? (w - r) : 0;
    const int frameBytes = channels_ * bytesPerSample_;
    double ringMs = 0.0;
    if (frameBytes > 0 && sampleRate_ > 0) {
        ringMs = (static_cast<double>(count) / static_cast<double>(frameBytes * sampleRate_)) * 1000.0;
    }
    const double urbMs = static_cast<double>(numUrbs_ * packetsPerUrb_);
    return ringMs + urbMs;
}

std::vector<int> UsbAudioSink::ParseSupportedRatesFromDescriptors(
    const uint8_t* desc, size_t len, int targetInterface) {
    if (!desc || len < 8) return {};

    std::vector<int> rates;
    constexpr int kStandardRates[] = {
        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
    };

    size_t i = 0;
    int currentInterface = -1;
    int currentClass = 0;
    int currentSubclass = 0;

    while (i + 2 <= len) {
        uint8_t bLength = desc[i];
        if (bLength < 2 || i + bLength > len) {
            i++;
            continue;
        }
        uint8_t bType = desc[i + 1];

        if (bType == 0x04) { // DESC_INTERFACE
            if (bLength >= 9) {
                currentInterface = desc[i + 2];
                currentClass = desc[i + 5];
                currentSubclass = desc[i + 6];
            }
        } else if (bType == 0x24) { // DESC_CS_INTERFACE
            if (currentClass == 0x01 && currentSubclass == 0x02 &&
                (targetInterface < 0 || currentInterface == targetInterface)) {
                // AudioStreaming CS_INTERFACE
                uint8_t bSubtype = desc[i + 2];
                if (bSubtype == 0x02 && bLength >= 8) { // FORMAT_TYPE
                    uint8_t bFormatType = desc[i + 3];
                    if (bFormatType == 0x01) { // FORMAT_TYPE_I (UAC1)
                        uint8_t bSamFreqType = desc[i + 7];
                        if (bSamFreqType == 0 && bLength >= 14) {
                            // Continuous sample rate range
                            int lower = desc[i + 8] | (desc[i + 9] << 8) | (desc[i + 10] << 16);
                            int upper = desc[i + 11] | (desc[i + 12] << 8) | (desc[i + 13] << 16);
                            for (int r : kStandardRates) {
                                if (r >= lower && r <= upper) {
                                    rates.push_back(r);
                                }
                            }
                        } else if (bSamFreqType > 0) {
                            // Discrete sample rates
                            for (uint8_t k = 0; k < bSamFreqType; ++k) {
                                size_t offset = i + 8 + 3 * k;
                                if (offset + 3 <= i + bLength) {
                                    int r = desc[offset] | (desc[offset + 1] << 8) | (desc[offset + 2] << 16);
                                    if (r > 0) {
                                        rates.push_back(r);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        i += bLength;
    }

    std::sort(rates.begin(), rates.end());
    rates.erase(std::unique(rates.begin(), rates.end()), rates.end());
    return rates;
}

std::vector<int> UsbAudioSink::QuerySupportedRates(int fd, int interfaceNumber) {
#if defined(__linux__) || defined(__ANDROID__)
    if (fd < 0) return {};

    uint8_t header[4] = {0};
    struct usbdevfs_ctrltransfer ctrl {};
    ctrl.bRequestType = 0x80; // USB_DIR_IN | USB_TYPE_STANDARD | USB_RECIP_DEVICE
    ctrl.bRequest = 0x06;     // USB_REQ_GET_DESCRIPTOR
    ctrl.wValue = 0x0200;     // (USB_DT_CONFIG << 8) | 0
    ctrl.wIndex = 0;
    ctrl.wLength = sizeof(header);
    ctrl.timeout = 1000;
    ctrl.data = header;

    if (ioctl(fd, USBDEVFS_CONTROL, &ctrl) < 0) {
        return {};
    }

    uint16_t totalLength = static_cast<uint16_t>(header[2] | (header[3] << 8));
    if (totalLength < 9 || totalLength > 16384) {
        totalLength = 4096;
    }

    std::vector<uint8_t> configDesc(totalLength);
    ctrl.wLength = totalLength;
    ctrl.data = configDesc.data();

    int res = ioctl(fd, USBDEVFS_CONTROL, &ctrl);
    if (res < 0) {
        return {};
    }
    configDesc.resize(static_cast<size_t>(res));

    std::vector<int> rates = ParseSupportedRatesFromDescriptors(
        configDesc.data(), configDesc.size(), interfaceNumber);

    // Scan for UAC2 Clock Source entities and query sample rates
    int acInterface = 0;
    std::vector<uint8_t> clockIds;
    size_t dIdx = 0;
    while (dIdx + 2 <= configDesc.size()) {
        uint8_t bLength = configDesc[dIdx];
        if (bLength < 2 || dIdx + bLength > configDesc.size()) break;
        uint8_t bType = configDesc[dIdx + 1];
        if (bType == 0x04 && bLength >= 9) { // DESC_INTERFACE
            if (configDesc[dIdx + 5] == 0x01 && configDesc[dIdx + 6] == 0x01) {
                acInterface = configDesc[dIdx + 2]; // AudioControl interface
            }
        } else if (bType == 0x24 && bLength >= 8) { // CS_INTERFACE
            if (configDesc[dIdx + 2] == 0x0B) { // CLOCK_SOURCE
                clockIds.push_back(configDesc[dIdx + 3]); // bClockID
            }
        }
        dIdx += bLength;
    }

    for (uint8_t clockId : clockIds) {
        uint8_t rangeBuf[256] = {0};
        struct usbdevfs_ctrltransfer rangeCtrl {};
        rangeCtrl.bRequestType = 0xA1; // IN | CLASS | INTERFACE
        rangeCtrl.bRequest = 0x02;     // UAC2 RANGE
        rangeCtrl.wValue = 0x0100;     // CS_SAM_FREQ_CONTROL (0x01) << 8
        rangeCtrl.wIndex = static_cast<uint16_t>((clockId << 8) | acInterface);
        rangeCtrl.wLength = sizeof(rangeBuf);
        rangeCtrl.timeout = 1000;
        rangeCtrl.data = rangeBuf;

        if (ioctl(fd, USBDEVFS_CONTROL, &rangeCtrl) >= 2) {
            uint16_t numRanges = rangeBuf[0] | (rangeBuf[1] << 8);
            size_t offset = 2;
            for (uint16_t r = 0; r < numRanges && offset + 12 <= sizeof(rangeBuf); ++r) {
                uint32_t dMin = rangeBuf[offset] | (rangeBuf[offset + 1] << 8) |
                                (rangeBuf[offset + 2] << 16) | (rangeBuf[offset + 3] << 24);
                uint32_t dMax = rangeBuf[offset + 4] | (rangeBuf[offset + 5] << 8) |
                                (rangeBuf[offset + 6] << 16) | (rangeBuf[offset + 7] << 24);
                if (dMin == dMax && dMin > 0) {
                    rates.push_back(static_cast<int>(dMin));
                } else if (dMin < dMax) {
                    constexpr int kStandardRates[] = {
                        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
                    };
                    for (int sr : kStandardRates) {
                        if (static_cast<uint32_t>(sr) >= dMin && static_cast<uint32_t>(sr) <= dMax) {
                            rates.push_back(sr);
                        }
                    }
                }
                offset += 12;
            }
        }
    }

    if (!rates.empty()) {
        std::sort(rates.begin(), rates.end());
        rates.erase(std::unique(rates.begin(), rates.end()), rates.end());
        return rates;
    }

    // Fallback: If no UAC1 rates detected (e.g. UAC2 DAC), probe standard high-res rates
    return {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
#else
    (void)fd;
    (void)interfaceNumber;
    return {44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000};
#endif
}

} // namespace pulsr
