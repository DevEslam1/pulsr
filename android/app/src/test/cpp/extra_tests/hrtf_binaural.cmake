# HRTF / SOFA binaural test registration (additive; CMakeLists.txt itself is untouched).
pulsr_add_test(test_hrtf_binaural ${MAIN_CPP}/HrtfBinaural.cpp)
# HrtfBinaural now owns a control-thread prepare mutex (the render side is
# lock-free), and the concurrency test runs a std::thread reader.
find_package(Threads REQUIRED)
target_link_libraries(test_hrtf_binaural PRIVATE Threads::Threads)
