// android/app/src/test/cpp/test_sdm.cpp
//
// Host test for pulsr::SdmModulator (Contract C): configuration domain, LSB-first
// byte packing against an independently written reference chain, 2 s of 1 kHz at
// -1 dBFS with measured in-band SNR, DC density, saturation-run bounds, capacity
// rejection and reset() behaviour.
#include "../../main/cpp/SdmModulator.h"
#include "../../main/cpp/Oversampler.h"

#include "FftUtil.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

int gFailures = 0;
constexpr double kPi = 3.14159265358979323846;

void Check(bool ok, const char* what) {
    if (!ok) {
        std::printf("  FAIL %s\n", what);
        ++gFailures;
    }
}

// Independent reference for the documented CIFB difference equations. Written from
// the header documentation, not from the production source.
struct ReferenceLoop {
    int order = 4;
    float a[6] = {0.0f, 0.0128f, 0.08362247f, 0.273075f, 0.522625185951f, 0.0f};
    float rho = 0.5f;
    float b1 = 0.0128f;
    float s[6] = {};
    float lastBit = 0.0f;

    int next(float x) {
        const float u = 0.5f * b1 * x;  // documented 6 dB DSD headroom
        for (int i = order; i >= 1; --i) {
            const float prev = (i == 1) ? u : rho * s[i - 1];
            float v = s[i] + prev - a[i] * lastBit;
            if (!(v > -4.0f)) v = -4.0f;
            if (v > 4.0f) v = 4.0f;
            s[i] = v;
        }
        const float v = (s[order] >= 0.0f) ? 1.0f : -1.0f;
        lastBit = v;
        return v > 0.0f ? 1 : 0;
    }
};

// Packs planar bits by hand: first sample -> bit 0 of the first byte.
std::vector<uint8_t> ReferencePack(const std::vector<int>& bits) {
    std::vector<uint8_t> out((bits.size() + 7) / 8, 0);
    for (size_t i = 0; i < bits.size(); ++i) {
        if (bits[i]) out[i / 8] = uint8_t(out[i / 8] | (1u << (i % 8)));
    }
    return out;
}

int PopCount(uint8_t v) {
    int n = 0;
    for (int b = 0; b < 8; ++b) n += (v >> b) & 1;
    return n;
}

int LongestRun(const std::vector<uint8_t>& bytes) {
    int best = 0;
    int run = 0;
    int last = -1;
    for (uint8_t b : bytes) {
        for (int i = 0; i < 8; ++i) {
            const int bit = (b >> i) & 1;
            if (bit == last) {
                ++run;
            } else {
                run = 1;
                last = bit;
            }
            best = std::max(best, run);
        }
    }
    return best;
}

double OnesDensity(const std::vector<uint8_t>& bytes) {
    if (bytes.empty()) return 0.0;
    long ones = 0;
    for (uint8_t b : bytes) ones += PopCount(b);
    return double(ones) / double(bytes.size() * 8);
}

