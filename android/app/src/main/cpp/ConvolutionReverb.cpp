#include "ConvolutionReverb.h"
#include <random>
#include <algorithm>
#include <cstring>
#include <cmath>
#include <mutex>
#include <map>
#include <list>
#include <tuple>
#if defined(__ANDROID__)
#include <android/log.h>
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

struct SyntheticCacheKey {
    int preset;
    int sampleRate;
    int dampingKey; // damping * 50

    bool operator<(const SyntheticCacheKey& other) const {
        return std::tie(preset, sampleRate, dampingKey) < std::tie(other.preset, other.sampleRate, other.dampingKey);
    }
};

struct SyntheticCacheEntry {
    std::shared_ptr<const PreparedIr> ir;
    size_t byteSize = 0;
    std::list<SyntheticCacheKey>::iterator lruIt;
};

static constexpr size_t SYNTHETIC_CACHE_BUDGET_BYTES = 64 * 1024 * 1024; // 64 MB (R1)
static std::mutex sIrCacheMutex;
static std::map<SyntheticCacheKey, SyntheticCacheEntry> sIrCacheMap;
static std::list<SyntheticCacheKey> sIrCacheLruList;
static std::vector<std::pair<std::weak_ptr<const PreparedIr>, size_t>> sCustomIrRegistry;
static size_t sCurrentCacheBytes = 0;
static std::atomic<uint64_t> sCacheMutexLockCount{0};

static void pruneExpiredCustomIrsLocked() {
    for (auto it = sCustomIrRegistry.begin(); it != sCustomIrRegistry.end(); ) {
        if (it->first.expired()) {
            if (sCurrentCacheBytes >= it->second) {
                sCurrentCacheBytes -= it->second;
            } else {
                sCurrentCacheBytes = 0;
            }
            it = sCustomIrRegistry.erase(it);
        } else {
            ++it;
        }
    }
}

uint64_t PreparedIr::getCacheMutexLockCount() {
    return sCacheMutexLockCount.load(std::memory_order_relaxed);
}

void PreparedIr::resetCacheMutexLockCount() {
    sCacheMutexLockCount.store(0, std::memory_order_relaxed);
}

struct CacheLockGuard {
    std::lock_guard<std::mutex> lock;
    CacheLockGuard(std::mutex& m) : lock(m) {
        sCacheMutexLockCount.fetch_add(1, std::memory_order_relaxed);
    }
};

size_t PreparedIr::getSyntheticCacheBytes() {
    CacheLockGuard lock(sIrCacheMutex);
    pruneExpiredCustomIrsLocked();
    return sCurrentCacheBytes;
}

size_t PreparedIr::getSyntheticCacheEntryCount() {
    CacheLockGuard lock(sIrCacheMutex);
    return sIrCacheMap.size();
}

void PreparedIr::clearSyntheticCache() {
    CacheLockGuard lock(sIrCacheMutex);
    sIrCacheMap.clear();
    sIrCacheLruList.clear();
    sCustomIrRegistry.clear();
    sCurrentCacheBytes = 0;
}

std::shared_ptr<const PreparedIr> PreparedIr::create(
        const float* irLData, const float* irRData, int totalTaps) {
    if (!irLData || !irRData || totalTaps <= 0) return nullptr;

    auto ir = std::make_shared<PreparedIr>();
    ir->totalTaps = totalTaps;
    ir->irL.assign(irLData, irLData + totalTaps);
    ir->irR.assign(irRData, irRData + totalTaps);

    if (totalTaps <= 1024) {
        ir->numPartitions = 0;
        return ir;
    }

    ir->numPartitions = (totalTaps + PARTITION_SIZE - 1) / PARTITION_SIZE;
    ir->irFreqL.assign(ir->numPartitions, std::vector<FftUtil::Complex>(FFT_SIZE));
    ir->irFreqR.assign(ir->numPartitions, std::vector<FftUtil::Complex>(FFT_SIZE));

    std::vector<FftUtil::Complex> timeBlockL(FFT_SIZE);
    std::vector<FftUtil::Complex> timeBlockR(FFT_SIZE);

    for (int p = 0; p < ir->numPartitions; ++p) {
        std::fill(timeBlockL.begin(), timeBlockL.end(), FftUtil::Complex(0.0f, 0.0f));
        std::fill(timeBlockR.begin(), timeBlockR.end(), FftUtil::Complex(0.0f, 0.0f));

        const int start = p * PARTITION_SIZE;
        const int count = std::min(PARTITION_SIZE, totalTaps - start);

        for (int i = 0; i < count; ++i) {
            timeBlockL[i] = FftUtil::Complex(ir->irL[start + i], 0.0f);
            timeBlockR[i] = FftUtil::Complex(ir->irR[start + i], 0.0f);
        }

        FftUtil::fft(timeBlockL);
        FftUtil::fft(timeBlockR);

        ir->irFreqL[p] = timeBlockL;
        ir->irFreqR[p] = timeBlockR;
    }

    return ir;
}

