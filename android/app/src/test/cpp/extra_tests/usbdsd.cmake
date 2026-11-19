# android/app/src/test/cpp/extra_tests/usbdsd.cmake
#
# Native-DSD (DSD_U32) USB producer path: sink admission, 32-bit packing, gap
# silence and the PCM/DSD API exclusion. The test drives the sink's ring and
# packet filler directly (same UsbAudioSinkTestAccess approach as
# test_usb_sink.cpp), so no DAC and no usbfs are needed.
#
# UsbAudioSink.cpp now calls pulsr::DsdRateForAltSetting() (Uac2Descriptors.cpp)
# and pulsr::PackDsdBitsToWords() (DsdNativePacker.cpp). DSP_SRCS in
# CMakeLists.txt lists neither translation unit, so every target that compiles
# the sink has to get them appended here. This block is the stopgap for a file
# this workstream does not own: the permanent fix is adding both TUs to DSP_SRCS
# (and to DSP_CORE_SOURCES in main/cpp/CMakeLists.txt, or libpulsr_dsp.so will
# fail to link on device).
set(USB_DSD_SRCS
    ${MAIN_CPP}/DsdNativePacker.cpp
    ${MAIN_CPP}/Uac2Descriptors.cpp
)

# Transient cross-workstream dependency: AudioDspEngine.cpp currently calls
# pulsr::HighQualityResampler, whose translation unit is not in DSP_SRCS yet, so
# every target that links the engine (and therefore this sink) fails at link
# time. Guarded so it becomes a no-op - CMake de-duplicates an identical source
# path - as soon as the owning workstream lands it in DSP_SRCS.
if(EXISTS "${MAIN_CPP}/HighQualityResampler.cpp")
    list(APPEND USB_DSD_SRCS ${MAIN_CPP}/HighQualityResampler.cpp)
endif()

pulsr_add_test(test_usb_dsd_path ${DSP_SRCS} ${USB_DSD_SRCS})

# Attach the same dependencies to every other target that already compiles the
# sink, so test_usb_sink (and the rest) keep building and linking unchanged.
get_property(pulsr_usbdsd_targets DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
             PROPERTY BUILDSYSTEM_TARGETS)
foreach(pulsr_usbdsd_target ${pulsr_usbdsd_targets})
    if(pulsr_usbdsd_target STREQUAL "test_usb_dsd_path")
        continue()
    endif()
    get_target_property(pulsr_usbdsd_sources ${pulsr_usbdsd_target} SOURCES)
    if(pulsr_usbdsd_sources MATCHES "UsbAudioSink[.]cpp")
        target_sources(${pulsr_usbdsd_target} PRIVATE ${USB_DSD_SRCS})
    endif()
endforeach()

# The new test is strict about the policy it pins; keep the same warning set the
# other pure-control tests use.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(test_usb_dsd_path PRIVATE -Wall -Wextra)
endif()
