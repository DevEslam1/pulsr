// android/app/src/test/cpp/test_usb_pull_renderer.cpp
//
// Host-side proof for the USB pull renderer:
//   * SPSC bit-exactness under adversarial chunking (rails, all-0x00/0xFF,
//     pseudo-random payloads, wrap-around of the byte ring),
//   * seek/flush, pause/resume and the prefill gate,
//   * underrun/overrun accounting (one event per call, never per frame),
//   * an 8-hour simulated soak at 1 ms packet granularity with producer and
//     consumer on clocks 150 ppm apart in opposite directions, where the
//     consumer is steered by ring-fill feedback.
#include "../../main/cpp/UsbClockDomain.h"
#include "../../main/cpp/UsbPullRenderer.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <vector>

using pulsr::UsbPullRenderer;

// Counts every heap allocation so the hot path can be proven allocation-free
// rather than merely assumed to be.
static std::atomic<uint64_t> gAllocations{0};
void* operator new(std::size_t size) {
    gAllocations.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(size ? size : 1)) return p;
    throw std::bad_alloc();
}
void* operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

namespace {

int gFailures = 0;
int gChecks = 0;

void check(bool ok, const char* what) {
    ++gChecks;
    if (!ok) {
        std::cout << "[FAIL] " << what << std::endl;
        ++gFailures;
    }
}

uint64_t splitmix64(uint64_t x) {
    x += 0x9E3779B97F4A7C15ull;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
    return x ^ (x >> 31);
}

// Deterministic payload for absolute frame index `index`. Mixing a hash with
// explicit 0x00/0xFF sentinels covers full-scale and alternating patterns
// without any per-test bookkeeping: the consumer can regenerate the expected
// bytes for any frame index on demand.
void fillFrames(uint8_t* dst, uint64_t firstFrame, int frames, int frameBytes) {
    for (int f = 0; f < frames; ++f) {
        const uint64_t index = firstFrame + static_cast<uint64_t>(f);
        uint8_t* p = dst + static_cast<size_t>(f) * static_cast<size_t>(frameBytes);
        const uint64_t h = splitmix64(index);
        const uint64_t h2 = splitmix64(index ^ 0xA5A5A5A5A5A5A5A5ull);
        if (index % 97 == 0) {
            std::memset(p, 0xFF, static_cast<size_t>(frameBytes));   // +FS rail
        } else if (index % 89 == 0) {
            std::memset(p, 0x00, static_cast<size_t>(frameBytes));   // digital silence
        } else if (index % 53 == 0) {
            std::memset(p, 0x80, static_cast<size_t>(frameBytes));   // -FS rail
        } else if (index % 41 == 0) {
            std::memset(p, 0x7F, static_cast<size_t>(frameBytes));   // near +FS
        } else if (index % 23 == 0) {
            for (int b = 0; b < frameBytes; ++b) {
                p[b] = (b & 1) ? 0xFF : 0x00;                        // alternating
            }
        } else {
            for (int b = 0; b < frameBytes; ++b) {
                p[b] = static_cast<uint8_t>((h >> (8 * (b & 7))) & 0xFF);
                if (b >= 8) p[b] ^= static_cast<uint8_t>(h2 >> (8 * (b & 7)));
            }
        }
    }
}

uint32_t nextRandom(uint32_t& state) {
    state = state * 1664525u + 1013904223u;
    return state >> 8;
}

// ---- SPSC bit-exactness -------------------------------------------------
void testBitExactSpsc() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 500), "Configure(48k,2ch,4B,500ms) must succeed");
    const size_t cap = r.capacityFrames();
    check(cap >= 24000, "500 ms at 48 kHz must give at least 24000 frames of capacity");
    check((cap & (cap - 1)) == 0, "capacity must be a power of two frames");
    check(r.frameBytes() == 8, "stereo 4-byte samples are 8 bytes per frame");

    constexpr int kFrameBytes = 8;
    constexpr int kChunk = 128;
    uint8_t src[kChunk * kFrameBytes];
    uint8_t dst[kChunk * kFrameBytes];
    uint8_t expect[kChunk * kFrameBytes];

    // Fill to the 80% prefill gate.
    uint64_t produced = 0;
    int guard = 0;
    while (!r.prefillSatisfied() && guard++ < 100000) {
        fillFrames(src, produced, kChunk, kFrameBytes);
        check(r.write(src, kChunk), "prefill write must succeed below capacity");
        produced += kChunk;
    }
    check(r.prefillSatisfied(), "prefill must latch at 80% of the configured buffer");
    check(r.fillMs() >= 400, "after prefill the ring must report >= 400 ms of the 500 ms buffer");

    uint64_t consumed = 0;
    uint32_t rng = 0xC0FFEEu;
    int compared = 0;
    for (int iteration = 0; iteration < 40000; ++iteration) {
        const int want = static_cast<int>(nextRandom(rng) % 37) + 1;
        if ((nextRandom(rng) & 1) != 0) {
            fillFrames(src, produced, want, kFrameBytes);
            if (r.write(src, want)) {
                produced += static_cast<uint64_t>(want);
            } else {
                // Ring full: drain instead, then the caller retries this block.
                const int got = r.pull(dst, want);
                check(got == want, "pull must satisfy a request the ring can hold");
                consumed += static_cast<uint64_t>(got);
            }
        } else {
            const int got = r.pull(dst, want);
            if (got > 0) {
                fillFrames(expect, consumed, got, kFrameBytes);
                check(std::memcmp(dst, expect, static_cast<size_t>(got) * kFrameBytes) == 0,
                      "pulled frames must be byte-identical to what the producer wrote");
                ++compared;
            }
            consumed += static_cast<uint64_t>(got);
        }
    }
    // Drain the rest and compare it too: this is where ring wrap-around is most
    // likely to tear a frame.
    while (consumed < produced) {
        const int want = static_cast<int>(std::min<uint64_t>(96, produced - consumed));
        const int got = r.pull(dst, want);
        check(got == want, "final drain must be satisfied");
        fillFrames(expect, consumed, got, kFrameBytes);
        check(std::memcmp(dst, expect, static_cast<size_t>(got) * kFrameBytes) == 0,
              "final drained frames must be byte-identical");
        ++compared;
        consumed += static_cast<uint64_t>(got);
    }
    check(compared > 1000, "the randomized SPSC run must actually compare many blocks");
    check(r.underrunEvents() == 0, "a producer that keeps up must never cause an underrun");
    check(r.framesPulled() == consumed, "framesPulled must count every delivered frame");
    check(r.availableFrames() == 0, "ring must be empty after the final drain");
}