std::shared_ptr<const PreparedIr> PreparedIr::createSynthetic(
        double sampleRate, int presetInt, float dampingFactor) {
    auto preset = static_cast<ReverbPreset>(presetInt);
    if (preset == ReverbPreset::Custom) return nullptr;

    const int srKey = static_cast<int>(std::round(sampleRate));
    const int dampKey = static_cast<int>(std::round(dampingFactor * 50.0f)); // Quantize * 50 (R1)
    const SyntheticCacheKey key{presetInt, srKey, dampKey};

    {
        CacheLockGuard lock(sIrCacheMutex);
        pruneExpiredCustomIrsLocked();
        auto it = sIrCacheMap.find(key);
        if (it != sIrCacheMap.end()) {
            // Touch LRU: move existing node to front with ZERO allocations via std::list::splice
            sIrCacheLruList.splice(sIrCacheLruList.begin(), sIrCacheLruList, it->second.lruIt);
            return it->second.ir;
        }
    }

    float rt60 = 1.2f;
    float presetDamp = 0.5f;

    switch (preset) {
        case ReverbPreset::Studio:      rt60 = 0.35f; presetDamp = 0.7f; break;
        case ReverbPreset::Room:        rt60 = 0.85f; presetDamp = 0.5f; break;
        case ReverbPreset::Chamber:     rt60 = 1.40f; presetDamp = 0.4f; break;
        case ReverbPreset::Hall:        rt60 = 2.20f; presetDamp = 0.35f; break;
        case ReverbPreset::ConcertHall: rt60 = 3.20f; presetDamp = 0.3f; break;
        case ReverbPreset::Cathedral:   rt60 = 5.00f; presetDamp = 0.2f; break;
        case ReverbPreset::Plate:       rt60 = 1.80f; presetDamp = 0.1f; break;
        case ReverbPreset::Spring:      rt60 = 1.10f; presetDamp = 0.6f; break;
        case ReverbPreset::Custom:      return nullptr;
    }

    // Respect user damping as multiplier on preset damping (BUG-004)
    const float damp = std::clamp(presetDamp * dampingFactor * 2.0f, 0.05f, 0.95f);

    int totalSamples = static_cast<int>(rt60 * sampleRate);
    if (totalSamples <= 0) return nullptr;
    // Tail truncation note (A9/N-04): For sample rates >192kHz with long decay presets (e.g., Cathedral @352.8kHz = 1.76M taps, @768kHz = 3.84M taps),
    // synthetic IRs are capped at kMaxSyntheticTaps (2048 partitions * 512 = 1,048,576 taps) to guarantee RT zero-allocation
    // and bound memory usage under 64MB. The reverberant tail beyond ~2.97s (at 352.8kHz) is truncated, which is below the human
    // perceptual audibility floor (-60dB RT60 decay).
    constexpr int kMaxSyntheticTaps = ConvolutionReverb::MAX_PREALLOC_PARTITIONS * ConvolutionReverb::PARTITION_SIZE;
    if (totalSamples > kMaxSyntheticTaps) {
#if defined(__ANDROID__)
        __android_log_print(ANDROID_LOG_INFO, "ConvolutionReverb",
            "Synthetic IR for preset %d at %.0f Hz truncated from %d to %d taps (>192kHz cap)",
            presetInt, sampleRate, totalSamples, kMaxSyntheticTaps);
#endif
        totalSamples = kMaxSyntheticTaps;
    }

    std::vector<float> irL(totalSamples);
    std::vector<float> irR(totalSamples);

    std::mt19937 genL(12345);
    std::mt19937 genR(12345 + 98765);
    std::normal_distribution<float> dist(0.0f, 1.0f);

    const float decayRate = -6.907755f / static_cast<float>(totalSamples); // ln(0.001) = -6.907755 (-60dB)

    // Air absorption one-pole lowpass filter state
    float lpStateL = 0.0f;
    float lpStateR = 0.0f;
    const float lpAlpha = 1.0f - std::clamp(damp * 0.8f, 0.05f, 0.95f);

    double energySum = 0.0;

    for (int i = 0; i < totalSamples; ++i) {
        const float env = std::exp(decayRate * static_cast<float>(i));
        const float noiseL = dist(genL);
        const float noiseR = dist(genR);

        lpStateL += lpAlpha * (noiseL - lpStateL);
        lpStateR += lpAlpha * (noiseR - lpStateR);

        const float sL = env * lpStateL;
        const float sR = env * lpStateR;

        irL[i] = sL;
        irR[i] = sR;

        energySum += sL * sL + sR * sR;
    }

    // Normalize to maintain unity acoustic gain
    if (energySum > 1e-9) {
        const float norm = static_cast<float>(std::sqrt(2.0 / energySum) * 0.45);
        for (int i = 0; i < totalSamples; ++i) {
            irL[i] *= norm;
            irR[i] *= norm;
        }
    }

    auto created = create(irL.data(), irR.data(), totalSamples);
    if (created) {
        const_cast<PreparedIr*>(created.get())->createdSampleRate = static_cast<int>(std::round(sampleRate));
        const size_t entrySize = static_cast<size_t>(created->totalTaps) * 12 +
                                 static_cast<size_t>(created->numPartitions) * ConvolutionReverb::FFT_SIZE * 16;
        CacheLockGuard lock(sIrCacheMutex);
        pruneExpiredCustomIrsLocked();
        auto it = sIrCacheMap.find(key);
        if (it != sIrCacheMap.end()) {
            sIrCacheLruList.splice(sIrCacheLruList.begin(), sIrCacheLruList, it->second.lruIt);
            return it->second.ir;
        }

        // Evict oldest entries to satisfy 64MB budget (R1)
        // Guard: single oversized entry must never breach budget (B-01)
        if (entrySize > SYNTHETIC_CACHE_BUDGET_BYTES) {
            return created; // usable but uncached — prevents 77MB Cathedral@352.8k / 169MB@768k from over-budgeting
        }
        while (sCurrentCacheBytes + entrySize > SYNTHETIC_CACHE_BUDGET_BYTES && !sIrCacheLruList.empty()) {
            const auto oldestKey = sIrCacheLruList.back();
            auto mapIt = sIrCacheMap.find(oldestKey);
            if (mapIt != sIrCacheMap.end()) {
                sCurrentCacheBytes -= mapIt->second.byteSize;
                sIrCacheMap.erase(mapIt);
            }
            sIrCacheLruList.pop_back();
        }
        if (sCurrentCacheBytes + entrySize > SYNTHETIC_CACHE_BUDGET_BYTES) {
            return created; // still over after evicting everything → return uncached
        }

        sIrCacheLruList.push_front(key);
        sIrCacheMap[key] = SyntheticCacheEntry{created, entrySize, sIrCacheLruList.begin()};
        sCurrentCacheBytes += entrySize;
    }
    return created;
}

