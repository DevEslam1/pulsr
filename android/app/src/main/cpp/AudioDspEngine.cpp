// android/app/src/main/cpp/AudioDspEngine.cpp
#include "AudioDspEngine.h"
#include <algorithm>
#include <cmath>
#include <thread>

AudioDspEngine& AudioDspEngine::instance() {
    static AudioDspEngine sInstance;
    return sInstance;
}

AudioDspEngine::AudioDspEngine() {
    auto initialSnapshot = std::make_shared<DspParamSnapshot>();
    initialSnapshot->generation = 1;
    initialSnapshot->sampleRate = 48000.0;
    initialSnapshot->activeStages = 0xFFFFFFFF;
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(initialSnapshot));
    setSampleRateInternal(48000.0);
}

void AudioDspEngine::setSampleRateInternal(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;

    eq_.setSampleRate(sampleRate_);
    crossfeed_.setSampleRate(sampleRate_);
    limiter_.setSampleRate(sampleRate_);
    resampler_.setRates(sampleRate_, sampleRate_);
}

void AudioDspEngine::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;

    // A1 (N-01): Bounded retry (max 2 attempts) to prewarm outside the lock.
    // If snapshot mutated while prewarming (e.g. preset/damping changed), release lock and
    // re-prewarm for the new parameters at the new sample rate.
    // On second conflict, publish without an IR swap and schedule one async re-prewarm.
    for (int attempt = 0; attempt < 2; ++attempt) {
        auto initial = currentParams_.load();
        const bool wasCustom = (initial->reverb.preset == static_cast<int>(ReverbPreset::Custom));
        std::shared_ptr<const PreparedIr> prewarmedIr = nullptr;
        if (!wasCustom) {
            prewarmedIr = PreparedIr::createSynthetic(
                sampleRate,
                initial->reverb.preset,
                static_cast<float>(initial->reverb.damping));
        } else {
            prewarmedIr = initial->reverb.preparedIr;
        }

        std::unique_lock<std::mutex> lock(publishMutex_);
        auto current = currentParams_.load();
        const bool nowCustom = (current->reverb.preset == static_cast<int>(ReverbPreset::Custom));

        if (!nowCustom && current != initial &&
            (current->reverb.preset != initial->reverb.preset ||
             std::abs(current->reverb.damping - initial->reverb.damping) > 1e-9)) {
            if (attempt == 0) {
                // First conflict: unlock and re-prewarm with the new reverb params
                lock.unlock();
                continue;
            } else {
                // Second conflict: publish preserving current IR and schedule one async re-prewarm
                const int targetPreset = current->reverb.preset;
                const double targetDamping = current->reverb.damping;
                auto updated = std::make_shared<DspParamSnapshot>(*current);
                updated->generation = ++snapshotGeneration_;
                updated->sampleRate = sampleRate;
                updated->reverb.preparedIr = current->reverb.preparedIr;
                currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
                lock.unlock();

                std::thread([this, sampleRate, targetPreset, targetDamping]() {
                    auto asyncIr = PreparedIr::createSynthetic(sampleRate, targetPreset, static_cast<float>(targetDamping));
                    if (asyncIr) {
                        std::lock_guard<std::mutex> asyncLock(publishMutex_);
                        auto latest = currentParams_.load();
                        if (latest && latest->sampleRate == sampleRate &&
                            latest->reverb.preset == targetPreset &&
                            std::abs(latest->reverb.damping - targetDamping) < 1e-9) {
                            auto newSnap = std::make_shared<DspParamSnapshot>(*latest);
                            newSnap->generation = ++snapshotGeneration_;
                            newSnap->reverb.preparedIr = asyncIr;
                            currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(newSnap));
                        }
                    }
                }).detach();
                return;
            }
        }

        if (nowCustom) {
            prewarmedIr = current->reverb.preparedIr;
        }

        auto updated = std::make_shared<DspParamSnapshot>(*current);
        updated->generation = ++snapshotGeneration_;
        updated->sampleRate = sampleRate;
        updated->reverb.preparedIr = prewarmedIr;
        currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
        return;
    }
}

