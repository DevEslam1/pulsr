// android/app/src/main/cpp/eq_jni_bridge.cpp
#include <jni.h>
#include <android/log.h>
#include <cmath>
#include <cstring>
#include <vector>
#include "AudioDspEngine.h"
#include "UsbAudioSink.h"

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
    DspEngineRegistry::instance().drainRetireQueues();
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
    // Read from the registry: the singleton control engine never renders audio,
    // so its stage latency is always 0. The per-player engines are the ones
    // whose limiter/resampler/reverb latency is real.
    return static_cast<jint>(DspEngineRegistry::instance().getMaxPipelineLatencyFrames());
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
    jsize qLen = jQs ? env->GetArrayLength(jQs) : 0;
    jdouble* qs = (jQs && qLen > 0) ? env->GetDoubleArrayElements(jQs, nullptr) : nullptr;
    jsize typeLen = jTypes ? env->GetArrayLength(jTypes) : 0;
    jint* types = (jTypes && typeLen > 0) ? env->GetIntArrayElements(jTypes, nullptr) : nullptr;
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
        const jsize limit = std::min(count, qLen);
        for (jsize i = 0; i < limit; ++i) vQs[i] = qs[i];
    }
    std::vector<int> vTypes(count, static_cast<int>(FilterType::Peaking));
    if (types) {
        const jsize limit = std::min(count, typeLen);
        for (jsize i = 0; i < limit; ++i) vTypes[i] = types[i];
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

// FIX C-3: Retain last loaded custom IR so it can be restored when
// the user switches back to the Custom preset from a synthetic one.
static std::shared_ptr<const PreparedIr> gLastCustomIr;

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbPreset(
        JNIEnv* /* env */, jobject /* thiz */, jint preset) {
    if (preset < 0 || preset > static_cast<jint>(ReverbPreset::Custom)) return;
    auto current = AudioDspEngine::instance().getParams();
    std::shared_ptr<const PreparedIr> ir = nullptr;
    if (preset != static_cast<int>(ReverbPreset::Custom)) {
        // Switching to a synthetic preset — create it from current damping
        ir = PreparedIr::createSynthetic(
            current->sampleRate, preset, static_cast<float>(current->reverb.damping));
    } else {
        // FIX C-3: Switching back to Custom — restore the last loaded custom IR
        ir = gLastCustomIr;
        // If no custom IR was ever loaded, ir stays nullptr;
        // the engine will be silent on Custom until the user loads an IR file.
    }
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.preset = preset;
        snap.reverb.preparedIr = ir;
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

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbCrossChannel(
        JNIEnv* /* env */, jobject /* thiz */, jdouble crossChannel) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.reverb.crossChannel = std::clamp(crossChannel, 0.0, 1.0);
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

    // Normalize the loaded IR to unit peak. A full-scale impulse response would
    // otherwise drive the wet path far above the dry signal (createCustom does
    // not normalize), forcing constant limiting/clipping. Normalizing here keeps
    // the reverb's dry/wet balance meaningful for arbitrary user IRs.
    float irPeak = 0.0f;
    for (int i = 0; i < len; ++i) {
        const float a = std::abs(data[i]);
        if (a > irPeak) irPeak = a;
    }
    if (irPeak > 1e-6f && std::isfinite(irPeak)) {
        const float invPeak = 1.0f / irPeak;
        for (int i = 0; i < len; ++i) {
            data[i] *= invPeak;
        }
    }

    auto current = AudioDspEngine::instance().getParams();
    const double targetCoreRate = (current && current->sampleRate > 0.0) ? std::min(current->sampleRate, 48000.0) : 48000.0;
    auto customIr = PreparedIr::createCustom(current ? current->sampleRate : 48000.0, data, frames, channels, targetCoreRate);
    env->ReleaseFloatArrayElements(irSamples, data, JNI_ABORT);

    if (customIr) {
        gLastCustomIr = customIr; // FIX C-3: persist for Custom preset restore
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

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerQuality(
        JNIEnv* /* env */, jobject /* thiz */, jint quality) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.resampler.quality = quality;
    });
}

