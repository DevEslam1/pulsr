// android/app/src/main/cpp/eq_jni_bridge.cpp
#include <jni.h>
#include <android/log.h>
#include <vector>
#include "AudioDspEngine.h"

#define LOG_TAG "PulsrDSP"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSampleRate(
        JNIEnv* /* env */, jobject /* thiz */, jdouble sampleRate) {
    AudioDspEngine::instance().setSampleRate(sampleRate);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeResyncForTrack(
        JNIEnv* /* env */, jobject /* thiz */, jdouble sampleRate, jint channels) {
    AudioDspEngine::instance().resyncForTrack(sampleRate, channels);
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetAppliedSampleRate(
        JNIEnv* /* env */, jobject /* thiz */) {
    return AudioDspEngine::instance().getAppliedSampleRate();
}

JNIEXPORT jlong JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetLastAppliedGeneration(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jlong>(AudioDspEngine::instance().getLastAppliedGeneration());
}

JNIEXPORT jlong JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetPublishedGeneration(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jlong>(AudioDspEngine::instance().getPublishedGeneration());
}

JNIEXPORT jint JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetPipelineLatencyFrames(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jint>(AudioDspEngine::instance().getPipelineLatencyFrames());
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([enabled](DspParamSnapshot& snap) {
        snap.eq.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBandCount(
        JNIEnv* /* env */, jobject /* thiz */, jint count) {
    AudioDspEngine::instance().updateParams([count](DspParamSnapshot& snap) {
        snap.eq.bandCount = std::clamp(static_cast<int>(count), 1, EqParamSet::MAX_BANDS);
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBand(
        JNIEnv* /* env */, jobject /* thiz */,
        jint index, jdouble freq, jdouble gainDb, jdouble q, jint type, jboolean enabled) {
    if (index < 0 || index >= EqParamSet::MAX_BANDS) return;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        if (index >= snap.eq.bandCount) snap.eq.bandCount = index + 1;
        snap.eq.bands[index].frequency = freq;
        snap.eq.bands[index].gainDb = gainDb;
        snap.eq.bands[index].q = q;
        snap.eq.bands[index].type = static_cast<FilterType>(type);
        snap.eq.bands[index].enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBandsBulk(
        JNIEnv* env, jobject /* thiz */,
        jdoubleArray jFreqs, jdoubleArray jGains, jdoubleArray jQs, jintArray jTypes) {
    if (!jFreqs || !jGains) return;
    jsize freqLen = env->GetArrayLength(jFreqs);
    jsize gainLen = env->GetArrayLength(jGains);
    jsize count = freqLen < gainLen ? freqLen : gainLen;
    if (count <= 0 || count > EqParamSet::MAX_BANDS) return;

    jdouble* freqs = env->GetDoubleArrayElements(jFreqs, nullptr);
    jdouble* gains = env->GetDoubleArrayElements(jGains, nullptr);
    jdouble* qs = jQs ? env->GetDoubleArrayElements(jQs, nullptr) : nullptr;
    jint* types = jTypes ? env->GetIntArrayElements(jTypes, nullptr) : nullptr;
    if (!freqs || !gains) {
        if (freqs) env->ReleaseDoubleArrayElements(jFreqs, freqs, JNI_ABORT);
        if (gains) env->ReleaseDoubleArrayElements(jGains, gains, JNI_ABORT);
        if (qs && jQs) env->ReleaseDoubleArrayElements(jQs, qs, JNI_ABORT);
        if (types && jTypes) env->ReleaseIntArrayElements(jTypes, types, JNI_ABORT);
        return;
    }

    std::vector<double> vFreqs(freqs, freqs + count);
    std::vector<double> vGains(gains, gains + count);
    std::vector<double> vQs(count, 1.414);
    if (qs) {
        for (int i = 0; i < count; ++i) vQs[i] = qs[i];
    }
    std::vector<int> vTypes(count, static_cast<int>(FilterType::Peaking));
    if (types) {
        for (int i = 0; i < count; ++i) vTypes[i] = types[i];
    }

    env->ReleaseDoubleArrayElements(jFreqs, freqs, JNI_ABORT);
    env->ReleaseDoubleArrayElements(jGains, gains, JNI_ABORT);
    if (qs && jQs) env->ReleaseDoubleArrayElements(jQs, qs, JNI_ABORT);
    if (types && jTypes) env->ReleaseIntArrayElements(jTypes, types, JNI_ABORT);

    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.eq.bandCount = static_cast<int>(count);
        for (int i = 0; i < count; ++i) {
            snap.eq.bands[i].frequency = vFreqs[i];
            snap.eq.bands[i].gainDb = vGains[i];
            snap.eq.bands[i].q = vQs[i];
            snap.eq.bands[i].type = static_cast<FilterType>(vTypes[i]);
            snap.eq.bands[i].enabled = true;
        }
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetBandSolo(
        JNIEnv* /* env */, jobject /* thiz */, jint index, jboolean solo) {
    if (index < 0 || index >= EqParamSet::MAX_BANDS) return;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.eq.bands[index].solo = solo;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetBandMute(
        JNIEnv* /* env */, jobject /* thiz */, jint index, jboolean mute) {
    if (index < 0 || index >= EqParamSet::MAX_BANDS) return;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.eq.bands[index].mute = mute;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqPreamp(
        JNIEnv* /* env */, jobject /* thiz */, jdouble preampDb) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.eq.preampDb = preampDb;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.crossfeed.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble delayUs, jdouble feedDb) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.crossfeed.delayUs = delayUs;
        snap.crossfeed.feedDb = feedDb;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedFcut(
        JNIEnv* /* env */, jobject /* thiz */, jdouble fcut) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.crossfeed.fcut = fcut;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.limiter.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble lookaheadMs, jdouble thresholdDb, jdouble releaseMs) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.limiter.lookaheadMs = lookaheadMs;
        snap.limiter.thresholdDb = thresholdDb;
        snap.limiter.releaseMs = releaseMs;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterTruePeak(
        JNIEnv* /* env */, jobject /* thiz */, jboolean truePeak) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.limiter.truePeakMode = truePeak;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    std::shared_ptr<const PreparedIr> ir = nullptr;
    if (enabled && !current->reverb.preparedIr && current->reverb.preset != static_cast<int>(ReverbPreset::Custom)) {
        ir = PreparedIr::createSynthetic(
            current->sampleRate, current->reverb.preset, static_cast<float>(current->reverb.damping));
    }
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.enabled = enabled;
        if (ir && !snap.reverb.preparedIr) {
            snap.reverb.preparedIr = ir;
        }
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbPreset(
        JNIEnv* /* env */, jobject /* thiz */, jint preset) {
    if (preset < 0 || preset > static_cast<jint>(ReverbPreset::Custom)) return;
    auto current = AudioDspEngine::instance().getParams();
    std::shared_ptr<const PreparedIr> ir = nullptr;
    if (preset != static_cast<int>(ReverbPreset::Custom)) {
        ir = PreparedIr::createSynthetic(
            current->sampleRate, preset, static_cast<float>(current->reverb.damping));
    }
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.preset = preset;
        if (ir) {
            snap.reverb.preparedIr = ir;
        }
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbWetDry(
        JNIEnv* /* env */, jobject /* thiz */, jfloat wetRatio) {
    const double wet = static_cast<double>(wetRatio);
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.wetDry = wet;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbPredelay(
        JNIEnv* /* env */, jobject /* thiz */, jdouble predelayMs) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.predelayMs = predelayMs;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbDamping(
        JNIEnv* /* env */, jobject /* thiz */, jdouble damping) {
    auto current = AudioDspEngine::instance().getParams();
    std::shared_ptr<const PreparedIr> ir = nullptr;
    if (current->reverb.preset != static_cast<int>(ReverbPreset::Custom)) {
        ir = PreparedIr::createSynthetic(
            current->sampleRate, current->reverb.preset, static_cast<float>(damping));
    }
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.damping = damping;
        if (ir) {
            snap.reverb.preparedIr = ir;
        }
    });
}

JNIEXPORT jboolean JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeLoadImpulseResponse(
        JNIEnv* env, jobject /* thiz */, jfloatArray irSamples, jint channels) {
    if (!irSamples) return JNI_FALSE;
    jsize len = env->GetArrayLength(irSamples);
    jfloat* data = env->GetFloatArrayElements(irSamples, nullptr);
    if (!data) return JNI_FALSE;

    int frames = (channels > 0) ? (len / channels) : len;
    auto current = AudioDspEngine::instance().getParams();
    const double targetCoreRate = (current && current->sampleRate > 0.0) ? std::min(current->sampleRate, 48000.0) : 48000.0;
    auto customIr = PreparedIr::createCustom(current ? current->sampleRate : 48000.0, data, frames, channels, targetCoreRate);
    env->ReleaseFloatArrayElements(irSamples, data, JNI_ABORT);

    if (customIr) {
        AudioDspEngine::instance().updateParams([customIr](DspParamSnapshot& snap) {
            snap.reverb.preset = static_cast<int>(ReverbPreset::Custom);
            snap.reverb.preparedIr = customIr;
        });
        return JNI_TRUE;
    }
    return JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoBalance(
        JNIEnv* /* env */, jobject /* thiz */, jdouble balance) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.panner.balance = balance;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetMonoMix(
        JNIEnv* /* env */, jobject /* thiz */, jboolean mono) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.panner.monoMix = mono;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.resampler.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerRates(
        JNIEnv* /* env */, jobject /* thiz */, jdouble inRate, jdouble outRate) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.resampler.inRate = inRate;
        snap.resampler.outRate = outRate;
    });
}

static inline jint processPcmAudioInternal(JNIEnv* env, jfloatArray jBuffer, jint frameCount, jint channels) {
    if (!jBuffer || frameCount <= 0 || channels <= 0 || channels > 8) {
        return 0;
    }
    jsize arrayLen = env->GetArrayLength(jBuffer);
    jsize requiredLen = static_cast<jsize>(frameCount) * channels;
    if (arrayLen < requiredLen) {
        frameCount = static_cast<jint>(arrayLen / channels);
        if (frameCount <= 0) return 0;
    }

    jfloat* javaBuffer = env->GetFloatArrayElements(jBuffer, nullptr);
    if (!javaBuffer) {
        return 0;
    }

    try {
        int processedFrames = AudioDspEngine::instance().processInterleaved(
            javaBuffer,
            frameCount,
            channels
        );
        env->ReleaseFloatArrayElements(jBuffer, javaBuffer, 0);
        return static_cast<jint>(processedFrames);
    } catch (const std::exception& e) {
        LOGE("processPcmAudio: exception - %s", e.what());
        env->ReleaseFloatArrayElements(jBuffer, javaBuffer, JNI_ABORT);
        return 0;
    } catch (...) {
        LOGE("processPcmAudio: unknown exception");
        env->ReleaseFloatArrayElements(jBuffer, javaBuffer, JNI_ABORT);
        return 0;
    }
}

JNIEXPORT jint JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeProcessAudio(
        JNIEnv* env, jobject /* thiz */, jfloatArray buffer, jint frames, jint channels) {
    return processPcmAudioInternal(env, buffer, frames, channels);
}

JNIEXPORT jfloatArray JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeDecodeDsd(
        JNIEnv* env, jobject /* thiz */,
        jbyteArray dsdL, jbyteArray dsdR, jint byteCount, jint dsdRate, jint targetPcmSampleRate, jint bitOrder) {
    if (!dsdL || !dsdR || byteCount <= 0) return nullptr;
    if (dsdRate != static_cast<jint>(DsdDecoder::DsdRate::DSD64) &&
        dsdRate != static_cast<jint>(DsdDecoder::DsdRate::DSD128) &&
        dsdRate != static_cast<jint>(DsdDecoder::DsdRate::DSD256)) {
        return nullptr;
    }
    if (bitOrder < 0 || bitOrder > 1) return nullptr;

    jbyte* lData = env->GetByteArrayElements(dsdL, nullptr);
    jbyte* rData = env->GetByteArrayElements(dsdR, nullptr);
    if (!lData || !rData) {
        if (lData) env->ReleaseByteArrayElements(dsdL, lData, JNI_ABORT);
        if (rData) env->ReleaseByteArrayElements(dsdR, rData, JNI_ABORT);
        return nullptr;
    }

    try {
        auto dsdBitOrder = (bitOrder == 0) ? DsdDecoder::DsdBitOrder::LSB_FIRST : DsdDecoder::DsdBitOrder::MSB_FIRST;
        DsdDecoder decoder;
        decoder.configure(
                static_cast<DsdDecoder::DsdRate>(dsdRate), targetPcmSampleRate, dsdBitOrder);

        int maxOutFrames = decoder.getExpectedPcmFrames(byteCount);
        std::vector<float> pcmOut(maxOutFrames * 2);

        int actualFrames = decoder.decodeDsdBytes(
                reinterpret_cast<const uint8_t*>(lData),
                reinterpret_cast<const uint8_t*>(rData),
                byteCount,
                pcmOut.data(),
                maxOutFrames);

        env->ReleaseByteArrayElements(dsdL, lData, JNI_ABORT);
        env->ReleaseByteArrayElements(dsdR, rData, JNI_ABORT);

        if (actualFrames <= 0) return nullptr;

        jfloatArray result = env->NewFloatArray(actualFrames * 2);
        if (result) {
            env->SetFloatArrayRegion(result, 0, actualFrames * 2, pcmOut.data());
        }
        return result;
    } catch (...) {
        env->ReleaseByteArrayElements(dsdL, lData, JNI_ABORT);
        env->ReleaseByteArrayElements(dsdR, rData, JNI_ABORT);
        return nullptr;
    }
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetActiveStages(
        JNIEnv* /* env */, jobject /* thiz */, jint bitmask) {
    AudioDspEngine::instance().setActiveStages(static_cast<uint32_t>(bitmask));
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCacheBudgetBytes(
        JNIEnv* /* env */, jobject /* thiz */, jlong budgetBytes) {
    PreparedIr::setCacheBudgetBytes(static_cast<size_t>(budgetBytes));
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeReset(
        JNIEnv* /* env */, jobject /* thiz */) {
    AudioDspEngine::instance().reset();
}

JNIEXPORT jint JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetAutoDegradedStages(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jint>(AudioDspEngine::instance().getAutoDegradedStages());
}

// ---- Phase 1 DSP expansion: Harmonic Saturation / Exciter ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSaturationEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.saturation.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSaturationParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble drive, jdouble mix, jdouble tilt) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.saturation.drive = drive;
        snap.saturation.mix = mix;
        snap.saturation.tilt = tilt;
    });
}

// ---- Phase 1 DSP expansion: Stereo Width (Mid/Side) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoWidthEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.stereoWidth.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoWidthParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble width) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.stereoWidth.width = width;
    });
}

// ---- Phase 1 DSP expansion: Loudness Contour (Fletcher-Munson) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLoudnessContourEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.loudness.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLoudnessContourParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble intensity, jdouble volumeLinear) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.loudness.intensity = intensity;
        snap.loudness.volumeLinear = volumeLinear;
    });
}

// ---- Phase 1 DSP expansion: Subwoofer / LFE Crossover (bass redirection) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSubCrossoverEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.subCrossover.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSubCrossoverParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble cornerHz, jdouble slopeDbPerOct, jdouble subGain) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.subCrossover.cornerHz = cornerHz;
        snap.subCrossover.slopeDbPerOct = slopeDbPerOct;
        snap.subCrossover.subGain = subGain;
    });
}

