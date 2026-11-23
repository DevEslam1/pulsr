// android/app/src/test/cpp/test_hrtf_binaural.cpp
#include "../../main/cpp/HrtfBinaural.h"

#include <iostream>
#include <vector>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <algorithm>
#include <numeric>
#include <atomic>
#include <thread>
#include <limits>

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    } else {
        std::cout << "[PASS] " << what << std::endl;
    }
}

void writeBe32(std::vector<uint8_t>& buf, uint32_t val) {
    buf.push_back(static_cast<uint8_t>((val >> 24) & 0xFF));
    buf.push_back(static_cast<uint8_t>((val >> 16) & 0xFF));
    buf.push_back(static_cast<uint8_t>((val >> 8) & 0xFF));
    buf.push_back(static_cast<uint8_t>(val & 0xFF));
}

void writeBeDouble(std::vector<uint8_t>& buf, double val) {
    uint64_t u;
    std::memcpy(&u, &val, sizeof(double));
    writeBe32(buf, static_cast<uint32_t>((u >> 32) & 0xFFFFFFFF));
    writeBe32(buf, static_cast<uint32_t>(u & 0xFFFFFFFF));
}

void writeString(std::vector<uint8_t>& buf, const std::string& str) {
    writeBe32(buf, static_cast<uint32_t>(str.size()));
    for (char c : str) buf.push_back(static_cast<uint8_t>(c));
    size_t pad = ((str.size() + 3) / 4) * 4 - str.size();
    for (size_t p = 0; p < pad; ++p) buf.push_back(0);
}

// Builds a synthetic NetCDF-3 classic SOFA buffer for testing
std::vector<uint8_t> createSyntheticSofaNetCdf3(int M, int R, int N,
                                                double sampleRate = 48000.0) {
    std::vector<uint8_t> buf;
    // Magic: CDF\x01
    buf.push_back('C'); buf.push_back('D'); buf.push_back('F'); buf.push_back(1);
    writeBe32(buf, 0); // numrecs = 0

    // Dimensions: tag 0x0000000A, count = 4 (M, R, N, C)
    writeBe32(buf, 0x0000000A);
    writeBe32(buf, 4);

    writeString(buf, "M"); writeBe32(buf, M);
    writeString(buf, "R"); writeBe32(buf, R);
    writeString(buf, "N"); writeBe32(buf, N);
    writeString(buf, "C"); writeBe32(buf, 3); // 3 coordinate dimensions

    // Global attributes: tag 0
    writeBe32(buf, 0);

    // Variables: tag 0x0000000B, count = 3 (SourcePosition, Data.SamplingRate, Data.IR)
    writeBe32(buf, 0x0000000B);
    writeBe32(buf, 3);

    // Placeholder offsets to fix up after header layout
    // 1. SourcePosition [M, C] -> double (type=6)
    writeString(buf, "SourcePosition");
    writeBe32(buf, 2); // 2 dims
    writeBe32(buf, 0); // dim M
    writeBe32(buf, 3); // dim C
    writeBe32(buf, 0); // no attrs
    writeBe32(buf, 6); // nc_type = double
    writeBe32(buf, M * 3 * 8); // vsize
    size_t posOffsetLoc = buf.size();
    writeBe32(buf, 0); // begin offset placeholder

    // 2. Data.SamplingRate [] -> double (type=6)
    writeString(buf, "Data.SamplingRate");
    writeBe32(buf, 0); // scalar
    writeBe32(buf, 0); // no attrs
    writeBe32(buf, 6); // nc_type = double
    writeBe32(buf, 8); // vsize = 8
    size_t srOffsetLoc = buf.size();
    writeBe32(buf, 0); // begin offset placeholder

    // 3. Data.IR [M, R, N] -> double (type=6)
    writeString(buf, "Data.IR");
    writeBe32(buf, 3); // 3 dims
    writeBe32(buf, 0); // M
    writeBe32(buf, 1); // R
    writeBe32(buf, 2); // N
    writeBe32(buf, 0); // no attrs
    writeBe32(buf, 6); // nc_type = double
    writeBe32(buf, M * R * N * 8); // vsize
    size_t irOffsetLoc = buf.size();
    writeBe32(buf, 0); // begin offset placeholder

    // Align data section to 4-byte boundary
    while (buf.size() % 4 != 0) buf.push_back(0);

    // Fix up begin offsets
    uint32_t posBegin = static_cast<uint32_t>(buf.size());
    buf[posOffsetLoc]     = (posBegin >> 24) & 0xFF;
    buf[posOffsetLoc + 1] = (posBegin >> 16) & 0xFF;
    buf[posOffsetLoc + 2] = (posBegin >> 8) & 0xFF;
    buf[posOffsetLoc + 3] = posBegin & 0xFF;

    // Write SourcePosition data: [M, 3] = { {azimuth, elevation, distance}, ... }
    // Positions: -30 deg, 0 deg, +30 deg
    for (int m = 0; m < M; ++m) {
        double az = (m == 0) ? -30.0 : (m == 1 ? 0.0 : +30.0);
        double el = 0.0;
        double dist = 1.4;
        writeBeDouble(buf, az);
        writeBeDouble(buf, el);
        writeBeDouble(buf, dist);
    }

    uint32_t srBegin = static_cast<uint32_t>(buf.size());
    buf[srOffsetLoc]     = (srBegin >> 24) & 0xFF;
    buf[srOffsetLoc + 1] = (srBegin >> 16) & 0xFF;
    buf[srOffsetLoc + 2] = (srBegin >> 8) & 0xFF;
    buf[srOffsetLoc + 3] = srBegin & 0xFF;

    writeBeDouble(buf, sampleRate);

    uint32_t irBegin = static_cast<uint32_t>(buf.size());
    buf[irOffsetLoc]     = (irBegin >> 24) & 0xFF;
    buf[irOffsetLoc + 1] = (irBegin >> 16) & 0xFF;
    buf[irOffsetLoc + 2] = (irBegin >> 8) & 0xFF;
    buf[irOffsetLoc + 3] = irBegin & 0xFF;

    // Write Data.IR data: [M, R=2, N]
    for (int m = 0; m < M; ++m) {
        for (int r = 0; r < R; ++r) {
            for (int n = 0; n < N; ++n) {
                // Synthetic delta at n = (m + 1) * (r + 1)
                double val = (n == ((m + 1) * 3 + r * 5)) ? 0.85 : 0.0;
                writeBeDouble(buf, val);
            }
        }
    }

    return buf;
}

