// android/app/src/main/cpp/DynamicBass.cpp
#include "DynamicBass.h"
#include <cstring>

DynamicBass::DynamicBass() {
    prepare(48000.0);
}

void DynamicBass::prepare(double sampleRate) {
    sampleRate_ = (sampleRate > 0.0) ? sampleRate : 48000.0;

    // Envelope ballistics: Attack ~ 10ms, Release ~ 80ms
    attackCoeff_ = std::exp(-1.0 / (sampleRate_ * 0.010));
    releaseCoeff_ = std::exp(-1.0 / (sampleRate_ * 0.080));

    updateFilters();
    reset();
}

void DynamicBass::reset() {
    yHpMid_.reset();
    yLpMid_.reset();
    yLpSide_.reset();
    xHpBass_.reset();
    xLpBass_.reset();
    envelope_ = 0.0;
}

void DynamicBass::getPresetValues(int preset, int& xLow, int& xHigh,
                                  int& yLow, int& yHigh,
                                  double& sideGainLow, double& sideGainHigh) {
    switch (preset) {
        case 1: // Extreme Headphone v2
            xLow = 140; xHigh = 6200; yLow = 40; yHigh = 60; sideGainLow = 0.10; sideGainHigh = 0.80; break;
        case 2: // High-End Headphone v2
            xLow = 180; xHigh = 5800; yLow = 55; yHigh = 80; sideGainLow = 0.10; sideGainHigh = 0.70; break;
        case 3: // Common Headphone v2
            xLow = 300; xHigh = 5600; yLow = 60; yHigh = 105; sideGainLow = 0.10; sideGainHigh = 0.50; break;
        case 4: // Low-End Headphone v2
            xLow = 600; xHigh = 5400; yLow = 60; yHigh = 105; sideGainLow = 0.10; sideGainHigh = 0.20; break;
        case 5: // Common Earphone v2
            xLow = 100; xHigh = 5600; yLow = 40; yHigh = 80; sideGainLow = 0.50; sideGainHigh = 0.50; break;
        case 6: // Extreme Headphone v1
            xLow = 1200; xHigh = 6200; yLow = 40; yHigh = 80; sideGainLow = 0.0; sideGainHigh = 0.20; break;
        case 7: // High-End Headphone v1
            xLow = 1000; xHigh = 6200; yLow = 40; yHigh = 80; sideGainLow = 0.0; sideGainHigh = 0.10; break;
        case 8: // Common Headphone v1
            xLow = 800; xHigh = 6200; yLow = 40; yHigh = 80; sideGainLow = 0.10; sideGainHigh = 0.0; break;
        case 9: // Common Earphone v1
            xLow = 400; xHigh = 6200; yLow = 40; yHigh = 80; sideGainLow = 0.10; sideGainHigh = 0.0; break;
        default:
            break;
    }
}

void DynamicBass::setParams(bool enabled, double strength, int xLow, int xHigh,
                            int yLow, int yHigh, double sideGainLow, double sideGainHigh,
                            int devicePreset) {
    const bool presetChanged = (devicePreset != devicePreset_);
    enabled_ = enabled;
    devicePreset_ = devicePreset;

    if (devicePreset_ > 0 && devicePreset_ <= 9) {
        getPresetValues(devicePreset_, xLow_, xHigh_, yLow_, yHigh_, sideGainLow_, sideGainHigh_);
    } else {
        xLow_ = std::clamp(xLow, 20, 2400);
        xHigh_ = std::clamp(xHigh, 500, 12000);
        yLow_ = std::clamp(yLow, 20, 200);
        yHigh_ = std::clamp(yHigh, 30, 300);
        sideGainLow_ = std::clamp(sideGainLow, 0.0, 1.0);
        sideGainHigh_ = std::clamp(sideGainHigh, 0.0, 1.0);
    }

    // strength: 1.0 to 8.0 (default 1.0)
    strength_ = std::clamp(strength, 0.0, 8.0);

    updateFilters();
    // Preset changes move the filter cutoffs; clear retained state so the swap
    // does not click.
    if (presetChanged) reset();
}