JNIEXPORT jfloatArray JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeDecodeDsd(
        JNIEnv* env, jobject /* thiz */,
        jbyteArray dsdL, jbyteArray dsdR, jint byteCount, jint dsdRate, jint targetPcmSampleRate, jint bitOrder) {
    if (!dsdL || !dsdR || byteCount <= 0) return nullptr;
    constexpr int kMaxDsdByteCount = 16 * 1024 * 1024; // 16 MB max per chunk
    if (byteCount > kMaxDsdByteCount) return nullptr;
    if (env->GetArrayLength(dsdL) < byteCount || env->GetArrayLength(dsdR) < byteCount) return nullptr;
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

    struct CachedDsdDecoder {
        DsdDecoder decoder;
        jint dsdRate = -1;
        jint targetRate = -1;
        jint bitOrder = -1;
    };
    static thread_local CachedDsdDecoder sDecoderCache;

    try {
        // bitOrder contract: 0 = LSB first (DSF), 1 = MSB first (DFF)
        auto dsdBitOrder = (bitOrder == 0) ? DsdDecoder::DsdBitOrder::LSB_FIRST : DsdDecoder::DsdBitOrder::MSB_FIRST;
        if (sDecoderCache.dsdRate != dsdRate ||
            sDecoderCache.targetRate != targetPcmSampleRate ||
            sDecoderCache.bitOrder != bitOrder) {
            sDecoderCache.decoder.configure(
                static_cast<DsdDecoder::DsdRate>(dsdRate), targetPcmSampleRate, dsdBitOrder);
            sDecoderCache.dsdRate = dsdRate;
            sDecoderCache.targetRate = targetPcmSampleRate;
            sDecoderCache.bitOrder = bitOrder;
        }

        int maxOutFrames = sDecoderCache.decoder.getExpectedPcmFrames(byteCount);
        constexpr int kMaxPcmFrames = 4 * 1024 * 1024;
        if (maxOutFrames <= 0 || maxOutFrames > kMaxPcmFrames) {
            env->ReleaseByteArrayElements(dsdL, lData, JNI_ABORT);
            env->ReleaseByteArrayElements(dsdR, rData, JNI_ABORT);
            return nullptr;
        }

        std::vector<float> pcmOut(maxOutFrames * 2);

        int actualFrames = sDecoderCache.decoder.decodeDsdBytes(
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
    return static_cast<jint>(DspEngineRegistry::instance().getAutoDegradedStages());
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetLimiterGrDb(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jdouble>(DspEngineRegistry::instance().getLimiterGrDb());
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetDynEqGrDb(
        JNIEnv* /* env */, jobject /* thiz */, jint band) {
    return static_cast<jdouble>(DspEngineRegistry::instance().getDynEqGrDb(static_cast<int>(band)));
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetMultibandGrDb(
        JNIEnv* /* env */, jobject /* thiz */, jint band) {
    return static_cast<jdouble>(DspEngineRegistry::instance().getMultibandGrDb(static_cast<int>(band)));
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetRollingRtf(
        JNIEnv* /* env */, jobject /* thiz */) {
    return DspEngineRegistry::instance().getRollingRtf();
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetPerformanceProfile(
        JNIEnv* /* env */, jobject /* thiz */, jint profile) {
    const auto prof = (profile == 0) ? DspPerformanceProfile::Audiophile
                    : (profile == 2) ? DspPerformanceProfile::PowerSaver
                    : DspPerformanceProfile::Performance;
    DspEngineRegistry::instance().setPerformanceProfile(prof);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetThermalLevel(
        JNIEnv* /* env */, jobject /* thiz */, jint level) {
    DspEngineRegistry::instance().setThermalLevel(static_cast<int>(level));
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbThreadingMode(
        JNIEnv* /* env */, jobject /* thiz */, jint mode) {
    const auto m = (mode == 0) ? ReverbThreadingMode::SingleThread
                 : (mode == 1) ? ReverbThreadingMode::MultiThread
                 : ReverbThreadingMode::Auto;
    DspEngineRegistry::instance().setReverbThreadingMode(m);
}

JNIEXPORT jdoubleArray JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetTelemetry(
        JNIEnv* env, jobject /* thiz */) {
    DspEngineRegistry::instance().drainRetireQueues();
    double telemetry[17] = {};
    DspEngineRegistry::instance().getTelemetry(telemetry, 17);
    jdoubleArray result = env->NewDoubleArray(17);
    if (result) {
        env->SetDoubleArrayRegion(result, 0, 17, telemetry);
    }
    return result;
}

// ---- Feature 4: Headphone Safety & Sound Dose Tracking (EN 62368-1 / WHO-ITU H.870) ----

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetWeeklyDose(
        JNIEnv* /* env */, jobject /* thiz */) {
    return DspEngineRegistry::instance().getWeeklyDose();
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeResetWeeklyDose(
        JNIEnv* /* env */, jobject /* thiz */) {
    DspEngineRegistry::instance().resetWeeklyDose();
}

JNIEXPORT jboolean JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeIsSafetyAttenuationActive(
        JNIEnv* /* env */, jobject /* thiz */) {
    return DspEngineRegistry::instance().isSafetyAttenuationActive() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetHeadphoneSafetyParams(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled, jdouble threshold, jdouble ceilingDb) {
    const double safeThreshold = (std::isfinite(threshold) && threshold > 0.0)
        ? std::clamp(static_cast<double>(threshold), 0.01, 10.0)
        : 1.0;
    const double safeCeilingDb = std::isfinite(ceilingDb)
        ? std::clamp(static_cast<double>(ceilingDb), -24.0, 0.0)
        : -6.0;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.headphoneSafety.enabled = enabled;
        snap.headphoneSafety.doseThreshold = safeThreshold;
        snap.headphoneSafety.safetyCeilingDb = safeCeilingDb;
        if (enabled) {
            snap.activeStages |= STAGE_HEADPHONE_SAFETY;
        } else {
            snap.activeStages &= ~STAGE_HEADPHONE_SAFETY;
        }
    });
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeGetAppliedSampleRate(
        JNIEnv* /* env */, jobject /* thiz */) {
    return DspEngineRegistry::instance().getAppliedSampleRate();
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
        JNIEnv* /* env */, jobject /* thiz */, jdouble drive, jdouble mix, jdouble tilt, jint mode, jboolean multiband) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.saturation.drive = drive;
        snap.saturation.mix = mix;
        snap.saturation.tilt = tilt;
        snap.saturation.mode = mode;
        snap.saturation.multiband = multiband;
    });
}

// ---- Phase 1 DSP expansion: Stereo Width (3-Band Multiband Stereo Imager) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoWidthEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.stereoWidth.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoWidthParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble width, jboolean multiband,
        jdouble lowWidth, jdouble midWidth, jdouble highWidth, jdouble lowCrossoverHz, jdouble highCrossoverHz) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.stereoWidth.width = width;
        snap.stereoWidth.multiband = multiband;
        snap.stereoWidth.lowWidth = lowWidth;
        snap.stereoWidth.midWidth = midWidth;
        snap.stereoWidth.highWidth = highWidth;
        snap.stereoWidth.lowCrossoverHz = lowCrossoverHz;
        snap.stereoWidth.highCrossoverHz = highCrossoverHz;
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

// ---- Phase 1 DSP expansion: Subwoofer Crossover & Bass Management (Bass Mono + Anti-Pop) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSubCrossoverEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.subCrossover.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSubCrossoverParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble cornerHz, jdouble slopeDbPerOct, jdouble subGain,
        jboolean bassMono, jboolean antiPop) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.subCrossover.cornerHz = cornerHz;
        snap.subCrossover.slopeDbPerOct = slopeDbPerOct;
        snap.subCrossover.subGain = subGain;
        snap.subCrossover.bassMono = bassMono;
        snap.subCrossover.antiPop = antiPop;
    });
}

// ---- Phase 1 DSP expansion: Dynamic EQ (Cut & Boost modes, Peaking/Shelves) ----

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
        jdouble attackMs, jdouble releaseMs, jdouble maxCutDb, jdouble maxBoostDb,
        jint mode, jint filterType, jboolean enabled) {
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
        band.maxBoostDb = maxBoostDb;
        band.mode = mode;
        band.filterType = filterType;
        band.enabled = enabled;
    });
}

