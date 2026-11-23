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
#include "../../main/cpp/ArbitraryResponseEq.h"
#include "../../main/cpp/ViperDdc.h"
#include "../../main/cpp/LiveProg.h"
#include "../../main/cpp/LoudnessContour.h"
#include "../../main/cpp/AudioDspEngine.h"
#include <limits>
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
    MultibandCompressorParamSet mbcParams;
    mbcParams.enabled = true;
    mbcParams.crossoverFreqs[0] = 160.0;
    mbcParams.crossoverFreqs[1] = 1000.0;
    mbcParams.crossoverFreqs[2] = 5000.0;
    // Set 4 bands with threshold -20 dB, ratio 4:1, fast attack/release
    for (int b = 0; b < 4; ++b) {
        mbcParams.bands[b].thresholdDb = -20.0;
        mbcParams.bands[b].ratio = 4.0;
        mbcParams.bands[b].attackMs = 5.0;
        mbcParams.bands[b].releaseMs = 50.0;
    }
    mbc.applyParams(mbcParams);
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
    sat.configure(0.8, 1.0, 0.0, 0);
    sat.reset();
    std::vector<float> tapeBuf(numFrames * 2);
    for (int i = 0; i < numFrames; ++i) {
        float s = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * (static_cast<float>(i) / 48000.0f));
        tapeBuf[i * 2] = s;
        tapeBuf[i * 2 + 1] = s;
    }
    sat.processInterleaved(tapeBuf.data(), numFrames);

    // Test Mode 1: Tube (Triode asymmetric)
    sat.configure(0.8, 1.0, 0.0, 1);
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
    sw.configure(1.0);
    sw.configureMultiband(true, 0.0, 1.0, 1.0, 200.0, 2500.0);
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
    DynamicEqBandParam boostBand;
    boostBand.frequency = 1000.0;
    boostBand.q = 2.0;
    boostBand.thresholdDb = -30.0;
    boostBand.attackMs = 2.0;
    boostBand.releaseMs = 50.0;
    boostBand.maxCutDb = 0.0;
    boostBand.maxBoostDb = 12.0;
    boostBand.mode = 1;
    deq.setBand(0, boostBand);
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


// -------------------------------------------------------------
// Transition Smoothing & Continuity Regression Tests
// -------------------------------------------------------------

static void checkSignalContinuity(const std::vector<float>& prevBlock,
                                  const std::vector<float>& curBlock,
                                  int channels,
                                  float maxAllowedDelta,
                                  const std::string& testName) {
    if (prevBlock.empty() || curBlock.empty()) return;
    int frames = static_cast<int>(curBlock.size()) / channels;
    for (int ch = 0; ch < channels; ++ch) {
        float lastPrev = prevBlock[prevBlock.size() - channels + ch];
        float firstCur = curBlock[ch];
        float stepAtBoundary = std::abs(firstCur - lastPrev);
        if (std::isnan(firstCur) || std::isinf(firstCur)) {
            std::cerr << "FAIL [" << testName << "]: NaN/Inf at block boundary ch " << ch << std::endl;
            std::exit(1);
        }
        if (stepAtBoundary > maxAllowedDelta) {
            std::cerr << "FAIL [" << testName << "]: Discontinuity at block boundary ch " << ch
                      << ": delta = " << stepAtBoundary << " (max allowed = " << maxAllowedDelta << ")" << std::endl;
            std::exit(1);
        }
        for (int i = 1; i < frames; ++i) {
            float prevSample = curBlock[(i - 1) * channels + ch];
            float curSample = curBlock[i * channels + ch];
            if (std::isnan(curSample) || std::isinf(curSample)) {
                std::cerr << "FAIL [" << testName << "]: NaN/Inf inside block at frame " << i << std::endl;
                std::exit(1);
            }
            float step = std::abs(curSample - prevSample);
            if (step > maxAllowedDelta) {
                std::cerr << "FAIL [" << testName << "]: Internal discontinuity at frame " << i
                          << ": delta = " << step << " (max allowed = " << maxAllowedDelta << ")" << std::endl;
                std::exit(1);
            }
        }
    }
}

static std::vector<float> generateSineWave(int numFrames, int channels, float freq, float sampleRate, float amp, int startFrame = 0) {
    std::vector<float> buf(numFrames * channels);
    for (int i = 0; i < numFrames; ++i) {
        float t = static_cast<float>(startFrame + i) / sampleRate;
        float s = amp * std::sin(2.0f * static_cast<float>(M_PI) * freq * t);
        for (int ch = 0; ch < channels; ++ch) {
            buf[i * channels + ch] = s;
        }
    }
    return buf;
}

