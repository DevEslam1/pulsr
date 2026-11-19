// android/app/src/test/cpp/test_dsd_native_packer.cpp
//
// Host test for pulsr::PackDsdBitsToWords / WordsForDsdBytes.
// Bit order is verified against hand-computed bit positions, not against the
// implementation's own idea of the layout.
#include "../../main/cpp/DsdNativePacker.h"

#include <cstdint>
#include <cstddef>
#include <initializer_list>
#include <iostream>
#include <vector>

namespace {

int gFailures = 0;

void Check(bool ok, const char* what) {
    if (ok) {
        std::cout << "  OK " << what << std::endl;
        return;
    }
    std::cout << "  FAIL " << what << std::endl;
    ++gFailures;
}

bool ExpectBytes(const uint8_t* got, size_t gotLen,
                 const std::vector<uint8_t>& want, const char* what) {
    if (gotLen != want.size()) {
        std::cout << "  FAIL " << what << ": got " << gotLen << " bytes, want "
                  << want.size() << std::endl;
        return false;
    }
    for (size_t i = 0; i < want.size(); ++i) {
        if (got[i] != want[i]) {
            std::cout << "  FAIL " << what << ": byte " << i << " is 0x" << std::hex
                      << static_cast<int>(got[i]) << ", want 0x"
                      << static_cast<int>(want[i]) << std::dec << std::endl;
            return false;
        }
    }
    return true;
}

}  // namespace

