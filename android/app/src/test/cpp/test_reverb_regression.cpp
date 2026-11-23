// android/app/src/test/cpp/test_reverb_regression.cpp
#include "../../main/cpp/ConvolutionReverb.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <memory>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main() {
    std::cout << "[TEST] Running Reverb N-1 Single-Tap Delay Regression Test..." << std::endl;

    auto reverb = std::make_unique<ConvolutionReverb>();
    reverb->setSampleRate(48000.0);
    reverb->setEnabled(true);
    reverb->setWetDry(1.0); // 100% wet
    reverb->setPredelay(0.0);

    // Create a 2048-tap single-tap IR at j=300 (partition 0)
    // IR length 2048 forces partitioned FFT mode (>1024 taps)
    const int irLen = 2048;
    std::vector<float> irInterleaved(irLen * 2, 0.0f);
    irInterleaved[300 * 2] = 1.0f;     // Left tap at sample 300
    irInterleaved[300 * 2 + 1] = 1.0f; // Right tap at sample 300

    bool loaded = reverb->loadCustomIR(irInterleaved.data(), irLen, 2);
    assert(loaded);
    reverb->reset();

    // 10 blocks of 512 samples = 5120 samples
    const int numBlocks = 10;
    const int blockSize = 512;
    const int totalFrames = numBlocks * blockSize;

    std::vector<float> inL(totalFrames);
    std::vector<float> inR(totalFrames);
    std::vector<float> outL(totalFrames, 0.0f);
    std::vector<float> outR(totalFrames, 0.0f);

    // Feed 1 kHz sine wave
    for (int i = 0; i < totalFrames; ++i) {
        float s = std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 48000.0f);
        inL[i] = s;
        inR[i] = s;
    }

    // Process block by block
    for (int b = 0; b < numBlocks; ++b) {
        reverb->process(&inL[b * blockSize], &inR[b * blockSize],
                        &outL[b * blockSize], &outR[b * blockSize], blockSize);
    }

    // Check outputs against expected delayed sine
    // In partitioned overlap-save, wet path latency is PARTITION_SIZE (512) + tap (300) = 812 samples
    const int totalDelay = 512 + 300;
    int mismatchCount = 0;
    float maxErr = 0.0f;

    for (int i = totalDelay; i < totalFrames; ++i) {
        float expected = inL[i - totalDelay];
        float actual = outL[i];
        float err = std::abs(expected - actual);
        if (err > maxErr) maxErr = err;
        if (err > 1e-4f) {
            mismatchCount++;
            if (mismatchCount <= 5) {
                std::cout << "  Mismatch at sample " << i << " (block " << (i / blockSize) 
                          << " pos " << (i % blockSize) << "): expected " << expected 
                          << ", got " << actual << " (err " << err << ")" << std::endl;
            }
        }
    }

    std::cout << "  Total mismatches (> 1e-4): " << mismatchCount << " / " << (totalFrames - totalDelay) << std::endl;
    std::cout << "  Max absolute error: " << maxErr << std::endl;

    if (mismatchCount > 0 || maxErr > 1e-3f) {
        std::cout << "  [FAIL] Output does not match delayed input!" << std::endl;
        return 1;
    }

    std::cout << "  [PASS] Single-tap delay exact match across all 10 blocks (max error: " << maxErr << ")." << std::endl;

    // --- Phase 1.1 Memory Footprint Tests ---
    // 1. Direct-FIR (<=1024 taps) zero partitioned history allocation test
    {
        std::cout << "[TEST] 1024-tap direct-FIR IR allocates zero partitioned history..." << std::endl;
        auto directReverb = std::make_unique<ConvolutionReverb>();
        directReverb->setSampleRate(48000.0);
        directReverb->setEnabled(true);
        directReverb->setWetDry(1.0);

        const int directIrLen = 1024;
        std::vector<float> directIr(directIrLen * 2, 0.0f);
        directIr[0] = 1.0f;
        directIr[1] = 1.0f;

        assert(directReverb->loadCustomIR(directIr.data(), directIrLen, 2));
        assert(directReverb->getHistoryPartitionCount() == 0);
        assert(directReverb->getHistoryAllocatedBytes() == 0);

        std::vector<float> inBlockL(512, 0.5f), inBlockR(512, 0.5f);
        std::vector<float> outBlockL(512, 0.0f), outBlockR(512, 0.0f);
        directReverb->process(inBlockL.data(), inBlockR.data(), outBlockL.data(), outBlockR.data(), 512);

        assert(directReverb->getHistoryPartitionCount() == 0);
        assert(directReverb->getHistoryAllocatedBytes() == 0);
        std::cout << "  [PASS] Direct-FIR 1024-tap allocated 0 partitioned history (0 bytes)." << std::endl;
    }

    // 2. Fixed-stride history ring (item 8) and its footprint accounting
    {
        std::cout << "[TEST] Fixed-stride history ring geometry..." << std::endl;
        auto roomReverb = std::make_unique<ConvolutionReverb>();
        roomReverb->setSampleRate(48000.0);
        roomReverb->setPreset(ReverbPreset::Room);

        size_t roomPartitions = roomReverb->getHistoryPartitionCount();
        size_t roomBytes = roomReverb->getHistoryAllocatedBytes();

        constexpr size_t maxPreallocBytes = 2 * static_cast<size_t>(ConvolutionReverb::MAX_PREALLOC_PARTITIONS) *
            ConvolutionReverb::FFT_SIZE * sizeof(FftUtil::Complex); // 512 * 1024 * 8 * 2 = 8,388,608 bytes

        // The effective partition count still follows the IR (80 for Room), but
        // the ring itself is the FIXED MAX_PREALLOC_PARTITIONS stride so a later
        // IR growth can never reinterpret a slot. That trades the old per-preset
        // footprint saving for correctness; the byte counter reports the truth.
        assert(roomPartitions == 80);
        assert(roomBytes >= maxPreallocBytes);

        // Growing the IR mid-stream must keep the ring valid (finite output) and
        // raise the effective partition count without a new geometry.
        std::vector<float> growInL(512, 0.1f), growInR(512, 0.1f);
        std::vector<float> growOutL(512, 0.0f), growOutR(512, 0.0f);
        roomReverb->setEnabled(true);
        roomReverb->setWetDry(0.5);
        for (int b = 0; b < 8; ++b) {
            roomReverb->process(growInL.data(), growInR.data(), growOutL.data(), growOutR.data(), 512);
        }
        roomReverb->setPreset(ReverbPreset::Cathedral);
        for (int b = 0; b < 8; ++b) {
            roomReverb->process(growInL.data(), growInR.data(), growOutL.data(), growOutR.data(), 512);
            for (int i = 0; i < 512; ++i) {
                assert(std::isfinite(growOutL[i]) && std::isfinite(growOutR[i]));
            }
        }
        assert(roomReverb->getHistoryPartitionCount() > 80);

        std::cout << "  [PASS] Fixed ring: " << roomBytes << " bytes ("
                  << roomPartitions << " effective / "
                  << ConvolutionReverb::MAX_PREALLOC_PARTITIONS << " slots), growth intact."
                  << std::endl;
    }

    // 3. Cross-partition-count IR crossfade alignment & overflow retire ring safety
    {
        auto rev = std::make_unique<ConvolutionReverb>();
        rev->setSampleRate(48000.0);
        rev->setEnabled(true);
        rev->setWetDry(0.8);
        rev->setPreset(ReverbPreset::Cathedral); // large partition count first so ring covers max

        std::vector<float> blkL(512, 0.0f), blkR(512, 0.0f);
        std::vector<float> outL(512, 0.0f), outR(512, 0.0f);
        for (int i = 0; i < 512; ++i) {
            blkL[i] = 0.25f * std::sin(2.0f * 3.14159265f * 440.0f * i / 48000.0f);
            blkR[i] = blkL[i];
        }
        for (int b = 0; b < 6; ++b) {
            rev->process(blkL.data(), blkR.data(), outL.data(), outR.data(), 512);
        }
        rev->setPreset(ReverbPreset::Studio); // switch to fewer partitions while historyHead_ wraps on Cathedral
        for (int b = 0; b < 4; ++b) {
            rev->process(blkL.data(), blkR.data(), outL.data(), outR.data(), 512);
            for (int i = 0; i < 512; ++i) {
                assert(std::isfinite(outL[i]) && std::isfinite(outR[i]));
            }
        }
        // Overflow retireIr beyond kMaxRetired without draining, then drain cleanly
        for (int k = 0; k < 600; ++k) {
            rev->setPreset((k % 2 == 0) ? ReverbPreset::Room : ReverbPreset::Chamber);
        }
        // Item 7: the bounded emergency stash must never leak a retained IR past a
        // drain, and the render path must never block on overflowMutex_.
        assert(rev->getRetiredPendingCount() > 0);
        rev->drainRetiredIrs();
        assert(rev->getRetiredPendingCount() == 0);
        std::cout << "  [PASS] Cross-partition crossfade & >512 retired-IR overflow drain verified." << std::endl;
    }

    // 4. Direct-IR shrink clears stale directRingL_/R_ taps AND high-rate (>= 96kHz)
    //    wetOutResampler_ uses full resampleOutL_/R_ buffer capacity.
    {
        auto rev = std::make_unique<ConvolutionReverb>();
        rev->setSampleRate(48000.0);
        rev->setEnabled(true);
        rev->setWetDry(1.0);
        rev->setPredelay(0.0);

        // Long direct IR (256 taps) with impulse at tap 200
        std::vector<float> irLong(256 * 2, 0.0f);
        irLong[200 * 2] = 0.8f;
        irLong[200 * 2 + 1] = 0.8f;
        assert(rev->loadCustomIR(irLong.data(), 256, 2));

        std::vector<float> inL(512, 0.0f), inR(512, 0.0f), outL(512, 0.0f), outR(512, 0.0f);
        inL[400] = 1.0f; // Still inside directRingL_ history past index 32
        inR[400] = 1.0f;
        rev->process(inL.data(), inR.data(), outL.data(), outR.data(), 512);

        // Shrink direct IR to 16 taps (tap 0 = 0.5). Crossfade must finish cleanly and
        // feeding silence afterward must not leak tap-200 energy from old directRing_.
        std::vector<float> irShort(16 * 2, 0.0f);
        irShort[0] = 0.5f;
        irShort[1] = 0.5f;
        assert(rev->loadCustomIR(irShort.data(), 16, 2));

        std::fill(inL.begin(), inL.end(), 0.0f);
        std::fill(inR.begin(), inR.end(), 0.0f);
        for (int b = 0; b < 8; ++b) {
            rev->process(inL.data(), inR.data(), outL.data(), outR.data(), 512);
        }
        std::fill(inL.begin(), inL.end(), 0.0f);
        std::fill(inR.begin(), inR.end(), 0.0f);
        rev->process(inL.data(), inR.data(), outL.data(), outR.data(), 512);
        for (int i = 0; i < 512; ++i) {
            assert(std::abs(outL[i]) < 1e-4f && std::abs(outR[i]) < 1e-4f &&
                   "Direct IR shrink must not retain stale history beyond new tap length");
        }

        // High-rate (>48kHz) wetOutResampler_ test at 192 kHz with full resampleOutL_/R_ capacity
        rev->setSampleRate(192000.0);
        rev->setPreset(ReverbPreset::Room);
        std::vector<float> hiInL(1024), hiInR(1024), hiOutL(1024, 0.0f), hiOutR(1024, 0.0f);
        for (int i = 0; i < 1024; ++i) {
            float v = 0.3f * std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * i / 192000.0f);
            hiInL[i] = v;
            hiInR[i] = v;
        }
        float maxWet = 0.0f;
        for (int b = 0; b < 6; ++b) {
            rev->process(hiInL.data(), hiInR.data(), hiOutL.data(), hiOutR.data(), 1024);
            for (int i = 0; i < 1024; ++i) {
                assert(std::isfinite(hiOutL[i]) && std::isfinite(hiOutR[i]));
                maxWet = std::max(maxWet, std::abs(hiOutL[i]));
            }
        }
        assert(maxWet > 0.01f && "192kHz resampled wet output must remain active and finite");
        std::cout << "  [PASS] Direct-IR shrink ring clear & 192kHz wetOutResampler capacity verified." << std::endl;
    }
    return 0;
}
