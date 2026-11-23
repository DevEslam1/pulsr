// android/app/src/main/cpp/ViperDdc.cpp
#include "ViperDdc.h"
#include <sstream>
#include <algorithm>
#include <cstring>
#include <cmath>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define PULSR_HAS_NEON 1
#elif defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>
#define PULSR_HAS_SSE2 1
#endif

namespace {
std::vector<double> parseFloats(const std::string& str) {
    std::vector<double> numbers;
    std::string token;
    for (char ch : str) {
        if (ch == ',' || ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == ';') {
            if (!token.empty()) {
                char* end = nullptr;
                double val = std::strtod(token.c_str(), &end);
                if (end != token.c_str() && std::isfinite(val)) {
                    numbers.push_back(val);
                }
                token.clear();
            }
        } else {
            token += ch;
        }
    }
    if (!token.empty()) {
        char* end = nullptr;
        double val = std::strtod(token.c_str(), &end);
        if (end != token.c_str() && std::isfinite(val)) {
            numbers.push_back(val);
        }
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
    crossfadeSections_.reserve(MAX_SECTIONS);
    setSampleRate(48000.0);
    reset();
}

void ViperDdc::setSampleRate(double sampleRate) {
    if (sampleRate < 8000.0) sampleRate = 8000.0;
    if (sampleRate > 768000.0) sampleRate = 768000.0;
    if (std::abs(sampleRate_ - sampleRate) < 0.5) return;
    sampleRate_ = sampleRate;
    updateActiveSections();
}

void ViperDdc::reset() {
    auto zeroSections = [](std::vector<Section>& secs) {
        for (auto& sec : secs) {
            std::fill(std::begin(sec.v1), std::end(sec.v1), 0);
            std::fill(std::begin(sec.v2), std::end(sec.v2), 0);
        }
    };
    zeroSections(activeSections_);
    zeroSections(sections441_);
    zeroSections(sections480_);
    crossfadeSections_.clear();
    sectionCrossfadeProgress_ = 1.0f;
    smoothedEnabledMix_ = (enabled_ && !activeSections_.empty()) ? 1.0f : 0.0f;
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

    const std::vector<Section>* target = nullptr;
    if (is441Family && !sections441_.empty()) {
        target = &sections441_;
    } else if (!sections480_.empty()) {
        target = &sections480_;
    } else if (!sections441_.empty()) {
        target = &sections441_;
    }

    if (target && !activeSections_.empty() && target->size() == activeSections_.size()) {
        bool identical = true;
        for (size_t s = 0; s < target->size(); ++s) {
            if ((*target)[s].b0 != activeSections_[s].b0 ||
                (*target)[s].b1 != activeSections_[s].b1 ||
                (*target)[s].b2 != activeSections_[s].b2 ||
                (*target)[s].a1 != activeSections_[s].a1 ||
                (*target)[s].a2 != activeSections_[s].a2) {
                identical = false;
                break;
            }
        }
        if (identical) return;
    }

    if (!activeSections_.empty() && (enabled_ || smoothedEnabledMix_ >= 1e-4f)) {
        crossfadeSections_.assign(activeSections_.begin(), activeSections_.end());
        sectionCrossfadeProgress_ = 0.0f;
    } else {
        crossfadeSections_.clear();
        sectionCrossfadeProgress_ = 1.0f;
    }

    if (target) {
        // Transfer filter history states from previous sections if matching in size
        const size_t oldSize = crossfadeSections_.size();
        activeSections_.assign(target->begin(), target->end());
        for (size_t s = 0; s < activeSections_.size() && s < oldSize; ++s) {
            for (int c = 0; c < MAX_CHANNELS; ++c) {
                activeSections_[s].v1[c] = crossfadeSections_[s].v1[c];
                activeSections_[s].v2[c] = crossfadeSections_[s].v2[c];
            }
        }
    } else {
        activeSections_.clear();
    }
}

void ViperDdc::applyParams(const ViperDdcParamSet& params) {
    enabled_ = params.enabled;
    // NOTE: do NOT copy params.profileName here. This runs on the audio thread
    // and std::string assignment can heap-allocate. The name is display-only and
    // is retained on the control thread; the DSP path never needs it.
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
    // If no prepared sections are supplied and ddcContent is empty, clear active sections
    // so loading an empty profile or clearing DDC cleanly deactivates filtering.
    if (params.ddcContent.empty()) {
        if (!activeSections_.empty() || prepared441_ || prepared480_) {
            sections441_.clear();
            sections480_.clear();
            activeSections_.clear();
            prepared441_.reset();
            prepared480_.reset();
            reset();
        }
        return;
    }
    // FIX M-18: never parse .vdc text on the audio thread. loadVdcString()
    // calls std::stod, grows std::vectors and copies on the heap — all of which
    // violate real-time constraints. The control-thread JNI setter is
    // responsible for parsing (parseVdcContent) and publishing the prepared
    // sections above. If no prepared sections are supplied, keep the previously
    // applied coefficients rather than parsing ddcContent here.
}

namespace {
#if defined(PULSR_F32_BIQUADS)
inline void filterDdcSample(std::vector<ViperDdc::Section>& sections, int ch, float& x) {
    for (auto& sec : sections) {
        const float a1_f = static_cast<float>(sec.a1);
        const float a2_f = static_cast<float>(sec.a2);
        const float b0_f = static_cast<float>(sec.b0);
        const float b1_f = static_cast<float>(sec.b1);
        const float b2_f = static_cast<float>(sec.b2);

        float w = x - a1_f * sec.v1[ch] - a2_f * sec.v2[ch];
        float y = b0_f * w + b1_f * sec.v1[ch] + b2_f * sec.v2[ch];
        if (!std::isfinite(w) || !std::isfinite(y)) {
            sec.v1[ch] = 0.0f; sec.v2[ch] = 0.0f; w = 0.0f; y = 0.0f;
        }
        if (std::abs(w) < 1e-30f) w = 0.0f;
        sec.v2[ch] = sec.v1[ch]; sec.v1[ch] = w;
        x = y;
    }
}
#else
inline void filterDdcSample(std::vector<ViperDdc::Section>& sections, int ch, double& x) {
    for (auto& sec : sections) {
        double w = x - sec.a1 * sec.v1[ch] - sec.a2 * sec.v2[ch];
        double y = sec.b0 * w + sec.b1 * sec.v1[ch] + sec.b2 * sec.v2[ch];
        if (!std::isfinite(w) || !std::isfinite(y)) {
            sec.v1[ch] = 0.0; sec.v2[ch] = 0.0; w = 0.0; y = 0.0;
        }
        if (std::abs(w) < 1e-30) w = 0.0;
        sec.v2[ch] = sec.v1[ch]; sec.v1[ch] = w;
        x = y;
    }
}
#endif
} // namespace

void ViperDdc::process(float* L, float* R, int frames) {
    const float targetEnabledMix = (enabled_ && !activeSections_.empty()) ? 1.0f : 0.0f;
    if (targetEnabledMix <= 0.0f && smoothedEnabledMix_ < 1e-4f) return;
    if (!L || !R || frames <= 0) return;

    // Asymmetric smoothing: fast cut (15ms) on disable, smooth ramp (25ms) on enable
    const double kTau = (targetEnabledMix > smoothedEnabledMix_) ? 0.025 : 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startEnabledMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetEnabledMix - smoothedEnabledMix_);
    if (std::abs(smoothedEnabledMix_ - targetEnabledMix) < 1e-4f) {
        smoothedEnabledMix_ = targetEnabledMix;
    }
    const float mixStep = (smoothedEnabledMix_ - startEnabledMix) / static_cast<float>(frames);
    float currentEnabledMix = startEnabledMix;

    const float crossfadeStep = 1.0f / static_cast<float>(sampleRate_ * 0.020);

    for (int i = 0; i < frames; ++i) {
        const float inL = L[i];
        const float inR = R[i];

#if defined(PULSR_F32_BIQUADS)
        float curL = std::isfinite(inL) ? inL : 0.0f;
        float curR = std::isfinite(inR) ? inR : 0.0f;
#else
        double curL = std::isfinite(inL) ? static_cast<double>(inL) : 0.0;
        double curR = std::isfinite(inR) ? static_cast<double>(inR) : 0.0;
#endif
        filterDdcSample(activeSections_, 0, curL);
        filterDdcSample(activeSections_, 1, curR);
        float wetL = static_cast<float>(curL);
        float wetR = static_cast<float>(curR);

        if (sectionCrossfadeProgress_ < 1.0f && !crossfadeSections_.empty()) {
#if defined(PULSR_F32_BIQUADS)
            float oldL = std::isfinite(inL) ? inL : 0.0f;
            float oldR = std::isfinite(inR) ? inR : 0.0f;
#else
            double oldL = std::isfinite(inL) ? static_cast<double>(inL) : 0.0;
            double oldR = std::isfinite(inR) ? static_cast<double>(inR) : 0.0;
#endif
            filterDdcSample(crossfadeSections_, 0, oldL);
            filterDdcSample(crossfadeSections_, 1, oldR);
            const float cfAngle = sectionCrossfadeProgress_ * (static_cast<float>(M_PI) * 0.5f);
            const float oldW = std::cos(cfAngle);
            const float newW = std::sin(cfAngle);
            wetL = oldW * static_cast<float>(oldL) + newW * wetL;
            wetR = oldW * static_cast<float>(oldR) + newW * wetR;
            sectionCrossfadeProgress_ = std::min(1.0f, sectionCrossfadeProgress_ + crossfadeStep);
            if (sectionCrossfadeProgress_ >= 1.0f) {
                crossfadeSections_.clear();
            }
        }

        if (!std::isfinite(wetL)) wetL = 0.0f;
        if (!std::isfinite(wetR)) wetR = 0.0f;

        // Equal-power crossfading for wet/dry enable/disable
        float dryW, wetW;
        if (currentEnabledMix >= 0.9999f) {
            dryW = 0.0f;
            wetW = 1.0f;
        } else if (currentEnabledMix <= 0.0001f) {
            dryW = 1.0f;
            wetW = 0.0f;
        } else {
            const float angle = currentEnabledMix * (static_cast<float>(M_PI) * 0.5f);
            dryW = std::cos(angle);
            wetW = std::sin(angle);
        }

        L[i] = dryW * inL + wetW * wetL;
        R[i] = dryW * inR + wetW * wetR;
        currentEnabledMix += mixStep;
    }
}

void ViperDdc::processInterleaved(float* buffer, int frames, int channels) {
    const float targetEnabledMix = (enabled_ && !activeSections_.empty()) ? 1.0f : 0.0f;
    if (targetEnabledMix <= 0.0f && smoothedEnabledMix_ < 1e-4f) return;
    if (!buffer || frames <= 0 || channels < 1) return;

    // Asymmetric smoothing: fast cut (15ms) on disable, smooth ramp (25ms) on enable
    const double kTau = (targetEnabledMix > smoothedEnabledMix_) ? 0.025 : 0.015;
    const double smoothFactor = 1.0 - std::exp(-static_cast<double>(frames) / (sampleRate_ * kTau));
    const float startEnabledMix = smoothedEnabledMix_;
    smoothedEnabledMix_ += static_cast<float>(smoothFactor) * (targetEnabledMix - smoothedEnabledMix_);
    if (std::abs(smoothedEnabledMix_ - targetEnabledMix) < 1e-4f) {
        smoothedEnabledMix_ = targetEnabledMix;
    }
    const float mixStep = (smoothedEnabledMix_ - startEnabledMix) / static_cast<float>(frames);
    float currentEnabledMix = startEnabledMix;

    const float crossfadeStep = 1.0f / static_cast<float>(sampleRate_ * 0.020);
    const int activeChannels = std::min(channels, MAX_CHANNELS);

    for (int i = 0; i < frames; ++i) {
        const bool crossfading = sectionCrossfadeProgress_ < 1.0f && !crossfadeSections_.empty();
        float oldW = 0.0f;
        float newW = 1.0f;
        if (crossfading) {
            const float cfAngle = sectionCrossfadeProgress_ * (static_cast<float>(M_PI) * 0.5f);
            oldW = std::cos(cfAngle);
            newW = std::sin(cfAngle);
        }

        // Equal-power crossfading for wet/dry enable/disable
        float dryW, wetW;
        if (currentEnabledMix >= 0.9999f) {
            dryW = 0.0f;
            wetW = 1.0f;
        } else if (currentEnabledMix <= 0.0001f) {
            dryW = 1.0f;
            wetW = 0.0f;
        } else {
            const float angle = currentEnabledMix * (static_cast<float>(M_PI) * 0.5f);
            dryW = std::cos(angle);
            wetW = std::sin(angle);
        }

        const int baseIdx = i * channels;
        for (int ch = 0; ch < activeChannels; ++ch) {
            const float inSample = buffer[baseIdx + ch];
#if defined(PULSR_F32_BIQUADS)
            float cur = std::isfinite(inSample) ? inSample : 0.0f;
#else
            double cur = std::isfinite(inSample) ? static_cast<double>(inSample) : 0.0;
#endif
            filterDdcSample(activeSections_, ch, cur);
            float wet = static_cast<float>(cur);
            if (crossfading) {
#if defined(PULSR_F32_BIQUADS)
                float old = std::isfinite(inSample) ? inSample : 0.0f;
#else
                double old = std::isfinite(inSample) ? static_cast<double>(inSample) : 0.0;
#endif
                filterDdcSample(crossfadeSections_, ch, old);
                wet = oldW * static_cast<float>(old) + newW * wet;
            }
            if (!std::isfinite(wet)) wet = 0.0f;
            buffer[baseIdx + ch] = dryW * inSample + wetW * wet;
        }

        if (crossfading) {
            sectionCrossfadeProgress_ = std::min(1.0f, sectionCrossfadeProgress_ + crossfadeStep);
            if (sectionCrossfadeProgress_ >= 1.0f) {
                crossfadeSections_.clear();
            }
        }
        currentEnabledMix += mixStep;
    }
}
