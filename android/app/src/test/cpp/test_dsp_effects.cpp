#include "../../main/cpp/ConvolutionReverb.h"
#include "../../main/cpp/LookaheadLimiter.h"
#include "../../main/cpp/Crossfeed.h"
#include "../../main/cpp/ParametricEQ.h"
#include "../../main/cpp/DsdDecoder.h"
#include "../../main/cpp/HarmonicSaturation.h"
#include "../../main/cpp/SpatialPanner.h"
#include "../../main/cpp/StereoWidth.h"
#include "../../main/cpp/SubCrossover.h"
#include <cassert>
#include <iostream>
#include <vector>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

void testConvolutionReverbUnityGain() {
    ConvolutionReverb reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWetDry(1.0f); // 100% wet
    reverb.setPreset(ReverbPreset::ConcertHall);
    reverb.reset();

    const int blockSize = 1024;
    const int blocks = 50;
    std::vector<float> buffer(blockSize * 2);

    float maxOutput = 0.0f;

    for (int b = 0; b < blocks; ++b) {
        for (int i = 0; i < blockSize; ++i) {
            float t = static_cast<float>(b * blockSize + i) / 48000.0f;
            // Full-scale sine wave input (1.0 amplitude)
            float sample = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * t);
            buffer[i * 2] = sample;
            buffer[i * 2 + 1] = sample;
        }

        reverb.processInterleaved(buffer.data(), blockSize);

        for (int i = 0; i < blockSize * 2; ++i) {
            float val = std::abs(buffer[i]);
            if (val > maxOutput) maxOutput = val;
            if (val > 1.0001f) {
                std::cerr << "FAIL: ConvolutionReverb exceeded unity gain: " << val << std::endl;
                std::exit(1);
            }
        }
    }

    std::cout << "PASS: ConvolutionReverb constant-power crossfading unity test (maxOutput = " 
              << maxOutput << " <= 1.0)." << std::endl;
}

void testLookaheadLimiterCeiling() {
    LookaheadLimiter limiter;
    limiter.setSampleRate(48000.0);
    limiter.configure(3.0, -0.2, 50.0);
    limiter.setEnabled(true);
    limiter.reset();

    const int blockSize = 512;
    std::vector<float> buffer(blockSize * 2);

    // Feed massive +12dB clipped transient (amplitude 4.0)
    for (int i = 0; i < blockSize * 2; ++i) {
        buffer[i] = (i % 2 == 0) ? 4.0f : -4.0f;
    }

    limiter.processInterleaved(buffer.data(), blockSize);

    for (int i = 0; i < blockSize * 2; ++i) {
        if (std::abs(buffer[i]) > 1.0001f) {
            std::cerr << "FAIL: LookaheadLimiter ceiling exceeded: " << buffer[i] << std::endl;
            std::exit(1);
        }
    }

    std::cout << "PASS: LookaheadLimiter ceiling invariant preserved (|out| <= 1.0)." << std::endl;
}

void testHarmonicSaturationStereoInterleaved() {
    HarmonicSaturation sat;
    sat.setSampleRate(48000.0);
    sat.configure(0.5, 0.8, 0.2); // drive=0.5, mix=0.8, tilt=0.2
    sat.setEnabled(true);
    sat.reset();

    const int frames = 512;
    std::vector<float> buffer(frames * 2);

    // Test 1: Channel isolation — Left active 1kHz sine, Right absolute silence (0.0)
    for (int i = 0; i < frames; ++i) {
        float s = std::sin(2.0 * M_PI * 1000.0 * i / 48000.0);
        buffer[i * 2] = s;
        buffer[i * 2 + 1] = 0.0f;
    }

    sat.processInterleaved(buffer.data(), frames, 2);

    for (int i = 0; i < frames; ++i) {
        const float outR = buffer[i * 2 + 1];
        // OutR must remain strictly zero (zero cross-talk or index corruption into R)
        if (std::abs(outR) > 1e-7f) {
            std::cerr << "FAIL: HarmonicSaturation stereo cross-talk/stride corruption detected on Right channel at frame " 
                      << i << ": outR = " << outR << " != 0" << std::endl;
            std::exit(1);
        }
    }

    // Test 2: Planar vs Interleaved Mathematical Equivalence
    HarmonicSaturation satPlanar;
    satPlanar.setSampleRate(48000.0);
    satPlanar.configure(0.5, 0.8, 0.2);
    satPlanar.setEnabled(true);
    satPlanar.reset();

    HarmonicSaturation satInterleaved;
    satInterleaved.setSampleRate(48000.0);
    satInterleaved.configure(0.5, 0.8, 0.2);
    satInterleaved.setEnabled(true);
    satInterleaved.reset();

    std::vector<float> planarL(frames);
    std::vector<float> planarR(frames);
    std::vector<float> interleavedBuf(frames * 2);

    for (int i = 0; i < frames; ++i) {
        float l = 0.7f * std::sin(2.0 * M_PI * 440.0 * i / 48000.0);
        float r = 0.5f * std::cos(2.0 * M_PI * 880.0 * i / 48000.0);
        planarL[i] = l;
        planarR[i] = r;
        interleavedBuf[i * 2] = l;
        interleavedBuf[i * 2 + 1] = r;
    }

    satPlanar.process(planarL.data(), planarR.data(), frames);
    satInterleaved.processInterleaved(interleavedBuf.data(), frames, 2);

    for (int i = 0; i < frames; ++i) {
        const float expectedL = planarL[i];
        const float expectedR = planarR[i];
        const float actualL = interleavedBuf[i * 2];
        const float actualR = interleavedBuf[i * 2 + 1];

        assert(std::abs(actualL - expectedL) < 1e-6f);
        assert(std::abs(actualR - expectedR) < 1e-6f);
    }

    std::cout << "PASS: HarmonicSaturation stereo interleaved stride and planar equivalence verified 100%." << std::endl;
}

