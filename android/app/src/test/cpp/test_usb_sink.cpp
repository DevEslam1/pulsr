// android/app/src/test/cpp/test_usb_sink.cpp
//
// The UAC2 sink is unvalidated against physical hardware (no device/AVD here),
// so the spec-dependent math that WOULD run on a device is pinned down on the
// host instead: descriptor rate parsing, async-feedback decode, and the
// fractional samples-per-packet accumulator. These are the three pieces whose
// correctness does not depend on usbfs ioctls, so a bug in them is catchable
// without a DAC. The pure helpers are exercised directly; no sink instance is
// opened (Open needs a real fd).
#include "../../main/cpp/UsbAudioSink.h"

#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

using pulsr::UsbAudioSink;

namespace {

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

// Appends a 9-byte standard INTERFACE descriptor.
void pushInterface(std::vector<uint8_t>& d, uint8_t ifaceNum, uint8_t alt,
                   uint8_t klass, uint8_t subclass) {
    d.push_back(9);          // bLength
    d.push_back(0x04);       // bDescriptorType = INTERFACE
    d.push_back(ifaceNum);   // bInterfaceNumber
    d.push_back(alt);        // bAlternateSetting
    d.push_back(0);          // bNumEndpoints
    d.push_back(klass);      // bInterfaceClass (0x01 = Audio)
    d.push_back(subclass);   // bInterfaceSubClass (0x02 = AudioStreaming)
    d.push_back(0);          // bInterfaceProtocol
    d.push_back(0);          // iInterface
}

void push3(std::vector<uint8_t>& d, int v) {
    d.push_back(static_cast<uint8_t>(v & 0xFF));
    d.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    d.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
}

// Appends a UAC1 FORMAT_TYPE_I CS_INTERFACE descriptor.
// If discrete is empty, emits a continuous [lo,hi] range.
void pushFormatType(std::vector<uint8_t>& d, const std::vector<int>& discrete,
                    int lo = 0, int hi = 0) {
    const uint8_t freqType = discrete.empty() ? 0 : static_cast<uint8_t>(discrete.size());
    const int body = 8 + 3 * (discrete.empty() ? 2 : static_cast<int>(discrete.size()));
    d.push_back(static_cast<uint8_t>(body)); // bLength
    d.push_back(0x24);       // bDescriptorType = CS_INTERFACE
    d.push_back(0x02);       // bDescriptorSubtype = FORMAT_TYPE
    d.push_back(0x01);       // bFormatType = FORMAT_TYPE_I
    d.push_back(2);          // bNrChannels
    d.push_back(3);          // bSubframeSize
    d.push_back(24);         // bBitResolution
    d.push_back(freqType);   // bSamFreqType
    if (discrete.empty()) {
        push3(d, lo);
        push3(d, hi);
    } else {
        for (int r : discrete) push3(d, r);
    }
}

bool contains(const std::vector<int>& v, int x) {
    for (int e : v) if (e == x) return true;
    return false;
}

} // namespace