void AudioDspEngine::resyncForTrack(double sampleRate, int channels) {
    (void)channels;
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;

    for (int attempt = 0; attempt < 2; ++attempt) {
        auto initial = currentParams_.load();
        const bool wasCustom = (initial->reverb.preset == static_cast<int>(ReverbPreset::Custom));
        std::shared_ptr<const PreparedIr> prewarmedIr = nullptr;
        if (!wasCustom && initial->reverb.enabled) {
            prewarmedIr = PreparedIr::createSynthetic(
                sampleRate,
                initial->reverb.preset,
                static_cast<float>(initial->reverb.damping));
        } else if (wasCustom) {
            prewarmedIr = initial->reverb.preparedIr;
        }

        std::unique_lock<std::mutex> lock(publishMutex_);
        auto current = currentParams_.load();
        const bool nowCustom = (current->reverb.preset == static_cast<int>(ReverbPreset::Custom));

        if (!nowCustom && current->reverb.enabled && current != initial &&
            (current->reverb.preset != initial->reverb.preset ||
             std::abs(current->reverb.damping - initial->reverb.damping) > 1e-9 ||
             current->reverb.enabled != initial->reverb.enabled)) {
            if (attempt == 0) {
                // First conflict: release lock and re-prewarm with the new parameters
                lock.unlock();
                continue;
            } else {
                // Second conflict: install current IR and schedule one async re-prewarm
                const int targetPreset = current->reverb.preset;
                const double targetDamping = current->reverb.damping;
                auto updated = std::make_shared<DspParamSnapshot>(*current);
                updated->generation = ++snapshotGeneration_;
                updated->sampleRate = sampleRate;
                updated->resetRequested = false;
                updated->reverb.preparedIr = current->reverb.preparedIr;
                currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
                lock.unlock();

                std::thread([this, sampleRate, targetPreset, targetDamping]() {
                    auto asyncIr = PreparedIr::createSynthetic(sampleRate, targetPreset, static_cast<float>(targetDamping));
                    if (asyncIr) {
                        std::lock_guard<std::mutex> asyncLock(publishMutex_);
                        auto latest = currentParams_.load();
                        if (latest && latest->sampleRate == sampleRate &&
                            latest->reverb.preset == targetPreset &&
                            std::abs(latest->reverb.damping - targetDamping) < 1e-9) {
                            auto newSnap = std::make_shared<DspParamSnapshot>(*latest);
                            newSnap->generation = ++snapshotGeneration_;
                            newSnap->reverb.preparedIr = asyncIr;
                            currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(newSnap));
                        }
                    }
                }).detach();
                return;
            }
        }

        if (nowCustom) {
            prewarmedIr = current->reverb.preparedIr;
        } else if (!current->reverb.enabled) {
            prewarmedIr = nullptr;
        }

        auto updated = std::make_shared<DspParamSnapshot>(*current);
        updated->generation = ++snapshotGeneration_;
        updated->sampleRate = sampleRate;
        updated->resetRequested = false; // Do not wipe filter state on seamless track resync

        if (current->reverb.enabled) {
            updated->reverb.preparedIr = prewarmedIr;
        }

        currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
        return;
    }
}

void AudioDspEngine::setActiveStages(uint32_t bitmask) {
    std::lock_guard<std::mutex> lock(publishMutex_);
    auto current = currentParams_.load();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->generation = ++snapshotGeneration_;
    updated->activeStages = bitmask;
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
}

uint32_t AudioDspEngine::getActiveStages() const {
    auto snapshot = getParams();
    return snapshot ? snapshot->activeStages : 0xFFFFFFFF;
}

void AudioDspEngine::publishParams(std::shared_ptr<const DspParamSnapshot> snapshot) {
    if (!snapshot) return;
    std::lock_guard<std::mutex> lock(publishMutex_);
    if (snapshot->generation <= lastAppliedGeneration_.load()) {
        auto mutableSnap = std::make_shared<DspParamSnapshot>(*snapshot);
        mutableSnap->generation = ++snapshotGeneration_;
        currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(mutableSnap));
    } else {
        snapshotGeneration_.store(snapshot->generation);
        currentParams_.store(snapshot);
    }
}

std::shared_ptr<const DspParamSnapshot> AudioDspEngine::getParams() const {
    return currentParams_.load();
}

void AudioDspEngine::resetInternal() {
    eq_.reset();
    crossfeed_.reset();
    limiter_.reset();
    reverb_.reset();
    resampler_.reset();
    panner_.reset();
    dsdDecoder_.reset();
}

void AudioDspEngine::reset() {
    std::lock_guard<std::mutex> lock(publishMutex_);
    auto current = currentParams_.load();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->generation = ++snapshotGeneration_;
    updated->resetRequested = true;
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
}

