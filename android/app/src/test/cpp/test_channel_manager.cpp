// android/app/src/test/cpp/test_channel_manager.cpp
#include "../../main/cpp/ChannelManager.h"

#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>

namespace {
constexpr int kFrames = 2400; // 50 ms at 48 kHz: longer than the 20 ms ramp
constexpr int kChannels = 6;

void fillConstant(std::vector<float>& buffer, int channels, float value) {
    for (size_t i = 0; i < buffer.size(); ++i) buffer[i] = value;
}
}  // namespace

int main() {
    std::cout << "[TEST] Running Multichannel ChannelManager tests..." << std::endl;

    // 1. Per-channel trim: channel 1 at -6 dB, others unity.
    {
        ChannelManager manager;
        manager.setSampleRate(48000.0);

        ChannelManagerParamSet params;
        params.enabled = true;
        params.channelCount = kChannels;
        params.trimDb[1] = -6.0206f; // exactly 0.5 linear
        manager.applyParams(params);

        std::vector<float> buffer(kFrames * kChannels, 0.5f);
        manager.processInterleaved(buffer.data(), kFrames, kChannels);

        const int last = (kFrames - 1) * kChannels;
        assert(std::abs(buffer[last + 0] - 0.5f) < 1e-4f);
        assert(std::abs(buffer[last + 1] - 0.25f) < 2e-3f);
        assert(std::abs(buffer[last + 2] - 0.5f) < 1e-4f);
        std::cout << "  ✓ per-channel trim (-6 dB on ch1) verified." << std::endl;
    }

    // 2. Per-channel delay: 10 ms on channel 2, dry channels unchanged.
    {
        ChannelManager manager;
        manager.setSampleRate(48000.0);

        ChannelManagerParamSet params;
        params.enabled = true;
        params.channelCount = kChannels;
        params.delayMs[2] = 10.0f;
        manager.applyParams(params);

        std::vector<float> buffer(kFrames * kChannels, 0.5f);
        manager.processInterleaved(buffer.data(), kFrames, kChannels);

        const int delayFrames = 480;
        // Before the delay line fills, channel 2 is silent.
        assert(std::abs(buffer[(delayFrames - 1) * kChannels + 2]) < 1e-6f);
        // After it fills, the 0.5 signal arrives.
        assert(std::abs(buffer[(delayFrames + 1) * kChannels + 2] - 0.5f) <
               1e-4f);
        assert(std::abs(buffer[(kFrames - 1) * kChannels + 0] - 0.5f) < 1e-4f);
        std::cout << "  ✓ per-channel delay (10 ms on ch2) verified." << std::endl;
    }

    // 3. Disabled manager is a bit-transparent pass-through.
    {
        ChannelManager manager;
        manager.setSampleRate(48000.0);
        ChannelManagerParamSet params;
        params.enabled = false;
        manager.applyParams(params);

        std::vector<float> buffer(kFrames * kChannels, 0.25f);
        manager.processInterleaved(buffer.data(), kFrames, kChannels);
        for (float sample : buffer) {
            assert(sample == 0.25f);
        }
        std::cout << "  ✓ disabled manager is bit-transparent." << std::endl;
    }

    // 4. Eight-channel layout is accepted and leaves channels 6/7 untouched
    //    when the declared layout is 6.0.
    {
        ChannelManager manager;
        manager.setSampleRate(48000.0);
        ChannelManagerParamSet params;
        params.enabled = true;
        params.channelCount = 6;
        params.trimDb[0] = -6.0206f;
        manager.applyParams(params);

        std::vector<float> buffer(kFrames * 8, 0.4f);
        manager.processInterleaved(buffer.data(), kFrames, 8);

        const int last = (kFrames - 1) * 8;
        assert(std::abs(buffer[last + 0] - 0.2f) < 2e-3f);
        assert(std::abs(buffer[last + 6] - 0.4f) < 1e-6f);
        assert(std::abs(buffer[last + 7] - 0.4f) < 1e-6f);
        std::cout << "  ✓ 8-channel buffer / 6-channel layout boundary verified."
                  << std::endl;
    }

    std::cout << "[PASS] ChannelManager tests passed." << std::endl;
    return 0;
}