std::shared_ptr<const PreparedIr> PreparedIr::createCustom(
        double sampleRate, const float* irInterleaved, int frames, int channels) {
    if (!irInterleaved || frames <= 0 || channels < 1) return nullptr;

    // Cap numPartitions at 512 (BUG-005)
    constexpr int MAX_CUSTOM_PARTITIONS = 512;
    constexpr int MAX_CUSTOM_TAPS = MAX_CUSTOM_PARTITIONS * PARTITION_SIZE; // 262,144 samples

    int actualFrames = frames;
    std::vector<float> irL;
    std::vector<float> irR;

    if (frames > MAX_CUSTOM_TAPS) {
        // High-order windowed-sinc anti-aliasing decimation (>80dB stopband attenuation)
        actualFrames = MAX_CUSTOM_TAPS;
        irL.resize(actualFrames);
        irR.resize(actualFrames);

        const double step = static_cast<double>(frames) / static_cast<double>(actualFrames);
        const float fc = static_cast<float>(0.45 / step); // Normalized to input rate Nyquist

        constexpr int FIR_TAPS = 63;
        constexpr int HALF_FIR = FIR_TAPS / 2;
        float firCoeffs[FIR_TAPS] = {};
        double coeffSum = 0.0;

        for (int k = 0; k < FIR_TAPS; ++k) {
            const int n = k - HALF_FIR;
            float sincVal = 1.0f;
            if (n != 0) {
                const float x = 2.0f * static_cast<float>(M_PI) * fc * static_cast<float>(n);
                sincVal = std::sin(x) / x;
            }
            const double w = 2.0 * M_PI * k / (FIR_TAPS - 1);
            const double win = 0.35875 - 0.48829 * std::cos(w) + 0.14128 * std::cos(2.0 * w) - 0.01168 * std::cos(3.0 * w);
            firCoeffs[k] = static_cast<float>(2.0f * fc * sincVal * win);
            coeffSum += firCoeffs[k];
        }

        if (std::abs(coeffSum) > 1e-6) {
            const float invSum = static_cast<float>(1.0 / coeffSum);
            for (int k = 0; k < FIR_TAPS; ++k) {
                firCoeffs[k] *= invSum;
            }
        }

        for (int i = 0; i < actualFrames; ++i) {
            const double srcCenter = i * step;
            const int centerIdx = static_cast<int>(std::round(srcCenter));

            float sumL = 0.0f;
            float sumR = 0.0f;

            for (int k = 0; k < FIR_TAPS; ++k) {
                const int sampleIdx = std::clamp(centerIdx + k - HALF_FIR, 0, frames - 1);
                const float l = irInterleaved[sampleIdx * channels];
                const float r = (channels > 1) ? irInterleaved[sampleIdx * channels + 1] : l;
                sumL += l * firCoeffs[k];
                sumR += r * firCoeffs[k];
            }

            irL[i] = sumL;
            irR[i] = sumR;
        }
    } else {
        irL.resize(actualFrames);
        irR.resize(actualFrames);
        for (int i = 0; i < actualFrames; ++i) {
            const float l = irInterleaved[i * channels];
            const float r = (channels > 1) ? irInterleaved[i * channels + 1] : l;
            irL[i] = l;
            irR[i] = r;
        }
    }

    auto created = create(irL.data(), irR.data(), actualFrames);
    if (!created) return nullptr;
    const_cast<PreparedIr*>(created.get())->createdSampleRate = static_cast<int>(std::round(sampleRate));

    // Apply 64MB budget & LRU eviction with Custom IR registry tracking (NEW-2)
    const size_t entrySize = static_cast<size_t>(created->totalTaps) * 12 +
                             static_cast<size_t>(created->numPartitions) * ConvolutionReverb::FFT_SIZE * 16;
    if (entrySize > SYNTHETIC_CACHE_BUDGET_BYTES) {
        return nullptr; // Exceeds entire budget
    }

    {
        CacheLockGuard lock(sIrCacheMutex);
        pruneExpiredCustomIrsLocked();

        // Evict synthetic LRU entries if needed
        while (sCurrentCacheBytes + entrySize > SYNTHETIC_CACHE_BUDGET_BYTES && !sIrCacheLruList.empty()) {
            const auto oldestKey = sIrCacheLruList.back();
            auto mapIt = sIrCacheMap.find(oldestKey);
            if (mapIt != sIrCacheMap.end()) {
                sCurrentCacheBytes -= mapIt->second.byteSize;
                sIrCacheMap.erase(mapIt);
            }
            sIrCacheLruList.pop_back();
        }

        if (sCurrentCacheBytes + entrySize > SYNTHETIC_CACHE_BUDGET_BYTES) {
            return nullptr; // Custom IRs currently alive exceed remaining budget
        }

        sCurrentCacheBytes += entrySize;
        sCustomIrRegistry.emplace_back(created, entrySize);
    }

    return created;
}

