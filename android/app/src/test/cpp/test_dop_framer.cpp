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

int main() {
    std::cout << "[TEST] Running DoP Framer Tests..." << std::endl;
    int failures = 0;

    // 1. Basic framing: one stereo frame -> [L0,L1,0x05,R0,R1,0x05]
    {
        const uint8_t in[4] = {0xAA, 0xBB, 0xCC, 0xDD};
        std::vector<uint8_t> out(6, 0);
        size_t n = 0;
        const bool ok = pulsr::FrameDopInterleaved(in, 4, out.data(), out.size(), &n);
        if (!ok || n != 6) {
            std::cout << "  FAIL basic framing returned ok=" << ok << " n=" << n << std::endl;
            ++failures;
        } else if (!ExpectBytes(out, {0xAA, 0xBB, 0x05, 0xCC, 0xDD, 0x05}, "basic frame")) {
            ++failures;
        } else {
            std::cout << "  OK basic framing produces [L0,L1,mk,R0,R1,mk]" << std::endl;
        }
    }

    // 2. Marker alternation across two frames: 0x05 then 0xFA
    {
        const uint8_t in[8] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};
        std::vector<uint8_t> out(12, 0);
        size_t n = 0;
        const bool ok = pulsr::FrameDopInterleaved(in, 8, out.data(), out.size(), &n);
        const std::vector<uint8_t> want = {
            0x01, 0x02, 0x05, 0x03, 0x04, 0x05,
            0x05, 0x06, 0xFA, 0x07, 0x08, 0xFA,
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
        if (!ExpectBytes(out, {0x11, 0x22, 0xFA, 0x33, 0x44, 0xFA},
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

    if (failures == 0) {
        std::cout << "[TEST] DoP Framer: all checks passed." << std::endl;
        return 0;
    }
    std::cout << "[TEST] DoP Framer: " << failures << " failure(s)." << std::endl;
    return 1;
}