void DynamicBass::updateFilters() {
    const double q = 0.7071067811865475;
    yHpMid_.setHighPass(sampleRate_, static_cast<double>(yLow_), q);
    yLpMid_.setLowPass(sampleRate_, static_cast<double>(yHigh_), q);
    yLpSide_.setLowPass(sampleRate_, static_cast<double>(yHigh_), q);
    // FIX C-5: the X-band defines the acoustic response range around the
    // boosted Y band. The X cutoffs are clamped to the Y band edges so the X
    // high-pass can never reject the boosted content (every preset has
    // xLow > yLow, which would otherwise silence the stage).
    xHpBass_.setHighPass(sampleRate_, std::min<double>(static_cast<double>(xLow_),
                                                       static_cast<double>(yLow_)), q);
    xLpBass_.setLowPass(sampleRate_, std::max<double>(static_cast<double>(xHigh_),
                                                      static_cast<double>(yHigh_)), q);
}

void DynamicBass::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || channels != 2 || strength_ <= 0.001 || buffer == nullptr || frames <= 0) {
        return;
    }

    const double str = strength_;
    const double sLow = sideGainLow_;
    const double sHigh = sideGainHigh_;

    for (int i = 0; i < frames; ++i) {
        const int idx = i * 2;
        const double L = buffer[idx];
        const double R = buffer[idx + 1];

        // 1. Mid-Side decomposition
        const double M = 0.5 * (L + R);
        const double S = 0.5 * (L - R);

        // Y-band isolates the sub-bass that receives the dynamic boost. The X
        // filters are preset-defined but must not be cascaded after the Y
        // band-pass: every preset has xLow > yHigh, so the X high-pass would
        // reject the whole Y band and silence the stage. Keep X as a low-pass
        // shaper on the boosted tap only (transparent below xHigh).
        const double yBand = yLpMid_.process(yHpMid_.process(M));
        const double midY = xLpBass_.process(xHpBass_.process(yBand));

        // 3. Peak envelope follower on sub-bass punch
        const double absY = std::abs(midY);
        if (absY > envelope_) {
            envelope_ = attackCoeff_ * envelope_ + (1.0 - attackCoeff_) * absY;
        } else {
            envelope_ = releaseCoeff_ * envelope_ + (1.0 - releaseCoeff_) * absY;
        }
        if (!std::isfinite(envelope_)) envelope_ = 0.0;

        // 4. Dynamic gain computer:
        //    Boosts quiet/medium bass passages with smooth soft saturation (tanh)
        //    when envelope is large to prevent digital clipping
        const double dynamicGain = str / (1.0 + 1.8 * envelope_);
        double bassBoost = midY * dynamicGain;

        // Psychoacoustic harmonic excitation for earphone reproduction. Uses a
        // sign-preserving (odd) nonlinearity so it enriches harmonics WITHOUT
        // the DC offset / envelope pumping of the previous x^2 term.
        const double harmonicExcitation = 0.15 * bassBoost * std::abs(bassBoost);
        bassBoost = std::tanh(bassBoost + harmonicExcitation);

        // 5. Sub-band Side Spatial Imaging:
        //    Extract low frequencies of side channel and scale by sideGainLow (mono bass)
        //    High frequencies of side channel scaled by sideGainHigh (wide spatial air)
        const double sideLow = yLpSide_.process(S);
        const double sideHigh = S - sideLow;
        const double sideProcessed = sideLow * sLow + sideHigh * sHigh;

        // 6. Recombine Mid and Side
        double midOut = M + bassBoost;
        if (!std::isfinite(midOut) || !std::isfinite(sideProcessed)) {
            midOut = M;
        }
        buffer[idx] = static_cast<float>(midOut + sideProcessed);
        buffer[idx + 1] = static_cast<float>(midOut - sideProcessed);
    }
}