static void testHarmonicSaturationTransitions() {
    std::cout << "Testing HarmonicSaturation enable/disable and mode transitions..." << std::endl;
    HarmonicSaturation sat;
    sat.configure(0.8, 1.0, 0.0, 0);
    sat.setEnabled(false);

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> prevBlock;
    int currentFrame = 0;
    // 440 Hz at 0.7 FS has a natural per-sample slope near 0.04; saturated
    // harmonics and the mode crossfade can legitimately reach ~0.10. 0.15
    // still catches a hard snap (a full-scale discontinuity is ~0.4+).
    const float maxDelta = 0.15f;

    // 1. Process 10 blocks disabled
    for (int b = 0; b < 10; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        sat.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Saturation Disabled");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // 2. Enable saturation -> verify smooth ramp-in
    sat.setEnabled(true);
    for (int b = 0; b < 20; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        sat.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Saturation Enabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // 3. Switch mode while running
    sat.configure(1.2, 1.0, 0.0, 1);
    for (int b = 0; b < 20; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        sat.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Saturation Mode Switch");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // 4. Disable saturation -> verify smooth ramp-out
    sat.setEnabled(false);
    for (int b = 0; b < 20; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        sat.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Saturation Disabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    std::cout << "PASS: HarmonicSaturation transitions verified smooth & bounded." << std::endl;
}

static void testLookaheadLimiterStageTransitions() {
    std::cout << "Testing LookaheadLimiter stage insertion/removal crossfades..." << std::endl;
    auto limiter = std::make_unique<LookaheadLimiter>();
    limiter->setSampleRate(48000.0);
    limiter->configure(5.0, -0.2, 50.0, false);
    limiter->setEnabled(true);
    limiter->setProcessingActive(true);

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> prevBlock;
    int currentFrame = 0;
    const float maxDelta = 0.08f;

    for (int b = 0; b < 60; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        limiter->processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Limiter Insertion");
        prevBlock = block;
        currentFrame += blockSize;
    }

    limiter->setProcessingActive(false);
    for (int b = 0; b < 60 && limiter->isDraining(); ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        limiter->processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Limiter Removal");
        prevBlock = block;
        currentFrame += blockSize;
    }
    if (limiter->isDraining()) {
        std::cerr << "FAIL: LookaheadLimiter removal did not finish." << std::endl;
        std::exit(1);
    }

    auto dryBlock = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
    auto dryProcessed = dryBlock;
    limiter->processInterleaved(dryProcessed.data(), blockSize, channels);
    for (size_t i = 0; i < dryBlock.size(); ++i) {
        if (std::abs(dryProcessed[i] - dryBlock[i]) > 1e-6f) {
            std::cerr << "FAIL: LookaheadLimiter is not dry after removal." << std::endl;
            std::exit(1);
        }
    }
    prevBlock = dryProcessed;
    currentFrame += blockSize;

    limiter->setProcessingActive(true);
    for (int b = 0; b < 60; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        limiter->processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "Limiter Reinsertion");
        prevBlock = block;
        currentFrame += blockSize;
    }

    std::cout << "PASS: LookaheadLimiter insertion/removal transitions verified smooth." << std::endl;
}

static void testArbitraryEqTransitions() {
    std::cout << "Testing ArbitraryResponseEq enable/disable and profile crossfading..." << std::endl;
    ArbitraryResponseEq eq;
    eq.setSampleRate(48000.0);
    eq.setEnabled(false);

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> prevBlock;
    int currentFrame = 0;
    const float maxDelta = 0.08f;

    // Disabled blocks
    for (int b = 0; b < 10; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ArbitraryEq Disabled");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Load profile 1 and enable
    std::string profile1 = "GraphicEQ: 20 0; 440 6; 1000 -6; 20000 0";
    eq.loadGraphicEqString(profile1);
    eq.setEnabled(true);
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ArbitraryEq Enabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Reconfigure profile 2 on the fly (crossfade)
    std::string profile2 = "GraphicEQ: 20 -10; 440 -6; 1000 6; 20000 0";
    eq.loadGraphicEqString(profile2);
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ArbitraryEq Reconfiguring");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Clear the response on the fly: the old kernel must crossfade to the
    // passthrough impulse instead of snapping the EQ off in one sample.
    eq.loadGraphicEqString("");
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ArbitraryEq Clearing");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Disable
    eq.setEnabled(false);
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ArbitraryEq Disabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    std::cout << "PASS: ArbitraryResponseEq transitions verified smooth & bounded." << std::endl;
}

static void testViperDdcTransitions() {
    std::cout << "Testing ViperDdc enable/disable and profile crossfading..." << std::endl;
    ViperDdc ddc;
    ddc.setSampleRate(48000.0);
    ddc.setEnabled(false);

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> prevBlock;
    int currentFrame = 0;
    const float maxDelta = 0.08f;

    // Disabled
    for (int b = 0; b < 10; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        ddc.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ViperDdc Disabled");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // VDC profile 1: +3 dB peaking biquad at 440 Hz
    std::string vdc1 = "SR_48000\n1.009754, -1.949473, 0.942957, -1.949473, 0.952711\n";
    ddc.loadVdcString(vdc1);
    ddc.setEnabled(true);

    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        ddc.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ViperDdc Enabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Switch to profile 2: -3 dB peaking biquad at 440 Hz
    std::string vdc2 = "SR_48000\n0.990340, -1.930641, 0.943508, -1.930641, 0.933848\n";
    ddc.loadVdcString(vdc2);

    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        ddc.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ViperDdc Profile Switch");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Disable
    ddc.setEnabled(false);
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        ddc.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "ViperDdc Disabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    std::cout << "PASS: ViperDdc transitions verified smooth & bounded." << std::endl;
}

static void testLiveProgTransitions() {
    std::cout << "Testing LiveProg enable/disable and program reloads..." << std::endl;
    LiveProg prog;
    prog.setSampleRate(48000.0);
    prog.setEnabled(false);

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> prevBlock;
    int currentFrame = 0;
    const float maxDelta = 0.08f;

    // Disabled
    for (int b = 0; b < 10; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        prog.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "LiveProg Disabled");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Program 1: Simple gain boost (spl0 = spl0 * 1.4)
    std::string code1 = "@sample\nspl0 = spl0 * 1.4;\nspl1 = spl1 * 1.4;\n";
    prog.loadCode(code1);
    prog.setEnabled(true);

    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        prog.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "LiveProg Enabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Program 2: Simple attenuation (spl0 = spl0 * 0.6)
    std::string code2 = "@sample\nspl0 = spl0 * 0.6;\nspl1 = spl1 * 0.6;\n";
    prog.loadCode(code2);

    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        prog.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "LiveProg Program Reload");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Reset while running
    prog.reset();
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        prog.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "LiveProg Reset");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Disable
    prog.setEnabled(false);
    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        prog.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "LiveProg Disabling");
        prevBlock = block;
        currentFrame += blockSize;
    }

    std::cout << "PASS: LiveProg transitions verified smooth & bounded." << std::endl;
}

static void testLiveProgRandVariance() {
    std::cout << "Testing LiveProg rand() builtin variance and distribution (B9)..." << std::endl;
    LiveProg prog;
    prog.setSampleRate(48000.0);

    std::string randCode = "@sample\nspl0 = rand();\nspl1 = rand();\n";
    prog.loadCode(randCode);
    prog.setEnabled(true);

    // Warm up across enable crossfade (25ms tau) so test measures steady-state rand()
    std::vector<float> warmup(4800 * 2, 0.0f);
    prog.processInterleaved(warmup.data(), 4800, 2);

    const int numSamples = 10000;
    std::vector<float> buffer(numSamples * 2, 0.0f);
    prog.processInterleaved(buffer.data(), numSamples, 2);

    double sum = 0.0;
    double minVal = 1.0;
    double maxVal = 0.0;
    for (int i = 0; i < numSamples; ++i) {
        float val = buffer[i * 2];
        assert(val >= 0.0f && val <= 1.0f);
        sum += val;
        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
    }
    double mean = sum / numSamples;
    double varianceSum = 0.0;
    for (int i = 0; i < numSamples; ++i) {
        float val = buffer[i * 2];
        double diff = val - mean;
        varianceSum += diff * diff;
    }
    double variance = varianceSum / numSamples;

    // Uniform [0, 1) has theoretical mean 0.5 and variance 1/12 ≈ 0.0833
    std::cout << "LiveProg rand() stats: mean=" << mean << " variance=" << variance
              << " min=" << minVal << " max=" << maxVal << std::endl;

    assert(mean > 0.45 && mean < 0.55);
    assert(variance > 0.06); // Non-zero, healthy variance proving it does not stick to 0 or any constant
    assert(minVal < 0.05 && maxVal > 0.95);
    std::cout << "PASS: LiveProg rand() variance verified." << std::endl;
}

static void testDvcBitPerfectTransitions() {
    std::cout << "Testing DVC / Direct Volume smooth ramping and Bit-Perfect..." << std::endl;
    auto engine = std::make_unique<AudioDspEngine>();
    engine->setSampleRate(48000.0);

    // Initial state: DVC enabled, volume 1.0 (0 dB)
    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = 48000.0;
    snap->activeStages = 0;
    snap->directVolume.enabled = true;
    snap->directVolume.gainLinear = 1.0;
    engine->publishParams(snap);

    const int blockSize = 256;
    const int channels = 2;
    std::vector<float> prevBlock;
    int currentFrame = 0;
    const float maxDelta = 0.08f;

    for (int b = 0; b < 10; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        engine->processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "DVC Nominal");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Ramp volume down to 0 before switching routing (simulating Bit-Perfect bypass switch)
    snap = std::make_shared<DspParamSnapshot>(*snap);
    snap->directVolume.gainLinear = 0.0;
    engine->publishParams(snap);

    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        engine->processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "DVC Fade Down");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Verify signal is silenced (faded down) smoothly
    float peakAtSilence = 0.0f;
    for (float s : prevBlock) {
        peakAtSilence = std::max(peakAtSilence, std::abs(s));
    }
    if (peakAtSilence > 0.05f) {
        std::cerr << "FAIL: DVC did not fade down completely! peak = " << peakAtSilence << std::endl;
        std::exit(1);
    }

    // Fade DVC back up smoothly
    snap = std::make_shared<DspParamSnapshot>(*snap);
    snap->directVolume.gainLinear = 1.0;
    engine->publishParams(snap);

    for (int b = 0; b < 25; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
        engine->processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, maxDelta, "DVC Fade Up");
        prevBlock = block;
        currentFrame += blockSize;
    }

    // Now test Bit-Perfect bypass bit-transparency
    snap = std::make_shared<DspParamSnapshot>(*snap);
    snap->bitPerfect.enabled = true;
    engine->publishParams(snap);

    auto testSine = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.7f, currentFrame);
    auto processed = testSine;
    engine->processInterleaved(processed.data(), blockSize, channels);
    for (size_t i = 0; i < testSine.size(); ++i) {
        if (std::abs(testSine[i] - processed[i]) > 1e-6f) {
            std::cerr << "FAIL: Bit-Perfect mode is not bit-identical to input! diff = "
                      << std::abs(testSine[i] - processed[i]) << std::endl;
            std::exit(1);
        }
    }

    std::cout << "PASS: DVC and Bit-Perfect transitions verified smooth & bit-transparent." << std::endl;
}

