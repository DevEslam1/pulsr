// android/app/src/main/cpp/fuzz/fuzz_liveprog.cc
#include "../LiveProg.h"
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <cassert>
#include <cmath>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 16384) return 0; // Practical JSFX script size limit
    std::string input(reinterpret_cast<const char*>(data), size);

    LiveProg liveProg;
    liveProg.setSampleRate(48000.0);

    if (liveProg.loadCode(input)) {
        auto prog = liveProg.buildProgram();
        if (prog) {
            LiveProgParamSet params;
            params.enabled = true;
            params.program = prog;
            liveProg.applyParams(params);

            // 64-sample processInterleaved (128 interleaved floats)
            float buffer[128];
            for (int i = 0; i < 128; ++i) {
                buffer[i] = (i % 2 == 0) ? 0.35f : -0.35f;
            }
            liveProg.processInterleaved(buffer, 64, 2);

            // Assert output always finite and <= +-4 (clamp contract)
            for (int i = 0; i < 128; ++i) {
                assert(std::isfinite(buffer[i]));
                assert(buffer[i] >= -4.05f && buffer[i] <= 4.05f);
            }
        }
    }

    return 0;
}
