# Build measure_native_dsp executable and wire into CTest (§8.7)
add_executable(measure_native_dsp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../scripts/measure_native_dsp.cpp
    ${DSP_SRCS}
)

add_test(NAME measure_native_dsp COMMAND measure_native_dsp --out-dir ${CMAKE_CURRENT_BINARY_DIR}/measure_native_dsp_out)
