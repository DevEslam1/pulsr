cmake_minimum_required(VERSION 3.22.1)
project(flacJNI C CXX)

set(CMAKE_CXX_STANDARD 17)

include_directories(
    flac/include
    flac/src/libFLAC/include
)

add_definitions(
    -DPACKAGE_VERSION="1.3.2"
    -DFLAC__NO_MD5
    -DFLAC__INTEGER_ONLY_LIBRARY
    -D_REENTRANT
    -DPIC
    -DU_COMMON_IMPLEMENTATION
    -DHAVE_SYS_PARAM_H
    -DFLAC__NO_ASM
    -DFLAC__HAS_OGG=0
)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -funroll-loops -finline-functions")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -funroll-loops -finline-functions")

add_library(flacJNI SHARED
    flac_jni.cc
    flac_parser.cc
    flac/src/libFLAC/bitmath.c
    flac/src/libFLAC/bitreader.c
    flac/src/libFLAC/bitwriter.c
    flac/src/libFLAC/cpu.c
    flac/src/libFLAC/crc.c
    flac/src/libFLAC/fixed.c
    flac/src/libFLAC/fixed_intrin_sse2.c
    flac/src/libFLAC/fixed_intrin_ssse3.c
    flac/src/libFLAC/float.c
    flac/src/libFLAC/format.c
    flac/src/libFLAC/lpc.c
    flac/src/libFLAC/lpc_intrin_avx2.c
    flac/src/libFLAC/lpc_intrin_sse2.c
    flac/src/libFLAC/lpc_intrin_sse41.c
    flac/src/libFLAC/lpc_intrin_sse.c
    flac/src/libFLAC/md5.c
    flac/src/libFLAC/memory.c
    flac/src/libFLAC/metadata_iterators.c
    flac/src/libFLAC/metadata_object.c
    flac/src/libFLAC/stream_decoder.c
    flac/src/libFLAC/stream_encoder.c
    flac/src/libFLAC/stream_encoder_framing.c
    flac/src/libFLAC/stream_encoder_intrin_avx2.c
    flac/src/libFLAC/stream_encoder_intrin_sse2.c
    flac/src/libFLAC/stream_encoder_intrin_ssse3.c
    flac/src/libFLAC/window.c
)

find_library(log-lib log)

target_link_libraries(flacJNI
    ${log-lib}
    z
    m
)
