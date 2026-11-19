# Contract C test registration (additive; CMakeLists.txt itself is untouched).
#
# Both components are new translation units, so each test links only the sources it
# needs. FftUtil.h is header-only and comes in through MAIN_CPP on the include path.
pulsr_add_test(test_oversampler ${MAIN_CPP}/Oversampler.cpp)
# test_sdm's reference chain feeds PCM through the public Oversampler, so it links
# both translation units.
pulsr_add_test(test_sdm ${MAIN_CPP}/SdmModulator.cpp ${MAIN_CPP}/Oversampler.cpp)