// ---- Native Multiband Compressor ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetMultibandCompressorEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.multibandCompressor.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetMultibandCompressorBand(
        JNIEnv* /* env */, jobject /* thiz */,
        jint bandIndex, jdouble thresholdDb, jdouble ratio, jdouble attackMs,
        jdouble releaseMs, jdouble kneeDb, jdouble makeupGainDb, jboolean enabled) {
    if (bandIndex < 0 || bandIndex >= MultibandCompressorParamSet::NUM_BANDS) return;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        auto& b = snap.multibandCompressor.bands[bandIndex];
        b.thresholdDb = thresholdDb;
        b.ratio = ratio;
        b.attackMs = attackMs;
        b.releaseMs = releaseMs;
        b.kneeDb = kneeDb;
        b.makeupGainDb = makeupGainDb;
        b.enabled = enabled;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetMultibandCompressorCrossovers(
        JNIEnv* /* env */, jobject /* thiz */,
        jdouble f0, jdouble f1, jdouble f2) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.multibandCompressor.crossoverFreqs[0] = f0;
        snap.multibandCompressor.crossoverFreqs[1] = f1;
        snap.multibandCompressor.crossoverFreqs[2] = f2;
    });
}

// ---- ViPER-modeled Dynamic System / Dynamic Bass ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicBassParams(
        JNIEnv* /* env */, jobject /* thiz */,
        jboolean enabled, jdouble strength,
        jint xLow, jint xHigh, jint yLow, jint yHigh,
        jdouble sideGainLow, jdouble sideGainHigh,
        jint devicePreset) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.dynamicBass.enabled = enabled;
        snap.dynamicBass.strength = strength;
        snap.dynamicBass.xLow = xLow;
        snap.dynamicBass.xHigh = xHigh;
        snap.dynamicBass.yLow = yLow;
        snap.dynamicBass.yHigh = yHigh;
        snap.dynamicBass.sideGainLow = sideGainLow;
        snap.dynamicBass.sideGainHigh = sideGainHigh;
        snap.dynamicBass.devicePreset = devicePreset;
    });
}


