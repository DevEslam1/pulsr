// android/app/src/test/cpp/test_sink_quantizer.cpp
//
// The last quantizer before bytes reach the DAC. Two properties matter and both
// are audible on low-impedance IEMs:
//   * a sample the engine already noise-shaped onto this grid must pass through
//     UNCHANGED, or the shaping is destroyed and the noise floor rises;
//   * a sample that is not on the grid must not be rounded plainly, because that
//     error is signal-correlated and reads as graininess on quiet fades.
#include "../../main/cpp/AAudioSinkSupport.h"
#include "../../main/cpp/SinkQuantizer.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

using namespace pulsr;

namespace {
int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

int32_t decodeI16(const uint8_t* p) {
    const uint32_t raw = static_cast<uint32_t>(p[0]) |
                         (static_cast<uint32_t>(p[1]) << 8);
    return static_cast<int16_t>(raw);
}

int32_t decodeI24(const uint8_t* p) {
    return static_cast<int32_t>(p[0]) |
           (static_cast<int32_t>(p[1]) << 8) |
           (static_cast<int32_t>(static_cast<int8_t>(p[2])) << 16);
}

int32_t decodeI32(const uint8_t* p) {
    uint32_t raw = 0;
    for (int b = 0; b < 4; ++b) raw |= static_cast<uint32_t>(p[b]) << (8 * b);
    return static_cast<int32_t>(raw);
}
}  // namespace

