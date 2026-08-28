// android/app/src/main/cpp/DspParams.h
#pragma once

#include <cstdint>
#include <memory>
#include <atomic>
#include <vector>
#include "FftUtil.h"

enum class FilterType {
    Peaking = 0,
    LowShelf = 1,
    HighShelf = 2,
    LowPass = 3,
    HighPass = 4,
    Notch = 5,
    BandPass = 6,
    AllPass = 7
};

struct EqBandParam {
    double frequency = 1000.0;
    double gainDb = 0.0;
    double q = 1.0;
    FilterType type = FilterType::Peaking;
    bool enabled = true;
    bool solo = false;
    bool mute = false;
};

struct EqParamSet {
    static constexpr int MAX_BANDS = 32;
    EqBandParam bands[MAX_BANDS];
    int bandCount = 10;
    double preampDb = 0.0;
    bool enabled = true;
};

struct CrossfeedParamSet {
    double delayUs = 350.0;
    double feedDb = -9.0;
    double fcut = 650.0;
    bool enabled = true;
};

struct LimiterParamSet {
    double lookaheadMs = 5.0;
    double thresholdDb = -0.2;
    double releaseMs = 50.0;
    bool truePeakMode = true;
    bool enabled = true;
};

struct PreparedIr {
    static constexpr int PARTITION_SIZE = 512;
    static constexpr int FFT_SIZE = PARTITION_SIZE * 2; // 1024

    int totalTaps = 0;
    int createdSampleRate = 0;
    std::vector<float> irL;
    std::vector<float> irR;
    int numPartitions = 0;
    std::vector<std::vector<FftUtil::Complex>> irFreqL;
    std::vector<std::vector<FftUtil::Complex>> irFreqR;

    static std::shared_ptr<const PreparedIr> create(
        const float* irLData, const float* irRData, int totalTaps);
    static std::shared_ptr<const PreparedIr> createSynthetic(
        double sampleRate, int preset, float damping);
    static std::shared_ptr<const PreparedIr> createCustom(
        double sampleRate, const float* irInterleaved, int frames, int channels);

    static size_t getSyntheticCacheBytes();
    static size_t getSyntheticCacheEntryCount();
    static void clearSyntheticCache();
    static uint64_t getCacheMutexLockCount();
    static void resetCacheMutexLockCount();
    size_t getEstimatedBytes() const {
        return static_cast<size_t>(totalTaps) * 12 + static_cast<size_t>(numPartitions) * FFT_SIZE * 16;
    }
};

struct ReverbParamSet {
    int preset = 0;
    double wetDry = 0.20;
    double predelayMs = 0.0;
    double damping = 0.5;
    bool enabled = false;
    std::shared_ptr<const PreparedIr> preparedIr = nullptr;
};

struct PannerParamSet {
    double balance = 0.0; // -1.0 (Left) to +1.0 (Right)
    bool monoMix = false;
};

struct ResamplerParamSet {
    double inRate = 48000.0;
    double outRate = 48000.0;
    bool enabled = false;
};

struct DspParamSnapshot {
    uint64_t generation = 0;
    double sampleRate = 48000.0;
    bool resetRequested = false;
    uint32_t activeStages = 0xFFFFFFFF;
    EqParamSet eq;
    CrossfeedParamSet crossfeed;
    LimiterParamSet limiter;
    ReverbParamSet reverb;
    PannerParamSet panner;
    ResamplerParamSet resampler;
};
