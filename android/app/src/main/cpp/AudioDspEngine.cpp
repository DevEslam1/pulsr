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
    safetyLimiter_.configure(5.0, -6.0, 50.0, true);
    safetyLimiter_.setEnabled(true);
    setSampleRateInternal(48000.0);
}

void AudioDspEngine::setSampleRateInternal(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_.store(sampleRate, std::memory_order_release);

    eq_.setSampleRate(sampleRate);
    panner_.setSampleRate(sampleRate);
    crossfeed_.setSampleRate(sampleRate);
    limiter_.setSampleRate(sampleRate);
    safetyLimiter_.setSampleRate(sampleRate);
    reverb_.setSampleRate(sampleRate);
    resampler_.setRates(sampleRate, sampleRate);
    saturation_.setSampleRate(sampleRate);
    stereoWidth_.setSampleRate(sampleRate);
    loudnessContour_.setSampleRate(sampleRate);
    subCrossover_.setSampleRate(sampleRate);
    dynamicEq_.setSampleRate(sampleRate);
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
    drainRetireQueue();
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

DspEngineRegistry& DspEngineRegistry::instance() {
    static DspEngineRegistry sRegistry;
    return sRegistry;
}

void DspEngineRegistry::registerEngine(AudioDspEngine* engine) {
    if (!engine) return;
    std::lock_guard<std::mutex> lock(mutex_);
    engines_.push_back(engine);
    auto current = AudioDspEngine::instance().getParams();
    if (current) {
        engine->publishParams(current);
    }
}

void DspEngineRegistry::unregisterEngine(AudioDspEngine* engine) {
    if (!engine) return;
    std::lock_guard<std::mutex> lock(mutex_);
    engines_.erase(std::remove(engines_.begin(), engines_.end(), engine), engines_.end());
}

void DspEngineRegistry::broadcastParams(const std::shared_ptr<const DspParamSnapshot>& snapshot) {
    if (!snapshot) return;
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto* engine : engines_) {
        if (engine && engine != &AudioDspEngine::instance()) {
            engine->publishParams(snapshot);
        }
    }
}

int DspEngineRegistry::getMaxPipelineLatencyFrames() {
    std::lock_guard<std::mutex> lock(mutex_);
    int maxLatency = 0;
    for (auto* engine : engines_) {
        if (engine) {
            maxLatency = std::max(maxLatency, engine->getPipelineLatencyFrames());
        }
    }
    return maxLatency;
}

float DspEngineRegistry::getLimiterGrDb() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (engines_.empty()) {
        return AudioDspEngine::instance().getLimiterGrDb();
    }
    float minGr = 0.0f;
    for (auto* engine : engines_) {
        if (engine) {
            minGr = std::min(minGr, engine->getLimiterGrDb());
        }
    }
    return minGr;
}

float DspEngineRegistry::getDynEqGrDb(int band) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!engines_.empty() && engines_.back()) {
        return engines_.back()->getDynEqGrDb(band);
    }
    return AudioDspEngine::instance().getDynEqGrDb(band);
}

float DspEngineRegistry::getMultibandGrDb(int band) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!engines_.empty() && engines_.back()) {
        return engines_.back()->getMultibandGrDb(band);
    }
    return AudioDspEngine::instance().getMultibandGrDb(band);
}

double DspEngineRegistry::getRollingRtf() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (engines_.empty()) {
        return AudioDspEngine::instance().getRollingRtf();
    }
    double maxRtf = 0.0;
    for (auto* engine : engines_) {
        if (engine) {
            maxRtf = std::max(maxRtf, engine->getRollingRtf());
        }
    }
    return maxRtf;
}

uint32_t DspEngineRegistry::getAutoDegradedStages() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (engines_.empty()) {
        return AudioDspEngine::instance().getAutoDegradedStages();
    }
    uint32_t degraded = 0;
    for (auto* engine : engines_) {
        if (engine) {
            degraded |= engine->getAutoDegradedStages();
        }
    }
    return degraded;
}

