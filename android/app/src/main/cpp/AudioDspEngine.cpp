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

void AudioDspEngine::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels < 1) return;

    if (channels == 2) {
        // 1. Parametric EQ (Stereo)
        if (eq_.isEnabled()) {
            eq_.processInterleaved(buffer, frames, 2);
        }

        // 2. Headphone Crossfeed (Stereo only)
        if (crossfeed_.isEnabled()) {
            crossfeed_.processInterleaved(buffer, frames);
        }

        // 3. Convolution Reverb / Room Simulation (Stereo)
        if (reverb_.isEnabled()) {
            reverb_.processInterleaved(buffer, frames);
        }

        // 4. Stereo Balance & Mono Mix (Stereo)
        panner_.processInterleaved(buffer, frames);

        // 5. Lookahead Brickwall Limiter (Stereo)
        if (limiter_.isEnabled()) {
            limiter_.processInterleaved(buffer, frames);
        }
    } else if (channels == 1) {
        // Mono channel path
        if (eq_.isEnabled()) {
            eq_.processInterleaved(buffer, frames, 1);
        }

        // Apply Lookahead Limiter to mono stream
        if (limiter_.isEnabled()) {
            limiter_.processMono(buffer, frames);
        }
    } else {
        // Multi-channel (>2) path
        if (eq_.isEnabled()) {
            eq_.processInterleaved(buffer, frames, channels);
        }
    }
}
