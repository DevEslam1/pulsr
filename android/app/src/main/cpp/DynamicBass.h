// android/app/src/main/cpp/DynamicBass.h
#pragma once

#include <cmath>
#include <algorithm>
#include <atomic>
#include "CrossoverUtil.h"

/**
 * DynamicBass: Modeled after ViPER4Android's famous "Dynamic System" / Dynamic Bass.
 *
 * Provides physical punch and visceral bass weight for headphones and earphones
 * without the muddy bloat of static shelf boosts.
 *
 * Features:
 * - Mid-Side sub-band extraction
 * - Y-Band Sub-Bass Isolation (yLow to yHigh Hz)
 * - Peak envelope follower with smooth attack/release ballistics
 * - Dynamic gain computer: boosts quiet/thin bass while smoothly saturating (tanh) loud notes
 * - Psychoacoustic subtle harmonic synthesis for earphone driver bass perception
 * - Mid-Side stereo staging (sideGainLow for tight mono sub, sideGainHigh for spatial stage)
 * - 9 ViPER-compatible headphone device presets + Custom mode
 */
class DynamicBass {
public:
    DynamicBass();
    ~DynamicBass() = default;

    void prepare(double sampleRate);
    void reset();

    void setParams(bool enabled, double strength, int xLow, int xHigh,
                   int yLow, int yHigh, double sideGainLow, double sideGainHigh,
                   int devicePreset);

    void processInterleaved(float* buffer, int frames, int channels);

    bool isEnabled() const { return enabled_; }

    static void getPresetValues(int preset, int& xLow, int& xHigh,
                                int& yLow, int& yHigh,
                                double& sideGainLow, double& sideGainHigh);

private:
    void updateFilters();

    double sampleRate_ = 48000.0;
    bool enabled_ = false;
    double strength_ = 1.0;     // 1.0 to 8.0 (or normalized 0.0 - 1.0)
    int xLow_ = 100;
    int xHigh_ = 5600;
    int yLow_ = 40;
    int yHigh_ = 80;
    double sideGainLow_ = 0.10;
    double sideGainHigh_ = 0.50;
    int devicePreset_ = 0;      // 0 = Custom, 1..9 = Presets

    // Filters for Mid channel sub-bass Y-band extraction
    Biquad yHpMid_;
    Biquad yLpMid_;

    // Filter for Side channel low-band extraction
    Biquad yLpSide_;

    // Filters for X-band acoustic response range [xLow, xHigh] Hz
    Biquad xHpBass_;   // high-pass at xLow
    Biquad xLpBass_;   // low-pass at xHigh

    // Dynamic envelope follower
    double envelope_ = 0.0;
    double attackCoeff_ = 0.0;
    double releaseCoeff_ = 0.0;

    std::atomic<bool> paramsChanged_{false};
    bool pendingEnabled_ = false;
    double pendingStrength_ = 1.0;
    int pendingXLow_ = 100;
    int pendingXHigh_ = 5600;
    int pendingYLow_ = 40;
    int pendingYHigh_ = 80;
    double pendingSideGainLow_ = 0.10;
    double pendingSideGainHigh_ = 0.50;
    int pendingDevicePreset_ = 0;
};
