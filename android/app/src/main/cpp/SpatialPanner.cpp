#include "SpatialPanner.h"

SpatialPanner::SpatialPanner() {
    setBalance(0.0);
    setMono(false);
}

void SpatialPanner::setBalance(double balance) {
    balance_ = std::max(-1.0, std::min(balance, 1.0));
    // Linear balance with center at 1.0
    if (balance_ <= 0.0) {
        gainL_ = 1.0f;
        gainR_ = static_cast<float>(1.0 + balance_);
    } else {
        gainL_ = static_cast<float>(1.0 - balance_);
        gainR_ = 1.0f;
    }
}

void SpatialPanner::setMono(bool mono) {
    mono_ = mono;
}

void SpatialPanner::process(float* L, float* R, int frames) {
    if (mono_) {
        for (int i = 0; i < frames; ++i) {
            float sum = (L[i] + R[i]) * 0.5f;
            L[i] = sum * gainL_;
            R[i] = sum * gainR_;
        }
    } else if (std::abs(balance_) > 0.001) {
        for (int i = 0; i < frames; ++i) {
            L[i] *= gainL_;
            R[i] *= gainR_;
        }
    }
}

void SpatialPanner::processInterleaved(float* buffer, int frames) {
    if (mono_) {
        for (int i = 0; i < frames; ++i) {
            float sum = (buffer[i * 2] + buffer[i * 2 + 1]) * 0.5f;
            buffer[i * 2] = sum * gainL_;
            buffer[i * 2 + 1] = sum * gainR_;
        }
    } else if (std::abs(balance_) > 0.001) {
        for (int i = 0; i < frames; ++i) {
            buffer[i * 2] *= gainL_;
            buffer[i * 2 + 1] *= gainR_;
        }
    }
}
