// android/app/src/test/cpp/test_usb_gap_fader.cpp
//
// The gap fader has one obligation: never introduce a step. It also must be
// completely inert during normal, non-underrunning playback, because otherwise
// it would be requantizing audio that never needed it.
#include "../../main/cpp/UsbGapFader.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

using pulsr::SinkDitherState;
using pulsr::UsbGapFader;

namespace {
int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

int16_t read16(const uint8_t* p) {
    return static_cast<int16_t>(static_cast<uint16_t>(p[0]) |
                                (static_cast<uint16_t>(p[1]) << 8));
}

void write16(uint8_t* p, int16_t v) {
    const uint16_t u = static_cast<uint16_t>(v);
    p[0] = static_cast<uint8_t>(u & 0xFF);
    p[1] = static_cast<uint8_t>((u >> 8) & 0xFF);
}

// Builds `frames` stereo int16 frames of a constant sample.
std::vector<uint8_t> constantFrames(int frames, int16_t value) {
    std::vector<uint8_t> buf(static_cast<size_t>(frames) * 4);
    for (int f = 0; f < frames; ++f) {
        write16(&buf[static_cast<size_t>(f) * 4], value);
        write16(&buf[static_cast<size_t>(f) * 4 + 2], value);
    }
    return buf;
}
int64_t readPacked(const uint8_t* p, int bytes) {
    uint32_t raw = 0;
    for (int b = 0; b < bytes; ++b) raw |= static_cast<uint32_t>(p[b]) << (8 * b);
    return raw & (uint32_t{1} << (bytes * 8 - 1))
        ? static_cast<int64_t>(raw) - (int64_t{1} << (bytes * 8)) : raw;
}

void writePacked(uint8_t* p, int bytes, int64_t value) {
    const auto raw = static_cast<uint32_t>(value);
    for (int b = 0; b < bytes; ++b) p[b] = static_cast<uint8_t>(raw >> (8 * b));
}

std::vector<uint8_t> packedSignal(int frames, int channels, int bytes, int polarity) {
    std::vector<uint8_t> data(static_cast<size_t>(frames) * channels * bytes);
    const int64_t full = int64_t{1} << (bytes * 8 - 1);
    for (int f = 0; f < frames; ++f) {
        for (int c = 0; c < channels; ++c) {
            // Distinct channels, both polarities, low bits not representable in
            // float32 for int32; this catches unwanted healthy float roundtrips.
            const int64_t sample = (full * (c + 2) / 12 + 7) *
                                   (c % 2 ? -polarity : polarity);
            writePacked(data.data() + (static_cast<size_t>(f) * channels + c) * bytes,
                        bytes, sample);
        }
    }
    return data;
}

}  // namespace