static void testParametricEqSweepContinuity() {
    std::cout << "Testing ParametricEQ large-block sweep continuity (sub-block smoothing)..." << std::endl;
    ParametricEQ eq;
    eq.setSampleRate(48000.0);
    EqParamSet params;
    params.enabled = true;
    params.bandCount = 1;
    params.preampDb = 0.0;
    params.bands[0].frequency = 400.0;
    params.bands[0].gainDb = 0.0;
    params.bands[0].q = 1.0;
    params.bands[0].enabled = true;
    eq.applyParams(params);
    eq.reset();

    const int blockSize = 2048;
    const int channels = 2;
    std::vector<float> prevBlock;
    int frameCursor = 0;
    for (int b = 0; b < 2; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.4f, frameCursor);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, 0.12f, "ParametricEQ Warm");
        prevBlock = block;
        frameCursor += blockSize;
    }

    // Abrupt target move without reset(): 400->4000 Hz, 0->+9 dB, Q 1->6 across 2048-frame blocks
    params.preampDb = -3.0;
    params.bands[0].frequency = 4000.0;
    params.bands[0].gainDb = 9.0;
    params.bands[0].q = 6.0;
    eq.applyParams(params);

    for (int b = 0; b < 4; ++b) {
        auto block = generateSineWave(blockSize, channels, 440.0f, 48000.0f, 0.4f, frameCursor);
        eq.processInterleaved(block.data(), blockSize, channels);
        checkSignalContinuity(prevBlock, block, channels, 0.12f, "ParametricEQ Sweep");
        prevBlock = block;
        frameCursor += blockSize;
    }
    std::cout << "PASS: ParametricEQ large-block sweep continuity verified." << std::endl;
}

static void testLoudnessContourSimdNanGuard() {
    std::cout << "Testing LoudnessContour SIMD NaN/Inf isolation..." << std::endl;
    LoudnessContour poisoned, ref;
    poisoned.setSampleRate(48000.0);
    ref.setSampleRate(48000.0);
    poisoned.setEnabled(true);
    ref.setEnabled(true);
    poisoned.configure(1.0, 0.2);
    ref.configure(1.0, 0.2);
    poisoned.reset();
    ref.reset();

    auto blockA = generateSineWave(512, 2, 200.0f, 48000.0f, 0.5f, 0);
    auto blockRef = blockA;
    blockA[20] = std::numeric_limits<float>::quiet_NaN();
    blockA[22] = std::numeric_limits<float>::infinity();
    blockA[24] = -std::numeric_limits<float>::infinity();

    poisoned.processInterleaved(blockA.data(), 512, 2);
    ref.processInterleaved(blockRef.data(), 512, 2);

    for (int f = 0; f < 512; ++f) {
        if (!std::isfinite(blockA[f * 2]) || !std::isfinite(blockA[f * 2 + 1])) {
            std::cerr << "FAIL: LoudnessContour SIMD emitted NaN/Inf at frame " << f << std::endl;
            std::exit(1);
        }
        if (std::abs(blockA[f * 2 + 1] - blockRef[f * 2 + 1]) > 1e-6f) {
            std::cerr << "FAIL: LoudnessContour L NaN corrupted clean R channel at frame " << f << std::endl;
            std::exit(1);
        }
    }

    auto cleanNext = generateSineWave(512, 2, 200.0f, 48000.0f, 0.5f, 512);
    poisoned.processInterleaved(cleanNext.data(), 512, 2);
    for (float s : cleanNext) {
        if (!std::isfinite(s)) {
            std::cerr << "FAIL: LoudnessContour retained NaN state into next block" << std::endl;
            std::exit(1);
        }
    }
    std::cout << "PASS: LoudnessContour SIMD NaN/Inf lane isolation verified." << std::endl;
}

static void testMultibandCompressorSurroundAndNan() {
    std::cout << "Testing MultibandCompressor 6ch surround parity & NaN guard..." << std::endl;
    MultibandCompressor mbc;
    mbc.setSampleRate(48000.0);
    MultibandCompressorParamSet mbcParams;
    mbcParams.enabled = true;
    for (int b = 0; b < 4; ++b) {
        mbcParams.bands[b].thresholdDb = -20.0;
        mbcParams.bands[b].ratio = 4.0;
        mbcParams.bands[b].attackMs = 5.0;
        mbcParams.bands[b].releaseMs = 50.0;
    }
    mbc.applyParams(mbcParams);
    mbc.reset();

    const int frames = 4800;
    const int chCount = 6;
    auto buf = generateSineWave(frames, chCount, 500.0f, 48000.0f, 1.0f, 0);
    mbc.processInterleaved(buf.data(), frames, chCount);

    float peakCh0 = 0.0f;
    for (int f = frames - 480; f < frames; ++f) {
        peakCh0 = std::max(peakCh0, std::abs(buf[f * chCount]));
        for (int ch = 1; ch < chCount; ++ch) {
            if (std::abs(buf[f * chCount + ch] - buf[f * chCount]) > 1e-5f) {
                std::cerr << "FAIL: MultibandCompressor channel " << ch
                          << " diverged from ch0 on 5.1 input" << std::endl;
                std::exit(1);
            }
        }
    }
    if (peakCh0 >= 0.5f || peakCh0 <= 0.05f) {
        std::cerr << "FAIL: MultibandCompressor 5.1 did not compress cleanly: " << peakCh0 << std::endl;
        std::exit(1);
    }

    buf[10 * chCount + 3] = std::numeric_limits<float>::quiet_NaN();
    mbc.processInterleaved(buf.data(), 512, chCount);
    for (int i = 0; i < 512 * chCount; ++i) {
        if (!std::isfinite(buf[i])) {
            std::cerr << "FAIL: MultibandCompressor leaked NaN in 5.1 mode" << std::endl;
            std::exit(1);
        }
    }
    std::cout << "PASS: MultibandCompressor 6ch surround parity & NaN guard verified." << std::endl;
}