// Builds a synthetic 2-channel RIFF/WAVE float buffer
std::vector<uint8_t> createSyntheticWavHrir(int channels, int frames, double sampleRate) {
    std::vector<uint8_t> buf;
    buf.resize(44 + frames * channels * 4);

    std::memcpy(buf.data(), "RIFF", 4);
    uint32_t fileSize = static_cast<uint32_t>(buf.size() - 8);
    std::memcpy(buf.data() + 4, &fileSize, 4);
    std::memcpy(buf.data() + 8, "WAVEfmt ", 8);

    uint32_t sub1Size = 16;
    uint16_t audioFormat = 3; // IEEE float
    uint16_t numChannels = static_cast<uint16_t>(channels);
    uint32_t sr = static_cast<uint32_t>(sampleRate);
    uint32_t byteRate = sr * channels * 4;
    uint16_t blockAlign = static_cast<uint16_t>(channels * 4);
    uint16_t bitsPerSample = 32;

    std::memcpy(buf.data() + 16, &sub1Size, 4);
    std::memcpy(buf.data() + 20, &audioFormat, 2);
    std::memcpy(buf.data() + 22, &numChannels, 2);
    std::memcpy(buf.data() + 24, &sr, 4);
    std::memcpy(buf.data() + 28, &byteRate, 4);
    std::memcpy(buf.data() + 32, &blockAlign, 2);
    std::memcpy(buf.data() + 34, &bitsPerSample, 2);

    std::memcpy(buf.data() + 36, "data", 4);
    uint32_t dataSize = static_cast<uint32_t>(frames * channels * 4);
    std::memcpy(buf.data() + 40, &dataSize, 4);

    float* samplePtr = reinterpret_cast<float*>(buf.data() + 44);
    for (int i = 0; i < frames; ++i) {
        samplePtr[i * channels] = (i == 10) ? 0.9f : 0.0f; // Left ear
        samplePtr[i * channels + 1] = (i == 20) ? 0.4f : 0.0f; // Right ear
    }

    return buf;
}

void test_sofa_netcdf3_synthetic() {
    std::cout << "--- test_sofa_netcdf3_synthetic ---" << std::endl;
    auto sofaBytes = createSyntheticSofaNetCdf3(3, 2, 64);
    check(!sofaBytes.empty(), "Synthetic SOFA buffer generated");

    pulsr::SofaDataset dataset;
    bool ok = pulsr::HrtfBinaural::parseSofaNetCdf3(sofaBytes.data(), sofaBytes.size(), dataset);
    check(ok, "parseSofaNetCdf3 parses valid synthetic SOFA");
    check(dataset.numMeasurements == 3, "SOFA M=3 measurements parsed");
    check(dataset.numReceivers == 2, "SOFA R=2 receivers parsed");
    check(dataset.irLength == 64, "SOFA N=64 samples parsed");
    check(std::abs(dataset.sampleRate - 48000.0) < 1.0, "SOFA sample rate == 48000 Hz");

    check(dataset.azimuths.size() == 3, "Azimuth table size == 3");
    check(std::abs(dataset.azimuths[0] - (-30.0)) < 1e-4, "Azimuth[0] == -30 deg");
    check(std::abs(dataset.azimuths[1] - 0.0) < 1e-4, "Azimuth[1] == 0 deg");
    check(std::abs(dataset.azimuths[2] - 30.0) < 1e-4, "Azimuth[2] == +30 deg");

    std::vector<float> irL, irR;
    bool findOk = dataset.findNearestHrir(28.0, 0.0, irL, irR);
    check(findOk, "findNearestHrir finds nearest angle to +28 deg");
    check(irL.size() == 64 && irR.size() == 64, "Extracted IR sizes match N=64");
    // Position 2 (m=2) was chosen: r=0 has delta at (2+1)*3 + 0*5 = 9
    check(std::abs(irL[9] - 0.85f) < 1e-4, "Extracted Left ear IR matches position 2 data");
}

