// scripts/measure_native_dsp.cpp
//
// Standalone offline native DSP stimulus & capture renderer for FFT analysis.
// Exercises the real AudioDspEngine, HighQualityResampler, SinkQuantizer, and
// CustodyVerifier on host or Android without requiring physical DAC hardware,
// emitting deterministic RIFF/WAVE captures for scripts/hil/measure_fft.py.
//
// Build on host (example with clang++ / g++):
//   clang++ -O3 -std=c++20 -Iandroid/app/src/main/cpp \
//       scripts/measure_native_dsp.cpp \
//       android/app/src/main/cpp/{ParametricEQ,Crossfeed,LookaheadLimiter,ConvolutionReverb,SincResampler,HighQualityResampler,DsdDecoder,DsdNativePacker,Uac2Descriptors,SpatialPanner,HarmonicSaturation,StereoWidth,LoudnessContour,SubCrossover,ChannelManager,DacVoicing,DynamicEQ,MultibandCompressor,DynamicBass,ViperDdc,ArbitraryResponseEq,LiveProg,CustodyVerifier,AudioDspEngine,UsbAudioSink,UsbPullRenderer,UsbAsrcClockSync,UsbPcmProducer}.cpp \
//       -o build/measure_native_dsp
//   ./build/measure_native_dsp --out-dir scratch/fft_captures
//
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <memory>

#include "AudioDspEngine.h"
#include "HighQualityResampler.h"
#include "SinkQuantizer.h"

namespace fs = std::filesystem;

