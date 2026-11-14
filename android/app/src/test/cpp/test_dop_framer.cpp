// android/app/src/test/cpp/test_dop_framer.cpp
#include "../../main/cpp/DopFramer.h"
#include <iostream>
#include <vector>
#include <cstring>

namespace {

bool ExpectBytes(const std::vector<uint8_t>& got,
                 const std::vector<uint8_t>& want, const char* what) {
    if (got.size() != want.size() ||
        std::memcmp(got.data(), want.data(), want.size()) != 0) {
        std::cout << "  FAIL " << what << ": size=" << got.size() << " [";
        for (auto b : got) std::cout << std::hex << (int)b << ' ';
        std::cout << "] want [";
        for (auto b : want) std::cout << std::hex << (int)b << ' ';
        std::cout << ']' << std::dec << std::endl;
        return false;
    }
    return true;
}

}  // namespace

extern "C" {
uint8_t* pulsr_dop_alloc(size_t bytes);
void pulsr_dop_free(uint8_t* ptr);
int32_t pulsr_dop_pcm_sample_rate(int32_t dsd_rate);
int32_t pulsr_dop_frame_planar(
    const uint8_t* dsd_left, const uint8_t* dsd_right,
    size_t channel_bytes, int32_t container_bits, int32_t reverse_bits,
    uint8_t first_marker, uint8_t* out_buf, size_t out_capacity,
    size_t* out_bytes, uint8_t* next_marker);
}

