// android/app/src/test/cpp/test_dsp_correctness.cpp
//
// Regression tests for the DSP-math fixes made in the audio review:
//  - HarmonicSaturation Tube/Analog modes actually generate harmonics and stay
//    bounded/DC-free (Mode 1 used to be an exact identity).
//  - ArbitraryResponseEq's synthesized FIR implements the requested response
//    (the default path used to discard half the kernel).
//  - ViperDdc auto-detects the coefficient sign convention and never blows up.
//  - ConvolutionReverb aligns dry and wet (dry used to arrive ~10.7 ms early).
//
// This file is #included by test_native_all.cpp (no own main()).

void runSaturationHarmonicsTest() {
    std::cout << "\n=== [CORRECTNESS 1/4] HarmonicSaturation modes generate harmonics ===" << std::endl;
    HarmonicSaturation sat;
    sat.setSampleRate(48000.0);

    const int n = 8192;
    std::vector<float> base(n * 2);
    for (int i = 0; i < n; ++i) {
        const float s = 0.7f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f *
                                        static_cast<float>(i) / 48000.0f);
        base[i * 2] = s;
        base[i * 2 + 1] = s;
    }

    auto render = [&](int mode, std::vector<float>& out) {
        SaturationParamSet p;
        p.enabled = true;
        p.drive = 0.8;
        p.mix = 1.0;
        p.tilt = 0.0;
        p.mode = mode;
        p.multiband = false;
        sat.applyParams(p);
        sat.reset();
        out = base;
        sat.processInterleaved(out.data(), n, 2);
    };

    for (int mode = 0; mode <= 2; ++mode) {
        std::vector<float> out;
        render(mode, out);

        double num = 0.0, den = 0.0;
        float maxPos = 0.0f, maxNeg = 0.0f, maxAbs = 0.0f;
        double sumDc = 0.0;
        for (int i = 0; i < n; ++i) {
            const float x = base[i * 2];
            const float y = out[i * 2];
            assert(std::isfinite(y));
            num += (y - x) * (y - x);
            den += x * x;
            maxPos = std::max(maxPos, y);
            maxNeg = std::max(maxNeg, -y);
            maxAbs = std::max(maxAbs, std::abs(y));
            if (i >= n / 2) sumDc += y;
        }
        const double diffRms = std::sqrt(num / den);

        // Every mode must actually change the signal (Mode 1 used to be identity).
        assert(diffRms > 0.02);
        // Bounded output (1/k makeup => well under full scale).
        assert(maxAbs <= 1.0f);
        // DC must be blocked on the asymmetric modes.
        assert(std::abs(sumDc / (n / 2)) < 0.01);

        const float asymmetry = std::abs(maxPos - maxNeg);
        if (mode == 0) {
            // Tape mode is symmetric.
            assert(asymmetry < 0.01f);
        } else {
            // Tube / Class-A are asymmetric.
            assert(asymmetry > 0.02f);
        }
    }
    std::cout << "  ✓ Modes 0/1/2 all non-identity, bounded, DC-free, correct symmetry." << std::endl;
}

void runArbitraryEqResponseTest() {
    std::cout << "\n=== [CORRECTNESS 2/4] ArbitraryResponseEq synthesizes requested response ===" << std::endl;
    ArbitraryResponseEq eq;
    eq.setSampleRate(48000.0);
    eq.setEnabled(true);
    const bool ok = eq.loadGraphicEqString("GraphicEq: 100 0; 1000 6; 10000 0", false);
    assert(ok);

    const int n = 32768;
    auto rmsAt = [&](double freq) -> double {
        std::vector<float> buf(n * 2);
        for (int i = 0; i < n; ++i) {
            const float s = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) *
                                            static_cast<float>(freq) * static_cast<float>(i) / 48000.0f);
            buf[i * 2] = s;
            buf[i * 2 + 1] = s;
        }
        eq.reset();
        eq.processInterleaved(buf.data(), n, 2);
        double sum = 0.0;
        int count = 0;
        for (int i = n / 2; i < n; ++i) {
            assert(std::isfinite(buf[i * 2]));
            sum += static_cast<double>(buf[i * 2]) * buf[i * 2];
            ++count;
        }
        return std::sqrt(sum / count);
    };

    const double r1k = rmsAt(1000.0);
    const double r100 = rmsAt(100.0);
    const double r10k = rmsAt(10000.0);

    // +6 dB at 1 kHz must be a clear boost vs the ~unity out-of-band response.
    assert(r1k > r100 * 1.4);
    assert(r100 > 0.05);
    assert(r10k > 0.05);
    std::cout << "  ✓ Response: 100Hz=" << r100 << ", 1kHz=" << r1k
              << ", 10kHz=" << r10k << " (1k boosted)." << std::endl;
}