void DspEngineRegistry::getTelemetry(double* outArray, int size) {
    if (!outArray || size < 15) return;
    std::lock_guard<std::mutex> lock(mutex_);
    AudioDspEngine* eng = engines_.empty() ? &AudioDspEngine::instance() : engines_.back();
    outArray[0] = static_cast<double>(eng->getLimiterGrDb());
    for (int i = 0; i < DynamicEqParamSet::MAX_BANDS; ++i) {
        outArray[1 + i] = static_cast<double>(eng->getDynEqGrDb(i));
    }
    for (int i = 0; i < MultibandCompressor::NUM_BANDS; ++i) {
        outArray[9 + i] = static_cast<double>(eng->getMultibandGrDb(i));
    }
    outArray[13] = eng->getRollingRtf();
    outArray[14] = static_cast<double>(eng->getAutoDegradedStages());
    if (size >= 16) {
        outArray[15] = eng->getWeeklyDose();
    }
    if (size >= 17) {
        outArray[16] = eng->isSafetyAttenuationActive() ? 1.0 : 0.0;
    }
}

double DspEngineRegistry::getWeeklyDose() {
    std::lock_guard<std::mutex> lock(mutex_);
    double maxDose = AudioDspEngine::instance().getWeeklyDose();
    for (auto* engine : engines_) {
        if (engine) {
            maxDose = std::max(maxDose, engine->getWeeklyDose());
        }
    }
    return maxDose;
}

void DspEngineRegistry::resetWeeklyDose() {
    std::lock_guard<std::mutex> lock(mutex_);
    AudioDspEngine::instance().resetWeeklyDose();
    for (auto* engine : engines_) {
        if (engine) {
            engine->resetWeeklyDose();
        }
    }
}

bool DspEngineRegistry::isSafetyAttenuationActive() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (AudioDspEngine::instance().isSafetyAttenuationActive()) return true;
    for (auto* engine : engines_) {
        if (engine && engine->isSafetyAttenuationActive()) {
            return true;
        }
    }
    return false;
}

double DspEngineRegistry::getAppliedSampleRate() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!engines_.empty() && engines_.back()) {
        return engines_.back()->getSampleRate();
    }
    return AudioDspEngine::instance().getSampleRate();
}

