// android/app/src/main/cpp/aaudio_jni_bridge.cpp
//
// JNI surface for Pulsr's native AAudio output sink. Bound to
// com.ryanheise.just_audio.AaudioNativeBridge (vendored just_audio fork).
// Lives inside libpulsr_dsp.so alongside the DSP chain so a single library
// serves both paths; the AAudio path intentionally bypasses the DSP chain
// (bit-perfect "Direct" output).
#include <android/log.h>
#include <jni.h>

#include <string>

#include "AAudioSink.h"

#define LOG_TAG "PulsrAAudioJni"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

namespace {

using pulsr::AAudioSink;

inline AAudioSink* AsSink(jlong handle) {
    return reinterpret_cast<AAudioSink*>(static_cast<intptr_t>(handle));
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeOpen(
    JNIEnv* /*env*/, jclass /*clazz*/, jint sampleRate, jint channelCount,
    jint encoding, jboolean preferExclusive, jint targetBufferMs) {
    AAudioSink::Config cfg;
    cfg.sampleRate = sampleRate;
    cfg.channelCount = channelCount;
    cfg.encoding = static_cast<AAudioSink::Encoding>(encoding);
    cfg.preferExclusive = preferExclusive == JNI_TRUE;
    cfg.targetBufferMs = targetBufferMs;
    auto* sink = new (std::nothrow) AAudioSink();
    if (sink == nullptr) return 0;
    std::string error;
    if (!sink->Open(cfg, &error)) {
        LOGW("nativeOpen failed: %s", error.c_str());
        delete sink;
        return 0;
    }
    return reinterpret_cast<jlong>(sink);
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeClose(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    auto* sink = AsSink(handle);
    if (sink == nullptr) return;
    sink->Close();
    delete sink;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeWrite(
    JNIEnv* env, jclass /*clazz*/, jlong handle, jobject directBuffer,
    jint offset, jint length) {
    auto* sink = AsSink(handle);
    if (sink == nullptr || directBuffer == nullptr) return -1;
    auto* addr = static_cast<uint8_t*>(
        env->GetDirectBufferAddress(directBuffer));
    if (addr == nullptr || length < 0 || offset < 0) return -1;
    return sink->Write(addr + offset, length);
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativePlay(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) sink->Play();
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativePause(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) sink->Pause();
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeFlush(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) sink->Flush();
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeGetFramesRead(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) return sink->FramesRead();
    return 0;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeGetFramesWritten(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) return sink->FramesWritten();
    return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeGetXRunCount(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) return sink->XRunCount();
    return 0;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeIsExclusive(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (auto* sink = AsSink(handle)) return sink->IsExclusive() ? JNI_TRUE : JNI_FALSE;
    return JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_audio_AaudioNativeBridge_nativeSetVolume(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle, jfloat volume) {
    if (auto* sink = AsSink(handle)) sink->SetVolume(volume);
}