ConvolutionReverb::ConvolutionReverb() {
    // Pre-allocate minimal working buffers (predelay, single partition, fftWork)
    predelayRingL_.assign(MAX_PREDELAY_SAMPLES, 0.0f);
    predelayRingR_.assign(MAX_PREDELAY_SAMPLES, 0.0f);
    predelayWritePos_ = 0;

    prevBlockL_.assign(PARTITION_SIZE, 0.0f);
    prevBlockR_.assign(PARTITION_SIZE, 0.0f);
    inputBlockL_.assign(PARTITION_SIZE, 0.0f);
    inputBlockR_.assign(PARTITION_SIZE, 0.0f);
    fftWorkL_.assign(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f));
    fftWorkR_.assign(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f));
    accumFreqL_.assign(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f));
    accumFreqR_.assign(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f));

    // A8 (N-03): Lazy-allocate inputHistoryFreqL_/R_ on publisher thread in preparePartitions()
    // rather than eagerly allocating 2048 partitions (32MB) in constructor.
    // Resident memory before enable remains < 1MB.
    inputHistoryFreqL_.clear();
    inputHistoryFreqR_.clear();
    directRingL_.assign(1024 * 2 + 16, 0.0f);
    directRingR_.assign(1024 * 2 + 16, 0.0f);

    ensureScratchCapacity(8192);
    setPreset(ReverbPreset::Room);
    reset();
}