int AudioDspEngine::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels <= 0) return frames;

    const auto blockStart = std::chrono::steady_clock::now();

    // Load parameter snapshot atomically ONCE per processing block
    auto snapshot = currentParams_.load();
    if (!snapshot) return frames;

    // Fast check: generation counter skips applyParams entirely when unchanged
    if (snapshot->generation != lastAppliedGeneration_.load()) {
        if (snapshot->resetRequested) {
            resetInternal();
        }

        reverb_.applyParams(snapshot->reverb);
        if (std::abs(snapshot->sampleRate - sampleRate_) > 0.5) {
            setSampleRateInternal(snapshot->sampleRate);
            reverb_.setSampleRate(snapshot->sampleRate);
        }

        eq_.applyParams(snapshot->eq);
        panner_.applyParams(snapshot->panner);
        crossfeed_.applyParams(snapshot->crossfeed);
        resampler_.applyParams(snapshot->resampler);
        limiter_.applyParams(snapshot->limiter);

        lastAppliedGeneration_.store(snapshot->generation);
    }

    const uint32_t rawStages = snapshot->activeStages;
    const uint32_t degraded = autoDegradedStages_.load();
    const uint32_t stages = rawStages & ~degraded;
    if (stages != 0) {
        // 1. Parametric EQ Stage
        if (stages & STAGE_EQ) {
            eq_.processInterleaved(buffer, frames, channels);
        }

        // 2. Spatial Panner & Balance (All channels) — positioner before reverb for natural acoustics
        if (stages & STAGE_PANNER) {
            panner_.processInterleaved(buffer, frames, channels);
        }

        // 3. Crossfeed Stage (Stereo only)
        if ((stages & STAGE_CROSSFEED) && channels == 2) {
            crossfeed_.processInterleaved(buffer, frames);
        }

        // 4. Convolution Reverb Stage (Stereo only)
        if ((stages & STAGE_REVERB) && channels == 2) {
            reverb_.processInterleaved(buffer, frames, channels);
        }

        // 5. Polyphase Sinc Resampler (Fixed-frame streaming contract)
        if ((stages & STAGE_RESAMPLER) && std::abs(resampler_.getRatio() - 1.0) > 1e-5) {
            resampler_.processInterleaved(buffer, frames, channels);
        }

        // 6. Lookahead Limiter Stage (Multichannel / stereo / mono) — true-peak limiter is final
        if (stages & STAGE_LIMITER) {
            limiter_.processInterleaved(buffer, frames, channels);
        }
    }

    // In-Engine RTF Nervous System Monitor (Signal-safe, Zero allocation, Zero mutex locks)
    if (autoDegradeMonitorEnabled_.load(std::memory_order_relaxed)) {
        double blockRtf = 0.0;
        const double simRtf = simulatedBlockRtf_.load(std::memory_order_relaxed);
        if (simRtf >= 0.0) {
            blockRtf = simRtf;
        } else {
            const auto blockEnd = std::chrono::steady_clock::now();
            const double elapsedSec = std::chrono::duration<double>(blockEnd - blockStart).count();
            const double budgetSec = static_cast<double>(frames) / sampleRate_;
            if (budgetSec > 1e-9) {
                blockRtf = elapsedSec / budgetSec;
            }
        }

        rtfRingBuffer_[rtfRingHead_] = static_cast<float>(blockRtf);
        rtfRingHead_ = (rtfRingHead_ + 1) % kRtfWindowSize;
        if (rtfCount_ < kRtfWindowSize) {
            rtfCount_++;
        }

        if (rtfCount_ >= kRtfWindowSize) {
            float sum = 0.0f;
            for (int i = 0; i < kRtfWindowSize; ++i) {
                sum += rtfRingBuffer_[i];
            }
            const float avgRtf = sum / static_cast<float>(kRtfWindowSize);
            rollingRtf_.store(avgRtf, std::memory_order_relaxed);

            const uint32_t currentDegraded = autoDegradedStages_.load(std::memory_order_relaxed);

            // Sustained high load (RTF > 0.80 over window): degrade ONE stage at a time in cost order
            if (avgRtf > 0.80f) {
                recoveryConsecutiveBlocks_ = 0;
                // Cost order: REVERB -> CROSSFEED -> PANNER -> EQ
                if ((rawStages & STAGE_REVERB) && !(currentDegraded & STAGE_REVERB)) {
                    triggerStageAutoDegrade(STAGE_REVERB);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_CROSSFEED) && !(currentDegraded & STAGE_CROSSFEED)) {
                    triggerStageAutoDegrade(STAGE_CROSSFEED);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_PANNER) && !(currentDegraded & STAGE_PANNER)) {
                    triggerStageAutoDegrade(STAGE_PANNER);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_EQ) && !(currentDegraded & STAGE_EQ)) {
                    triggerStageAutoDegrade(STAGE_EQ);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if (avgRtf > 1.0f && (rawStages & STAGE_LIMITER) && !(currentDegraded & STAGE_LIMITER)) {
                    // NEVER auto-degrade limiter unless RTF > 1.0 persists across all other degraded stages
                    triggerStageAutoDegrade(STAGE_LIMITER);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                }
            } else if (avgRtf < 0.50f && currentDegraded != 0) {
                // Recovery: sustained low load (RTF < 0.50) over kRtfRecoveryWindowSize blocks
                recoveryConsecutiveBlocks_++;
                if (recoveryConsecutiveBlocks_ >= kRtfRecoveryWindowSize) {
                    recoveryConsecutiveBlocks_ = 0;
                    // Reverse cost order: EQ -> PANNER -> CROSSFEED -> REVERB -> LIMITER
                    if (currentDegraded & STAGE_EQ) {
                        recoverStageAutoDegrade(STAGE_EQ);
                    } else if (currentDegraded & STAGE_PANNER) {
                        recoverStageAutoDegrade(STAGE_PANNER);
                    } else if (currentDegraded & STAGE_CROSSFEED) {
                        recoverStageAutoDegrade(STAGE_CROSSFEED);
                    } else if (currentDegraded & STAGE_REVERB) {
                        recoverStageAutoDegrade(STAGE_REVERB);
                    } else if (currentDegraded & STAGE_LIMITER) {
                        recoverStageAutoDegrade(STAGE_LIMITER);
                    }
                }
            } else {
                recoveryConsecutiveBlocks_ = 0;
            }
        }
    }

    return frames;
}
