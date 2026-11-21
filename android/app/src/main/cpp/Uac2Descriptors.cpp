// android/app/src/main/cpp/Uac2Descriptors.cpp
//
// See Uac2Descriptors.h for the descriptor walk, the rate mapping and - most
// importantly - the false-positive reasoning behind the detection rule.
#include "Uac2Descriptors.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace pulsr {
namespace {

constexpr uint8_t kDescTypeConfiguration = 0x02;
constexpr uint8_t kDescTypeInterface = 0x04;
constexpr uint8_t kDescTypeEndpoint = 0x05;
constexpr uint8_t kDescTypeCsInterface = 0x24;

constexpr uint8_t kAudioClass = 0x01;
constexpr uint8_t kAudioStreamingSubclass = 0x02;
constexpr uint8_t kProtocolUac1 = 0x00;
constexpr uint8_t kProtocolUac2 = 0x20;

constexpr uint8_t kCsSubtypeAsGeneral = 0x01;
constexpr uint8_t kCsSubtypeFormatType = 0x02;
constexpr uint8_t kFormatTypeI = 0x01;
constexpr uint32_t kUac2FormatTypeIRawData = 0x80000000u;

constexpr uint8_t kEndpointTransferMask = 0x03;
constexpr uint8_t kEndpointTransferIsochronous = 0x01;

constexpr int kMaxChannels = 32;  // 2..8 is real life; 32 is a generous bound

// ---------------------------------------------------------------------------
// Quirk table insertion point.
//
// Rows here are (vendorId, productId) pairs for which native DSD is trusted
// even though the descriptor graph is ambiguous - i.e. a stereo interface with
// a single DSD-mapped rate and no adjacent ladder rung. Rule (a) already covers
// mono alt settings and rule (b) covers a coherent ladder, so a row is only
// ever needed for a DAC that is real but looks like 32-bit PCM.
//
// The table is empty on purpose: no DAC has been verified against this
// codebase's own hardware yet, and every row is a promise that the device stops
// using DoP and starts receiving raw 1-bit data. A wrong row is full-scale
// noise, so entries are added one real unit at a time.
//
// To add one, bump the size and list the row:
//   constexpr std::array<DsdQuirkEntry, 1> kDsdQuirks{{{0x20B1, 0x0001}}};
// ---------------------------------------------------------------------------
constexpr std::array<DsdQuirkEntry, 0> kDsdQuirks{};

bool QuirkListed(const DsdQuirkEntry* quirks, size_t quirkCount, int vendorId,
                 int productId) {
    if (quirks == nullptr || quirkCount == 0) return false;
    for (size_t i = 0; i < quirkCount; ++i) {
        if (quirks[i].vendorId == vendorId && quirks[i].productId == productId) {
            return true;
        }
    }
    return false;
}

int LadderRungFor(int dsdRate) {
    switch (dsdRate) {
        case 64: return 0;
        case 128: return 1;
        case 256: return 2;
        case 512: return 3;
        default: return -1;
    }
}

// One (frames per second, DSD multiple) pair advertised by a FORMAT_TYPE_I.
struct MappedRate {
    int framesPerSecond = 0;
    int dsdRate = 0;
};

// One alternate setting of one audio-streaming interface, reduced to what the
// detection rule needs. Built while walking the descriptor chain.
struct AltSummary {
    int interfaceNumber = -1;
    int altSetting = 0;
    int endpointAddress = 0;
    int channels = 0;
    std::vector<MappedRate> rates;  // DSD-mapped rates, descriptor order
    int primaryRung = -1;           // ladder rung of the first mapped rate
    bool uac2 = true;               // layout selector, not part of the result
    bool isUac2RawData = false;     // UAC2 AS_GENERAL bmFormats == TYPE_I_RAW_DATA
    int asGeneralChannels = 0;      // UAC2 AS_GENERAL bNrChannels for 6-byte FORMAT_TYPE_I
};

// A UAC2/UAC1 FORMAT_TYPE_I payload. `d` points at the descriptor start and
// `dlen` is its bLength. Returns false only when the descriptor contradicts
// itself (a truncated tSamFreq[] or a missing bFormatType); a legal but
// uninteresting format returns true and simply records nothing.
//
// bBitResolution is deliberately not read: PCM and native-DSD alt settings both
// declare 32 bits for a 4-byte subslot, so it carries no discriminating power.
bool ReadFormatTypeI(const uint8_t* d, int dlen, bool uac2, AltSummary* alt) {
    // UAC2 moves bNrChannels behind tSamFreq[] and a 4-byte bmChannelConfig;
    // UAC1 keeps it in front of the subslot fields. See the header table.
    const int subslotOff = uac2 ? 4 : 5;
    const int freqTypeOff = uac2 ? 6 : 7;
    const int freqOff = uac2 ? 7 : 8;
    // Standard USB Audio 2.0 FORMAT_TYPE_I is 6 bytes (bLength=6, no inline
    // tSamFreq[]); channels and bmFormats come from the preceding AS_GENERAL.
    // Valid 6-byte PCM alt settings emit no DSD rates without aborting parsing
    // of sibling alt settings.
    if (uac2 && dlen == 6) {
        alt->rates.clear();
        alt->primaryRung = -1;
        const int subslot = d[4];
        const int bitResolution = d[5];
        if (subslot == 4 && bitResolution == 32 && alt->isUac2RawData &&
            alt->asGeneralChannels >= 1 &&
            alt->asGeneralChannels <= kMaxChannels) {
            alt->channels = alt->asGeneralChannels;
            alt->primaryRung = 0;
            for (int r = 0; r < 4; ++r) {
                const int fps = kDsdLadderFramesPerSecond[r];
                const int rate = DsdRateForAltSetting(fps, 4);
                if (rate > 0) alt->rates.push_back(MappedRate{fps, rate});
            }
        }
        return true;
    }
    if (dlen <= freqTypeOff) return false;

    alt->rates.clear();
    alt->primaryRung = -1;

    const int subslot = d[subslotOff];
    if (subslot != 4) return true;  // U16/PCM-only geometry: never reported
    const int freqType = d[freqTypeOff];
    if (freqType == 0) return true;  // continuous range: no discrete rate

    const int freqBytes = 3 * freqType;
    if (freqOff + freqBytes > dlen) return false;  // truncated tSamFreq[]

    int channels = 0;
    if (uac2) {
        const int channelsOff = freqOff + freqBytes + 4;  // past bmChannelConfig
        if (channelsOff < dlen) channels = d[channelsOff];
    } else {
        channels = d[4];
    }
    if (channels < 1 || channels > kMaxChannels) return true;  // unusable

    for (int k = 0; k < freqType; ++k) {
        const int off = freqOff + 3 * k;
        const int framesPerSecond = d[off] | (d[off + 1] << 8) | (d[off + 2] << 16);
        const int rate = DsdRateForAltSetting(framesPerSecond, 4);
        if (rate == 0) continue;
        if (alt->primaryRung < 0) alt->primaryRung = LadderRungFor(rate);
        alt->rates.push_back(MappedRate{framesPerSecond, rate});
    }
    alt->channels = channels;
    return true;
}

void FinalizeAlt(const AltSummary& alt, bool hasFormat, bool isAudioStreaming,
                 std::vector<AltSummary>* out) {
    if (!isAudioStreaming || !hasFormat) return;
    if (alt.endpointAddress <= 0) return;          // no isochronous OUT endpoint
    if (alt.channels < 1) return;                  // channel count unreadable
    if (alt.rates.empty()) return;                 // not a DSD-mapped alt setting
    out->push_back(alt);
}

// Ladder evidence is counted across *distinct alternate settings* of the same
// interface, never across several rates listed by one alt setting. A DSD alt
// setting carries exactly one DSD clock; a PCM alt setting routinely lists
// several rates in a single FORMAT_TYPE_I ({44100, 48000, 88200, ...}), so
// counting those as a "ladder" would re-open the exact false positive this rule
// exists to close.
bool HasAdjacentLadderRung(const std::vector<AltSummary>& alts, size_t index) {
    const AltSummary& self = alts[index];
    const int rung = self.primaryRung;
    if (rung < 0) return false;
    for (size_t i = 0; i < alts.size(); ++i) {
        if (i == index) continue;
        const AltSummary& other = alts[i];
        if (other.interfaceNumber != self.interfaceNumber) continue;
        if (other.altSetting == self.altSetting) continue;  // duplicate descriptor
        if (other.primaryRung != rung - 1 && other.primaryRung != rung + 1) continue;
        // The adjacent rung must itself be a real, distinct rate: this is
        // guaranteed by construction (primaryRung names a mapped DSD multiple).
        return true;
    }
    return false;
}

std::vector<DsdAltSetting> ParseImpl(const uint8_t* config, size_t len,
                                     int vendorId, int productId,
                                     const DsdQuirkEntry* quirks,
                                     size_t quirkCount) {
    std::vector<DsdAltSetting> result;
    if (config == nullptr || len < 9) return result;
    if (config[1] != kDescTypeConfiguration) return result;
    if (config[0] < 9) return result;

    const size_t total =
        static_cast<size_t>(config[2]) | (static_cast<size_t>(config[3]) << 8);
    // A short buffer is truncation; a longer buffer is simply a generous read
    // (usbfs returns what fits), so the walk is bounded by wTotalLength.
    if (total < 9 || total > len) return result;

    std::vector<AltSummary> alts;
    AltSummary alt;
    bool hasFormat = false;
    bool isAudioStreaming = false;

    size_t i = 0;
    while (i < total) {
        const int dlen = config[i];
        if (dlen < 2 || dlen > static_cast<int>(total - i)) return {};
        const uint8_t dtype = config[i + 1];

        if (dtype == kDescTypeInterface) {
            if (dlen < 9) return {};
            FinalizeAlt(alt, hasFormat, isAudioStreaming, &alts);
            alt = AltSummary{};
            hasFormat = false;
            alt.interfaceNumber = config[i + 2];
            alt.altSetting = config[i + 3];
            const uint8_t proto = config[i + 7];
            isAudioStreaming = config[i + 5] == kAudioClass &&
                               config[i + 6] == kAudioStreamingSubclass &&
                               (proto == kProtocolUac2 || proto == kProtocolUac1);
            alt.uac2 = proto != kProtocolUac1;
        } else if (dtype == kDescTypeCsInterface) {
            if (dlen < 3) return {};
            if (isAudioStreaming && alt.uac2 &&
                config[i + 2] == kCsSubtypeAsGeneral && dlen >= 16) {
                if (config[i + 5] == kFormatTypeI) {
                    const uint32_t bmFormats =
                        static_cast<uint32_t>(config[i + 6]) |
                        (static_cast<uint32_t>(config[i + 7]) << 8) |
                        (static_cast<uint32_t>(config[i + 8]) << 16) |
                        (static_cast<uint32_t>(config[i + 9]) << 24);
                    alt.isUac2RawData = (bmFormats == kUac2FormatTypeIRawData);
                    alt.asGeneralChannels = config[i + 10];
                }
            } else if (isAudioStreaming && !hasFormat &&
                       config[i + 2] == kCsSubtypeFormatType) {
                if (dlen < 4) return {};
                if (config[i + 3] == kFormatTypeI) {
                    hasFormat = true;
                    if (!ReadFormatTypeI(config + i, dlen, alt.uac2, &alt)) return {};
                }
            }
        } else if (dtype == kDescTypeEndpoint) {
            if (dlen < 7) return {};
            const int address = config[i + 2];
            // Isochronous OUT endpoint, first one wins. bEndpointAddress is a
            // 4-bit number in bits 3..0 (bit 7 = direction, bits 6..4
            // reserved), so anything above 0x0F is a garbled descriptor and
            // is ignored rather than reported as a stream target. Alt setting
            // 0 (no bandwidth, bNumEndpoints 0) therefore never becomes a
            // candidate.
            const bool validAddress = address >= 1 && address <= 0x0F;
            if (isAudioStreaming && alt.endpointAddress == 0 && validAddress &&
                (config[i + 3] & kEndpointTransferMask) == kEndpointTransferIsochronous) {
                alt.endpointAddress = address;
            }
        }
        i += static_cast<size_t>(dlen);
    }
    FinalizeAlt(alt, hasFormat, isAudioStreaming, &alts);

    const bool quirkListed = QuirkListed(quirks, quirkCount, vendorId, productId);
    for (size_t index = 0; index < alts.size(); ++index) {
        const AltSummary& altSetting = alts[index];
        const bool mono = altSetting.channels == 1;
        if (!mono && !quirkListed && !altSetting.isUac2RawData &&
            !HasAdjacentLadderRung(alts, index)) {
            continue;
        }
        for (const MappedRate& rate : altSetting.rates) {
            DsdAltSetting setting;
            setting.interfaceNumber = altSetting.interfaceNumber;
            setting.altSetting = altSetting.altSetting;
            setting.endpointAddress = altSetting.endpointAddress;
            setting.channels = altSetting.channels;
            setting.bytesPerSample = 4;
            setting.framesPerSecond = rate.framesPerSecond;
            setting.dsdRate = rate.dsdRate;
            result.push_back(setting);
        }
    }
    return result;
}

}  // namespace

