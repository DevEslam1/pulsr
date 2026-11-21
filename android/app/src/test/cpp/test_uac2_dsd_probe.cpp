// android/app/src/test/cpp/test_uac2_dsd_probe.cpp
//
// Host test for pulsr::ParseDsdAltSettings / DsdRateForAltSetting.
// Every blob here is synthetic: the point is to pin the detection rule (and its
// deliberate rejections) without a DAC, and to prove the parser is fuzz-safe.
#include "../../main/cpp/Uac2Descriptors.h"

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

bool Matches(const pulsr::DsdAltSetting& s, int interfaceNumber, int altSetting,
             int endpointAddress, int channels, int framesPerSecond, int dsdRate) {
    return s.interfaceNumber == interfaceNumber && s.altSetting == altSetting &&
           s.endpointAddress == endpointAddress && s.channels == channels &&
           s.bytesPerSample == 4 && s.framesPerSecond == framesPerSecond &&
           s.dsdRate == dsdRate;
}

void Dump(const std::vector<pulsr::DsdAltSetting>& settings) {
    std::cout << "    got " << settings.size() << " setting(s):";
    for (const pulsr::DsdAltSetting& s : settings) {
        std::cout << " {if=" << s.interfaceNumber << " alt=" << s.altSetting
                  << " ep=0x" << std::hex << s.endpointAddress << std::dec
                  << " ch=" << s.channels << " bps=" << s.bytesPerSample
                  << " fps=" << s.framesPerSecond << " dsd=" << s.dsdRate << "}";
    }
    std::cout << std::endl;
}

// Minimal descriptor builder. Lengths are computed, never hand-counted, so a
// test can only be wrong in the fields it sets deliberately.
class Blob {
public:
    Blob& Config(int numInterfaces = 1) {
        U8(9);
        U8(0x02);   // bDescriptorType = CONFIGURATION
        U16(0);     // wTotalLength, patched by Finish()
        U8(numInterfaces);
        U8(1);      // bConfigurationValue
        U8(0);      // iConfiguration
        U8(0x80);   // bmAttributes
        U8(0x32);   // bMaxPower
        return *this;
    }

    Blob& Interface(int number, int alt, int numEndpoints, int proto,
                    int cls = 0x01, int sub = 0x02) {
        U8(9);
        U8(0x04);   // bDescriptorType = INTERFACE
        U8(number);
        U8(alt);
        U8(numEndpoints);
        U8(cls);
        U8(sub);
        U8(proto);
        U8(0);      // iInterface
        return *this;
    }

    // UAC2 Audio Data Formats 2.0, table 2-2.
    Blob& Uac2Format(int channels, int subslot, int bits,
                     const std::vector<int>& rates) {
        U8(14 + 3 * static_cast<int>(rates.size()));
        U8(0x24);   // CS_INTERFACE
        U8(0x02);   // FORMAT_TYPE
        U8(0x01);   // FORMAT_TYPE_I
        U8(subslot);
        U8(bits);
        U8(static_cast<int>(rates.size()));  // bSamFreqType
        for (const int rate : rates) U24(rate);
        U32(0);     // bmChannelConfig
        U8(channels);  // bNrChannels (after tSamFreq[] in UAC2)
        U8(0);      // bmChannelNames
        U8(0);      // iChannelNames
        return *this;
    }

    // UAC1 Audio Data Formats 1.0, table 3-2.
    Blob& Uac1Format(int channels, int subslot, int bits,
                     const std::vector<int>& rates) {
        U8(8 + 3 * static_cast<int>(rates.size()));
        U8(0x24);
        U8(0x02);
        U8(0x01);
        U8(channels);  // bNrChannels before the subslot fields in UAC1
        U8(subslot);
        U8(bits);
        U8(static_cast<int>(rates.size()));
        for (const int rate : rates) U24(rate);
        return *this;
    }

    Blob& Endpoint(int address, int attributes = 0x05) {
        U8(7);
        U8(0x05);   // ENDPOINT
        U8(address);
        U8(attributes);  // 0x05 = isochronous, asynchronous
        U16(0x0200);
        U8(1);      // bInterval
        return *this;
    }

    Blob& Raw(std::initializer_list<int> values) {
        for (const int v : values) U8(v);
        return *this;
    }

