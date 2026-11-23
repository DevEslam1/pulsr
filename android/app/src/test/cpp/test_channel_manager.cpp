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

    // 5. Positive-gain query follows the live ramp, including disable drain,
    //    but ignores attenuation and channels outside the processed layout.
    {
        ChannelManager manager;
        ChannelManagerParamSet params;
        params.enabled = true;
        params.channelCount = 6;
        params.trimDb[4] = 6.0f;
        manager.applyParams(params);
        assert(manager.canBoost(6)); // Ramp target before first boosted sample.
        assert(!manager.canBoost(2));
        std::vector<float> buffer(128 * 6, 0.8f);
        for (int i = 0; i < 10; ++i) manager.processInterleaved(buffer.data(), 128, 6);
        params.trimDb[4] = -6.0f;
        manager.applyParams(params);
        assert(manager.canBoost(6)); // Current gain remains positive.
        for (int i = 0; i < 10; ++i) manager.processInterleaved(buffer.data(), 128, 6);
        assert(!manager.canBoost(6));
        params.trimDb[4] = 6.0f;
        manager.applyParams(params);
        for (int i = 0; i < 10; ++i) manager.processInterleaved(buffer.data(), 128, 6);
        params.enabled = false;
        manager.applyParams(params);
        manager.setEnabled(false);
        assert(manager.isRamping());
        assert(manager.canBoost(6));
        for (int i = 0; i < 10; ++i) manager.processInterleaved(buffer.data(), 128, 6);
        assert(!manager.isRamping());
        assert(!manager.canBoost(6));
        params.enabled = true;
        params.trimDb[4] = 0.0f;
        params.trimDb[7] = 12.0f;
        manager.applyParams(params);
        manager.setEnabled(true);
        assert(!manager.canBoost(8)); // Declared six-channel layout excludes ch7.
        std::cout << "  positive gain query follows ramp and layout boundaries." << std::endl;
    }

    // 6. Disabling with nonzero delay (and unity gain) ramps delay smoothly to 0
    //    instead of snapping mid-stream.
    {
        ChannelManager manager;
        manager.setSampleRate(48000.0);
        ChannelManagerParamSet params;
        params.enabled = true;
        params.channelCount = 2;
        params.trimDb[0] = 0.0f;
        params.trimDb[1] = 0.0f;
        params.delayMs[1] = 10.0f; // 480 samples
        manager.applyParams(params);

        std::vector<float> buf(64 * 2, 0.5f);
        manager.processInterleaved(buf.data(), 64, 2);

        params.enabled = false;
        manager.applyParams(params);
        assert(manager.isRamping() && "ChannelManager must keep ramping while nonzero delay drains to 0");
        for (int b = 0; b < 32; ++b) {
            std::fill(buf.begin(), buf.end(), 0.5f);
            manager.processInterleaved(buf.data(), 64, 2);
            for (float v : buf) assert(std::isfinite(v));
        }
        assert(!manager.isRamping() && "ChannelManager must settle after delay ramp finishes");
        std::cout << "  ✓ ChannelManager delay disable ramp verified." << std::endl;
    }

    // 7. L-03: setSampleRate preserves active trims, recalculates per-channel
    //    delay sample counts, and flushes stale old-rate delay history.
    {
        ChannelManager manager;
        manager.setSampleRate(48000.0);
        ChannelManagerParamSet params;
        params.enabled = true;
        params.channelCount = 2;
        params.trimDb[0] = 3.5f;
        params.trimDb[1] = -6.0f;
        params.delayMs[0] = 0.0f;
        params.delayMs[1] = 10.0f; // 480 samples @ 48 kHz -> 960 samples @ 96 kHz
        manager.applyParams(params);

        std::vector<float> blk(512 * 2, 0.25f);
        for (int b = 0; b < 8; ++b) {
            std::fill(blk.begin(), blk.end(), 0.25f);
            manager.processInterleaved(blk.data(), 512, 2);
        }

        manager.setSampleRate(96000.0);
        assert(manager.canBoost(2) && "ChannelManager must preserve positive ch0 trim after setSampleRate");

        // Feed silence first to confirm stale 48kHz buffered samples were cleared.
        std::vector<float> zeroBlk(960 * 2, 0.0f);
        manager.processInterleaved(zeroBlk.data(), 960, 2);
        for (float v : zeroBlk) {
            assert(std::abs(v) < 1e-6f && "Stale delay history must be cleared on setSampleRate");
        }

        // Feed unit impulse on L+R; ch1 delayed by ~960 samples @ 96kHz, ch0 trimmed to +3.5dB.
        std::vector<float> impBlk(1024 * 2, 0.0f);
        impBlk[0] = 0.5f;
        impBlk[1] = 0.5f;
        for (int b = 0; b < 32; ++b) {
            std::vector<float> ramp(256 * 2, 0.5f);
            manager.processInterleaved(ramp.data(), 256, 2);
        }
        // After trims settle, ch0 > 0.5f (+3.5 dB) and ch1 < 0.5f (-6.0 dB), with 10ms = 960ch1 delay intact.
        std::fill(impBlk.begin(), impBlk.end(), 0.5f);
        manager.processInterleaved(impBlk.data(), 1024, 2);
        const float expectedCh0 = 0.5f * std::pow(10.0f, 3.5f / 20.0f);
        const float expectedCh1 = 0.5f * std::pow(10.0f, -6.0f / 20.0f);
        assert(std::abs(impBlk[1000 * 2 + 0] - expectedCh0) < 0.01f &&
               "Channel 0 positive trim must survive setSampleRate");
        assert(std::abs(impBlk[1000 * 2 + 1] - expectedCh1) < 0.01f &&
               "Channel 1 attenuation trim must survive setSampleRate");

        // Now pulse ch1 alone after zeroing history and verify onset at frame 960 (+/- 1).
        manager.setSampleRate(96000.0);
        std::vector<float> pulseBlk(1100 * 2, 0.0f);
        pulseBlk[0] = 1.0f;
        pulseBlk[1] = 1.0f;
        manager.processInterleaved(pulseBlk.data(), 1100, 2);
        int ch1PeakIdx = -1;
        float ch1Peak = 0.0f;
        for (int f = 0; f < 1100; ++f) {
            float v = std::abs(pulseBlk[f * 2 + 1]);
            if (v > ch1Peak) { ch1Peak = v; ch1PeakIdx = f; }
        }
        assert(ch1PeakIdx >= 959 && ch1PeakIdx <= 961 &&
               "Channel 1 10ms delay must recalculate to 960 samples at 96kHz");
        std::cout << "  ✓ ChannelManager setSampleRate trim preservation & delay rescale verified." << std::endl;
    }

    std::cout << "[PASS] ChannelManager tests passed." << std::endl;
    return 0;
}
