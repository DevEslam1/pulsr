// RG fallback, DoP safety in the bit-perfect path, bit-perfect exit smoothing.
#include "../../main/cpp/AudioDspEngine.h"
#include <cmath>
#include <cstring>
#include <iostream>
#include <memory>
#include <vector>

namespace {
int gFailures = 0;
void check(bool ok, const char* what) {
    if (!ok) { std::cout << "[FAIL] " << what << std::endl; ++gFailures; }
}
std::vector<float> sig(int frames, int ch) {
    std::vector<float> b(static_cast<size_t>(frames) * ch);
    for (int i = 0; i < frames; ++i)
        for (int c = 0; c < ch; ++c)
            b[static_cast<size_t>(i) * ch + c] = static_cast<float>(0.4 * std::sin((i + c * 11) * 0.05));
    return b;
}
std::shared_ptr<DspParamSnapshot> base() {
    auto s = std::make_shared<DspParamSnapshot>();
    s->sampleRate = 48000.0;
    s->activeStages = 0;
    s->headphoneSafety.enabled = false;
    return s;
}
// Settled output/input peak ratio under a ReplayGain snapshot.
double settledRatio(std::shared_ptr<DspParamSnapshot> s) {
    auto e = std::make_unique<AudioDspEngine>();
    e->setSampleRate(48000.0);
    e->publishParams(s);
    const auto in = sig(512, 2);
    std::vector<float> w;
    for (int b = 0; b < 200; ++b) { w = in; e->processInterleaved(w.data(), 512, 2); }
    double pi = 0, po = 0;
    for (size_t i = 0; i < in.size(); ++i) { pi = std::max(pi, (double)std::fabs(in[i])); po = std::max(po, (double)std::fabs(w[i])); }
    return po / pi;
}
}  // namespace

