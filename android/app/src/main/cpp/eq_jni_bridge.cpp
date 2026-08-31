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
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->eq.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBandCount(
        JNIEnv* /* env */, jobject /* thiz */, jint count) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->eq.bandCount = std::clamp(static_cast<int>(count), 1, EqParamSet::MAX_BANDS);
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBand(
        JNIEnv* /* env */, jobject /* thiz */,
        jint index, jdouble freq, jdouble gainDb, jdouble q, jint type, jboolean enabled) {
    if (index < 0 || index >= EqParamSet::MAX_BANDS) return;
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    if (index >= updated->eq.bandCount) updated->eq.bandCount = index + 1;

    updated->eq.bands[index].frequency = freq;
    updated->eq.bands[index].gainDb = gainDb;
    updated->eq.bands[index].q = q;
    updated->eq.bands[index].type = static_cast<FilterType>(type);
    updated->eq.bands[index].enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
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

    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->eq.bandCount = static_cast<int>(count);
    for (int i = 0; i < count; ++i) {
        updated->eq.bands[i].frequency = freqs[i];
        updated->eq.bands[i].gainDb = gains[i];
        updated->eq.bands[i].q = qs ? qs[i] : 1.414;
        updated->eq.bands[i].type = types ? static_cast<FilterType>(types[i]) : FilterType::Peaking;
        updated->eq.bands[i].enabled = true;
    }
    // Single atomic publish — 1 generation bump vs 32
    AudioDspEngine::instance().publishParams(updated);

    env->ReleaseDoubleArrayElements(jFreqs, freqs, JNI_ABORT);
    env->ReleaseDoubleArrayElements(jGains, gains, JNI_ABORT);
    if (qs && jQs) env->ReleaseDoubleArrayElements(jQs, qs, JNI_ABORT);
    if (types && jTypes) env->ReleaseIntArrayElements(jTypes, types, JNI_ABORT);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetBandSolo(
        JNIEnv* /* env */, jobject /* thiz */, jint index, jboolean solo) {
    if (index < 0 || index >= EqParamSet::MAX_BANDS) return;
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->eq.bands[index].solo = solo;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetBandMute(
        JNIEnv* /* env */, jobject /* thiz */, jint index, jboolean mute) {
    if (index < 0 || index >= EqParamSet::MAX_BANDS) return;
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->eq.bands[index].mute = mute;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqPreamp(
        JNIEnv* /* env */, jobject /* thiz */, jdouble preampDb) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->eq.preampDb = preampDb;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->crossfeed.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble delayUs, jdouble feedDb) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->crossfeed.delayUs = delayUs;
    updated->crossfeed.feedDb = feedDb;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedFcut(
        JNIEnv* /* env */, jobject /* thiz */, jdouble fcut) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->crossfeed.fcut = fcut;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->limiter.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble lookaheadMs, jdouble thresholdDb, jdouble releaseMs) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->limiter.lookaheadMs = lookaheadMs;
    updated->limiter.thresholdDb = thresholdDb;
    updated->limiter.releaseMs = releaseMs;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterTruePeak(
        JNIEnv* /* env */, jobject /* thiz */, jboolean truePeak) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->limiter.truePeakMode = truePeak;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->reverb.enabled = enabled;
    if (enabled && !updated->reverb.preparedIr && updated->reverb.preset != static_cast<int>(ReverbPreset::Custom)) {
        updated->reverb.preparedIr = PreparedIr::createSynthetic(
            current->sampleRate, updated->reverb.preset, static_cast<float>(updated->reverb.damping));
    }
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbPreset(
        JNIEnv* /* env */, jobject /* thiz */, jint preset) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->reverb.preset = preset;
    updated->reverb.preparedIr = PreparedIr::createSynthetic(
        current->sampleRate, preset, static_cast<float>(current->reverb.damping));
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbWetDry(
        JNIEnv* /* env */, jobject /* thiz */, jfloat wetRatio) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->reverb.wetDry = static_cast<double>(wetRatio);
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbPredelay(
        JNIEnv* /* env */, jobject /* thiz */, jdouble predelayMs) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->reverb.predelayMs = predelayMs;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbDamping(
        JNIEnv* /* env */, jobject /* thiz */, jdouble damping) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->reverb.damping = damping;
    if (updated->reverb.preset != static_cast<int>(ReverbPreset::Custom)) {
        updated->reverb.preparedIr = PreparedIr::createSynthetic(
            current->sampleRate, updated->reverb.preset, static_cast<float>(damping));
    }
    AudioDspEngine::instance().publishParams(updated);
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
    auto customIr = PreparedIr::createCustom(current->sampleRate, data, frames, channels);
    env->ReleaseFloatArrayElements(irSamples, data, JNI_ABORT);

    if (customIr) {
        auto updated = std::make_shared<DspParamSnapshot>(*current);
        updated->reverb.preset = static_cast<int>(ReverbPreset::Custom);
        updated->reverb.preparedIr = customIr;
        AudioDspEngine::instance().publishParams(updated);
        return JNI_TRUE;
    }
    return JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoBalance(
        JNIEnv* /* env */, jobject /* thiz */, jdouble balance) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->panner.balance = balance;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetMonoMix(
        JNIEnv* /* env */, jobject /* thiz */, jboolean mono) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->panner.monoMix = mono;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->resampler.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerRates(
        JNIEnv* /* env */, jobject /* thiz */, jdouble inRate, jdouble outRate) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->resampler.inRate = inRate;
    updated->resampler.outRate = outRate;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT jint JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeProcessAudio(
        JNIEnv* env, jobject /* thiz */, jfloatArray buffer, jint frames, jint channels) {
    if (!buffer || frames <= 0 || channels < 1 || channels > 8) return 0;
    jsize arrayLen = env->GetArrayLength(buffer);
    jsize requiredLen = static_cast<jsize>(frames) * channels;
    if (arrayLen < requiredLen) {
        frames = static_cast<jint>(arrayLen / channels);
        if (frames <= 0) return 0;
    }
    jfloat* data = env->GetFloatArrayElements(buffer, nullptr);
    if (!data) return 0;
    int outFrames = AudioDspEngine::instance().processInterleaved(data, frames, channels);
    env->ReleaseFloatArrayElements(buffer, data, 0); // commit back to Java array
    return static_cast<jint>(outFrames);
}

JNIEXPORT jfloatArray JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeDecodeDsd(
        JNIEnv* env, jobject /* thiz */,
        jbyteArray dsdL, jbyteArray dsdR, jint byteCount, jint dsdRate, jint targetPcmSampleRate, jint bitOrder) {
    if (!dsdL || !dsdR || byteCount <= 0) return nullptr;

    jbyte* lData = env->GetByteArrayElements(dsdL, nullptr);
    jbyte* rData = env->GetByteArrayElements(dsdR, nullptr);
    if (!lData || !rData) {
        if (lData) env->ReleaseByteArrayElements(dsdL, lData, JNI_ABORT);
        if (rData) env->ReleaseByteArrayElements(dsdR, rData, JNI_ABORT);
        return nullptr;
    }

    auto dsdBitOrder = (bitOrder == 0) ? DsdDecoder::DsdBitOrder::LSB_FIRST : DsdDecoder::DsdBitOrder::MSB_FIRST;
    auto& dsd = AudioDspEngine::instance().dsdDecoder();
    dsd.configure(
            static_cast<DsdDecoder::DsdRate>(dsdRate), targetPcmSampleRate, dsdBitOrder);

    int maxOutFrames = dsd.getExpectedPcmFrames(byteCount);
    std::vector<float> pcmOut(maxOutFrames * 2);

    int actualFrames = dsd.decodeDsdBytes(
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
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->saturation.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSaturationParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble drive, jdouble mix, jdouble tilt) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->saturation.drive = drive;
    updated->saturation.mix = mix;
    updated->saturation.tilt = tilt;
    AudioDspEngine::instance().publishParams(updated);
}

// ---- Phase 1 DSP expansion: Stereo Width (Mid/Side) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoWidthEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->stereoWidth.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoWidthParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble width) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->stereoWidth.width = width;
    AudioDspEngine::instance().publishParams(updated);
}