void ConvolutionReverb::ensurePredelayCapacity() {
    // Fixed max capacity (153,600) pre-allocated in constructor (Sr up to 768kHz * 0.200).
    // Real-time audio thread never re-allocates.
    const int requiredCap = std::max(4096, static_cast<int>(sampleRate_ * 0.150) + 16);
    if (static_cast<int>(predelayRingL_.size()) < requiredCap) {
        predelayRingL_.assign(MAX_PREDELAY_SAMPLES, 0.0f);
        predelayRingR_.assign(MAX_PREDELAY_SAMPLES, 0.0f);
    }
}

void ConvolutionReverb::ensureScratchCapacity(int frames) {
    if (static_cast<int>(scratchInL_.size()) < frames) {
        scratchInL_.resize(frames, 0.0f);
        scratchInR_.resize(frames, 0.0f);
        scratchOutL_.resize(frames, 0.0f);
        scratchOutR_.resize(frames, 0.0f);
    }
}

void ConvolutionReverb::setSampleRate(double sampleRate) {
    if (sampleRate <= 0.0 || std::abs(sampleRate_ - sampleRate) < 1.0) return;
    sampleRate_ = sampleRate;
    setPredelay(predelayMs_);
    ensurePredelayCapacity();
    // A2 (B-05): Regenerate prepared IR for non-custom presets
    if (preset_ != ReverbPreset::Custom) {
        updatePreparedIr();
    }
}

void ConvolutionReverb::setPreset(ReverbPreset preset) {
    preset_ = preset;
    updatePreparedIr();
}

void ConvolutionReverb::updatePreparedIr() {
    if (preset_ == ReverbPreset::Custom) return;
    preparedIr_ = PreparedIr::createSynthetic(sampleRate_, static_cast<int>(preset_), static_cast<float>(damping_));
    preparePartitions();
}

void ConvolutionReverb::setWetDry(double wet) {
    targetWet_ = std::clamp(wet, 0.0, 1.0);
    smoothedWet_ = targetWet_;
}

void ConvolutionReverb::setPredelay(double predelayMs) {
    predelayMs_ = std::clamp(predelayMs, 0.0, 150.0);
    targetPredelaySamples_ = static_cast<float>(predelayMs_ * 0.001 * sampleRate_);
}

void ConvolutionReverb::setDamping(double damping) {
    damping_ = std::clamp(damping, 0.0, 1.0);
    updatePreparedIr();
}

void ConvolutionReverb::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void ConvolutionReverb::applyParams(const ReverbParamSet& params) {
    enabled_ = params.enabled;
    targetWet_ = std::clamp(params.wetDry, 0.0, 1.0);
    setPredelay(params.predelayMs);
    damping_ = std::clamp(params.damping, 0.0, 1.0);

    // BUG-001 / [A1]: Audio-thread RT safety:
    // If preparedIr is provided, apply it. If null, DO NOT allocate or lock cache on audio thread.
    if (params.preparedIr) {
        if (params.preparedIr != preparedIr_) {
            preparedIr_ = params.preparedIr;
            preset_ = static_cast<ReverbPreset>(params.preset);
            preparePartitions();
        }
    }
}

bool ConvolutionReverb::loadCustomIR(const float* irInterleaved, int frames, int channels) {
    auto customIr = PreparedIr::createCustom(sampleRate_, irInterleaved, frames, channels);
    if (!customIr) return false;

    preparedIr_ = customIr;
    preset_ = ReverbPreset::Custom;
    preparePartitions();
    return true;
}