int main() {
    std::cout << "[TEST] USB UAC2 sink host-verifiable math..." << std::endl;

    // ---- Descriptor rate parsing -----------------------------------------
    {
        // Discrete 44100 + 48000 on an AudioStreaming interface.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        pushFormatType(d, {44100, 48000});
        auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(rates.size() == 2 && rates[0] == 44100 && rates[1] == 48000,
              "discrete FORMAT_TYPE_I must yield sorted {44100,48000}");
    }
    {
        // Continuous [44100,96000] expands to the standard rates in range.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        pushFormatType(d, {}, 44100, 96000);
        auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(rates.size() == 4 && contains(rates, 44100) && contains(rates, 48000) &&
                  contains(rates, 88200) && contains(rates, 96000),
              "continuous range must expand to {44100,48000,88200,96000}");
        check(!contains(rates, 176400), "continuous range must not exceed upper bound");
    }
    {
        // targetInterface filters: rates on interface 2 must be ignored when
        // querying interface 1.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x01, 0x02);
        pushFormatType(d, {44100});
        pushInterface(d, 2, 1, 0x01, 0x02);
        pushFormatType(d, {192000});
        auto only1 = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size(), 1);
        check(only1.size() == 1 && only1[0] == 44100,
              "targetInterface=1 must return only interface 1's rates");
        auto only2 = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size(), 2);
        check(only2.size() == 1 && only2[0] == 192000,
              "targetInterface=2 must return only interface 2's rates");
        auto all = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(all.size() == 2 && contains(all, 44100) && contains(all, 192000),
              "no targetInterface must merge every AudioStreaming interface");
    }
    {
        // A non-AudioStreaming interface (class != 0x01) must be skipped.
        std::vector<uint8_t> d;
        pushInterface(d, 1, 1, 0x08, 0x06); // mass storage, not audio
        pushFormatType(d, {48000});
        auto rates = UsbAudioSink::ParseSupportedRatesFromDescriptors(d.data(), d.size());
        check(rates.empty(), "non-audio interface must yield no rates");
    }
    {
        // Malformed input must not crash or invent rates.
        check(UsbAudioSink::ParseSupportedRatesFromDescriptors(nullptr, 0).empty(),
              "null descriptor must be empty");
        const uint8_t tiny[4] = {0x09, 0x04, 0x01, 0x01};
        check(UsbAudioSink::ParseSupportedRatesFromDescriptors(tiny, sizeof(tiny)).empty(),
              "descriptor shorter than 8 bytes must be empty");
        // bLength=0 would loop forever if not guarded; ensure forward progress.
        std::vector<uint8_t> zero(64, 0);
        check(UsbAudioSink::ParseSupportedRatesFromDescriptors(zero.data(), zero.size()).empty(),
              "all-zero descriptor must terminate and yield no rates");
    }

    // ---- Async-feedback decode -------------------------------------------
    {
        // 4-byte Q16.16 high-speed: nominal 48000 => 6.0 samples/microframe.
        // v = 6.0 * 65536 = 0x00060000 (LE).
        const uint8_t nom[4] = {0x00, 0x00, 0x06, 0x00};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nom, 4, 48000) == 48000,
              "HS nominal feedback must decode to the nominal rate");

        // +50 ppm: ratio 1.00005 -> 48002 (inside the +/-0.1% clamp).
        const uint32_t vUp = static_cast<uint32_t>(6.0 * 1.00005 * 65536.0 + 0.5);
        uint8_t up[4] = {static_cast<uint8_t>(vUp & 0xFF), static_cast<uint8_t>((vUp >> 8) & 0xFF),
                         static_cast<uint8_t>((vUp >> 16) & 0xFF), static_cast<uint8_t>((vUp >> 24) & 0xFF)};
        const int gotUp = UsbAudioSink::DecodeFeedbackRatePerSec(up, 4, 48000);
        check(gotUp > 48000 && gotUp <= 48048,
              "small positive feedback must nudge the rate up within the clamp");

        // ratio 1.05 is accepted by the +/-10% window but must clamp to +0.1%.
        const uint32_t vBig = static_cast<uint32_t>(6.0 * 1.05 * 65536.0 + 0.5);
        uint8_t big[4] = {static_cast<uint8_t>(vBig & 0xFF), static_cast<uint8_t>((vBig >> 8) & 0xFF),
                          static_cast<uint8_t>((vBig >> 16) & 0xFF), static_cast<uint8_t>((vBig >> 24) & 0xFF)};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(big, 4, 48000) == 48048,
              "in-window but out-of-clamp feedback must clamp to +0.1%");

        // ratio 1.5 is outside +/-10% -> reject (return 0).
        const uint32_t vRej = static_cast<uint32_t>(6.0 * 1.5 * 65536.0 + 0.5);
        uint8_t rej[4] = {static_cast<uint8_t>(vRej & 0xFF), static_cast<uint8_t>((vRej >> 8) & 0xFF),
                          static_cast<uint8_t>((vRej >> 16) & 0xFF), static_cast<uint8_t>((vRej >> 24) & 0xFF)};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(rej, 4, 48000) == 0,
              "implausible feedback (>+10%) must be rejected");

        const uint8_t zero[4] = {0, 0, 0, 0};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(zero, 4, 48000) == 0,
              "zero feedback sample must be rejected");
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nullptr, 4, 48000) == 0,
              "null feedback must be rejected");
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nom, 4, 0) == 0,
              "non-positive nominal rate must be rejected");
    }
    {
        // 3-byte Q10.14 full-speed: nominal 48000 => 48.0 samples/frame.
        // v = 48.0 * 16384 = 0x0C0000 (LE, 3 bytes).
        const uint8_t nom[3] = {0x00, 0x00, 0x0C};
        check(UsbAudioSink::DecodeFeedbackRatePerSec(nom, 3, 48000) == 48000,
              "FS nominal feedback must decode to the nominal rate");

        // 44100 => 44.1 samples/frame => v = 44.1*16384 = 722534.4 -> 722534.
        const uint32_t v44 = 722534;
        const uint8_t f44[3] = {static_cast<uint8_t>(v44 & 0xFF), static_cast<uint8_t>((v44 >> 8) & 0xFF),
                                static_cast<uint8_t>((v44 >> 16) & 0xFF)};
        const int got44 = UsbAudioSink::DecodeFeedbackRatePerSec(f44, 3, 44100);
        check(got44 >= 44055 && got44 <= 44145, "FS 44100 feedback must decode near nominal");
    }

    // ---- Fractional packet sizing ----------------------------------------
    {
        // 48000 is an integer number of frames per 1 ms packet: always 48.
        uint32_t acc = 0;
        const int maxF = (48000 + 999) / 1000 + 1; // 49
        bool all48 = true;
        for (int i = 0; i < 100; ++i) {
            if (UsbAudioSink::NextPacketFrames(acc, 48000, maxF) != 48) all48 = false;
        }
        check(all48, "48000 must emit exactly 48 frames per 1 ms packet");
        check(acc == 0, "48000 must leave zero fractional remainder");
    }
    {
        // 44100 emits 44/45 frames so every 10 packets sum to exactly 441.
        uint32_t acc = 0;
        const int maxF = (44100 + 999) / 1000 + 1; // 45
        int sum = 0;
        bool in4445 = true;
        for (int i = 0; i < 10; ++i) {
            const int f = UsbAudioSink::NextPacketFrames(acc, 44100, maxF);
            if (f != 44 && f != 45) in4445 = false;
            sum += f;
        }
        check(in4445, "44100 packets must be 44 or 45 frames");
        check(sum == 441, "44100 must emit exactly 441 frames per 10 packets");
        // Over 1000 packets the accumulator must produce exactly 44100 frames.
        acc = 0;
        long total = 0;
        for (int i = 0; i < 1000; ++i) total += UsbAudioSink::NextPacketFrames(acc, 44100, maxF);
        check(total == 44100, "44100 must emit exactly 44100 frames per 1000 packets");
    }
    {
        // The clamp caps a packet so feedback can never overflow the URB buffer.
        uint32_t acc = 0;
        const int f = UsbAudioSink::NextPacketFrames(acc, 48000, 10);
        check(f == 10, "NextPacketFrames must clamp to maxFramesPerPacket");
        check(acc == 0, "clamp must still consume the whole 1 ms remainder");
    }

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " USB sink check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB descriptor parsing, feedback decode, and packet sizing verified."
              << std::endl;
    return 0;
}