// ---- flush() is a seek ---------------------------------------------------
void testFlush() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 100), "Configure(48k,2ch,4B,100ms) must succeed");
    constexpr int kFrameBytes = 8;
    uint8_t frame[kFrameBytes];
    uint8_t out[kFrameBytes * 64];

    for (int i = 0; i < 600; ++i) {
        fillFrames(frame, static_cast<uint64_t>(i), 1, kFrameBytes);
        check(r.write(frame, 1), "writes below the 4800-frame buffer must succeed");
    }
    check(r.fillMs() > 0, "the ring must report occupancy after writing");
    r.flush();
    check(r.fillMs() == 0, "flush() must drop buffered audio (seek)");
    check(r.availableFrames() == 0, "flush() must leave zero frames available");
    check(!r.prefillSatisfied(), "flush() must re-arm the prefill gate");
    check(r.underrunEvents() == 0 && r.overrunEvents() == 0,
          "a seek must not be accounted as an underrun or an overrun");

    // The gate blocks draining even though the seek target is playable.
    check(r.pullExact(out, 48) == 0, "pull must not drain before prefill after a seek");
    check(r.underrunEvents() == 0, "a gated pre-start pull is not an underrun");

    // Post-seek audio must come out exactly as written.
    uint64_t produced = 0;
    std::vector<uint8_t> block(3840 * kFrameBytes);
    fillFrames(block.data(), 1000000, 3840, kFrameBytes);
    check(r.write(block.data(), 3840), "post-seek prefill must succeed");
    produced += 3840;
    check(r.prefillSatisfied(), "80% of 100 ms at 48 kHz must satisfy prefill");
    uint8_t expect[kFrameBytes * 64];
    const int got = r.pull(out, 64);
    check(got == 64, "pull after re-prefill must return data");
    fillFrames(expect, 1000000, got, kFrameBytes);
    check(std::memcmp(out, expect, static_cast<size_t>(got) * kFrameBytes) == 0,
          "post-seek audio must be the newly written data, not stale bytes");
    check(r.framesPulled() == static_cast<uint64_t>(got),
          "flush() keeps counters; framesPulled must only count post-seek frames");
    (void)produced;
}

