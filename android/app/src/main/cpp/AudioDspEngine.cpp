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
    saturation_.setSampleRate(sampleRate_);
    loudnessContour_.setSampleRate(sampleRate_);
    subCrossover_.setSampleRate(sampleRate_);
    dynamicEq_.setSampleRate(sampleRate_);
}

void AudioDspEngine::applySampleRateLocked(double sampleRate) {
    auto current = currentParams_.load();
    const bool wasCustom = (current->reverb.preset == static_cast<int>(ReverbPreset::Custom));
    std::shared_ptr<const PreparedIr> prewarmedIr = nullptr;
    if (!wasCustom && current->reverb.enabled) {
        prewarmedIr = PreparedIr::createSynthetic(
            sampleRate,
            current->reverb.preset,
            static_cast<float>(current->reverb.damping));
    } else {
        prewarmedIr = current->reverb.preparedIr;
    }

    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->generation = ++snapshotGeneration_;
    updated->sampleRate = sampleRate;
    updated->resetRequested = false; // Never wipe state on rate transitions
    if (current->reverb.enabled && prewarmedIr) {
        updated->reverb.preparedIr = prewarmedIr;
    }
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
}

void AudioDspEngine::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;

    std::unique_lock<std::mutex> lock(publishMutex_);
    applySampleRateLocked(sampleRate);
}

void AudioDspEngine::resyncForTrack(double sampleRate, int channels) {
    (void)channels;
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;

    std::unique_lock<std::mutex> lock(publishMutex_);
    applySampleRateLocked(sampleRate);
}

void AudioDspEngine::updateParams(SnapshotMutator mutator) {
    if (!mutator) return;
    std::lock_guard<std::mutex> lock(publishMutex_);
    auto current = currentParams_.load();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->resetRequested = false; // Clear reset by default so reset() only fires once
    mutator(*updated);
    updated->generation = ++snapshotGeneration_;
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(updated));
}

void AudioDspEngine::setActiveStages(uint32_t bitmask) {
    updateParams([bitmask](DspParamSnapshot& snap) {
        snap.activeStages = bitmask;
    });
}

uint32_t AudioDspEngine::getActiveStages() const {
    auto snapshot = getParams();
    return snapshot ? snapshot->activeStages : 0xFFFFFFFF;
}

void AudioDspEngine::publishParams(std::shared_ptr<const DspParamSnapshot> snapshot) {
    if (!snapshot) return;
    std::lock_guard<std::mutex> lock(publishMutex_);
    auto mutableSnap = std::make_shared<DspParamSnapshot>(*snapshot);
    mutableSnap->generation = ++snapshotGeneration_;
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(mutableSnap));
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
    saturation_.reset();
    stereoWidth_.reset();
    loudnessContour_.reset();
    subCrossover_.reset();
    dynamicEq_.reset();
}

