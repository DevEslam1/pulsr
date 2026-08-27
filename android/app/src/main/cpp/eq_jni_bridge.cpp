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
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().eq().setEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBandCount(
        JNIEnv* /* env */, jobject /* thiz */, jint count) {
    AudioDspEngine::instance().eq().setBandCount(count);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqBand(
        JNIEnv* /* env */, jobject /* thiz */,
        jint index, jdouble freq, jdouble gainDb, jdouble q, jint type, jboolean enabled) {
    AudioDspEngine::instance().eq().setBand(
            index, freq, gainDb, q, static_cast<FilterType>(type), enabled);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetEqPreamp(
        JNIEnv* /* env */, jobject /* thiz */, jdouble preampDb) {
    AudioDspEngine::instance().eq().setPreamp(preampDb);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().crossfeed().setEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetCrossfeedParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble delayUs, jdouble feedDb) {
    AudioDspEngine::instance().crossfeed().configure(delayUs, feedDb);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().limiter().setEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetLimiterParams(
        JNIEnv* /* env */, jobject /* thiz */, jdouble lookaheadMs, jdouble thresholdDb, jdouble releaseMs) {
    AudioDspEngine::instance().limiter().configure(lookaheadMs, thresholdDb, releaseMs);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().reverb().setEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbPreset(
        JNIEnv* /* env */, jobject /* thiz */, jint preset) {
    AudioDspEngine::instance().reverb().setPreset(static_cast<ReverbPreset>(preset));
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetReverbWetDry(
        JNIEnv* /* env */, jobject /* thiz */, jfloat wetRatio) {
    AudioDspEngine::instance().reverb().setWetDry(wetRatio);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeLoadImpulseResponse(
        JNIEnv* env, jobject /* thiz */, jfloatArray irSamples) {
    if (!irSamples) return;
    jsize len = env->GetArrayLength(irSamples);
    jfloat* data = env->GetFloatArrayElements(irSamples, nullptr);
    if (data) {
        AudioDspEngine::instance().reverb().loadCustomIR(data, len);
        env->ReleaseFloatArrayElements(irSamples, data, JNI_ABORT);
    }
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetStereoBalance(
        JNIEnv* /* env */, jobject /* thiz */, jdouble balance) {
    AudioDspEngine::instance().panner().setBalance(balance);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetMonoMix(
        JNIEnv* /* env */, jobject /* thiz */, jboolean mono) {
    AudioDspEngine::instance().panner().setMono(mono);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerEnabled(
        JNIEnv* /* env */, jobject /* thiz */, jboolean enabled) {
    AudioDspEngine::instance().resampler().setEnabled(enabled);
}

JNIEXPORT void JNICALL
Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerRates(
        JNIEnv* /* env */, jobject /* thiz */, jdouble inRate, jdouble outRate) {
    AudioDspEngine::instance().resampler().setRates(inRate, outRate);
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
    env->ReleaseFloatArrayElements(buffer, data, 0); // 0 = commit back to Java array
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

    auto dsdBitOrder = (bitOrder == 1) ? DsdDecoder::DsdBitOrder::LSB_FIRST : DsdDecoder::DsdBitOrder::MSB_FIRST;
    AudioDspEngine::instance().dsdDecoder().configure(
            static_cast<DsdDecoder::DsdRate>(dsdRate), targetPcmSampleRate, dsdBitOrder);

    int dsdSampleRate = (dsdRate == 64) ? 2822400 : ((dsdRate == 128) ? 5644800 : 11289600);
    int decimationRatio = (targetPcmSampleRate > 0) ? std::max(1, dsdSampleRate / targetPcmSampleRate) : 16;
    int maxOutFrames = (byteCount * 8 / decimationRatio) + 64;
    std::vector<float> pcmOut(maxOutFrames * 2);

    int actualFrames = AudioDspEngine::instance().dsdDecoder().decodeDsdBytes(
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
Java_com_pulsr_music_AudioEffectsPlugin_nativeReset(
        JNIEnv* /* env */, jobject /* thiz */) {
    AudioDspEngine::instance().reset();
}

} // extern "C"