// In-band SNR/SINAD of the 1-bit stream. The applied tone is removed with a
// least-squares fit at the exact test frequency, so window leakage cannot floor the
// measurement; the residual's periodogram then integrates the 20 Hz..20 kHz noise.
// The reported figure therefore includes distortion (SINAD), which is the stricter
// reading of "in-band SNR".
double MeasureSnrDb(const std::vector<uint8_t>& bytes, double fs, double toneHz, int fftSize,
                    double* outToneAmp) {
    const int total = int(bytes.size()) * 8;
    if (total < fftSize) return -1.0;
    const int start = (total - fftSize) / 2;
    std::vector<double> y(static_cast<size_t>(fftSize));
    const double w = 2.0 * kPi * toneHz / fs;

    double cx = 0.0, sx = 0.0, cxx = 0.0, sxx = 0.0, cxs = 0.0;
    for (int i = 0; i < fftSize; ++i) {
        const int bit = (bytes[size_t((start + i) / 8)] >> ((start + i) % 8)) & 1;
        y[size_t(i)] = bit ? 1.0 : -1.0;
        const double c = std::cos(w * double(start + i));
        const double s = std::sin(w * double(start + i));
        cx += c;
        sx += s;
        cxx += c * c;
        sxx += s * s;
        cxs += c * s;
    }
    double cy = 0.0, sy = 0.0, sum = 0.0;
    for (int i = 0; i < fftSize; ++i) {
        const double c = std::cos(w * double(start + i));
        const double s = std::sin(w * double(start + i));
        cy += c * y[size_t(i)];
        sy += s * y[size_t(i)];
        sum += y[size_t(i)];
    }
    double m[3][4] = {{cxx, cxs, cx, cy}, {cxs, sxx, sx, sy}, {cx, sx, double(fftSize), sum}};
    for (int col = 0; col < 3; ++col) {
        int piv = col;
        for (int r = col + 1; r < 3; ++r) {
            if (std::abs(m[r][col]) > std::abs(m[piv][col])) piv = r;
        }
        for (int c = 0; c < 4; ++c) std::swap(m[col][c], m[piv][c]);
        const double d = m[col][col];
        if (std::abs(d) < 1e-12) return -1.0;
        for (int c = col; c < 4; ++c) m[col][c] /= d;
        for (int r = 0; r < 3; ++r) {
            if (r == col) continue;
            const double f = m[r][col];
            for (int c = col; c < 4; ++c) m[r][c] -= f * m[col][c];
        }
    }
    const double a = m[0][3];
    const double b = m[1][3];
    const double dc = m[2][3];
    if (outToneAmp != nullptr) *outToneAmp = std::sqrt(a * a + b * b);

    std::vector<FftUtil::Complex> spec(static_cast<size_t>(fftSize), FftUtil::Complex(0.0f, 0.0f));
    double wsum = 0.0;
    for (int i = 0; i < fftSize; ++i) {
        const double win = 0.5 - 0.5 * std::cos(2.0 * kPi * double(i) / double(fftSize - 1));
        const double fit =
            a * std::cos(w * double(start + i)) + b * std::sin(w * double(start + i)) + dc;
        spec[size_t(i)] = FftUtil::Complex(float((y[size_t(i)] - fit) * win), 0.0f);
        wsum += win * win;
    }
    FftUtil::fft(spec);
    double noise = 0.0;
    for (int k = 1; k < fftSize / 2; ++k) {
        const double f = double(k) * fs / double(fftSize);
        if (f < 20.0 || f > 20000.0) continue;
        noise += double(std::norm(spec[size_t(k)]));
    }
    noise /= (double(fftSize) * wsum);
    const double signal = 0.5 * (a * a + b * b);
    if (!(noise > 0.0)) return 200.0;
    return 10.0 * std::log10(signal / noise);
}

struct ToneRun {
    std::vector<uint8_t> left;
    std::vector<uint8_t> right;
    int bytes = 0;
    float peakState = 0.0f;
};

ToneRun RunTone(pulsr::SdmModulator& sdm, double fs, double toneHz, double amplitude, double seconds,
                int block, int multiple) {
    const int frames = int(std::lround(fs * seconds));
    ToneRun run;
    const int capacity = frames * multiple / 8 + 8;
    run.left.assign(static_cast<size_t>(capacity), 0);
    run.right.assign(static_cast<size_t>(capacity), 0);
    std::vector<float> l(static_cast<size_t>(block)), r(static_cast<size_t>(block));
    int done = 0;
    while (done < frames) {
        const int n = std::min(block, frames - done);
        for (int i = 0; i < n; ++i) {
            const double t = double(done + i) / fs;
            l[size_t(i)] = float(amplitude * std::sin(2.0 * kPi * toneHz * t));
            r[size_t(i)] = float(-amplitude * std::sin(2.0 * kPi * toneHz * t));
        }
        const float* pin[2] = {l.data(), r.data()};
        const int writtenHere = (done * multiple) / 8;
        const int written = sdm.process(pin, n, run.left.data() + writtenHere,
                                       run.right.data() + writtenHere,
                                       capacity - writtenHere);
        if (written < 0) {
            std::printf("  FAIL tone block rejected (frames=%d)\n", n);
            ++gFailures;
            break;
        }
        run.bytes += written;
        done += n;
    }
    run.peakState = sdm.peakStateMagnitude();
    run.left.resize(static_cast<size_t>(run.bytes));
    run.right.resize(static_cast<size_t>(run.bytes));
    return run;
}