int main() {
    std::cout << "[TEST] Running DSD native packer tests..." << std::endl;

    // ---------------------------------------------------------------------
    // 1. Hand-computed 32-bit words. The first DSD bit is the LSB of word 0,
    //    so a lone bit 0 stays in byte 0 and the last bit of the fourth byte
    //    becomes bit 31 (the top byte of the little-endian word).
    // ---------------------------------------------------------------------
    {
        const uint8_t dsd[8] = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80};
        uint8_t out[8] = {0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC};
        const int written = pulsr::PackDsdBitsToWords(dsd, 8, out, sizeof(out), 4);
        Check(written == 8 && ExpectBytes(out, 8,
                                          {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80},
                                          "two 32-bit words"),
              "32-bit packing keeps DSF bit order (word 0 = 0x00000001, word 1 = 0x80000000)");
    }

    // ---------------------------------------------------------------------
    // 2. Bit-position sweep: a single set DSD bit n must appear at byte n/8,
    //    bit n%8 of the packed stream - for both container widths. This is the
    //    actual LSB-first claim, independent of any byte-copy shortcut.
    // ---------------------------------------------------------------------
    {
        const int positions[] = {0, 1, 6, 7, 8, 9, 15, 16, 23, 24, 31, 32, 33, 63};
        bool ok = true;
        for (const int bit : positions) {
            uint8_t dsd[8] = {0};
            dsd[bit / 8] = static_cast<uint8_t>(1u << (bit % 8));
            uint8_t out[8] = {0};
            const int written = pulsr::PackDsdBitsToWords(dsd, 8, out, sizeof(out), 4);
            if (written != 8) {
                ok = false;
                break;
            }
            for (int byte = 0; byte < 8; ++byte) {
                const uint8_t want =
                    (byte == bit / 8) ? static_cast<uint8_t>(1u << (bit % 8)) : 0u;
                if (out[byte] != want) ok = false;
            }
        }
        Check(ok, "each DSD bit n lands at byte n/8 bit n%8 (32-bit container)");
    }
    {
        bool ok = true;
        for (int bit = 0; bit < 32; ++bit) {
            uint8_t dsd[4] = {0};
            dsd[bit / 8] = static_cast<uint8_t>(1u << (bit % 8));
            uint8_t out[4] = {0};
            if (pulsr::PackDsdBitsToWords(dsd, 4, out, sizeof(out), 2) != 4) {
                ok = false;
                break;
            }
            for (int byte = 0; byte < 4; ++byte) {
                const uint8_t want =
                    (byte == bit / 8) ? static_cast<uint8_t>(1u << (bit % 8)) : 0u;
                if (out[byte] != want) ok = false;
            }
        }
        Check(ok, "each DSD bit n lands at byte n/8 bit n%8 (16-bit container)");
    }

    // ---------------------------------------------------------------------
    // 3. 16-bit containers, whole and partial words.
    // ---------------------------------------------------------------------
    {
        const uint8_t dsd[3] = {0xAA, 0x55, 0x11};
        uint8_t out[4] = {0xCC, 0xCC, 0xCC, 0xCC};
        const int written = pulsr::PackDsdBitsToWords(dsd, 3, out, sizeof(out), 2);
        Check(written == 4 && ExpectBytes(out, 4, {0xAA, 0x55, 0x11, 0x00},
                                          "16-bit partial word"),
              "16-bit container: 3 bytes -> 2 words, high byte zero-padded");
    }
    {
        const uint8_t dsd[1] = {0x80};
        uint8_t out[2] = {0xCC, 0xCC};
        const int written = pulsr::PackDsdBitsToWords(dsd, 1, out, sizeof(out), 2);
        Check(written == 2 && ExpectBytes(out, 2, {0x80, 0x00}, "16-bit single byte"),
              "16-bit container: 1 byte -> 1 word, second byte zero");
    }

    // ---------------------------------------------------------------------
    // 4. 32-bit containers: partial trailing word, alignment.
    // ---------------------------------------------------------------------
    {
        const uint8_t dsd[3] = {0xAA, 0x55, 0x11};
        uint8_t out[4] = {0xCC, 0xCC, 0xCC, 0xCC};
        const int written = pulsr::PackDsdBitsToWords(dsd, 3, out, sizeof(out), 4);
        Check(written == 4 && ExpectBytes(out, 4, {0xAA, 0x55, 0x11, 0x00},
                                          "32-bit partial word"),
              "32-bit container: 3 bytes -> 1 word with a zero fourth byte");
    }
    {
        const uint8_t dsd[5] = {0xAA, 0x55, 0x11, 0x22, 0x7F};
        uint8_t out[8] = {0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC};
        const int written = pulsr::PackDsdBitsToWords(dsd, 5, out, sizeof(out), 4);
        Check(written == 8 &&
                  ExpectBytes(out, 8, {0xAA, 0x55, 0x11, 0x22, 0x7F, 0x00, 0x00, 0x00},
                              "32-bit 5 bytes"),
              "32-bit container: 5 bytes -> 2 words, tail padded");
    }
    {
        // 1024 bytes are an exact multiple: no padding, byte-exact copy.
        std::vector<uint8_t> dsd(1024);
        for (size_t i = 0; i < dsd.size(); ++i) {
            dsd[i] = static_cast<uint8_t>((i * 37u) & 0xFFu);
        }
        std::vector<uint8_t> out(1024, 0);
        const int written = pulsr::PackDsdBitsToWords(
            dsd.data(), static_cast<int>(dsd.size()), out.data(),
            static_cast<int>(out.size()), 4);
        Check(written == 1024 && out == dsd, "1024-byte 32-bit block is byte-exact");
    }

    // ---------------------------------------------------------------------
    // 5. Capacity handling: a shortfall writes nothing and reports 0.
    // ---------------------------------------------------------------------
    {
        const uint8_t dsd[8] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88};
        std::vector<uint8_t> out(8, 0xA5);
        const int written = pulsr::PackDsdBitsToWords(dsd, 8, out.data(), 7, 4);
        bool untouched = true;
        for (const uint8_t byte : out) {
            if (byte != 0xA5) untouched = false;
        }
        Check(written == 0 && untouched, "short capacity returns 0 and writes nothing");
    }
    {
        const uint8_t dsd[3] = {0xAA, 0x55, 0x11};
        std::vector<uint8_t> out(3, 0xA5);
        const int written = pulsr::PackDsdBitsToWords(dsd, 3, out.data(), 3, 4);
        bool untouched = true;
        for (const uint8_t byte : out) {
            if (byte != 0xA5) untouched = false;
        }
        Check(written == 0 && untouched,
              "a partial trailing word still needs its full capacity");
    }
    {
        // Over-sized capacity: exactly the needed bytes are written, the guard
        // region past them is untouched.
        const uint8_t dsd[4] = {0x01, 0x02, 0x03, 0x04};
        std::vector<uint8_t> out(16, 0xA5);
        const int written = pulsr::PackDsdBitsToWords(dsd, 4, out.data(),
                                                      static_cast<int>(out.size()), 4);
        bool guards = true;
        for (size_t i = 4; i < out.size(); ++i) {
            if (out[i] != 0xA5) guards = false;
        }
        Check(written == 4 && guards, "no write past the packed length");
    }
    {
        const uint8_t dsd[2] = {0x01, 0x02};
        uint8_t out[4] = {0xCC, 0xCC, 0xCC, 0xCC};
        Check(pulsr::PackDsdBitsToWords(dsd, 2, out, 4, 2) == 2,
              "exact capacity is accepted");
    }

    // ---------------------------------------------------------------------
    // 6. Invalid geometry and null pointers.
    // ---------------------------------------------------------------------
    {
        const uint8_t dsd[4] = {0x01, 0x02, 0x03, 0x04};
        const uint8_t single = 0x01;
        uint8_t out[8] = {0};
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, 8, 0) == 0, "container 0 rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, 8, 1) == 0, "container 1 rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, 8, 3) == 0, "container 3 rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, 8, 8) == 0, "container 8 rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, 8, -4) == 0, "negative container rejected");
        Check(pulsr::PackDsdBitsToWords(nullptr, 4, out, 8, 4) == 0, "null input rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, nullptr, 8, 4) == 0, "null output rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 0, out, 8, 4) == 0, "zero-length input rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, -4, out, 8, 4) == 0, "negative length rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, 0, 4) == 0, "zero capacity rejected");
        Check(pulsr::PackDsdBitsToWords(dsd, 4, out, -1, 4) == 0, "negative capacity rejected");
        Check(pulsr::PackDsdBitsToWords(&single, 1, out, 8, 4) == 4,
              "one byte into a 4-byte container is valid");
        Check(out[0] == 0x01 && out[1] == 0 && out[2] == 0 && out[3] == 0,
              "one byte is padded with three zero bytes");
    }

    // ---------------------------------------------------------------------
    // 7. WordsForDsdBytes.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::WordsForDsdBytes(0, 4) == 0, "words(0, 4) == 0");
        Check(pulsr::WordsForDsdBytes(1, 4) == 1, "words(1, 4) == 1");
        Check(pulsr::WordsForDsdBytes(4, 4) == 1, "words(4, 4) == 1");
        Check(pulsr::WordsForDsdBytes(5, 4) == 2, "words(5, 4) == 2");
        Check(pulsr::WordsForDsdBytes(4096, 4) == 1024, "words(4096, 4) == 1024");
        Check(pulsr::WordsForDsdBytes(1, 2) == 1, "words(1, 2) == 1");
        Check(pulsr::WordsForDsdBytes(3, 2) == 2, "words(3, 2) == 2");
        Check(pulsr::WordsForDsdBytes(4096, 2) == 2048, "words(4096, 2) == 2048");
        Check(pulsr::WordsForDsdBytes(-1, 4) == 0, "words(-1, 4) == 0");
        Check(pulsr::WordsForDsdBytes(4, 3) == 0, "words(4, 3) == 0");
        Check(pulsr::WordsForDsdBytes(4, 0) == 0, "words(4, 0) == 0");
    }
    {
        // WordsForDsdBytes and PackDsdBitsToWords must agree for every length
        // in a representative range, including non-multiples of the container.
        bool ok = true;
        for (int bytes = 1; bytes <= 64; ++bytes) {
            for (const int container : {2, 4}) {
                const int words = pulsr::WordsForDsdBytes(bytes, container);
                std::vector<uint8_t> dsd(static_cast<size_t>(bytes), 0x5A);
                std::vector<uint8_t> out(
                    static_cast<size_t>(words * container + 4), 0xA5);
                const int written = pulsr::PackDsdBitsToWords(
                    dsd.data(), bytes, out.data(), static_cast<int>(out.size()),
                    container);
                if (written != words * container) ok = false;
                for (int i = 0; i < 4; ++i) {
                    if (out[static_cast<size_t>(written + i)] != 0xA5) ok = false;
                }
            }
        }
        Check(ok, "WordsForDsdBytes matches the packer for 1..64 bytes, both containers");
    }

    if (gFailures == 0) {
        std::cout << "[TEST] DSD native packer: all checks passed." << std::endl;
        return 0;
    }
    std::cout << "[TEST] DSD native packer: " << gFailures << " failure(s)." << std::endl;
    return 1;
}
