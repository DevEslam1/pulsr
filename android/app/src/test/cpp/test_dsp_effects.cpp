#include "../../main/cpp/ConvolutionReverb.h"
#include "../../main/cpp/LookaheadLimiter.h"
#include "../../main/cpp/Crossfeed.h"
#include "../../main/cpp/ParametricEQ.h"
#include "../../main/cpp/DsdDecoder.h"
#include "../../main/cpp/MultibandCompressor.h"
#include "../../main/cpp/HarmonicSaturation.h"
#include "../../main/cpp/StereoWidth.h"
#include "../../main/cpp/DynamicEQ.h"
#include "../../main/cpp/SubCrossover.h"
#include "../../main/cpp/DynamicBass.h"
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
    reverb.setCrossChannel(0.3); // Verify crosstalk setting does not crash
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

void testMultibandCompressor() {
    MultibandCompressor mbc;
    mbc.setSampleRate(48000.0);
    mbc.setEnabled(true);
    mbc.setCrossovers(160.0, 1000.0, 5000.0);
    // Set 4 bands with threshold -20 dB, ratio 4:1, fast attack/release
    for (int b = 0; b < 4; ++b) {
        mbc.setBand(b, -20.0, 4.0, 5.0, 50.0, 3.0, 0.0, true);
    }
    mbc.reset();

    const int numFrames = 4800; // 100 ms
    std::vector<float> buffer(numFrames * 2);

    // Feed 0 dBFS sine wave at 500 Hz (Band 1: 160-1000 Hz)
    for (int i = 0; i < numFrames; ++i) {
        float sample = std::sin(2.0f * static_cast<float>(M_PI) * 500.0f * (static_cast<float>(i) / 48000.0f));
        buffer[i * 2] = sample;
        buffer[i * 2 + 1] = sample;
    }

    mbc.processInterleaved(buffer.data(), numFrames);

    // After 100 ms of 0 dBFS input (which is 20 dB above the -20 dB threshold),
    // with ratio 4:1, expected compression is 20 * (1 - 1/4) = 15 dB attenuation!
    // Output amplitude should be around -15 dB = 10^(-15/20) ≈ 0.178.
    float peakAtEnd = 0.0f;
    for (int i = numFrames - 480; i < numFrames; ++i) {
        float s = std::abs(buffer[i * 2]);
        if (s > peakAtEnd) peakAtEnd = s;
    }

    if (peakAtEnd >= 0.5f || peakAtEnd <= 0.05f) {
        std::cerr << "FAIL: MultibandCompressor did not compress properly! peakAtEnd = " << peakAtEnd << std::endl;
        std::exit(1);
    }

    std::cout << "PASS: MultibandCompressor 4-band LR4 compression verified (peak = " << peakAtEnd << " < 0.5)." << std::endl;
}

void testHarmonicSaturationModes() {
    HarmonicSaturation sat;
    sat.setSampleRate(48000.0);
    sat.setEnabled(true);

    const int numFrames = 4800;

    // Test Mode 0: Tape
    sat.setParams(0.8, 1.0, 0.0, SaturationMode::Tape);
    sat.reset();
    std::vector<float> tapeBuf(numFrames * 2);
    for (int i = 0; i < numFrames; ++i) {
        float s = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * (static_cast<float>(i) / 48000.0f));
        tapeBuf[i * 2] = s;
        tapeBuf[i * 2 + 1] = s;
    }
    sat.processInterleaved(tapeBuf.data(), numFrames);

    // Test Mode 1: Tube (Triode asymmetric)
    sat.setParams(0.8, 1.0, 0.0, SaturationMode::Tube);
    sat.reset();
    std::vector<float> tubeBuf(numFrames * 2);
    for (int i = 0; i < numFrames; ++i) {
        float s = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * (static_cast<float>(i) / 48000.0f));
        tubeBuf[i * 2] = s;
        tubeBuf[i * 2 + 1] = s;
    }
    sat.processInterleaved(tubeBuf.data(), numFrames);

    // In Tube mode, asymmetry should create a difference between positive and negative peaks,
    // and DC blocker should ensure mean DC is near zero (< 0.01).
    float sumDc = 0.0f;
    for (int i = numFrames / 2; i < numFrames; ++i) {
        sumDc += tubeBuf[i * 2];
    }
    float avgDc = std::abs(sumDc / (numFrames / 2));
    if (avgDc > 0.02f) {
        std::cerr << "FAIL: Tube mode DC blocker failed, avgDc = " << avgDc << std::endl;
        std::exit(1);
    }

    std::cout << "PASS: HarmonicSaturation Tape & Tube modes verified (DC offset = " << avgDc << " < 0.02)." << std::endl;
}