void AudioDspEngine::reset() {
    updateParams([](DspParamSnapshot& snap) {
        snap.resetRequested = true;
    });
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
            sampleRate_ = snapshot->sampleRate;
            eq_.setSampleRate(sampleRate_);
            crossfeed_.setSampleRate(sampleRate_);
            limiter_.setSampleRate(sampleRate_);
            saturation_.setSampleRate(sampleRate_);
            loudnessContour_.setSampleRate(sampleRate_);
            subCrossover_.setSampleRate(sampleRate_);
            dynamicEq_.setSampleRate(sampleRate_);
        }

        eq_.applyParams(snapshot->eq);
        panner_.applyParams(snapshot->panner);
        crossfeed_.applyParams(snapshot->crossfeed);
        limiter_.applyParams(snapshot->limiter);
        saturation_.applyParams(snapshot->saturation);
        stereoWidth_.applyParams(snapshot->stereoWidth);
        loudnessContour_.applyParams(snapshot->loudness);
        subCrossover_.applyParams(snapshot->subCrossover);
        dynamicEq_.applyParams(snapshot->dynamicEq);

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

        // 2. Dynamic EQ Stage — adjacent to the parametric EQ so band energy
        //    is detected on the tonally-shaped (but not yet spatialized) signal
        if (stages & STAGE_DYNEQ) {
            dynamicEq_.processInterleaved(buffer, frames, channels);
        }

        // 3. Spatial Panner & Balance (All channels) — positioner before reverb for natural acoustics
        if (stages & STAGE_PANNER) {
            panner_.processInterleaved(buffer, frames, channels);
        }

        // 4. Crossfeed Stage (Stereo only)
        if ((stages & STAGE_CROSSFEED) && channels == 2) {
            crossfeed_.processInterleaved(buffer, frames);
        }

        // 5. Convolution Reverb Stage (Stereo only)
        if ((stages & STAGE_REVERB) && channels == 2) {
            reverb_.processInterleaved(buffer, frames, channels);
        }

        // 6. Harmonic Saturation / Exciter Stage — after tonal + spatial shaping,
        //    before the limiter, so added harmonics stay under peak control
        if (stages & STAGE_SATURATION) {
            saturation_.processInterleaved(buffer, frames, channels);
        }

        // 7. Stereo Width Stage (M/S, stereo only) — after crossfeed/reverb so
        //    the widened field is not re-collapsed by later spatial stages
        if ((stages & STAGE_WIDTH) && channels == 2) {
            stereoWidth_.processInterleaved(buffer, frames, channels);
        }

        // 8. Subwoofer / LFE Crossover Stage (bass redirection sum, stereo pairs)
        if (stages & STAGE_CROSSOVER) {
            subCrossover_.processInterleaved(buffer, frames, channels);
        }

        // 9. Loudness Contour Stage — computed against the current volume-stage
        //    value (pushed from Dart). Applied pre-limiter so the limiter still
        //    guards the contour-boosted peaks.
        if (stages & STAGE_LOUDNESS) {
            loudnessContour_.processInterleaved(buffer, frames, channels);
        }

        // 10. Lookahead Limiter Stage (Multichannel / stereo / mono) — true-peak limiter is final
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
            const double effectiveRate = (snapshot && snapshot->sampleRate > 0.0) ? snapshot->sampleRate : sampleRate_;
            const double budgetSec = static_cast<double>(frames) / effectiveRate;
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
            // Note: Limiter output protection is NEVER disabled during auto-degrade to prevent clipping.
            if (avgRtf > 0.80f) {
                recoveryConsecutiveBlocks_ = 0;
                // Cost order: REVERB -> SATURATION -> DYNEQ -> CROSSOVER -> WIDTH -> CROSSFEED -> PANNER -> EQ
                if ((rawStages & STAGE_REVERB) && !(currentDegraded & STAGE_REVERB)) {
                    triggerStageAutoDegrade(STAGE_REVERB);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_SATURATION) && !(currentDegraded & STAGE_SATURATION)) {
                    triggerStageAutoDegrade(STAGE_SATURATION);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_DYNEQ) && !(currentDegraded & STAGE_DYNEQ)) {
                    triggerStageAutoDegrade(STAGE_DYNEQ);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_CROSSOVER) && !(currentDegraded & STAGE_CROSSOVER)) {
                    triggerStageAutoDegrade(STAGE_CROSSOVER);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_WIDTH) && !(currentDegraded & STAGE_WIDTH)) {
                    triggerStageAutoDegrade(STAGE_WIDTH);
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
                }
            } else if (avgRtf < 0.50f && currentDegraded != 0) {
                // Recovery: sustained low load (RTF < 0.50) over kRtfRecoveryWindowSize blocks
                recoveryConsecutiveBlocks_++;
                if (recoveryConsecutiveBlocks_ >= kRtfRecoveryWindowSize) {
                    recoveryConsecutiveBlocks_ = 0;
                    // Reverse cost order: EQ -> PANNER -> CROSSFEED -> WIDTH -> CROSSOVER -> DYNEQ -> SATURATION -> REVERB
                    if (currentDegraded & STAGE_EQ) {
                        eq_.reset();
                        recoverStageAutoDegrade(STAGE_EQ);
                    } else if (currentDegraded & STAGE_PANNER) {
                        panner_.reset();
                        recoverStageAutoDegrade(STAGE_PANNER);
                    } else if (currentDegraded & STAGE_CROSSFEED) {
                        crossfeed_.reset();
                        recoverStageAutoDegrade(STAGE_CROSSFEED);
                    } else if (currentDegraded & STAGE_WIDTH) {
                        stereoWidth_.reset();
                        recoverStageAutoDegrade(STAGE_WIDTH);
                    } else if (currentDegraded & STAGE_CROSSOVER) {
                        subCrossover_.reset();
                        recoverStageAutoDegrade(STAGE_CROSSOVER);
                    } else if (currentDegraded & STAGE_DYNEQ) {
                        dynamicEq_.reset();
                        recoverStageAutoDegrade(STAGE_DYNEQ);
                    } else if (currentDegraded & STAGE_SATURATION) {
                        saturation_.reset();
                        recoverStageAutoDegrade(STAGE_SATURATION);
                    } else if (currentDegraded & STAGE_REVERB) {
                        reverb_.reset();
                        recoverStageAutoDegrade(STAGE_REVERB);
                    }
                }
            } else {
                recoveryConsecutiveBlocks_ = 0;
            }
        }
    }

    return frames;
}
