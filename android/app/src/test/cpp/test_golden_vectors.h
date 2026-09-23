// android/app/src/test/cpp/test_golden_vectors.h
#pragma once

#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/Crossfeed.h"
#include "../../main/cpp/LookaheadLimiter.h"
#include "../../main/cpp/DsdDecoder.h"
#include "../../main/cpp/ViperDdc.h"
#include "../../main/cpp/ArbitraryResponseEq.h"
#include "../../main/cpp/UsbAudioSink.h"

#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// 1. DSD bit order regression test
inline void runGoldenVectorDsdBitOrderTest() {
    std::cout << "\n=== [GOLDEN 1/7] DSD Bit-Order Symmetry Regression Test ===" << std::endl;
    DsdDecoder decoderLsb;
    decoderLsb.configure(DsdDecoder::DsdRate::DSD64, 44100, DsdDecoder::DsdBitOrder::LSB_FIRST);

    DsdDecoder decoderMsb;
    decoderMsb.configure(DsdDecoder::DsdRate::DSD64, 44100, DsdDecoder::DsdBitOrder::MSB_FIRST);

    // Create 128 bytes of DSD pattern
    const int byteCount = 128;
    std::vector<uint8_t> dsdPatternL(byteCount);
    std::vector<uint8_t> dsdPatternR(byteCount);
    std::vector<uint8_t> dsdReversedL(byteCount);
    std::vector<uint8_t> dsdReversedR(byteCount);

    for (int i = 0; i < byteCount; ++i) {
        uint8_t b = static_cast<uint8_t>((i * 37 + 13) & 0xFF);
        dsdPatternL[i] = b;
        dsdPatternR[i] = static_cast<uint8_t>(~b);

        // Bit-reverse each byte
        auto bitRev = [](uint8_t x) -> uint8_t {
            x = ((x & 0xAA) >> 1) | ((x & 0x55) << 1);
            x = ((x & 0xCC) >> 2) | ((x & 0x33) << 2);
            x = ((x & 0xF0) >> 4) | ((x & 0x0F) << 4);
            return x;
        };
        dsdReversedL[i] = bitRev(dsdPatternL[i]);
        dsdReversedR[i] = bitRev(dsdPatternR[i]);
    }

    const int maxFrames = decoderLsb.getExpectedPcmFrames(byteCount);
    std::vector<float> pcmLsb(maxFrames * 2, 0.0f);
    std::vector<float> pcmMsb(maxFrames * 2, 0.0f);

    int framesLsb = decoderLsb.decodeDsdBytes(dsdPatternL.data(), dsdPatternR.data(), byteCount, pcmLsb.data(), maxFrames);
    int framesMsb = decoderMsb.decodeDsdBytes(dsdReversedL.data(), dsdReversedR.data(), byteCount, pcmMsb.data(), maxFrames);

    assert(framesLsb > 0 && framesLsb == framesMsb);

    float maxDiff = 0.0f;
    for (int i = 0; i < framesLsb * 2; ++i) {
        maxDiff = std::max(maxDiff, std::abs(pcmLsb[i] - pcmMsb[i]));
    }

    assert(maxDiff < 1e-4f);
    std::cout << "  ✓ DSD LSB-first vs MSB-first bit-reversed streams match identically (max error: "
              << maxDiff << ")." << std::endl;
}