// Runs a constant input for `frames` PCM frames and returns the byte stream.
std::vector<uint8_t> RunDc(pulsr::SdmModulator& sdm, double dc, int frames, int multiple,
                           float* peakState) {
    std::vector<uint8_t> bytes(static_cast<size_t>(frames) * multiple / 8, 0);
    std::vector<uint8_t> sink(bytes.size(), 0);
    std::vector<float> l(4096), r(4096);
    int done = 0;
    int written = 0;
    while (done < frames) {
        const int n = std::min(int(l.size()), frames - done);
        std::fill(l.begin(), l.begin() + n, float(dc));
        std::fill(r.begin(), r.begin() + n, float(-dc));
        const float* pin[2] = {l.data(), r.data()};
        const int w = sdm.process(pin, n, bytes.data() + written, sink.data() + written,
                                  int(bytes.size()) - written);
        if (w < 0) {
            std::printf("  FAIL DC block rejected\n");
            ++gFailures;
            break;
        }
        written += w;
        done += n;
    }
    if (peakState != nullptr) *peakState = sdm.peakStateMagnitude();
    bytes.resize(static_cast<size_t>(written));
    return bytes;
}

void TestConfiguration() {
    std::printf("[TEST] configuration domain\n");
    pulsr::SdmModulator sdm;
    Check(!sdm.isConfigured(), "starts unconfigured");
    Check(!sdm.configure(44100.0, 64, 0), "order 0 rejected");
    Check(!sdm.configure(44100.0, 64, 6), "order 6 rejected");
    Check(!sdm.configure(44100.0, 32, 4), "DSD32 rejected");
    Check(!sdm.configure(44100.0, 512, 4), "DSD512 multiple rejected");
    Check(!sdm.configure(32000.0, 64, 4), "32 kHz rejected");
    Check(!sdm.configure(44100.0 * 3.0, 64, 4), "3x rate rejected");
    Check(!sdm.configure(768000.0, 256, 4), "DSD rate above DSD512 rejected");
    for (int multiple : {64, 128, 256}) {
        for (int order : {2, 4, 5}) {
            pulsr::SdmModulator m;
            if (!m.configure(44100.0, multiple, order)) {
                std::printf("  FAIL configure(44100, %d, %d)\n", multiple, order);
                ++gFailures;
            }
            Check(m.dsdRate() == 44100.0 * multiple, "dsdRate = pcmRate * multiple");
            Check(m.order() == order, "order reported");
        }
    }
    Check(sdm.configure(48000.0, 64, 4), "48 kHz family accepted");
    Check(std::abs(sdm.dsdRate() - 3072000.0) < 1e-6, "48 kHz DSD64 = 3.072 MHz");
    Check(sdm.configure(96000.0, 128, 4), "96 kHz DSD128 accepted");
    Check(sdm.configure(44100.0, 256, 4), "44.1 kHz DSD256 accepted");
    std::printf("  OK order 2/4/5 x DSD64/128/256 accepted, out-of-domain values rejected\n");
}

