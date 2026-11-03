// android/app/src/test/cpp/test_dsd_dynamic_cic.cpp
//
// Dynamic CIC decimation keeps Stage 1 at 352.8 kHz for every DSD rate, so the
// Stage 2 anti-alias FIR has the same sharp transition band for DSD512 as for
// DSD64. A 30 kHz tone in a 48 kHz output must alias >80 dB down.
#include "../../main/cpp/DsdDecoder.h"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {
int gFailures = 0;
void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

// Single-bin Hann-windowed DFT amplitude.
double toneAmplitude(const std::vector<float>& pcm, int frames, double freq,
                     double sampleRate) {
    if (frames <= 1) return 0.0;
    const int start = frames / 4;
    const int count = frames - start;
    double re = 0.0;
    double im = 0.0;
    double wsum = 0.0;
    for (int n = 0; n < count; ++n) {
        const double w = 0.5 - 0.5 * std::cos(2.0 * M_PI * n / (count - 1));
        const double phase = 2.0 * M_PI * freq * n / sampleRate;
        const double x = pcm[static_cast<size_t>(start + n) * 2];
        re += w * x * std::cos(phase);
        im -= w * x * std::sin(phase);
        wsum += w;
    }
    return 2.0 * std::sqrt(re * re + im * im) / wsum;
}

std::vector<float> decodeDsd512Tone(double toneHz, int targetRate,
                                    int dsdBytes, int& actualFrames) {
    DsdDecoder decoder;
    decoder.configure(DsdDecoder::DsdRate::DSD512, targetRate,
                      DsdDecoder::DsdBitOrder::LSB_FIRST);

    std::vector<uint8_t> data(dsdBytes, 0);
    const double dsdRate = 44100.0 * 512.0;
    double integrator = 0.0;
    for (int byteIdx = 0; byteIdx < dsdBytes; ++byteIdx) {
        uint8_t byte = 0;
        for (int bit = 0; bit < 8; ++bit) {
            const int sampleIdx = byteIdx * 8 + bit;
            const double input =
                0.5 * std::sin(2.0 * M_PI * toneHz *
                               static_cast<double>(sampleIdx) / dsdRate);
            integrator += input;
            const int out = (integrator >= 0.0) ? 1 : 0;
            integrator -= (out ? 1.0 : -1.0);
            if (out) byte |= (1 << bit);
        }
        data[byteIdx] = byte;
    }

    const int maxFrames = decoder.getExpectedPcmFrames(dsdBytes);
    std::vector<float> pcm(static_cast<size_t>(maxFrames) * 2, 0.0f);
    actualFrames = decoder.decodeDsdBytes(data.data(), data.data(), dsdBytes,
                                          pcm.data(), maxFrames);
    return pcm;
}
}  // namespace

int main() {
    std::cout << "[TEST] DSD dynamic CIC decimation..." << std::endl;

    {
        DsdDecoder decoder;
        decoder.configure(DsdDecoder::DsdRate::DSD64, 48000);
        check(decoder.getCicDecimFactor() == 8, "DSD64 CIC factor is 8x");
        decoder.configure(DsdDecoder::DsdRate::DSD128, 48000);
        check(decoder.getCicDecimFactor() == 16, "DSD128 CIC factor is 16x");
        decoder.configure(DsdDecoder::DsdRate::DSD256, 48000);
        check(decoder.getCicDecimFactor() == 32, "DSD256 CIC factor is 32x");
        decoder.configure(DsdDecoder::DsdRate::DSD512, 48000);
        check(decoder.getCicDecimFactor() == 64, "DSD512 CIC factor is 64x");
    }

    const int targetRate = 48000;
    const int dsdBytes = 44100 * 512 / 8 / 4;  // ~0.25 s of DSD512
    int passFrames = 0;
    int stopFrames = 0;
    const auto passband = decodeDsd512Tone(1000.0, targetRate, dsdBytes, passFrames);
    const auto stopband = decodeDsd512Tone(30000.0, targetRate, dsdBytes, stopFrames);

    check(passFrames > 1000 && stopFrames > 1000, "decoded enough PCM frames");
    const double passTone = toneAmplitude(passband, passFrames, 1000.0, targetRate);
    // 30 kHz aliases to 18 kHz at a 48 kHz output rate.
    const double aliasTone = toneAmplitude(stopband, stopFrames, 18000.0, targetRate);
    check(passTone > 0.05, "1 kHz passband tone survives");
    const double attenuationDb = 20.0 * std::log10(std::max(passTone, 1e-12) /
                                                   std::max(aliasTone, 1e-12));
    std::cout << "  passband=" << passTone << " alias=" << aliasTone
              << " attenuation=" << attenuationDb << " dB" << std::endl;
    check(attenuationDb > 80.0,
          "DSD512 >24 kHz content is attenuated by more than 80 dB");

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " DSD dynamic CIC check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] DSD dynamic CIC decimation is correct." << std::endl;
    return 0;
}