int DsdRateForAltSetting(int framesPerSecond, int bytesPerSample) {
    if (framesPerSecond <= 0) return 0;
    if (bytesPerSample != 2 && bytesPerSample != 4) return 0;
    const int64_t bitsPerSecond =
        static_cast<int64_t>(framesPerSecond) * 8 * bytesPerSample;
    if (bitsPerSecond % 44100 != 0) return 0;
    const int64_t rate = bitsPerSecond / 44100;
    if (rate == 64) return 64;
    if (rate == 128) return 128;
    if (rate == 256) return 256;
    if (rate == 512) return 512;
    return 0;
}

bool IsDsdQuirkDevice(int vendorId, int productId) {
    return QuirkListed(kDsdQuirks.data(), kDsdQuirks.size(), vendorId, productId);
}

std::vector<DsdAltSetting> ParseDsdAltSettings(const uint8_t* config, size_t len,
                                               int vendorId, int productId) {
    return ParseImpl(config, len, vendorId, productId, kDsdQuirks.data(),
                     kDsdQuirks.size());
}

std::vector<DsdAltSetting> ParseDsdAltSettingsWithQuirks(
    const uint8_t* config, size_t len, int vendorId, int productId,
    const DsdQuirkEntry* quirks, size_t quirkCount) {
    return ParseImpl(config, len, vendorId, productId, quirks, quirkCount);
}

std::vector<int> DsdRatesFor(const std::vector<DsdAltSetting>& settings) {
    std::vector<int> rates;
    for (const DsdAltSetting& setting : settings) {
        if (setting.dsdRate <= 0) continue;
        rates.push_back(setting.dsdRate);
    }
    std::sort(rates.begin(), rates.end());
    rates.erase(std::unique(rates.begin(), rates.end()), rates.end());
    return rates;
}

}  // namespace pulsr
