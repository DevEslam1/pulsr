// android/app/src/main/cpp/HrtfBinaural.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"

#include <vector>
#include <string>
#include <memory>
#include <atomic>
#include <mutex>
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

    /// §8.9: inverse-distance interpolation over the 4 nearest measurements on
    /// the SOFA grid instead of pure nearest-neighbour. Each neighbour IR is
    /// resampled from this dataset's sampleRate to targetSampleRate before it is
    /// weighted and accumulated, so a 44.1 kHz dataset convolved at 48 kHz no
    /// longer plays the wrong ITD/spectral spacing. outTaps is set to
    /// round(irLength * targetSampleRate / sampleRate), capped at maxTaps.
    /// Control-thread only: resizing the output vectors may allocate. Callers
    /// that must stay allocation-free (the HrtfBinaural slot prepare path)
    /// reserve MAX_HRIR_TAPS capacity beforehand.
    bool findInterpolatedHrir(double targetAzimuthDeg, double targetElevationDeg,
                              double targetSampleRate, int maxTaps,
                              std::vector<float>& outLeftEar,
                              std::vector<float>& outRightEar,
                              int& outTaps) const;
};

class HrtfBinaural {
public:
    static constexpr int MAX_HRIR_TAPS = 2048;
    static constexpr int DEFAULT_HRIR_TAPS = 128;

    // §8.9 ownership model (RT-allocation fix):
    // HrtfBinaural owns four fixed, fully preallocated HrirQuad slots. The
    // CONTROL thread prepares a quad into a free slot (never one the render
    // thread may be convolving) and publishes the slot index through
    // readySlot_. The RENDER thread claims the newest ready slot at a block
    // boundary, crossfades from its previous slot, and publishes active/old
    // indices so the writer never reuses a slot that is still being read.
    // At most three slots are referenced (active, crossfade source, pending),
    // so the writer always has a free slot even when playback is paused.
    // process()/processFrame() therefore never allocate, lock, free or log.
    static constexpr int kHrirSlotCount = 4;

    HrtfBinaural();
    ~HrtfBinaural();

    // Control-thread configuration. These prepare + publish a quad; they are
    // never called from the render thread any more.
    void setSampleRate(double sampleRate);
    void setAzimuth(double azimuthDeg); // -90.0 to +90.0 (virtual speaker angle, default 30.0)
    void setElevation(double elevationDeg); // -45.0 to +45.0 (default 0.0)

    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }
    bool isRamping() const {
        return (!enabled_.load(std::memory_order_relaxed) && smoothedEnabledMix_ >= 1e-4f) ||
               (enabled_.load(std::memory_order_relaxed) && smoothedEnabledMix_ < 0.9999f) ||
               (crossfadeProgress_ < 1.0f) ||
               (readySlot_.load(std::memory_order_acquire) >= 0);
    }

    double getAzimuth() const { return targetAzimuthDeg_.load(std::memory_order_relaxed); }
    double getElevation() const { return targetElevationDeg_.load(std::memory_order_relaxed); }
    double getEngineSampleRate() const { return engineSampleRate_.load(std::memory_order_relaxed); }

    int getLatencyFrames() const {
        return 0; // Direct FIR convolution without extra lookahead has 0 extra algorithmic latency
    }

    void reset();

    /// Control thread: prepares the interpolated/resampled quad for this
    /// geometry and engine rate, then publishes it. No-op when the request
    /// matches the last published quad. Returns false only when no slot could
    /// be acquired (render thread has been stalled) or a dataset rebuild failed.
    bool prepare(double azimuthDeg, double elevationDeg, double engineSampleRate);

    /// Render thread: claims the newest published quad slot, if any. Called
    /// once per block before processFrame(); allocation-, lock- and log-free.
    void applyPrepared();

    /// Loads a SOFA (NetCDF-3 classic binary) file from disk or memory.
    bool loadSofaFile(const std::string& path);
    bool loadSofaMemory(const uint8_t* data, size_t size);

    /// Restores the synthesized default HRIR (used when the user clears a
    /// custom SOFA dataset). Control thread; publishes a synthetic quad.
    bool clearDataset();
    bool hasDataset() const { return hasDataset_.load(std::memory_order_relaxed); }

    /// Control thread: adopts an immutable, already-parsed dataset (the value
    /// carried by DspParamSnapshot::hrtf.dataset). Passing nullptr restores the
    /// synthesized default only when the current source is a dataset; a loaded
    /// WAV/custom IR is left untouched. Does not publish a quad by itself —
    /// call prepare() afterwards.
    void setDataset(std::shared_ptr<const SofaDataset> dataset);
    std::shared_ptr<const SofaDataset> getDataset() const;

    /// Loads a 2-channel or 4-channel RIFF/WAVE HRIR file from disk or memory.
    bool loadWavHrir(const std::string& path);
    bool loadWavHrirMemory(const uint8_t* data, size_t size);

    /// Loads raw custom impulse response quad.
    bool loadCustomIr(const float* ll, const float* lr, const float* rl, const float* rr,
                      int taps, double irSampleRate);

    // Audio-thread processing: allocation-free, lock-free, log-free.
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

    /// Diagnostics/tests only: copies the quad currently convolved by the
    /// render thread. Allocates (vector copies); never call on the render
    /// thread. The active slot is not mutated by the control writer.
    bool copyActiveQuad(HrirQuad& out) const;

private:
    enum class IrSource { Synthetic, Dataset, Custom };

    std::atomic<double> engineSampleRate_{48000.0};
    std::atomic<bool> enabled_{false};
    std::atomic<bool> hasDataset_{false};
    float smoothedEnabledMix_ = 0.0f;

    std::atomic<double> targetAzimuthDeg_{30.0};
    std::atomic<double> targetElevationDeg_{0.0};

    // Preallocated immutable-handoff slots (see kHrirSlotCount ownership note).
    HrirQuad slots_[kHrirSlotCount];
    std::atomic<int> readySlot_{-1};
    std::atomic<int> activeSlotAtomic_{-1};
    std::atomic<int> oldSlotAtomic_{-1};

    // Render-thread mirrors of the slot indices. Written only by the render
    // thread (applyPrepared / processFrame).
    int activeSlot_ = -1;
    int oldSlot_ = -1;
    float crossfadeProgress_ = 1.0f;

    // Control-thread-only state. Serializes the single writer so two platform
    // calls (slider + SOFA load) cannot race the slot handoff.
    mutable std::mutex prepareMutex_;
    std::shared_ptr<const SofaDataset> dataset_;
    HrirQuad customIrSource_;
    IrSource source_ = IrSource::Synthetic;
    bool hasPublished_ = false;
    double lastPreparedAzimuthDeg_ = 0.0;
    double lastPreparedElevationDeg_ = 0.0;
    double lastPreparedSampleRate_ = 0.0;

    // Doubled circular history buffer for zero-copy contiguous FIR reads
    float historyL_[MAX_HRIR_TAPS * 2] = {};
    float historyR_[MAX_HRIR_TAPS * 2] = {};
    int historyIdx_ = 0;

    bool prepareLocked(double azimuthDeg, double elevationDeg, double engineSampleRate);
    bool acquireFreeSlotLocked(int& outSlot);
    bool buildQuadLocked(int slot, double azimuthDeg, double elevationDeg,
                         double engineSampleRate);
    void publishSlotLocked(int slot);

    inline void processFrame(float inL, float inR, float& outL, float& outR,
                             float currentEnabledMix, float crossfadeStep,
                             const HrirQuad* qNew, const HrirQuad* qOld);
};

} // namespace pulsr