int main() {
    std::cout << "[TEST] RG fallback / DoP safety..." << std::endl;
    {   // DoP words must survive a transport fade untouched.
        auto e = std::make_unique<AudioDspEngine>();
        auto s = base();
        s->bitPerfect.enabled = true;
        s->bitPerfect.isDop = true;
        e->setSampleRate(48000.0);
        e->publishParams(s);
        const auto in = sig(256, 2);
        auto w = in;
        std::vector<float> gains(256, 0.5f);
        e->processInterleaved(w.data(), 256, 2, gains.data());
        check(std::memcmp(w.data(), in.data(), in.size() * sizeof(float)) == 0,
              "DoP bit-perfect must ignore transport gain");
    }
    {   // Album mode, no album tag -> track gain (-6 dB).
        auto s = base();
        s->replayGain.enabled = true;
        s->replayGain.mode = ReplayGainMode::Album;
        s->replayGain.hasAlbumGain = false;
        s->replayGain.trackGainDb = -6.0;
        const double r = settledRatio(s);
        check(std::fabs(r - 0.501) < 0.01, "album mode must fall back to track gain");
    }
    {   // Album mode with album tag uses it.
        auto s = base();
        s->replayGain.enabled = true;
        s->replayGain.mode = ReplayGainMode::Album;
        s->replayGain.albumGainDb = -12.0;
        s->replayGain.trackGainDb = -6.0;
        const double r = settledRatio(s);
        check(std::fabs(r - 0.251) < 0.01, "album tag must win in album mode");
    }
    {   // Untagged: pre-amp only, no stale tag gain.
        auto s = base();
        s->replayGain.enabled = true;
        s->replayGain.mode = ReplayGainMode::Track;
        s->replayGain.hasTrackGain = false;
        s->replayGain.trackGainDb = -20.0;
        s->replayGain.preAmpDb = -6.0;
        const double r = settledRatio(s);
        check(std::fabs(r - 0.501) < 0.01, "untagged track must use pre-amp only");
    }
    {   // New track tags must take effect within the first block.
        auto e = std::make_unique<AudioDspEngine>();
        e->setSampleRate(48000.0);
        auto s = base();
        s->replayGain.enabled = true;
        s->replayGain.mode = ReplayGainMode::Track;
        s->replayGain.trackGainDb = -12.0;
        e->publishParams(s);
        const auto in = sig(512, 2);
        std::vector<float> w;
        for (int b = 0; b < 100; ++b) { w = in; e->processInterleaved(w.data(), 512, 2); }
        auto s2 = base();
        s2->replayGain.enabled = true;
        s2->replayGain.mode = ReplayGainMode::Track;
        s2->replayGain.trackGainDb = 0.0;
        e->publishParams(s2);
        w = in;
        e->processInterleaved(w.data(), 512, 2);
        // The first block ramps cleanly across the block so it hits the new
        // track's exact target gain by the final frame (no 20ms tail lag).
        const double lastRatio = std::fabs(w[511 * 2] / in[511 * 2]);
        check(std::fabs(lastRatio - 1.0) < 1e-4, "track change must reach new gain by end of first block");
        w = in;
        e->processInterleaved(w.data(), 512, 2);
        double pi = 0, po = 0;
        for (size_t i = 0; i < in.size(); ++i) { pi = std::max(pi, (double)std::fabs(in[i])); po = std::max(po, (double)std::fabs(w[i])); }
        check(std::fabs(po / pi - 1.0) < 1e-4, "second block after track change must sit at exact new gain");
    }
    {   // Bit-perfect USB software volume: unity & DoP stay bit-exact; non-unity attenuates PCM.
        auto e = std::make_unique<AudioDspEngine>();
        e->setSampleRate(48000.0);
        const auto in = sig(512, 2);

        // DoP must stay bit-exact even if directUsbGain < 1.0.
        auto sDop = base();
        sDop->bitPerfect.enabled = true;
        sDop->bitPerfect.isDop = true;
        sDop->bitPerfect.directUsbGain = 0.25;
        e->publishParams(sDop);
        auto w = in;
        e->processInterleaved(w.data(), 512, 2);
        check(w == in && e->wasLastBlockBitPerfect(),
              "DoP must ignore directUsbGain and stay bit-exact");

        // Bit-perfect PCM at unity stays bit-exact.
        auto sUnity = base();
        sUnity->bitPerfect.enabled = true;
        sUnity->bitPerfect.isDop = false;
        sUnity->bitPerfect.directUsbGain = 1.0;
        e->publishParams(sUnity);
        w = in;
        e->processInterleaved(w.data(), 512, 2);
        check(w == in && e->wasLastBlockBitPerfect(),
              "bit-perfect PCM at directUsbGain=1.0 must stay bit-exact");

        // Bit-perfect PCM at <1.0 attenuates smoothly and returns to raw on 1.0.
        auto sAtten = base();
        sAtten->bitPerfect.enabled = true;
        sAtten->bitPerfect.isDop = false;
        sAtten->bitPerfect.directUsbGain = 0.25;
        e->publishParams(sAtten);
        for (int b = 0; b < 40; ++b) { w = in; e->processInterleaved(w.data(), 512, 2); }
        check(!e->wasLastBlockBitPerfect(),
              "non-unity directUsbGain must drop raw bit-exact flag");
        double pi = 0, po = 0;
        for (size_t i = 0; i < in.size(); ++i) {
            pi = std::max(pi, (double)std::fabs(in[i]));
            po = std::max(po, (double)std::fabs(w[i]));
        }
        check(std::fabs(po / pi - 0.25) < 0.01,
              "bit-perfect PCM with directUsbGain=0.25 must settle to 0.25");

        e->publishParams(sUnity);
        for (int b = 0; b < 60; ++b) { w = in; e->processInterleaved(w.data(), 512, 2); }
        check(w == in && e->wasLastBlockBitPerfect(),
              "returning directUsbGain to 1.0 must restore raw bit-exact pass-through");
    }
    if (gFailures == 0) std::cout << "[PASS] test_rg_dop" << std::endl;
    return gFailures == 0 ? 0 : 1;
}