// ---- ReplayGain 2.0 / EBU R128 pre-gain (bit-transparent, in-DSP) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReplayGainEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.replayGain.enabled = enabled;
        if (!enabled) snap.replayGain.mode = ReplayGainMode::Off;
        else if (snap.replayGain.mode == ReplayGainMode::Off) snap.replayGain.mode = ReplayGainMode::Track;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReplayGainParams(
        JNIEnv* /* env */, jobject /* thiz */,
        jint mode, jdouble trackGainDb, jdouble albumGainDb,
        jdouble trackPeak, jdouble albumPeak,
        jdouble preAmpDb, jboolean preventClipping, jboolean enabled) {
    if (mode < 0 || mode > 2) return;
    auto m = static_cast<ReplayGainMode>(mode);
    // Sanitize at the boundary: a corrupt tag (NaN / +/-inf) reaching the
    // engine poisons its smoothed pre-gain for the whole session, so every
    // following track plays as noise. Peak already had a `> 0.0` guard, which
    // happens to reject NaN; gain and preamp had none.
    const auto finiteOr = [](double v, double fallback) {
        return std::isfinite(v) ? v : fallback;
    };
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.replayGain.mode = enabled ? m : ReplayGainMode::Off;
        snap.replayGain.trackGainDb = finiteOr(trackGainDb, 0.0);
        snap.replayGain.albumGainDb = finiteOr(albumGainDb, 0.0);
        snap.replayGain.trackPeak =
            (std::isfinite(trackPeak) && trackPeak > 0.0) ? trackPeak : 1.0;
        snap.replayGain.albumPeak =
            (std::isfinite(albumPeak) && albumPeak > 0.0) ? albumPeak : 1.0;
        snap.replayGain.preAmpDb = finiteOr(preAmpDb, 0.0);
        snap.replayGain.preventClipping = preventClipping;
        snap.replayGain.enabled = enabled;
    });
}

