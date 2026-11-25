// android/app/src/test/cpp/test_usb_dsd_path.cpp
//
// Host coverage for the native (DSD_U32) USB producer path. No DAC is involved:
// the sink's ring and packet filler are driven directly, exactly like
// test_usb_sink.cpp does for the PCM path, and the pieces that only a device can
// answer (usbfs claim, descriptor I/O, real URB completions) stay out of scope.
//
// What is pinned here:
//   * stream-shape admission, both directions of the PCM/DSD matrix, including a
//     failed Open never leaving the DSD latch published;
//   * packing integration - a known 1-bit payload lands in the expected 32-bit
//     words, LSB-first, with a zero-padded trailing partial word;
//   * ordering across accepted and refused blocks (all-or-nothing like WritePcm);
//   * PCM producer APIs refused while DSD is live, and WriteDsd refused in PCM;
//   * the DC-neutral DSD gap pattern (alternating 0x69/0x96, 50 % bit density);
//   * the 1 MiB per-call bound, exactly at and one byte past the limit;
//   * IsDsdActive() across prepare/close and across a failed Open, plus the
//     BitPerfect-shaped clock-domain derivation.
#include "../../main/cpp/UsbAudioSink.h"
#include "../../main/cpp/DsdNativePacker.h"
#include "../../main/cpp/Uac2Descriptors.h"
#include "../../main/cpp/UsbClockDomain.h"

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

namespace pulsr {
// Same friend-of-the-sink shape test_usb_sink.cpp uses: no production API is
// widened just for tests, and the PCM suite keeps its own copy of the harness.
struct UsbAudioSinkTestAccess {
    static void reset(UsbAudioSink& sink) {
        sink.Close();  // joins/clears any previous prepared state
        sink.renderMode_ = 0;
        sink.dsdMode_.store(false);
        sink.dsdSilencePhase_ = UsbAudioSink::kDsdSilenceByteA;
        sink.ring_.clear();
        sink.ringRawDepth_.clear();
        sink.ringFrameMask_ = 0;
        sink.ringRead_.store(0);
        sink.ringWrite_.store(0);
        sink.underrunCount_.store(0);
        sink.overrunCount_.store(0);
        sink.channelMismatchFrames_.store(0);
        sink.producerOwner_.store(0);
        sink.producerRawDepth_.store(0);
        sink.bitPerfectEligible_.store(false);
        sink.bitPerfectDisqualified_.store(false);
        sink.lastError_.store(0);
        sink.exclusive_.store(false);
        sink.active_.store(false);
        sink.writerGate_.store(0);
    }

    // A live native-DSD stream as Open() would have left it, without usbfs.
    // Slots are pre-filled with 0xAA so anything the sink did not write shows up.
    static void prepareDsd(UsbAudioSink& sink, size_t ringFrames = 1024) {
        reset(sink);
        sink.renderMode_ = static_cast<int>(UsbRenderMode::DsdNative);
        sink.dsdMode_.store(true);
        sink.sampleRate_ = 88200;   // DSD64 at DSD_U32
        sink.channels_ = 2;
        sink.bytesPerSample_ = 4;
        sink.validBitDepth_ = 32;
        sink.ring_.assign(ringFrames * 8, 0xAA);
        sink.ringRawDepth_.assign(ringFrames, 0);
        sink.ringFrameMask_ = ringFrames - 1;
        sink.exclusive_.store(true);
        sink.active_.store(true);
    }

    // A live 32-bit PCM stream, for the "vice versa" half of the matrix.
    static void preparePcm(UsbAudioSink& sink, size_t ringFrames = 1024) {
        reset(sink);
        sink.renderMode_ = static_cast<int>(UsbRenderMode::BestEffort);
        sink.dsdMode_.store(false);
        sink.sampleRate_ = 48000;
        sink.channels_ = 2;
        sink.bytesPerSample_ = 4;
        sink.validBitDepth_ = 32;
        sink.ring_.assign(ringFrames * 8, 0xAA);
        sink.ringRawDepth_.assign(ringFrames, 0);
        sink.ringFrameMask_ = ringFrames - 1;
        sink.exclusive_.store(true);
        sink.active_.store(true);
    }

