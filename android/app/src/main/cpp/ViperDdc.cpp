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

// Denominator 1 + a1 z^-1 + a2 z^-2 has both poles strictly inside the unit
// circle iff |a2| < 1 and |a1| < 1 + a2.
bool stableSection(const ViperDdcSection& s) {
    return std::isfinite(s.a1) && std::isfinite(s.a2) &&
           std::abs(s.a2) < 1.0 && std::abs(s.a1) < 1.0 + s.a2;
}

// .vdc files exist in both transfer-function conventions: some store the
// denominator as `1 + a1 z^-1 + a2 z^-2` (the form the DF-II recurrence here
// expects) and some store the `y = ... - a1 y1 - a2 y2` form (already
// negated). Detect the convention by majority stability and flip if needed,
// then drop any section that is still unstable so a malformed file can never
// blow up the audio stream.
void sanitizeSections(std::vector<ViperDdcSection>& sections) {
    if (sections.empty()) return;
    int stable = 0;
    for (auto& s : sections) {
        if (stableSection(s)) ++stable;
    }
    if (stable * 2 < static_cast<int>(sections.size())) {
        for (auto& s : sections) {
            s.a1 = -s.a1;
            s.a2 = -s.a2;
        }
    }
    sections.erase(std::remove_if(sections.begin(), sections.end(),
        [](const ViperDdcSection& s) { return !stableSection(s); }),
        sections.end());
}

void buildSectionsFromNums(const std::vector<double>& nums,
                           std::vector<ViperDdcSection>& out) {
    const int count = std::min(static_cast<int>(nums.size() / 5), ViperDdc::MAX_SECTIONS);
    for (int i = 0; i < count; ++i) {
        ViperDdcSection s;
        s.b0 = nums[i * 5 + 0];
        s.b1 = nums[i * 5 + 1];
        s.b2 = nums[i * 5 + 2];
        s.a1 = nums[i * 5 + 3];
        s.a2 = nums[i * 5 + 4];
        out.push_back(s);
    }
}
} // namespace