    std::vector<uint8_t> Finish() {
        const int total = static_cast<int>(bytes_.size());
        bytes_[2] = static_cast<uint8_t>(total & 0xFF);
        bytes_[3] = static_cast<uint8_t>((total >> 8) & 0xFF);
        return bytes_;
    }

private:
    void U8(int v) { bytes_.push_back(static_cast<uint8_t>(v & 0xFF)); }
    void U16(int v) { U8(v); U8(v >> 8); }
    void U24(int v) { U8(v); U8(v >> 8); U8(v >> 16); }
    void U32(int v) { U16(v); U16(v >> 16); }

    std::vector<uint8_t> bytes_;
};

struct AltSpec {
    int alt = 1;
    int channels = 2;
    int subslot = 4;
    int bits = 32;
    std::vector<int> rates;
    int endpoint = 0x01;  // 0 = no endpoint descriptor at all
};

std::vector<uint8_t> MakeDevice(int proto, const std::vector<AltSpec>& alts,
                                int interfaceNumber = 1) {
    Blob b;
    b.Config(1);
    for (const AltSpec& alt : alts) {
        b.Interface(interfaceNumber, alt.alt, alt.endpoint == 0 ? 0 : 1, proto);
        if (alt.subslot > 0) {
            if (proto == 0x20) {
                b.Uac2Format(alt.channels, alt.subslot, alt.bits, alt.rates);
            } else {
                b.Uac1Format(alt.channels, alt.subslot, alt.bits, alt.rates);
            }
        }
        if (alt.endpoint != 0) b.Endpoint(alt.endpoint);
    }
    return b.Finish();
}

std::vector<pulsr::DsdAltSetting> Parse(const std::vector<uint8_t>& blob,
                                        int vendorId = 0x1234, int productId = 0x5678) {
    return pulsr::ParseDsdAltSettings(blob.data(), blob.size(), vendorId, productId);
}

bool InvariantsHold(const pulsr::DsdAltSetting& s) {
    const bool rate = s.dsdRate == 64 || s.dsdRate == 128 ||
                      s.dsdRate == 256 || s.dsdRate == 512;
    return s.interfaceNumber >= 0 && s.altSetting >= 0 && s.bytesPerSample == 4 &&
           s.channels >= 1 && s.channels <= 32 && s.endpointAddress >= 1 &&
           s.endpointAddress <= 0x0F && s.framesPerSecond > 0 && rate;
}

}  // namespace