void TestBitOrderAgainstReference() {
    std::printf("[TEST] bit order and packing vs hand-written reference chain\n");
    const double fs = 44100.0;
    const int multiple = 64;
    const int frames = 5000;
    std::vector<float> l(static_cast<size_t>(frames)), r(static_cast<size_t>(frames));
    for (int n = 0; n < frames; ++n) {
        l[size_t(n)] = 0.9f * std::sin(0.021f * float(n));
        r[size_t(n)] = -0.6f * std::sin(0.0043f * float(n) + 1.0f);
    }

    pulsr::SdmModulator sdm;
    Check(sdm.configure(fs, multiple, 4), "configure for packing test");
    const int expectedBytes = frames * multiple / 8;
    std::vector<uint8_t> gotL(static_cast<size_t>(expectedBytes), 0xEE);
    std::vector<uint8_t> gotR(static_cast<size_t>(expectedBytes), 0xEE);
    const float* pin[2] = {l.data(), r.data()};
    const int written = sdm.process(pin, frames, gotL.data(), gotR.data(), expectedBytes);
    Check(written == expectedBytes, "bytes written = frames * dsdMultiple / 8");
    std::printf("  %d PCM frames -> %d bytes/channel (%d bits), pending %d\n", frames, written,
                written * 8, sdm.pendingBits());
    Check(sdm.pendingBits() == 0, "dsdMultiple is a byte multiple, so no partial byte");

    // Reference chain: the same documented 8x pre-interpolation (the Oversampler is
    // independently tested) followed by the documented loop and a hand packer.
    pulsr::Oversampler up;
    Check(up.configure(2, pulsr::SdmModulator::kPreFactor, pulsr::OversampleKernel::Sharp),
          "reference upsampler configured");
    const int upFrames = frames * pulsr::SdmModulator::kPreFactor;
    std::vector<float> upL(static_cast<size_t>(upFrames), 0.0f);
    std::vector<float> upR(static_cast<size_t>(upFrames), 0.0f);
    const float* upIn[2] = {l.data(), r.data()};
    float* upOut[2] = {upL.data(), upR.data()};
    Check(up.process(upIn, upOut, frames) == upFrames, "reference upsampler frame count");

    ReferenceLoop refL;
    ReferenceLoop refR;
    std::vector<int> bitsL, bitsR;
    bitsL.reserve(static_cast<size_t>(expectedBytes) * 8);
    bitsR.reserve(static_cast<size_t>(expectedBytes) * 8);
    const int zoh = multiple / pulsr::SdmModulator::kPreFactor;
    for (int u = 0; u < upFrames; ++u) {
        for (int rep = 0; rep < zoh; ++rep) {
            bitsL.push_back(refL.next(upL[size_t(u)]));
            bitsR.push_back(refR.next(upR[size_t(u)]));
        }
    }
    const std::vector<uint8_t> wantL = ReferencePack(bitsL);
    const std::vector<uint8_t> wantR = ReferencePack(bitsR);
    const bool matchL = std::memcmp(gotL.data(), wantL.data(), size_t(expectedBytes)) == 0;
    const bool matchR = std::memcmp(gotR.data(), wantR.data(), size_t(expectedBytes)) == 0;
    if (!matchL || !matchR) {
        std::printf("  FAIL byte stream differs from the reference chain (L=%d R=%d)\n",
                    int(matchL), int(matchR));
        for (int i = 0; i < std::min(8, expectedBytes); ++i) {
            std::printf("    byte %d got %02X/%02X want %02X/%02X\n", i, gotL[size_t(i)],
                        gotR[size_t(i)], wantL[size_t(i)], wantR[size_t(i)]);
        }
        ++gFailures;
    } else {
        std::printf("  OK %d bytes/channel match the reference loop bit-for-bit (LSB first)\n",
                    expectedBytes);
    }

    // Bit significance: the packer must place the first sample in bit 0. The
    // reference packer does that by construction, so agreement pins the order; state
    // it explicitly as well.
    Check(((gotL[0] >> 0) & 1) == (bitsL.empty() ? 0 : bitsL[0]), "bit 0 of byte 0 is sample 0");
    std::printf("  first sample -> bit 0 of byte 0 (%d)\n", (gotL[0] >> 0) & 1);

    // Clean rejection paths.
    pulsr::SdmModulator guarded;
    Check(guarded.configure(fs, multiple, 4), "configure capacity guard test");
    std::vector<uint8_t> tiny(static_cast<size_t>(expectedBytes) - 1, 0xA5);
    std::vector<uint8_t> sink(static_cast<size_t>(expectedBytes), 0xA5);
    Check(guarded.process(pin, frames, tiny.data(), sink.data(), int(tiny.size())) == -1,
          "one byte short rejected");
    bool untouched = true;
    for (uint8_t v : tiny) untouched = untouched && (v == 0xA5);
    Check(untouched, "rejected call wrote nothing");
}

