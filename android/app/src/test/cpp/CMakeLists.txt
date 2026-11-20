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
if(WIN32)
    add_link_options(-static)
endif()

# Fast float32 recurrence and SIMD for biquad stages (ParametricEQ, DynamicEQ, LoudnessContour, ViperDdc)
option(PULSR_F32_BIQUADS "Enable float32 fast path for biquad filter stages" OFF)
if(PULSR_F32_BIQUADS)
    add_compile_definitions(PULSR_F32_BIQUADS=1)
endif()

# Opt-in ASan/UBSan for the sanitizer pass. Enabled by the gradle
# testNative task via -DPULSR_TEST_SANITIZERS=ON; not part of the parity build.
option(PULSR_TEST_SANITIZERS "Build native DSP tests with ASan/UBSan" OFF)
# Windows toolchain ships no working ASan runtime (the dynamic DLL aborts before
# main), but UBSan works when linked statically. This option provides the
# memory-safety-adjacent evidence locally while CI runs full ASan on Linux.
option(PULSR_TEST_UBSAN "Build native DSP tests with UBSan only" OFF)
if(PULSR_TEST_UBSAN)
    add_compile_options(-fsanitize=undefined -fno-sanitize=vptr -fno-omit-frame-pointer)
    add_link_options(-fsanitize=undefined)
endif()
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
    ${MAIN_CPP}/HighQualityResampler.cpp
    ${MAIN_CPP}/DsdDecoder.cpp
    ${MAIN_CPP}/DsdNativePacker.cpp
    ${MAIN_CPP}/Uac2Descriptors.cpp
    ${MAIN_CPP}/SpatialPanner.cpp
    ${MAIN_CPP}/HarmonicSaturation.cpp
    ${MAIN_CPP}/StereoWidth.cpp
    ${MAIN_CPP}/LoudnessContour.cpp
    ${MAIN_CPP}/SubCrossover.cpp
    ${MAIN_CPP}/ChannelManager.cpp
    ${MAIN_CPP}/DacVoicing.cpp
    ${MAIN_CPP}/DynamicEQ.cpp
    ${MAIN_CPP}/MultibandCompressor.cpp
    ${MAIN_CPP}/DynamicBass.cpp
    ${MAIN_CPP}/ViperDdc.cpp
    ${MAIN_CPP}/ArbitraryResponseEq.cpp
    ${MAIN_CPP}/LiveProg.cpp
    ${MAIN_CPP}/CustodyVerifier.cpp
    ${MAIN_CPP}/HrtfBinaural.cpp
    ${MAIN_CPP}/AudioDspEngine.cpp
    ${MAIN_CPP}/UsbAudioSink.cpp
    ${MAIN_CPP}/UsbPullRenderer.cpp
    ${MAIN_CPP}/UsbAsrcClockSync.cpp
    ${MAIN_CPP}/UsbPcmProducer.cpp
    ${MAIN_CPP}/Oversampler.cpp
    ${MAIN_CPP}/SdmModulator.cpp
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
pulsr_add_test(test_transport_gain ${DSP_SRCS})
pulsr_add_test(test_tap_src ${DSP_SRCS})
pulsr_add_test(test_custody_verifier ${DSP_SRCS})
pulsr_add_test(test_usb_sink ${DSP_SRCS})
pulsr_add_test(test_safety_bypass ${DSP_SRCS})
pulsr_add_test(test_aaudio_sink_support)
pulsr_add_test(test_sink_quantizer)
pulsr_add_test(test_usb_gap_fader)
pulsr_add_test(test_usb_pcm_producer ${MAIN_CPP}/UsbPcmProducer.cpp ${MAIN_CPP}/UsbPullRenderer.cpp)
pulsr_add_test(test_ir_bounds)

# ConvolutionReverb resamples its wet path above 48 kHz, so it never links alone.
set(REVERB_SRCS
    ${MAIN_CPP}/ConvolutionReverb.cpp
    ${MAIN_CPP}/SincResampler.cpp
)

pulsr_add_test(test_reverb_regression ${REVERB_SRCS})
# Item 2: direct-IR (<= 1024 tap) crossfade completion.
pulsr_add_test(test_reverb_direct_crossfade ${REVERB_SRCS})
pulsr_add_test(test_reverb_equivalence ${REVERB_SRCS})
pulsr_add_test(test_reverb_fft ${REVERB_SRCS})

pulsr_add_test(test_dsd_dc_soak ${MAIN_CPP}/DsdDecoder.cpp)
pulsr_add_test(test_dsd_decoder_correctness ${MAIN_CPP}/DsdDecoder.cpp)
pulsr_add_test(test_dsd_dynamic_cic ${MAIN_CPP}/DsdDecoder.cpp)
pulsr_add_test(test_engine_registry ${DSP_SRCS})

pulsr_add_test(test_limiter_true_peak ${MAIN_CPP}/LookaheadLimiter.cpp)
# Item 1: a sample-rate change on an active limiter must re-prime, not go silent.
pulsr_add_test(test_limiter_rate_change ${MAIN_CPP}/LookaheadLimiter.cpp)
# Item 1: reset() on a live limiter must re-prime, not emit one lookahead window of silence.
pulsr_add_test(test_limiter_reset_live ${MAIN_CPP}/LookaheadLimiter.cpp)
# Item 4: the range table must survive SanitizeSnapshot and every stage clamp.
pulsr_add_test(test_param_ranges ${DSP_SRCS})
# Item 3: DoP underrun silence is a pure helper (header only).
pulsr_add_test(test_dop_silence)

pulsr_add_test(test_sinc_resampler ${MAIN_CPP}/SincResampler.cpp)
pulsr_add_test(test_dop_framer ${MAIN_CPP}/DopFramer.cpp)
pulsr_add_test(test_resampler_polyphase ${MAIN_CPP}/SincResampler.cpp)

pulsr_add_test(test_channel_manager ${MAIN_CPP}/ChannelManager.cpp)
pulsr_add_test(test_dac_voicing ${DSP_SRCS})
pulsr_add_test(test_dither_hires ${DSP_SRCS})
pulsr_add_test(test_dsp_effects ${DSP_SRCS})
pulsr_add_test(test_rtf_governor ${DSP_SRCS})

pulsr_add_test(test_rg_dop ${DSP_SRCS})

# USB clock-domain / pull renderer / ASRC / parser fuzz cores.
pulsr_add_test(test_usb_pull_renderer ${MAIN_CPP}/UsbPullRenderer.cpp)
pulsr_add_test(test_usb_asrc ${MAIN_CPP}/UsbAsrcClockSync.cpp)
pulsr_add_test(test_usb_fuzz ${DSP_SRCS})

# Additive test targets live in extra_tests/*.cmake so parallel workstreams never
# edit this file. Each include may call pulsr_add_test() and may use DSP_SRCS /
# MAIN_CPP from this scope.
file(GLOB PULSR_EXTRA_TEST_CMAKE "${CMAKE_CURRENT_SOURCE_DIR}/extra_tests/*.cmake")
foreach(extra_cmake ${PULSR_EXTRA_TEST_CMAKE})
    include(${extra_cmake})
endforeach()
