// android/app/src/main/cpp/aaudio_jni_bridge.cpp
//
// JNI surface for Pulsr's native AAudio output sink. Bound to
// com.ryanheise.just_audio.AaudioNativeBridge (vendored just_audio fork).
// Lives inside libpulsr_dsp.so alongside the DSP chain so a single library
// serves both paths; the AAudio path intentionally bypasses the DSP chain
// (bit-perfect "Direct" output).
#include <android/log.h>
#include <jni.h>

#include <mutex>
#include <new>
#include <shared_mutex>
#include <string>
#include <unordered_set>

#include "AAudioSink.h"

#define LOG_TAG "PulsrAAudioJni"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

namespace {

using pulsr::AAudioSink;

// Serialises handle registration/removal and nativeClose()'s teardown against
// every other call that uses the raw jlong handle (write/play/pause/flush/
// volume/queries). Shared for the hot write/query paths, unique for open
// registration and close extraction, so a sink can never be freed mid-call
// and stale or double-closed jlong handles never cause use-after-free.
std::shared_mutex gSinkLifecycleMutex;
std::unordered_set<AAudioSink*> gLiveSinks;

// Caller must hold gSinkLifecycleMutex (shared or unique).
inline AAudioSink* AsSink(jlong handle) {
    if (handle == 0) return nullptr;
    auto* candidate = reinterpret_cast<AAudioSink*>(static_cast<intptr_t>(handle));
    return gLiveSinks.find(candidate) != gLiveSinks.end() ? candidate : nullptr;
}

// RAII shared guard for the common entry points.
struct SinkReadLock {
    std::shared_lock<std::shared_mutex> lock{gSinkLifecycleMutex};
};

static jlong OpenSinkInternal(jint deviceId, jint sampleRate, jint channelCount,
                              jint encoding, jboolean preferExclusive, jint targetBufferMs) {
    AAudioSink::Config cfg;
    cfg.deviceId = deviceId;
    cfg.sampleRate = sampleRate;
    cfg.channelCount = channelCount;
    cfg.encoding = static_cast<AAudioSink::Encoding>(encoding);
    cfg.preferExclusive = preferExclusive == JNI_TRUE;
    cfg.targetBufferMs = targetBufferMs;
    auto* sink = new (std::nothrow) AAudioSink();
    if (sink == nullptr) return 0;
    std::string error;
    if (!sink->Open(cfg, &error)) {
        LOGW("OpenSinkInternal failed: %s", error.c_str());
        delete sink;
        return 0;
    }
    try {
        std::unique_lock<std::shared_mutex> lifeLock(gSinkLifecycleMutex);
        gLiveSinks.insert(sink);
    } catch (...) {
        sink->Close();
        delete sink;
        return 0;
    }
    return reinterpret_cast<jlong>(sink);
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeOpen(
    JNIEnv* /*env*/, jclass /*clazz*/, jint sampleRate, jint channelCount,
    jint encoding, jboolean preferExclusive, jint targetBufferMs) {
    return OpenSinkInternal(0, sampleRate, channelCount, encoding, preferExclusive, targetBufferMs);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeOpenForDevice(
    JNIEnv* /*env*/, jclass /*clazz*/, jint sampleRate, jint channelCount,
    jint encoding, jboolean preferExclusive, jint targetBufferMs, jint deviceId) {
    return OpenSinkInternal(deviceId, sampleRate, channelCount, encoding, preferExclusive, targetBufferMs);
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeClose(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (handle == 0) return;
    AAudioSink* sink = nullptr;
    {
        // Waiting on unique_lock drains any in-flight shared callers; the worst
        // case is bounded by AAudioSink::Write()'s 150 ms (3 x 50 ms) write
        // timeout. Erasing `sink` from gLiveSinks before releasing the lock
        // guarantees no stale, concurrent, or double-close call can resolve
        // this handle again (and avoids ABA before `delete sink`), while the
        // longer tail drain inside sink->Close() runs outside the lock.
        std::unique_lock<std::shared_mutex> lifeLock(gSinkLifecycleMutex);
        sink = AsSink(handle);
        if (sink == nullptr) return;
        gLiveSinks.erase(sink);
    }
    sink->Close();
    delete sink;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeWrite(
    JNIEnv* env, jclass /*clazz*/, jlong handle, jobject directBuffer,
    jint offset, jint length) {
    SinkReadLock lifeLock;
    auto* sink = AsSink(handle);
    if (sink == nullptr || directBuffer == nullptr) return -1;
    auto* addr = static_cast<uint8_t*>(
        env->GetDirectBufferAddress(directBuffer));
    if (addr == nullptr || length < 0 || offset < 0) return -1;
    // Validate buffer bounds to prevent overruns from untrusted offset/length.
    jlong capacity = env->GetDirectBufferCapacity(directBuffer);
    if (capacity < 0 || static_cast<jlong>(offset) + length > capacity) return -1;
    try {
        return sink->Write(addr + offset, length);
    } catch (...) {
        return -1;
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativePlay(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) sink->Play();
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativePause(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) sink->Pause();
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeFlush(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) sink->Flush();
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetFramesRead(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->FramesRead();
    return 0;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetFramesWritten(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->FramesWritten();
    return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetXRunCount(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->XRunCount();
    return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetXRunDelta(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->XRunDelta();
    return 0;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeIsExclusive(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->IsExclusive() ? JNI_TRUE : JNI_FALSE;
    return JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeSetVolume(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle, jfloat volume) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) sink->SetVolume(volume);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetOutputLatencyMs(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->GetOutputLatencyMs();
    return 0.0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetFramesPerBurst(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->FramesPerBurst();
    return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeGetDeviceId(
    JNIEnv*, jclass, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->DeviceId();
    return 0;
}

// Bit-perfect / DoP verdict for the live stream. AsSink + the shared lifecycle
// read lock, exactly like nativeSetVolume/nativeIsExclusive, so a concurrent
// nativeClose() cannot free the sink mid-call. SetBitPerfect() returns false
// (leaving the sink's bit-perfect flag off) when the request cannot be honoured
// on a non-exclusive stream.
extern "C" JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeSetBitPerfect(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle, jboolean bitPerfect, jboolean dop) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) {
        sink->SetBitPerfect(bitPerfect == JNI_TRUE, dop == JNI_TRUE);
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_ryanheise_just_1audio_AaudioNativeBridge_nativeIsBitPerfectSink(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    SinkReadLock lifeLock;
    if (auto* sink = AsSink(handle)) return sink->IsBitPerfectSink() ? JNI_TRUE : JNI_FALSE;
    return JNI_FALSE;
}