// ---- Phase 1 DSP expansion: Dynamic EQ ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicEqEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.dynamicEq.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicEqBandCount(
        JNIEnv* /* env */, jobject /* thiz */, jint count) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.dynamicEq.bandCount = std::clamp(static_cast<int>(count), 0, DynamicEqParamSet::MAX_BANDS);
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicEqBand(
        JNIEnv* /* env */, jobject /* thiz */,
        jint index, jdouble freq, jdouble q, jdouble thresholdDb, jdouble ratio,
        jdouble attackMs, jdouble releaseMs, jdouble maxCutDb, jboolean enabled) {
    if (index < 0 || index >= DynamicEqParamSet::MAX_BANDS) return;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        if (index >= snap.dynamicEq.bandCount) snap.dynamicEq.bandCount = index + 1;
        auto& band = snap.dynamicEq.bands[index];
        band.frequency = freq;
        band.q = q;
        band.thresholdDb = thresholdDb;
        band.ratio = ratio;
        band.attackMs = attackMs;
        band.releaseMs = releaseMs;
        band.maxCutDb = maxCutDb;
        band.enabled = enabled;
    });
}

// ---- PCM Audio Processing for per-frame DSP ----

JNIEXPORT jint JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeProcessPcmAudio(
        JNIEnv* env, jobject /* thiz */,
        jfloatArray jBuffer, jint frameCount, jint channels) {
    return processPcmAudioInternal(env, jBuffer, frameCount, channels);
}

// ---- ExoPlayer Media3 NativeDspAudioProcessor In-Stream Direct Buffer Bridge ----

JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeProcessDirectFloatBuffer(
        JNIEnv* env, jclass /* clazz */, jobject byteBuffer, jint offsetBytes, jint frameCount, jint channels) {
    if (!byteBuffer || frameCount <= 0 || channels <= 0 || channels > 8) return 0;
    void* addr = env->GetDirectBufferAddress(byteBuffer);
    if (!addr) return 0;
    float* floatBuffer = reinterpret_cast<float*>(static_cast<char*>(addr) + offsetBytes);
    try {
        return static_cast<jint>(AudioDspEngine::instance().processInterleaved(floatBuffer, frameCount, channels));
    } catch (...) {
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeResyncForTrack(
        JNIEnv* /* env */, jclass /* clazz */, jdouble sampleRate, jint channels) {
    AudioDspEngine::instance().resyncForTrack(sampleRate, channels);
}

} // extern "C"
