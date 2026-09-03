cmake_minimum_required(VERSION 3.22.1)
project(pulsr_dsp_tests CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# test_native_all.cpp pulls in <windows.h> (PSAPI) for RSS profiling; without
# NOMINMAX its min/max macros break every std::min/std::max call under MSVC.
add_compile_definitions(NOMINMAX)

set(DSP_SRCS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ParametricEQ.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/Crossfeed.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/LookaheadLimiter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ConvolutionReverb.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SincResampler.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/DsdDecoder.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SpatialPanner.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/HarmonicSaturation.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/StereoWidth.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/LoudnessContour.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SubCrossover.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/DynamicEQ.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/AudioDspEngine.cpp
)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp)

add_executable(test_native_all
    test_native_all.cpp
    ${DSP_SRCS}
)

add_executable(test_reverb_regression
    test_reverb_regression.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ConvolutionReverb.cpp
    # ConvolutionReverb gained wet-path SincResampler taps — link them or the target no longer links.
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SincResampler.cpp
)

add_executable(test_reverb_equivalence
    test_reverb_equivalence.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ConvolutionReverb.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SincResampler.cpp
)

add_executable(test_dsd_dc_soak
    test_dsd_dc_soak.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/DsdDecoder.cpp
)

add_executable(test_dsp_stress
    test_dsp_stress.cpp
    ${DSP_SRCS}
)

add_executable(test_dsp_expansion
    test_dsp_expansion.cpp
    ${DSP_SRCS}
)

add_executable(test_limiter_mask_safety
    test_limiter_mask_safety.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/LookaheadLimiter.cpp
)

add_executable(test_eq_threshold_continuity
    test_eq_threshold_continuity.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ParametricEQ.cpp
)

add_executable(test_auto_degrade_hysteresis
    test_auto_degrade_hysteresis.cpp
    ${DSP_SRCS}
)
