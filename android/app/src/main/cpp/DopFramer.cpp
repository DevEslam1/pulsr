// android/app/src/main/cpp/DopFramer.cpp
//
// C ABI exports for DopFramer.h so Dart (via dart:ffi on libpulsr_dsp.so) and
// native callers share one DoP v1.1 implementation with zero duplicate logic.
#include "DopFramer.h"

#include <cstdlib>

#if defined(_WIN32)
#define PULSR_DOP_EXPORT __declspec(dllexport)
#else
#define PULSR_DOP_EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

PULSR_DOP_EXPORT uint8_t* pulsr_dop_alloc(size_t bytes) {
    if (bytes == 0) bytes = 1;
    return static_cast<uint8_t*>(std::malloc(bytes));
}

PULSR_DOP_EXPORT void pulsr_dop_free(uint8_t* ptr) {
    std::free(ptr);
}

PULSR_DOP_EXPORT int32_t pulsr_dop_pcm_sample_rate(int32_t dsd_rate) {
    return pulsr::DopPcmSampleRate(dsd_rate);
}

PULSR_DOP_EXPORT int32_t pulsr_dop_frame_planar(
    const uint8_t* dsd_left,
    const uint8_t* dsd_right,
    size_t channel_bytes,
    int32_t container_bits,
    int32_t reverse_bits,
    uint8_t first_marker,
    uint8_t* out_buf,
    size_t out_capacity,
    size_t* out_bytes,
    uint8_t* next_marker) {
    const bool ok = pulsr::FrameDopPlanar(
        dsd_left,
        dsd_right,
        channel_bytes,
        container_bits,
        reverse_bits != 0,
        out_buf,
        out_capacity,
        out_bytes,
        first_marker,
        next_marker);
    return ok ? 1 : 0;
}

}  // extern "C"