void TestToneSnr() {
    std::printf("[TEST] 1 kHz at -1 dBFS for 2 s: bounded output and in-band SNR\n");
    const double fs = 44100.0;
    const double amplitude = std::pow(10.0, -1.0 / 20.0);
    struct Case {
        int order;
        int multiple;
    };
    for (Case c : {Case{4, 64}, Case{2, 64}, Case{5, 64}, Case{4, 256}}) {
        pulsr::SdmModulator sdm;
        if (!sdm.configure(fs, c.multiple, c.order)) {
            std::printf("  FAIL configure(%d, %d)\n", c.multiple, c.order);
            ++gFailures;
            continue;
        }
        const ToneRun run = RunTone(sdm, fs, 1000.0, amplitude, 2.0, 4096, c.multiple);
        const int expectedBytes = int(std::lround(fs * 2.0)) * c.multiple / 8;
        if (run.bytes != expectedBytes) {
            std::printf("  FAIL order %d DSD%d: %d bytes, want %d\n", c.order, c.multiple, run.bytes,
                        expectedBytes);
            ++gFailures;
        }
        const int runL = LongestRun(run.left);
        const double density = OnesDensity(run.left);
        double toneAmp = 0.0;
        const double snr = MeasureSnrDb(run.left, fs * c.multiple, 1000.0, 65536, &toneAmp);
        std::printf("  order %d DSD%-3d: %d bytes, peak state %.3f, density %.4f, longest run %d "
                    "bits, tone %.4f, SNR %.1f dB\n",
                    c.order, c.multiple, run.bytes, double(run.peakState), density, runL, toneAmp,
                    snr);
        Check(run.peakState <= pulsr::SdmModulator::kStateClamp, "integrator states stayed clamped");
        Check(run.peakState < 2.0f, "integrator states stayed in the linear range");
        if (runL > pulsr::SdmModulator::kMaxSaturationRunBits) {
            std::printf("  FAIL order %d: %d identical bits in a row (limit %d)\n", c.order, runL,
                        pulsr::SdmModulator::kMaxSaturationRunBits);
            ++gFailures;
        }
        Check(density > 0.47 && density < 0.53, "AC-coupled tone keeps ~50% density");
        // The bitstream carries the PCM amplitude scaled by the 6 dB DSD headroom.
        Check(std::abs(toneAmp - amplitude * pulsr::SdmModulator::kInputHeadroom) < 0.02,
              "tone amplitude preserved through the documented headroom mapping");
        if (c.order == 4 && c.multiple == 64) {
            Check(snr >= 60.0, "DSD64 order-4 in-band SNR >= 60 dB");
        }
        Check(snr > 55.0, "SNR is plausible for the order");
    }
}

void TestDcAndDensity() {
    std::printf("[TEST] DC input density and full-scale bounds\n");
    const double fs = 44100.0;
    // density = 0.5 + 0.5 * headroom * dc, with headroom = 0.5.
    struct Case {
        double dc;
        double lo;
        double hi;
    };
    const Case cases[] = {{0.0, 0.48, 0.52},   {0.5, 0.615, 0.635}, {-0.5, 0.365, 0.385},
                          {1.0, 0.73, 0.77},   {-1.0, 0.23, 0.27}};
    for (int order : {2, 4, 5}) {
        for (const Case& c : cases) {
            pulsr::SdmModulator sdm;
            Check(sdm.configure(fs, 64, order), "configure DC test");
            float peak = 0.0f;
            const std::vector<uint8_t> bytes = RunDc(sdm, c.dc, int(fs) / 4, 64, &peak);
            const double density = OnesDensity(bytes);
            std::printf("  order %d DC %+.2f: density %.4f (want %.3f..%.3f), peak state %.3f\n",
                        order, c.dc, density, c.lo, c.hi, double(peak));
            if (!(density >= c.lo && density <= c.hi)) {
                std::printf("  FAIL order %d DC %+.2f density %.4f outside [%.3f, %.3f]\n", order,
                            c.dc, density, c.lo, c.hi);
                ++gFailures;
            }
            Check(peak <= pulsr::SdmModulator::kStateClamp, "DC input kept integrators bounded");
        }
    }
}

