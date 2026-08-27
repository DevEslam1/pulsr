cmake_minimum_required(VERSION 3.22.1)
project("pulsr_dsp")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(-O3 -ffast-math -Wall -Wextra)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_compile_options(-fsanitize=address,undefined)
    add_link_options(-fsanitize=address,undefined)
endif()

add_library(pulsr_dsp SHARED
    ParametricEQ.cpp
    Crossfeed.cpp
    LookaheadLimiter.cpp
    ConvolutionReverb.cpp
    SincResampler.cpp
    DsdDecoder.cpp
    SpatialPanner.cpp
    AudioDspEngine.cpp
    eq_jni_bridge.cpp
)

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(pulsr_dsp
    ${log-lib}
    ${android-lib}
    m
)
