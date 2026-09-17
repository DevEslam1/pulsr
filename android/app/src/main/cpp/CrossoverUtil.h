// android/app/src/main/cpp/CrossoverUtil.h
#pragma once

#include <cmath>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// 2nd-order Biquad filter (two cascaded form an LR4 Linkwitz-Riley crossover)
class Biquad {
public:
    Biquad() { reset(); }

    void reset() {
        x1_ = x2_ = y1_ = y2_ = 0.0;
    }

    void setLowPass(double sampleRate, double cutoffHz, double q = 0.7071067811865475) {
        if (sampleRate <= 0.0 || cutoffHz <= 0.0) return;
        const double w0 = 2.0 * M_PI * std::clamp(cutoffHz, 10.0, sampleRate * 0.499) / sampleRate;
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double alpha = sinw0 / (2.0 * std::max(q, 0.01));

        const double a0 = 1.0 + alpha;
        b0_ = ((1.0 - cosw0) / 2.0) / a0;
        b1_ = (1.0 - cosw0) / a0;
        b2_ = ((1.0 - cosw0) / 2.0) / a0;
        a1_ = (-2.0 * cosw0) / a0;
        a2_ = (1.0 - alpha) / a0;
    }

    void setHighPass(double sampleRate, double cutoffHz, double q = 0.7071067811865475) {
        if (sampleRate <= 0.0 || cutoffHz <= 0.0) return;
        const double w0 = 2.0 * M_PI * std::clamp(cutoffHz, 10.0, sampleRate * 0.499) / sampleRate;
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double alpha = sinw0 / (2.0 * std::max(q, 0.01));

        const double a0 = 1.0 + alpha;
        b0_ = ((1.0 + cosw0) / 2.0) / a0;
        b1_ = -(1.0 + cosw0) / a0;
        b2_ = ((1.0 + cosw0) / 2.0) / a0;
        a1_ = (-2.0 * cosw0) / a0;
        a2_ = (1.0 - alpha) / a0;
    }

    inline double process(double in) {
        // Guard against a non-finite input poisoning the recursive state, and
        // flush subnormal state during silence (ARM denormal CPU spikes).
        if (!std::isfinite(in)) {
            reset();
            return 0.0;
        }
        double out = b0_ * in + b1_ * x1_ + b2_ * x2_ - a1_ * y1_ - a2_ * y2_;
        if (!std::isfinite(out)) {
            reset();
            return 0.0;
        }
        x2_ = x1_;
        x1_ = in;
        y2_ = y1_;
        y1_ = out;
        if (std::abs(out) < 1e-30 && std::abs(x1_) < 1e-30 && std::abs(x2_) < 1e-30 &&
            std::abs(y1_) < 1e-30 && std::abs(y2_) < 1e-30) {
            reset();
        }
        return out;
    }

private:
    double b0_ = 1.0, b1_ = 0.0, b2_ = 0.0;
    double a1_ = 0.0, a2_ = 0.0;
    double x1_ = 0.0, x2_ = 0.0;
    double y1_ = 0.0, y2_ = 0.0;
};

// Linkwitz-Riley 4th order filter pair (LP and HP with flat summing magnitude)
class LinkwitzRiley4 {
public:
    void reset() {
        lp1_L.reset(); lp2_L.reset();
        lp1_R.reset(); lp2_R.reset();
        hp1_L.reset(); hp2_L.reset();
        hp1_R.reset(); hp2_R.reset();
    }

    void configure(double sampleRate, double cutoffHz) {
        const double newCutoff = std::clamp(cutoffHz, 20.0, sampleRate * 0.48);
        // Retuning a live crossover must clear the old filter state, otherwise
        // the retained registers (belonging to the previous cutoff) produce a
        // transient/instability. Skip the reset when nothing actually moved so
        // repeated applyParams calls don't click.
        const bool changed =
            std::abs(newCutoff - cutoffHz_) > 0.01 || std::abs(sampleRate - sampleRate_) > 0.5;
        cutoffHz_ = newCutoff;
        sampleRate_ = sampleRate;
        const double q = 0.7071067811865475; // Butterworth Q
        lp1_L.setLowPass(sampleRate_, cutoffHz_, q);
        lp2_L.setLowPass(sampleRate_, cutoffHz_, q);
        lp1_R.setLowPass(sampleRate_, cutoffHz_, q);
        lp2_R.setLowPass(sampleRate_, cutoffHz_, q);

        hp1_L.setHighPass(sampleRate_, cutoffHz_, q);
        hp2_L.setHighPass(sampleRate_, cutoffHz_, q);
        hp1_R.setHighPass(sampleRate_, cutoffHz_, q);
        hp2_R.setHighPass(sampleRate_, cutoffHz_, q);

        if (changed) {
            reset();
        }
    }

    inline void process(double inL, double inR, double& outLpL, double& outLpR, double& outHpL, double& outHpR) {
        outLpL = lp2_L.process(lp1_L.process(inL));
        outLpR = lp2_R.process(lp1_R.process(inR));
        outHpL = hp2_L.process(hp1_L.process(inL));
        outHpR = hp2_R.process(hp1_R.process(inR));
    }

private:
    double sampleRate_ = 48000.0;
    double cutoffHz_ = 1000.0;
    Biquad lp1_L, lp2_L, lp1_R, lp2_R;
    Biquad hp1_L, hp2_L, hp1_R, hp2_R;
};
