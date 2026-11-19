// android/app/src/main/cpp/Uac2Descriptors.h
//
// Native-DSD capability probe for USB Audio Class 2.0 DACs.
//
// Some DACs expose "native DSD" as a set of UAC2 AudioStreaming alternate
// settings whose FORMAT_TYPE_I descriptor carries a 32-bit subslot; the device
// then expects the 1-bit DSD stream packed into 32-bit little-endian words
// (DSD_U32, the XMOS/Thesycon convention) instead of the 24-bit DoP framing
// used by the default path. This module answers one question, from the raw
// configuration descriptor blob only: *which alternate settings speak DSD, at
// which multiple?* It never opens a stream and never talks to hardware, so the
// whole decision is host-testable (test_uac2_dsd_probe.cpp).
//
// Descriptor walk
// ---------------
//   configuration (0x02, 9 bytes, wTotalLength bounds the walk)
//     -> interface (0x04) with bInterfaceClass 0x01, bInterfaceSubClass 0x02
//        and bInterfaceProtocol 0x20 (UAC2) or 0x00 (UAC1, accepted for
//        completeness; UAC1 alt settings are never DSD in practice)
//          -> class-specific AS interface descriptor (0x24, subtype 0x02 =
//             FORMAT_TYPE) whose bFormatType is 0x01 = FORMAT_TYPE_I
//          -> endpoint (0x05), isochronous, OUT (bit 7 clear)
//
// FORMAT_TYPE_I is laid out differently by the two specs, and the difference
// matters because it moves bNrChannels:
//   UAC1 (Audio Data Formats 1.0, table 3-2):
//     bNrChannels@4, bSubframeSize@5, bBitResolution@6, bSamFreqType@7,
//     tSamFreq[]@8
//   UAC2 (Audio Data Formats 2.0, table 2-2):
//     bSubslotSize@4, bBitResolution@5, bSamFreqType@6, tSamFreq[]@7,
//     bmChannelConfig (4 bytes), bNrChannels (1 byte)
// The interface's bInterfaceProtocol selects the layout. bSamFreqType == 0
// means a continuous min/max pair, which cannot name one discrete rate and is
// therefore never a DSD candidate; bSamFreqType == N >= 1 is a list of N
// 24-bit little-endian frames-per-second values.
//
// Rate mapping
// ------------
//   dsdRate = framesPerSecond * 8 * bytesPerSample / 44100
// A DSD64/U32 alt setting runs at 88200 frames/s (64 * 44100 / 32), DSD128 at
// 176400, DSD256 at 352800, DSD512 at 705600. The quotient is the true DSD
// multiple for any subslot size, but only the 4-byte ladder is trusted (see
// below): DSD_U16 carries half as many DSD bits per frame, so its rungs sit at
// double the frame rate (DSD64 = 176400 frames/s, DSD128 = 352800, DSD256 =
// 705600) and collide with plain 16-bit PCM rates. The division must be exact
// and the quotient must be one of 64/128/256/512; anything else (PCM 384000/32
// -> 278.6, the 48 kHz DSD family -> 69.66, DSD1024 -> 1024) maps to 0.
//
// Detection rule (deliberate, conservative)
// -----------------------------------------
// The descriptor bytes alone do not distinguish a DSD_U32 alt setting from a
// high-rate 32-bit PCM alt setting: both are bInterfaceClass 0x01 /
// subclass 0x02 / FORMAT_TYPE_I / bSubslotSize 4, and both usually declare
// bBitResolution 32. The only honest evidence is structural, so an alt setting
// is reported if and only if ALL of the following hold:
//
//   * bSubslotSize == 4 (32-bit subslot),
//   * the rate mapping above yields exactly 64, 128, 256 or 512, and
//   * at least one of:
//       (a) it is mono (bNrChannels == 1) - the "one alt setting per channel"
//           DSD_U32 convention, where a stereo pair costs two alt settings and
//           a PCM alt setting of that shape would be useless;
//       (b) the *same* AS interface exposes an adjacent rung of the DSD
//           ladder (88200 / 176400 / 352800 / 705600 at 4-byte subslots) as a
//           second, separately streamable alternate setting, i.e. two
//           consecutive DSD-mapped rates with one clock each. A firmware that
//           fakes DSD usually fakes the whole ladder, and a PCM-only interface
//           is very unlikely to offer e.g. both 88.2 kHz and 176.4 kHz at 32
//           bits *and* nothing else in between;
//       (c) the VID/PID is in the quirk table (empty by default - see
//           kDsdQuirks in Uac2Descriptors.cpp for the insertion point).
//
// Everything else is dropped. The cost of a false positive is severe: we would
// stop sending DoP and push raw 1-bit data at a PCM DAC, which plays full-scale
// noise. The cost of a false negative is that the DAC keeps running DoP, which
// is bit-perfect up to DSD128 and merely halves the maximum rate. Missing a DAC
// is therefore much cheaper than misfiring on one, and 2-byte subslot
// (DSD_U16) alt settings are never reported at all even when the mapping
// succeeds: their rungs land on established 16-bit PCM rates, and the
// native-DSD ecosystem is U32-only in practice, so a U16 device would need an
// explicit quirk entry rather than a looser rule.
//
// Two refinements keep rule (b) from re-opening the hole it closes:
//   * the ladder is counted across distinct alternate settings, never across
//     several rates listed by one FORMAT_TYPE_I (a PCM alt setting commonly
//     advertises {44100, 48000, 88200, ...} in a single descriptor);
//   * a rung only counts when it is streamable, i.e. that alternate setting has
//     its own isochronous OUT endpoint, so an endpoint-less alt 0 cannot lend
//     ladder credibility to alt 1.
//
// Residual risk that this rule cannot remove
// ------------------------------------------
// A stereo interface exposing 88.2 kHz *and* 176.4 kHz at 32-bit subslots, and
// nothing else, is descriptor-identical to a DSD64/DSD128 ladder. Both are
// plausible PCM rates. This is why (b) requires *adjacent* rungs rather than
// any two DSD-mapped rates, and why the caller must keep DoP as the fallback
// until the first native-DSD buffer is confirmed by ear/analyser. Contract A
// keeps the probe offline; the sink-side verification is out of scope here.
//
// Robustness
// ----------
// The parser is fuzz-safe: every length byte is validated, no read goes past
// `len`, and any structural inconsistency (bLength < 2, a descriptor that runs
// past wTotalLength, wTotalLength larger than the buffer, a truncated
// FORMAT_TYPE_I rate list) makes the whole blob parse to an empty vector rather
// than to a best-effort partial answer. Control-path allocation is fine here;
// nothing in this header runs on the audio thread.
#ifndef PULSR_UAC2_DESCRIPTORS_H_
#define PULSR_UAC2_DESCRIPTORS_H_