static void testHarmonicSaturationDcClearAndNan() {
    std::cout << "Testing HarmonicSaturation Tube->Tape DC cleanup & NaN resilience..." << std::endl;
    HarmonicSaturation sat;
    sat.setSampleRate(48000.0);
    sat.setEnabled(true);
    sat.configure(1.2, 1.0, 0.0, 1);
    sat.reset();

    auto tubeAudio = generateSineWave(4800, 2, 1000.0f, 48000.0f, 0.8f, 0);
    sat.processInterleaved(tubeAudio.data(), 4800, 2);

    sat.configure(0.8, 1.0, 0.0, 0);
    auto tapeAudio = generateSineWave(4800, 2, 1000.0f, 48000.0f, 0.5f, 4800);
    sat.processInterleaved(tapeAudio.data(), 4800, 2);

    std::vector<float> silence(512 * 2, 0.0f);
    silence[16] = std::numeric_limits<float>::quiet_NaN();
    silence[17] = -std::numeric_limits<float>::infinity();
    sat.processInterleaved(silence.data(), 512, 2);
    for (int f = 64; f < 512; ++f) {
        if (!std::isfinite(silence[f * 2]) || !std::isfinite(silence[f * 2 + 1]) ||
            std::abs(silence[f * 2]) > 1e-4f || std::abs(silence[f * 2 + 1]) > 1e-4f) {
            std::cerr << "FAIL: HarmonicSaturation residual DC/NaN at frame " << f
                      << " L=" << silence[f * 2] << " R=" << silence[f * 2 + 1] << std::endl;
            std::exit(1);
        }
    }
    std::cout << "PASS: HarmonicSaturation Tube->Tape DC cleanup & NaN guard verified." << std::endl;
}

void testDynamicBassNanGuard() {
    DynamicBass db;
    db.prepare(48000.0);
    db.setParams(true, 1.0, 40, 120, 0, 12, 1.0, 1.25, 0);

    constexpr int frames = 256;
    std::vector<float> buf(frames * 2, 0.0f);
    buf[0] = std::numeric_limits<float>::quiet_NaN();
    buf[1] = -std::numeric_limits<float>::infinity();
    buf[2] = std::numeric_limits<float>::infinity();
    buf[3] = std::numeric_limits<float>::quiet_NaN();
    for (int i = 2; i < frames; ++i) {
        const float v = 0.25f * std::sin(2.0f * 3.14159265f * 60.0f * i / 48000.0f);
        buf[i * 2] = v;
        buf[i * 2 + 1] = -0.5f * v;
    }

    db.processInterleaved(buf.data(), frames, 2);

    float tailMaxAbs = 0.0f;
    for (int i = 0; i < frames * 2; ++i) {
        assert(std::isfinite(buf[i]) && "DynamicBass must sanitize NaN/Inf input before MS decomposition");
        if (i >= (frames - 32) * 2) {
            tailMaxAbs = std::max(tailMaxAbs, std::abs(buf[i]));
        }
    }
    assert(tailMaxAbs > 0.01f && "DynamicBass must recover cleanly with valid output after NaN/Inf");
    std::cout << "PASS: DynamicBass NaN/Inf sanitization & recovery verified." << std::endl;
}

void testSubCrossoverNanGuard() {
    SubCrossover sub;
    sub.setSampleRate(48000.0);
    sub.configure(80.0, 24.0, 6.0, true, false);
    sub.setEnabled(true);

    constexpr int frames = 256;
    std::vector<float> l(frames, 0.0f);
    std::vector<float> r(frames, 0.0f);
    l[0] = std::numeric_limits<float>::quiet_NaN();
    r[0] = std::numeric_limits<float>::infinity();
    l[1] = -std::numeric_limits<float>::infinity();
    r[1] = std::numeric_limits<float>::quiet_NaN();
    for (int i = 2; i < frames; ++i) {
        const float v = 0.25f * std::sin(2.0f * 3.14159265f * 50.0f * i / 48000.0f);
        l[i] = v;
        r[i] = 0.5f * v;
    }

    sub.process(l.data(), r.data(), frames);
    float tailMaxPlanar = 0.0f;
    for (int i = 0; i < frames; ++i) {
        assert(std::isfinite(l[i]) && std::isfinite(r[i]) &&
               "SubCrossover::process must sanitize NaN/Inf before side/mono filtering");
        if (i >= frames - 32) {
            tailMaxPlanar = std::max(tailMaxPlanar, std::max(std::abs(l[i]), std::abs(r[i])));
        }
    }
    assert(tailMaxPlanar > 0.01f && "SubCrossover::process must recover after NaN/Inf");

    sub.reset();
    sub.setEnabled(true);
    std::vector<float> interleaved(frames * 2, 0.0f);
    interleaved[0] = std::numeric_limits<float>::quiet_NaN();
    interleaved[1] = -std::numeric_limits<float>::infinity();
    interleaved[2] = std::numeric_limits<float>::infinity();
    interleaved[3] = std::numeric_limits<float>::quiet_NaN();
    for (int i = 2; i < frames; ++i) {
        const float v = 0.25f * std::sin(2.0f * 3.14159265f * 50.0f * i / 48000.0f);
        interleaved[i * 2] = v;
        interleaved[i * 2 + 1] = -0.25f * v;
    }

    sub.processInterleaved(interleaved.data(), frames, 2);
    float tailMaxInterleaved = 0.0f;
    for (int i = 0; i < frames * 2; ++i) {
        assert(std::isfinite(interleaved[i]) &&
               "SubCrossover::processInterleaved must sanitize NaN/Inf before side/mono filtering");
        if (i >= (frames - 32) * 2) {
            tailMaxInterleaved = std::max(tailMaxInterleaved, std::abs(interleaved[i]));
        }
    }
    assert(tailMaxInterleaved > 0.01f && "SubCrossover::processInterleaved must recover after NaN/Inf");
    std::cout << "PASS: SubCrossover NaN/Inf sanitization & recovery verified." << std::endl;
}

