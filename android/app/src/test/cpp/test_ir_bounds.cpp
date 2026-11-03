// android/app/src/test/cpp/test_ir_bounds.cpp
#include "../../main/cpp/IrBounds.h"

#include <cmath>
#include <iostream>
#include <vector>

namespace {
int gFailures = 0;
void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}
}  // namespace

int main() {
    std::cout << "[TEST] Impulse-response bounds..." << std::endl;

    check(!pulsr::ValidateIrShape(1001, 2), "reject len % channels != 0");
    check(!pulsr::ValidateIrShape(0, 2), "reject empty IR");
    check(!pulsr::ValidateIrShape(16, 0), "reject zero channels");
    check(!pulsr::ValidateIrShape(16, 9), "reject > 8 channels");
    check(pulsr::ValidateIrShape(1024, 2), "accept well-formed stereo IR");

    {
        const int channels = 2;
        const int frames = 100000;
        const int maxFrames = 10000;
        const int fadeFrames = 100;
        std::vector<float> ir(static_cast<size_t>(frames) * channels, 1.0f);
        const int out = pulsr::TruncateIrWithFade(ir, channels, maxFrames, fadeFrames);
        check(out == maxFrames, "truncate to cap");
        check(ir.size() == static_cast<size_t>(maxFrames) * channels,
              "interleaved buffer resized consistently");
        check(std::fabs(ir[static_cast<size_t>(maxFrames - 1) * channels]) < 0.05f,
              "tail is faded out near the cut");
        check(ir[0] == 1.0f, "IR head is untouched");
    }

    {
        std::vector<float> shortIr(200, 0.5f);
        const int out = pulsr::TruncateIrWithFade(shortIr, 1, 300, 10);
        check(out == 200, "shorter-than-cap IR is not modified");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " IR bound check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] IR shape and length bounds hold." << std::endl;
    return 0;
}
