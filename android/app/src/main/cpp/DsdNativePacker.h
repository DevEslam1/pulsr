// android/app/src/main/cpp/DsdNativePacker.h
//
// Packs a 1-bit DSD stream into the 16- or 32-bit little-endian words that a
// native-DSD UAC2 DAC expects (DSD_U32 / DSD_U16, the XMOS/Thesycon
// convention). Pure byte shuffling: no allocation, no locks, no logging, safe
// to call from a render thread, and host-testable without a DAC
// (test_dsd_native_packer.cpp).
//
// Bit order
// ---------
// Input is the DSF bit order: within every byte, bit 0 is the *earliest* DSD
// sample. Output keeps that order, so the first DSD bit becomes bit 0 (the LSB)
// of the first little-endian word and the stream is continuous across word
// boundaries. For a 4-byte container that reduces to a byte-for-byte copy of
// the DSF payload, which is exactly why DSF -> DSD_U32_LE needs no bit
// reversal; it is spelled out as explicit shifts anyway so nobody "fixes" the
// byte order later.
//
// DFF files are MSB-first per byte and must be bit-reversed *before* this call
// (see DopFramer.h for the LSB<->MSB reversal used by the DoP path). Do not
// paper over that here: the two container formats disagree, and hiding the
// conversion inside the packer would silently corrupt one of them.
//
// Geometry
// --------
// One word holds `bytesPerSample * 8` DSD bits, so `dsdBytes` DSD bytes need
// ceil(dsdBytes / bytesPerSample) words. A trailing partial word is padded
// with zero bits on the high side; the function never writes past
// `outCapacity`, and it writes nothing at all when the capacity is short.
#ifndef PULSR_DSD_NATIVE_PACKER_H_
#define PULSR_DSD_NATIVE_PACKER_H_

#include <cstdint>

namespace pulsr {

/// Words (16- or 32-bit containers) needed for `dsdBytes` DSD bytes.
/// Returns 0 for negative input or for a container size other than 2 or 4.
int WordsForDsdBytes(int dsdBytes, int bytesPerSample);

/// Packs `dsdBytes` of a 1-bit stream into `bytesPerSample`-wide little-endian
/// words, `bytesPerSample` being 2 or 4. The first DSD bit is the LSB of the
/// first word. A partial trailing word is zero-padded.
///
/// Returns the number of bytes written (WordsForDsdBytes() * bytesPerSample),
/// or 0 when the geometry is invalid, when `dsdBytes` <= 0, when a pointer is
/// null, or when `outCapacity` cannot hold the complete result. On a 0 return
/// nothing has been written.
int PackDsdBitsToWords(const uint8_t* dsd, int dsdBytes, uint8_t* out,
                       int outCapacity, int bytesPerSample);

}  // namespace pulsr

#endif  // PULSR_DSD_NATIVE_PACKER_H_