void runViperDdcConventionTest() {
    std::cout << "\n=== [CORRECTNESS 3/4] ViperDdc sign-convention auto-detect ===" << std::endl;
    // Coefficients (a1=1.0, a2=-0.6) are unstable in the positive-denominator
    // convention but stable once negated; the parser must flip them and keep the
    // section, and processing must never blow up.
    ViperDdc ddc;
    ddc.setSampleRate(48000.0);
    ddc.setEnabled(true);
    const bool ok = ddc.loadVdcString("SR_48000 1.0 0.0 0.0 1.0 -0.6");
    assert(ok);
    assert(ddc.getSectionCount() > 0);

    const int n = 16384;
    std::vector<float> buf(n * 2);
    for (int i = 0; i < n; ++i) {
        const float s = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f *
                                        static_cast<float>(i) / 48000.0f);
        buf[i * 2] = s;
        buf[i * 2 + 1] = s;
    }
    ddc.processInterleaved(buf.data(), n, 2);
    float maxAbs = 0.0f;
    for (float v : buf) {
        assert(std::isfinite(v));
        maxAbs = std::max(maxAbs, std::abs(v));
    }
    assert(maxAbs < 10.0f);
    std::cout << "  ✓ Unstable-in-positive-convention section flipped to stable (peak "
              << maxAbs << ")." << std::endl;
}

void runReverbDryWetAlignmentTest() {
    std::cout << "\n=== [CORRECTNESS 4/4] ConvolutionReverb dry/wet time alignment ===" << std::endl;
    ConvolutionReverb reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWetDry(0.5);
    reverb.setPredelay(0.0);

    // Partitioned mode needs > 1024 taps; a single tap at 0 makes wet == dry
    // (both delayed by the one-block partition latency) so the mix must be a
    // clean, single-tap delayed copy.
    const int irLen = 2048;
    std::vector<float> ir(irLen * 2, 0.0f);
    ir[0] = 1.0f;
    ir[1] = 1.0f;
    assert(reverb.loadCustomIR(ir.data(), irLen, 2));
    reverb.reset();

    const int blockSize = 512;
    const int numBlocks = 12;
    const int total = blockSize * numBlocks;
    std::vector<float> inL(total), inR(total), outL(total, 0.0f), outR(total, 0.0f);
    for (int i = 0; i < total; ++i) {
        const float s = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f *
                                 static_cast<float>(i) / 48000.0f);
        inL[i] = s;
        inR[i] = s;
    }
    for (int b = 0; b < numBlocks; ++b) {
        reverb.process(&inL[b * blockSize], &inR[b * blockSize],
                       &outL[b * blockSize], &outR[b * blockSize], blockSize);
    }

    const int latency = 512;
    // Equal-power dry/wet at 0.5 -> both gains = sin/cos(pi/4) = 0.7071, so the
    // aligned sum recombines to (cos+sin)*dry = sqrt(2)*dry.
    const double k = std::cos(0.25 * M_PI) + std::sin(0.25 * M_PI);
    int mismatches = 0;
    float maxErr = 0.0f;
    for (int i = latency; i < total; ++i) {
        const float expected = static_cast<float>(k * inL[i - latency]);
        const float err = std::abs(expected - outL[i]);
        maxErr = std::max(maxErr, err);
        if (err > 1e-3f) ++mismatches;
    }
    assert(mismatches == 0 && maxErr < 1e-3f);
    std::cout << "  ✓ Dry+wet recombine as a single " << latency
              << "-frame delayed copy (max err " << maxErr << ")." << std::endl;
}
