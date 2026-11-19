// android/app/src/main/cpp/UsbPullRenderer.cpp
//
// See UsbPullRenderer.h for the scope/threading contract. Everything here is
// deliberately boring: whole-frame memcpy, two atomic indices, and counters.
#include "UsbPullRenderer.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace pulsr {
namespace {

constexpr int kMinSampleRate = 8000;
constexpr int kMaxSampleRate = 1536000;
constexpr int kMaxChannels = 32;
constexpr int kMaxBytesPerSample = 8;
constexpr int kMaxBufferMs = 60000;
// Refuse implausible rings instead of letting a bad bufferMs turn into a huge
// allocation on the audio service thread.
constexpr size_t kMaxRingBytes = size_t{256} * 1024 * 1024;

size_t nextPowerOfTwo(size_t v) {
    size_t p = 1;
    while (p < v) p <<= 1;
    return p;
}

}  // namespace

bool UsbPullRenderer::Configure(int sampleRate, int channels, int bytesPerSample,
                                int bufferMs) {
    if (sampleRate < kMinSampleRate || sampleRate > kMaxSampleRate) return false;
    if (channels < 1 || channels > kMaxChannels) return false;
    if (bytesPerSample < 1 || bytesPerSample > kMaxBytesPerSample) return false;
    if (bufferMs < 1 || bufferMs > kMaxBufferMs) return false;

    const int frameBytes = channels * bytesPerSample;
    const size_t requested = static_cast<size_t>(
        (static_cast<int64_t>(sampleRate) * bufferMs + 999) / 1000);
    if (requested == 0) return false;

    const size_t capacity = nextPowerOfTwo(requested);
    // Overflow-safe byte check before touching the allocator.
    if (capacity > kMaxRingBytes / static_cast<size_t>(frameBytes)) return false;

    // std::vector aborts on OOM under -fno-exceptions (the DSP core build),
    // which is the desired fail-closed behaviour here: never publish a ring we
    // could not allocate.
    std::vector<uint8_t> ring;
    ring.assign(capacity * static_cast<size_t>(frameBytes), 0);

    ring_.swap(ring);
    sampleRate_ = sampleRate;
    channels_ = channels;
    bytesPerSample_ = bytesPerSample;
    frameBytes_ = frameBytes;
    bufferMs_ = bufferMs;
    requestedFrames_ = requested;
    capacityFrames_ = capacity;
    capacityMask_ = capacity - 1;
    // 80% of the configured duration, rounded down, at least one frame.
    prefillFrames_ = std::max<size_t>(1, requested * kPrefillNumerator / kPrefillDenominator);
    configured_ = true;

    writeIndex_.store(0, std::memory_order_relaxed);
    readIndex_.store(0, std::memory_order_relaxed);
    overrunEvents_.store(0, std::memory_order_relaxed);
    underrunEvents_.store(0, std::memory_order_relaxed);
    framesPulled_.store(0, std::memory_order_relaxed);
    paused_.store(false, std::memory_order_relaxed);
    prefillSatisfied_.store(false, std::memory_order_relaxed);
    return true;
}

void UsbPullRenderer::reset() {
    // Quiesced by contract. Clear the producer index first so a concurrent
    // observer can only see "empty", never a used count past capacity.
    writeIndex_.store(0, std::memory_order_relaxed);
    readIndex_.store(0, std::memory_order_relaxed);
    overrunEvents_.store(0, std::memory_order_relaxed);
    underrunEvents_.store(0, std::memory_order_relaxed);
    framesPulled_.store(0, std::memory_order_relaxed);
    paused_.store(false, std::memory_order_relaxed);
    prefillSatisfied_.store(false, std::memory_order_release);
}

void UsbPullRenderer::flush() {
    // Seek: the buffered audio is no longer the audio the user is listening
    // to, so it is dropped rather than played. This is not an underrun and not
    // an overrun, so neither counter moves.
    writeIndex_.store(0, std::memory_order_relaxed);
    readIndex_.store(0, std::memory_order_relaxed);
    prefillSatisfied_.store(false, std::memory_order_release);
}

void UsbPullRenderer::setPaused(bool paused) {
    paused_.store(paused, std::memory_order_release);
}

