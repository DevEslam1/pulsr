// android/app/src/main/cpp/ChannelManager.cpp
#include "ChannelManager.h"

ChannelManager::ChannelManager() {
    // Preallocate the worst-case 768 kHz / 50 ms delay line once. Sample-rate
    // changes happen on the audio thread (engine resync), so setSampleRate()
    // must never resize.
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        delayLines_[ch].assign(static_cast<size_t>(MAX_DELAY_SAMPLES + 1), 0.0f);
    }
    setSampleRate(48000.0);
    reset();
}

void ChannelManager::setSampleRate(double sampleRate) {
    const double sr = (std::isfinite(sampleRate) && sampleRate > 0.0)
                          ? sampleRate
                          : 48000.0;
    if (std::abs(sr - sampleRate_) < 0.5 && !delayLines_[0].empty()) {
        return;
    }
    sampleRate_ = sr;
    maxDelaySamples_ = std::clamp(
        static_cast<int>(sr * (MAX_DELAY_MS / 1000.0)) + 1, 1,
        MAX_DELAY_SAMPLES);
    // Buffers are preallocated; only the logical window changes.
    reset();
}

void ChannelManager::resetChannelState(int channel) {
    if (channel < 0 || channel >= MAX_CHANNELS) return;
    const float gain = targetGain_[channel];
    currentGain_[channel] = gain;
    gainStep_[channel] = 0.0f;
    rampRemaining_[channel] = 0;
    std::fill(delayLines_[channel].begin(), delayLines_[channel].end(), 0.0f);
    writeIndex_[channel] = 0;
}

void ChannelManager::reset() {
    rampingDown_ = false;
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        targetGain_[ch] = 1.0f;
        currentGain_[ch] = 1.0f;
        gainStep_[ch] = 0.0f;
        rampRemaining_[ch] = 0;
        delaySamples_[ch] = 0;
        std::fill(delayLines_[ch].begin(), delayLines_[ch].end(), 0.0f);
        writeIndex_[ch] = 0;
    }
}

void ChannelManager::applyParams(const ChannelManagerParamSet& params) {
    const bool wasEnabled = params_.enabled;
    params_ = params;
    params_.channelCount = std::clamp(params_.channelCount, 2, MAX_CHANNELS);
    if (!params_.enabled) {
        if (wasEnabled) {
            const int rampFrames = std::max(
                1, static_cast<int>(sampleRate_ * (RAMP_MS / 1000.0)));
            bool anyRamp = false;
            for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
                targetGain_[ch] = 1.0f;
                if (std::abs(1.0f - currentGain_[ch]) > 1e-6f) {
                    gainStep_[ch] = (1.0f - currentGain_[ch]) / static_cast<float>(rampFrames);
                    rampRemaining_[ch] = rampFrames;
                    anyRamp = true;
                } else {
                    currentGain_[ch] = 1.0f;
                    gainStep_[ch] = 0.0f;
                    rampRemaining_[ch] = 0;
                }
            }
            rampingDown_ = anyRamp;
            if (!rampingDown_) {
                reset();
            }
        }
        return;
    }
    rampingDown_ = false;

    const bool justEnabled = (!wasEnabled && params_.enabled);
    const int rampFrames = std::max(
        1, static_cast<int>(sampleRate_ * (RAMP_MS / 1000.0)));
    for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
        const float trimDb =
            std::clamp(params_.trimDb[ch], -30.0f, 12.0f);
        const float target = std::pow(10.0f, trimDb / 20.0f);
        targetGain_[ch] = target;
        if (justEnabled) {
            currentGain_[ch] = 1.0f;
            gainStep_[ch] = (target - 1.0f) / static_cast<float>(rampFrames);
            rampRemaining_[ch] = rampFrames;
        } else if (std::abs(target - currentGain_[ch]) > 1e-6f) {
            gainStep_[ch] = (target - currentGain_[ch]) /
                            static_cast<float>(rampFrames);
            rampRemaining_[ch] = rampFrames;
        } else {
            currentGain_[ch] = target;
            gainStep_[ch] = 0.0f;
            rampRemaining_[ch] = 0;
        }

        const double delayMs =
            std::clamp(static_cast<double>(params_.delayMs[ch]), 0.0,
                       MAX_DELAY_MS);
        delaySamples_[ch] = std::clamp(
            static_cast<int>(delayMs * 0.001 * sampleRate_), 0,
            maxDelaySamples_);
    }
}

void ChannelManager::processInterleaved(float* buffer, int frames, int channels) {
    if (buffer == nullptr || frames <= 0 || channels <= 0) return;
    if (!params_.enabled && !rampingDown_) return;

    const int activeChannels = std::min(channels, MAX_CHANNELS);
    const int declaredChannels = std::min(params_.channelCount, activeChannels);
    for (int f = 0; f < frames; ++f) {
        const int base = f * channels;
        for (int ch = 0; ch < activeChannels; ++ch) {
            float x = buffer[base + ch];
            if (!std::isfinite(x)) x = 0.0f;

            if (ch < declaredChannels) {
                const int d = delaySamples_[ch];
                auto& line = delayLines_[ch];
                if (!line.empty()) {
                    const int size = static_cast<int>(line.size());
                    if (d > 0) {
                        int read = writeIndex_[ch] - d;
                        if (read < 0) read += size;
                        const float delayed = line[static_cast<size_t>(read)];
                        line[static_cast<size_t>(writeIndex_[ch])] = x;
                        x = delayed;
                    } else {
                        line[static_cast<size_t>(writeIndex_[ch])] = x;
                    }
                    writeIndex_[ch] = (writeIndex_[ch] + 1) % size;
                }

                if (rampRemaining_[ch] > 0) {
                    currentGain_[ch] += gainStep_[ch];
                    --rampRemaining_[ch];
                    if (rampRemaining_[ch] == 0) {
                        currentGain_[ch] = targetGain_[ch];
                    }
                }
                x *= currentGain_[ch];
            }
            buffer[base + ch] = x;
        }
    }

    if (rampingDown_) {
        bool stillRamping = false;
        for (int ch = 0; ch < MAX_CHANNELS; ++ch) {
            if (rampRemaining_[ch] > 0) {
                stillRamping = true;
                break;
            }
        }
        if (!stillRamping) {
            rampingDown_ = false;
            reset();
        }
    }
}