ViperDdc::ViperDdc() {
    sections441_.reserve(MAX_SECTIONS);
    sections480_.reserve(MAX_SECTIONS);
    activeSections_.reserve(MAX_SECTIONS);
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

bool ViperDdc::parseVdcContent(const std::string& vdcContent,
                               std::vector<ViperDdcSection>& out441,
                               std::vector<ViperDdcSection>& out480) {
    out441.clear();
    out480.clear();
    out441.reserve(MAX_SECTIONS);
    out480.reserve(MAX_SECTIONS);
    if (vdcContent.empty()) return false;

    auto pos441 = vdcContent.find("SR_44100");
    auto pos480 = vdcContent.find("SR_48000");

    if (pos441 == std::string::npos && pos480 == std::string::npos) {
        // Fallback: parse whatever floats exist in groups of 5
        buildSectionsFromNums(parseFloats(vdcContent), out480);
        out441 = out480;
    } else {
        if (pos441 != std::string::npos) {
            std::string sub441;
            if (pos480 != std::string::npos && pos480 > pos441) {
                sub441 = vdcContent.substr(pos441 + 8, pos480 - (pos441 + 8));
            } else {
                sub441 = vdcContent.substr(pos441 + 8);
            }
            buildSectionsFromNums(parseFloats(sub441), out441);
        }

        if (pos480 != std::string::npos) {
            std::string sub480;
            if (pos441 != std::string::npos && pos441 > pos480) {
                sub480 = vdcContent.substr(pos480 + 8, pos441 - (pos480 + 8));
            } else {
                sub480 = vdcContent.substr(pos480 + 8);
            }
            buildSectionsFromNums(parseFloats(sub480), out480);
        }

        if (out441.empty() && !out480.empty()) out441 = out480;
        if (out480.empty() && !out441.empty()) out480 = out441;
    }

    sanitizeSections(out441);
    sanitizeSections(out480);
    return !out441.empty() || !out480.empty();
}

void ViperDdc::applyPreparedSections(const std::vector<ViperDdcSection>& s441,
                                     const std::vector<ViperDdcSection>& s480) {
    sections441_.clear();
    sections480_.clear();
    const int n441 = std::min(static_cast<int>(s441.size()), MAX_SECTIONS);
    for (int i = 0; i < n441; ++i) {
        Section sec;
        sec.b0 = s441[i].b0; sec.b1 = s441[i].b1; sec.b2 = s441[i].b2;
        sec.a1 = s441[i].a1; sec.a2 = s441[i].a2;
        sections441_.push_back(sec);
    }
    const int n480 = std::min(static_cast<int>(s480.size()), MAX_SECTIONS);
    for (int i = 0; i < n480; ++i) {
        Section sec;
        sec.b0 = s480[i].b0; sec.b1 = s480[i].b1; sec.b2 = s480[i].b2;
        sec.a1 = s480[i].a1; sec.a2 = s480[i].a2;
        sections480_.push_back(sec);
    }
    updateActiveSections();
}

bool ViperDdc::loadVdcString(const std::string& vdcContent) {
    if (vdcContent.empty()) {
        sections441_.clear();
        sections480_.clear();
        activeSections_.clear();
        loadedContent_.clear();
        prepared441_.reset();
        prepared480_.reset();
        return false;
    }

    if (vdcContent == loadedContent_) {
        return true;
    }

    std::vector<ViperDdcSection> s441;
    std::vector<ViperDdcSection> s480;
    if (!parseVdcContent(vdcContent, s441, s480)) {
        loadedContent_.clear();
        return false;
    }

    loadedContent_ = vdcContent;
    applyPreparedSections(s441, s480);
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
    // Preferred path: sections were parsed off the audio thread by the JNI
    // setter. Only copy them in (pre-reserved storage -> no allocation).
    if (params.sections441 || params.sections480) {
        if (params.sections441 != prepared441_ || params.sections480 != prepared480_) {
            prepared441_ = params.sections441;
            prepared480_ = params.sections480;
            static const std::vector<ViperDdcSection> kEmpty;
            applyPreparedSections(params.sections441 ? *params.sections441 : kEmpty,
                                  params.sections480 ? *params.sections480 : kEmpty);
        }
        return;
    }
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
            if (!std::isfinite(wL) || !std::isfinite(yL)) {
                sec.v1L = 0.0; sec.v2L = 0.0; wL = 0.0; yL = 0.0;
            }
            if (std::abs(wL) < 1e-30) wL = 0.0;
            sec.v2L = sec.v1L; sec.v1L = wL;
            l = yL;

            double wR = r - sec.a1 * sec.v1R - sec.a2 * sec.v2R;
            double yR = sec.b0 * wR + sec.b1 * sec.v1R + sec.b2 * sec.v2R;
            if (!std::isfinite(wR) || !std::isfinite(yR)) {
                sec.v1R = 0.0; sec.v2R = 0.0; wR = 0.0; yR = 0.0;
            }
            if (std::abs(wR) < 1e-30) wR = 0.0;
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
            if (!std::isfinite(wL) || !std::isfinite(yL)) {
                sec.v1L = 0.0; sec.v2L = 0.0; wL = 0.0; yL = 0.0;
            }
            if (std::abs(wL) < 1e-30) wL = 0.0;
            sec.v2L = sec.v1L; sec.v1L = wL;
            l = yL;

            double wR = r - sec.a1 * sec.v1R - sec.a2 * sec.v2R;
            double yR = sec.b0 * wR + sec.b1 * sec.v1R + sec.b2 * sec.v2R;
            if (!std::isfinite(wR) || !std::isfinite(yR)) {
                sec.v1R = 0.0; sec.v2R = 0.0; wR = 0.0; yR = 0.0;
            }
            if (std::abs(wR) < 1e-30) wR = 0.0;
            sec.v2R = sec.v1R; sec.v1R = wR;
            r = yR;
        }

        buffer[i * channels] = static_cast<float>(l);
        buffer[i * channels + 1] = static_cast<float>(r);
    }
}