int main() {
    std::cout << "[TEST] Running UAC2 native-DSD probe tests..." << std::endl;

    // ---------------------------------------------------------------------
    // 1. Rate mapping: exact power-of-two only, 2- and 4-byte subslots.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::DsdRateForAltSetting(88200, 4) == 64, "88200 fps / 4-byte -> DSD64");
        Check(pulsr::DsdRateForAltSetting(176400, 4) == 128, "176400 fps / 4-byte -> DSD128");
        Check(pulsr::DsdRateForAltSetting(352800, 4) == 256, "352800 fps / 4-byte -> DSD256");
        Check(pulsr::DsdRateForAltSetting(705600, 4) == 512, "705600 fps / 4-byte -> DSD512");
        Check(pulsr::DsdRateForAltSetting(352800, 2) == 128, "352800 fps / 2-byte -> DSD128");
        Check(pulsr::DsdRateForAltSetting(88200, 2) == 0, "88200 fps / 2-byte is DSD32, rejected");
        Check(pulsr::DsdRateForAltSetting(1411200, 4) == 0, "DSD1024 is out of range, rejected");
        Check(pulsr::DsdRateForAltSetting(384000, 4) == 0, "PCM 384k/32 is not a power of two");
        Check(pulsr::DsdRateForAltSetting(96000, 4) == 0, "48 kHz family never maps");
        Check(pulsr::DsdRateForAltSetting(44100, 4) == 0, "44.1k/32 is not DSD");
        Check(pulsr::DsdRateForAltSetting(0, 4) == 0, "zero rate rejected");
        Check(pulsr::DsdRateForAltSetting(-88200, 4) == 0, "negative rate rejected");
        Check(pulsr::DsdRateForAltSetting(88200, 3) == 0, "3-byte subslot rejected");
        Check(pulsr::DsdRateForAltSetting(88200, 1) == 0, "1-byte subslot rejected");
        Check(pulsr::DsdRateForAltSetting(pulsr::kDsdLadderFramesPerSecond[0], 4) == 64 &&
                  pulsr::DsdRateForAltSetting(pulsr::kDsdLadderFramesPerSecond[3], 4) == 512,
              "header ladder constant matches the mapping");
    }

    // ---------------------------------------------------------------------
    // 2. Rule (a): mono 32-bit DSD alt setting is accepted.
    // ---------------------------------------------------------------------
    {
        const std::vector<uint8_t> blob =
            MakeDevice(0x20, {{1, 1, 4, 32, {88200}, 0x01}});
        const auto got = Parse(blob);
        const bool ok = got.size() == 1 && Matches(got[0], 1, 1, 0x01, 1, 88200, 64);
        Check(ok, "mono U32 DSD64 alt setting accepted");
        if (!ok) Dump(got);
    }
    {
        // Mono is accepted on its own even when it is the only rate present.
        const std::vector<uint8_t> blob =
            MakeDevice(0x20, {{2, 1, 4, 32, {705600}, 0x03}});
        const auto got = Parse(blob);
        const bool ok = got.size() == 1 && Matches(got[0], 1, 2, 0x03, 1, 705600, 512);
        Check(ok, "mono U32 DSD512 alt setting accepted");
        if (!ok) Dump(got);
    }

    // ---------------------------------------------------------------------
    // 3. Stereo without ladder evidence is rejected (the default case).
    // ---------------------------------------------------------------------
    {
        const auto got = Parse(MakeDevice(0x20, {{1, 2, 4, 32, {88200}, 0x01}}));
        Check(got.empty(), "stereo single-rate U32 DSD64 rejected (no ladder)");
        if (!got.empty()) Dump(got);
    }
    {
        // 352.8 kHz / 32-bit is a real PCM rate and maps to DSD256. It must not
        // be accepted on its own: this is the exact false positive the ladder
        // rule exists to prevent.
        const auto got = Parse(MakeDevice(0x20, {{1, 2, 4, 32, {352800}, 0x01}}));
        Check(got.empty(), "stereo 352.8 kHz / 32-bit PCM rejected (DSD256 lookalike)");
        if (!got.empty()) Dump(got);
    }

    // ---------------------------------------------------------------------
    // 4. Rule (b): a two-rung ladder on the same interface is accepted.
    // ---------------------------------------------------------------------
    {
        const std::vector<uint8_t> blob = MakeDevice(
            0x20, {{1, 2, 4, 32, {88200}, 0x01}, {2, 2, 4, 32, {176400}, 0x02}});
        const auto got = Parse(blob);
        const bool ok = got.size() == 2 && Matches(got[0], 1, 1, 0x01, 2, 88200, 64) &&
                        Matches(got[1], 1, 2, 0x02, 2, 176400, 128);
        Check(ok, "stereo DSD64/DSD128 ladder accepted");
        if (!ok) Dump(got);

        const std::vector<int> rates = pulsr::DsdRatesFor(got);
        Check(rates.size() == 2 && rates[0] == 64 && rates[1] == 128,
              "DsdRatesFor returns {64,128} sorted");
    }
    {
        // Full ladder, four alts.
        const std::vector<uint8_t> blob = MakeDevice(
            0x20, {{1, 2, 4, 32, {88200}, 0x01},
                   {2, 2, 4, 32, {176400}, 0x01},
                   {3, 2, 4, 32, {352800}, 0x01},
                   {4, 2, 4, 32, {705600}, 0x01}});
        const auto got = Parse(blob);
        const std::vector<int> rates = pulsr::DsdRatesFor(got);
        const bool ok = got.size() == 4 && rates.size() == 4 && rates[0] == 64 &&
                        rates[1] == 128 && rates[2] == 256 && rates[3] == 512;
        Check(ok, "full DSD64..DSD512 ladder accepted");
        if (!ok) Dump(got);
    }
    {
        // Non-adjacent rungs (64 and 256, skipping 128) are not a ladder.
        const auto got = Parse(MakeDevice(
            0x20, {{1, 2, 4, 32, {88200}, 0x01}, {2, 2, 4, 32, {352800}, 0x02}}));
        Check(got.empty(), "non-adjacent rungs (64,256) rejected");
        if (!got.empty()) Dump(got);
    }
    {
        // A single alt setting listing several rates is not a ladder: PCM alt
        // settings routinely advertise several rates in one FORMAT_TYPE_I.
        const auto got = Parse(MakeDevice(0x20, {{1, 2, 4, 32, {88200, 176400}, 0x01}}));
        Check(got.empty(), "one alt setting with {88200,176400} rejected (not a ladder)");
        if (!got.empty()) Dump(got);
    }
    {
        // The ladder is an interface property: rungs on *different* interfaces
        // must not combine into one.
        Blob b;
        b.Config(2);
        b.Interface(1, 1, 1, 0x20);
        b.Uac2Format(2, 4, 32, {88200});
        b.Endpoint(0x01);
        b.Interface(2, 1, 1, 0x20);
        b.Uac2Format(2, 4, 32, {176400});
        b.Endpoint(0x02);
        const auto got = Parse(b.Finish());
        Check(got.empty(), "rungs split across two interfaces do not form a ladder");
        if (!got.empty()) Dump(got);
    }

    // ---------------------------------------------------------------------
    // 5. Geometry that must never be reported.
    // ---------------------------------------------------------------------
    {
        const auto got = Parse(MakeDevice(0x20, {{1, 2, 4, 32, {384000}, 0x01}}));
        Check(got.empty(), "PCM 384 kHz / 32-bit rejected");
        if (!got.empty()) Dump(got);
    }
    {
        const auto got = Parse(MakeDevice(0x20, {{1, 1, 4, 32, {48000}, 0x01}}));
        Check(got.empty(), "48 kHz mono / 32-bit rejected (48 kHz DSD family excluded)");
        if (!got.empty()) Dump(got);
    }
    {
        // DSD_U16: the mapping succeeds (352800 * 16 / 44100 = 128) but the
        // policy never reports 2-byte subslots, mono or not.
        const auto stereo16 = Parse(MakeDevice(0x20, {{1, 2, 2, 32, {352800}, 0x01}}));
        Check(stereo16.empty(), "U16 subslot DSD128 rejected by policy");
        if (!stereo16.empty()) Dump(stereo16);
        const auto mono16 = Parse(MakeDevice(0x20, {{1, 1, 2, 32, {352800}, 0x01}}));
        Check(mono16.empty(), "mono U16 subslot rejected by policy");
        if (!mono16.empty()) Dump(mono16);
    }

    // ---------------------------------------------------------------------
    // 6. Endpoint filtering.
    // ---------------------------------------------------------------------
    {
        Blob b;
        b.Config(1);
        b.Interface(1, 1, 2, 0x20);
        b.Uac2Format(1, 4, 32, {88200});
        b.Endpoint(0x81);  // IN (feedback) first
        b.Endpoint(0x01);  // then the real OUT endpoint
        const auto got = Parse(b.Finish());
        const bool ok = got.size() == 1 && Matches(got[0], 1, 1, 0x01, 1, 88200, 64);
        Check(ok, "IN endpoint skipped, isochronous OUT selected");
        if (!ok) Dump(got);
    }
    {
        Blob b;
        b.Config(1);
        b.Interface(1, 1, 1, 0x20);
        b.Uac2Format(1, 4, 32, {88200});
        b.Endpoint(0x81);
        const auto got = Parse(b.Finish());
        Check(got.empty(), "IN-only alt setting rejected");
        if (!got.empty()) Dump(got);
    }
    {
        Blob b;
        b.Config(1);
        b.Interface(1, 1, 1, 0x20);
        b.Uac2Format(1, 4, 32, {88200});
        b.Endpoint(0x01, 0x02);  // bulk OUT
        const auto got = Parse(b.Finish());
        Check(got.empty(), "bulk OUT endpoint rejected (isochronous only)");
        if (!got.empty()) Dump(got);
    }
    {
        const auto got = Parse(MakeDevice(0x20, {{0, 1, 4, 32, {88200}, 0}}));
        Check(got.empty(), "alt setting 0 (no endpoint) rejected");
        if (!got.empty()) Dump(got);
    }
    {
        // A rate only counts as a ladder rung when it is streamable, so an
        // endpoint-less alt 0 cannot pair up with a real alt 1.
        Blob b;
        b.Config(1);
        b.Interface(1, 0, 0, 0x20);
        b.Uac2Format(2, 4, 32, {88200});
        b.Interface(1, 1, 1, 0x20);
        b.Uac2Format(2, 4, 32, {176400});
        b.Endpoint(0x01);
        const auto got = Parse(b.Finish());
        Check(got.empty(), "endpoint-less alt 0 does not provide ladder evidence");
        if (!got.empty()) Dump(got);
    }

    // ---------------------------------------------------------------------
    // 7. Interface class filtering.
    // ---------------------------------------------------------------------
    {
        Blob b;  // AudioControl interface (subclass 0x01) with a stray format
        b.Config(1);
        b.Interface(0, 0, 1, 0x20, 0x01, 0x01);
        b.Uac2Format(1, 4, 32, {88200});
        b.Endpoint(0x01);
        const auto got = Parse(b.Finish());
        Check(got.empty(), "AudioControl interface (subclass 0x01) ignored");
        if (!got.empty()) Dump(got);
    }
    {
        Blob b;  // vendor-specific interface
        b.Config(1);
        b.Interface(3, 0, 1, 0x20, 0xFF, 0x00);
        b.Uac2Format(1, 4, 32, {88200});
        b.Endpoint(0x01);
        const auto got = Parse(b.Finish());
        Check(got.empty(), "vendor-specific interface ignored");
        if (!got.empty()) Dump(got);
    }
    {
        // UAC1 (bInterfaceProtocol 0x00) uses the other FORMAT_TYPE_I layout.
        const auto mono = Parse(MakeDevice(0x00, {{1, 1, 4, 32, {88200}, 0x01}}));
        const bool ok = mono.size() == 1 && Matches(mono[0], 1, 1, 0x01, 1, 88200, 64);
        Check(ok, "UAC1-layout mono alt setting accepted");
        if (!ok) Dump(mono);

        const auto stereo = Parse(MakeDevice(0x00, {{1, 2, 4, 32, {88200}, 0x01}}));
        Check(stereo.empty(), "UAC1-layout stereo single-rate rejected");
        if (!stereo.empty()) Dump(stereo);
    }

    // ---------------------------------------------------------------------
    // 8. Quirk table path.
    // ---------------------------------------------------------------------
    {
        const std::vector<uint8_t> blob = MakeDevice(0x20, {{1, 2, 4, 32, {88200}, 0x01}});
        Check(Parse(blob, 0x1234, 0x5678).empty(),
              "unlisted VID/PID gets no quirk privileges");
        Check(!pulsr::IsDsdQuirkDevice(0x1234, 0x5678),
              "built-in quirk table is empty by default");

        const pulsr::DsdQuirkEntry table[] = {{0x1234, 0x5678}};
        const auto quirked = pulsr::ParseDsdAltSettingsWithQuirks(
            blob.data(), blob.size(), 0x1234, 0x5678, table, 1);
        const bool ok = quirked.size() == 1 && Matches(quirked[0], 1, 1, 0x01, 2, 88200, 64);
        Check(ok, "quirk-listed stereo single-rate accepted");
        if (!ok) Dump(quirked);

        const auto otherPid = pulsr::ParseDsdAltSettingsWithQuirks(
            blob.data(), blob.size(), 0x1234, 0x9999, table, 1);
        Check(otherPid.empty(), "quirk entry matches VID and PID together");

        const auto noTable = pulsr::ParseDsdAltSettingsWithQuirks(
            blob.data(), blob.size(), 0x1234, 0x5678, nullptr, 0);
        Check(noTable.empty(), "null quirk table behaves like an empty one");

        // A quirk row cannot turn an unmappable geometry into DSD.
        const std::vector<uint8_t> pcm = MakeDevice(0x20, {{1, 2, 4, 32, {384000}, 0x01}});
        const auto quirkedPcm = pulsr::ParseDsdAltSettingsWithQuirks(
            pcm.data(), pcm.size(), 0x1234, 0x5678, table, 1);
        Check(quirkedPcm.empty(), "quirk row does not rescue a non-DSD rate");
        if (!quirkedPcm.empty()) Dump(quirkedPcm);
    }

    // ---------------------------------------------------------------------
    // 9. Malformed / truncated input returns empty, never a partial answer.
    // ---------------------------------------------------------------------
    {
        const std::vector<uint8_t> good = MakeDevice(0x20, {{1, 1, 4, 32, {88200}, 0x01}});

        Check(pulsr::ParseDsdAltSettings(nullptr, 0, 0, 0).empty(), "null pointer with len 0");
        Check(pulsr::ParseDsdAltSettings(nullptr, 4096, 0, 0).empty(), "null pointer with len 4096");
        Check(Parse(std::vector<uint8_t>{}).empty(), "empty blob");

        std::vector<uint8_t> tooShort(good.begin(), good.begin() + 8);
        Check(Parse(tooShort).empty(), "short config descriptor rejected");

        std::vector<uint8_t> wrongType = good;
        wrongType[1] = 0x04;
        Check(Parse(wrongType).empty(), "non-configuration descriptor rejected");

        std::vector<uint8_t> shortConfig = good;
        shortConfig[0] = 4;
        Check(Parse(shortConfig).empty(), "config bLength < 9 rejected");

        std::vector<uint8_t> overlong = good;
        const int declared = static_cast<int>(overlong.size()) + 10;
        overlong[2] = static_cast<uint8_t>(declared & 0xFF);
        overlong[3] = static_cast<uint8_t>((declared >> 8) & 0xFF);
        Check(Parse(overlong).empty(), "wTotalLength beyond the buffer rejected");

        std::vector<uint8_t> configOnly = good;
        configOnly[2] = 9;
        configOnly[3] = 0;
        Check(Parse(configOnly).empty(), "configuration with no interfaces is empty");

        std::vector<uint8_t> zeroLength = good;
        zeroLength[9] = 0;  // first interface descriptor bLength
        Check(Parse(zeroLength).empty(), "bLength 0 rejected (no infinite walk)");

        std::vector<uint8_t> runsPastEnd = good;
        runsPastEnd[9] = 200;
        Check(Parse(runsPastEnd).empty(), "descriptor running past wTotalLength rejected");

        Check(Parse(std::vector<uint8_t>(64, 0xFF)).empty(), "0xFF-filled blob rejected");
    }
    {
        // FORMAT_TYPE_I whose tSamFreq[] does not fit in its own bLength.
        Blob b;
        b.Config(1);
        b.Interface(1, 1, 1, 0x20);
        b.Raw({10, 0x24, 0x02, 0x01, 4, 32, 2, 0x88, 0x58, 0x01});
        b.Endpoint(0x01);
        Check(Parse(b.Finish()).empty(), "truncated tSamFreq[] rejected");
    }
    {
        // FORMAT_TYPE header without bFormatType.
        Blob b;
        b.Config(1);
        b.Interface(1, 1, 1, 0x20);
        b.Raw({3, 0x24, 0x02});
        b.Endpoint(0x01);
        Check(Parse(b.Finish()).empty(), "CS descriptor shorter than its subtype rejected");
    }
    {
        // Endpoint descriptor shorter than 7 bytes.
        Blob b;
        b.Config(1);
        b.Interface(1, 1, 1, 0x20);
        b.Uac2Format(1, 4, 32, {88200});
        b.Raw({5, 0x05, 0x01, 0x05});
        Check(Parse(b.Finish()).empty(), "truncated endpoint descriptor rejected");
    }
    {
        // Bytes past wTotalLength are ignored, not treated as truncation.
        std::vector<uint8_t> padded = MakeDevice(0x20, {{1, 1, 4, 32, {88200}, 0x01}});
        padded.insert(padded.end(), 32, 0xFF);
        const auto got = Parse(padded);
        const bool ok = got.size() == 1 && Matches(got[0], 1, 1, 0x01, 1, 88200, 64);
        Check(ok, "trailing bytes past wTotalLength are ignored");
        if (!ok) Dump(got);
    }

    // ---------------------------------------------------------------------
    // 10. Fuzz-safety: prefix sweep and deterministic mutations.
    // ---------------------------------------------------------------------
    {
        const std::vector<uint8_t> base = MakeDevice(
            0x20, {{1, 2, 4, 32, {88200}, 0x01}, {2, 2, 4, 32, {176400}, 0x02}});
        bool invariants = true;
        for (size_t n = 0; n <= base.size(); ++n) {
            const auto got = pulsr::ParseDsdAltSettings(base.data(), n, 0x1234, 0x5678);
            for (const auto& s : got) {
                if (!InvariantsHold(s)) invariants = false;
            }
        }
        Check(invariants, "every truncated prefix parses safely");

        uint32_t state = 0x12345678u;
        auto next = [&state]() {
            state = state * 1664525u + 1013904223u;
            return state >> 16;
        };
        invariants = true;
        for (int iteration = 0; iteration < 2000; ++iteration) {
            std::vector<uint8_t> mutated = base;
            const int mutations = 1 + static_cast<int>(next() % 6);
            for (int m = 0; m < mutations; ++m) {
                const size_t index = static_cast<size_t>(next()) % mutated.size();
                mutated[index] = static_cast<uint8_t>(next());
            }
            const auto got = Parse(mutated);
            for (const auto& s : got) {
                if (!InvariantsHold(s)) invariants = false;
            }
        }
        Check(invariants, "2000 mutated blobs keep the result invariants");
    }

    // ---------------------------------------------------------------------
    // 11. Helper.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::DsdRatesFor({}).empty(), "DsdRatesFor(empty) is empty");
        std::vector<pulsr::DsdAltSetting> settings(3);
        settings[0].dsdRate = 128;
        settings[1].dsdRate = 64;
        settings[2].dsdRate = 0;
        const auto rates = pulsr::DsdRatesFor(settings);
        Check(rates.size() == 2 && rates[0] == 64 && rates[1] == 128,
              "DsdRatesFor sorts and drops rate 0");
    }

    // ---------------------------------------------------------------------
    // 12. Standard 6-byte UAC2 FORMAT_TYPE_I + AS_GENERAL TYPE_I_RAW_DATA.
    // ---------------------------------------------------------------------
    {
        // Standard hardware UAC2 DSD alt setting: AS_GENERAL with bmFormats =
        // TYPE_I_RAW_DATA (0x80000000 LE) and bNrChannels = 2, plus 6-byte
        // FORMAT_TYPE_I (subslot 4, bitResolution 32).
        Blob b;
        b.Config(1);
        b.Interface(1, 0, 0, 0x20);
        // Alt 1: PCM 6-byte FORMAT_TYPE_I (bmFormats = 0x00000001) -> ignored
        b.Interface(1, 1, 1, 0x20);
        b.Raw({16, 0x24, 0x01, 1, 0, 1, 0x01, 0x00, 0x00, 0x00, 2, 0x03, 0, 0, 0, 0});
        b.Raw({6, 0x24, 0x02, 0x01, 4, 32});
        b.Endpoint(0x01);
        // Alt 2: RAW_DATA 6-byte FORMAT_TYPE_I with 2-byte subslot -> rejected
        b.Interface(1, 2, 1, 0x20);
        b.Raw({16, 0x24, 0x01, 1, 0, 1, 0x00, 0x00, 0x00, 0x80, 2, 0x03, 0, 0, 0, 0});
        b.Raw({6, 0x24, 0x02, 0x01, 2, 16});
        b.Endpoint(0x01);
        // Alt 3: RAW_DATA 6-byte FORMAT_TYPE_I (4-byte, 32-bit, 2ch) -> DSD64..DSD512
        b.Interface(1, 3, 1, 0x20);
        b.Raw({16, 0x24, 0x01, 1, 0, 1, 0x00, 0x00, 0x00, 0x80, 2, 0x03, 0, 0, 0, 0});
        b.Raw({6, 0x24, 0x02, 0x01, 4, 32});
        b.Endpoint(0x01);
        const auto got = Parse(b.Finish());
        const auto rates = pulsr::DsdRatesFor(got);
        const bool ok = got.size() == 4 &&
                        Matches(got[0], 1, 3, 0x01, 2, 88200, 64) &&
                        Matches(got[3], 1, 3, 0x01, 2, 705600, 512) &&
                        rates.size() == 4;
        Check(ok, "standard 6-byte UAC2 FORMAT_TYPE_I TYPE_I_RAW_DATA emits DSD64..DSD512");
        if (!ok) Dump(got);
    }

    if (gFailures == 0) {
        std::cout << "[TEST] UAC2 native-DSD probe: all checks passed." << std::endl;
        return 0;
    }
    std::cout << "[TEST] UAC2 native-DSD probe: " << gFailures << " failure(s)." << std::endl;
    return 1;
}
