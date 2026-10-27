cmake_minimum_required(VERSION 3.22)
project("pulsr_dsp")

# Ensure C++20 standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Ignore/unset Windows CMAKE_INSTALL_PREFIX on Android builds
if(ANDROID)
    set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Default install path" FORCE)
    # P0-1: Android 15+ 16 KB memory-page size compatibility
    add_link_options(-Wl,-z,max-page-size=16384)
endif()

# Global linker flags: garbage collect unused sections across all configurations
add_link_options(-Wl,--gc-sections)

# Base compile options
add_compile_options(
    -Wall
    -Wextra
    -Werror=return-type
    -fno-strict-aliasing
    -fno-math-errno
)

# ASan/UBSan need the clang runtime (libclang_rt.asan-<abi>-android.so) to be
# packaged with the APK - it is not, so enabling this in a normal build makes
# libpulsr_dsp.so fail to dlopen ("libclang_rt.asan-x86_64-android.so not
# found") and silently disables all DSP. Opt in explicitly only if you also
# bundle the sanitizer runtime:
#   ./gradlew assembleYtmDebug -Pandroid.native.buildCmakeArgs="-DPULSR_DSP_WITH_ASAN=ON"
option(PULSR_DSP_WITH_ASAN "Build libpulsr_dsp with ASan/UBSan (requires bundling the sanitizer runtime)" OFF)
if(PULSR_DSP_WITH_ASAN)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

# NEON tuning for armeabi-v7a if targeted
if(ANDROID_ABI STREQUAL "armeabi-v7a")
    add_compile_options(-mfpu=neon-vfpv4 -mfloat-abi=softfp)
endif()

# Fast float32 recurrence and SIMD for biquad stages (ParametricEQ, DynamicEQ, LoudnessContour, ViperDdc)
option(PULSR_F32_BIQUADS "Enable float32 fast path for biquad filter stages" ON)
if(PULSR_F32_BIQUADS)
    add_compile_definitions(PULSR_F32_BIQUADS=1)
endif()

set(DSP_CORE_SOURCES
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
    ChannelManager.cpp
    DynamicEQ.cpp
    MultibandCompressor.cpp
    DynamicBass.cpp
    ViperDdc.cpp
    ArbitraryResponseEq.cpp
    LiveProg.cpp
    AudioDspEngine.cpp
    AAudioSink.cpp
    UsbAudioSink.cpp
)

set(JNI_BRIDGE_SOURCES
    eq_jni_bridge.cpp
    aaudio_jni_bridge.cpp
)

add_library(pulsr_dsp SHARED
    ${DSP_CORE_SOURCES}
    ${JNI_BRIDGE_SOURCES}
)

# Disable RTTI and exceptions on DSP core translation units.
# JNI bridges retain exceptions to safely catch std::bad_alloc/runtime exceptions at bridge boundary.
set_source_files_properties(${DSP_CORE_SOURCES} PROPERTIES
    COMPILE_FLAGS "-fno-exceptions -fno-rtti"
)

# Configuration-specific optimization flags:
# - Debug: -O1 -g (instead of -O0) so real-time audio deadlines are testable on device without buffer underruns
# - Release / RelWithDebInfo: -O3 -flto=thin with linker LTO
target_compile_options(pulsr_dsp PRIVATE
    $<$<CONFIG:Debug>:-O1 -g>
    $<$<CONFIG:RelWithDebInfo>:-O3 -g -flto=thin>
    $<$<CONFIG:Release>:-O3 -flto=thin>
)

target_link_options(pulsr_dsp PRIVATE
    $<$<CONFIG:RelWithDebInfo>:-flto=thin -Wl,--lto-O3>
    $<$<CONFIG:Release>:-flto=thin -Wl,--lto-O3>
)

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(pulsr_dsp
    ${log-lib}
    ${android-lib}
    aaudio
    m
)
