// android/app/src/main/cpp/LoudnessContour.h
#pragma once

#include "DspParams.h"
#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Fletcher-Munson (equal-loudness) contour compensation: as the playback
// volume-stage value drops, hearing becomes relatively less sensitive to
// bass and (to a lesser degree) treble. This stage applies a gentle low-
// shelf lift (~100 Hz) and smaller high-shelf lift (~8 kHz) whose magnitude
// follows (1 - volume)^1.5 scaled by user intensity. Computed against the
// current volume-stage value pushed from Dart; zero lift at full volume.
class LoudnessContour {
public:
    static constexpr int MAX_CHANNELS = 8;

    LoudnessContour();

    void setSampleRate(double sampleRate);
    // intensity: 0..1 user amount; volumeLinear: current volume-stage value 0..1.
    void configure(double intensity, double volumeLinear);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const LoudnessContourParamSet& params);
    void reset();

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

    // Diagnostics/tests: target shelf gains for the current intensity+volume
    double getTargetBassDb() const { return targetBassDb_; }
    double getTargetTrebleDb() const { return targetTrebleDb_; }
    // Current (smoothed) applied shelf gains
    double getCurrentBassDb() const { return currentBassDb_; }
    double getCurrentTrebleDb() const { return currentTrebleDb_; }

private:
    static constexpr double kBassShelfHz = 100.0;
    static constexpr double kTrebleShelfHz = 8000.0;
    static constexpr double kBassMaxDb = 10.0;
    static constexpr double kTrebleMaxDb = 4.0;

    struct Biquad {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
        double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
        inline float process(float x) {
            const double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
            x2 = x1; x1 = x;
            y2 = y1; y1 = y;
            return static_cast<float>(y);
        }
    };

    static void computeLowShelf(Biquad& bq, double f0, double gainDb, double sampleRate);
    static void computeHighShelf(Biquad& bq, double f0, double gainDb, double sampleRate);
    void updateTargetGains();
    void rampTowardTarget(int frames = 512); // time-based smoothing

    double sampleRate_ = 48000.0;
    double intensity_ = 0.0;
    double volumeLinear_ = 1.0;
    double targetBassDb_ = 0.0;
    double targetTrebleDb_ = 0.0;
    double currentBassDb_ = 0.0;
    double currentTrebleDb_ = 0.0;
    double lastComputedBassDb_ = 1e9;
    double lastComputedTrebleDb_ = 1e9;
    bool enabled_ = false;

    Biquad bass_[MAX_CHANNELS];
    Biquad treble_[MAX_CHANNELS];
};
