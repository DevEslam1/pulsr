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
        double sampleRate, const float* irInterleaved, int frames, int channels, double targetRate = 48000.0);

    static size_t getSyntheticCacheBytes();
    static size_t getSyntheticCacheEntryCount();
    static void clearSyntheticCache();
    static void setCacheBudgetBytes(size_t budgetBytes);
    static size_t getCacheBudgetBytes();
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

struct SaturationParamSet {
    double drive = 0.0; // 0..1 (0 = linear/transparent)
    double mix = 0.5;   // 0..1 wet/dry blend
    double tilt = 0.0;  // 0..1 HF pre-emphasis into the shaper (tape-style)
    bool enabled = false;
};

struct StereoWidthParamSet {
    double width = 1.0; // 0 = mono, 1 = normal, up to 2 = widened
    bool enabled = false;
};

// Fletcher-Munson equal-loudness compensation. `volumeLinear` is the current
// playback volume-stage value (0..1) pushed from Dart; the contour lift scales
// with (1 - volume) so a full-volume signal gets zero compensation.
struct LoudnessContourParamSet {
    double intensity = 0.0;    // 0..1
    double volumeLinear = 1.0; // current volume-stage value
    bool enabled = false;
};

// Subwoofer / LFE crossover. NOTE: the current pipeline is stereo-only, so this
// is implemented as bass-management *redirection* — a Linkwitz-Riley-style
// low-passed mono sum added back into both channels at `subGain`. Mains keep
// full range (no high-pass); this is NOT true multichannel LFE routing.
struct SubCrossoverParamSet {
    double cornerHz = 80.0;      // 60..150
    double slopeDbPerOct = 24.0; // 12 or 24 (Linkwitz-Riley 2/4)
    double subGain = 0.8;        // 0..1 gain of the redirected sub tap
    bool enabled = false;
};

struct DynamicEqBandParam {
    double frequency = 1000.0;
    double q = 2.0;
    double thresholdDb = -30.0; // band energy threshold
    double ratio = 3.0;         // compression above threshold
    double attackMs = 5.0;
    double releaseMs = 120.0;
    double maxCutDb = -12.0; // gain reduction ceiling (<= 0; cuts only)
    bool enabled = true;
};

struct DynamicEqParamSet {
    static constexpr int MAX_BANDS = 8;
    DynamicEqBandParam bands[MAX_BANDS];
    int bandCount = 1;
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
    SaturationParamSet saturation;
    StereoWidthParamSet stereoWidth;
    LoudnessContourParamSet loudness;
    SubCrossoverParamSet subCrossover;
    DynamicEqParamSet dynamicEq;
};
