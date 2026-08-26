#include "Crossfeed.h"
#include <cstring>

Crossfeed::Crossfeed() {
    setSampleRate(48000.0);
    configure(350.0, -9.0);
    reset();
}

void Crossfeed::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    configure(delayUs_, feedDb_);
}

void Crossfeed::configure(double delayUs, double feedDb) {
    delayUs_ = std::max(50.0, std::min(delayUs, 2000.0));
    feedDb_ = std::max(-30.0, std::min(feedDb, 0.0));

    delaySamples_ = std::max(1, std::min(static_cast<int>(sampleRate_ * delayUs_ / 1e6), MAX_DELAY_SAMPLES - 1));
    feedLevel_ = static_cast<float>(std::pow(10.0, feedDb_ / 20.0));

    // One-pole lowpass cutoff ~700 Hz (head shadow frequency)
    double fc = 700.0 / sampleRate_;
    lpCoeff_ = static_cast<float>(1.0 - std::exp(-2.0 * M_PI * fc));
}

void Crossfeed::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void Crossfeed::reset() {
    std::memset(delayBufferL_, 0, sizeof(delayBufferL_));
    std::memset(delayBufferR_, 0, sizeof(delayBufferR_));
    writeIdx_ = 0;
    lpL_ = 0.0f;
    lpR_ = 0.0f;
}

void Crossfeed::process(float* L, float* R, int frames) {
    if (!enabled_ || !L || !R || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        float l = L[i];
        float r = R[i];

        // Lowpass filter signal for head shadow
        lpL_ += lpCoeff_ * (l - lpL_);
        lpR_ += lpCoeff_ * (r - lpR_);

        // Retrieve delayed lowpassed signal from opposite channel
        int rdIdx = (writeIdx_ - delaySamples_ + MAX_DELAY_SAMPLES) % MAX_DELAY_SAMPLES;
        float delayedL = delayBufferL_[rdIdx];
        float delayedR = delayBufferR_[rdIdx];

        // Store current lowpassed samples in delay buffer
        delayBufferL_[writeIdx_] = lpL_;
        delayBufferR_[writeIdx_] = lpR_;
        writeIdx_ = (writeIdx_ + 1) % MAX_DELAY_SAMPLES;

        // Crossfeed mix
        L[i] = l + delayedR * feedLevel_;
        R[i] = r + delayedL * feedLevel_;
    }
}

void Crossfeed::processInterleaved(float* buffer, int frames) {
    if (!enabled_ || !buffer || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        float l = buffer[i * 2];
        float r = buffer[i * 2 + 1];

        lpL_ += lpCoeff_ * (l - lpL_);
        lpR_ += lpCoeff_ * (r - lpR_);

        int rdIdx = (writeIdx_ - delaySamples_ + MAX_DELAY_SAMPLES) % MAX_DELAY_SAMPLES;
        float delayedL = delayBufferL_[rdIdx];
        float delayedR = delayBufferR_[rdIdx];

        delayBufferL_[writeIdx_] = lpL_;
        delayBufferR_[writeIdx_] = lpR_;
        writeIdx_ = (writeIdx_ + 1) % MAX_DELAY_SAMPLES;

        buffer[i * 2] = l + delayedR * feedLevel_;
        buffer[i * 2 + 1] = r + delayedL * feedLevel_;
    }
}