// ---- Phase 1 DSP expansion: Loudness Contour (Fletcher-Munson) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLoudnessContourEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->loudness.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLoudnessContourParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble intensity, jdouble volumeLinear) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->loudness.intensity = intensity;
    updated->loudness.volumeLinear = volumeLinear;
    AudioDspEngine::instance().publishParams(updated);
}

// ---- Phase 1 DSP expansion: Subwoofer / LFE Crossover (bass redirection) ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSubCrossoverEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->subCrossover.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSubCrossoverParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble cornerHz, jdouble slopeDbPerOct, jdouble subGain) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->subCrossover.cornerHz = cornerHz;
    updated->subCrossover.slopeDbPerOct = slopeDbPerOct;
    updated->subCrossover.subGain = subGain;
    AudioDspEngine::instance().publishParams(updated);
}

// ---- Phase 1 DSP expansion: Dynamic EQ ----

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicEqEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->dynamicEq.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicEqBandCount(
        JNIEnv* /* env */, jobject /* thiz */, jint count) {
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    updated->dynamicEq.bandCount = std::clamp(static_cast<int>(count), 0, DynamicEqParamSet::MAX_BANDS);
    AudioDspEngine::instance().publishParams(updated);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDynamicEqBand(
        JNIEnv* /* env */, jobject /* thiz */,
        jint index, jdouble freq, jdouble q, jdouble thresholdDb, jdouble ratio,
        jdouble attackMs, jdouble releaseMs, jdouble maxCutDb, jboolean enabled) {
    if (index < 0 || index >= DynamicEqParamSet::MAX_BANDS) return;
    auto current = AudioDspEngine::instance().getParams();
    auto updated = std::make_shared<DspParamSnapshot>(*current);
    if (index >= updated->dynamicEq.bandCount) updated->dynamicEq.bandCount = index + 1;

    auto& band = updated->dynamicEq.bands[index];
    band.frequency = freq;
    band.q = q;
    band.thresholdDb = thresholdDb;
    band.ratio = ratio;
    band.attackMs = attackMs;
    band.releaseMs = releaseMs;
    band.maxCutDb = maxCutDb;
    band.enabled = enabled;
    AudioDspEngine::instance().publishParams(updated);
}

// ---- PCM Audio Processing for per-frame DSP ----

JNIEXPORT jint JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeProcessPcmAudio(
        JNIEnv* env, jobject /* thiz */,
        jfloatArray jBuffer, jint frameCount, jint channels) {
    if (!jBuffer || frameCount <= 0 || channels <= 0) {
        LOGE("nativeProcessPcmAudio: invalid parameters - frameCount=%d, channels=%d", frameCount, channels);
        return 0;
    }

    // Get the float array from Java
    jfloat* javaBuffer = env->GetFloatArrayElements(jBuffer, nullptr);
    if (!javaBuffer) {
        LOGE("nativeProcessPcmAudio: failed to get float array elements");
        return 0;
    }

    try {
        // Process the PCM audio through the DSP engine
        // The buffer is expected to be interleaved: L, R, L, R, ... for stereo
        // or single channel depending on the channels parameter
        int processedFrames = AudioDspEngine::instance().processInterleaved(
            javaBuffer,
            frameCount,
            channels
        );
        
        // Release the array elements, copying back the modified buffer
        env->ReleaseFloatArrayElements(jBuffer, javaBuffer, 0);
        
        return processedFrames;
    } catch (const std::exception& e) {
        LOGE("nativeProcessPcmAudio: exception - %s", e.what());
        env->ReleaseFloatArrayElements(jBuffer, javaBuffer, JNI_ABORT);
        return 0;
    }
}

} // extern "C"