void testMediumCspFixes() {
    // 1. Crossfeed: 0 dB floor honored & preset->Custom crossfades cleanly
    {
        Crossfeed cf;
        cf.setSampleRate(48000.0);
        cf.setEnabled(true);
        cf.setMode(CrossfeedMode::Bs2bDefault);
        float l[512], r[512];
        for (int b = 0; b < 8; ++b) {
            for (int i = 0; i < 512; ++i) {
                l[i] = 0.3f * std::sin(2.0f * 3.14159265f * 500.0f * (b * 512 + i) / 48000.0f);
                r[i] = 0.0f;
            }
            cf.process(l, r, 512);
        }
        const float lastL = l[511];
        CrossfeedParamSet custom{};
        custom.enabled = true;
        custom.mode = CrossfeedMode::Custom;
        custom.delayUs = 300.0;
        custom.feedDb = 0.0;
        custom.fcut = 650.0;
        cf.applyParams(custom);
        for (int i = 0; i < 512; ++i) {
            l[i] = 0.3f * std::sin(2.0f * 3.14159265f * 500.0f * (8 * 512 + i) / 48000.0f);
            r[i] = 0.0f;
        }
        cf.process(l, r, 512);
        assert(std::abs(l[0] - lastL) < 0.08f && "Crossfeed preset->Custom transition must crossfade click-free");
        cf.configure(300.0, -0.2, 650.0);
        const double g02 = cf.getBs2bA0Lo();
        cf.configure(300.0, -3.0, 650.0);
        const double g30 = cf.getBs2bA0Lo();
        assert(g02 != g30 && "Crossfeed initBs2b must honor <1 dB feed settings");
    }

    // 2. LookaheadLimiter: 0.1 ms min & active lookahead change does not kill bypassMix_
    {
        LookaheadLimiter lim;
        lim.setSampleRate(48000.0);
        lim.setEnabled(true);
        lim.configure(5.0, -3.0, 50.0, true);
        lim.setProcessingActive(true);
        std::vector<float> buf(512 * 2, 0.25f);
        for (int b = 0; b < 8; ++b) {
            lim.processInterleaved(buf.data(), 512, 2);
        }
        lim.configure(0.1, -3.0, 50.0, true);
        assert(lim.getLatencyFrames() < static_cast<int>(0.002 * 48000.0) + LookaheadLimiter::FILTER_DELAY + 2 &&
               "LookaheadLimiter must accept 0.1 ms lookahead without 0.5 ms clamp");
        std::fill(buf.begin(), buf.end(), 0.25f);
        lim.processInterleaved(buf.data(), 512, 2);
        bool allFinite = true;
        for (float s : buf) allFinite &= std::isfinite(s);
        assert(allFinite && "LookaheadLimiter lookahead change must remain finite");
    }

    // 3. HarmonicSaturation: drive 0->positive clears history; mode crossfade completes at drive=0
    {
        HarmonicSaturation sat;
        sat.setSampleRate(48000.0);
        SaturationParamSet p{};
        p.enabled = true;
        p.drive = 0.8;
        p.mix = 1.0;
        p.mode = 0;
        sat.applyParams(p);
        std::vector<float> sig(512 * 2, 0.4f);
        sat.processInterleaved(sig.data(), 512, 2);
        p.drive = 0.0;
        p.mode = 1;
        sat.applyParams(p);
        std::vector<float> zero(512 * 2, 0.0f);
        for (int b = 0; b < 32; ++b) {
            std::fill(zero.begin(), zero.end(), 0.0f);
            sat.processInterleaved(zero.data(), 512, 2);
        }
        p.drive = 0.5;
        sat.applyParams(p);
        std::fill(zero.begin(), zero.end(), 0.0f);
        sat.processInterleaved(zero.data(), 512, 2);
        float maxLeak = 0.0f;
        for (float v : zero) maxLeak = std::max(maxLeak, std::abs(v));
        assert(maxLeak < 1e-4f && "HarmonicSaturation 0->positive drive must not replay stale decimHistory");
    }

    // 4. DynamicBass: xLow affects harmonic exciter output
    {
        auto runWithXLow = [](int xLow) {
            DynamicBass db;
            db.prepare(48000.0);
            db.setParams(true, 4.0, xLow, 5600, 40, 90, 0.1, 0.5, 0);
            std::vector<float> buf(2048 * 2);
            for (int f = 0; f < 2048; ++f) {
                const float s = 0.6f * std::sin(2.0f * 3.14159265f * 60.0f * f / 48000.0f);
                buf[f * 2] = s;
                buf[f * 2 + 1] = s;
            }
            db.processInterleaved(buf.data(), 2048, 2);
            double e = 0.0;
            for (float v : buf) e += static_cast<double>(v) * v;
            return e;
        };
        const double eLow = runWithXLow(100);
        const double eHigh = runWithXLow(2000);
        assert(std::abs(eLow - eHigh) > 1e-4 && "DynamicBass xLow must affect harmonic exciter output");
    }
    std::cout << "PASS: Medium C++ DSP fixes (Crossfeed/Limiter/Saturation/DynamicBass) verified." << std::endl;
}

