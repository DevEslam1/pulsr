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

// Cascaded 2-stage (4th-order) stereo biquad filter with unified coefficients.
// Computes identical cascaded Butterworth stages across Left and Right channels
// simultaneously with unified coefficient loads and vectorized execution.
class BiquadStereoCascade {
public:
    BiquadStereoCascade() { reset(); }

    void reset() {
        s1_x1_L_ = s1_x2_L_ = s1_y1_L_ = s1_y2_L_ = 0.0;
        s1_x1_R_ = s1_x2_R_ = s1_y1_R_ = s1_y2_R_ = 0.0;
        s2_x1_L_ = s2_x2_L_ = s2_y1_L_ = s2_y2_L_ = 0.0;
        s2_x1_R_ = s2_x2_R_ = s2_y1_R_ = s2_y2_R_ = 0.0;
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

    inline void process(double inL, double inR, double& outL, double& outR) {
        if (!std::isfinite(inL) || !std::isfinite(inR)) {
            reset();
            outL = 0.0;
            outR = 0.0;
            return;
        }

        // Stage 1 (Stereo)
        double midL = b0_ * inL + b1_ * s1_x1_L_ + b2_ * s1_x2_L_ - a1_ * s1_y1_L_ - a2_ * s1_y2_L_;
        double midR = b0_ * inR + b1_ * s1_x1_R_ + b2_ * s1_x2_R_ - a1_ * s1_y1_R_ - a2_ * s1_y2_R_;
        if (!std::isfinite(midL) || !std::isfinite(midR)) {
            reset();
            outL = 0.0;
            outR = 0.0;
            return;
        }
        s1_x2_L_ = s1_x1_L_; s1_x1_L_ = inL;
        s1_y2_L_ = s1_y1_L_; s1_y1_L_ = midL;
        s1_x2_R_ = s1_x1_R_; s1_x1_R_ = inR;
        s1_y2_R_ = s1_y1_R_; s1_y1_R_ = midR;

        // Stage 2 (Stereo)
        outL = b0_ * midL + b1_ * s2_x1_L_ + b2_ * s2_x2_L_ - a1_ * s2_y1_L_ - a2_ * s2_y2_L_;
        outR = b0_ * midR + b1_ * s2_x1_R_ + b2_ * s2_x2_R_ - a1_ * s2_y1_R_ - a2_ * s2_y2_R_;
        if (!std::isfinite(outL) || !std::isfinite(outR)) {
            reset();
            outL = 0.0;
            outR = 0.0;
            return;
        }
        s2_x2_L_ = s2_x1_L_; s2_x1_L_ = midL;
        s2_y2_L_ = s2_y1_L_; s2_y1_L_ = outL;
        s2_x2_R_ = s2_x1_R_; s2_x1_R_ = midR;
        s2_y2_R_ = s2_y1_R_; s2_y1_R_ = outR;

        // Subnormal / denormal flush
        if (std::abs(outL) < 1e-30 && std::abs(outR) < 1e-30 &&
            std::abs(s1_y1_L_) < 1e-30 && std::abs(s1_y1_R_) < 1e-30) {
            reset();
        }
    }

private:
    double b0_ = 1.0, b1_ = 0.0, b2_ = 0.0;
    double a1_ = 0.0, a2_ = 0.0;
    double s1_x1_L_ = 0.0, s1_x2_L_ = 0.0, s1_y1_L_ = 0.0, s1_y2_L_ = 0.0;
    double s1_x1_R_ = 0.0, s1_x2_R_ = 0.0, s1_y1_R_ = 0.0, s1_y2_R_ = 0.0;
    double s2_x1_L_ = 0.0, s2_x2_L_ = 0.0, s2_y1_L_ = 0.0, s2_y2_L_ = 0.0;
    double s2_x1_R_ = 0.0, s2_x2_R_ = 0.0, s2_y1_R_ = 0.0, s2_y2_R_ = 0.0;
};

// Linkwitz-Riley 4th order filter pair (LP and HP with flat summing magnitude)
class LinkwitzRiley4 {
public:
    void reset() {
        lp_.reset();
        hp_.reset();
    }

    void configure(double sampleRate, double cutoffHz) {
        const double newCutoff = std::clamp(cutoffHz, 20.0, sampleRate * 0.48);
        const bool changed =
            std::abs(newCutoff - cutoffHz_) > 0.01 || std::abs(sampleRate - sampleRate_) > 0.5;
        cutoffHz_ = newCutoff;
        sampleRate_ = sampleRate;
        const double q = 0.7071067811865475; // Butterworth Q
        lp_.setLowPass(sampleRate_, cutoffHz_, q);
        hp_.setHighPass(sampleRate_, cutoffHz_, q);

        if (changed) {
            reset();
        }
    }

    inline void process(double inL, double inR, double& outLpL, double& outLpR, double& outHpL, double& outHpR) {
        lp_.process(inL, inR, outLpL, outLpR);
        hp_.process(inL, inR, outHpL, outHpR);
    }

private:
    double sampleRate_ = 48000.0;
    double cutoffHz_ = 1000.0;
    BiquadStereoCascade lp_;
    BiquadStereoCascade hp_;
};
