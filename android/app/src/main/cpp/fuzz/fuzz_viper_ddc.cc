// android/app/src/main/cpp/fuzz/fuzz_viper_ddc.cc
#include "../ViperDdc.h"
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 65536) return 0;
    std::string input(reinterpret_cast<const char*>(data), size);

    // 1. Fuzz parseVdcContent
    std::vector<ViperDdcSection> s441;
    std::vector<ViperDdcSection> s480;
    ViperDdc::parseVdcContent(input, s441, s480);

    // 2. Fuzz loadVdcString
    ViperDdc ddc;
    ddc.setSampleRate(48000.0);
    ddc.setEnabled(true);
    bool loaded = ddc.loadVdcString(input);

    // 3. Process 1 block through biquad sections
    if (loaded || !s480.empty()) {
        float buffer[512] = {0.0f};
        for (int i = 0; i < 512; ++i) {
            buffer[i] = 0.25f;
        }
        ddc.processInterleaved(buffer, 256, 2);
    }

    return 0;
}