int main() {
    std::cout << "[TEST] sink quantizer..." << std::endl;

    // ---- Already-on-grid samples pass through untouched -------------------
    // This is the contract with the engine's noise-shaped dither: if the packer
    // perturbs these, shaping is being re-quantized away.
    {
        SinkDitherState st{};
        bool exact16 = true;
        for (int32_t k = -32768; k <= 32767; k += 7) {
            const float v = static_cast<float>(k) / 32768.0f;
            uint8_t out[4] = {};
            PackPcmSample(v, out, 2, st);
            if (decodeI16(out) != k) { exact16 = false; break; }
        }
        check(exact16, "16-bit grid values must pack back to the same integer");

        bool exact24 = true;
        for (int32_t k = -8388608; k <= 8388607; k += 4093) {
            const float v = static_cast<float>(k) / 8388608.0f;
            uint8_t out[4] = {};
            PackPcmSample(v, out, 3, st);
            if (decodeI24(out) != k) { exact24 = false; break; }
        }
        check(exact24, "24-bit grid values must pack back to the same integer");

        // Repeating one on-grid value must be bit-identical every time — a
        // dither layer applied here would make it jitter.
        const float v = 0.25f;  // exactly 8192/32768
        uint8_t a[4] = {}, b[4] = {};
        PackPcmSample(v, a, 2, st);
        for (int i = 0; i < 500; ++i) PackPcmSample(v, b, 2, st);
        check(decodeI16(a) == decodeI16(b) && decodeI16(a) == 8192,
              "an on-grid sample must not accumulate dither across calls");
    }

    // ---- Off-grid samples are dithered, and decorrelated ------------------
    {
        SinkDitherState st{};
        // Midpoint between LSB 10000 and 10001: plain rounding would always
        // pick the same one.
        const double mid = 10000.5 / 32768.0;
        int lo = 0, hi = 0, other = 0;
        double sumErr = 0.0;
        constexpr int kN = 20000;
        for (int i = 0; i < kN; ++i) {
            uint8_t out[4] = {};
            PackPcmSample(static_cast<float>(mid), out, 2, st);
            const int32_t q = decodeI16(out);
            if (q == 10000) ++lo;
            else if (q == 10001) ++hi;
            else ++other;
            sumErr += (static_cast<double>(q) - mid * 32768.0);
        }
        check(other == 0, "dither must stay within one LSB of the sample");
        check(lo > 0 && hi > 0, "an off-grid sample must dither both ways");
        // A balanced split is the difference between noise and a tonal artifact.
        const double spread = std::abs(static_cast<double>(lo - hi)) /
                              static_cast<double>(kN);
        check(spread < 0.1, "TPDF must be near-balanced between the neighbours");
        const double meanErr = sumErr / static_cast<double>(kN);
        check(std::abs(meanErr) < 0.1, "mean quantization error must be ~0 LSB");
    }

    // ---- Saturation, non-finite and container edges ----------------------
    {
        SinkDitherState st{};
        uint8_t out[4] = {};

        PackPcmSample(1.0f, out, 2, st);
        check(decodeI16(out) == 32767, "+1.0 saturates to +32767");
        PackPcmSample(4.0f, out, 2, st);
        check(decodeI16(out) == 32767, "above full scale saturates, never wraps");
        PackPcmSample(-1.0f, out, 2, st);
        check(decodeI16(out) == -32768, "-1.0 reaches the negative rail");
        PackPcmSample(-9.0f, out, 2, st);
        check(decodeI16(out) == -32768, "below full scale saturates, never wraps");

        PackPcmSample(std::nan(""), out, 2, st);
        check(decodeI16(out) == 0, "NaN must become silence, not a rail");
        PackPcmSample(HUGE_VALF, out, 3, st);
        check(decodeI24(out) == 0, "infinity must become silence");

        // Little-endian on the wire, pinned explicitly.
        PackPcmSample(-0.5f, out, 2, st);
        check(out[0] == 0x00 && out[1] == 0xC0,
              "16-bit packs little-endian (-16384 = 0xC000)");

        // An unknown subslot size must write nothing rather than 4 junk bytes.
        uint8_t probe[4] = {0xAA, 0xAA, 0xAA, 0xAA};
        check(PackPcmSample(0.5f, probe, 1, st) == 0,
              "1-byte container is refused");
        check(PackPcmSample(0.5f, probe, 5, st) == 0,
              "5-byte container is refused");
        check(PackPcmSample(0.5f, nullptr, 2, st) == 0, "null dst is refused");
        check(probe[0] == 0xAA, "a refused pack must not touch the buffer");
    }

    // ---- 32-bit containers are not dithered ------------------------------
    // float32's own mantissa is the limiting quantizer here; TPDF would add
    // noise below it. Determinism is the observable consequence.
    {
        SinkDitherState st{};
        uint8_t a[4] = {}, b[4] = {};
        PackPcmSample(0.123456f, a, 4, st);
        for (int i = 0; i < 200; ++i) PackPcmSample(0.123456f, b, 4, st);
        check(decodeI32(a) == decodeI32(b),
              "32-bit packing is plain rounding, not dithered");
        check(DitherHelpsAtBits(32) == false && DitherHelpsAtBits(24),
              "dither eligibility follows the mantissa floor");
    }

    // ---- Depth table -----------------------------------------------------
    check(LsbScaleForBits(16) == 32768.0, "16-bit LSB scale is 2^15");
    check(LsbScaleForBits(24) == 8388608.0, "24-bit LSB scale is 2^23");
    check(LsbScaleForBits(32) == 2147483648.0, "32-bit LSB scale is 2^31");
    check(LsbScaleForBits(20) == 0.0, "an unsupported depth reports 0 so the caller refuses");

    // ---- Sink-side volume requantization ---------------------------------
    // Multiplying moves every sample off its grid, so this must dither — except
    // where the product lands back on the grid.
    {
        std::vector<int16_t> buf(4096);
        for (size_t i = 0; i < buf.size(); ++i) {
            buf[i] = static_cast<int16_t>(static_cast<int>(i) - 2048);
        }
        SinkDitherState st{};
        auto unity = buf;
        ApplyI16Volume(unity.data(), static_cast<int32_t>(unity.size()), 1.0f, st);
        check(unity == buf, "unity gain is bit-transparent");

        auto odd = buf;
        for (size_t i = 0; i < odd.size(); ++i) odd[i] = (i % 2) ? 1001 : -1001;
        auto halved = odd;
        ApplyI16Volume(halved.data(), static_cast<int32_t>(halved.size()), 0.5f, st);
        bool stayedNearHalf = true;
        for (size_t i = 0; i < halved.size(); ++i) {
            const int q = halved[i];
            if (q != 500 && q != 501 && q != -500 && q != -501) {
                stayedNearHalf = false;
                break;
            }
        }
        check(stayedNearHalf, "off-grid half-gain products stay within 1 LSB");

        bool jittered = false;
        for (size_t i = 2; i < halved.size(); ++i) {
            if (halved[i] != halved[i - 2]) { jittered = true; break; }
        }
        check(jittered, "identical off-grid samples are dithered, not rounded alike");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " sink quantizer check(s) failed."
                  << std::endl;
        return 1;
    }
    std::cout << "[PASS] sink quantizer behaves as specified." << std::endl;
    return 0;
}
