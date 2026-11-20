// android/app/src/main/cpp/HrtfBinaural.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"

#include <vector>
#include <string>
#include <memory>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace pulsr {

struct HrirQuad {
    // 4 impulse responses for stereo binauralization:
    // Left channel -> Left ear (hLL) and Right ear (hLR)
    // Right channel -> Left ear (hRL) and Right ear (hRR)
    std::vector<float> hLL;
    std::vector<float> hLR;
    std::vector<float> hRL;
    std::vector<float> hRR;
    int taps = 128;
    double sampleRate = 48000.0;
    double azimuthDeg = 30.0;
    double elevationDeg = 0.0;
};

struct SofaDataset {
    std::string title;
    double sampleRate = 48000.0;
    int numMeasurements = 0;
    int numReceivers = 2; // R=2 (0=Left ear, 1=Right ear)
    int irLength = 0;
    std::vector<double> azimuths;   // degrees [-180..180] or [0..360]
    std::vector<double> elevations; // degrees [-90..90]
    std::vector<float> irData;      // [numMeasurements * 2 * irLength]

    bool findNearestHrir(double targetAzimuthDeg, double targetElevationDeg,
                         std::vector<float>& outLeftEar,
                         std::vector<float>& outRightEar) const;
};

class HrtfBinaural {
public:
    static constexpr int MAX_HRIR_TAPS = 2048;
    static constexpr int DEFAULT_HRIR_TAPS = 128;

    HrtfBinaural();
    ~HrtfBinaural();

    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }
    bool isRamping() const {
        return (!enabled_.load(std::memory_order_relaxed) && smoothedEnabledMix_ >= 1e-4f) ||
               (enabled_.load(std::memory_order_relaxed) && smoothedEnabledMix_ < 0.9999f) ||
               (crossfadeProgress_ < 1.0f);
    }

    void setAzimuth(double azimuthDeg); // -90.0 to +90.0 (virtual speaker angle, default 30.0)
    double getAzimuth() const { return targetAzimuthDeg_; }
    void setElevation(double elevationDeg); // -45.0 to +45.0 (default 0.0)
    double getElevation() const { return targetElevationDeg_; }

    int getLatencyFrames() const {
        return 0; // Direct FIR convolution without extra lookahead has 0 extra algorithmic latency
    }

    void reset();

    /// Loads a SOFA (NetCDF-3 classic binary) file from disk or memory.
    bool loadSofaFile(const std::string& path);
    bool loadSofaMemory(const uint8_t* data, size_t size);

    /// Loads a 2-channel or 4-channel RIFF/WAVE HRIR file from disk or memory.
    bool loadWavHrir(const std::string& path);
    bool loadWavHrirMemory(const uint8_t* data, size_t size);

    /// Loads raw custom impulse response quad.
    bool loadCustomIr(const float* ll, const float* lr, const float* rl, const float* rr,
                      int taps, double irSampleRate);

    // Audio-thread processing: allocation-free, lock-free.
    void process(const float* inL, const float* inR, float* outL, float* outR, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    // Parser functions (testable standalone)
    static bool parseSofaNetCdf3(const uint8_t* data, size_t size, SofaDataset& outDataset);
    static bool parseWavHrir(const uint8_t* data, size_t size,
                             std::vector<float>& outL, std::vector<float>& outR,
                             int& outChannels, double& outSampleRate);

    // Default HRIR synthesizer (anechoic head-shadow + pinna ITD/ILD model)
    static HrirQuad synthesizeDefaultHrir(double azimuthDeg, double elevationDeg,
                                          double sampleRate = 48000.0,
                                          int taps = DEFAULT_HRIR_TAPS);

private:
    double sampleRate_ = 48000.0;
    std::atomic<bool> enabled_{false};
    float smoothedEnabledMix_ = 0.0f;

    double targetAzimuthDeg_ = 30.0;
    double targetElevationDeg_ = 0.0;

    // Prepared quad pointers for atomic swap
    std::shared_ptr<const HrirQuad> activeQuad_;
    std::shared_ptr<const HrirQuad> oldQuad_;
    float crossfadeProgress_ = 1.0f;

    // Active loaded SOFA dataset (if any)
    std::shared_ptr<const SofaDataset> sofaDataset_;

    // Doubled circular history buffer for zero-copy contiguous FIR reads
    float historyL_[MAX_HRIR_TAPS * 2] = {};
    float historyR_[MAX_HRIR_TAPS * 2] = {};
    int historyIdx_ = 0;

    void updateHrirQuad();
    inline void processFrame(float inL, float inR, float& outL, float& outR,
                             float currentEnabledMix, float crossfadeStep);
};

} // namespace pulsr