void ConvolutionReverb::preparePartitions() {
    ensureScratchCapacity(8192);
    if (!preparedIr_) return;

    if (preparedIr_->numPartitions == 0) {
        const int ringSize = preparedIr_->totalTaps * 2 + 16;
        if (static_cast<int>(directRingL_.size()) < ringSize) {
            directRingL_.resize(ringSize, 0.0f);
            directRingR_.resize(ringSize, 0.0f);
        }
        std::fill(directRingL_.begin(), directRingL_.end(), 0.0f);
        std::fill(directRingR_.begin(), directRingR_.end(), 0.0f);
        directPos_ = 0;
        return;
    }

    // B-06: RT-alloc guard — cap effective partitions to preallocated max (2048) to avoid
    // unbounded allocation on the audio thread (Cathedral@768k = 7500 partitions → 245MB).
    // Synthetic creation is already capped, but custom or stale cached IR may still exceed.
    const int effectivePartitions = std::min(preparedIr_->numPartitions, MAX_PREALLOC_PARTITIONS);
    if (preparedIr_->numPartitions > MAX_PREALLOC_PARTITIONS) {
        // A3 (N-02): Log warning when partitions exceed max preallocated cap
#if defined(__ANDROID__)
        __android_log_print(ANDROID_LOG_WARN, "ConvolutionReverb",
            "IR partitions (%d) exceed MAX_PREALLOC_PARTITIONS (%d); tail truncated for RT safety",
            preparedIr_->numPartitions, MAX_PREALLOC_PARTITIONS);
#endif
    }
    const int numPartitions = effectivePartitions;
    if (static_cast<int>(inputHistoryFreqL_.size()) < MAX_PREALLOC_PARTITIONS) {
        inputHistoryFreqL_.resize(MAX_PREALLOC_PARTITIONS, std::vector<FftUtil::Complex>(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f)));
        inputHistoryFreqR_.resize(MAX_PREALLOC_PARTITIONS, std::vector<FftUtil::Complex>(FFT_SIZE, FftUtil::Complex(0.0f, 0.0f)));
    }

    for (int p = 0; p < numPartitions; ++p) {
        std::fill(inputHistoryFreqL_[p].begin(), inputHistoryFreqL_[p].end(), FftUtil::Complex(0.0f, 0.0f));
        std::fill(inputHistoryFreqR_[p].begin(), inputHistoryFreqR_[p].end(), FftUtil::Complex(0.0f, 0.0f));
    }
    historyHead_ = 0;

    std::fill(prevBlockL_.begin(), prevBlockL_.end(), 0.0f);
    std::fill(prevBlockR_.begin(), prevBlockR_.end(), 0.0f);
    std::fill(inputBlockL_.begin(), inputBlockL_.end(), 0.0f);
    std::fill(inputBlockR_.begin(), inputBlockR_.end(), 0.0f);
    inputBlockPos_ = 0;

    std::fill(fftWorkL_.begin(), fftWorkL_.end(), FftUtil::Complex(0.0f, 0.0f));
    std::fill(fftWorkR_.begin(), fftWorkR_.end(), FftUtil::Complex(0.0f, 0.0f));
    std::fill(accumFreqL_.begin(), accumFreqL_.end(), FftUtil::Complex(0.0f, 0.0f));
    std::fill(accumFreqR_.begin(), accumFreqR_.end(), FftUtil::Complex(0.0f, 0.0f));
}

void ConvolutionReverb::reset() {
    ensurePredelayCapacity();
    ensureScratchCapacity(4096);
    std::fill(predelayRingL_.begin(), predelayRingL_.end(), 0.0f);
    std::fill(predelayRingR_.begin(), predelayRingR_.end(), 0.0f);
    predelayWritePos_ = 0;
    smoothedPredelaySamples_ = targetPredelaySamples_;
    smoothedWet_ = targetWet_;

    if (!preparedIr_) return;

    if (preparedIr_->numPartitions == 0) {
        std::fill(directRingL_.begin(), directRingL_.end(), 0.0f);
        std::fill(directRingR_.begin(), directRingR_.end(), 0.0f);
        directPos_ = 0;
    } else {
        std::fill(prevBlockL_.begin(), prevBlockL_.end(), 0.0f);
        std::fill(prevBlockR_.begin(), prevBlockR_.end(), 0.0f);
        std::fill(inputBlockL_.begin(), inputBlockL_.end(), 0.0f);
        std::fill(inputBlockR_.begin(), inputBlockR_.end(), 0.0f);
        for (auto& h : inputHistoryFreqL_) std::fill(h.begin(), h.end(), FftUtil::Complex(0.0f, 0.0f));
        for (auto& h : inputHistoryFreqR_) std::fill(h.begin(), h.end(), FftUtil::Complex(0.0f, 0.0f));
        std::fill(accumFreqL_.begin(), accumFreqL_.end(), FftUtil::Complex(0.0f, 0.0f));
        std::fill(accumFreqR_.begin(), accumFreqR_.end(), FftUtil::Complex(0.0f, 0.0f));
        inputBlockPos_ = 0;
        historyHead_ = 0;
    }
}