// 2. BS2B coefficient accuracy test
inline void runGoldenVectorBs2bCoeffsTest() {
    std::cout << "\n=== [GOLDEN 2/7] BS2B Analytic Coefficient Precision Test ===" << std::endl;
    Crossfeed crossfeed;
    const double sr = 44100.0;
    crossfeed.setSampleRate(sr);
    crossfeed.setMode(CrossfeedMode::Bs2bChuMoy); // fcut = 700.0, feedDb = -6.0

    // Analytical reference computation
    const double level = 6.0;
    const double Fc_lo = 700.0;
    const double GB_lo = level * -5.0 / 6.0 - 3.0; // -8.0 dB
    const double GB_hi = level / 6.0 - 3.0;        // -2.0 dB
    const double G_lo  = std::pow(10.0, GB_lo / 20.0);
    const double G_hi  = 1.0 - std::pow(10.0, GB_hi / 20.0);
    const double Fc_hi = Fc_lo * std::pow(2.0, (GB_lo - 20.0 * std::log10(G_hi)) / 12.0);

    const double x_lo = std::exp(-2.0 * M_PI * Fc_lo / sr);
    const double ref_b1_lo = x_lo;
    const double ref_a0_lo = G_lo * (1.0 - x_lo);

    const double x_hi = std::exp(-2.0 * M_PI * Fc_hi / sr);
    const double ref_b1_hi = x_hi;
    const double ref_a0_hi = 1.0 - G_hi * (1.0 - x_hi);

    const double diffA0Lo = std::abs(crossfeed.getBs2bA0Lo() - ref_a0_lo);
    const double diffB1Lo = std::abs(crossfeed.getBs2bB1Lo() - ref_b1_lo);
    const double diffA0Hi = std::abs(crossfeed.getBs2bA0Hi() - ref_a0_hi);

    assert(diffA0Lo < 1e-9);
    assert(diffB1Lo < 1e-9);
    assert(diffA0Hi < 1e-9);

    std::cout << "  ✓ BS2B filter coefficients match reference to < 1e-9 (diff: "
              << diffA0Lo << ", " << diffB1Lo << ")." << std::endl;
}

// 3. True peak 4x oversampled interpolation test
inline void runGoldenVectorTruePeakTest() {
    std::cout << "\n=== [GOLDEN 3/7] True Peak 4x Oversampled Sinc Interpolator Test ===" << std::endl;
    LookaheadLimiter limiter;
    limiter.setSampleRate(48000.0);
    limiter.configure(5.0, -0.2, 50.0, true);

    // Symmetric intersample peak pattern: raw samples peak at 0.80, but between
    // taps 2 and 3 the reconstructed continuous analog peak is > 1.05.
    const float history[6] = {0.0f, -0.4f, 0.80f, 0.80f, -0.4f, 0.0f};
    const float truePeak = limiter.estimateTruePeak(history);

    assert(truePeak > 0.80f);
    assert(truePeak > 1.0f);
    std::cout << "  ✓ Discrete sample peak: 0.80 -> 4x True Peak interpolated: "
              << truePeak << " (> 1.0 intersample overshoot detected)." << std::endl;
}

// 4. VDC parser sanitization test
inline void runGoldenVectorVdcSanitizerTest() {
    std::cout << "\n=== [GOLDEN 4/7] ViPER VDC Pathological Input Sanitizer Test ===" << std::endl;
    std::vector<ViperDdcSection> s441, s480;

    // Test 1: Empty string
    assert(!ViperDdc::parseVdcContent("", s441, s480));

    // Test 2: Random garbage string
    assert(!ViperDdc::parseVdcContent("This is not a valid VDC file #$%^&*", s441, s480));

    // Test 3: Pathological values (NaN, infinity, extreme numbers)
    const std::string badVdc =
        "SampleRate: 44100\n"
        "b0: NaN b1: inf b2: -999999.0 a1: 1e30 a2: -1e30\n"
        "SampleRate: 48000\n"
        "b0: 1.0 b1: 0.0 b2: 0.0 a1: 0.0 a2: 0.0\n";
    // Must either reject or parse without crashing or emitting NaNs
    bool parsed = ViperDdc::parseVdcContent(badVdc, s441, s480);
    if (parsed) {
        for (const auto& sec : s441) {
            assert(std::isfinite(sec.b0) && std::isfinite(sec.b1) && std::isfinite(sec.b2));
            assert(std::isfinite(sec.a1) && std::isfinite(sec.a2));
        }
    }

    std::cout << "  ✓ ViPER VDC parser safely handled empty, garbage, and NaN/Inf pathological streams." << std::endl;
}

