cmake_minimum_required(VERSION 3.22.1)
project("pulsr_dsp")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(-Wall -Wextra)

# ASan/UBSan need the clang runtime (libclang_rt.asan-<abi>-android.so) to be
# packaged with the APK - it is not, so enabling this in a normal build makes
# libpulsr_dsp.so fail to dlopen ("libclang_rt.asan-x86_64-android.so not
# found") and silently disables all DSP. Opt in explicitly only if you also
# bundle the sanitizer runtime:
#   ./gradlew assembleYtmDebug -Pandroid.native.buildCmakeArgs="-DPULSR_DSP_WITH_ASAN=ON"
option(PULSR_DSP_WITH_ASAN "Build libpulsr_dsp with ASan/UBSan (requires bundling the sanitizer runtime)" OFF)
if(PULSR_DSP_WITH_ASAN)
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
    HarmonicSaturation.cpp
    StereoWidth.cpp
    LoudnessContour.cpp
    SubCrossover.cpp
    DynamicEQ.cpp
    AudioDspEngine.cpp
    eq_jni_bridge.cpp
)

target_compile_options(pulsr_dsp PRIVATE
    $<$<CONFIG:Debug>:-O0 -g>
    $<$<CONFIG:RelWithDebInfo>:-O2 -g>
    $<$<CONFIG:Release>:-O3>
)

find_library(log-lib log)
find_library(android-lib android)

target_link_options(pulsr_dsp PRIVATE
    "-Wl,-z,max-page-size=16384"
)

target_link_libraries(pulsr_dsp
    ${log-lib}
    ${android-lib}
    m
)