bool UsbPullRenderer::write(const void* src, int frames) {
    if (!configured_ || frames < 0) return false;
    if (frames == 0) return true;
    if (src == nullptr) return false;

    const uint64_t w = writeIndex_.load(std::memory_order_relaxed);
    const uint64_t r = readIndex_.load(std::memory_order_acquire);
    const uint64_t used = w - r;  // unsigned wrap is exact here
    const size_t n = static_cast<size_t>(frames);
    if (n > capacityFrames_ || used + n > capacityFrames_) {
        // All-or-nothing: a partially published block would let the consumer
        // hand a torn packet to the DAC.
        overrunEvents_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }

    const size_t fb = static_cast<size_t>(frameBytes_);
    const auto* in = static_cast<const uint8_t*>(src);
    const size_t pos = static_cast<size_t>(w) & capacityMask_;
    const size_t first = std::min(n, capacityFrames_ - pos);
    std::memcpy(ring_.data() + pos * fb, in, first * fb);
    if (first < n) {
        std::memcpy(ring_.data(), in + first * fb, (n - first) * fb);
    }
    writeIndex_.store(w + n, std::memory_order_release);

    // Prefill latch. Only the producer can raise it; flush()/reset() clear it
    // from the control thread while the stream is quiesced.
    if (!prefillSatisfied_.load(std::memory_order_relaxed) &&
        used + n >= static_cast<uint64_t>(prefillFrames_)) {
        prefillSatisfied_.store(true, std::memory_order_release);
    }
    return true;
}

size_t UsbPullRenderer::copyOut(uint8_t* dst, size_t frames) {
    const uint64_t r = readIndex_.load(std::memory_order_relaxed);
    const uint64_t w = writeIndex_.load(std::memory_order_acquire);
    const uint64_t used = w - r;
    const size_t n = std::min(frames, static_cast<size_t>(used));
    if (n == 0) return 0;

    const size_t fb = static_cast<size_t>(frameBytes_);
    const size_t pos = static_cast<size_t>(r) & capacityMask_;
    const size_t first = std::min(n, capacityFrames_ - pos);
    std::memcpy(dst, ring_.data() + pos * fb, first * fb);
    if (first < n) {
        std::memcpy(dst + first * fb, ring_.data(), (n - first) * fb);
    }
    readIndex_.store(r + n, std::memory_order_release);
    return n;
}

int UsbPullRenderer::pull(void* dst, int maxFrames) {
    if (!configured_ || maxFrames <= 0 || dst == nullptr) return 0;
    if (paused_.load(std::memory_order_acquire)) return 0;
    if (!prefillSatisfied_.load(std::memory_order_acquire)) return 0;

    const size_t got = copyOut(static_cast<uint8_t*>(dst), static_cast<size_t>(maxFrames));
    if (got != 0) framesPulled_.fetch_add(got, std::memory_order_relaxed);
    return static_cast<int>(got);
}

int UsbPullRenderer::pullExact(void* dst, int frames) {
    if (!configured_ || frames <= 0) return 0;
    if (dst == nullptr) return 0;
    if (paused_.load(std::memory_order_acquire)) return 0;
    if (!prefillSatisfied_.load(std::memory_order_acquire)) return 0;

    auto* out = static_cast<uint8_t*>(dst);
    const size_t want = static_cast<size_t>(frames);
    const size_t got = copyOut(out, want);
    if (got < want) {
        const size_t fb = static_cast<size_t>(frameBytes_);
        std::memset(out + got * fb, 0, (want - got) * fb);
        underrunEvents_.fetch_add(1, std::memory_order_relaxed);
    }
    if (got != 0) framesPulled_.fetch_add(got, std::memory_order_relaxed);
    return static_cast<int>(got);
}

size_t UsbPullRenderer::availableFrames() const {
    if (!configured_) return 0;
    const uint64_t r = readIndex_.load(std::memory_order_acquire);
    const uint64_t w = writeIndex_.load(std::memory_order_acquire);
    const uint64_t used = w - r;
    return static_cast<size_t>(std::min<uint64_t>(used, capacityFrames_));
}

int UsbPullRenderer::fillMs() const {
    if (!configured_ || sampleRate_ <= 0) return 0;
    const uint64_t frames = static_cast<uint64_t>(availableFrames());
    const uint64_t ms = frames * 1000ULL / static_cast<uint64_t>(sampleRate_);
    return static_cast<int>(std::min<uint64_t>(ms, static_cast<uint64_t>(kMaxBufferMs)));
}

int UsbPullRenderer::driftPpm(int64_t producerFrames, int64_t consumerFrames) {
    if (consumerFrames <= 0) return 0;
    const long double delta =
        static_cast<long double>(producerFrames) - static_cast<long double>(consumerFrames);
    const long double ppm = delta / static_cast<long double>(consumerFrames) * 1.0e6L;
    if (ppm > 1.0e6L) return 1000000;
    if (ppm < -1.0e6L) return -1000000;
    return static_cast<int>(std::llround(ppm));
}

}  // namespace pulsr