void TestCapacityAndReset() {
    std::printf("[TEST] capacity rejection and reset()\n");
    const double fs = 44100.0;
    const int multiple = 64;
    pulsr::SdmModulator sdm;
    Check(sdm.configure(fs, multiple, 4), "configure capacity test");
    const int frames = 1024;
    const int bytes = frames * multiple / 8;
    std::vector<float> l(static_cast<size_t>(frames), 0.3f), r(static_cast<size_t>(frames), -0.3f);
    const float* pin[2] = {l.data(), r.data()};

    std::vector<uint8_t> smallL(static_cast<size_t>(bytes) - 1, 0xA5);
    std::vector<uint8_t> smallR(static_cast<size_t>(bytes) - 1, 0xA5);
    const int rejected = sdm.process(pin, frames, smallL.data(), smallR.data(), int(smallL.size()));
    std::printf("  short capacity -> %d (needed %d bytes)\n", rejected, bytes);
    Check(rejected == -1, "insufficient capacity rejected");
    bool untouched = true;
    for (uint8_t v : smallL) untouched = untouched && (v == 0xA5);
    for (uint8_t v : smallR) untouched = untouched && (v == 0xA5);
    Check(untouched, "rejected call wrote nothing");
    Check(sdm.pendingBits() == 0, "rejected call did not consume bits");

    std::vector<uint8_t> goodL(static_cast<size_t>(bytes), 0), goodR(static_cast<size_t>(bytes), 0);
    Check(sdm.process(pin, frames, goodL.data(), goodR.data(), bytes) == bytes,
          "exact capacity accepted");
    pulsr::SdmModulator fresh;
    Check(fresh.configure(fs, multiple, 4), "configure fresh run");
    std::vector<uint8_t> freshL(static_cast<size_t>(bytes), 0), freshR(static_cast<size_t>(bytes), 0);
    Check(fresh.process(pin, frames, freshL.data(), freshR.data(), bytes) == bytes,
          "fresh run accepted");
    Check(std::memcmp(goodL.data(), freshL.data(), size_t(bytes)) == 0,
          "rejected call left no side effects");
    Check(std::memcmp(goodR.data(), freshR.data(), size_t(bytes)) == 0,
          "rejected call left no side effects (R)");

    // reset() must restore the idle pattern: after a loud DC burst, silence again
    // means ~50 % density and no long runs.
    const int burstFrames = 2048;
    std::vector<float> loud(static_cast<size_t>(burstFrames), 0.95f);
    std::vector<uint8_t> burstL(static_cast<size_t>(burstFrames) * multiple / 8, 0);
    std::vector<uint8_t> burstR(burstL.size(), 0);
    const float* pburst[2] = {loud.data(), loud.data()};
    Check(sdm.process(pburst, burstFrames, burstL.data(), burstR.data(), int(burstL.size())) ==
              int(burstL.size()),
          "burst processed");
    sdm.reset();
    Check(sdm.pendingBits() == 0, "reset clears the partial byte");
    Check(sdm.peakStateMagnitude() == 0.0f, "reset clears the peak-state telemetry");
    const int silenceFrames = int(fs) / 4;
    std::vector<float> zero(static_cast<size_t>(silenceFrames), 0.0f);
    const float* pzero[2] = {zero.data(), zero.data()};
    std::vector<uint8_t> silence(static_cast<size_t>(silenceFrames) * multiple / 8, 0);
    std::vector<uint8_t> silenceR(silence.size(), 0);
    Check(sdm.process(pzero, silenceFrames, silence.data(), silenceR.data(), int(silence.size())) ==
              int(silence.size()),
          "post-reset silence processed");
    const double density = OnesDensity(silence);
    const int run = LongestRun(silence);
    std::printf("  after reset: density %.4f, longest run %d bits, peak state %.3f\n", density, run,
                double(sdm.peakStateMagnitude()));
    Check(density > 0.45 && density < 0.55, "reset() restores the 50% idle pattern");
    Check(run <= pulsr::SdmModulator::kMaxSaturationRunBits, "idle pattern has no long runs");

    Check(sdm.process(nullptr, 8, goodL.data(), goodR.data(), bytes) == -1, "null input rejected");
    Check(sdm.process(pin, 8, nullptr, goodR.data(), bytes) == -1, "null left output rejected");
    Check(sdm.process(pin, -1, goodL.data(), goodR.data(), bytes) == -1, "negative frames rejected");
    sdm.release();
    Check(!sdm.isConfigured(), "release disables the modulator");
    Check(sdm.process(pin, 8, goodL.data(), goodR.data(), bytes) == -1, "process after release fails");
}

}  // namespace

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("[TEST] Running SdmModulator tests...\n");
    TestConfiguration();
    TestBitOrderAgainstReference();
    TestToneSnr();
    TestDcAndDensity();
    TestCapacityAndReset();

    if (gFailures == 0) {
        std::printf("[TEST] SdmModulator: all checks passed.\n");
        return 0;
    }
    std::printf("[TEST] SdmModulator: %d failure(s).\n", gFailures);
    return 1;
}