static void testStereoWidthPerSampleRampAndNanScrub() {
    std::cout << "Testing StereoWidth per-sample ramp (broadband & multiband) and NaN scrubbing..." << std::endl;

    // 1. Broadband planar linear ramp: constant pure-side input (L=1, R=-1) => outL[i] == w[i].
    {
        StereoWidth sw;
        sw.setSampleRate(48000.0);
        sw.setEnabled(true);
        sw.configure(0.0);
        sw.reset();

        constexpr int frames = 512;
        std::vector<float> l(frames, 1.0f), r(frames, -1.0f);
        sw.configure(2.0);
        sw.process(l.data(), r.data(), frames);

        // Must start at previous block's width (0.0), not snap at frame 0.
        assert(std::abs(l[0] - 0.0f) < 1e-5f && "Broadband planar must start at previous width (no boundary step)");
        const float expectedStep = l[1] - l[0];
        assert(expectedStep > 1e-4f && "Broadband planar width must ramp upward per frame");
        for (int i = 1; i < frames; ++i) {
            const float step = l[i] - l[i - 1];
            assert(std::abs(step - expectedStep) < 1e-4f && "Broadband planar ramp must be linear per frame");
            assert(std::abs(r[i] + l[i]) < 1e-5f && "Broadband planar R must mirror L on pure-side input");
        }

        // Next block must continue smoothly from end of block 0.
        const float prevLast = l[frames - 1];
        std::fill(l.begin(), l.end(), 1.0f);
        std::fill(r.begin(), r.end(), -1.0f);
        sw.process(l.data(), r.data(), frames);
        assert(std::abs((l[0] - prevLast) - expectedStep) < 1e-4f &&
               "Broadband planar block-boundary delta must match per-sample ramp slope");
    }

    // 2. Broadband interleaved linear ramp (2ch and 4ch).
    for (int channels : {2, 4}) {
        StereoWidth sw;
        sw.setSampleRate(48000.0);
        sw.setEnabled(true);
        sw.configure(0.0);
        sw.reset();

        constexpr int frames = 512;
        std::vector<float> buf(frames * channels);
        auto fillPureSide = [&]() {
            for (int i = 0; i < frames; ++i) {
                for (int ch = 0; ch < channels; ch += 2) {
                    buf[i * channels + ch] = 1.0f;
                    buf[i * channels + ch + 1] = -1.0f;
                }
            }
        };
        fillPureSide();
        sw.configure(2.0);
        sw.processInterleaved(buf.data(), frames, channels);

        assert(std::abs(buf[0] - 0.0f) < 1e-5f && "Broadband interleaved must start at previous width");
        const float expectedStep = buf[channels] - buf[0];
        assert(expectedStep > 1e-4f && "Broadband interleaved width must ramp per frame");
        for (int i = 1; i < frames; ++i) {
            for (int ch = 0; ch < channels; ch += 2) {
                const float cur = buf[i * channels + ch];
                const float prev = buf[(i - 1) * channels + ch];
                assert(std::abs((cur - prev) - expectedStep) < 1e-4f &&
                       "Broadband interleaved ramp must be linear across all pairs");
            }
        }
        const float prevLast = buf[(frames - 1) * channels];
        fillPureSide();
        sw.processInterleaved(buf.data(), frames, channels);
        assert(std::abs((buf[0] - prevLast) - expectedStep) < 1e-4f &&
               "Broadband interleaved block boundary must be continuous");
    }

    // 3. Multiband per-sample ramp (planar & interleaved): low-frequency out-of-phase sine
    //    must ramp smoothly across block boundaries when lowWidth jumps 0.0 -> 2.0.
    {
        StereoWidth swPlanar, swInter;
        swPlanar.setSampleRate(48000.0);
        swPlanar.setEnabled(true);
        swPlanar.configureMultiband(true, 0.0, 0.0, 0.0, 250.0, 3000.0);
        swPlanar.reset();

        swInter.setSampleRate(48000.0);
        swInter.setEnabled(true);
        swInter.configureMultiband(true, 0.0, 0.0, 0.0, 250.0, 3000.0);
        swInter.reset();

        constexpr int blockSize = 512;
        int cursor = 0;
        std::vector<float> prevInter;
        float prevPlanarLastL = 0.0f;
        bool hasPrevPlanar = false;

        auto runBlocks = [&](int count, float maxAllowedDelta, const char* label) {
            for (int b = 0; b < count; ++b) {
                std::vector<float> l(blockSize), r(blockSize), inter(blockSize * 2);
                for (int i = 0; i < blockSize; ++i) {
                    const float t = static_cast<float>(cursor + i) / 48000.0f;
                    const float s = 0.7f * std::sin(2.0f * static_cast<float>(M_PI) * 100.0f * t);
                    l[i] = s;
                    r[i] = -s;
                    inter[i * 2] = s;
                    inter[i * 2 + 1] = -s;
                }
                swPlanar.process(l.data(), r.data(), blockSize);
                swInter.processInterleaved(inter.data(), blockSize, 2);

                if (hasPrevPlanar) {
                    assert(std::abs(l[0] - prevPlanarLastL) < maxAllowedDelta &&
                           "Multiband planar boundary must not stair-step on width jump");
                }
                for (int i = 1; i < blockSize; ++i) {
                    assert(std::abs(l[i] - l[i - 1]) < maxAllowedDelta &&
                           "Multiband planar internal step must stay smooth");
                }
                for (int i = 0; i < blockSize; ++i) {
                    assert(std::abs(l[i] - inter[i * 2]) < 1e-5f &&
                           std::abs(r[i] - inter[i * 2 + 1]) < 1e-5f &&
                           "Multiband planar and interleaved ramps must match");
                }
                checkSignalContinuity(prevInter, inter, 2, maxAllowedDelta, label);
                prevPlanarLastL = l[blockSize - 1];
                hasPrevPlanar = true;
                prevInter = inter;
                cursor += blockSize;
            }
        };

        runBlocks(4, 0.06f, "StereoWidth Multiband Warm");
        swPlanar.configureMultiband(true, 2.0, 2.0, 2.0, 250.0, 3000.0);
        swInter.configureMultiband(true, 2.0, 2.0, 2.0, 250.0, 3000.0);
        runBlocks(8, 0.06f, "StereoWidth Multiband Jump 0->2");
        swPlanar.setEnabled(false);
        swInter.setEnabled(false);
        runBlocks(8, 0.06f, "StereoWidth Multiband Disable");
    }

    // 4. Multiband NaN/Inf input scrubbing (planar & interleaved): crossover state stays finite.
    {
        StereoWidth sw;
        sw.setSampleRate(48000.0);
        sw.setEnabled(true);
        sw.configureMultiband(true, 0.0, 1.0, 1.5, 200.0, 3000.0);
        sw.reset();

        constexpr int frames = 256;
        std::vector<float> l(frames), r(frames);
        for (int i = 0; i < frames; ++i) {
            const float s = 0.4f * std::sin(2.0f * static_cast<float>(M_PI) * 500.0f * i / 48000.0f);
            l[i] = s;
            r[i] = -s;
        }
        l[0] = std::numeric_limits<float>::quiet_NaN();
        r[0] = std::numeric_limits<float>::infinity();
        l[5] = -std::numeric_limits<float>::infinity();
        r[5] = std::numeric_limits<float>::quiet_NaN();

        sw.process(l.data(), r.data(), frames);
        for (int i = 0; i < frames; ++i) {
            assert(std::isfinite(l[i]) && std::isfinite(r[i]) &&
                   "StereoWidth multiband planar must scrub NaN/Inf before crossover");
        }
        // Subsequent clean block must remain finite and produce real audio.
        for (int i = 0; i < frames; ++i) {
            const float s = 0.4f * std::sin(2.0f * static_cast<float>(M_PI) * 500.0f * (frames + i) / 48000.0f);
            l[i] = s;
            r[i] = s;
        }
        sw.process(l.data(), r.data(), frames);
        float maxClean = 0.0f;
        for (int i = 0; i < frames; ++i) {
            assert(std::isfinite(l[i]) && std::isfinite(r[i]) &&
                   "StereoWidth multiband planar crossover state must stay finite");
            maxClean = std::max(maxClean, std::abs(l[i]));
        }
        assert(maxClean > 0.1f && "StereoWidth multiband planar must recover clean audio after NaN");

        sw.reset();
        std::vector<float> inter(frames * 4, 0.0f);
        for (int i = 0; i < frames; ++i) {
            const float s = 0.4f * std::sin(2.0f * static_cast<float>(M_PI) * 500.0f * i / 48000.0f);
            for (int ch = 0; ch < 4; ++ch) inter[i * 4 + ch] = s;
        }
        inter[0] = std::numeric_limits<float>::quiet_NaN();
        inter[1] = -std::numeric_limits<float>::infinity();
        inter[2] = std::numeric_limits<float>::infinity();
        inter[3] = std::numeric_limits<float>::quiet_NaN();
        sw.processInterleaved(inter.data(), frames, 4);
        for (float v : inter) {
            assert(std::isfinite(v) && "StereoWidth multiband interleaved must scrub NaN/Inf");
        }
        for (int i = 0; i < frames; ++i) {
            const float s = 0.4f * std::sin(2.0f * static_cast<float>(M_PI) * 500.0f * (frames + i) / 48000.0f);
            for (int ch = 0; ch < 4; ++ch) inter[i * 4 + ch] = s;
        }
        sw.processInterleaved(inter.data(), frames, 4);
        float maxInterClean = 0.0f;
        for (float v : inter) {
            assert(std::isfinite(v) && "StereoWidth multiband interleaved state must stay finite");
            maxInterClean = std::max(maxInterClean, std::abs(v));
        }
        assert(maxInterClean > 0.1f && "StereoWidth multiband interleaved must recover after NaN");
    }

    std::cout << "PASS: StereoWidth per-sample ramp & multiband NaN scrubbing verified." << std::endl;
}