// ---- pause / resume ------------------------------------------------------
void testPause() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 100), "Configure for pause test must succeed");
    constexpr int kFrameBytes = 8;
    std::vector<uint8_t> block(3840 * kFrameBytes);
    fillFrames(block.data(), 500000, 3840, kFrameBytes);
    check(r.write(block.data(), 3840), "pause test prefill must succeed");
    const int filledMs = r.fillMs();
    check(filledMs > 0, "pause test must have buffered audio");

    uint8_t out[kFrameBytes * 64];
    r.setPaused(true);
    check(r.paused(), "setPaused(true) must be observable");
    check(r.pullExact(out, 48) == 0, "a paused renderer must not drain");
    check(r.pull(out, 48) == 0, "pull() must also refuse to drain while paused");
    check(r.underrunEvents() == 0, "a paused pull must not be accounted as an underrun");
    check(r.fillMs() == filledMs, "a paused pull must leave the ring untouched");

    // While paused the producer may keep filling: that is dropout protection.
    std::vector<uint8_t> more(1024 * kFrameBytes);
    fillFrames(more.data(), 600000, 1024, kFrameBytes);
    check(r.write(more.data(), 1024), "the producer may fill while paused");

    r.setPaused(false);
    check(!r.paused(), "setPaused(false) must clear the pause");
    const int got = r.pullExact(out, 48);
    check(got == 48, "resuming must drain immediately");
    check(r.underrunEvents() == 0, "resume must not invent an underrun");
}

// ---- underrun accounting -------------------------------------------------
void testUnderrunAccounting() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 100), "Configure for underrun test must succeed");
    constexpr int kFrameBytes = 8;
    std::vector<uint8_t> block(480 * kFrameBytes);
    for (int i = 0; i < 8; ++i) {
        fillFrames(block.data(), static_cast<uint64_t>(i) * 480, 480, kFrameBytes);
        check(r.write(block.data(), 480), "underrun prefill write must succeed");
    }
    check(r.prefillSatisfied(), "3840 of 4800 frames is above the 80% gate");

    std::vector<uint8_t> out(4000 * kFrameBytes, 0xAA);
    int got = r.pullExact(out.data(), 100);
    check(got == 100, "a satisfiable pullExact must return the full request");
    check(r.underrunEvents() == 0, "a satisfiable pullExact must not count an underrun");

    got = r.pullExact(out.data(), 4000);
    check(got == 3740, "pullExact must report the frames it could really deliver");
    check(r.underrunEvents() == 1, "one short call must count exactly one underrun event");
    bool zeros = true;
    for (size_t i = static_cast<size_t>(got) * kFrameBytes; i < out.size(); ++i) {
        if (out[i] != 0x00) zeros = false;
    }
    check(zeros, "the unsatisfied tail of pullExact must be zero-filled");

    got = r.pullExact(out.data(), 48);
    check(got == 0, "an empty ring must deliver zero frames");
    check(r.underrunEvents() == 2, "each short call counts one event, not one per frame");
    zeros = true;
    for (size_t i = 0; i < 48 * kFrameBytes; ++i) {
        if (out[i] != 0x00) zeros = false;
    }
    check(zeros, "a fully unsatisfied pullExact must zero the whole destination");
    check(r.framesPulled() == 3840, "framesPulled must exclude zero-fill");
}

