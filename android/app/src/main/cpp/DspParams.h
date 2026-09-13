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
    static constexpr int MAX_BANDS = 64;
    EqBandParam bands[MAX_BANDS];
    int bandCount = 10;
    double preampDb = 0.0;
    bool enabled = true;
};

enum class CrossfeedMode {
    Bs2bDefault = 0,   // 700 Hz, 4.5 dB
    Bs2bChuMoy = 1,    // 700 Hz, 6.0 dB
    Bs2bJanMeier = 2,  // 650 Hz, 9.5 dB
    Custom = 3         // User-configured fcut, feedDb, delayUs
};

struct CrossfeedParamSet {
    CrossfeedMode mode = CrossfeedMode::Bs2bDefault;
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
        // Each partition holds FFT_SIZE complex<float> bins = 8 bytes each
        // (std::complex<float> is two floats), not 16.
        return static_cast<size_t>(totalTaps) * 12 + static_cast<size_t>(numPartitions) * FFT_SIZE * 8;
    }
};

struct ReverbParamSet {
    int preset = 0;
    double wetDry = 0.20;
    double predelayMs = 0.0;
    double damping = 0.5;
    double crossChannel = 0.0; // 0.0 to 1.0 (binaural crosstalk blend)
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
    // User-selectable resampler quality: 0 = Fast (linear interpolation),
    // 1 = Standard (16-tap polyphase), 2 = High (32-tap), 3 = Ultra (64-tap,
    // full table; the historical behaviour and default).
    int quality = 3;
};

struct SaturationParamSet {
    double drive = 0.0; // 0..1 (0 = linear/transparent)
    double mix = 0.5;   // 0..1 wet/dry blend
    double tilt = 0.0;  // 0..1 HF pre-emphasis into the shaper (tape-style)
    int mode = 0;       // 0 = Tape (odd harmonics), 1 = Tube (even+odd triode), 2 = Analog (Class-A)
    bool multiband = false; // true = 6-band crossover mid-band warmth mode (JamesDSP)
    bool enabled = false;
};

struct StereoWidthParamSet {
    double width = 1.0; // 0 = mono, 1 = normal, up to 2 = widened
    bool enabled = false;
    // 3-Band Multiband Stereo Imager with Bass Mono
    bool multiband = false;
    double lowWidth = 0.0;           // default 0.0 (Bass Mono)
    double midWidth = 1.0;           // 0..2
    double highWidth = 1.5;          // 0..2
    double lowCrossoverHz = 160.0;   // Low/Mid cutoff
    double highCrossoverHz = 4000.0; // Mid/High cutoff
};

// Fletcher-Munson equal-loudness compensation. `volumeLinear` is the current
// playback volume-stage value (0..1) pushed from Dart; the contour lift scales
// with (1 - volume) so a full-volume signal gets zero compensation.
struct LoudnessContourParamSet {
    double intensity = 0.0;    // 0..1
    double volumeLinear = 1.0; // current volume-stage value
    bool enabled = false;
};

// Subwoofer / LFE crossover & Bass Management
struct SubCrossoverParamSet {
    double cornerHz = 80.0;      // 60..150
    double slopeDbPerOct = 24.0; // 12 or 24 (Linkwitz-Riley 2/4)
    double subGain = 0.8;        // 0..1 gain of the redirected sub tap
    bool bassMono = true;        // collapse low-end below cornerHz to pure mono
    bool antiPop = true;         // soft-knee saturation on sub transients to protect voice coils
    bool enabled = false;
};

struct DynamicEqBandParam {
    double frequency = 1000.0;
    double q = 2.0;
    double thresholdDb = -30.0; // band energy threshold
    double ratio = 3.0;         // compression or expansion ratio above threshold
    double attackMs = 5.0;
    double releaseMs = 120.0;
    double maxCutDb = -12.0;    // gain reduction ceiling (<= 0)
    double maxBoostDb = 12.0;   // gain boost ceiling (>= 0)
    int mode = 0;               // 0 = Cut (Compress), 1 = Boost (Expand/Lift)
    int filterType = 0;         // 0 = Peaking, 1 = LowShelf, 2 = HighShelf
    bool enabled = true;
};

struct DynamicEqParamSet {
    static constexpr int MAX_BANDS = 8;
    DynamicEqBandParam bands[MAX_BANDS];
    int bandCount = 1;
    bool enabled = false;
};

struct MultibandBandParam {
    double thresholdDb = -18.0;   // -60.0 to 0.0 dB
    double ratio = 2.0;           // 1.0 (bypass) to 20.0 (limiting)
    double attackMs = 15.0;       // 0.1 to 200.0 ms
    double releaseMs = 100.0;     // 5.0 to 1000.0 ms
    double kneeDb = 3.0;          // 0.0 to 12.0 dB
    double makeupGainDb = 0.0;    // 0.0 to 24.0 dB
    bool enabled = true;
};

struct MultibandCompressorParamSet {
    static constexpr int NUM_BANDS = 4;
    MultibandBandParam bands[NUM_BANDS];
    double crossoverFreqs[NUM_BANDS - 1] = {150.0, 1000.0, 5000.0};
    bool enabled = false;
};

// ViPER-modeled Dynamic System / Dynamic Bass
struct DynamicBassParamSet {
    bool enabled = false;
    double strength = 1.0;
    int xLow = 100;
    int xHigh = 5600;
    int yLow = 40;
    int yHigh = 80;
    double sideGainLow = 0.10;
    double sideGainHigh = 0.50;
    int devicePreset = 0; // 0 = Custom, 1..9 = Presets
};


enum class ReplayGainMode {
    Off = 0,
    Track = 1,
    Album = 2
};

struct ReplayGainParamSet {
    ReplayGainMode mode = ReplayGainMode::Off;
    double trackGainDb = 0.0;
    double albumGainDb = 0.0;
    double trackPeak = 1.0;
    double albumPeak = 1.0;
    double preAmpDb = 0.0;
    bool preventClipping = true;
    bool enabled = false;
};

struct DitherParamSet {
    bool enabled = false;
    int targetBitDepth = 16;  // 16, 24, 32
    bool isBluetooth = false;
};

struct BitPerfectParamSet {
    bool enabled = false;
    bool isDop = false;
};

struct ViperDdcParamSet {
    bool enabled = false;
    std::string ddcContent; // Raw .vdc format text
    std::string profileName;
};

struct ArbitraryEqParamSet {
    bool enabled = false;
    std::string graphicEqString; // GraphicEq: 20 0; 100 2; ...
    bool linearPhase = false;
};

struct LiveProgParamSet {
    bool enabled = false;
    std::string code; // EEL script with @init and @sample
    double slider1 = 0.0;
    double slider2 = 0.0;
    double slider3 = 0.0;
    double slider4 = 0.0;
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
    MultibandCompressorParamSet multibandCompressor;
    DynamicBassParamSet dynamicBass;
    ReplayGainParamSet replayGain;
    DitherParamSet dither;
    BitPerfectParamSet bitPerfect;
    ViperDdcParamSet viperDdc;
    ArbitraryEqParamSet arbitraryEq;
    LiveProgParamSet liveProg;
};