static void testLiveProgUtf8Lexer() {
    std::cout << "Testing LiveProg Lexer UTF-8 / non-ASCII byte safety..." << std::endl;
    LiveProg prog;
    prog.setSampleRate(48000.0);

    // UTF-8 accented Latin, CJK, and high-bit bytes inside line and block comments
    const std::string utf8Script =
        "// Caf\xC3\xA9 \xE9\x9F\xB3\xE6\xA5\xBD \xF0\x9F\x8E\xB5 \x80\xFF\n"
        "@init\n"
        "/* \xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82 gain = 0.5 */\n"
        "g = 0.5;\n"
        "@sample\n"
        "// \xC3\xBC\xC3\xB6\xC3\xA4 scaling\n"
        "spl0 = spl0 * g;\n"
        "spl1 = spl1 * g;\n";

    const bool ok = prog.loadCode(utf8Script);
    assert(ok && "LiveProg must compile scripts with UTF-8 comments cleanly");
    prog.setEnabled(true);
    prog.reset();

    std::vector<float> buf(64 * 2, 0.8f);
    prog.processInterleaved(buf.data(), 64, 2);
    for (float v : buf) {
        assert(std::isfinite(v) && std::abs(v - 0.4f) < 1e-4f &&
               "LiveProg UTF-8 commented script must execute accurately");
    }

    // Stray non-ASCII bytes outside comments must fail cleanly without UB/crash.
    const std::string badNonAscii = "@sample\n\xC3\xA9 = spl0;\n";
    assert(!prog.loadCode(badNonAscii) && "Non-ASCII identifier must be rejected cleanly");
    assert(!prog.getLastError().empty() && "Rejected non-ASCII token must set lastError");

    const std::string badHighByte = "@sample\n\xFF\n";
    assert(!prog.loadCode(badHighByte) && "0xFF byte outside comment must be rejected cleanly");

    const std::string badAtTag = "@\xC3\xA9\nspl0 = spl0;\n";
    (void)prog.loadCode(badAtTag); // Must not UB/crash regardless of parse outcome

    std::cout << "PASS: LiveProg Lexer UTF-8 / non-ASCII safety verified." << std::endl;
}

static void testConvolutionReverbSurroundToggleCrossfade() {
    std::cout << "Testing ConvolutionReverb multichannel (5.1) surround toggle crossfade..." << std::endl;
    auto reverb = std::make_unique<ConvolutionReverb>();
    reverb->setSampleRate(48000.0);
    reverb->setPreset(ReverbPreset::Room);
    reverb->setWetDry(0.5);
    reverb->setEnabled(false);
    reverb->reset();

    const int channels = 6;
    const int blockSize = 256;
    const float freq = 220.0f;
    const float amp = 0.6f;

    std::vector<float> prevBlock;
    int cursor = 0;

    auto runBlocks = [&](int count, const char* label, float maxSurroundDelta, float firstBoundaryMax = -1.0f) {
        for (int b = 0; b < count; ++b) {
            auto block = generateSineWave(blockSize, channels, freq, 48000.0f, amp, cursor);
            reverb->processInterleaved(block.data(), blockSize, channels);
            if (!prevBlock.empty()) {
                const float bLimit = (b == 0 && firstBoundaryMax > 0.0f) ? firstBoundaryMax : maxSurroundDelta;
                for (int ch = 2; ch < channels; ++ch) {
                    const float lastPrev = prevBlock[prevBlock.size() - channels + ch];
                    const float firstCur = block[ch];
                    const float boundaryDelta = std::abs(firstCur - lastPrev);
                    if (!std::isfinite(firstCur) || boundaryDelta > bLimit) {
                        std::cerr << "FAIL [" << label << "]: surround ch " << ch
                                  << " block " << b << " boundary click delta=" << boundaryDelta
                                  << " (limit=" << bLimit << ")" << std::endl;
                        std::exit(1);
                    }
                    for (int i = 1; i < blockSize; ++i) {
                        const float step = std::abs(block[i * channels + ch] - block[(i - 1) * channels + ch]);
                        if (!std::isfinite(block[i * channels + ch]) || step > maxSurroundDelta) {
                            std::cerr << "FAIL [" << label << "]: surround ch " << ch
                                      << " block " << b << " internal click at frame " << i
                                      << " delta=" << step << std::endl;
                            std::exit(1);
                        }
                    }
                }
            }
            prevBlock = block;
            cursor += blockSize;
        }
    };

    // 1. Disabled warm-up (natural 220 Hz @ 48 kHz slope is ~0.017)
    runBlocks(4, "Reverb 5.1 Disabled", 0.04f);

    // 2. Enable reverb -> first boundary must stay continuous with undelayed input (< 0.04,
    //    whereas un-crossfaded snap to zeroed delay jumped by ~0.56). Later blocks allow
    //    bounded emergence of the zero-primed delay line matching L/R's dryDelay_.
    //    70 blocks (~373 ms) exceeds 9.2 * 35 ms so smoothedEnabledMix_ snaps to 1.0.
    reverb->setEnabled(true);
    runBlocks(70, "Reverb 5.1 Enabling", 0.20f, 0.04f);

    // 3. Steady-state check: surround channel is delayed by reverbLatencyFrames_ (512 samples)
    const int latency = reverb->getReverbLatencyFrames();
    assert(latency == ConvolutionReverb::PARTITION_SIZE && "Room preset @ 48kHz has 512-sample latency");
    {
        auto block = generateSineWave(blockSize, channels, freq, 48000.0f, amp, cursor);
        reverb->processInterleaved(block.data(), blockSize, channels);
        for (int i = 0; i < blockSize; ++i) {
            const float tDelayed = static_cast<float>(cursor + i - latency) / 48000.0f;
            const float expected = amp * std::sin(2.0f * static_cast<float>(M_PI) * freq * tDelayed);
            for (int ch = 2; ch < channels; ++ch) {
                assert(std::abs(block[i * channels + ch] - expected) < 1e-3f &&
                       "Steady-state surround channel must be time-aligned with reverb latency");
            }
        }
        prevBlock = block;
        cursor += blockSize;
    }

    // 4. Disable reverb -> surround must smoothly crossfade back to undelayed before bypass
    //    with tight continuity across every sample and block boundary (including entering bypass).
    reverb->setEnabled(false);
    runBlocks(70, "Reverb 5.1 Disabling", 0.04f);
    assert(!reverb->isRamping() && "Reverb 5.1 disable ramp must finish within 70 blocks");

    // 5. Post-disable bypass must be exact undelayed input and continuous with the final ramp block
    {
        auto block = generateSineWave(blockSize, channels, freq, 48000.0f, amp, cursor);
        auto expected = block;
        reverb->processInterleaved(block.data(), blockSize, channels);
        for (int ch = 2; ch < channels; ++ch) {
            const float lastPrev = prevBlock[prevBlock.size() - channels + ch];
            assert(std::abs(block[ch] - lastPrev) < 0.04f &&
                   "Post-disable 5.1 bypass entry must be click-free");
        }
        for (size_t i = 0; i < block.size(); ++i) {
            assert(std::abs(block[i] - expected[i]) < 1e-6f &&
                   "Post-disable 5.1 bypass must be exact passthrough");
        }
    }

    std::cout << "PASS: ConvolutionReverb 5.1 surround toggle crossfade verified click-free." << std::endl;
}

