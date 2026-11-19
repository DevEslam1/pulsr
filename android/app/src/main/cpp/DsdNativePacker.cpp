// android/app/src/main/cpp/DsdNativePacker.cpp
//
// See DsdNativePacker.h for the bit-order contract.
#include "DsdNativePacker.h"

#include <cstdint>

namespace pulsr {
namespace {

bool IsValidContainer(int bytesPerSample) {
    return bytesPerSample == 2 || bytesPerSample == 4;
}

}  // namespace

int WordsForDsdBytes(int dsdBytes, int bytesPerSample) {
    if (dsdBytes < 0 || !IsValidContainer(bytesPerSample)) return 0;
    // Written as divide+remainder so that dsdBytes == INT_MAX cannot overflow.
    return dsdBytes / bytesPerSample + ((dsdBytes % bytesPerSample) != 0 ? 1 : 0);
}

int PackDsdBitsToWords(const uint8_t* dsd, int dsdBytes, uint8_t* out,
                       int outCapacity, int bytesPerSample) {
    if (!IsValidContainer(bytesPerSample)) return 0;
    if (dsd == nullptr || out == nullptr) return 0;
    if (dsdBytes <= 0 || outCapacity <= 0) return 0;

    const int words = WordsForDsdBytes(dsdBytes, bytesPerSample);
    const int64_t needed = static_cast<int64_t>(words) * bytesPerSample;
    if (needed > outCapacity) return 0;  // nothing is written on a shortfall

    int source = 0;
    for (int word = 0; word < words; ++word) {
        uint32_t packed = 0;
        for (int byte = 0; byte < bytesPerSample; ++byte) {
            // DSD bit (8 * byte + j) -> word bit (8 * byte + j): the DSD byte
            // lands in the byte of the word at the same bit position. Bits
            // past the end of the input stay 0 (partial word padding).
            const uint32_t value =
                (source < dsdBytes) ? static_cast<uint32_t>(dsd[source]) : 0u;
            packed |= value << (8 * byte);
            ++source;
        }
        const int base = word * bytesPerSample;
        for (int byte = 0; byte < bytesPerSample; ++byte) {
            out[base + byte] = static_cast<uint8_t>((packed >> (8 * byte)) & 0xFFu);
        }
    }
    return static_cast<int>(needed);
}

}  // namespace pulsr