// ---- overrun accounting --------------------------------------------------
void testOverrunAccounting() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 100), "Configure for overrun test must succeed");
    check(r.capacityFrames() == 8192, "4800 requested frames must round to 8192 frames");
    constexpr int kFrameBytes = 8;
    std::vector<uint8_t> block(4800 * kFrameBytes);
    fillFrames(block.data(), 0, 4800, kFrameBytes);
    check(r.write(block.data(), 4800), "first 4800 frames must fit");
    check(r.write(block.data(), 3392), "remaining capacity must fit exactly");
    check(r.availableFrames() == 8192, "ring must be exactly full");

    const uint64_t overrunsBefore = r.overrunEvents();
    fillFrames(block.data(), 800000, 1, kFrameBytes);
    check(!r.write(block.data(), 1), "a write into a full ring must fail");
    check(r.overrunEvents() == overrunsBefore + 1, "a dropped block counts one overrun event");
    check(r.availableFrames() == 8192, "a rejected write must not change occupancy");

    // Larger than the whole ring: still all-or-nothing.
    std::vector<uint8_t> huge(static_cast<size_t>(8193) * kFrameBytes);
    check(!r.write(huge.data(), 8193), "a block larger than the ring must be rejected whole");
    check(r.overrunEvents() == overrunsBefore + 2, "the oversized block counts one event");
    check(r.availableFrames() == 8192, "the oversized block must not publish anything");

    // Free one frame, write one frame: no new overrun.
    uint8_t out[kFrameBytes];
    check(r.pull(out, 1) == 1, "pulling one frame must succeed");
    check(r.write(block.data(), 1), "a fitting write after a pull must succeed");
    check(r.overrunEvents() == overrunsBefore + 2, "a fitting write must not count an overrun");
    check(r.fillMs() == 170, "8192 frames at 48 kHz must report 170 ms");
}

// ---- reset() -------------------------------------------------------------
void testReset() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 100), "Configure for reset test must succeed");
    constexpr int kFrameBytes = 8;
    std::vector<uint8_t> block(3840 * kFrameBytes);
    fillFrames(block.data(), 0, 3840, kFrameBytes);
    check(r.write(block.data(), 3840), "reset test prefill must succeed");
    r.setPaused(true);
    (void)r.pullExact(block.data(), 1);  // paused: nothing happens, still armed
    r.reset();
    check(r.fillMs() == 0, "reset() must drop buffered audio");
    check(!r.prefillSatisfied(), "reset() must clear the prefill latch");
    check(!r.paused(), "reset() must clear the pause state");
    check(r.underrunEvents() == 0 && r.overrunEvents() == 0 && r.framesPulled() == 0,
          "reset() must zero every counter");
    check(r.capacityFrames() > 0, "reset() must keep the configuration");
}

// ---- driftPpm ------------------------------------------------------------
void testDriftPpm() {
    check(UsbPullRenderer::driftPpm(48000, 48000) == 0, "equal counts must report 0 ppm");
    check(UsbPullRenderer::driftPpm(0, 0) == 0, "zero counts must report 0 ppm");
    check(UsbPullRenderer::driftPpm(1, 0) == 0, "a zero consumer count must report 0 ppm");
    const int64_t producer = 48000LL * 3600;      // one hour at 48 kHz
    const int64_t consumer = 172774080LL;         // 47.9928 kHz for the same hour
    check(UsbPullRenderer::driftPpm(producer, consumer) == 150,
          "a 150 ppm fast producer must report +150 ppm");
    check(UsbPullRenderer::driftPpm(consumer, producer) == -150,
          "the inverse must report -150 ppm");
    check(std::abs(UsbPullRenderer::driftPpm(172800001, 172800000)) == 0,
          "a single frame over an hour is below 1 ppm and must round to 0");
}

// ---- clock-domain vocabulary ---------------------------------------------
void testClockDomainContract() {
    using pulsr::UsbClockDomain;
    using pulsr::UsbClockDomainName;
    check(std::strcmp(UsbClockDomainName(UsbClockDomain::Unknown), "unknown") == 0,
          "Unknown must serialize as 'unknown'");
    check(std::strcmp(UsbClockDomainName(UsbClockDomain::BitPerfectLocked),
                      "bitPerfectLocked") == 0,
          "BitPerfectLocked must serialize as 'bitPerfectLocked'");
    check(std::strcmp(UsbClockDomainName(UsbClockDomain::Asrc), "asrc") == 0,
          "Asrc must serialize as 'asrc'");
    check(std::strcmp(UsbClockDomainName(UsbClockDomain::BestEffort), "bestEffort") == 0,
          "BestEffort must serialize as 'bestEffort'");
    check(static_cast<int32_t>(UsbClockDomain::Unknown) == 0 &&
              static_cast<int32_t>(UsbClockDomain::BitPerfectLocked) == 1 &&
              static_cast<int32_t>(UsbClockDomain::Asrc) == 2 &&
              static_cast<int32_t>(UsbClockDomain::BestEffort) == 3,
          "the wire enum values must stay 0/1/2/3");
    check(std::strcmp(UsbClockDomainName(static_cast<UsbClockDomain>(99)), "unknown") == 0,
          "an out-of-range domain must degrade to 'unknown', never to a stale name");
    const pulsr::UsbClockStatus status{};
    check(status.domain == UsbClockDomain::Unknown && status.clockDriftPpm == 0 &&
              status.ringFillMs == 0 && !status.feedbackPresent &&
              status.underrunCount == 0 && status.overrunCount == 0,
          "UsbClockStatus must default to an inert Unknown status");
}

