// android/app/src/test/cpp/test_dop_silence.cpp
//
// Item 3 regression: DoP underrun silence must be a VALID DoP frame, not zeros.
//
// A DoP word is [payload | marker] with the marker (0x05 / 0xFA) in the MSB and
// the markers alternating once per stereo frame. Zero-filling a gap wipes the
// marker pattern, so a DoP-capable DAC loses marker lock and decodes the gap as
// noise. The helper under test emits zero payload with the correct marker in the
// MSB of every sample and continues the producer's alternation.
#include "../../main/cpp/DopGapSilence.h"

#include <cstdint>
#include <cstdio>
#include <vector>

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::printf("[FAIL] %s\n", what);
        ++gFailures;
    }
}

}  // namespace

int main() {
    std::printf("[TEST] DoP underrun silence byte patterns...\n");

    // ---- 24-in-32 carrier (4-byte subslot, marker in the MSB) --------------
    {
        std::vector<uint8_t> buf(4 * 2 * 4, 0xAA);
        const uint8_t next = pulsr::FillDopSilence(buf.data(), 4, 2, 4, pulsr::kDopMarkerA);
        const std::vector<uint8_t> expected = {
            0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x05,  // frame 0 (L,R) 0x05
            0x00, 0x00, 0x00, 0xFA, 0x00, 0x00, 0x00, 0xFA,  // frame 1      0xFA
            0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x05,  // frame 2      0x05
            0x00, 0x00, 0x00, 0xFA, 0x00, 0x00, 0x00, 0xFA,  // frame 3      0xFA
        };
        check(buf == expected, "24-in-32 silence must be zero payload + alternating marker");
        check(next == pulsr::kDopMarkerA,
              "an even number of frames must leave the phase unchanged");
    }

    // ---- 16-bit carrier ---------------------------------------------------
    {
        std::vector<uint8_t> buf(2 * 2 * 2, 0xAA);
        static_cast<void>(pulsr::FillDopSilence(buf.data(), 2, 2, 2, pulsr::kDopMarkerB));
        const std::vector<uint8_t> expected = {
            0x00, 0xFA, 0x00, 0xFA,  // frame 0 = 0xFA
            0x00, 0x05, 0x00, 0x05,  // frame 1 = 0x05
        };
        check(buf == expected, "16-bit silence must put the marker in the MSB byte");
    }

    // ---- Packed 24-bit carrier -------------------------------------------
    {
        std::vector<uint8_t> buf(3 * 2, 0xAA);
        static_cast<void>(pulsr::FillDopSilence(buf.data(), 1, 2, 3, pulsr::kDopMarkerA));
        const std::vector<uint8_t> expected = {0x00, 0x00, 0x05, 0x00, 0x00, 0x05};
        check(buf == expected, "packed 24-bit silence must be [0,0,marker]");
    }

    // ---- Alternation continuity across packets ---------------------------
    {
        std::vector<uint8_t> first(4 * 2 * 3, 0);
        std::vector<uint8_t> second(4 * 2 * 3, 0);
        uint8_t phase = pulsr::kDopMarkerA;
        phase = pulsr::FillDopSilence(first.data(), 3, 2, 3, phase);  // odd -> flips
        check(phase == pulsr::kDopMarkerB,
              "an odd frame count must hand the flipped marker to the next packet");
        phase = pulsr::FillDopSilence(second.data(), 3, 2, 3, phase);
        check(first[(3 - 1) * 6 + 2] == pulsr::kDopMarkerA &&
                  second[2] == pulsr::kDopMarkerB,
              "markers must keep alternating across a packet boundary");
        check(phase == pulsr::kDopMarkerA, "two odd packets must return to 0x05");
    }

    // ---- Marker phase derived from real frames ---------------------------
    {
        // Two real 24-in-32 frames: 0x05 then 0xFA -> the gap starts at 0x05.
        std::vector<uint8_t> packet = {
            0x11, 0x22, 0x33, 0x05, 0x44, 0x55, 0x66, 0x05,
            0x77, 0x88, 0x99, 0xFA, 0xAA, 0xBB, 0xCC, 0xFA,
        };
        check(pulsr::DopMarkerAfterLastFrame(packet.data(), 2, 2, 4, pulsr::kDopMarkerA) ==
                  pulsr::kDopMarkerA,
              "a 0xFA last frame must hand 0x05 to the gap");
        check(pulsr::DopMarkerAfterLastFrame(packet.data(), 1, 2, 4, pulsr::kDopMarkerB) ==
                  pulsr::kDopMarkerB,
              "a 0x05 last frame must hand 0xFA to the gap");
        // Non-DoP payload (plain PCM) must keep the current phase instead of
        // inventing an alternation.
        std::vector<uint8_t> pcm = {1, 2, 3, 4, 5, 6, 7, 8};
        check(pulsr::DopMarkerAfterLastFrame(pcm.data(), 1, 2, 4, pulsr::kDopMarkerB) ==
                  pulsr::kDopMarkerB,
              "a non-marker MSB must not fabricate a DoP phase");
    }

    // ---- Rejected inputs write nothing ----------------------------------
    {
        std::vector<uint8_t> buf(16, 0x5A);
        const std::vector<uint8_t> untouched = buf;
        check(pulsr::FillDopSilence(buf.data(), 2, 2, 1, pulsr::kDopMarkerA) ==
                  pulsr::kDopMarkerA &&
                  buf == untouched,
              "an unsupported container must be rejected without writing");
        check(pulsr::FillDopSilence(nullptr, 2, 2, 4, pulsr::kDopMarkerA) ==
                  pulsr::kDopMarkerA,
              "a null destination must be rejected");
        check(pulsr::FillDopSilence(buf.data(), 2, 2, 4, 0x7F) == 0x7F && buf == untouched,
              "an invalid marker must be rejected without writing");
    }

    if (gFailures != 0) {
        std::printf("[FAIL] %d DoP silence check(s) failed.\n", gFailures);
        return 1;
    }
    std::printf("[PASS] DoP silence keeps marker phase across containers and packets.\n");
    return 0;
}