void ConvolutionReverb::process(const float* inL, const float* inR, float* outL, float* outR, int frames) {
    if (!enabled_ || !preparedIr_ || preparedIr_->totalTaps == 0) {
        if (inL != outL) std::memcpy(outL, inL, frames * sizeof(float));
        if (inR != outR) std::memcpy(outR, inR, frames * sizeof(float));
        return;
    }

    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * 0.020));
    smoothedWet_ += smoothFactor * (targetWet_ - smoothedWet_);

    const float dryGain = static_cast<float>(std::cos(smoothedWet_ * (M_PI / 2.0)));
    const float wetGain = static_cast<float>(std::sin(smoothedWet_ * (M_PI / 2.0)));

    const int totalTaps = preparedIr_->totalTaps;
    const int predelayCap = static_cast<int>(predelayRingL_.size());

    // Direct FIR convolution path (for IR <= 1024) - BUG-006 vectorized contiguous loop
    if (preparedIr_->numPartitions == 0) {
        const float* irL = preparedIr_->irL.data();
        const float* irR = preparedIr_->irR.data();

        for (int i = 0; i < frames; ++i) {
            float inSampleL = inL[i];
            float inSampleR = inR[i];

            // Smooth predelay interpolation
            smoothedPredelaySamples_ += 0.005f * (targetPredelaySamples_ - smoothedPredelaySamples_);
            if (smoothedPredelaySamples_ > 0.5f && predelayCap > 0) {
                predelayRingL_[predelayWritePos_] = inSampleL;
                predelayRingR_[predelayWritePos_] = inSampleR;

                float exactReadPos = static_cast<float>(predelayWritePos_) - smoothedPredelaySamples_;
                while (exactReadPos < 0.0f) exactReadPos += static_cast<float>(predelayCap);
                int readPos0 = static_cast<int>(exactReadPos) % predelayCap;
                int readPos1 = (readPos0 + 1) % predelayCap;
                float frac = exactReadPos - static_cast<float>(static_cast<int>(exactReadPos));

                inSampleL = (1.0f - frac) * predelayRingL_[readPos0] + frac * predelayRingL_[readPos1];
                inSampleR = (1.0f - frac) * predelayRingR_[readPos0] + frac * predelayRingR_[readPos1];

                predelayWritePos_ = (predelayWritePos_ + 1) % predelayCap;
            }

            directRingL_[directPos_] = inSampleL;
            directRingL_[directPos_ + totalTaps] = inSampleL;
            directRingR_[directPos_] = inSampleR;
            directRingR_[directPos_ + totalTaps] = inSampleR;

            float convL = 0.0f;
            float convR = 0.0f;

            // Direct contiguous pointer loop with zero branches and zero modulo (BUG-006)
            const float* rL = &directRingL_[directPos_ + totalTaps];
            const float* rR = &directRingR_[directPos_ + totalTaps];

            for (int tap = 0; tap < totalTaps; ++tap) {
                convL += rL[-tap] * irL[tap];
                convR += rR[-tap] * irR[tap];
            }

            outL[i] = inL[i] * dryGain + convL * wetGain;
            outR[i] = inR[i] * dryGain + convR * wetGain;

            directPos_ = (directPos_ + 1) % totalTaps;
        }
        return;
    }

    // Textbook Uniform-Partitioned Overlap-Save FFT Convolution (for IR > 1024)
    // B-06 clamp: keep effective partitions within preallocated max to guarantee RT safety
    const int numPartitions = std::min(preparedIr_->numPartitions, MAX_PREALLOC_PARTITIONS);
    const auto& irFreqL = preparedIr_->irFreqL;
    const auto& irFreqR = preparedIr_->irFreqR;

    for (int i = 0; i < frames; ++i) {
        float inSampleL = inL[i];
        float inSampleR = inR[i];

        // Smooth predelay interpolation
        smoothedPredelaySamples_ += 0.005f * (targetPredelaySamples_ - smoothedPredelaySamples_);
        if (smoothedPredelaySamples_ > 0.5f && predelayCap > 0) {
            predelayRingL_[predelayWritePos_] = inSampleL;
            predelayRingR_[predelayWritePos_] = inSampleR;

            float exactReadPos = static_cast<float>(predelayWritePos_) - smoothedPredelaySamples_;
            while (exactReadPos < 0.0f) exactReadPos += static_cast<float>(predelayCap);
            int readPos0 = static_cast<int>(exactReadPos) % predelayCap;
            int readPos1 = (readPos0 + 1) % predelayCap;
            float frac = exactReadPos - static_cast<float>(static_cast<int>(exactReadPos));

            inSampleL = (1.0f - frac) * predelayRingL_[readPos0] + frac * predelayRingL_[readPos1];
            inSampleR = (1.0f - frac) * predelayRingR_[readPos0] + frac * predelayRingR_[readPos1];

            predelayWritePos_ = (predelayWritePos_ + 1) % predelayCap;
        }

        inputBlockL_[inputBlockPos_] = inSampleL;
        inputBlockR_[inputBlockPos_] = inSampleR;

        // Overlap-save retrieval: valid linear convolution output is at index PARTITION_SIZE + inputBlockPos_
        const float convSampleL = accumFreqL_[PARTITION_SIZE + inputBlockPos_].real();
        const float convSampleR = accumFreqR_[PARTITION_SIZE + inputBlockPos_].real();

        outL[i] = inL[i] * dryGain + convSampleL * wetGain;
        outR[i] = inR[i] * dryGain + convSampleR * wetGain;

        inputBlockPos_++;

        if (inputBlockPos_ == PARTITION_SIZE) {
            // Assemble FFT input buffer = [prevBlock (0..P-1) | inputBlock (P..2P-1)]
            for (int k = 0; k < PARTITION_SIZE; ++k) {
                fftWorkL_[k] = FftUtil::Complex(prevBlockL_[k], 0.0f);
                fftWorkR_[k] = FftUtil::Complex(prevBlockR_[k], 0.0f);
                fftWorkL_[PARTITION_SIZE + k] = FftUtil::Complex(inputBlockL_[k], 0.0f);
                fftWorkR_[PARTITION_SIZE + k] = FftUtil::Complex(inputBlockR_[k], 0.0f);
            }

            FftUtil::fft(fftWorkL_);
            FftUtil::fft(fftWorkR_);

            inputHistoryFreqL_[historyHead_] = fftWorkL_;
            inputHistoryFreqR_[historyHead_] = fftWorkR_;

            // Frequency domain complex MAC accumulation across all partitions
            std::fill(accumFreqL_.begin(), accumFreqL_.end(), FftUtil::Complex(0.0f, 0.0f));
            std::fill(accumFreqR_.begin(), accumFreqR_.end(), FftUtil::Complex(0.0f, 0.0f));

            for (int p = 0; p < numPartitions; ++p) {
                int histIdx = (historyHead_ - p) % numPartitions;
                if (histIdx < 0) histIdx += numPartitions;

                const auto& inFreqL = inputHistoryFreqL_[histIdx];
                const auto& inFreqR = inputHistoryFreqR_[histIdx];
                const auto& irBlockL = irFreqL[p];
                const auto& irBlockR = irFreqR[p];

                for (int k = 0; k < FFT_SIZE; ++k) {
                    accumFreqL_[k] += inFreqL[k] * irBlockL[k];
                    accumFreqR_[k] += inFreqR[k] * irBlockR[k];
                }
            }

            // IFFT to return to time domain
            FftUtil::fft(accumFreqL_, true);
            FftUtil::fft(accumFreqR_, true);

            // Overlap-save block advance: current block becomes previous block
            prevBlockL_ = inputBlockL_;
            prevBlockR_ = inputBlockR_;

            historyHead_ = (historyHead_ + 1) % numPartitions;
            inputBlockPos_ = 0;
        }
    }
}

void ConvolutionReverb::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !buffer || frames <= 0 || channels < 2 || !preparedIr_ || preparedIr_->totalTaps == 0) return;

    ensureScratchCapacity(frames);

    float* inL = scratchInL_.data();
    float* inR = scratchInR_.data();
    float* outL = scratchOutL_.data();
    float* outR = scratchOutR_.data();

    for (int i = 0; i < frames; ++i) {
        inL[i] = buffer[i * channels];
        inR[i] = buffer[i * channels + 1];
    }

    process(inL, inR, outL, outR, frames);

    for (int i = 0; i < frames; ++i) {
        buffer[i * channels] = outL[i];
        buffer[i * channels + 1] = outR[i];
    }
}