// ---- no allocation on the audio path -------------------------------------
void testNoAllocationInHotPath() {
    UsbPullRenderer r;
    check(r.Configure(48000, 2, 4, 200), "Configure for the allocation test must succeed");
    constexpr int kFrameBytes = 8;
    std::vector<uint8_t> block(3840 * kFrameBytes);
    fillFrames(block.data(), 0, 3840, kFrameBytes);
    check(r.write(block.data(), 3840), "allocation-test prefill must succeed");
    check(r.write(block.data(), 3840), "allocation-test prefill must reach the 80% gate");

    uint8_t src[48 * kFrameBytes];
    uint8_t dst[48 * kFrameBytes];
    fillFrames(src, 100000, 48, kFrameBytes);
    const uint64_t before = gAllocations.load(std::memory_order_relaxed);
    bool allOk = true;
    for (int i = 0; i < 2000; ++i) {
        if (!r.write(src, 48)) allOk = false;
        if (r.pullExact(dst, 48) != 48) allOk = false;
    }
    const uint64_t after = gAllocations.load(std::memory_order_relaxed);
    check(allOk, "the allocation-test stream must flow without drops");
    check(after == before, "write()/pullExact() must not allocate on the audio path");
}

// ---- 8-hour soak ---------------------------------------------------------
void testEightHourSoak() {
    constexpr int kIterations = 8 * 3600 * 1000;  // one simulated ms each
    constexpr double kProducerPpm = 150.0;
    constexpr double kConsumerPpm = -150.0;
    constexpr double kTargetMs = 3000.0;

    UsbPullRenderer r;
    // 3 s configured -> 262144 frames (5.46 s) of capacity, so the steering
    // loop has room to settle without ever touching the rim.
    check(r.Configure(48000, 2, 4, 3000), "soak Configure(48k,2ch,4B,3000ms) must succeed");

    constexpr int kFrameBytes = 8;
    std::vector<uint8_t> pcm(static_cast<size_t>(64) * kFrameBytes);
    fillFrames(pcm.data(), 0, 64, kFrameBytes);
    uint8_t out[64 * kFrameBytes];

    // Prebuffer 3 s, exactly the configured buffer depth.
    const int prebufferFrames = 48000 * 3;
    int written = 0;
    while (written < prebufferFrames) {
        const int chunk = std::min(64, prebufferFrames - written);
        if (!r.write(pcm.data(), chunk)) {
            check(false, "prebuffer must fit the configured buffer");
            return;
        }
        written += chunk;
    }
    check(r.prefillSatisfied(), "a 3 s prebuffer must satisfy the 80% gate of a 3 s buffer");

    const double producerPerMs = 48.0 * (1.0 + kProducerPpm * 1e-6);
    const double consumerNominalPerMs = 48.0 * (1.0 + kConsumerPpm * 1e-6);
    const double targetFrames = kTargetMs * 48.0;

    double producerAcc = 0.0;
    double consumerAcc = 0.0;
    int64_t producedFrames = prebufferFrames;
    int64_t consumedFrames = 0;
    uint64_t overflows = 0;
    uint64_t underflows = 0;
    size_t maxFill = 0;
    size_t minFill = static_cast<size_t>(-1);

    const auto start = std::chrono::steady_clock::now();
    for (int ms = 0; ms < kIterations; ++ms) {
        producerAcc += producerPerMs;
        const int produce = static_cast<int>(producerAcc);
        producerAcc -= produce;
        if (!r.write(pcm.data(), produce)) {
            ++overflows;
            break;
        }
        producedFrames += produce;

        // Feedback steering: the consumer's own clock is 150 ppm slow, so the
        // loop has to make up the whole 300 ppm relative error. This is the
        // shape the real transport uses, but driven by ring fill instead of a
        // USB feedback endpoint.
        const size_t fill = r.availableFrames();
        if (fill > maxFill) maxFill = fill;
        if (fill < minFill) minFill = fill;
        const double err =
            (static_cast<double>(fill) - targetFrames) / targetFrames;
        double rate = consumerNominalPerMs * (1.0 + 0.005 * err);
        const double limit = consumerNominalPerMs * 0.005;
        if (rate > consumerNominalPerMs + limit) rate = consumerNominalPerMs + limit;
        if (rate < consumerNominalPerMs - limit) rate = consumerNominalPerMs - limit;

        consumerAcc += rate;
        const int consume = static_cast<int>(consumerAcc);
        consumerAcc -= consume;
        if (r.pullExact(out, consume) != consume) {
            ++underflows;
            break;
        }
        consumedFrames += consume;
    }
    const auto elapsed = std::chrono::steady_clock::now() - start;
    const double seconds = std::chrono::duration<double>(elapsed).count();

    std::cout << "[INFO] soak: " << kIterations << " simulated ms (8 h), "
              << producedFrames << " frames produced, " << consumedFrames
              << " consumed, fill " << (minFill / 48) << ".." << (maxFill / 48)
              << " ms, " << seconds << " s wall" << std::endl;

    check(overflows == 0, "8-hour soak: the ring must never overflow when the consumer is steered");
    check(underflows == 0, "8-hour soak: the ring must never underflow when prebuffered 3 s");
    check(r.overrunEvents() == 0, "8-hour soak: no overrun events");
    check(r.underrunEvents() == 0, "8-hour soak: no underrun events");
    check(maxFill < r.capacityFrames(), "8-hour soak: fill must stay strictly inside the ring");
    check(minFill > static_cast<size_t>(2900 * 48),
          "8-hour soak: fill must never fall below 2.9 s (buffer must stay precharged)");
    check(maxFill < static_cast<size_t>(3300 * 48),
          "8-hour soak: fill must never run away toward the rim");

    // The producer's integer accumulator must deliver exactly its clock's frame
    // count (within the final <1 frame fraction).
    const int64_t expectedProduced = static_cast<int64_t>(producerPerMs * kIterations);
    const int64_t delta = producedFrames - prebufferFrames - expectedProduced;
    check(delta <= 8 && delta >= -8,
          "8-hour soak: the producer must deliver exactly its clock's frame count");
    // Conservation: every frame produced is either consumed or still buffered.
    check(consumedFrames + static_cast<int64_t>(r.availableFrames()) == producedFrames,
          "8-hour soak: consumed + buffered must equal produced (no silently lost frames)");
    check(r.framesPulled() == static_cast<uint64_t>(consumedFrames),
          "8-hour soak: framesPulled must match the consumer's own accounting");

    // The consumer's own clock is 150 ppm slow. Tracking the producer therefore
    // requires the steering loop to run it ~300 ppm above its own nominal rate;
    // that is the number that proves the loop did real work instead of drifting.
    const int64_t consumerNative = static_cast<int64_t>(consumerNominalPerMs * kIterations);
    const int steeringPpm = UsbPullRenderer::driftPpm(consumedFrames, consumerNative);
    std::cout << "[INFO] soak steering: " << steeringPpm
              << " ppm above the consumer's own clock, " << seconds << " s wall"
              << std::endl;
    check(steeringPpm >= 290 && steeringPpm <= 310,
          "8-hour soak: feedback steering must make up the 300 ppm relative clock error");
    check(seconds < 60.0, "8-hour soak: 28.8M packet iterations must finish well under 60 s");
}

}  // namespace

int main() {
    std::cout << "[TEST] USB pull renderer (SPSC ring, prefill, soak)..." << std::endl;

    testBitExactSpsc();
    testFlush();
    testPause();
    testUnderrunAccounting();
    testOverrunAccounting();
    testReset();
    testDriftPpm();
    testClockDomainContract();
    testNoAllocationInHotPath();
    testEightHourSoak();

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " of " << gChecks
                  << " USB pull renderer check(s) failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB pull renderer: " << gChecks
              << " checks (bit-exact SPSC, seek, pause, under/overrun, 8 h soak)."
              << std::endl;
    return 0;
}