void test_sofa_malformed_guards() {
    std::cout << "--- test_sofa_malformed_guards ---" << std::endl;
    pulsr::SofaDataset dataset;
    // Null pointer
    check(!pulsr::HrtfBinaural::parseSofaNetCdf3(nullptr, 100, dataset), "Null pointer rejected");
    // Too small buffer
    std::vector<uint8_t> tiny(16, 0);
    check(!pulsr::HrtfBinaural::parseSofaNetCdf3(tiny.data(), tiny.size(), dataset), "Truncated buffer rejected");
    // Bad magic
    std::vector<uint8_t> badMagic(100, 0);
    badMagic[0] = 'B'; badMagic[1] = 'A'; badMagic[2] = 'D'; badMagic[3] = '!';
    check(!pulsr::HrtfBinaural::parseSofaNetCdf3(badMagic.data(), badMagic.size(), dataset), "Invalid magic rejected");
}

void test_wav_hrir_parser() {
    std::cout << "--- test_wav_hrir_parser ---" << std::endl;
    auto wavBytes = createSyntheticWavHrir(2, 128, 48000.0);
    check(!wavBytes.empty(), "Synthetic WAV HRIR generated");

    std::vector<float> wavL, wavR;
    int channels = 0;
    double sampleRate = 0.0;
    bool ok = pulsr::HrtfBinaural::parseWavHrir(
        wavBytes.data(), wavBytes.size(), wavL, wavR, channels, sampleRate);

    check(ok, "parseWavHrir parses valid WAV buffer");
    check(channels == 2, "WAV channels == 2");
    check(std::abs(sampleRate - 48000.0) < 1.0, "WAV sampleRate == 48000 Hz");
    check(wavL.size() == 128, "WAV frames == 128");
    check(std::abs(wavL[10] - 0.9f) < 1e-4, "Left ear sample at frame 10 matches");
    check(std::abs(wavR[20] - 0.4f) < 1e-4, "Right ear sample at frame 20 matches");
}

void test_hrtf_spatial_symmetry() {
    std::cout << "--- test_hrtf_spatial_symmetry ---" << std::endl;
    // Test default KEMAR/anechoic synthesized model
    auto quadRight = pulsr::HrtfBinaural::synthesizeDefaultHrir(30.0, 0.0, 48000.0, 128);
    check(quadRight.taps == 128, "Default HRIR taps == 128");
    check(quadRight.hLL.size() == 128 && quadRight.hRR.size() == 128, "Quad IR vectors sized to 128");

    // Right virtual speaker (+30 deg):
    // Right ear (hRR) is ipsilateral: earlier onset and larger peak than Left ear (hRL)
    auto maxIpsI = std::max_element(quadRight.hRR.begin(), quadRight.hRR.end(),
        [](float a, float b) { return std::abs(a) < std::abs(b); });
    auto maxContra = std::max_element(quadRight.hRL.begin(), quadRight.hRL.end(),
        [](float a, float b) { return std::abs(a) < std::abs(b); });

    int ipsiPeakIdx = static_cast<int>(std::distance(quadRight.hRR.begin(), maxIpsI));
    int contraPeakIdx = static_cast<int>(std::distance(quadRight.hRL.begin(), maxContra));

    check(std::abs(*maxIpsI) > std::abs(*maxContra),
          "Right speaker produces higher amplitude in Right ear than Left ear (ILD)");
    check(contraPeakIdx > ipsiPeakIdx,
          "Contralateral Left ear onset is delayed relative to Ipsilateral Right ear (ITD)");

    // Left virtual speaker (-30 deg):
    auto quadLeft = pulsr::HrtfBinaural::synthesizeDefaultHrir(-30.0, 0.0, 48000.0, 128);
    auto maxLeftIpsi = std::max_element(quadLeft.hLL.begin(), quadLeft.hLL.end(),
        [](float a, float b) { return std::abs(a) < std::abs(b); });
    auto maxLeftContra = std::max_element(quadLeft.hLR.begin(), quadLeft.hLR.end(),
        [](float a, float b) { return std::abs(a) < std::abs(b); });

    check(std::abs(*maxLeftIpsi) > std::abs(*maxLeftContra),
          "Left speaker produces higher amplitude in Left ear than Right ear (ILD)");

    // Acoustic symmetry: hLL(+30) must match hRR(-30)
    double energyLL_R = 0.0, energyRR_L = 0.0;
    for (int i = 0; i < 128; ++i) {
        energyLL_R += quadRight.hLL[i] * quadRight.hLL[i];
        energyRR_L += quadLeft.hRR[i] * quadLeft.hRR[i];
    }
    check(std::abs(energyLL_R - energyRR_L) < 1e-5, "Symmetric soundstage energy parity verified");
}

