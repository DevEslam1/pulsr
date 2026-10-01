// android/app/src/main/cpp/FftUtil.h
#pragma once

#if defined(__FAST_MATH__)
#error "-ffast-math leaked into the DSP build — check CMake / gradle compiler flags"
#endif

#include <cmath>
#include <vector>
#include <complex>
#include <algorithm>
#include <cassert>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace FftUtil {

using Complex = std::complex<float>;

inline void bitReverse(std::vector<Complex>& a) {
    const int n = static_cast<int>(a.size());
    for (int i = 1, j = 0; i < n; ++i) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }
        j ^= bit;
        if (i < j) {
            std::swap(a[i], a[j]);
        }
    }
}

inline void fft(std::vector<Complex>& a, bool invert = false) {
    const int n = static_cast<int>(a.size());
    // The radix-2 Cooley-Tukey butterflies below require a power-of-two length.
    assert(n > 0 && (n & (n - 1)) == 0 && "FftUtil::fft size must be a power of two");
    bitReverse(a);

    for (int len = 2; len <= n; len <<= 1) {
        const int half = len >> 1;
        const double ang = 2.0 * M_PI / static_cast<double>(len) * (invert ? -1.0 : 1.0);

        // FIX M-1: derive every twiddle directly from the double-precision angle
        // j*ang instead of carrying a running float product (w *= wlen). The old
        // recurrence accumulated rounding error across up to len/2 (512 for
        // N=1024) complex multiplies per stage; computing cos/sin from an
        // independent double angle and narrowing to float keeps each twiddle at
        // full float accuracy. Looping j outside i computes each twiddle once per
        // stage and reuses it across all butterfly blocks (~N-1 cos/sin per FFT).
        for (int j = 0; j < half; ++j) {
            const double angJ = ang * static_cast<double>(j);
            const Complex w(static_cast<float>(std::cos(angJ)),
                            static_cast<float>(std::sin(angJ)));
            for (int i = 0; i < n; i += len) {
                const Complex u = a[i + j];
                const Complex v = a[i + j + half] * w;
                a[i + j]        = u + v;
                a[i + j + half] = u - v;
            }
        }
    }

    if (invert) {
        const float invN = 1.0f / static_cast<float>(n);
        for (int i = 0; i < n; ++i) {
            a[i] *= invN;
        }
    }
}

} // namespace FftUtil
