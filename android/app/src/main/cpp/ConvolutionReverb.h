// android/app/src/main/cpp/ConvolutionReverb.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"
#include <vector>
#include <cmath>
#include <memory>
#include <string>

enum class ReverbPreset {
    Studio = 0,
    Room = 1,
    Chamber = 2,
    Hall = 3,
    ConcertHall = 4,
    Cathedral = 5,
    Plate = 6,
    Spring = 7,
    Custom = 8
};

class ConvolutionReverb {
public:
    static constexpr int PARTITION_SIZE = 512;
    static constexpr int FFT_SIZE = PARTITION_SIZE * 2; // 1024
    static constexpr int MAX_PREDELAY_SAMPLES = 153600; // 153,600 samples max predelay capacity (R2)
    static constexpr int MAX_PREALLOC_PARTITIONS = 4096;

    ConvolutionReverb();
    void setSampleRate(double sampleRate);
    void setPreset(ReverbPreset preset);
    void setWetDry(double wet); // 0.0 (dry) to 1.0 (wet)
    void setPredelay(double predelayMs); // 0.0 to 150.0 ms
    void setDamping(double damping); // 0.0 (bright) to 1.0 (dark/damped)
    void setEnabled(bool enabled);
    bool isEnabled() const { return enabled_; }
    void applyParams(const ReverbParamSet& params);
    void reset();

    bool loadCustomIR(const float* irInterleaved, int frames, int channels);
    std::shared_ptr<const PreparedIr> getPreparedIr() const { return preparedIr_; }
    ReverbPreset getPreset() const { return preset_; }

    // Reverb wet-path block latency: 512 samples in partitioned mode, 0 in direct FIR
    int getReverbLatencyFrames() const {
        if (!enabled_ || !preparedIr_) return 0;
        return (preparedIr_->numPartitions == 0) ? 0 : PARTITION_SIZE;
    }

    void process(const float* inL, const float* inR, float* outL, float* outR, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    void updatePreparedIr();
    void preparePartitions();
    void ensurePredelayCapacity();
    void ensureScratchCapacity(int frames);

    double sampleRate_ = 48000.0;
    ReverbPreset preset_ = ReverbPreset::Room;
    double targetWet_ = 0.20;
    double smoothedWet_ = 0.20;
    double predelayMs_ = 0.0;
    float targetPredelaySamples_ = 0.0f;
    float smoothedPredelaySamples_ = 0.0f;
    double damping_ = 0.5;
    bool enabled_ = false;

    // Prepared IR snapshot pointer
    std::shared_ptr<const PreparedIr> preparedIr_;

    // Overlap-save previous block history (P samples)
    std::vector<float> prevBlockL_;
    std::vector<float> prevBlockR_;

    // Current input block (P samples)
    std::vector<float> inputBlockL_;
    std::vector<float> inputBlockR_;
    int inputBlockPos_ = 0;

    // Overlap-save input history ring buffer: [numPartitions][FFT_SIZE]
    std::vector<std::vector<FftUtil::Complex>> inputHistoryFreqL_;
    std::vector<std::vector<FftUtil::Complex>> inputHistoryFreqR_;
    int historyHead_ = 0;

    // Direct convolution ring buffers for short IRs (<= 1024)
    std::vector<float> directRingL_;
    std::vector<float> directRingR_;
    int directPos_ = 0;

    // Predelay circular buffer
    std::vector<float> predelayRingL_;
    std::vector<float> predelayRingR_;
    int predelayWritePos_ = 0;

    // Working buffers
    std::vector<FftUtil::Complex> fftWorkL_;
    std::vector<FftUtil::Complex> fftWorkR_;
    std::vector<FftUtil::Complex> accumFreqL_;
    std::vector<FftUtil::Complex> accumFreqR_;

    // Scratch buffers for allocation-free processInterleaved
    std::vector<float> scratchInL_;
    std::vector<float> scratchInR_;
    std::vector<float> scratchOutL_;
    std::vector<float> scratchOutR_;
};
