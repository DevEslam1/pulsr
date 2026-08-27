#include "AudioDspEngine.h"

AudioDspEngine& AudioDspEngine::instance() {
    static AudioDspEngine sInstance;
    return sInstance;
}

AudioDspEngine::AudioDspEngine() {
    setSampleRate(48000.0);
}

void AudioDspEngine::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;

    eq_.setSampleRate(sampleRate);
    crossfeed_.setSampleRate(sampleRate);
    limiter_.setSampleRate(sampleRate);
    reverb_.setSampleRate(sampleRate);
}

void AudioDspEngine::reset() {
    eq_.reset();
    crossfeed_.reset();
    limiter_.reset();
    reverb_.reset();
    resampler_.reset();
    dsdDecoder_.reset();
}

int AudioDspEngine::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels < 1) return 0;
    int chCount = std::min(channels, 8);

#if defined(__arm__)
    // ARMv7: flush-to-zero via FPSCR (VFP control register)
    unsigned int fpscr;
    asm volatile("vmrs %0, fpscr" : "=r"(fpscr));
    fpscr |= (1u << 24); // FZ bit — Flush-to-zero mode
    asm volatile("vmsr fpscr, %0" : : "r"(fpscr));
#elif defined(__aarch64__)
    // AArch64: flush-to-zero via FPCR (replaces FPSCR; uses mrs/msr)
    uint64_t fpcr;
    asm volatile("mrs %0, fpcr" : "=r"(fpcr));
    fpcr |= (1ULL << 24); // FZ bit — Flush-to-zero mode
    asm volatile("msr fpcr, %0" : : "r"(fpcr));
#endif

    int outFrames = frames;

    if (chCount == 2) {
        // 1. Parametric EQ (Stereo)
        if ((activeStages_ & STAGE_EQ) && eq_.isEnabled()) {
            eq_.processInterleaved(buffer, outFrames, 2);
        }

        // 2. Headphone Crossfeed (Stereo only)
        if ((activeStages_ & STAGE_CROSSFEED) && crossfeed_.isEnabled()) {
            crossfeed_.processInterleaved(buffer, outFrames);
        }

        // 3. Convolution Reverb / Room Simulation (Stereo)
        if ((activeStages_ & STAGE_REVERB) && reverb_.isEnabled()) {
            reverb_.processInterleaved(buffer, outFrames);
        }

        // 4. Stereo Balance & Mono Mix (Stereo)
        if (activeStages_ & STAGE_PANNER) {
            panner_.processInterleaved(buffer, outFrames);
        }

        // 5. Lookahead Brickwall Limiter (Stereo)
        if ((activeStages_ & STAGE_LIMITER) && limiter_.isEnabled()) {
            limiter_.processInterleaved(buffer, outFrames);
        }

        // 6. Sinc Resampler (Stereo)
        if ((activeStages_ & STAGE_RESAMPLER) && resampler_.isEnabled()) {
            const int expectedOut = resampler_.getExpectedOutFrames(outFrames);
            const size_t totalSamples = static_cast<size_t>(std::max(outFrames, expectedOut)) * 2;
            if (resamplerOutBuf_.size() < totalSamples) {
                resamplerOutBuf_.resize(totalSamples);
            }
            int resampledFrames = resampler_.processInterleaved(
                buffer, outFrames, resamplerOutBuf_.data(),
                static_cast<int>(totalSamples / 2));
            if (resampledFrames > 0) {
                const int copyFrames = std::min(resampledFrames, frames);
                std::memcpy(buffer, resamplerOutBuf_.data(),
                            static_cast<size_t>(copyFrames) * 2 * sizeof(float));
                outFrames = copyFrames;
            }
        }
    } else if (channels == 1) {
        // Mono channel path
        if ((activeStages_ & STAGE_EQ) && eq_.isEnabled()) {
            eq_.processInterleaved(buffer, outFrames, 1);
        }

        // Apply Lookahead Limiter to mono stream
        if ((activeStages_ & STAGE_LIMITER) && limiter_.isEnabled()) {
            limiter_.processMono(buffer, outFrames);
        }
    } else {
        // Multi-channel (>2) path
        if ((activeStages_ & STAGE_EQ) && eq_.isEnabled()) {
            eq_.processInterleaved(buffer, outFrames, channels);
        }
    }

    return outFrames;
}