    // One packet through the real filler (the worker's own entry point).
    static size_t fill(UsbAudioSink& sink, uint8_t* dst, int frames, int& depth,
                       uint64_t& epoch) {
        size_t read = sink.ringRead_.load(std::memory_order_relaxed);
        const size_t written = sink.fillPacketFromRing(dst, frames, read, depth, epoch);
        sink.ringRead_.store(read, std::memory_order_release);
        return written;
    }
    // Ring slot bytes in logical order (wraps), as the worker would read them.
    static std::vector<uint8_t> slotBytes(UsbAudioSink& sink, size_t frame, size_t frames) {
        const size_t frameBytes =
            static_cast<size_t>(sink.channels_) * static_cast<size_t>(sink.bytesPerSample_);
        std::vector<uint8_t> out(frames * frameBytes);
        for (size_t f = 0; f < frames; ++f) {
            const size_t slot = (frame + f) & sink.ringFrameMask_;
            std::memcpy(out.data() + f * frameBytes, sink.ring_.data() + slot * frameBytes,
                        frameBytes);
        }
        return out;
    }
    static size_t writeCount(UsbAudioSink& sink) { return sink.ringWrite_.load(); }
    static uint64_t overruns(UsbAudioSink& sink) { return sink.overrunCount_.load(); }
    static uint64_t underruns(UsbAudioSink& sink) { return sink.underrunCount_.load(); }
    static int lastError(UsbAudioSink& sink) { return sink.lastError_.load(); }
    static bool eligible(UsbAudioSink& sink) { return sink.bitPerfectEligible_.load(); }
    static bool disqualified(UsbAudioSink& sink) { return sink.bitPerfectDisqualified_.load(); }
    static uint8_t silencePhase(UsbAudioSink& sink) { return sink.dsdSilencePhase_; }
    // What the worker does when it self-exits on a device fault: active_ drops
    // but the mode/ownership latches stay until control teardown.
    static void markWorkerExited(UsbAudioSink& sink) {
        sink.active_.store(false);
    }
};
}  // namespace pulsr