namespace {

constexpr double kTwoPi = 6.283185307179586476925286766559;
constexpr int kSampleRate = 48000;
constexpr int kChannels = 2;
constexpr int kBlockFrames = 512;
constexpr int kTotalFrames = 32768; // ~0.68s @ 48 kHz -> crisp FFT bins

void writeLe16(std::ofstream& out, uint16_t v) {
    char b[2] = {static_cast<char>(v & 0xFF), static_cast<char>((v >> 8) & 0xFF)};
    out.write(b, 2);
}

void writeLe32(std::ofstream& out, uint32_t v) {
    char b[4] = {
        static_cast<char>(v & 0xFF),
        static_cast<char>((v >> 8) & 0xFF),
        static_cast<char>((v >> 16) & 0xFF),
        static_cast<char>((v >> 24) & 0xFF),
    };
    out.write(b, 4);
}

/// Writes an interleaved float buffer [-1, 1] to a signed PCM RIFF/WAVE file.
/// When `useSinkQuantizerDither` is true, non-grid samples receive SinkQuantizer
/// TPDF dither; when false, samples are rounded straight to the integer grid so
/// dither-off quantization floor and harmonics can be measured directly.
bool writePcmWav(const fs::path& path, const std::vector<float>& interleaved,
                 int sampleRate, int channels, int bitsPerSample,
                 bool useSinkQuantizerDither) {
    const int bytesPerSample = bitsPerSample / 8;
    const int frames = static_cast<int>(interleaved.size()) / channels;
    const uint32_t dataBytes = static_cast<uint32_t>(frames * channels * bytesPerSample);
    const uint32_t byteRate = static_cast<uint32_t>(sampleRate * channels * bytesPerSample);
    const uint16_t blockAlign = static_cast<uint16_t>(channels * bytesPerSample);

    std::ofstream out(path, std::ios::binary);
    if (!out) return false;

    out.write("RIFF", 4);
    writeLe32(out, 36 + dataBytes);
    out.write("WAVE", 4);
    out.write("fmt ", 4);
    writeLe32(out, 16);
    writeLe16(out, 1); // PCM
    writeLe16(out, static_cast<uint16_t>(channels));
    writeLe32(out, static_cast<uint32_t>(sampleRate));
    writeLe32(out, byteRate);
    writeLe16(out, blockAlign);
    writeLe16(out, static_cast<uint16_t>(bitsPerSample));
    out.write("data", 4);
    writeLe32(out, dataBytes);

    pulsr::SinkDitherState ditherState;
    const double scale = pulsr::LsbScaleForBits(bitsPerSample);
    const int64_t half = int64_t{1} << (bitsPerSample - 1);
    uint8_t sampleBytes[4] = {};

    for (float s : interleaved) {
        if (useSinkQuantizerDither) {
            pulsr::PackPcmSample(s, sampleBytes, bytesPerSample, ditherState, bitsPerSample);
        } else {
            const double scaled = std::isfinite(s) ? static_cast<double>(s) * scale : 0.0;
            const double rounded = std::rint(scaled);
            const int64_t q = static_cast<int64_t>(
                std::clamp(rounded, -static_cast<double>(half), static_cast<double>(half - 1)));
            const uint32_t wire = static_cast<uint32_t>(q);
            for (int b = 0; b < bytesPerSample; ++b) {
                sampleBytes[b] = static_cast<uint8_t>(wire >> (8 * b));
            }
        }
        out.write(reinterpret_cast<const char*>(sampleBytes), bytesPerSample);
    }
    return static_cast<bool>(out);
}

void configureEngine(AudioDspEngine& engine, double sampleRate, int sinkBits,
                     bool bitPerfect, bool ditherEnabled, int ditherBits) {
    engine.setSampleRate(sampleRate);
    engine.setSinkBitDepth(sinkBits);
    engine.setActiveStages(ditherEnabled ? STAGE_DITHER : 0u);
    engine.updateParams([&](DspParamSnapshot& p) {
        p.sampleRate = sampleRate;
        p.activeStages = ditherEnabled ? STAGE_DITHER : 0u;
        p.bitPerfect.enabled = bitPerfect;
        p.bitPerfect.isDop = false;
        p.bitPerfect.directUsbActive = false;
        p.bitPerfect.directUsbGain = 1.0;
        p.dither.enabled = ditherEnabled;
        p.dither.targetBitDepth = ditherBits;
        p.dither.isBluetooth = false;
        p.eq.enabled = false;
        p.crossfeed.enabled = false;
        p.limiter.enabled = false;
        p.reverb.enabled = false;
        p.panner.balance = 0.0;
        p.panner.monoMix = false;
        p.saturation.enabled = false;
        p.stereoWidth.enabled = false;
        p.loudness.enabled = false;
        p.subCrossover.enabled = false;
        p.channelManager.enabled = false;
        p.dynamicEq.enabled = false;
        p.multibandCompressor.enabled = false;
        p.dynamicBass.enabled = false;
        p.replayGain.enabled = false;
        p.viperDdc.enabled = false;
        p.arbitraryEq.enabled = false;
        p.liveProg.enabled = false;
        p.headphoneSafety.enabled = false;
        p.bypassCompare.enabled = false;
        p.dacVoicing.enabled = false;
    });
}

void runEngineBlocks(AudioDspEngine& engine, std::vector<float>& interleaved, int frames) {
    for (int offset = 0; offset < frames; offset += kBlockFrames) {
        const int n = std::min(kBlockFrames, frames - offset);
        engine.processInterleaved(interleaved.data() + offset * kChannels, n, kChannels);
    }
}

std::vector<float> makeStereoSine(int frames, double sampleRate, double freqHz,
                                  double ampL, double ampR) {
    std::vector<float> buf(static_cast<size_t>(frames) * kChannels, 0.0f);
    for (int i = 0; i < frames; ++i) {
        const double phase = kTwoPi * freqHz * i / sampleRate;
        const double s = std::sin(phase);
        buf[i * 2] = static_cast<float>(ampL * s);
        buf[i * 2 + 1] = static_cast<float>(ampR * s);
    }
    return buf;
}

std::vector<float> makeSmpteImd(int frames, double sampleRate) {
    // SMPTE RP120: 60 Hz + 7 kHz in 4:1 amplitude ratio at -3 dBFS combined peak.
    const double peakScale = std::pow(10.0, -3.0 / 20.0);
    const double ampLow = peakScale * 0.8;
    const double ampHigh = peakScale * 0.2;
    std::vector<float> buf(static_cast<size_t>(frames) * kChannels, 0.0f);
    for (int i = 0; i < frames; ++i) {
        const double v =
            ampLow * std::sin(kTwoPi * 60.0 * i / sampleRate) +
            ampHigh * std::sin(kTwoPi * 7000.0 * i / sampleRate);
        buf[i * 2] = static_cast<float>(v);
        buf[i * 2 + 1] = static_cast<float>(v);
    }
    return buf;
}

std::vector<float> makeCcifImd(int frames, double sampleRate) {
    // CCIF twin-tone IMD (§8.7): 19 kHz + 20 kHz 1:1 at -3 dBFS combined peak.
    const double peakScale = std::pow(10.0, -3.0 / 20.0);
    const double amp = peakScale * 0.5;
    std::vector<float> buf(static_cast<size_t>(frames) * kChannels, 0.0f);
    for (int i = 0; i < frames; ++i) {
        const double v =
            amp * std::sin(kTwoPi * 19000.0 * i / sampleRate) +
            amp * std::sin(kTwoPi * 20000.0 * i / sampleRate);
        buf[i * 2] = static_cast<float>(v);
        buf[i * 2 + 1] = static_cast<float>(v);
    }
    return buf;
}

uint64_t fnv1a64(const float* data, size_t count) {
    uint64_t hash = 14695981039346656037ULL;
    const uint8_t* bytes = reinterpret_cast<const uint8_t*>(data);
    for (size_t i = 0; i < count * sizeof(float); ++i) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

std::string hex64(uint64_t v) {
    std::ostringstream oss;
    oss << std::hex << std::setw(16) << std::setfill('0') << v;
    return oss.str();
}

} // namespace

int main(int argc, char** argv) {
    fs::path outDir = fs::path("scratch") / "fft_captures";
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--out-dir" && i + 1 < argc) {
            outDir = argv[++i];
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: measure_native_dsp [--out-dir DIR]\n";
            return 0;
        }
    }

    fs::create_directories(outDir);

    const double ampMinus3dB = std::pow(10.0, -3.0 / 20.0);
    const double ampMinus60dB = std::pow(10.0, -60.0 / 20.0);
    const double ampMinus1dB = std::pow(10.0, -1.0 / 20.0);

    // 1. 16-bit THD+N (1 kHz @ -3 dBFS), dither off vs on
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto bufOff = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus3dB, ampMinus3dB);
        configureEngine(*engine, kSampleRate, 16, false, false, 16);
        runEngineBlocks(*engine, bufOff, kTotalFrames);
        writePcmWav(outDir / "thd_16bit_dither_off.wav", bufOff, kSampleRate, kChannels, 16, false);

        auto bufOn = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus3dB, ampMinus3dB);
        configureEngine(*engine, kSampleRate, 16, false, true, 16);
        runEngineBlocks(*engine, bufOn, kTotalFrames);
        // Engine STAGE_DITHER already applied dither; useSinkQuantizerDither=false prevents double dither (§8.7).
        writePcmWav(outDir / "thd_16bit_dither_on.wav", bufOn, kSampleRate, kChannels, 16, false);
    }

    // 2. 16-bit low-level linearity (-60 dBFS 1 kHz), dither off vs on
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto bufOff = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus60dB, ampMinus60dB);
        configureEngine(*engine, kSampleRate, 16, false, false, 16);
        runEngineBlocks(*engine, bufOff, kTotalFrames);
        writePcmWav(outDir / "quiet_16bit_dither_off.wav", bufOff, kSampleRate, kChannels, 16, false);

        auto bufOn = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus60dB, ampMinus60dB);
        configureEngine(*engine, kSampleRate, 16, false, true, 16);
        runEngineBlocks(*engine, bufOn, kTotalFrames);
        writePcmWav(outDir / "quiet_16bit_dither_on.wav", bufOn, kSampleRate, kChannels, 16, false);
    }

    // 3. 24-bit THD+N (1 kHz @ -3 dBFS), dither off vs on
    {
        auto engine = std::make_unique<AudioDspEngine>();
        auto bufOff = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus3dB, ampMinus3dB);
        configureEngine(*engine, kSampleRate, 24, false, false, 24);
        runEngineBlocks(*engine, bufOff, kTotalFrames);
        writePcmWav(outDir / "thd_24bit_dither_off.wav", bufOff, kSampleRate, kChannels, 24, false);

        auto bufOn = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus3dB, ampMinus3dB);
        configureEngine(*engine, kSampleRate, 24, false, true, 24);
        runEngineBlocks(*engine, bufOn, kTotalFrames);
        writePcmWav(outDir / "thd_24bit_dither_on.wav", bufOn, kSampleRate, kChannels, 24, false);
    }

    // 4. Noise floor (digital zero) at 16-bit and 24-bit, dither off vs on
    {
        auto engine = std::make_unique<AudioDspEngine>();
        std::vector<float> z16Off(static_cast<size_t>(kTotalFrames) * kChannels, 0.0f);
        configureEngine(*engine, kSampleRate, 16, false, false, 16);
        runEngineBlocks(*engine, z16Off, kTotalFrames);
        writePcmWav(outDir / "noise_floor_16bit_dither_off.wav", z16Off, kSampleRate, kChannels, 16, false);

        std::vector<float> z16On(static_cast<size_t>(kTotalFrames) * kChannels, 0.0f);
        configureEngine(*engine, kSampleRate, 16, false, true, 16);
        runEngineBlocks(*engine, z16On, kTotalFrames);
        writePcmWav(outDir / "noise_floor_16bit_dither_on.wav", z16On, kSampleRate, kChannels, 16, false);

        std::vector<float> z24Off(static_cast<size_t>(kTotalFrames) * kChannels, 0.0f);
        configureEngine(*engine, kSampleRate, 24, false, false, 24);
        runEngineBlocks(*engine, z24Off, kTotalFrames);
        writePcmWav(outDir / "noise_floor_24bit_dither_off.wav", z24Off, kSampleRate, kChannels, 24, false);

        std::vector<float> z24On(static_cast<size_t>(kTotalFrames) * kChannels, 0.0f);
        configureEngine(*engine, kSampleRate, 24, false, true, 24);
        runEngineBlocks(*engine, z24On, kTotalFrames);
        writePcmWav(outDir / "noise_floor_24bit_dither_on.wav", z24On, kSampleRate, kChannels, 24, false);
    }

    // 5. SMPTE IMD (60 Hz + 7 kHz) & CCIF (19 kHz + 20 kHz) & Stereo Crosstalk (1 kHz L-only) & Jitter carrier (12 kHz)
    bool custodyBitExact = false;
    std::string custodyInHash;
    std::string custodyOutHash;
    {
        auto engine = std::make_unique<AudioDspEngine>();
        configureEngine(*engine, kSampleRate, 24, true, false, 24);

        auto imdBuf = makeSmpteImd(kTotalFrames, kSampleRate);
        runEngineBlocks(*engine, imdBuf, kTotalFrames);
        writePcmWav(outDir / "imd_smpte_24bit.wav", imdBuf, kSampleRate, kChannels, 24, false);

        auto ccifBuf = makeCcifImd(kTotalFrames, kSampleRate);
        runEngineBlocks(*engine, ccifBuf, kTotalFrames);
        writePcmWav(outDir / "imd_ccif_24bit.wav", ccifBuf, kSampleRate, kChannels, 24, false);

        // CustodyVerifier proof over bit-perfect bypass window.
        engine->custody().arm(4096, kSampleRate, true, false);
        auto xtalkBuf = makeStereoSine(kTotalFrames, kSampleRate, 1000.0, ampMinus1dB, 0.0);
        runEngineBlocks(*engine, xtalkBuf, kTotalFrames);
        writePcmWav(outDir / "crosstalk_1khz_l_only.wav", xtalkBuf, kSampleRate, kChannels, 24, false);

        CustodyVerifier::Window win{};
        if (engine->custody().take(win) && win.frames > 0 && win.input != nullptr && win.output != nullptr) {
            const size_t n = static_cast<size_t>(win.frames) * CustodyVerifier::kChannels;
            const uint64_t inH = fnv1a64(win.input, n);
            const uint64_t outH = fnv1a64(win.output, n);
            custodyInHash = hex64(inH);
            custodyOutHash = hex64(outH);
            custodyBitExact = (!win.truncated && inH == outH);
        }

        auto jitterBuf = makeStereoSine(kTotalFrames, kSampleRate, 12000.0, ampMinus3dB, ampMinus3dB);
        runEngineBlocks(*engine, jitterBuf, kTotalFrames);
        writePcmWav(outDir / "jitter_12khz_24bit.wav", jitterBuf, kSampleRate, kChannels, 24, false);
    }

    // 6. Tap-SRC 44.1 kHz -> 48 kHz (512-tap / quality 3 HighQualityResampler)
    {
        const int inRate = 44100;
        const int outRate = 48000;
        const int inFrames = 32768;
        auto src = makeStereoSine(inFrames, inRate, 1000.0, ampMinus3dB, ampMinus3dB);
        std::vector<float> inL(inFrames);
        std::vector<float> inR(inFrames);
        for (int i = 0; i < inFrames; ++i) {
            inL[i] = src[i * 2];
            inR[i] = src[i * 2 + 1];
        }
        pulsr::HighQualityResampler resampler;
        resampler.configure(kChannels, 512, 2048,
                            static_cast<double>(inRate), static_cast<double>(outRate));
        const int maxOut = static_cast<int>(std::ceil(inFrames * (static_cast<double>(outRate) / inRate))) + 2048;
        std::vector<float> outL(maxOut, 0.0f);
        std::vector<float> outR(maxOut, 0.0f);
        const float* inPtrs[2] = {inL.data(), inR.data()};
        float* outPtrs[2] = {outL.data(), outR.data()};
        int consumed = 0;
        int produced = resampler.process(inPtrs, inFrames, outPtrs, maxOut, consumed);

        // Drain the resampler tail (§8.7) with silence to recover full latency window
        std::vector<float> drainIn(512, 0.0f);
        const float* drainPtrs[2] = {drainIn.data(), drainIn.data()};
        int drainConsumed = 0;
        float* tailPtrs[2] = {outL.data() + produced, outR.data() + produced};
        const int tailProduced = resampler.process(drainPtrs, 512, tailPtrs, maxOut - produced, drainConsumed);
        produced += tailProduced;

        // Trim initial kernel warm-up (512 frames) so steady-state THD+N is measured cleanly.
        const int skip = std::min(512, produced / 4);
        const int keep = std::max(0, produced - skip);
        std::vector<float> resampled(static_cast<size_t>(keep) * kChannels);
        for (int i = 0; i < keep; ++i) {
            resampled[i * 2] = outL[skip + i];
            resampled[i * 2 + 1] = outR[skip + i];
        }
        writePcmWav(outDir / "tap_src_441_to_48_512taps.wav", resampled, outRate, kChannels, 24, false);
    }

    // Write manifest JSON for measure_fft.py
    const fs::path manifestPath = outDir / "native_manifest.json";
    {
        std::ofstream m(manifestPath);
        m << "{\n"
          << "  \"provenance\": \"native_dsp_render\",\n"
          << "  \"sampleRate\": " << kSampleRate << ",\n"
          << "  \"custodyBitExact\": " << (custodyBitExact ? "true" : "false") << ",\n"
          << "  \"custodyInputFnv1a64\": \"" << custodyInHash << "\",\n"
          << "  \"custodyOutputFnv1a64\": \"" << custodyOutHash << "\"\n"
          << "}\n";
    }

    std::cout << "Rendered native DSP FFT captures to " << outDir.string()
              << " (custodyBitExact=" << (custodyBitExact ? "true" : "false") << ")\n";
    return 0;
}