int main() {
    std::cout << "[TEST] USB gap fader..." << std::endl;

    constexpr int kRate = 48000;
    SinkDitherState st{};

    // ---- Inert while the ring has data ----------------------------------
    {
        UsbGapFader fader;
        fader.configure(kRate, 2, 2);
        check(fader.fadeSamples() == 96, "2 ms fade window at 48 kHz");

        const auto src = constantFrames(500, 12000);
        auto copy = src;
        fader.applyReal(copy.data(), 500, st);
        check(copy == src, "steady-state frames must pass through byte-identical");
        check(!fader.recovering() && fader.envelope() == 1.0,
              "the envelope stays at unity without an underrun");
    }

    // ---- Ride-down: no step, monotonic, reaches true silence --------------
    {
        UsbGapFader fader;
        fader.configure(kRate, 2, 2);
        auto loud = constantFrames(10, 20000);
        fader.applyReal(loud.data(), 10, st);

        constexpr int kGap = 400;
        std::vector<uint8_t> gap(static_cast<size_t>(kGap) * 4, 0xAB);
        fader.fillGap(gap.data(), kGap, st);

        const int first = std::abs(read16(&gap[0]));
        check(first >= 19000 && first <= 20100,
              "the first gap frame continues from the last emitted sample");

        bool monotonic = true;
        int previous = first;
        for (int f = 1; f < kGap; ++f) {
            const int v = std::abs(read16(&gap[static_cast<size_t>(f) * 4]));
            if (v > previous + 1) {  // +1 for dither LSB jitter
                monotonic = false;
                break;
            }
            previous = v;
        }
        check(monotonic, "the gap decays monotonically, never overshoots");
        check(previous == 0, "a 400-frame gap ends in exact silence");

        // Tail must be bit-exact zero, not a denormal trickle.
        bool tailAllZero = true;
        for (int f = kGap - 50; f < kGap; ++f) {
            for (int b = 0; b < 4; ++b) {
                if (gap[static_cast<size_t>(f) * 4 + b] != 0) tailAllZero = false;
            }
        }
        check(tailAllZero, "the silent tail is written as zeros, both channels");
        check(fader.envelope() == 0.0, "the envelope settles at absolute silence");
    }

    // ---- Ride-up: resumes from wherever the decay reached -----------------
    {
        UsbGapFader fader;
        fader.configure(kRate, 2, 2);
        auto loud = constantFrames(10, 20000);
        fader.applyReal(loud.data(), 10, st);

        // A gap far shorter than the fade window.
        std::vector<uint8_t> shortGap(4 * 4, 0);
        fader.fillGap(shortGap.data(), 4, st);
        check(fader.envelope() > 0.7,
              "a 4-frame gap must not reset the envelope to silence");

        auto incoming = constantFrames(600, 20000);
        auto scaled = incoming;
        fader.applyReal(scaled.data(), 600, st);

        const int start = std::abs(read16(&scaled[0]));
        check(start < 20000 && start > 10000,
              "resumed audio fades in from the decayed level, not from full");
        const int end = std::abs(read16(
            &scaled[static_cast<size_t>(599) * 4]));
        check(end == 20000, "the ramp completes and leaves the signal at full");
        check(!fader.recovering(), "the envelope is back at unity");

        // No jump at the boundary: the resumed frame continues the same decay
        // step the gap had reached, then turns around and rises. Anything
        // larger than one decay increment would be a step again.
        const int lastGap = std::abs(read16(&shortGap[12]));
        check(start <= lastGap && start > static_cast<int>(lastGap * 0.90),
              "crossing from gap to audio continues the envelope, no jump");
    }

    // ---- The fade completes across packet boundaries ---------------------
    {
        UsbGapFader fader;
        fader.configure(kRate, 2, 2);
        auto loud = constantFrames(8, 20000);
        fader.applyReal(loud.data(), 8, st);
        std::vector<uint8_t> gap(96 * 4, 0);
        fader.fillGap(gap.data(), 96, st);  // exactly one fade window
        const double afterWindow = fader.envelope();
        check(afterWindow == 0.0,
              "one bounded fade window must reach exact silence");

        auto incoming = constantFrames(48, 20000);
        auto part = incoming;
        fader.applyReal(part.data(), 48, st);  // half a window
        check(fader.recovering(),
              "a partial ramp must keep ramping in the next packet");
        auto rest = incoming;
        fader.applyReal(rest.data(), 48, st);
        check(!fader.recovering(), "the ramp finishes inside the second packet");
        // The decisive property: once recovered, packets are not touched at all,
        // so steady-state audio is never requantized by this stage.
        auto third = incoming;
        const auto thirdBefore = incoming;
        fader.applyReal(third.data(), 48, st);
        check(third == thirdBefore, "packets after recovery are byte-identical");
    }

    // ---- 24-bit containers round-trip ------------------------------------
    {
        UsbGapFader fader;
        fader.configure(96000, 2, 3);
        std::vector<uint8_t> frames(2 * 6, 0);
        const int32_t value = 4000000;  // ~ -6.5 dBFS in 24-bit
        for (int f = 0; f < 2; ++f) {
            for (int c = 0; c < 2; ++c) {
                uint8_t* p = &frames[static_cast<size_t>(f) * 6 + c * 3];
                p[0] = static_cast<uint8_t>(value & 0xFF);
                p[1] = static_cast<uint8_t>((value >> 8) & 0xFF);
                p[2] = static_cast<uint8_t>((value >> 16) & 0xFF);
            }
        }
        const auto before = frames;
        fader.applyReal(frames.data(), 2, st);
        check(frames == before, "24-bit steady state is also byte-identical");

        // 96 kHz fades per-sample, so reaching the silence floor takes longer in
        // frames than at 48 kHz: 800 frames is ~8 ms.
        std::vector<uint8_t> gap(6 * 800, 0xAA);
        fader.fillGap(gap.data(), 800, st);
        const int32_t firstRaw = static_cast<int32_t>(gap[0]) |
                                 (static_cast<int32_t>(gap[1]) << 8) |
                                 (static_cast<int32_t>(static_cast<int8_t>(gap[2])) << 16);
        check(firstRaw > 3700000 && firstRaw <= 4000000,
              "24-bit gap starts from the emitted level");
        check(gap[static_cast<size_t>(799) * 6] == 0 &&
                  gap[static_cast<size_t>(799) * 6 + 5] == 0,
              "24-bit gap ends in silence on both channels");
    }

    // Opposite-polarity resume and interrupted recovery in every packed depth.
    // For a constant signal the added step is bounded by the span/window plus
    // <= 3 LSB quantizer jitter, not a full-scale discontinuity.
    for (int bytes : {2, 3, 4}) {
        for (int channels : {1, 2, 6, 8}) {
            for (int gapFrames : {1, 4, 95, 400}) {
                UsbGapFader fader;
                fader.configure(kRate, channels, bytes);
                const int window = fader.fadeSamples();
                const int frameBytes = channels * bytes;
                auto healthy = packedSignal(10, channels, bytes, 1);
                const auto original = healthy;
                const auto beforeDither = st;
                fader.applyReal(healthy.data(), 10, st);
                check(healthy == original, "healthy packed PCM must be byte-identical at 16/24/32 bits");
                check(st.s1 == beforeDither.s1 && st.s2 == beforeDither.s2,
                      "healthy packets must not consume dither state");
                std::vector<uint8_t> gap(static_cast<size_t>(gapFrames) * frameBytes);
                fader.fillGap(gap.data(), gapFrames, st);
                check(fader.recovering(), "every gap must require non-bit-perfect recovery");
                for (int c = 0; c < channels; ++c) {
                    const int64_t prior = readPacked(original.data() + 9 * frameBytes + c * bytes, bytes);
                    check(readPacked(gap.data() + c * bytes, bytes) == prior,
                          "first gap sample must exactly continue last healthy packed sample");
                    const double bound = std::abs(static_cast<double>(prior)) / (window - 1) + 3.0;
                    int64_t previous = prior;
                    for (int f = 0; f < gapFrames; ++f) {
                        const int64_t v = readPacked(gap.data() + static_cast<size_t>(f) * frameBytes + c * bytes, bytes);
                        check(std::abs(static_cast<double>(v - previous)) <= bound,
                              "gap first-difference must be bounded by fade-window slope");
                        previous = v;
                    }
                }
                const int resumedFrames = window / 3;
                auto resume = packedSignal(resumedFrames, channels, bytes, -1);
                const auto real = resume;
                fader.applyReal(resume.data(), resumedFrames, st);
                for (int c = 0; c < channels; ++c) {
                    const int64_t lastGap = readPacked(gap.data() + static_cast<size_t>(gapFrames - 1) * frameBytes + c * bytes, bytes);
                    const int64_t target = readPacked(real.data() + c * bytes, bytes);
                    check(readPacked(resume.data() + c * bytes, bytes) == lastGap,
                          "opposite-sign recovery must exactly continue the last emitted gap frame");
                    const double bound = std::abs(static_cast<double>(target - lastGap)) / (window - 1) + 3.0;
                    int64_t previous = lastGap;
                    for (int f = 0; f < resumedFrames; ++f) {
                        const int64_t v = readPacked(resume.data() + static_cast<size_t>(f) * frameBytes + c * bytes, bytes);
                        check(std::abs(static_cast<double>(v - previous)) <= bound,
                              "recovery first-difference must follow bounded crossfade slope");
                        previous = v;
                    }
                }
                // Interrupt a partial recovery with another short gap. Its
                // first frame must use emitted output, not old envelope*output.
                std::vector<uint8_t> secondGap(3 * frameBytes);
                fader.fillGap(secondGap.data(), 3, st);
                for (int c = 0; c < channels; ++c) {
                    check(readPacked(secondGap.data() + c * bytes, bytes) ==
                          readPacked(resume.data() + static_cast<size_t>(resumedFrames - 1) * frameBytes + c * bytes, bytes),
                          "repeated gap must never double-attenuate the remembered emitted sample");
                }
                auto finalResume = packedSignal(window + 20, channels, bytes, 1);
                const auto finalInput = finalResume;
                fader.applyReal(finalResume.data(), window + 20, st);
                for (int c = 0; c < channels; ++c) {
                    const int64_t base = readPacked(secondGap.data() + 2 * frameBytes + c * bytes, bytes);
                    const int64_t target = readPacked(finalInput.data() + c * bytes, bytes);
                    const double bound = std::abs(static_cast<double>(target - base)) / (window - 1) + 3.0;
                    int64_t previous = base;
                    for (int f = 0; f < window + 20; ++f) {
                        const int64_t v = readPacked(finalResume.data() + static_cast<size_t>(f) * frameBytes + c * bytes, bytes);
                        check(std::abs(static_cast<double>(v - previous)) <= bound,
                              "repeated recovery and return to healthy bytes must remain continuous");
                        previous = v;
                    }
                }
                check(!fader.recovering(), "recovery must complete in one bounded window");
                check(std::equal(finalResume.begin() + (window - 1) * frameBytes,
                                 finalResume.end(), finalInput.begin() + (window - 1) * frameBytes),
                      "completed crossfade must preserve the final endpoint and healthy bytes exactly");
            }
        }
        // Splitting an uninterrupted gap/recovery over USB packet boundaries
        // must not restart its base/envelope or change any samples.
        UsbGapFader whole, split;
        whole.configure(kRate, 6, bytes);
        split.configure(kRate, 6, bytes);
        auto healthy = packedSignal(1, 6, bytes, 1);
        SinkDitherState a{}, b{};
        whole.applyReal(healthy.data(), 1, a);
        split.applyReal(healthy.data(), 1, b);
        const int frameBytes = 6 * bytes;
        std::vector<uint8_t> one(40 * frameBytes), two(one.size());
        whole.fillGap(one.data(), 40, a);
        split.fillGap(two.data(), 7, b);
        split.fillGap(two.data() + 7 * frameBytes, 33, b);
        check(one == two, "gap packet partitions must preserve emitted samples exactly");
        auto realA = packedSignal(200, 6, bytes, -1), realB = realA;
        whole.applyReal(realA.data(), 200, a);
        split.applyReal(realB.data(), 11, b);
        split.applyReal(realB.data() + 11 * frameBytes, 189, b);
        check(realA == realB, "recovery packet partitions must preserve emitted samples exactly");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " USB gap fader check(s) failed."
                  << std::endl;
        return 1;
    }
    std::cout << "[PASS] gap fill fades instead of stepping, and is inert otherwise."
              << std::endl;
    return 0;
}
