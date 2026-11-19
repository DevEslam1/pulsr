# android/app/src/test/cpp/extra_tests/tapsrc.cmake
#
# Tap sample-rate conversion: HighQualityResampler.
#
# The class is standalone (no AudioDspEngine, no SincResampler, no reverb
# dependency), so the target links exactly the unit under test plus its test.
# Keeping it out of DSP_SRCS also keeps the parity build honest: nothing about
# the convolution reverb's resampler changes.

pulsr_add_test(test_high_quality_resampler ${MAIN_CPP}/HighQualityResampler.cpp)

# Pure DSP component, so the strict warning set is applied per target and does
# not leak into the DSP sources, which keep the parity flags from CMakeLists.txt.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(test_high_quality_resampler PRIVATE -Wall -Wextra)
endif()