void AudioDspEngine::updateParams(SnapshotMutator mutator) {
    if (!mutator) return;
    std::lock_guard<std::mutex> lock(publishMutex_);
    auto current = currentParams_.load();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->resetRequested = false; // Clear reset by default so reset() only fires once
    mutator(*updated);
    updated->generation = ++snapshotGeneration_;
    auto snap = std::const_pointer_cast<const DspParamSnapshot>(updated);
    currentParams_.store(snap);
    drainRetireQueue();

    if (this == &AudioDspEngine::instance()) {
        DspEngineRegistry::instance().broadcastParams(snap);
    }
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
    const double mySr = sampleRate_.load(std::memory_order_acquire);
    if (mySr >= 8000.0) {
        mutableSnap->sampleRate = mySr;
        if (std::abs(mySr - snapshot->sampleRate) > 0.5) {
            if (snapshot->reverb.enabled &&
                snapshot->reverb.preset != static_cast<int>(ReverbPreset::Custom)) {
                mutableSnap->reverb.preparedIr = PreparedIr::createSynthetic(
                    mySr,
                    snapshot->reverb.preset,
                    static_cast<float>(snapshot->reverb.damping));
            }
        }
    }
    if (snapshot->generation >= snapshotGeneration_.load()) {
        snapshotGeneration_.store(snapshot->generation);
    }
    mutableSnap->generation = ++snapshotGeneration_;
    currentParams_.store(std::const_pointer_cast<const DspParamSnapshot>(mutableSnap));
    drainRetireQueue();
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
    multibandCompressor_.reset();
    dynamicBass_.reset();
    viperDdc_.reset();
    arbitraryEq_.reset();
    liveProg_.reset();
    safetyLimiter_.reset();
    smoothedReplayGain_ = 1.0;
    targetReplayGain_ = 1.0;
    smoothedDirectVolume_ = 1.0;
    smoothedSafetyGain_ = 1.0;
    limiterGrDb_.store(0.0f, std::memory_order_relaxed);
    for (int b = 0; b < DynamicEqParamSet::MAX_BANDS; ++b) {
        dynEqGrDb_[b].store(0.0f, std::memory_order_relaxed);
    }
    for (int b = 0; b < MultibandCompressor::NUM_BANDS; ++b) {
        mbCompGrDb_[b].store(0.0f, std::memory_order_relaxed);
    }
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

        const double currentSr = sampleRate_.load(std::memory_order_acquire);
        if (std::abs(snapshot->sampleRate - currentSr) > 0.5) {
            sampleRate_.store(snapshot->sampleRate, std::memory_order_release);
            const double sr = snapshot->sampleRate;
            eq_.setSampleRate(sr);
            panner_.setSampleRate(sr);
            crossfeed_.setSampleRate(sr);
            limiter_.setSampleRate(sr);
            safetyLimiter_.setSampleRate(sr);
            reverb_.setSampleRate(sr, /*updateIr=*/false);
            saturation_.setSampleRate(sr);
            stereoWidth_.setSampleRate(sr);
            loudnessContour_.setSampleRate(sr);
            subCrossover_.setSampleRate(sr);
            dynamicEq_.setSampleRate(sr);
            multibandCompressor_.setSampleRate(sr);
            dynamicBass_.prepare(sr);
            viperDdc_.setSampleRate(sr);
            arbitraryEq_.setSampleRate(sr, /*resynthesize=*/false);
            liveProg_.setSampleRate(sr);
        }

        eq_.applyParams(snapshot->eq);
        reverb_.applyParams(snapshot->reverb);
        panner_.applyParams(snapshot->panner);
        crossfeed_.applyParams(snapshot->crossfeed);
        limiter_.applyParams(snapshot->limiter);
        resampler_.applyParams(snapshot->resampler);
        saturation_.applyParams(snapshot->saturation);
        stereoWidth_.applyParams(snapshot->stereoWidth);
        loudnessContour_.applyParams(snapshot->loudness);
        subCrossover_.applyParams(snapshot->subCrossover);
        dynamicEq_.applyParams(snapshot->dynamicEq);
        multibandCompressor_.applyParams(snapshot->multibandCompressor);
        dynamicBass_.setParams(
            snapshot->dynamicBass.enabled,
            snapshot->dynamicBass.strength,
            snapshot->dynamicBass.xLow,
            snapshot->dynamicBass.xHigh,
            snapshot->dynamicBass.yLow,
            snapshot->dynamicBass.yHigh,
            snapshot->dynamicBass.sideGainLow,
            snapshot->dynamicBass.sideGainHigh,
            snapshot->dynamicBass.devicePreset
        );
        viperDdc_.applyParams(snapshot->viperDdc);
        arbitraryEq_.applyParams(snapshot->arbitraryEq);
        liveProg_.applyParams(snapshot->liveProg);
        safetyLimiter_.configure(5.0, snapshot->headphoneSafety.safetyCeilingDb, 50.0, true);
        safetyLimiter_.setEnabled(snapshot->headphoneSafety.enabled);

        lastAppliedGeneration_.store(snapshot->generation);
    }

    // Bit-Perfect / DoP bypass path: sample-identical to raw input, zero DSP roundtrips, volume locked to unity.
    // Gated on `enabled` only: a stale `isDop` must never keep the chain
    // bypassed after the user disables bit-perfect. Callers must clear
    // `enabled` (and `isDop`) together on disable.
    if (snapshot->bitPerfect.enabled) {
        return frames;
    }

    // ReplayGain 2.0 / EBU R128 pre-gain calculation
    if (snapshot->replayGain.enabled && snapshot->replayGain.mode != ReplayGainMode::Off) {
        double rawGainDb = (snapshot->replayGain.mode == ReplayGainMode::Album)
            ? (snapshot->replayGain.albumGainDb + snapshot->replayGain.preAmpDb)
            : (snapshot->replayGain.trackGainDb + snapshot->replayGain.preAmpDb);
        double gainLinear = std::pow(10.0, rawGainDb / 20.0);
        if (snapshot->replayGain.preventClipping) {
            double peak = (snapshot->replayGain.mode == ReplayGainMode::Album)
                ? snapshot->replayGain.albumPeak : snapshot->replayGain.trackPeak;
            if (peak > 0.0 && gainLinear * peak > 1.0) {
                gainLinear = 1.0 / peak;
            }
        }
        targetReplayGain_ = gainLinear;
    } else {
        targetReplayGain_ = 1.0;
    }

    // Smooth ReplayGain across 20ms window
    const double currentSr = sampleRate_.load(std::memory_order_relaxed);
    const double rgTau = 0.020;
    const double rgSmoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (currentSr * rgTau));
    const double startReplayGain = smoothedReplayGain_;
    smoothedReplayGain_ += rgSmoothFactor * (targetReplayGain_ - smoothedReplayGain_);

    // Net gain check for conditional limiter insertion
    bool hasNetPositiveGain = (smoothedReplayGain_ > 1.001);
    if (snapshot->directVolume.enabled && snapshot->directVolume.gainLinear > 1.001) {
        hasNetPositiveGain = true;
    }
    if (snapshot->eq.enabled) {
        if (snapshot->eq.preampDb > 0.01) hasNetPositiveGain = true;
        for (int b = 0; b < snapshot->eq.bandCount; ++b) {
            if (snapshot->eq.bands[b].enabled && snapshot->eq.bands[b].gainDb > 0.01) {
                hasNetPositiveGain = true;
                break;
            }
        }
    }
    if (snapshot->loudness.enabled && snapshot->loudness.intensity > 0.01 && snapshot->loudness.volumeLinear < 0.99) {
        hasNetPositiveGain = true;
    }
    if (snapshot->stereoWidth.enabled && snapshot->stereoWidth.width > 1.01) {
        hasNetPositiveGain = true;
    }
    if (snapshot->dynamicBass.enabled && snapshot->dynamicBass.strength > 1.01) {
        hasNetPositiveGain = true;
    }

    const uint32_t rawStages = snapshot->activeStages;
    const uint32_t degraded = autoDegradedStages_.load();
    const uint32_t stages = rawStages & ~degraded;
    const bool dvcActive = snapshot->directVolume.enabled &&
        (std::abs(smoothedDirectVolume_ - 1.0) > 1e-4 || std::abs(snapshot->directVolume.gainLinear - 1.0) > 1e-4);
    const bool nonUnityGain = (stages != 0) ||
                              (std::abs(smoothedReplayGain_ - 1.0) > 1e-4) ||
                              (std::abs(startReplayGain - 1.0) > 1e-4) ||
                              dvcActive ||
                              (std::abs(smoothedDirectVolume_ - 1.0) > 1e-4);

    if (nonUnityGain) {
        // Apply smoothed ReplayGain pre-gain before EQ stage
        if (std::abs(smoothedReplayGain_ - 1.0) > 1e-4 || std::abs(startReplayGain - 1.0) > 1e-4) {
            const int totalSamples = frames * channels;
            double currentRg = startReplayGain;
            double rgIncrement = (smoothedReplayGain_ - startReplayGain) / totalSamples;
            for (int i = 0; i < totalSamples; ++i) {
                buffer[i] *= static_cast<float>(currentRg);
                currentRg += rgIncrement;
            }
        }

        // 0. Sinc Resampler Stage — rate-matches the track to the engine rate
        //    first so all downstream coefficients (EQ, reverb, crossover) run
        //    at the true rate. In-place polyphase FIR keeps the N-in/N-out
        //    block contract; bypassed when rates match (zero cost).
        if ((stages & STAGE_RESAMPLER) && snapshot->resampler.enabled && !resampler_.isBypassed()) {
            resampler_.processInterleaved(buffer, frames, channels);
        }

        // 1. Parametric EQ Stage
        if (stages & STAGE_EQ) {
            eq_.processInterleaved(buffer, frames, channels);
        }

        // 1b. Arbitrary Response EQ (EqualizerAPO GraphicEq)
        if ((stages & STAGE_ARBITRARY_EQ) && snapshot->arbitraryEq.enabled) {
            arbitraryEq_.processInterleaved(buffer, frames, channels);
        }

        // 1c. ViPER-DDC (Digital Dynamic Correction)
        if ((stages & STAGE_VIPER_DDC) && snapshot->viperDdc.enabled) {
            viperDdc_.processInterleaved(buffer, frames, channels);
        }

        // 2. Dynamic EQ Stage — adjacent to the parametric EQ so band energy
        //    is detected on the tonally-shaped (but not yet spatialized) signal
        if (stages & STAGE_DYNEQ) {
            dynamicEq_.processInterleaved(buffer, frames, channels);
        }

        // 2b. Native Multiband Compressor Stage — 4-band LR4 dynamics (stereo channels 0 and 1)
        if ((stages & STAGE_MULTIBAND_COMPRESSOR) && snapshot->multibandCompressor.enabled && channels >= 2) {
            multibandCompressor_.processInterleaved(buffer, frames, channels);
        }

        // 3. Spatial Panner & Balance (All channels) — positioner before reverb for natural acoustics
        if (stages & STAGE_PANNER) {
            panner_.processInterleaved(buffer, frames, channels);
        }

        // 4. Crossfeed Stage (Stereo channels 0 and 1)
        if ((stages & STAGE_CROSSFEED) && channels >= 2) {
            crossfeed_.processInterleaved(buffer, frames, channels);
        }

        // 5. Convolution Reverb Stage (Stereo channels 0 and 1)
        if ((stages & STAGE_REVERB) && channels >= 2) {
            reverb_.processInterleaved(buffer, frames, channels);
        }

        // 6. Harmonic Saturation / Exciter Stage — 4x oversampled with anti-aliasing
        if (stages & STAGE_SATURATION) {
            saturation_.processInterleaved(buffer, frames, channels);
        }

        // 6b. Live Programmable DSP Stage
        if ((stages & STAGE_LIVE_PROG) && snapshot->liveProg.enabled) {
            liveProg_.processInterleaved(buffer, frames, channels);
        }

        // 7. Stereo Width Stage (M/S, stereo channels 0 and 1) — after crossfeed/reverb so
        //    the widened field is not re-collapsed by later spatial stages
        if ((stages & STAGE_WIDTH) && channels >= 2) {
            stereoWidth_.processInterleaved(buffer, frames, channels);
        }

        // 8. Subwoofer / LFE Crossover Stage (bass redirection sum, stereo pairs)
        if ((stages & STAGE_CROSSOVER) || subCrossover_.isRamping()) {
            subCrossover_.processInterleaved(buffer, frames, channels);
        }

        // 8b. Dynamic Bass Stage (ViPER-modeled Dynamic System, stereo channels 0 and 1)
        if ((stages & STAGE_DYNAMIC_BASS) && snapshot->dynamicBass.enabled && channels >= 2) {
            dynamicBass_.processInterleaved(buffer, frames, channels);
        }

        // 9. Loudness Contour Stage — computed against the current volume-stage
        //    value (pushed from Dart). Applied pre-limiter so the limiter still
        //    guards the contour-boosted peaks.
        if (stages & STAGE_LOUDNESS) {
            loudnessContour_.processInterleaved(buffer, frames, channels);
        }

        // 9b. Direct Volume Control (DVC): applied before the limiter so that any digital
        //     preamp or gain boost (> 1.0) is smoothly limited by LookaheadLimiter instead of
        //     hard-clipping against [-1, 1]. Smoothed over 20ms to avoid zipper noise on slider drags.
        {
            const double dvcTarget = snapshot->directVolume.enabled
                ? std::clamp(snapshot->directVolume.gainLinear, 0.0, 4.0)
                : 1.0;
            const double startDvc = smoothedDirectVolume_;
            if (std::abs(dvcTarget - smoothedDirectVolume_) > 1e-5) {
                const double dvcTau = 0.020;
                const double dvcSmooth =
                    1.0 - std::exp(-static_cast<double>(frames) / (currentSr * dvcTau));
                smoothedDirectVolume_ += dvcSmooth * (dvcTarget - smoothedDirectVolume_);
            } else {
                smoothedDirectVolume_ = dvcTarget;
            }
            if (std::abs(smoothedDirectVolume_ - 1.0) > 1e-4 || std::abs(startDvc - 1.0) > 1e-4) {
                const int totalSamples = frames * channels;
                double currentDvc = startDvc;
                double dvcIncrement = (smoothedDirectVolume_ - startDvc) / totalSamples;
                for (int i = 0; i < totalSamples; ++i) {
                    buffer[i] *= static_cast<float>(currentDvc);
                    currentDvc += dvcIncrement;
                }
            }
        }

        // 10. Lookahead Limiter Stage — inserted only when net gain > 0dB or enabled by config
        if ((stages & STAGE_LIMITER) && (hasNetPositiveGain || snapshot->limiter.enabled)) {
            limiter_.processInterleaved(buffer, frames, channels);
        }
    } else {
        smoothedDirectVolume_ = 1.0;
    }

    // 11. Headphone Safety & Sound Dose Tracking (EN 62368-1 / WHO-ITU H.870)
    // Mask-immune: safety enforcement cannot be bypassed by activeStages bitmask dropping.
    // Placed after DVC and main limiter, before dither.
    if (snapshot->headphoneSafety.enabled && frames > 0 && currentSr > 0.0) {
        double sumSq = 0.0;
        const int totalSamples = frames * channels;
        for (int i = 0; i < totalSamples; ++i) {
            const float s = buffer[i];
            if (std::isfinite(s)) {
                sumSq += static_cast<double>(s * s);
            }
        }
        const double meanSq = sumSq / static_cast<double>(totalSamples);
        // 100% weekly dose = 40 hours continuous at -14 dBFS (mean square power ~ 0.0398107)
        // deltaDose = (meanSq / 0.0398107) * (frames / (40.0 * 3600.0 * currentSr))
        // 0.0398107 * 144000.0 = 5732.74
        const double deltaDose = (meanSq * static_cast<double>(frames)) / (5732.74 * currentSr);

        // Rolling 7-day exponential decay per block (tau = 7 days = 604,800 s)
        const double decayFactor = std::max(0.0, 1.0 - (static_cast<double>(frames) / (604800.0 * currentSr)));
        double curDose = weeklyDose_.load(std::memory_order_relaxed);
        double newDose = 0.0;
        do {
            newDose = (curDose * decayFactor) + deltaDose;
        } while (!weeklyDose_.compare_exchange_weak(curDose, newDose,
                                                    std::memory_order_relaxed,
                                                    std::memory_order_relaxed));

        const bool thresholdExceeded = (newDose >= snapshot->headphoneSafety.doseThreshold);
        safetyAttenuationActive_.store(thresholdExceeded, std::memory_order_relaxed);

        // Smooth broadband attenuation when weekly dose threshold is exceeded (-6 dB gain)
        const double targetGain = thresholdExceeded ? 0.5 : 1.0;
        const double startGain = smoothedSafetyGain_;
        if (std::abs(targetGain - smoothedSafetyGain_) > 1e-5) {
            const double safetyTau = 0.020;
            const double safetySmooth =
                1.0 - std::exp(-static_cast<double>(frames) / (currentSr * safetyTau));
            smoothedSafetyGain_ += safetySmooth * (targetGain - smoothedSafetyGain_);
        } else {
            smoothedSafetyGain_ = targetGain;
        }
        if (std::abs(smoothedSafetyGain_ - 1.0) > 1e-4 || std::abs(startGain - 1.0) > 1e-4) {
            const int total = frames * channels;
            double currentGain = startGain;
            double gainIncrement = (smoothedSafetyGain_ - startGain) / total;
            for (int i = 0; i < total; ++i) {
                buffer[i] *= static_cast<float>(currentGain);
                currentGain += gainIncrement;
            }
        }

        // Continuous true-peak ceiling guard
        safetyLimiter_.processInterleaved(buffer, frames, channels);
    } else {
        smoothedSafetyGain_ = 1.0;
        safetyAttenuationActive_.store(false, std::memory_order_relaxed);
    }

    // TPDF Dither — its own stage bit, so a lone dither toggle acts standalone
    // (previously it was nested inside the non-unity-gain block and dead when no
    // other effect was active). Applied at the final requantization to the
    // configured output depth (16/24/32-bit) with a correctly scaled LSB.
    // SKIPPED on Bluetooth: SBC/AAC/LDAC re-quantize downstream, so dithering
    // here is wasted noise. When disabled — or the stage bit is clear — this is
    // bit-transparent: no write touches the buffer.
    const bool ditherStageActive = (stages & STAGE_DITHER) != 0 &&
                                   snapshot->dither.enabled &&
                                   !snapshot->dither.isBluetooth;
    if (ditherStageActive) {
        const float scale = ditherScaleForBits(snapshot->dither.targetBitDepth);
        const float invScale = 1.0f / scale;
        const int totalSamples = frames * channels;
        for (int i = 0; i < totalSamples; ++i) {
            float x = buffer[i];
            if (!std::isfinite(x)) continue;
            float dither = generateTpdf(); // Triangular PDF (-1.0 .. +1.0 LSB)
            float quant = std::round(x * scale + dither) * invScale;
            buffer[i] = std::clamp(quant, -1.0f, 1.0f);
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
            const double effectiveRate = (snapshot && snapshot->sampleRate > 0.0) ? snapshot->sampleRate : sampleRate_.load(std::memory_order_relaxed);
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
                // Cost order: REVERB -> MULTIBAND_COMPRESSOR -> DYNAMIC_BASS -> SATURATION -> DYNEQ -> CROSSOVER -> WIDTH -> CROSSFEED -> PANNER -> EQ
                if ((rawStages & STAGE_REVERB) && !(currentDegraded & STAGE_REVERB)) {
                    triggerStageAutoDegrade(STAGE_REVERB);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_MULTIBAND_COMPRESSOR) && !(currentDegraded & STAGE_MULTIBAND_COMPRESSOR)) {
                    triggerStageAutoDegrade(STAGE_MULTIBAND_COMPRESSOR);
                    rtfCount_ = 0;
                    rtfRingHead_ = 0;
                } else if ((rawStages & STAGE_DYNAMIC_BASS) && !(currentDegraded & STAGE_DYNAMIC_BASS)) {
                    triggerStageAutoDegrade(STAGE_DYNAMIC_BASS);
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
                    // Reverse cost order: EQ -> PANNER -> CROSSFEED -> WIDTH -> CROSSOVER -> DYNEQ -> SATURATION -> DYNAMIC_BASS -> MULTIBAND_COMPRESSOR -> REVERB
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
                    } else if (currentDegraded & STAGE_DYNAMIC_BASS) {
                        dynamicBass_.reset();
                        recoverStageAutoDegrade(STAGE_DYNAMIC_BASS);
                    } else if (currentDegraded & STAGE_MULTIBAND_COMPRESSOR) {
                        multibandCompressor_.reset();
                        recoverStageAutoDegrade(STAGE_MULTIBAND_COMPRESSOR);
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

    // Output-integrity guard: if any upstream stage emitted a non-finite sample
    // (corrupt tag, denormal blow-up, bad coefficient), scrub it and reset the
    // whole chain. Without this a poisoned filter/gain state stays NaN and every
    // subsequent track plays as persistent noise until the process restarts.
    {
        const int total = frames * channels;
        bool nonFiniteFound = false;
        for (int i = 0; i < total; ++i) {
            if (!std::isfinite(buffer[i])) {
                buffer[i] = 0.0f;
                nonFiniteFound = true;
            }
        }
        if (nonFiniteFound) {
            resetInternal();
            smoothedReplayGain_ = 1.0;
            smoothedDirectVolume_ = 1.0;
        }
    }

    // Defer destruction of old snapshots off the audio thread
    int head = retireHead_.load(std::memory_order_relaxed);
    int next = (head + 1) % kRetireQueueSize;
    if (next != retireTail_.load(std::memory_order_acquire)) {
        retireQueue_[head] = std::move(snapshot);
        retireHead_.store(next, std::memory_order_release);
    }

    // Telemetry updates (lock-free atomics)
    limiterGrDb_.store(limiter_.getCurrentGainReductionDb(), std::memory_order_relaxed);
    for (int b = 0; b < DynamicEqParamSet::MAX_BANDS; ++b) {
        dynEqGrDb_[b].store(static_cast<float>(dynamicEq_.getGainAdjustmentDb(b)), std::memory_order_relaxed);
    }
    for (int b = 0; b < MultibandCompressor::NUM_BANDS; ++b) {
        mbCompGrDb_[b].store(static_cast<float>(multibandCompressor_.getBandGainReductionDb(b)), std::memory_order_relaxed);
    }

    return frames;
}