// ---- Direct Volume Control (DVC) float output gain ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDirectVolumeParams(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled, jdouble gainLinear) {
    double g = gainLinear;
    // Reject NaN/inf and clamp to a sane linear range. Negative gain is muted.
    if (!(g >= 0.0)) g = 0.0;
    if (g > 4.0) g = 4.0;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.directVolume.enabled = enabled;
        snap.directVolume.gainLinear = g;
    });
}

// ---- Dither (TPDF at 16/24/32-bit target) + Bluetooth route flag ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDitherParams(
        JNIEnv* /* env */, jobject /* thiz */,
        jboolean enabled, jint targetBitDepth, jboolean isBluetooth) {
    int depth = static_cast<int>(targetBitDepth);
    if (depth != 16 && depth != 24 && depth != 32) return;
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.dither.enabled = enabled;
        snap.dither.targetBitDepth = depth;
        snap.dither.isBluetooth = isBluetooth;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDitherBluetooth(
        JNIEnv* /* env */, jobject /* thiz */, jboolean isBluetooth) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.dither.isBluetooth = isBluetooth;
    });
}

// ---- Bit-Perfect / DoP bypass (source of truth alongside activeStages=0) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetBitPerfectParams(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled, jboolean isDop) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.bitPerfect.enabled = enabled;
        snap.bitPerfect.isDop = isDop;
    });
}

// ---- ExoPlayer Media3 NativeDspAudioProcessor In-Stream Direct Buffer Bridge ----

JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeCreateEngine(
        JNIEnv* /* env */, jclass /* clazz */) {
    try {
        auto* engine = new AudioDspEngine();
        DspEngineRegistry::instance().registerEngine(engine);
        return reinterpret_cast<jlong>(engine);
    } catch (...) {
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedMode(
        JNIEnv* /* env */, jobject /* thiz */, jint mode) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.crossfeed.mode = static_cast<CrossfeedMode>(mode);
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSaturationMultiband(
        JNIEnv* /* env */, jobject /* thiz */, jboolean multiband) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.saturation.multiband = multiband;
    });
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetViperDdcEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.viperDdc.enabled = enabled;
    });
}

JNIEXPORT jboolean JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeLoadViperDdc(
        JNIEnv* env, jobject /* thiz */, jstring jDdcContent, jstring jProfileName) {
    if (!jDdcContent) return JNI_FALSE;
    const char* ddcStr = env->GetStringUTFChars(jDdcContent, nullptr);
    const char* nameStr = jProfileName ? env->GetStringUTFChars(jProfileName, nullptr) : "";
    std::string content(ddcStr ? ddcStr : "");
    std::string name(nameStr ? nameStr : "");
    if (ddcStr) env->ReleaseStringUTFChars(jDdcContent, ddcStr);
    if (jProfileName && nameStr) env->ReleaseStringUTFChars(jProfileName, nameStr);

    // Parse off-thread and publish the prepared coefficient sets via the
    // snapshot so the audio-thread applyParams never parses/allocates.
    std::vector<ViperDdcSection> s441;
    std::vector<ViperDdcSection> s480;
    const bool ok = ViperDdc::parseVdcContent(content, s441, s480);
    if (ok) {
        auto p441 = std::make_shared<const std::vector<ViperDdcSection>>(s441);
        auto p480 = std::make_shared<const std::vector<ViperDdcSection>>(s480);
        AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
            snap.viperDdc.ddcContent = content;
            snap.viperDdc.profileName = name;
            snap.viperDdc.sections441 = p441;
            snap.viperDdc.sections480 = p480;
        });
    }
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetArbitraryEqEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.arbitraryEq.enabled = enabled;
    });
}