int main() {
    std::cout << "[TEST] Running DoP Framer Tests..." << std::endl;
    int failures = 0;

    // 1. Basic framing: one stereo frame. DoP v1.1 word (LE) = [newer, older,
    //    marker], so [L_newer,L_older,0x05,R_newer,R_older,0x05].
    {
        const uint8_t in[4] = {0xAA, 0xBB, 0xCC, 0xDD};
        std::vector<uint8_t> out(6, 0);
        size_t n = 0;
        const bool ok = pulsr::FrameDopInterleaved(in, 4, out.data(), out.size(), &n);
        if (!ok || n != 6) {
            std::cout << "  FAIL basic framing returned ok=" << ok << " n=" << n << std::endl;
            ++failures;
        } else if (!ExpectBytes(out, {0xBB, 0xAA, 0x05, 0xDD, 0xCC, 0x05}, "basic frame")) {
            ++failures;
        } else {
            std::cout << "  OK basic framing produces [Lnew,Lold,mk,Rnew,Rold,mk]" << std::endl;
        }
    }

    // 2. Marker alternation across two frames: 0x05 then 0xFA
    {
        const uint8_t in[8] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};
        std::vector<uint8_t> out(12, 0);
        size_t n = 0;
        const bool ok = pulsr::FrameDopInterleaved(in, 8, out.data(), out.size(), &n);
        const std::vector<uint8_t> want = {
            0x02, 0x01, 0x05, 0x04, 0x03, 0x05,
            0x06, 0x05, 0xFA, 0x08, 0x07, 0xFA,
        };
        if (!ok || !ExpectBytes(out, want, "marker alternation")) {
            ++failures;
        } else {
            std::cout << "  OK markers alternate 0x05/0xFA per frame" << std::endl;
        }
    }

    // 3. firstMarker continuation: starting from 0xFA flips the sequence.
    {
        const uint8_t in[4] = {0x11, 0x22, 0x33, 0x44};
        std::vector<uint8_t> out(6, 0);
        size_t n = 0;
        pulsr::FrameDopInterleaved(in, 4, out.data(), out.size(), &n,
                                   pulsr::kDopMarkerB);
        if (!ExpectBytes(out, {0x22, 0x11, 0xFA, 0x44, 0x33, 0xFA},
                         "firstMarker=0xFA")) {
            ++failures;
        } else {
            std::cout << "  OK firstMarker continuation honoured" << std::endl;
        }
    }

    // 4. Rejects misaligned input (not a multiple of 4).
    {
        const uint8_t in[3] = {0x01, 0x02, 0x03};
        uint8_t out[6];
        size_t n = 99;
        if (pulsr::FrameDopInterleaved(in, 3, out, sizeof(out), &n)) {
            std::cout << "  FAIL misaligned input accepted" << std::endl;
            ++failures;
        } else if (n != 0) {
            std::cout << "  FAIL misaligned input wrote bytes" << std::endl;
            ++failures;
        } else {
            std::cout << "  OK misaligned input rejected without writes" << std::endl;
        }
    }

    // 5. Rejects insufficient output capacity.
    {
        const uint8_t in[8] = {0};
        uint8_t out[6];
        size_t n = 99;
        if (pulsr::FrameDopInterleaved(in, 8, out, sizeof(out), &n)) {
            std::cout << "  FAIL undersized output accepted" << std::endl;
            ++failures;
        } else {
            std::cout << "  OK undersized output buffer rejected" << std::endl;
        }
    }

    // 6. Null arguments rejected.
    {
        uint8_t out[6];
        size_t n = 0;
        const uint8_t in[4] = {0};
        if (pulsr::FrameDopInterleaved(nullptr, 4, out, sizeof(out), &n) ||
            pulsr::FrameDopInterleaved(in, 4, nullptr, sizeof(out), &n) ||
            pulsr::FrameDopInterleaved(in, 4, out, sizeof(out), nullptr)) {
            std::cout << "  FAIL null arguments accepted" << std::endl;
            ++failures;
        } else {
            std::cout << "  OK null arguments rejected" << std::endl;
        }
    }

    // 7. Planar 24-bit and 32-bit framing match DopEncoder byte layout.
    {
        const uint8_t l[4] = {0xAA, 0x55, 0x11, 0x22};
        const uint8_t r[4] = {0x33, 0x44, 0x66, 0x77};
        std::vector<uint8_t> out24(12, 0);
        size_t n24 = 0;
        uint8_t next24 = 0;
        const bool ok24 = pulsr::FrameDopPlanar(
            l, r, 4, 24, false, out24.data(), out24.size(), &n24,
            pulsr::kDopMarkerA, &next24);
        const std::vector<uint8_t> want24 = {
            0x55, 0xAA, 0x05, 0x44, 0x33, 0x05,
            0x22, 0x11, 0xFA, 0x77, 0x66, 0xFA,
        };
        if (!ok24 || n24 != 12 || next24 != pulsr::kDopMarkerA ||
            !ExpectBytes(out24, want24, "planar 24-bit")) {
            ++failures;
        }

        std::vector<uint8_t> out32(16, 0);
        size_t n32 = 0;
        uint8_t next32 = 0;
        const bool ok32 = pulsr::FrameDopPlanar(
            l, r, 4, 32, false, out32.data(), out32.size(), &n32,
            pulsr::kDopMarkerA, &next32);
        const std::vector<uint8_t> want32 = {
            0x00, 0x55, 0xAA, 0x05, 0x00, 0x44, 0x33, 0x05,
            0x00, 0x22, 0x11, 0xFA, 0x00, 0x77, 0x66, 0xFA,
        };
        if (!ok32 || n32 != 16 || next32 != pulsr::kDopMarkerA ||
            !ExpectBytes(out32, want32, "planar 32-bit")) {
            ++failures;
        }
    }

    // 8. Inline bit-reversal (LSB-first DSF -> MSB-first DoP) and chunk continuity.
    {
        // Chunk 1: 1 frame (2 bytes/ch), chunk 2: 1 frame -> markers must alternate 0x05, 0xFA.
        const uint8_t l[4] = {0x80, 0x01, 0xB4, 0x0F}; // reversed: {0x01, 0x80, 0x2D, 0xF0}
        const uint8_t r[4] = {0x02, 0x40, 0xC3, 0x5A}; // reversed: {0x40, 0x02, 0xC3, 0x5A}
        std::vector<uint8_t> full(12, 0);
        size_t nFull = 0;
        pulsr::FrameDopPlanar(l, r, 4, 24, true, full.data(), full.size(), &nFull);

        std::vector<uint8_t> chunked(12, 0);
        size_t n1 = 0, n2 = 0;
        uint8_t mk = pulsr::kDopMarkerA;
        const bool ok1 = pulsr::FrameDopPlanar(
            l, r, 2, 24, true, chunked.data(), 6, &n1, mk, &mk);
        const bool ok2 = pulsr::FrameDopPlanar(
            l + 2, r + 2, 2, 24, true, chunked.data() + 6, 6, &n2, mk, &mk);

        const std::vector<uint8_t> want = {
            0x80, 0x01, 0x05, 0x02, 0x40, 0x05,
            0xF0, 0x2D, 0xFA, 0x5A, 0xC3, 0xFA,
        };
        if (!ok1 || !ok2 || n1 != 6 || n2 != 6 || mk != pulsr::kDopMarkerA ||
            !ExpectBytes(full, want, "reverseBits full") ||
            !ExpectBytes(chunked, want, "reverseBits chunked continuity")) {
            ++failures;
        }
    }

    // 9. Planar validation + empty input + C ABI exports + sample rate math.
    {
        const uint8_t l[4] = {0x11, 0x22, 0x33, 0x44};
        const uint8_t r[4] = {0x55, 0x66, 0x77, 0x88};
        size_t outBytes = 99;
        uint8_t nextMk = 0;
        uint8_t dummy[16];
        if (!pulsr::FrameDopPlanar(nullptr, nullptr, 0, 24, false, nullptr, 0, &outBytes,
                                   pulsr::kDopMarkerB, &nextMk) ||
            outBytes != 0 || nextMk != pulsr::kDopMarkerB) {
            std::cout << "  FAIL planar empty input" << std::endl;
            ++failures;
        }
        if (pulsr::FrameDopPlanar(l, r, 3, 24, false, dummy, sizeof(dummy), &outBytes) ||
            pulsr::FrameDopPlanar(l, r, 4, 16, false, dummy, sizeof(dummy), &outBytes) ||
            pulsr::FrameDopPlanar(l, r, 4, 24, false, dummy, sizeof(dummy), &outBytes, 0x00) ||
            pulsr::FrameDopPlanar(l, r, 4, 24, false, dummy, 11, &outBytes)) {
            std::cout << "  FAIL planar invalid input accepted" << std::endl;
            ++failures;
        }

        if (pulsr_dop_pcm_sample_rate(64) != 176400 ||
            pulsr_dop_pcm_sample_rate(128) != 352800 ||
            pulsr_dop_pcm_sample_rate(256) != 705600 ||
            pulsr_dop_pcm_sample_rate(512) != 0 ||
            pulsr_dop_pcm_sample_rate(0) != 0) {
            std::cout << "  FAIL pulsr_dop_pcm_sample_rate" << std::endl;
            ++failures;
        }

        uint8_t* nl = pulsr_dop_alloc(4);
        uint8_t* nr = pulsr_dop_alloc(4);
        uint8_t* nout = pulsr_dop_alloc(12);
        if (!nl || !nr || !nout) {
            std::cout << "  FAIL pulsr_dop_alloc" << std::endl;
            ++failures;
        } else {
            std::memcpy(nl, l, 4);
            std::memcpy(nr, r, 4);
            size_t cOut = 0;
            uint8_t cNext = 0;
            const int32_t rc = pulsr_dop_frame_planar(
                nl, nr, 4, 24, 0, pulsr::kDopMarkerA, nout, 12, &cOut, &cNext);
            std::vector<uint8_t> got(nout, nout + cOut);
            const std::vector<uint8_t> want = {
                0x22, 0x11, 0x05, 0x66, 0x55, 0x05,
                0x44, 0x33, 0xFA, 0x88, 0x77, 0xFA,
            };
            if (rc != 1 || cOut != 12 || cNext != pulsr::kDopMarkerA ||
                !ExpectBytes(got, want, "C ABI planar")) {
                ++failures;
            }
        }
        pulsr_dop_free(nl);
        pulsr_dop_free(nr);
        pulsr_dop_free(nout);
    }

    if (failures == 0) {
        std::cout << "[TEST] DoP Framer: all checks passed." << std::endl;
        return 0;
    }
    std::cout << "[TEST] DoP Framer: " << failures << " failure(s)." << std::endl;
    return 1;
}
