# android/app/src/test/cpp/extra_tests/uac2.cmake
#
# Contract A (UAC2 native-DSD probe + LSB-first DSD word packer) and Contract B
# (UAC2 hardware volume codec). Each component is standalone: no DSP_SRCS, no
# Android/JNI headers, so every target compiles and links exactly the
# translation unit under test plus its test.

pulsr_add_test(test_uac2_dsd_probe ${MAIN_CPP}/Uac2Descriptors.cpp)
pulsr_add_test(test_dsd_native_packer ${MAIN_CPP}/DsdNativePacker.cpp)
pulsr_add_test(test_uac2_volume ${MAIN_CPP}/Uac2Volume.cpp)

# All three are pure control-path components, so the strict warning set is
# applied per target: it must not leak into the DSP sources, which keep the
# parity flags from CMakeLists.txt.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    foreach(uac2_test test_uac2_dsd_probe test_dsd_native_packer test_uac2_volume)
        target_compile_options(${uac2_test} PRIVATE -Wall -Wextra)
    endforeach()
endif()
