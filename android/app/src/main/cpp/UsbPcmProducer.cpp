// android/app/src/main/cpp/UsbPcmProducer.cpp
#include "UsbPcmProducer.h"

#include <algorithm>
#include <chrono>
#include <cstring>

namespace pulsr {
namespace {

constexpr uint16_t kFormatPcm = 0x0001;
constexpr uint16_t kFormatExtensible = 0xFFFE;

uint16_t readLe16(const uint8_t* p) {
    return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

uint32_t readLe32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

bool readExact(std::FILE* f, void* dst, size_t bytes) {
    return bytes == 0 || std::fread(dst, 1, bytes, f) == bytes;
}

// 64-bit file positioning: a 24/192 multichannel WAV can exceed 2 GiB, where a
// 32-bit long fseek would wrap.
int64_t fileTell(std::FILE* f) {
#if defined(_WIN32)
    return _ftelli64(f);
#else
    return static_cast<int64_t>(ftello(f));
#endif
}

bool fileSeek(std::FILE* f, uint64_t offset) {
    if (offset > static_cast<uint64_t>(INT64_MAX)) return false;
#if defined(_WIN32)
    return _fseeki64(f, static_cast<int64_t>(offset), SEEK_SET) == 0;
#else
    return fseeko(f, static_cast<off_t>(offset), SEEK_SET) == 0;
#endif
}

bool skipBytes(std::FILE* f, uint64_t bytes) {
    const int64_t now = fileTell(f);
    if (now < 0) return false;
    return fileSeek(f, static_cast<uint64_t>(now) + bytes);
}

}  // namespace

UsbPcmProducer::~UsbPcmProducer() { close(); }

bool UsbPcmProducer::open(const std::string& path, const UsbPcmFormat& target,
                          UsbPullRenderer& out, int bufferMs,
                          bool configureRenderer) {
    close();
    lastError_.clear();
    if (target.sampleRate <= 0 || target.channels <= 0 ||
        target.containerBytes < 1 || target.containerBytes > 4 ||
        target.validBits < 1 || target.validBits > target.containerBytes * 8) {
        lastError_ = "invalid_target_format";
        return false;
    }
    file_ = std::fopen(path.c_str(), "rb");
    if (file_ == nullptr) {
        lastError_ = "file_open_failed";
        return false;
    }
    if (!parseWav()) {
        close();
        return false;
    }
    if (format_ != target) {
        // No conversion is allowed on the bit-perfect pull path.
        lastError_ = "format_mismatch";
        close();
        return false;
    }
    if (configureRenderer &&
        !out.Configure(target.sampleRate, target.channels,
                       target.containerBytes, bufferMs)) {
        lastError_ = "renderer_configure_failed";
        close();
        return false;
    }
    renderer_ = &out;
    frameBytes_ = target.channels * target.containerBytes;
    totalFrames_ = dataBytes_ / static_cast<uint64_t>(frameBytes_);
    buffer_.assign(static_cast<size_t>(kChunkFrames) * frameBytes_, 0);
    framesRead_.store(0, std::memory_order_relaxed);
    framesWritten_.store(0, std::memory_order_relaxed);
    finished_.store(totalFrames_ == 0, std::memory_order_release);
    return true;
}

bool UsbPcmProducer::parseWav() {
    if (file_ == nullptr) return false;
    uint8_t header[12];
    if (!readExact(file_, header, sizeof(header)) ||
        std::memcmp(header, "RIFF", 4) != 0 ||
        std::memcmp(header + 8, "WAVE", 4) != 0) {
        lastError_ = "not_a_wav";
        return false;
    }

    bool haveFormat = false;
    bool haveData = false;
    uint16_t audioFormat = 0;
    uint16_t channels = 0;
    uint32_t sampleRate = 0;
    uint16_t blockAlign = 0;
    uint16_t bitsPerSample = 0;
    uint16_t validBits = 0;

    for (;;) {
        uint8_t chunk[8];
        if (std::fread(chunk, 1, sizeof(chunk), file_) != sizeof(chunk)) break;
        const uint32_t size = readLe32(chunk + 4);
        if (std::memcmp(chunk, "fmt ", 4) == 0) {
            if (size < 16 || size > 4096) {
                lastError_ = "fmt_chunk_invalid";
                return false;
            }
            std::vector<uint8_t> fmt(size);
            if (!readExact(file_, fmt.data(), size)) {
                lastError_ = "fmt_chunk_truncated";
                return false;
            }
            audioFormat = readLe16(fmt.data());
            channels = readLe16(fmt.data() + 2);
            sampleRate = readLe32(fmt.data() + 4);
            blockAlign = readLe16(fmt.data() + 12);
            bitsPerSample = readLe16(fmt.data() + 14);
            validBits = bitsPerSample;
            if (audioFormat == kFormatExtensible) {
                if (size < 40) {
                    lastError_ = "extensible_fmt_truncated";
                    return false;
                }
                validBits = readLe16(fmt.data() + 18);
                // SubFormat GUID starts with the 16-bit format tag.
                if (readLe16(fmt.data() + 24) != kFormatPcm) {
                    lastError_ = "extensible_not_pcm";
                    return false;
                }
            } else if (audioFormat != kFormatPcm) {
                lastError_ = "not_integer_pcm";
                return false;
            }
            haveFormat = true;
        } else if (std::memcmp(chunk, "data", 4) == 0) {
            const int64_t offset = fileTell(file_);
            if (offset < 0) {
                lastError_ = "data_offset_failed";
                return false;
            }
            dataOffset_ = static_cast<uint64_t>(offset);
            dataBytes_ = size;
            haveData = true;
            // A WAV may carry more chunks after data; stop once both are known
            // so the reader thread starts at a stable offset.
            break;
        } else {
            // Skip unknown chunks, including the pad byte for odd sizes.
            uint64_t skip = size;
            if ((size & 1u) != 0) skip++;
            if (!skipBytes(file_, skip)) {
                lastError_ = "chunk_skip_failed";
                return false;
            }
        }
    }

    if (!haveFormat || !haveData) {
        lastError_ = haveFormat ? "data_chunk_missing" : "fmt_chunk_missing";
        return false;
    }
    if (channels < 1 || channels > 8 || sampleRate < 8000 || sampleRate > 1536000) {
        lastError_ = "wav_geometry_unsupported";
        return false;
    }
    if (bitsPerSample == 0 || (bitsPerSample % 8) != 0 || bitsPerSample > 32) {
        lastError_ = "wav_bits_unsupported";
        return false;
    }
    const int containerBytes = blockAlign / channels;
    if (containerBytes < 1 || containerBytes > 4 ||
        blockAlign != channels * containerBytes) {
        lastError_ = "wav_block_align_unsupported";
        return false;
    }
    if (validBits < 1 || validBits > bitsPerSample || validBits > 32) {
        lastError_ = "wav_valid_bits_unsupported";
        return false;
    }
    format_.sampleRate = static_cast<int>(sampleRate);
    format_.channels = static_cast<int>(channels);
    format_.containerBytes = containerBytes;
    format_.validBits = static_cast<int>(validBits);
    if (dataBytes_ % static_cast<uint64_t>(blockAlign) != 0) {
        lastError_ = "wav_data_not_whole_frames";
        return false;
    }
    // Position at the first audio frame; the thread reads from here.
    if (!fileSeek(file_, dataOffset_)) {
        lastError_ = "wav_seek_failed";
        return false;
    }
    return true;
}

void UsbPcmProducer::start() {
    if (file_ == nullptr || running_.load(std::memory_order_acquire)) return;
    running_.store(true, std::memory_order_release);
    thread_ = std::thread(&UsbPcmProducer::threadMain, this);
}

void UsbPcmProducer::stop() {
    running_.store(false, std::memory_order_release);
    if (thread_.joinable()) thread_.join();
}

void UsbPcmProducer::close() {
    stop();
    std::lock_guard<std::mutex> lock(fileMutex_);
    if (file_ != nullptr) {
        std::fclose(file_);
        file_ = nullptr;
    }
    renderer_ = nullptr;
    buffer_.clear();
    buffer_.shrink_to_fit();
    // Keep lastError_: open() calls close() on its failure paths and the caller
    // must still be able to read the reason.
    finished_.store(false, std::memory_order_release);
    seekRequest_.store(UINT64_MAX, std::memory_order_release);
    framesRead_.store(0, std::memory_order_relaxed);
    framesWritten_.store(0, std::memory_order_relaxed);
}

bool UsbPcmProducer::seekToFrame(uint64_t frame) {
    if (file_ == nullptr || renderer_ == nullptr) return false;
    if (frame > totalFrames_) return false;
    seekRequest_.store(frame, std::memory_order_release);
    return true;
}

void UsbPcmProducer::threadMain() {
    while (running_.load(std::memory_order_acquire)) {
        if (paused_.load(std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(kIdleSleepMs));
            continue;
        }
        const uint64_t requested = seekRequest_.exchange(UINT64_MAX,
                                                        std::memory_order_acq_rel);
        if (requested != UINT64_MAX) {
            std::lock_guard<std::mutex> lock(fileMutex_);
            if (!fileSeek(file_, dataOffset_ +
                            requested * static_cast<uint64_t>(frameBytes_))) {
                lastError_ = "seek_failed";
                running_.store(false, std::memory_order_release);
                break;
            }
            framesRead_.store(requested, std::memory_order_relaxed);
            finished_.store(false, std::memory_order_release);
            // Control-thread contract: consumption is quiesced during a seek.
            renderer_->flush();
            continue;
        }

        const size_t freeFrames = renderer_->capacityFrames() -
                                  renderer_->availableFrames();
        if (freeFrames < static_cast<size_t>(kChunkFrames)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }

        int got = 0;
        {
            std::lock_guard<std::mutex> lock(fileMutex_);
            const uint64_t already = framesRead_.load(std::memory_order_relaxed);
            const uint64_t remaining = totalFrames_ > already
                ? totalFrames_ - already : 0;
            const int want = static_cast<int>(std::min<uint64_t>(
                kChunkFrames, remaining));
            if (want > 0) {
                const size_t bytes = static_cast<size_t>(want) *
                                     static_cast<size_t>(frameBytes_);
                got = static_cast<int>(std::fread(buffer_.data(), 1, bytes, file_) /
                                       static_cast<size_t>(frameBytes_));
            }
        }
        if (got <= 0) {
            finished_.store(true, std::memory_order_release);
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            continue;
        }
        if (!renderer_->write(buffer_.data(), got)) {
            // The capacity check above should make this impossible; treat a
            // rejected write as backpressure rather than dropping frames.
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        framesRead_.fetch_add(static_cast<uint64_t>(got), std::memory_order_relaxed);
        framesWritten_.fetch_add(static_cast<uint64_t>(got), std::memory_order_relaxed);
        finished_.store(false, std::memory_order_release);
    }
}

}  // namespace pulsr