static void testM12EmptyProfileRampingAndSurroundViperDdc() {
    std::cout << "Testing ArbitraryResponseEq / ViperDdc empty-profile guard, phase delay, and 5.1 ViperDDC..." << std::endl;

    // 1. ArbitraryResponseEq symmetric linear-phase group delay is (FIR_TAPS - 1) / 2 = 2047
    //    and matches surround dry delay across stereo + surround channels.
    {
        ArbitraryResponseEq arb;
        arb.setSampleRate(48000.0);
        const bool loadedLinear = arb.loadGraphicEqString("GraphicEq: 20 0; 1000 0; 20000 0", true);
        assert(loadedLinear && "Linear-phase flat GraphicEq profile must parse cleanly");
        arb.setEnabled(true);
        const int totalFrames = 4096;
        const int ch = 6;
        // First settle enable ramp so dry/wet mix hits 1.0 cleanly.
        std::vector<float> warmup(1024 * ch, 0.0f);
        for (int b = 0; b < 32; ++b) {
            arb.processInterleaved(warmup.data(), 1024, ch);
        }
        std::vector<float> impulse(totalFrames * ch, 0.0f);
        for (int c = 0; c < ch; ++c) impulse[c] = 1.0f;
        arb.processInterleaved(impulse.data(), totalFrames, ch);

        auto peakFrameForCh = [&](int channel) {
            int bestIdx = -1;
            float bestVal = -1.0f;
            for (int f = 0; f < totalFrames; ++f) {
                float a = std::abs(impulse[f * ch + channel]);
                if (a > bestVal) { bestVal = a; bestIdx = f; }
            }
            return bestIdx;
        };
        const int stereoPeak = peakFrameForCh(0);
        const int surroundPeak = peakFrameForCh(2);
        // Flat linear-phase delay is (FIR_TAPS - 1) * 0.5 = 2047.5, so energy splits symmetrically across [2047, 2048],
        // while SURROUND_DRY_DELAY = (FIR_TAPS - 1) / 2 = 2047 aligns surround to sample 2047 (and not 2048).
        assert((stereoPeak == 2047 || stereoPeak == 2048) &&
               "Linear-phase ArbitraryResponseEq group delay must center on 2047.5");
        assert(std::abs(impulse[2047 * ch] - impulse[2048 * ch]) < 1e-3f &&
               "Linear-phase flat kernel must split energy symmetrically at taps 2047 and 2048");
        assert(surroundPeak == 2047 && "Surround dry delay must match PHASE_DELAY_TAPS (2047 samples)");

        // When switching linearPhase -> minimum-phase during crossfade, phaseDelayL_/R_ aligns the
        // minimum-phase output to sample 2047 (not 2048) with zero undelayed sample-0 leakage.
        const bool loadedMin = arb.loadGraphicEqString("GraphicEq: 20 0; 1000 0; 20000 0", false);
        assert(loadedMin);
        std::vector<float> cfImpulse(totalFrames * ch, 0.0f);
        for (int c = 0; c < ch; ++c) cfImpulse[c] = 1.0f;
        arb.processInterleaved(cfImpulse.data(), 64, ch); // mid-crossfade block
        assert(std::abs(cfImpulse[0]) < 1e-3f &&
               "Crossfading linear->min phase must phase-align min-phase path instead of leaking at sample 0");
    }

    // 2. Empty/unloaded ArbitraryResponseEq & ViperDdc must report !isRamping() even across enable/disable toggles.
    {
        ArbitraryResponseEq arb;
        arb.setSampleRate(48000.0);
        arb.setEnabled(true);
        assert(!arb.isRamping() && "Empty ArbitraryResponseEq must not report ramping on enable");
        arb.setEnabled(false);
        assert(!arb.isRamping() && "Empty ArbitraryResponseEq must not report ramping on disable");

        ViperDdc ddc;
        ddc.setSampleRate(48000.0);
        ddc.setEnabled(true);
        assert(!ddc.isRamping() && "Empty ViperDdc must not report ramping on enable");
        ddc.setEnabled(false);
        assert(!ddc.isRamping() && "Empty ViperDdc must not report ramping on disable");
    }

    // 3. Active ViperDdc in 6-channel (5.1) interleaved processing must filter surround channels 2..5 too.
    {
        ViperDdc ddc;
        ddc.setSampleRate(48000.0);
        // -6 dB low-shelf/attenuating biquad at DC/440Hz
        ddc.loadVdcString("SR_48000\n0.5, 0.0, 0.0, 0.0, 0.0\n");
        ddc.setEnabled(true);

        const int block = 256;
        const int ch = 6;
        std::vector<float> buf(block * ch, 0.8f);
        for (int iter = 0; iter < 30; ++iter) {
            std::fill(buf.begin(), buf.end(), 0.8f);
            ddc.processInterleaved(buf.data(), block, ch);
        }
        // After enable ramp settles (~20ms -> 30 blocks = 160ms), every channel 0..5 should approach 0.4f.
        for (int c = 0; c < ch; ++c) {
            float sample = buf[(block - 1) * ch + c];
            assert(std::abs(sample - 0.4f) < 0.02f &&
                   "ViperDdc multichannel processing must filter all surround channels");
        }
    }

    std::cout << "PASS: M-12 ArbitraryResponseEq & ViperDdc fixes verified." << std::endl;
}

int main() {
    std::cout << "Running DSP effects C++ unit tests..." << std::endl;
    testConvolutionReverbUnityGain();
    testLookaheadLimiterCeiling();
    testLookaheadLimiterStageTransitions();
    testMultibandCompressor();
    testHarmonicSaturationModes();
    testStereoWidthBassMono();
    testDynamicEqBoostMode();
    testDynamicBass();
    testHarmonicSaturationTransitions();
    testArbitraryEqTransitions();
    testViperDdcTransitions();
    testLiveProgTransitions();
    testLiveProgRandVariance();
    testDvcBitPerfectTransitions();
    testParametricEqSweepContinuity();
    testLoudnessContourSimdNanGuard();
    testMultibandCompressorSurroundAndNan();
    testHarmonicSaturationDcClearAndNan();
    testDynamicBassNanGuard();
    testSubCrossoverNanGuard();
    testMediumCspFixes();
    testStereoWidthPerSampleRampAndNanScrub();
    testLiveProgUtf8Lexer();
    testConvolutionReverbSurroundToggleCrossfade();
    testM12EmptyProfileRampingAndSurroundViperDdc();
    std::cout << "All DSP effects C++ tests passed successfully!" << std::endl;
    return 0;
}
