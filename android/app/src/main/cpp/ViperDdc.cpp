// android/app/src/main/cpp/ViperDdc.cpp
#include "ViperDdc.h"
#include <sstream>
#include <algorithm>
#include <cstring>

namespace {
std::vector<double> parseFloats(const std::string& str) {
    std::vector<double> numbers;
    std::string token;
    for (char ch : str) {
        if (ch == ',' || ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == ';') {
            if (!token.empty()) {
                try {
                    numbers.push_back(std::stod(token));
                } catch (...) {}
                token.clear();
            }
        } else {
            token += ch;
        }
    }
    if (!token.empty()) {
        try {
            numbers.push_back(std::stod(token));
        } catch (...) {}
    }
    return numbers;
}
} // namespace

ViperDdc::ViperDdc() {
    setSampleRate(48000.0);
    reset();
}

void ViperDdc::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    sampleRate_ = sampleRate;
    updateActiveSections();
}

void ViperDdc::reset() {
    for (auto& sec : activeSections_) {
        sec.v1L = 0.0; sec.v2L = 0.0;
        sec.v1R = 0.0; sec.v2R = 0.0;
    }
    for (auto& sec : sections441_) {
        sec.v1L = 0.0; sec.v2L = 0.0;
        sec.v1R = 0.0; sec.v2R = 0.0;
    }
    for (auto& sec : sections480_) {
        sec.v1L = 0.0; sec.v2L = 0.0;
        sec.v1R = 0.0; sec.v2R = 0.0;
    }
}

int ViperDdc::getSectionCount() const {
    return static_cast<int>(activeSections_.size());
}

bool ViperDdc::loadVdcString(const std::string& vdcContent) {
    if (vdcContent.empty()) {
        sections441_.clear();
        sections480_.clear();
        activeSections_.clear();
        loadedContent_.clear();
        return false;
    }

    if (vdcContent == loadedContent_) {
        return true;
    }

    loadedContent_ = vdcContent;
    sections441_.clear();
    sections480_.clear();

    auto pos441 = vdcContent.find("SR_44100");
    auto pos480 = vdcContent.find("SR_48000");

    if (pos441 == std::string::npos && pos480 == std::string::npos) {
        // Fallback: parse whatever floats exist in groups of 5
        auto nums = parseFloats(vdcContent);
        int count = static_cast<int>(nums.size() / 5);
        for (int i = 0; i < count; ++i) {
            Section s;
            s.b0 = nums[i * 5 + 0];
            s.b1 = nums[i * 5 + 1];
            s.b2 = nums[i * 5 + 2];
            s.a1 = -nums[i * 5 + 3];
            s.a2 = -nums[i * 5 + 4];
            sections480_.push_back(s);
        }
        sections441_ = sections480_;
    } else {
        if (pos441 != std::string::npos) {
            std::string sub441;
            if (pos480 != std::string::npos && pos480 > pos441) {
                sub441 = vdcContent.substr(pos441 + 8, pos480 - (pos441 + 8));
            } else {
                sub441 = vdcContent.substr(pos441 + 8);
            }
            auto nums = parseFloats(sub441);
            int count = static_cast<int>(nums.size() / 5);
            for (int i = 0; i < count; ++i) {
                Section s;
                s.b0 = nums[i * 5 + 0];
                s.b1 = nums[i * 5 + 1];
                s.b2 = nums[i * 5 + 2];
                s.a1 = -nums[i * 5 + 3];
                s.a2 = -nums[i * 5 + 4];
                sections441_.push_back(s);
            }
        }

        if (pos480 != std::string::npos) {
            std::string sub480;
            if (pos441 != std::string::npos && pos441 > pos480) {
                sub480 = vdcContent.substr(pos480 + 8, pos441 - (pos480 + 8));
            } else {
                sub480 = vdcContent.substr(pos480 + 8);
            }
            auto nums = parseFloats(sub480);
            int count = static_cast<int>(nums.size() / 5);
            for (int i = 0; i < count; ++i) {
                Section s;
                s.b0 = nums[i * 5 + 0];
                s.b1 = nums[i * 5 + 1];
                s.b2 = nums[i * 5 + 2];
                s.a1 = -nums[i * 5 + 3];
                s.a2 = -nums[i * 5 + 4];
                sections480_.push_back(s);
            }
        }

        if (sections441_.empty() && !sections480_.empty()) sections441_ = sections480_;
        if (sections480_.empty() && !sections441_.empty()) sections480_ = sections441_;
    }

    updateActiveSections();
    return !activeSections_.empty();
}

void ViperDdc::updateActiveSections() {
    // If the sample rate is closer to 44.1k (or multiple like 88.2k, 176.4k), use sections441_
    // Otherwise use sections480_ (48k, 96k, 192k)
    long sr = static_cast<long>(sampleRate_);
    bool is441Family = (sr % 44100 == 0) || (std::abs(sampleRate_ - 44100.0) < std::abs(sampleRate_ - 48000.0));

    if (is441Family && !sections441_.empty()) {
        activeSections_ = sections441_;
    } else if (!sections480_.empty()) {
        activeSections_ = sections480_;
    } else if (!sections441_.empty()) {
        activeSections_ = sections441_;
    } else {
        activeSections_.clear();
    }
    reset();
}

void ViperDdc::applyParams(const ViperDdcParamSet& params) {
    enabled_ = params.enabled;
    profileName_ = params.profileName;
    if (!params.ddcContent.empty() && params.ddcContent != loadedContent_) {
        loadVdcString(params.ddcContent);
    }
}

void ViperDdc::process(float* L, float* R, int frames) {
    if (!enabled_ || activeSections_.empty() || !L || !R || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        double l = L[i];
        double r = R[i];
        if (!std::isfinite(l)) l = 0.0;
        if (!std::isfinite(r)) r = 0.0;

        for (auto& sec : activeSections_) {
            double wL = l - sec.a1 * sec.v1L - sec.a2 * sec.v2L;
            double yL = sec.b0 * wL + sec.b1 * sec.v1L + sec.b2 * sec.v2L;
            sec.v2L = sec.v1L; sec.v1L = wL;
            l = yL;

            double wR = r - sec.a1 * sec.v1R - sec.a2 * sec.v2R;
            double yR = sec.b0 * wR + sec.b1 * sec.v1R + sec.b2 * sec.v2R;
            sec.v2R = sec.v1R; sec.v1R = wR;
            r = yR;
        }

        L[i] = static_cast<float>(l);
        R[i] = static_cast<float>(r);
    }
}

void ViperDdc::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || activeSections_.empty() || !buffer || frames <= 0 || channels < 2) return;

    for (int i = 0; i < frames; ++i) {
        double l = buffer[i * channels];
        double r = buffer[i * channels + 1];
        if (!std::isfinite(l)) l = 0.0;
        if (!std::isfinite(r)) r = 0.0;

        for (auto& sec : activeSections_) {
            double wL = l - sec.a1 * sec.v1L - sec.a2 * sec.v2L;
            double yL = sec.b0 * wL + sec.b1 * sec.v1L + sec.b2 * sec.v2L;
            sec.v2L = sec.v1L; sec.v1L = wL;
            l = yL;

            double wR = r - sec.a1 * sec.v1R - sec.a2 * sec.v2R;
            double yR = sec.b0 * wR + sec.b1 * sec.v1R + sec.b2 * sec.v2R;
            sec.v2R = sec.v1R; sec.v1R = wR;
            r = yR;
        }

        buffer[i * channels] = static_cast<float>(l);
        buffer[i * channels + 1] = static_cast<float>(r);
    }
}
