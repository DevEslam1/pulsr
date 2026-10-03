cmake_minimum_required(VERSION 3.22.1)
project(pulsr_dsp_tests CXX)

# Must match main/cpp/CMakeLists.txt: the DSP sources are shared, so a lower
# standard here compiles different code than production ships.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Parity build: match production compiler flags so the tests exercise the same
# optimized code the app ships (main/cpp uses -O3 -fno-strict-aliasing).
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()
add_compile_options(-fno-strict-aliasing)
set(CMAKE_CXX_FLAGS_RELEASE "-O3")

# Opt-in ASan/UBSan for the sanitizer pass. Enabled by the gradle
# testNative task via -DPULSR_TEST_SANITIZERS=ON; not part of the parity build.
option(PULSR_TEST_SANITIZERS "Build native DSP tests with ASan/UBSan" OFF)
if(PULSR_TEST_SANITIZERS)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
    # Android's uninstrumented libc++ exposes std::__ndk1 RTTI while the vptr
    # instrumentation expects std::ostream RTTI. This aborts before test code
    # runs; retain ASan and the other UB checks on Android, and full vptr
    # checking on host builds.
    if(ANDROID)
        add_compile_options(-fno-sanitize=vptr)
    endif()
endif()

enable_testing()

# Also allow this suite to run on an Android emulator/device with the NDK.
if(ANDROID)
    link_libraries(log)
endif()

set(MAIN_CPP ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp)

# Every translation unit AudioDspEngine links against. Keep in sync with the
# pulsr_dsp target in main/cpp/CMakeLists.txt (minus eq_jni_bridge.cpp, which
# needs the JNI headers and has no host-testable logic).
set(DSP_SRCS
    ${MAIN_CPP}/ParametricEQ.cpp
    ${MAIN_CPP}/Crossfeed.cpp
    ${MAIN_CPP}/LookaheadLimiter.cpp
    ${MAIN_CPP}/ConvolutionReverb.cpp
    ${MAIN_CPP}/SincResampler.cpp
    ${MAIN_CPP}/DsdDecoder.cpp
    ${MAIN_CPP}/SpatialPanner.cpp
    ${MAIN_CPP}/HarmonicSaturation.cpp
    ${MAIN_CPP}/StereoWidth.cpp
    ${MAIN_CPP}/LoudnessContour.cpp
    ${MAIN_CPP}/SubCrossover.cpp
    ${MAIN_CPP}/DynamicEQ.cpp
    ${MAIN_CPP}/MultibandCompressor.cpp
    ${MAIN_CPP}/DynamicBass.cpp
    ${MAIN_CPP}/ViperDdc.cpp
    ${MAIN_CPP}/ArbitraryResponseEq.cpp
    ${MAIN_CPP}/LiveProg.cpp
    ${MAIN_CPP}/AudioDspEngine.cpp
    ${MAIN_CPP}/UsbAudioSink.cpp
)

include_directories(${MAIN_CPP})

# test_rt_alloc / test_sr_change / test_snapshot_race / test_custom_ir_budget
# have no main(); test_native_all.cpp #includes them as translation units.
function(pulsr_add_test name)
    add_executable(${name} ${name}.cpp ${ARGN})
    add_test(NAME ${name} COMMAND ${name})
endfunction()

pulsr_add_test(test_native_all ${DSP_SRCS})
pulsr_add_test(test_dsp_stress ${DSP_SRCS})
pulsr_add_test(test_bypass_transparency ${DSP_SRCS})

# ConvolutionReverb resamples its wet path above 48 kHz, so it never links alone.
set(REVERB_SRCS
    ${MAIN_CPP}/ConvolutionReverb.cpp
    ${MAIN_CPP}/SincResampler.cpp
)

pulsr_add_test(test_reverb_regression ${REVERB_SRCS})
pulsr_add_test(test_reverb_equivalence ${REVERB_SRCS})
pulsr_add_test(test_reverb_fft ${REVERB_SRCS})

pulsr_add_test(test_dsd_dc_soak ${MAIN_CPP}/DsdDecoder.cpp)
pulsr_add_test(test_dsd_decoder_correctness ${MAIN_CPP}/DsdDecoder.cpp)

pulsr_add_test(test_limiter_true_peak ${MAIN_CPP}/LookaheadLimiter.cpp)

pulsr_add_test(test_sinc_resampler ${MAIN_CPP}/SincResampler.cpp)
pulsr_add_test(test_dop_framer)
pulsr_add_test(test_resampler_polyphase ${MAIN_CPP}/SincResampler.cpp)

pulsr_add_test(test_dsp_effects
    ${REVERB_SRCS}
    ${MAIN_CPP}/LookaheadLimiter.cpp
    ${MAIN_CPP}/Crossfeed.cpp
    ${MAIN_CPP}/ParametricEQ.cpp
    ${MAIN_CPP}/DsdDecoder.cpp
    ${MAIN_CPP}/MultibandCompressor.cpp
    ${MAIN_CPP}/HarmonicSaturation.cpp
    ${MAIN_CPP}/StereoWidth.cpp
    ${MAIN_CPP}/DynamicEQ.cpp
    ${MAIN_CPP}/SubCrossover.cpp
    ${MAIN_CPP}/DynamicBass.cpp
)
