// android/app/src/test/cpp/test_limiter_mask_safety.cpp
#include ../../main/cpp/LookaheadLimiter.h
#include <iostream>
#include <vector>
#include <cassert>

int main() {
    std::cout << [TEST] Running Lookahead Limiter Mask Safety & Power-of-2 Tests... << std::endl;

    // 1. Static assertion check on power-of-2
    static_assert((LookaheadLimiter::MAX_LOOKAHEAD_SAMPLES & (LookaheadLimiter::MAX_LOOKAHEAD_SAMPLES - 1)) == 0,
                  MAX_LOOKAHEAD_SAMPLES must be a power of 2 for bitmask wrap);
    std::cout <<  ✓ MAX_LOOKAHEAD_SAMPLES =  << LookaheadLimiter::MAX_LOOKAHEAD_SAMPLES <<  is a verified power of 2. << std::endl;

    // 2. Extreme lookahead sample clamping
    LookaheadLimiter limiter;
    limiter.setSampleRate(192000.0);
    limiter.configure(100.0, -0.2, 50.0, true);
    assert(limiter.getLatencyFrames() < LookaheadLimiter::MAX_LOOKAHEAD_SAMPLES);
    std::cout <<  ✓ Clamped lookahead frames:  << limiter.getLatencyFrames() <<  <  << LookaheadLimiter::MAX_LOOKAHEAD_SAMPLES << std::endl;

    // 3. Multi-block wrap-around throughput check
    constexpr int framesPerBlock = 512;
    constexpr int totalBlocks = 100;
    std::vector<float> audio(framesPerBlock * 2, 0.5f);

    limiter.setEnabled(true);
    for (int b = 0; b < totalBlocks; ++b) {
        limiter.processInterleaved(audio.data(), framesPerBlock, 2);
    }
    std::cout <<  ✓ Processed  << (framesPerBlock * totalBlocks) <<  samples across wrap boundary cleanly. << std::endl;

    std::cout << [PASS] Lookahead Limiter Mask Safety tests successfully passed! << std::endl;
    return 0;
}