void testSpatialPannerTimeConstantSmoothing() {
    SpatialPanner panner64;
    panner64.setSampleRate(48000.0);
    panner64.setBalance(0.0);
    panner64.reset();

    SpatialPanner panner512;
    panner512.setSampleRate(48000.0);
    panner512.setBalance(0.0);
    panner512.reset();

    // Step balance target to 1.0 (hard right)
    panner64.setBalance(1.0);
    panner512.setBalance(1.0);

    const int totalFrames = 5120; // 512 * 10 and 64 * 80 (multiple time constants)
    std::vector<float> audio64(totalFrames * 2, 1.0f);
    std::vector<float> audio512(totalFrames * 2, 1.0f);

    for (int offset = 0; offset < totalFrames; offset += 64) {
        panner64.processInterleaved(&audio64[offset * 2], 64, 2);
    }

    for (int offset = 0; offset < totalFrames; offset += 512) {
        panner512.processInterleaved(&audio512[offset * 2], 512, 2);
    }

    // Compare output envelopes across buffer sizes at 5120 frames (~106ms)
    const float finalL64 = audio64[(totalFrames - 1) * 2];
    const float finalL512 = audio512[(totalFrames - 1) * 2];
    const float finalR64 = audio64[(totalFrames - 1) * 2 + 1];
    const float finalR512 = audio512[(totalFrames - 1) * 2 + 1];

    assert(std::abs(finalL64 - finalL512) < 0.02f);
    assert(std::abs(finalR64 - finalR512) < 0.02f);

    std::cout << "PASS: SpatialPanner time-constant smoothing verified across buffer sizes (64 vs 512 frames)." << std::endl;
}

void testSubCrossoverResetAndPairs() {
    std::cout << "Starting testSubCrossoverResetAndPairs..." << std::endl;
    SubCrossover xover;
    xover.setSampleRate(48000.0);
    xover.configure(80.0, 24.0, 0.8);
    xover.setEnabled(true);
    xover.reset();

    // Feed 50Hz bass tone into stereo interleaved buffer
    const int frames = 512;
    std::vector<float> buf(frames * 2);
    for (int i = 0; i < frames; ++i) {
        float s = std::sin(2.0 * M_PI * 50.0 * i / 48000.0);
        buf[i * 2] = s;
        buf[i * 2 + 1] = s;
    }

    xover.processInterleaved(buf.data(), frames, 2);
    float energyBefore = 0.0f;
    for (float v : buf) energyBefore += v * v;
    assert(energyBefore > 0.0f);

    // Call reset() and re-process: filter coefficients must NOT be zeroed out
    xover.reset();
    for (int i = 0; i < frames; ++i) {
        float s = std::sin(2.0 * M_PI * 50.0 * i / 48000.0);
        buf[i * 2] = s;
        buf[i * 2 + 1] = s;
    }
    xover.processInterleaved(buf.data(), frames, 2);
    float energyAfter = 0.0f;
    for (float v : buf) energyAfter += v * v;

    assert(energyAfter > 0.0f);
    assert(std::abs(energyBefore - energyAfter) / energyBefore < 1e-4f);

    std::cout << "PASS: SubCrossover reset coefficient preservation and pair processing verified." << std::endl;
}

int main() {
    std::cout << "Running DSP effects C++ unit tests..." << std::endl;
    testConvolutionReverbUnityGain();
    testLookaheadLimiterCeiling();
    testHarmonicSaturationStereoInterleaved();
    testSpatialPannerTimeConstantSmoothing();
    testSubCrossoverResetAndPairs();
    std::cout << "All DSP effects C++ tests passed successfully!" << std::endl;
    return 0;
}
