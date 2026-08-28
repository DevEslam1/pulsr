cmake_minimum_required(VERSION 3.22.1)
project(pulsr_dsp_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(DSP_SRCS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ParametricEQ.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/Crossfeed.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/LookaheadLimiter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ConvolutionReverb.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SincResampler.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/DsdDecoder.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/SpatialPanner.cpp
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
)

add_executable(test_reverb_equivalence
    test_reverb_equivalence.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/ConvolutionReverb.cpp
)

add_executable(test_dsd_dc_soak
    test_dsd_dc_soak.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/DsdDecoder.cpp
)

add_executable(test_dsp_stress
    test_dsp_stress.cpp
    ${DSP_SRCS}
)