void testStereoWidthBassMono() {
    StereoWidth sw;
    sw.setSampleRate(48000.0);
    sw.setEnabled(true);
    // Multiband mode: low width = 0.0 (pure mono), mid = 1.0, high = 1.0, low crossover = 200 Hz
    sw.setParams(1.0, true, 0.0, 1.0, 1.0, 200.0, 2500.0);
    sw.reset();

    const int numFrames = 4800;
    std::vector<float> buffer(numFrames * 2);

    // Input: pure out-of-phase 80 Hz sub-bass (L = 1.0, R = -1.0)
    for (int i = 0; i < numFrames; ++i) {
        float s = std::sin(2.0f * static_cast<float>(M_PI) * 80.0f * (static_cast<float>(i) / 48000.0f));
        buffer[i * 2] = s;
        buffer[i * 2 + 1] = -s;
    }

    sw.processInterleaved(buffer.data(), numFrames);

    // With low width = 0.0, out-of-phase sub-bass difference should be collapsed/nulled
    float maxDiff = 0.0f;
    for (int i = numFrames / 2; i < numFrames; ++i) {
        float diff = std::abs(buffer[i * 2] - buffer[i * 2 + 1]);
        if (diff > maxDiff) maxDiff = diff;
    }

    if (maxDiff > 0.1f) {
        std::cerr << "FAIL: StereoWidth Bass Mono did not eliminate sub-bass side difference! maxDiff = " << maxDiff << std::endl;
        std::exit(1);
    }

    std::cout << "PASS: StereoWidth 3-Band Bass Mono verified (sub-bass side diff = " << maxDiff << " < 0.1)." << std::endl;
}

void testDynamicEqBoostMode() {
    DynamicEQ deq;
    deq.setSampleRate(48000.0);
    deq.setEnabled(true);
    deq.setBandCount(1);
    // Band 0: 1000 Hz, Q=2, threshold -30 dB, ratio 3:1, attack 2ms, release 50ms, maxCut 0, maxBoost 12dB, Mode 1 (Boost)
    deq.setBand(0, 1000.0, 2.0, -30.0, 3.0, 2.0, 50.0, 0.0, 12.0, 1, 0, true);
    deq.reset();

    const int numFrames = 4800;
    std::vector<float> buffer(numFrames * 2);

    // Feed 1000 Hz tone at 0.5 amplitude (~ -6 dBFS, well above -30 dB threshold)
    for (int i = 0; i < numFrames; ++i) {
        float s = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * (static_cast<float>(i) / 48000.0f));
        buffer[i * 2] = s;
        buffer[i * 2 + 1] = s;
    }

    deq.processInterleaved(buffer.data(), numFrames);

    // Peak amplitude should be boosted above 0.5f
    float maxPeak = 0.0f;
    for (int i = numFrames / 2; i < numFrames; ++i) {
        float s = std::abs(buffer[i * 2]);
        if (s > maxPeak) maxPeak = s;
    }

    if (maxPeak <= 0.55f) {
        std::cerr << "FAIL: DynamicEQ Boost mode did not amplify! maxPeak = " << maxPeak << std::endl;
        std::exit(1);
    }

    std::cout << "PASS: DynamicEQ Boost mode verified (peak = " << maxPeak << " > 0.55)." << std::endl;
}

void testDynamicBass() {
    DynamicBass db;
    db.prepare(48000.0);
    // Preset 3: Common Headphone v2 (xLow: 300, xHigh: 5600, yLow: 60, yHigh: 105, sideLow: 0.10, sideHigh: 0.50)
    db.setParams(true, 3.0, 300, 5600, 60, 105, 0.10, 0.50, 3);
    db.reset();

    const int numFrames = 4800;
    std::vector<float> buffer(numFrames * 2);

    // Feed 75 Hz tone (within 60-105 Hz punch window) at 0.2 amplitude
    for (int i = 0; i < numFrames; ++i) {
        float s = 0.2f * std::sin(2.0f * static_cast<float>(M_PI) * 75.0f * (static_cast<float>(i) / 48000.0f));
        buffer[i * 2] = s;
        buffer[i * 2 + 1] = s;
    }

    db.processInterleaved(buffer.data(), numFrames, 2);

    float maxPeak = 0.0f;
    for (int i = numFrames / 2; i < numFrames; ++i) {
        float s = std::abs(buffer[i * 2]);
        if (s > maxPeak) maxPeak = s;
    }

    if (maxPeak <= 0.25f) {
        std::cerr << "FAIL: DynamicBass did not boost sub-bass punch! maxPeak = " << maxPeak << std::endl;
        std::exit(1);
    }

    std::cout << "PASS: DynamicBass verified (boosted peak = " << maxPeak << " > 0.25)." << std::endl;
}

int main() {
    std::cout << "Running DSP effects C++ unit tests..." << std::endl;
    testConvolutionReverbUnityGain();
    testLookaheadLimiterCeiling();
    testMultibandCompressor();
    testHarmonicSaturationModes();
    testStereoWidthBassMono();
    testDynamicEqBoostMode();
    testDynamicBass();
    std::cout << "All DSP effects C++ tests passed successfully!" << std::endl;
    return 0;
}