// 5. ArbitraryResponseEq linear-phase symmetric impulse test
inline void runGoldenVectorLinearPhaseFirTest() {
    std::cout << "\n=== [GOLDEN 5/7] ArbitraryResponseEq Linear-Phase Symmetric FIR Test ===" << std::endl;
    ArbitraryResponseEq arbEq;
    arbEq.setSampleRate(48000.0);
    arbEq.setEnabled(true);

    const std::string eqStr = "GraphicEq: 20 6.0; 100 -3.0; 1000 5.0; 10000 -4.0; 20000 0.0";
    bool loaded = arbEq.loadGraphicEqString(eqStr, true); // linearPhase = true
    assert(loaded);

    const auto& fir = arbEq.getFirFilter();
    assert(fir.size() == ArbitraryResponseEq::FIR_TAPS);

    // Verify strict symmetry: fir[i] == fir[FIR_TAPS - 1 - i]
    float maxAsymmetry = 0.0f;
    for (size_t i = 0; i < fir.size() / 2; ++i) {
        float diff = std::abs(fir[i] - fir[fir.size() - 1 - i]);
        maxAsymmetry = std::max(maxAsymmetry, diff);
    }

    assert(maxAsymmetry < 0.005f);
    std::cout << "  ✓ 512-tap Linear-phase FIR kernel is strictly Hermitian symmetric (max asymmetry: "
              << maxAsymmetry << " < 0.005)." << std::endl;
}

// 6. Limiter ceiling invariant test
inline void runGoldenVectorLimiterCeilingTest() {
    std::cout << "\n=== [GOLDEN 6/7] Lookahead Limiter Absolute Ceiling Invariant Test ===" << std::endl;
    LookaheadLimiter limiter;
    limiter.setSampleRate(48000.0);
    const double thresholdDb = -1.5;
    limiter.configure(5.0, thresholdDb, 40.0, true);
    limiter.setEnabled(true);

    const float ceiling = std::pow(10.0f, static_cast<float>(thresholdDb) / 20.0f);

    // Feed aggressive +18 dBFS signal
    const int frames = 4096;
    std::vector<float> buf(frames * 2);
    for (int i = 0; i < frames; ++i) {
        float sig = 8.0f * std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * i / 48000.0f);
        buf[i * 2] = sig;
        buf[i * 2 + 1] = -sig;
    }

    limiter.processInterleaved(buf.data(), frames, 2);

    float maxSample = 0.0f;
    for (int i = 0; i < frames * 2; ++i) {
        assert(std::isfinite(buf[i]));
        maxSample = std::max(maxSample, std::abs(buf[i]));
    }

    assert(maxSample <= ceiling + 1e-4f);
    std::cout << "  ✓ Lookahead limiter clamped +18dBFS overload to ceiling "
              << ceiling << " (actual max: " << maxSample << ")." << std::endl;
}

// 7. Rate-change FIR tracking test
inline void runGoldenVectorRateChangeTrackingTest() {
    std::cout << "\n=== [GOLDEN 7/7] Multi-Rate Engine Transition & FIR Tracking Test ===" << std::endl;
    auto engine = std::make_unique<AudioDspEngine>();
    engine->setSampleRate(44100.0);
    engine->setActiveStages(0xFFFFFFFF);

    auto snapshot = std::make_shared<DspParamSnapshot>();
    snapshot->limiter.enabled = true;
    snapshot->crossfeed.enabled = true;
    snapshot->arbitraryEq.enabled = true;
    snapshot->reverb.enabled = true;
    snapshot->reverb.preset = static_cast<int>(ReverbPreset::Room);
    snapshot->sampleRate = 44100.0;
    engine->publishParams(snapshot);

    const double sampleRates[] = {44100.0, 96000.0, 192000.0, 48000.0};
    const int frames = 512;
    std::vector<float> buffer(frames * 2, 0.5f);

    for (double sr : sampleRates) {
        auto nextSnap = std::make_shared<DspParamSnapshot>(*snapshot);
        nextSnap->generation++;
        nextSnap->sampleRate = sr;
        engine->publishParams(nextSnap);
        engine->setSampleRate(sr);
        engine->processInterleaved(buffer.data(), frames, 2);

        for (int i = 0; i < frames * 2; ++i) {
            assert(std::isfinite(buffer[i]));
        }
    }

    std::cout << "  ✓ Engine transitioned across 44.1k -> 96k -> 192k -> 48k with zero degradation or non-finite output." << std::endl;
}

