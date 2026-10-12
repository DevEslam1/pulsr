// scripts/bench_native_dsp.cpp
//
// Standalone micro-benchmark harness for Pulsr native DSP algorithms.
// Runnable on host or on Android device via adb shell:
//   $CXX -O3 -std=c++20 -Iandroid/app/src/main/cpp scripts/bench_native_dsp.cpp \
//       android/app/src/main/cpp/{ParametricEQ,LookaheadLimiter,StereoWidth,SincResampler}.cpp \
//       -o bench_dsp
//   adb push bench_dsp /data/local/tmp/
//   adb shell /data/local/tmp/bench_dsp
//
#include <iostream>
#include <vector>
#include <chrono>
#include <cmath>
#include <numeric>
#include <iomanip>

#include "ParametricEQ.h"
#include "LookaheadLimiter.h"
#include "StereoWidth.h"
#include "SincResampler.h"

namespace {

constexpr int kSampleRate = 48000;
constexpr int kBlockSize = 512;
constexpr int kNumBlocks = 2000; // ~21.3s of audio processed
constexpr int kChannels = 2;

std::vector<float> generateSineWave(int totalSamples, float freq = 1000.0f) {
    std::vector<float> buf(totalSamples);
    for (int i = 0; i < totalSamples; ++i) {
        buf[i] = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * freq * (i / 2) / kSampleRate);
    }
    return buf;
}

template <typename Func>
double benchmark(const std::string& name, Func&& func) {
    // Warm-up
    func();

    const auto start = std::chrono::high_resolution_clock::now();
    func();
    const auto end = std::chrono::high_resolution_clock::now();

    const std::chrono::duration<double, std::milli> elapsed = end - start;
    const double totalAudioSec = (static_cast<double>(kNumBlocks * kBlockSize)) / kSampleRate;
    const double speedupFactor = totalAudioSec / (elapsed.count() / 1000.0);

    std::cout << std::left << std::setw(28) << name 
              << " | Time: " << std::fixed << std::setprecision(2) << std::setw(7) << elapsed.count() << " ms"
              << " | Speedup: " << std::setw(6) << std::setprecision(1) << speedupFactor << "x real-time"
              << std::endl;
    return elapsed.count();
}

} // namespace

int main() {
    std::cout << "==========================================================" << std::endl;
    std::cout << "Pulsr Native DSP Micro-Benchmark (SIMD / NEON Verification)" << std::endl;
    std::cout << "Blocks: " << kNumBlocks << " x " << kBlockSize << " frames ("
              << (kNumBlocks * kBlockSize * 1000 / kSampleRate) << " ms audio)" << std::endl;
    std::cout << "==========================================================" << std::endl;

    const int totalFloats = kNumBlocks * kBlockSize * kChannels;
    auto testSignal = generateSineWave(totalFloats);

    // 1. ParametricEQ (10 bands)
    {
        ParametricEQ eq;
        eq.setSampleRate(kSampleRate);
        eq.setBandCount(10);
        for (int i = 0; i < 10; ++i) {
            eq.setBandGain(i, 3.0);
        }
        auto buffer = testSignal;
        benchmark("ParametricEQ (10-band IIR)", [&]() {
            for (int b = 0; b < kNumBlocks; ++b) {
                eq.processInterleaved(buffer.data() + b * kBlockSize * kChannels, kBlockSize, kChannels);
            }
        });
    }

    // 2. LookaheadLimiter
    {
        LookaheadLimiter limiter;
        limiter.setSampleRate(kSampleRate);
        limiter.configure(5.0, -0.5, 50.0, true);
        auto buffer = testSignal;
        benchmark("LookaheadLimiter (Peak Limiter)", [&]() {
            for (int b = 0; b < kNumBlocks; ++b) {
                limiter.processInterleaved(buffer.data() + b * kBlockSize * kChannels, kBlockSize, kChannels);
            }
        });
    }

    // 3. StereoWidth (M/S matrix expansion)
    {
        StereoWidth sw;
        sw.setSampleRate(kSampleRate);
        sw.setWidth(1.5f);
        auto buffer = testSignal;
        benchmark("StereoWidth (M/S Matrix)", [&]() {
            for (int b = 0; b < kNumBlocks; ++b) {
                sw.processInterleaved(buffer.data() + b * kBlockSize * kChannels, kBlockSize, kChannels);
            }
        });
    }

    // 4. SincResampler (Planar polyphase filter)
    {
        SincResampler resampler;
        resampler.setRates(44100.0, 48000.0);
        resampler.setQuality(3); // Ultra 64-tap
        resampler.setEnabled(true);
        std::vector<float> inCh0(kBlockSize, 0.5f);
        std::vector<float> inCh1(kBlockSize, 0.5f);
        std::vector<float> outCh0(kBlockSize * 2, 0.0f);
        std::vector<float> outCh1(kBlockSize * 2, 0.0f);
        const float* inPlanar[2] = { inCh0.data(), inCh1.data() };
        float* outPlanar[2] = { outCh0.data(), outCh1.data() };

        benchmark("SincResampler (64-tap FIR)", [&]() {
            for (int b = 0; b < kNumBlocks; ++b) {
                resampler.processPlanar(inPlanar, outPlanar, kBlockSize, 2, kBlockSize * 2);
            }
        });
    }

    std::cout << "==========================================================" << std::endl;
    std::cout << "All benchmarks completed successfully." << std::endl;
    return 0;
}
