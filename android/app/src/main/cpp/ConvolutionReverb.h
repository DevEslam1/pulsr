// android/app/src/main/cpp/ConvolutionReverb.h
#pragma once

#include "DspParams.h"
#include "FftUtil.h"
#include "SincResampler.h"
#include <vector>
#include <cmath>
#include <memory>
#include <string>
#include <atomic>
#include <thread>
#include <condition_variable>

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

enum class ReverbThreadingMode {
    SingleThread = 0,
    MultiThread = 1,
    Auto = 2
};

class ConvolutionReverb {
public:
    static constexpr int PARTITION_SIZE = 512;
    static constexpr int FFT_SIZE = PARTITION_SIZE * 2; // 1024
    static constexpr int MAX_PREDELAY_SAMPLES = 153600; // 153,600 samples max predelay capacity (R2)
    static constexpr int MAX_PREALLOC_PARTITIONS = 512;

    ConvolutionReverb();
    ~ConvolutionReverb();
    void setSampleRate(double sampleRate, bool updateIr = true);
    void setPreset(ReverbPreset preset);
    void setWetDry(double wet); // 0.0 (dry) to 1.0 (wet)
    void setPredelay(double predelayMs); // 0.0 to 150.0 ms
    void setDamping(double damping); // 0.0 (bright) to 1.0 (dark/damped)
    void setCrossChannel(double crossChannel) { crossChannel_ = std::clamp(crossChannel, 0.0, 1.0); }
    double getCrossChannel() const { return crossChannel_; }
    void setEnabled(bool enabled) {
        enabled_.store(enabled, std::memory_order_relaxed);
        targetEnabledMix_.store(enabled ? 1.0f : 0.0f, std::memory_order_release);
    }
    bool isEnabled() const {
        return targetEnabledMix_.load(std::memory_order_relaxed) > 1e-4f;
    }
    bool isRamping() const {
        return (smoothedEnabledMix_ > 1e-4f) || (targetEnabledMix_.load(std::memory_order_relaxed) > 1e-4f);
    }
    void setThreadingMode(ReverbThreadingMode mode) { threadingMode_.store(mode, std::memory_order_relaxed); }
    ReverbThreadingMode getThreadingMode() const { return threadingMode_.load(std::memory_order_relaxed); }
    void applyParams(const ReverbParamSet& params);
    void reset();

    bool loadCustomIR(const float* irInterleaved, int frames, int channels, double irSampleRate = 0.0);
    std::shared_ptr<const PreparedIr> getPreparedIr() const { return preparedIr_; }
    ReverbPreset getPreset() const { return preset_; }

    int getReverbLatencyFrames() const {
        if (!isEnabled()) return 0;
        return reverbLatencyFrames_.load(std::memory_order_relaxed);
    }

    void prepareForBlockSize(int maxFrames);
    void process(const float* inL, const float* inR, float* outL, float* outR, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    void drainRetiredIrs();

private:
    static constexpr int kMaxRetired = 256;
    std::shared_ptr<const PreparedIr> retiredRing_[kMaxRetired];
    std::atomic<int> retiredHead_{0};
    std::atomic<int> retiredTail_{0};
    static constexpr int kMaxEmergencyOverflow = 256;
    std::shared_ptr<const PreparedIr> overflowSlots_[kMaxEmergencyOverflow];
    std::atomic<int> overflowCount_{0};

    void updatePreparedIr();
    void setPreparedIrPtr(std::shared_ptr<const PreparedIr> ir);
    void preparePartitions();
    void ensurePredelayCapacity();
    void ensureScratchCapacity(int frames);
    void processCore(const float* inL, const float* inR, float* outL, float* outR, int frames,
                     float startMix, float mixStep, double startWet, double wetStep);

    double sampleRate_ = 48000.0;
    double coreRate_ = 48000.0;
    ReverbPreset preset_ = ReverbPreset::Room;
    double targetWet_ = 0.20;
    double smoothedWet_ = 0.20;
    double predelayMs_ = 0.0;
    float targetPredelaySamples_ = 0.0f;
    float smoothedPredelaySamples_ = 0.0f;
    double damping_ = 0.5;
    std::atomic<bool> enabled_{false};
    std::atomic<float> targetEnabledMix_{0.0f};
    float smoothedEnabledMix_{0.0f};
    int irCrossfadeSamples_{0};
    int irCrossfadeTotal_{0};
    std::atomic<ReverbThreadingMode> threadingMode_{ReverbThreadingMode::Auto};

    // Fixed-rate wet path resamplers for sample rates > 48kHz
    SincResampler wetInResampler_;
    SincResampler wetOutResampler_;
    std::vector<float> resampleInL_;
    std::vector<float> resampleInR_;
    std::vector<float> resampleWetL_;
    std::vector<float> resampleWetR_;
    std::vector<float> resampleOutL_;
    std::vector<float> resampleOutR_;

    // Prepared IR snapshot pointer
    std::shared_ptr<const PreparedIr> preparedIr_;

    // Latency of the currently prepared IR, mirrored to an atomic so the
    // control-thread latency query never races the audio-thread IR swap.
    std::atomic<int> reverbLatencyFrames_{0};

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

    // Dry-path delay line (PARTITION_SIZE) used in partitioned mode to time-align dry with wet
    std::vector<float> dryDelayL_;
    std::vector<float> dryDelayR_;
    int dryDelayPos_ = 0;


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

    // Cached raw custom IR for rate resynchronization
    std::vector<float> rawCustomIr_;
    int rawCustomFrames_ = 0;
    int rawCustomChannels_ = 2;
    double rawCustomSampleRate_ = 48000.0;
    double crossChannel_ = 0.0;

    void processLeftChannelPartition(int numPartitions);
    void processRightChannelPartition(int numPartitions);
    void workerLoop();

    std::thread workerThread_;
    std::mutex workerMutex_;
    std::condition_variable workerCv_;
    std::mutex workerDoneMutex_;
    std::condition_variable workerCvDone_;
    std::atomic<bool> workerRunning_{false};
    std::atomic<bool> workerJobReady_{false};
    std::atomic<bool> workerJobDone_{false};
    std::atomic<int> workerNumPartitions_{0};
};