void test_hrtf_realtime_processing() {
    std::cout << "--- test_hrtf_realtime_processing ---" << std::endl;
    pulsr::HrtfBinaural hrtf;
    hrtf.setSampleRate(48000.0);
    hrtf.setAzimuth(30.0);
    hrtf.setElevation(0.0);
    hrtf.setEnabled(true);

    check(hrtf.isEnabled(), "HRTF enabled");
    check(hrtf.getLatencyFrames() == 0, "HRTF direct FIR latency is zero frames");

    const int frames = 512;
    std::vector<float> buffer(frames * 2);
    // Sine in left channel, cosine in right channel
    for (int i = 0; i < frames; ++i) {
        buffer[i * 2] = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
        buffer[i * 2 + 1] = std::cos(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
    }

    std::vector<float> dryCopy = buffer;

    // Process through binaural convolver
    hrtf.processInterleaved(buffer.data(), frames, 2);

    // Verify wet output differs from dry (HRTF applied)
    double diffSum = 0.0;
    for (size_t i = 0; i < buffer.size(); ++i) {
        check(std::isfinite(buffer[i]), "Output sample is finite");
        diffSum += std::abs(buffer[i] - dryCopy[i]);
    }
    check(diffSum > 1.0, "HRTF convolution alters stereo soundstage as expected");

    // Dynamic live angle change: switch azimuth to -45 deg
    hrtf.setAzimuth(-45.0);
    check(hrtf.isRamping(), "Azimuth switch engages smooth crossfade ramping");

    // Process several blocks through the crossfade
    for (int b = 0; b < 10; ++b) {
        hrtf.processInterleaved(buffer.data(), frames, 2);
    }
    check(!hrtf.isRamping(), "Crossfade completed smoothly without glitches");

    // Bypass test
    hrtf.setEnabled(false);
    for (int b = 0; b < 10; ++b) {
        hrtf.processInterleaved(buffer.data(), frames, 2);
    }
    check(!hrtf.isEnabled(), "HRTF successfully disabled");
}

// §8.9: targets between SOFA grid points must blend neighbouring measurements
// (inverse-distance over the 4 nearest), not snap to a single one.
void test_sofa_interpolation() {
    std::cout << "--- test_sofa_interpolation ---" << std::endl;
    auto sofaBytes = createSyntheticSofaNetCdf3(3, 2, 64);
    pulsr::SofaDataset dataset;
    check(pulsr::HrtfBinaural::parseSofaNetCdf3(sofaBytes.data(), sofaBytes.size(), dataset),
          "Interpolation dataset parsed");

    // Measurement deltas live at (m + 1) * 3 + r * 5 (r=0 left ear).
    // m1 (0 deg) -> 6, m2 (+30 deg) -> 9 in the left-ear IR.
    std::vector<float> interpL, interpR;
    int taps = 0;
    const bool ok = dataset.findInterpolatedHrir(20.0, 0.0, 48000.0, 64,
                                                 interpL, interpR, taps);
    check(ok, "findInterpolatedHrir succeeds");
    check(taps == 64, "Interpolated IR taps match the 48 kHz source length");
    check(interpL.size() == 64 && interpR.size() == 64, "Interpolated IR sizes match");

    check(std::abs(interpL[9]) > 1e-4f && std::abs(interpL[6]) > 1e-4f,
          "20 deg target blends the +30 deg and 0 deg measurements");
    check(std::abs(interpL[9]) > std::abs(interpL[6]),
          "Nearer +30 deg measurement dominates a 20 deg target");

    // Pure nearest would return the +30 deg measurement with zero energy at 6.
    std::vector<float> nearestL, nearestR;
    check(dataset.findNearestHrir(20.0, 0.0, nearestL, nearestR),
          "Nearest reference lookup succeeds");
    check(std::abs(nearestL[6]) < 1e-6f,
          "Nearest-neighbour reference has no 0 deg contribution (interpolation adds it)");

    // On-grid target: the exact measurement dominates and the far neighbour is
    // strongly attenuated (inverse distance, not a flat average).
    std::vector<float> onGridL, onGridR;
    int onGridTaps = 0;
    check(dataset.findInterpolatedHrir(30.0, 0.0, 48000.0, 64,
                                       onGridL, onGridR, onGridTaps),
          "On-grid interpolation succeeds");
    check(std::abs(onGridL[9]) > 0.8f, "On-grid +30 deg keeps the exact measurement amplitude");
    check(std::abs(onGridL[6]) < 0.01f, "On-grid far neighbour is negligible");
}

// §8.9: a 44.1 kHz SOFA dataset applied to a 48 kHz engine must be resampled
// before convolution (taps scaled), not convolved at the wrong rate.
void test_sofa_resampling_44k_to_48k() {
    std::cout << "--- test_sofa_resampling_44k_to_48k ---" << std::endl;
    auto sofaBytes = createSyntheticSofaNetCdf3(3, 2, 64, 44100.0);
    pulsr::SofaDataset dataset;
    check(pulsr::HrtfBinaural::parseSofaNetCdf3(sofaBytes.data(), sofaBytes.size(), dataset),
          "44.1 kHz SOFA parses");
    check(std::abs(dataset.sampleRate - 44100.0) < 1.0, "Dataset sample rate is 44100 Hz");

    pulsr::HrtfBinaural hrtf;
    hrtf.setSampleRate(48000.0);
    check(hrtf.loadSofaMemory(sofaBytes.data(), sofaBytes.size()),
          "44.1 kHz SOFA loads into a 48 kHz engine");
    hrtf.setAzimuth(30.0);
    hrtf.setElevation(0.0);
    // Render-thread side of the handoff: claim the published slot.
    hrtf.applyPrepared();

    pulsr::HrirQuad quad;
    check(hrtf.copyActiveQuad(quad), "Active prepared quad is observable");
    const int expectedTaps =
        static_cast<int>(std::ceil(64.0 * 48000.0 / 44100.0));
    check(quad.sampleRate == 48000.0, "Prepared quad runs at the engine rate");
    check(quad.taps == expectedTaps,
          "HRIR taps are rescaled by 48000/44100 (not convolved at 44.1k spacing)");
    check(quad.taps > 64, "Resampled quad is longer than the 44.1 kHz source");

    // Left virtual speaker at -30 deg = measurement m0; hLL (r=0) delta at n=3,
    // hLR (r=1) delta at n=8. At 48 kHz these land near 3.27 and 8.71.
    auto peakIndex = [](const std::vector<float>& v) {
        int idx = 0;
        float best = 0.0f;
        for (size_t i = 0; i < v.size(); ++i) {
            if (std::abs(v[i]) > best) {
                best = std::abs(v[i]);
                idx = static_cast<int>(i);
            }
        }
        return idx;
    };
    const int peakLL = peakIndex(quad.hLL);
    const int peakLR = peakIndex(quad.hLR);
    check(std::abs(peakLL - 3) <= 2, "Resampled left-ear impulse lands near n=3");
    check(std::abs(peakLR - 9) <= 2, "Resampled right-ear impulse lands near n=9");

    double energyLL = 0.0;
    for (float v : quad.hLL) energyLL += static_cast<double>(v) * v;
    check(energyLL > 0.2 && energyLL < 1.2,
          "Resampled impulse preserves energy (windowed-sinc, not a drop/duplicate)");

    // End-to-end: the impulse response is finite and audible through process().
    std::vector<float> block(256 * 2, 0.0f);
    block[0] = 1.0f;
    block[1] = 1.0f;
    hrtf.setEnabled(true);
    hrtf.reset();
    hrtf.processInterleaved(block.data(), 256, 2);
    double outEnergy = 0.0;
    bool finite = true;
    for (float v : block) {
        finite = finite && std::isfinite(v);
        outEnergy += static_cast<double>(v) * v;
    }
    check(finite, "Resampled HRIR processing output is finite");
    check(outEnergy > 0.01, "Resampled HRIR produces audible convolution output");
}

// §8.9: loading datasets / changing geometry while another thread convolves must
// never crash or expose a torn quad. Functional (not TSan) but exercises the
// slot handoff: the writer only ever touches a slot the render thread is not
// convolving.
void test_hrtf_concurrent_load() {
    std::cout << "--- test_hrtf_concurrent_load ---" << std::endl;
    auto sofa48 = createSyntheticSofaNetCdf3(3, 2, 64, 48000.0);
    auto sofa44 = createSyntheticSofaNetCdf3(3, 2, 96, 44100.0);

    pulsr::HrtfBinaural hrtf;
    hrtf.setSampleRate(48000.0);
    hrtf.setAzimuth(30.0);
    hrtf.setElevation(0.0);
    hrtf.setEnabled(true);

    std::atomic<bool> stop{false};
    std::atomic<bool> sawNonFinite{false};
    std::atomic<int> blocks{0};
    int loadFailures = 0;

    std::thread renderThread([&]() {
        std::vector<float> buffer(256 * 2, 0.0f);
        while (!stop.load(std::memory_order_relaxed)) {
            for (size_t k = 0; k < buffer.size(); ++k) {
                buffer[k] = 0.05f * static_cast<float>((k % 9) - 4);
            }
            hrtf.processInterleaved(buffer.data(), 256, 2);
            for (float v : buffer) {
                if (!std::isfinite(v)) sawNonFinite.store(true);
            }
            blocks.fetch_add(1, std::memory_order_relaxed);
        }
    });

    for (int i = 0; i < 120; ++i) {
        if (!hrtf.loadSofaMemory(sofa48.data(), sofa48.size())) ++loadFailures;
        hrtf.setAzimuth(-30.0 + static_cast<double>(i % 7) * 10.0);
        if (!hrtf.loadSofaMemory(sofa44.data(), sofa44.size())) ++loadFailures;
        hrtf.setElevation(static_cast<double>((i % 3) - 1) * 15.0);
        if ((i % 5) == 0) {
            if (!hrtf.clearDataset()) ++loadFailures;
        }
    }
    stop.store(true);
    renderThread.join();

    check(blocks.load() > 0, "Render thread convolved blocks during concurrent loads");
    check(!sawNonFinite.load(), "Concurrent dataset loads produced only finite output");
    check(loadFailures == 0, "Every concurrent dataset publish found a free slot");

    // Restore the synthesized default and let the render path claim it.
    check(hrtf.clearDataset(), "clearDataset succeeds");
    check(!hrtf.hasDataset(), "clearDataset restores the synthetic source");
    std::vector<float> flush(256 * 2, 0.0f);
    hrtf.processInterleaved(flush.data(), 256, 2);
    pulsr::HrirQuad quad;
    check(hrtf.copyActiveQuad(quad), "Active quad remains valid after the load storm");
    check(quad.taps == pulsr::HrtfBinaural::DEFAULT_HRIR_TAPS,
          "Synthetic quad is restored at the default tap count");
}

void test_hrtf_zero_lag_and_safety_guards() {
    std::cout << "--- test_hrtf_zero_lag_and_safety_guards ---" << std::endl;
    // 1. Custom Dirac delta at k=0 must produce output at n=0 (no 1-sample circular lag).
    pulsr::HrtfBinaural hrtf;
    hrtf.setSampleRate(48000.0);
    std::vector<float> ll(16, 0.0f), lr(16, 0.0f), rl(16, 0.0f), rr(16, 0.0f);
    ll[0] = 1.0f;
    rr[0] = 1.0f;
    check(hrtf.loadCustomIr(ll.data(), lr.data(), rl.data(), rr.data(), 16, 48000.0),
          "Custom Dirac quad loaded");
    hrtf.setEnabled(true);
    hrtf.reset();
    std::vector<float> buf(32 * 2, 0.0f);
    buf[0] = 1.0f;
    buf[1] = -0.5f;
    hrtf.processInterleaved(buf.data(), 32, 2);
    check(std::abs(buf[0] - 1.0f) < 1e-4f && std::abs(buf[1] - (-0.5f)) < 1e-4f,
          "Impulse appears at exact n=0 without circular buffer off-by-one lag");

    // 2. NaN inputs must be scrubbed to finite output.
    std::vector<float> nanBuf(16 * 2, std::numeric_limits<float>::quiet_NaN());
    hrtf.processInterleaved(nanBuf.data(), 16, 2);
    bool allFinite = std::all_of(nanBuf.begin(), nanBuf.end(),
                                 [](float v) { return std::isfinite(v); });
    check(allFinite, "Non-finite input samples are scrubbed before convolution history");

    // 3. Disable must ramp smoothly (~20ms) instead of snapping to 0 in one small block.
    hrtf.setEnabled(false);
    std::vector<float> stepBuf(16 * 2, 1.0f);
    hrtf.processInterleaved(stepBuf.data(), 16, 2);
    check(hrtf.isRamping(), "Short block after disable stays mid-ramp without click snap");

    // 4. High sample-rate (192 kHz) synthetic quad must scale taps to avoid ITD clamping.
    pulsr::HrtfBinaural hiSrHrtf;
    hiSrHrtf.setSampleRate(192000.0);
    hiSrHrtf.setAzimuth(60.0);
    hiSrHrtf.applyPrepared();
    pulsr::HrirQuad hiQuad;
    check(hiSrHrtf.copyActiveQuad(hiQuad), "192 kHz synthetic quad copied");
    check(hiQuad.taps >= pulsr::HrtfBinaural::DEFAULT_HRIR_TAPS * 4,
          "192 kHz synthetic quad scales tap window with sample rate");

    // 5. Malformed SOFA dimension count / R < 2 / truncated payload rejected cleanly.
    auto badSofa = createSyntheticSofaNetCdf3(3, 1, 64); // R=1 < 2
    pulsr::SofaDataset badDs;
    check(!pulsr::HrtfBinaural::parseSofaNetCdf3(badSofa.data(), badSofa.size(), badDs),
          "SOFA with R < 2 receivers is rejected safely");
}

void test_hrtf_settled_bypass_and_old_slot_release() {
    std::cout << "--- test_hrtf_settled_bypass_and_old_slot_release ---" << std::endl;

    // 1. Settled bypass: bit-exact passthrough (planar & interleaved) without running FIR convolution.
    {
        pulsr::HrtfBinaural hrtf;
        hrtf.setSampleRate(48000.0);
        std::vector<float> ll(16, 0.0f), lr(16, 0.0f), rl(16, 0.0f), rr(16, 0.0f);
        ll[1] = 1.0f; // Pure 1-sample delay IR so any history write leaks on next sample
        rr[1] = 1.0f;
        check(hrtf.loadCustomIr(ll.data(), lr.data(), rl.data(), rr.data(), 16, 48000.0),
              "1-sample delay custom IR loaded for bypass test");
        hrtf.setEnabled(false);
        hrtf.reset();

        // Planar with distinct out buffers
        const int frames = 64;
        std::vector<float> inL(frames), inR(frames), outL(frames, -999.0f), outR(frames, -999.0f);
        for (int i = 0; i < frames; ++i) {
            inL[i] = (i == 0) ? 1e-40f : (0.1234567f * static_cast<float>(i + 1));
            inR[i] = -0.7654321f * static_cast<float>(i + 1);
        }
        hrtf.process(inL.data(), inR.data(), outL.data(), outR.data(), frames);
        check(std::memcmp(inL.data(), outL.data(), frames * sizeof(float)) == 0 &&
              std::memcmp(inR.data(), outR.data(), frames * sizeof(float)) == 0,
              "Planar settled bypass is bit-exact passthrough");

        // Interleaved in-place
        std::vector<float> inter(frames * 2);
        for (int i = 0; i < frames; ++i) {
            inter[i * 2] = 0.75f;
            inter[i * 2 + 1] = -0.5f;
        }
        std::vector<float> interCopy = inter;
        hrtf.processInterleaved(inter.data(), frames, 2);
        check(std::memcmp(inter.data(), interCopy.data(), inter.size() * sizeof(float)) == 0,
              "Interleaved settled bypass is bit-exact passthrough");

        // Verify FIR convolution was truly skipped: history must still be all zeros,
        // so enabling and processing 1 sample of silence yields 0 (no 1-sample delayed leak).
        hrtf.setEnabled(true);
        float zInL = 0.0f, zInR = 0.0f, zOutL = -1.0f, zOutR = -1.0f;
        hrtf.process(&zInL, &zInR, &zOutL, &zOutR, 1);
        check(zOutL == 0.0f && zOutR == 0.0f,
              "Settled bypass skips 4x FIR convolution and leaves FIR history untouched");
    }

    // 2. While disabled & settled, geometry changes still applyPrepared() and release oldSlotAtomic_.
    {
        pulsr::HrtfBinaural hrtf;
        hrtf.setSampleRate(48000.0);
        hrtf.setEnabled(false);
        hrtf.reset();
        std::vector<float> buf(32 * 2, 0.25f);
        hrtf.processInterleaved(buf.data(), 32, 2);
        hrtf.setAzimuth(-45.0);
        std::vector<float> before = buf;
        hrtf.processInterleaved(buf.data(), 32, 2);
        check(std::memcmp(buf.data(), before.data(), buf.size() * sizeof(float)) == 0,
              "Disabled geometry update keeps bit-exact passthrough");
        check(!hrtf.hasPendingOldSlotForTesting(),
              "Disabled block still claims prepared slot and releases oldSlotAtomic_");
    }

    // 3. Active crossfade releases oldSlotAtomic_ at the END of the completing block (interleaved).
    {
        pulsr::HrtfBinaural hrtf;
        hrtf.setSampleRate(48000.0);
        hrtf.setAzimuth(30.0);
        hrtf.setEnabled(true);
        hrtf.reset();

        std::vector<float> initBuf(64 * 2, 0.1f);
        hrtf.processInterleaved(initBuf.data(), 64, 2);
        check(!hrtf.hasPendingOldSlotForTesting(), "No pending old slot after initial block");

        hrtf.setAzimuth(-45.0);
        // Short block (128 < 720 frames @ 48kHz) stays mid-crossfade -> old slot still pinned.
        std::vector<float> shortBuf(128 * 2, 0.1f);
        hrtf.processInterleaved(shortBuf.data(), 128, 2);
        check(hrtf.hasPendingOldSlotForTesting(),
              "Interleaved mid-crossfade keeps oldSlotAtomic_ pinned");

        // Completing block (1024 frames finishes 15 ms fade) must release oldSlotAtomic_ immediately.
        std::vector<float> doneBuf(1024 * 2, 0.1f);
        hrtf.processInterleaved(doneBuf.data(), 1024, 2);
        check(!hrtf.hasPendingOldSlotForTesting(),
              "Interleaved processInterleaved releases oldSlotAtomic_ at end of completing block");
    }

    // 4. Active crossfade releases oldSlotAtomic_ at the END of the completing block (planar).
    {
        pulsr::HrtfBinaural hrtf;
        hrtf.setSampleRate(48000.0);
        hrtf.setAzimuth(30.0);
        hrtf.setEnabled(true);
        hrtf.reset();

        std::vector<float> inL(64, 0.1f), inR(64, -0.1f), outL(64), outR(64);
        hrtf.process(inL.data(), inR.data(), outL.data(), outR.data(), 64);
        check(!hrtf.hasPendingOldSlotForTesting(), "Planar: no pending old slot after initial block");

        hrtf.setAzimuth(60.0);
        std::vector<float> sL(128, 0.1f), sR(128, -0.1f), soL(128), soR(128);
        hrtf.process(sL.data(), sR.data(), soL.data(), soR.data(), 128);
        check(hrtf.hasPendingOldSlotForTesting(),
              "Planar mid-crossfade keeps oldSlotAtomic_ pinned");

        std::vector<float> dL(1024, 0.1f), dR(1024, -0.1f), doL(1024), doR(1024);
        hrtf.process(dL.data(), dR.data(), doL.data(), doR.data(), 1024);
        check(!hrtf.hasPendingOldSlotForTesting(),
              "Planar process() releases oldSlotAtomic_ at end of completing block");
    }
}

void test_wav_rf64_quad_and_atomic_sr_reset() {
    std::cout << "--- test_wav_rf64_quad_and_atomic_sr_reset ---" << std::endl;

    auto pushU32Le = [](std::vector<uint8_t>& b, uint32_t v) {
        b.push_back(static_cast<uint8_t>(v & 0xFF));
        b.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
        b.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
        b.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
    };
    auto pushU16Le = [](std::vector<uint8_t>& b, uint16_t v) {
        b.push_back(static_cast<uint8_t>(v & 0xFF));
        b.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    };

    // 1. Crafted RIFF chunk with chunkSize == 0xFFFFFFFF must not wrap uint32 or hang.
    {
        std::vector<uint8_t> malicious;
        malicious.insert(malicious.end(), {'R', 'I', 'F', 'F'});
        pushU32Le(malicious, 36);
        malicious.insert(malicious.end(), {'W', 'A', 'V', 'E'});
        malicious.insert(malicious.end(), {'j', 'u', 'n', 'k'});
        pushU32Le(malicious, 0xFFFFFFFFu); // uint64_t step skips safely past EOF
        std::vector<float> l, r;
        int ch = 0;
        double sr = 0.0;
        bool parsed = pulsr::HrtfBinaural::parseWavHrir(
            malicious.data(), malicious.size(), l, r, ch, sr);
        check(!parsed, "0xFFFFFFFF WAV chunk exits cleanly instead of hanging");
    }

    // 2. True 4-channel WAV HRIR (hLL, hLR, hRL, hRR) preserves distinct cross-ear taps.
    {
        const uint32_t frames = 64;
        const uint32_t channels = 4;
        const uint32_t dataBytes = frames * channels * sizeof(float);
        std::vector<uint8_t> wav;
        wav.insert(wav.end(), {'R', 'I', 'F', 'F'});
        pushU32Le(wav, 36 + dataBytes);
        wav.insert(wav.end(), {'W', 'A', 'V', 'E'});
        wav.insert(wav.end(), {'f', 'm', 't', ' '});
        pushU32Le(wav, 16);
        pushU16Le(wav, 3); // IEEE float
        pushU16Le(wav, channels);
        pushU32Le(wav, 48000);
        pushU32Le(wav, 48000 * channels * 4);
        pushU16Le(wav, channels * 4);
        pushU16Le(wav, 32);
        wav.insert(wav.end(), {'d', 'a', 't', 'a'});
        pushU32Le(wav, dataBytes);
        std::vector<float> pcm(frames * channels, 0.0f);
        pcm[2 * 4 + 0] = 0.9f;  // hLL @ frame 2
        pcm[5 * 4 + 1] = 0.35f; // hLR @ frame 5
        pcm[7 * 4 + 2] = 0.25f; // hRL @ frame 7
        pcm[9 * 4 + 3] = 0.85f; // hRR @ frame 9
        const auto* raw = reinterpret_cast<const uint8_t*>(pcm.data());
        wav.insert(wav.end(), raw, raw + dataBytes);

        std::vector<float> ll, lr, rl, rr;
        int outCh = 0;
        double outSr = 0.0;
        bool ok = pulsr::HrtfBinaural::parseWavHrirQuad(
            wav.data(), wav.size(), ll, lr, rl, rr, outCh, outSr);
        check(ok && outCh == 4 && ll.size() == frames, "parseWavHrirQuad decodes 4ch IEEE float HRIR");
        check(std::abs(ll[2] - 0.9f) < 1e-5f && std::abs(lr[5] - 0.35f) < 1e-5f &&
              std::abs(rl[7] - 0.25f) < 1e-5f && std::abs(rr[9] - 0.85f) < 1e-5f,
              "4ch WAV preserves independent LL/LR/RL/RR taps");
    }

    // 3. Concurrent setSampleRate + processInterleaved uses atomic render-thread reset.
    {
        pulsr::HrtfBinaural hrtf;
        hrtf.setSampleRate(48000.0);
        hrtf.setEnabled(true);
        hrtf.reset();

        std::atomic<bool> stop{false};
        std::atomic<bool> nanSeen{false};
        std::thread audio([&]() {
            std::vector<float> buf(256 * 2, 0.1f);
            for (int iter = 0; iter < 400 && !stop.load(std::memory_order_relaxed); ++iter) {
                std::fill(buf.begin(), buf.end(), 0.1f * std::sin(static_cast<float>(iter)));
                hrtf.processInterleaved(buf.data(), 256, 2);
                for (float v : buf) {
                    if (!std::isfinite(v)) nanSeen.store(true, std::memory_order_relaxed);
                }
            }
        });
        for (int s = 0; s < 40; ++s) {
            hrtf.setSampleRate((s % 2 == 0) ? 96000.0 : 44100.0);
        }
        stop.store(true, std::memory_order_relaxed);
        audio.join();
        check(!nanSeen.load(), "Concurrent setSampleRate + processInterleaved stays finite and lock-free");
    }
}

} // namespace

int main() {
    std::cout << "Starting test_hrtf_binaural..." << std::endl;

    test_sofa_netcdf3_synthetic();
    test_sofa_malformed_guards();
    test_wav_hrir_parser();
    test_hrtf_spatial_symmetry();
    test_hrtf_realtime_processing();
    test_sofa_interpolation();
    test_sofa_resampling_44k_to_48k();
    test_hrtf_concurrent_load();
    test_hrtf_zero_lag_and_safety_guards();
    test_hrtf_settled_bypass_and_old_slot_release();
    test_wav_rf64_quad_and_atomic_sr_reset();

    if (gFailures == 0) {
        std::cout << "[ALL TESTS PASSED] test_hrtf_binaural succeeded completely!" << std::endl;
        return 0;
    } else {
        std::cout << "[TEST FAILED] " << gFailures << " failures in test_hrtf_binaural" << std::endl;
        return 1;
    }
}