#include <cstddef>
#include <cstdint>
#include <vector>

namespace pulsr {

/// One DSD-capable UAC2 alternate setting, as accepted by the detection rule.
struct DsdAltSetting {
    int interfaceNumber = -1;
    int altSetting = 0;
    int endpointAddress = 0;   // isochronous OUT, bit 7 clear
    int channels = 2;
    int bytesPerSample = 4;    // U32 packing is the norm; U16 also exists
    int framesPerSecond = 0;   // 88200 for DSD64/U32, 176400 for DSD128/U32, ...
    int dsdRate = 0;           // 64/128/256/512, 0 if not a DSD alt setting
};

/// The DSD ladder expressed as U32 frames per second: DSD64/128/256/512.
inline constexpr int kDsdLadderFramesPerSecond[4] = {88200, 176400, 352800, 705600};

/// Maps a UAC2 alt setting geometry to a DSD multiple.
///
///   rate = framesPerSecond * 8 * bytesPerSample / 44100
///
/// Returns 64, 128, 256 or 512 when that quotient is exact and equals one of
/// those powers of two, otherwise 0. Only 2- and 4-byte subslots are valid
/// geometry; 0 is returned for everything else (including 48 kHz-family DSD,
/// which is outside the UAC2/DoP integer relationship used here).
int DsdRateForAltSetting(int framesPerSecond, int bytesPerSample);

/// A VID/PID for which native DSD is trusted regardless of the ladder evidence.
struct DsdQuirkEntry {
    int vendorId;
    int productId;
};

/// True when the VID/PID is in the built-in quirk table. The built-in table is
/// deliberately empty (see kDsdQuirks in the .cpp): no DAC has been verified on
/// this codebase's own hardware yet, and a speculative entry here would defeat
/// the whole conservative rule.
bool IsDsdQuirkDevice(int vendorId, int productId);

/// Parses a raw configuration descriptor blob and returns the DSD alternate
/// settings accepted by the rule documented at the top of this file, in
/// descriptor order. Returns an empty vector for malformed or truncated input,
/// for a blob that is not a configuration descriptor, and for every DAC whose
/// DSD support is not provable from the descriptor graph.
///
/// The walk is bounded by wTotalLength, not by `len`, so a buffer that carries
/// trailing bytes past the declared configuration length still parses; a buffer
/// shorter than wTotalLength is treated as truncated (empty result).
std::vector<DsdAltSetting> ParseDsdAltSettings(const uint8_t* config, size_t len,
                                               int vendorId, int productId);

/// Same walk, with an explicit quirk table used *instead of* the built-in one.
/// Production code calls ParseDsdAltSettings(); this entry point exists so the
/// quirk path is testable and so a platform layer can add entries without
/// touching this file. `quirks` / `quirkCount` of 0 disables the quirk path.
std::vector<DsdAltSetting> ParseDsdAltSettingsWithQuirks(
    const uint8_t* config, size_t len, int vendorId, int productId,
    const DsdQuirkEntry* quirks, size_t quirkCount);

/// Sorted, de-duplicated DSD multiples present in `settings` (64..512).
std::vector<int> DsdRatesFor(const std::vector<DsdAltSetting>& settings);

}  // namespace pulsr

#endif  // PULSR_UAC2_DESCRIPTORS_H_
