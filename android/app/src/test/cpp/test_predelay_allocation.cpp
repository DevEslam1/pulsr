// android/app/src/test/cpp/test_predelay_allocation.cpp
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <cassert>
#include <algorithm>

void runPredelayAllocationTest() {
    std::cout << "\n=== [TEST] ConvolutionReverb Predelay Allocation Dynamic Cap ===" << std::endl;
    ConvolutionReverb reverb;

    // At construction, minimal working buffers (4096)
    int initCap = reverb.getPredelayCapacity();
    assert(initCap >= 4096 && initCap < 153600);
    std::cout << "Initial predelay capacity: " << initCap << " (expected >= 4096 and < 153600)" << std::endl;

    // Set sample rate to 48kHz
    reverb.setSampleRate(48000.0);
    reverb.setPredelay(0.150); // 150ms
    int cap48 = reverb.getPredelayCapacity();
    int expected48 = std::max(4096, static_cast<int>(48000.0 * 0.150) + 16);
    assert(cap48 == expected48);
    std::cout << "48kHz 150ms predelay capacity: " << cap48 << " == expected " << expected48 << std::endl;

    std::cout << "  [PASS] ConvolutionReverb Predelay Allocation Test Passed!" << std::endl;
}

#ifdef STANDALONE_TEST_PREDELAY
int main() {
    runPredelayAllocationTest();
    return 0;
}
#endif
