// android/app/src/test/cpp/test_eq_threshold_continuity.cpp
#include ../../main/cpp/ParametricEQ.h
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>

int main() {
    std::cout << [TEST] Running EQ Threshold Continuity Tests... << std::endl;

    ParametricEQ eq;
    eq.setSampleRate(48000.0);
    eq.setEnabled(true);

    float lastMaxOutput = 1.0f;
    bool first = true;

    // Sweep gain across zero boundary from -0.05 dB to +0.05 dB with 0.001 dB steps
    for (double g = -0.05; g <= 0.05; g += 0.001) {
        EqParamSet params;
        params.enabled = true;
        params.bands[0].enabled = true;
        params.bands[0].type = FilterType::Peaking;
        params.bands[0].frequency = 1000.0;
        params.bands[0].q = 1.0;
        params.bands[0].gainDb = g;

        eq.applyParams(params);

        std::vector<float> buffer(512, 0.0f);
        buffer[0] = 1.0f; // Unit impulse

        eq.processInterleaved(buffer.data(), 256, 2);

        float maxVal = 0.0f;
        for (float s : buffer) {
            maxVal = std::max(maxVal, std::abs(s));
        }

        if (!first) {
            float diff = std::abs(maxVal - lastMaxOutput);
            // Must have smooth continuity without step-jump > 0.05
            assert(diff < 0.05f);
        }
        lastMaxOutput = maxVal;
        first = false;
    }

    std::cout <<  ✓ Swept -0.05dB to +0.05dB in 0.001dB steps: zero click/pop discontinuities detected. << std::endl;
    std::cout << [PASS] EQ Threshold Continuity tests successfully passed! << std::endl;
    return 0;
}