JNIEXPORT jboolean JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeLoadArbitraryEq(
        JNIEnv* env, jobject /* thiz */, jstring jEqString, jboolean linearPhase) {
    if (!jEqString) return JNI_FALSE;
    const char* eqStr = env->GetStringUTFChars(jEqString, nullptr);
    std::string content(eqStr ? eqStr : "");
    if (eqStr) env->ReleaseStringUTFChars(jEqString, eqStr);

    // Parse off-thread and publish the parsed node list via the snapshot so the
    // audio-thread applyParams never parses/allocates (see DspParams.h).
    std::vector<std::pair<double, double>> nodes;
    const bool ok = ArbitraryResponseEq::parseGraphicEq(content, nodes);
    if (ok) {
        auto parsed = std::make_shared<const std::vector<std::pair<double, double>>>(nodes);
        AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
            snap.arbitraryEq.graphicEqString = content;
            snap.arbitraryEq.linearPhase = linearPhase;
            snap.arbitraryEq.parsedNodes = parsed;
        });
    }
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLiveProgEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        snap.liveProg.enabled = enabled;
    });
}

JNIEXPORT jstring JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeLoadLiveProgCode(
        JNIEnv* env, jobject /* thiz */, jstring jCode) {
    if (!jCode) return env->NewStringUTF("Empty code");
    const char* codeStr = env->GetStringUTFChars(jCode, nullptr);
    std::string script(codeStr ? codeStr : "");
    if (codeStr) env->ReleaseStringUTFChars(jCode, codeStr);

    // Compile on a throwaway instance so the live bytecode is only rebuilt on
    // the audio thread from the prepared program; then package it off-thread.
    LiveProg validator;
    const bool ok = validator.loadCode(script);
    if (ok) {
        auto program = validator.buildProgram();
        AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
            snap.liveProg.code = script;
            snap.liveProg.program = program;
        });
        return env->NewStringUTF("OK");
    } else {
        return env->NewStringUTF(validator.getLastError().c_str());
    }
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLiveProgSlider(
        JNIEnv* /* env */, jobject /* thiz */, jint index, jdouble value) {
    // Publish only; LiveProg::applyParams writes the sliders on the audio
    // thread. Calling setSlider() here would mutate program memory mid-execution.
    AudioDspEngine::instance().updateParams([=](DspParamSnapshot& snap) {
        if (index == 1) snap.liveProg.slider1 = value;
        else if (index == 2) snap.liveProg.slider2 = value;
        else if (index == 3) snap.liveProg.slider3 = value;
        else if (index == 4) snap.liveProg.slider4 = value;
        else if (index == 5) snap.liveProg.slider5 = value;
        else if (index == 6) snap.liveProg.slider6 = value;
        else if (index == 7) snap.liveProg.slider7 = value;
        else if (index == 8) snap.liveProg.slider8 = value;
    });
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeDestroyEngine(
        JNIEnv* /* env */, jclass /* clazz */, jlong engineHandle) {
    if (engineHandle == 0) return;
    try {
        auto* engine = reinterpret_cast<AudioDspEngine*>(engineHandle);
        DspEngineRegistry::instance().unregisterEngine(engine);
        delete engine;
    } catch (...) {}
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeResetEngine(
        JNIEnv* /* env */, jclass /* clazz */, jlong engineHandle) {
    auto* engine = reinterpret_cast<AudioDspEngine*>(engineHandle);
    if (!engine) engine = &AudioDspEngine::instance();
    try {
        engine->reset();
    } catch (...) {}
}

JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeProcessDirectFloatBuffer(
        JNIEnv* env, jclass /* clazz */, jlong engineHandle, jobject byteBuffer, jint offsetBytes, jint frameCount, jint channels) {
    if (!byteBuffer || frameCount <= 0 || channels <= 0 || channels > 8) return 0;
    void* addr = env->GetDirectBufferAddress(byteBuffer);
    if (!addr) return 0;
    // Validate buffer bounds to prevent overruns from untrusted offset/frameCount.
    jlong capacity = env->GetDirectBufferCapacity(byteBuffer);
    jlong requiredBytes = static_cast<jlong>(offsetBytes) +
        static_cast<jlong>(frameCount) * channels * static_cast<jlong>(sizeof(float));
    if (capacity < 0 || requiredBytes > capacity) return 0;
    float* floatBuffer = reinterpret_cast<float*>(static_cast<char*>(addr) + offsetBytes);
    auto* engine = reinterpret_cast<AudioDspEngine*>(engineHandle);
    if (!engine) engine = &AudioDspEngine::instance();
    try {
        jint processed = static_cast<jint>(engine->processInterleaved(floatBuffer, frameCount, channels));
        // USB exclusive streaming: tee the processed PCM to the isochronous USB
        // sink and mute the HAL path so audio is never doubled if Android
        // re-routes to another output.
        auto& usb = pulsr::UsbAudioSink::instance();
        if (usb.IsActive()) {
            usb.WriteInterleaved(floatBuffer, frameCount, channels);
            std::memset(floatBuffer, 0,
                        static_cast<size_t>(frameCount) * channels * sizeof(float));
        }
        return processed;
    } catch (...) {
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeResyncForTrack(
        JNIEnv* /* env */, jclass /* clazz */, jlong engineHandle, jdouble sampleRate, jint channels) {
    auto* engine = reinterpret_cast<AudioDspEngine*>(engineHandle);
    if (!engine) engine = &AudioDspEngine::instance();
    try {
        engine->resyncForTrack(sampleRate, channels);
    } catch (...) {}
}

// ---- USB UAC2 isochronous exclusive streaming (UsbExclusivePlugin) ----

JNIEXPORT jint JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamStart(
        JNIEnv* /* env */, jobject /* thiz */, jint fd, jint endpoint,
        jint interfaceNumber, jint altSetting, jint sampleRate, jint channels) {
    auto res = pulsr::UsbAudioSink::instance().Open(
               fd, endpoint, interfaceNumber, altSetting, sampleRate, channels, 2);
    return static_cast<jint>(res);
}

JNIEXPORT jint JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamStartWithFormat(
        JNIEnv* /* env */, jobject /* thiz */, jint fd, jint endpoint,
        jint interfaceNumber, jint altSetting, jint sampleRate, jint channels, jint bytesPerSample) {
    const int bps = (bytesPerSample == 3 || bytesPerSample == 4) ? static_cast<int>(bytesPerSample) : 2;
    auto res = pulsr::UsbAudioSink::instance().Open(
               fd, endpoint, interfaceNumber, altSetting, sampleRate, channels, bps);
    return static_cast<jint>(res);
}

JNIEXPORT jintArray JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbQuerySupportedRates(
        JNIEnv* env, jobject /* thiz */, jint fd, jint interfaceNumber) {
    std::vector<int> rates = pulsr::UsbAudioSink::QuerySupportedRates(fd, interfaceNumber);
    jintArray result = env->NewIntArray(static_cast<jsize>(rates.size()));
    if (result != nullptr && !rates.empty()) {
        env->SetIntArrayRegion(result, 0, static_cast<jsize>(rates.size()),
                               reinterpret_cast<const jint*>(rates.data()));
    }
    return result;
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamStop(
        JNIEnv* /* env */, jobject /* thiz */) {
    pulsr::UsbAudioSink::instance().Close();
}

JNIEXPORT jboolean JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamIsActive(
        JNIEnv* /* env */, jobject /* thiz */) {
    return pulsr::UsbAudioSink::instance().IsActive() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamGetLastError(
        JNIEnv* /* env */, jobject /* thiz */) {
    return pulsr::UsbAudioSink::instance().GetLastError();
}

JNIEXPORT jlong JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamGetUnderrunCount(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jlong>(pulsr::UsbAudioSink::instance().GetUnderrunCount());
}

JNIEXPORT jlong JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamGetOverrunCount(
        JNIEnv* /* env */, jobject /* thiz */) {
    return static_cast<jlong>(pulsr::UsbAudioSink::instance().GetOverrunCount());
}

JNIEXPORT jdouble JNICALL
Java_com_pulsr_music_UsbExclusivePlugin_nativeUsbStreamGetBufferedMs(
        JNIEnv* /* env */, jobject /* thiz */) {
    return pulsr::UsbAudioSink::instance().GetBufferedMs();
}

} // extern "C"
