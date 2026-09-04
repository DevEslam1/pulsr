// android/app/src/main/cpp/FftUtil.h
#pragma once

#if defined(__FAST_MATH__)
#error "-ffast-math leaked into the DSP build — check CMake / gradle compiler flags"
#endif

#include <cmath>
#include <vector>
#include <complex>
#include <algorithm>

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
    bitReverse(a);

    for (int len = 2; len <= n; len <<= 1) {
        const double ang = 2.0 * M_PI / len * (invert ? -1.0 : 1.0);
        const Complex wlen(static_cast<float>(std::cos(ang)), static_cast<float>(std::sin(ang)));

        for (int i = 0; i < n; i += len) {
            Complex w(1.0f, 0.0f);
            for (int j = 0; j < len / 2; ++j) {
                const Complex u = a[i + j];
                const Complex v = a[i + j + len / 2] * w;
                a[i + j] = u + v;
                a[i + j + len / 2] = u - v;
                w *= wlen;
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