namespace {

using pulsr::UsbAudioSink;
using pulsr::UsbAudioSinkTestAccess;
using pulsr::UsbRenderMode;
using pulsr::UsbStreamResult;

int gFailures = 0;

void check(bool ok, const char* what) {
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

// Fills a DSD payload where every byte is distinct, so a byte-order, channel-swap
// or bit-reversal bug is visible instead of hiding inside a symmetric pattern.
std::vector<uint8_t> rampPayload(int bytes, uint8_t seed) {
    std::vector<uint8_t> out(static_cast<size_t>(bytes));
    for (int i = 0; i < bytes; ++i) {
        out[static_cast<size_t>(i)] = static_cast<uint8_t>(seed + i * 0x11);
    }
    return out;
}

int popcount(uint8_t v) {
    int n = 0;
    for (int b = 0; b < 8; ++b) n += (v >> b) & 1;
    return n;
}

}  // namespace

int main() {
    std::cout << "[TEST] USB native-DSD (DSD_U32) path..." << std::endl;
    auto& sink = UsbAudioSink::instance();

    // ---- 1. Stream-shape admission matrix ---------------------------------
    // "PCM geometry rejected in DSD mode": a 16/24-bit, 3-byte or non-stereo
    // request may not start a DSD stream. "Vice versa": the DSD-only rate ladder
    // is not a PCM admission rule, and the PCM producer APIs (and WriteDsd's
    // reverse) are covered in section 4.
    {
        using pulsr::UsbAudioSink;
        // Accepted: exactly the four U32 rungs, stereo, 4-byte, 32 valid bits.
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 88200) ==
                  UsbStreamResult::Ok, "DSD64/U32 (88200) must be admitted");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 176400) ==
                  UsbStreamResult::Ok, "DSD128/U32 (176400) must be admitted");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 352800) ==
                  UsbStreamResult::Ok, "DSD256/U32 (352800) must be admitted");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 705600) ==
                  UsbStreamResult::Ok, "DSD512/U32 (705600) must be admitted");
        // 0 valid bits means "the whole container", i.e. 32 here.
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 0, 88200) ==
                  UsbStreamResult::Ok, "DSD64 with implicit 32 valid bits must be admitted");
        // PCM geometry in a DSD mode.
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 2, 16, 88200) ==
                  UsbStreamResult::InvalidArgs, "16-bit geometry must be refused in DSD mode");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 3, 24, 88200) ==
                  UsbStreamResult::InvalidArgs, "24-in-3 geometry must be refused in DSD mode");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 24, 88200) ==
                  UsbStreamResult::InvalidArgs, "24 valid bits in a 4-byte slot must be refused");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 1, 4, 32, 88200) ==
                  UsbStreamResult::InvalidArgs, "mono must be refused in DSD mode");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 6, 4, 32, 88200) ==
                  UsbStreamResult::InvalidArgs, "6 channels must be refused in DSD mode");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 5, 32, 88200) ==
                  UsbStreamResult::InvalidArgs, "5-byte subslot must be refused in DSD mode");
        // Right geometry, rate off the DSD ladder: the rate is what is wrong.
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 48000) ==
                  UsbStreamResult::RateUnsupported, "48 kHz must be RateUnsupported in DSD mode");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 44100) ==
                  UsbStreamResult::RateUnsupported, "44.1 kHz must be RateUnsupported in DSD mode");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::DsdNative, 2, 4, 32, 768000) ==
                  UsbStreamResult::RateUnsupported, "768 kHz must be RateUnsupported in DSD mode");
        // PCM modes keep their own geometry and rate rules.
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::BestEffort, 2, 2, 16, 44100) ==
                  UsbStreamResult::Ok, "S16 must stay admissible for PCM");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::BitPerfectPull, 2, 4, 32, 352800) ==
                  UsbStreamResult::Ok, "S32 must stay admissible for PCM");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::BestEffort, 2, 4, 20, 48000) ==
                  UsbStreamResult::InvalidArgs, "20 valid bits must be refused for PCM");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::BestEffort, 0, 2, 16, 48000) ==
                  UsbStreamResult::InvalidArgs, "zero channels must be refused for PCM");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::BestEffort, 9, 2, 16, 48000) ==
                  UsbStreamResult::InvalidArgs, "9 channels must be refused for PCM");
        check(UsbAudioSink::CheckStreamShape(UsbRenderMode::BestEffort, 2, 2, 16, 88201) ==
                  UsbStreamResult::RateUnsupported, "off-list rate must be RateUnsupported");
        check(UsbAudioSink::CheckStreamShape(static_cast<UsbRenderMode>(7), 2, 4, 32, 88200) ==
                  UsbStreamResult::InvalidArgs, "unknown render mode must be InvalidArgs");
    }

    // ---- 2. Open() honours the same matrix, and fails closed --------------
    // The host has no usbfs, so a shape-accepted Open always ends at the platform
    // gate (ENOSYS -> InvalidArgs). What is verified here is that the DSD-only
    // rejections happen *before* any device access (EINVAL) and that a failed
    // Open never publishes the DSD latch.
    {
        UsbAudioSinkTestAccess::reset(sink);
#if defined(__linux__) || defined(__ANDROID__)
        constexpr int kPlatformGateErrno = EINVAL;
#else
        constexpr int kPlatformGateErrno = ENOSYS;
#endif
        check(sink.Open(9, 1, 1, 1, 88200, 2, 4, 32, false, 3) == UsbStreamResult::InvalidArgs &&
                  UsbAudioSinkTestAccess::lastError(sink) == kPlatformGateErrno,
              "host Open must reach the platform gate for an admitted DSD shape");
        check(!sink.IsDsdActive(), "a failed Open must never publish IsDsdActive()");
        check(sink.Open(9, 1, 1, 1, 48000, 2, 4, 32, false, 3) == UsbStreamResult::RateUnsupported &&
                  UsbAudioSinkTestAccess::lastError(sink) == EINVAL,
              "DSD Open at 48 kHz must be refused before touching the device");
        check(sink.Open(9, 1, 1, 1, 88200, 2, 2, 16, false, 3) == UsbStreamResult::InvalidArgs &&
                  UsbAudioSinkTestAccess::lastError(sink) == EINVAL,
              "16-bit DSD Open must be refused before touching the device");
        check(sink.Open(9, 1, 1, 1, 88200, 1, 4, 32, false, 3) == UsbStreamResult::InvalidArgs &&
                  UsbAudioSinkTestAccess::lastError(sink) == EINVAL,
              "mono DSD Open must be refused before touching the device");
        check(!sink.IsDsdActive(), "refused DSD Opens must leave IsDsdActive() false");
    }

    // ---- 3. Packer integration --------------------------------------------
    // A known payload must land as 4-byte little-endian words, left channel then
    // right channel per frame, first DSD bit in the word's LSB.
    {
        UsbAudioSinkTestAccess::prepareDsd(sink);
        const auto left = rampPayload(8, 0x01);    // 01 12 23 34 45 56 67 78
        const auto right = rampPayload(8, 0x81);   // 81 92 A3 B4 C5 D6 E7 F8
        check(sink.WriteDsd(left.data(), right.data(), 8, 77),
              "WriteDsd must accept a full-word stereo block");
        check(UsbAudioSinkTestAccess::writeCount(sink) == 2,
              "8 DSD bytes per channel must be 2 wire frames");
        uint8_t packet[16] = {0};
        int depth = -1;
        uint64_t epoch = 0;
        const size_t got = UsbAudioSinkTestAccess::fill(sink, packet, 2, depth, epoch);
        check(got == 16, "two DSD frames must fill 16 wire bytes");
        const uint8_t expected[16] = {
            0x01, 0x12, 0x23, 0x34, 0x81, 0x92, 0xA3, 0xB4,   // frame 0: L then R
            0x45, 0x56, 0x67, 0x78, 0xC5, 0xD6, 0xE7, 0xF8,   // frame 1: L then R
        };
        check(std::memcmp(packet, expected, sizeof(expected)) == 0,
              "DSD payload must be copied word-for-word, LSB-first, no dither/gain");
        check(depth == 32, "a DSD packet must report raw 32-bit payload depth");
        check(UsbAudioSinkTestAccess::eligible(sink),
              "a full DSD packet must earn the BitPerfect-shaped eligibility flag");

        // The packer itself: one set bit stays in the LSB of the first word, and a
        // partial word is padded on the high side instead of sign-extended.
        uint8_t words[8] = {0};
        const uint8_t oneBit[4] = {0x01, 0x00, 0x00, 0x00};
        check(pulsr::PackDsdBitsToWords(oneBit, 4, words, 8, 4) == 4 &&
                  words[0] == 0x01 && words[1] == 0 && words[2] == 0 && words[3] == 0,
              "LSB-first: the first DSD bit must be bit 0 of the first word");

        // A trailing partial word: 6 bytes -> 2 words, the second zero-padded.
        UsbAudioSinkTestAccess::prepareDsd(sink);
        const uint8_t tail[6] = {0xA1, 0xA2, 0xA3, 0xA4, 0xB1, 0xB2};
        const uint8_t tailR[6] = {0x11, 0x12, 0x13, 0x14, 0x15, 0x16};
        check(sink.WriteDsd(tail, tailR, 6, 78),
              "WriteDsd must accept a payload with a partial trailing word");
        check(UsbAudioSinkTestAccess::writeCount(sink) == 2,
              "6 DSD bytes per channel must still be 2 whole words");
        uint8_t partial[16] = {0};
        check(UsbAudioSinkTestAccess::fill(sink, partial, 2, depth, epoch) == 16, "partial-word packet length");
        const uint8_t expectedTail[16] = {
            0xA1, 0xA2, 0xA3, 0xA4, 0x11, 0x12, 0x13, 0x14,
            0xB1, 0xB2, 0x00, 0x00, 0x15, 0x16, 0x00, 0x00,
        };
        check(std::memcmp(partial, expectedTail, sizeof(expectedTail)) == 0,
              "a partial trailing word must be zero-padded on its high side");
    }

    // ---- 4. Ordering, backpressure and the PCM/DSD API exclusion ----------
    {
        UsbAudioSinkTestAccess::prepareDsd(sink, 64);
        const uint8_t a[4] = {0x01, 0x00, 0x00, 0x00};
        const uint8_t b[4] = {0x02, 0x00, 0x00, 0x00};
        const uint8_t c[4] = {0x03, 0x00, 0x00, 0x00};
        const uint8_t r[4] = {0xF0, 0x00, 0x00, 0x00};
        check(sink.WriteDsd(a, r, 4, 80) && sink.WriteDsd(b, r, 4, 80) && sink.WriteDsd(c, r, 4, 80),
              "three single-frame DSD writes must be accepted in order");
        auto slots = UsbAudioSinkTestAccess::slotBytes(sink, 0, 3);
        check(slots[0] == 0x01 && slots[8] == 0x02 && slots[16] == 0x03,
              "accepted DSD blocks must keep producer order in the ring");

        // Fill the ring exactly (one slot stays free as the full/empty marker),
        // then prove the next block is refused whole.
        std::vector<uint8_t> bulk(static_cast<size_t>(60) * 4, 0x5A);
        std::vector<uint8_t> bulkR(static_cast<size_t>(60) * 4, 0xA5);
        check(sink.WriteDsd(bulk.data(), bulkR.data(), 60 * 4, 80),
              "the remaining ring space must accept exactly its free frames");
        const size_t before = UsbAudioSinkTestAccess::writeCount(sink);
        const uint64_t overrunsBefore = UsbAudioSinkTestAccess::overruns(sink);
        check(!sink.WriteDsd(c, r, 4, 80), "a DSD block that does not fit must be refused");
        check(UsbAudioSinkTestAccess::writeCount(sink) == before,
              "a refused DSD block must not advance the ring write cursor");
        check(UsbAudioSinkTestAccess::lastError(sink) == ENOSPC,
              "a refused DSD block must report ENOSPC");
        check(UsbAudioSinkTestAccess::overruns(sink) == overrunsBefore + 1,
              "a refused DSD block must be counted as an overrun");

        // Make room, then prove ordering survives the refusal.
        uint8_t drain[8] = {0};
        int depth = -1;
        uint64_t epoch = 0;
        UsbAudioSinkTestAccess::fill(sink, drain, 1, depth, epoch);
        const uint8_t d[4] = {0x04, 0x00, 0x00, 0x00};
        check(sink.WriteDsd(d, r, 4, 80), "a DSD write after a refusal must be accepted");
        slots = UsbAudioSinkTestAccess::slotBytes(sink, 63, 1);
        check(slots[0] == 0x04, "the block after a refusal must land contiguously");

        // PCM producer APIs must refuse while DSD is live, without touching the ring.
        const size_t pcmWritesBefore = UsbAudioSinkTestAccess::writeCount(sink);
        const float floats[8] = {0.25f, -0.25f, 0.5f, -0.5f, 0.0f, 0.0f, 0.0f, 0.0f};
        check(!sink.WriteInterleaved(floats, 4, 2, 88200, 80),
              "WriteInterleaved must be refused in DSD mode");
        check(UsbAudioSinkTestAccess::lastError(sink) == ENOTSUP,
              "a PCM write in DSD mode must report ENOTSUP");
        uint8_t pcm[32] = {0};
        check(!sink.WritePcm(pcm, 4, 2, 32, 88200, 80), "WritePcm must be refused in DSD mode");
        check(UsbAudioSinkTestAccess::writeCount(sink) == pcmWritesBefore,
              "refused PCM writes must not alter the DSD ring");

        // Vice versa: WriteDsd must be refused by a live PCM stream.
        UsbAudioSinkTestAccess::preparePcm(sink);
        const size_t pcmCount = UsbAudioSinkTestAccess::writeCount(sink);
        check(!sink.WriteDsd(a, r, 4, 81), "WriteDsd must be refused in every PCM mode");
        check(UsbAudioSinkTestAccess::lastError(sink) == ENOTSUP,
              "WriteDsd in a PCM mode must report ENOTSUP");
        check(UsbAudioSinkTestAccess::writeCount(sink) == pcmCount,
              "a refused WriteDsd must not alter a PCM ring");
        check(sink.WritePcm(pcm, 4, 2, 32, 48000, 81), "the same sink must still accept PCM");
    }

    // ---- 5. DC-neutral DSD silence ----------------------------------------
    {
        uint8_t bytes[16] = {0};
        uint8_t phase = UsbAudioSink::FillDsdSilence(
            bytes, 16, UsbAudioSink::kDsdSilenceByteA);
        bool alternating = true;
        for (int i = 0; i < 16; ++i) {
            const uint8_t want = (i % 2 == 0) ? 0x69 : 0x96;
            alternating = alternating && bytes[i] == want;
        }
        check(alternating, "DSD silence must alternate 0x69 / 0x96 byte by byte");
        check(phase == UsbAudioSink::kDsdSilenceByteA,
              "an even-length fill must hand back the same phase");
        check(UsbAudioSink::FillDsdSilence(bytes, 7, UsbAudioSink::kDsdSilenceByteA) ==
                  UsbAudioSink::kDsdSilenceByteB,
              "an odd-length fill must flip the phase");
        check(UsbAudioSink::FillDsdSilence(nullptr, 16, UsbAudioSink::kDsdSilenceByteA) ==
                  UsbAudioSink::kDsdSilenceByteA,
              "a null buffer must be a no-op");

        // 50 % bit density per byte, hence per 32-bit word: zero DC after the
        // DAC's low-pass. This is the whole point of 0x69/0x96.
        std::vector<uint8_t> longFill(4096);
        UsbAudioSink::FillDsdSilence(longFill.data(), static_cast<int>(longFill.size()),
                                     UsbAudioSink::kDsdSilenceByteA);
        int ones = 0;
        for (uint8_t v : longFill) ones += popcount(v);
        check(ones == static_cast<int>(longFill.size()) * 4,
              "every DSD silence byte must carry exactly four of eight bits");
        bool wordsBalanced = true;
        for (size_t i = 0; i + 3 < longFill.size(); i += 4) {
            wordsBalanced = wordsBalanced &&
                popcount(longFill[i]) + popcount(longFill[i + 1]) +
                popcount(longFill[i + 2]) + popcount(longFill[i + 3]) == 16;
        }
        check(wordsBalanced, "every 32-bit silence word must be exactly half ones");

        // The real gap path: an empty DSD ring must emit the pattern, not zeroes,
        // and must not leave the stream claiming bit-perfect.
        UsbAudioSinkTestAccess::prepareDsd(sink);
        uint8_t packet[16] = {0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC,
                              0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC};
        int depth = -1;
        uint64_t epoch = 0;
        check(UsbAudioSinkTestAccess::fill(sink, packet, 2, depth, epoch) == 16, "gap packet length");
        const uint8_t expectedGap[16] = {
            0x69, 0x96, 0x69, 0x96, 0x69, 0x96, 0x69, 0x96,
            0x69, 0x96, 0x69, 0x96, 0x69, 0x96, 0x69, 0x96,
        };
        check(std::memcmp(packet, expectedGap, sizeof(expectedGap)) == 0,
              "an underrun must emit DSD silence, never PCM zeroes");
        check(UsbAudioSinkTestAccess::underruns(sink) == 1, "the gap must be counted as an underrun");
        check(depth == 32, "a DSD gap still carries raw 32-bit DSD payload");
        check(UsbAudioSinkTestAccess::disqualified(sink) &&
                  !UsbAudioSinkTestAccess::eligible(sink),
              "a DSD gap must disqualify the session from bit-perfect claims");
    }

    // ---- 6. 1 MiB per-call bound ------------------------------------------
    {
        // 262 144 frames + slack: exactly the largest block the bound permits.
        UsbAudioSinkTestAccess::prepareDsd(sink, 524288);
        check(UsbAudioSink::kMaxDsdBytesPerCall == 1024 * 1024,
              "the per-call bound is 1 MiB per channel");
        std::vector<uint8_t> big(static_cast<size_t>(UsbAudioSink::kMaxDsdBytesPerCall), 0x3C);
        std::vector<uint8_t> bigR(static_cast<size_t>(UsbAudioSink::kMaxDsdBytesPerCall), 0xC3);
        check(sink.WriteDsd(big.data(), bigR.data(), UsbAudioSink::kMaxDsdBytesPerCall, 82),
              "a block exactly at the 1 MiB bound must be accepted");
        check(UsbAudioSinkTestAccess::writeCount(sink) == 262144,
              "1 MiB of DSD per channel must be 262144 wire frames");

        UsbAudioSinkTestAccess::prepareDsd(sink, 524288);
        std::vector<uint8_t> tooBig(static_cast<size_t>(UsbAudioSink::kMaxDsdBytesPerCall) + 1, 0x3C);
        std::vector<uint8_t> tooBigR(static_cast<size_t>(UsbAudioSink::kMaxDsdBytesPerCall) + 1, 0xC3);
        check(!sink.WriteDsd(tooBig.data(), tooBigR.data(),
                             UsbAudioSink::kMaxDsdBytesPerCall + 1, 83),
              "one byte past the 1 MiB bound must be refused");
        check(UsbAudioSinkTestAccess::lastError(sink) == EINVAL,
              "an oversized DSD block must report EINVAL");
        check(UsbAudioSinkTestAccess::writeCount(sink) == 0,
              "an oversized DSD block must not write anything");
        check(!sink.WriteDsd(nullptr, tooBigR.data(), 4, 83), "a null channel must be refused");
        check(!sink.WriteDsd(big.data(), bigR.data(), 0, 83), "a zero-length block must be refused");
    }

    // ---- 7. IsDsdActive() lifecycle and clock-domain derivation -----------
    {
        UsbAudioSinkTestAccess::reset(sink);
        check(!sink.IsDsdActive(), "IsDsdActive() must be false before any stream");
        UsbAudioSinkTestAccess::prepareDsd(sink);
        check(sink.IsDsdActive(), "IsDsdActive() must be true for a live DSD stream");
        check(sink.Close(), "closing a host-prepared DSD stream must succeed");
        check(!sink.IsDsdActive(), "IsDsdActive() must be false after close");
        UsbAudioSinkTestAccess::preparePcm(sink);
        check(!sink.IsDsdActive(), "IsDsdActive() must be false for a live PCM stream");
        // A worker self-exit clears active_ before teardown runs: the latch alone
        // must never keep reporting a live DSD stream.
        UsbAudioSinkTestAccess::prepareDsd(sink);
        UsbAudioSinkTestAccess::markWorkerExited(sink);
        check(!sink.IsDsdActive(), "a self-exited DSD worker must not report IsDsdActive()");
        UsbAudioSinkTestAccess::reset(sink);

        check(UsbAudioSink::DeriveClockDomain(UsbRenderMode::DsdNative, true, true, 0, 0) ==
                  pulsr::UsbClockDomain::BitPerfectLocked,
              "a clean DSD session must derive BitPerfectLocked like the pull path");
        check(UsbAudioSink::DeriveClockDomain(UsbRenderMode::DsdNative, true, true, 1, 0) ==
                  pulsr::UsbClockDomain::BestEffort,
              "one DSD underrun must downgrade the clock domain");
        check(UsbAudioSink::DeriveClockDomain(UsbRenderMode::DsdNative, true, false, 0, 0) ==
                  pulsr::UsbClockDomain::BestEffort,
              "an ineligible DSD session must not claim bit-perfect");
        check(UsbAudioSink::DeriveClockDomain(UsbRenderMode::DsdNative, false, true, 0, 0) ==
                  pulsr::UsbClockDomain::Unknown,
              "a closed DSD stream has no clock domain");
        check(UsbAudioSink::DeriveClockDomain(UsbRenderMode::BestEffort, true, true, 0, 0) ==
                  pulsr::UsbClockDomain::BestEffort,
              "BestEffort must keep reporting BestEffort");
        check(UsbAudioSink::DeriveClockDomain(UsbRenderMode::ClockSyncAsrc, true, true, 0, 0) ==
                  pulsr::UsbClockDomain::Asrc,
              "ClockSyncAsrc must keep reporting Asrc");
    }

    if (gFailures == 0) {
        std::cout << "[PASS] USB native-DSD path" << std::endl;
        return 0;
    }
    std::cout << "[FAIL] " << gFailures << " checks" << std::endl;
    return 1;
}