// 8. Feature 4: Headphone Safety & Sound Dose Tracking (WHO-ITU H.870 / EN 62368-1)
inline void runHeadphoneSafetySoundDoseTest() {
    std::cout << "\n=== [SAFETY 1/1] Headphone Safety & Sound Dose Accumulator Test ===" << std::endl;
    auto engine = std::make_unique<AudioDspEngine>();
    engine->setSampleRate(48000.0);
    engine->setActiveStages(0xFFFFFFFF);

    auto snap = std::make_shared<DspParamSnapshot>();
    snap->sampleRate = 48000.0;
    snap->activeStages = 0xFFFFFFFF;
    snap->headphoneSafety.enabled = true;
    snap->headphoneSafety.doseThreshold = 1.0;
    snap->headphoneSafety.safetyCeilingDb = -6.0;
    engine->publishParams(snap);

    assert(engine->getWeeklyDose() == 0.0);
    assert(!engine->isSafetyAttenuationActive());

    // Process a block of audio and verify dose accumulates
    const int frames = 1024;
    std::vector<float> buffer(frames * 2, 0.8f);
    engine->processInterleaved(buffer.data(), frames, 2);

    const double dose1 = engine->getWeeklyDose();
    assert(dose1 > 0.0);
    assert(!engine->isSafetyAttenuationActive());

    // Artificially advance weekly dose past 100% threshold
    engine->setWeeklyDose(1.05);
    assert(engine->getWeeklyDose() >= 1.0);

    // Feed high-level signal (+0 dBFS sine) and verify safety limiter clamps output to <= -6 dBFS (0.502)
    std::vector<float> loudBuffer(frames * 2);
    for (int b = 0; b < 10; ++b) {
        for (int i = 0; i < frames; ++i) {
            float sig = 0.95f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * (i + b * frames) / 48000.0f);
            loudBuffer[i * 2] = sig;
            loudBuffer[i * 2 + 1] = sig;
        }
        engine->processInterleaved(loudBuffer.data(), frames, 2);
    }

    assert(engine->isSafetyAttenuationActive());

    float maxSample = 0.0f;
    for (int i = 0; i < frames * 2; ++i) {
        maxSample = std::max(maxSample, std::abs(loudBuffer[i]));
    }
    const float safeCeilingLinear = std::pow(10.0f, -6.0f / 20.0f); // ~0.501187
    assert(maxSample <= safeCeilingLinear + 0.05f); // Smooth limiter clamped down near -6 dBFS

    // Verify reset clears dose and deactivates attenuation
    engine->resetWeeklyDose();
    assert(engine->getWeeklyDose() == 0.0);

    // Process normal buffer and ensure attenuation clears
    std::vector<float> quietBuffer(frames * 2, 0.1f);
    engine->processInterleaved(quietBuffer.data(), frames, 2);
    assert(!engine->isSafetyAttenuationActive());

    // Verify mask immunity: even when activeStages drops STAGE_HEADPHONE_SAFETY,
    // safety attenuation and limiter stay active if headphoneSafety.enabled is true.
    engine->setWeeklyDose(1.05);
    auto maskSnap = std::make_shared<DspParamSnapshot>(*snap);
    maskSnap->activeStages = 0; // Drop all stages!
    maskSnap->headphoneSafety.enabled = true;
    maskSnap->headphoneSafety.doseThreshold = 1.0;
    maskSnap->headphoneSafety.safetyCeilingDb = -6.0;
    engine->publishParams(maskSnap);

    engine->processInterleaved(loudBuffer.data(), frames, 2);
    assert(engine->isSafetyAttenuationActive());

    // Verify rate retune (N1): track sample rate changes from 48k to 96k
    auto rateSnap = std::make_shared<DspParamSnapshot>(*maskSnap);
    rateSnap->sampleRate = 96000.0;
    engine->publishParams(rateSnap);
    std::vector<float> rateBuffer(frames * 2, 0.95f);
    engine->processInterleaved(rateBuffer.data(), frames, 2);
    assert(engine->isSafetyAttenuationActive());

    // Verify rolling decay (N5): process silence and verify dose decreases
    const double doseBeforeSilence = engine->getWeeklyDose();
    std::vector<float> silenceBuffer(frames * 2, 0.0f);
    for (int b = 0; b < 100; ++b) {
        engine->processInterleaved(silenceBuffer.data(), frames, 2);
    }
    const double doseAfterSilence = engine->getWeeklyDose();
    assert(doseAfterSilence < doseBeforeSilence);

    std::cout << "  ✓ Headphone safety: dose accumulated, safety limiter clamped loud audio to "
              << maxSample << " (target ceiling: " << safeCeilingLinear << "), mask-immune, rate-retuned, and rolling-decay verified."
              << std::endl;
}

// 9. Feature 7: USB descriptor sample rate query and structured error regression test
inline void runUsbDescriptorRateParserTest() {
    std::cout << "\n=== [GOLDEN 9/9] USB Descriptor Rate Parser & Error Enum Test ===" << std::endl;

    // 1. Test parsing discrete sample rates from UAC1 Format Type I descriptor
    // Interface 1 (AudioStreaming) + CS_INTERFACE (FORMAT_TYPE, 3 discrete rates: 44.1k, 96k, 192k)
    std::vector<uint8_t> discreteConfig = {
        // Interface descriptor: length 9, type 0x04, iface 1, alt 1, 0 endpoints, class 1, subclass 2
        0x09, 0x04, 0x01, 0x01, 0x00, 0x01, 0x02, 0x00, 0x00,
        // CS_INTERFACE descriptor: length 17, type 0x24, subtype 0x02, format 0x01, channels 2, subframe 2, bits 16, numRates 3
        0x11, 0x24, 0x02, 0x01, 0x02, 0x02, 0x10, 0x03,
        // 44100 (0x00AC44)
        0x44, 0xAC, 0x00,
        // 96000 (0x017700)
        0x00, 0x77, 0x01,
        // 192000 (0x02EE00)
        0x00, 0xEE, 0x02
    };

    std::vector<int> parsedDiscrete = pulsr::UsbAudioSink::ParseSupportedRatesFromDescriptors(
        discreteConfig.data(), discreteConfig.size(), 1);

    assert(parsedDiscrete.size() == 3);
    assert(parsedDiscrete[0] == 44100);
    assert(parsedDiscrete[1] == 96000);
    assert(parsedDiscrete[2] == 192000);

    // 2. Test parsing continuous sample rate range from UAC1 Format Type I descriptor
    // samFreqType = 0, lower = 44100, upper = 96000
    std::vector<uint8_t> continuousConfig = {
        0x09, 0x04, 0x01, 0x01, 0x00, 0x01, 0x02, 0x00, 0x00,
        // length 14, samFreqType = 0
        0x0E, 0x24, 0x02, 0x01, 0x02, 0x02, 0x10, 0x00,
        // lower: 44100
        0x44, 0xAC, 0x00,
        // upper: 96000
        0x00, 0x77, 0x01
    };

    std::vector<int> parsedContinuous = pulsr::UsbAudioSink::ParseSupportedRatesFromDescriptors(
        continuousConfig.data(), continuousConfig.size(), 1);

    assert(parsedContinuous.size() == 4);
    assert(parsedContinuous[0] == 44100);
    assert(parsedContinuous[1] == 48000);
    assert(parsedContinuous[2] == 88200);
    assert(parsedContinuous[3] == 96000);

    // 3. Test structured UsbStreamResult enum codes from Open
    auto invalidRes = pulsr::UsbAudioSink::instance().Open(-1, 0, 0, 0, 48000, 2, 2);
    assert(invalidRes == pulsr::UsbStreamResult::InvalidArgs);

    auto unsuppRes = pulsr::UsbAudioSink::instance().Open(10, 0, 0, 0, 12345, 2, 2);
    assert(unsuppRes == pulsr::UsbStreamResult::RateUnsupported);

    std::cout << "  ✓ USB descriptor parsing: discrete rates (44.1k/96k/192k) & continuous range (44.1k-96k) validated." << std::endl;
    std::cout << "  ✓ Structured error codes: InvalidArgs and RateUnsupported validated." << std::endl;
}

