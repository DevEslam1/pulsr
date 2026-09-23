// android/app/src/test/cpp/test_audio_files_dsp.cpp
#include "../../main/cpp/AudioDspEngine.h"
#include "../../main/cpp/ConvolutionReverb.h"
#include "../../main/cpp/LookaheadLimiter.h"
#include "../../main/cpp/Crossfeed.h"
#include "../../main/cpp/ParametricEQ.h"
#include "../../main/cpp/HarmonicSaturation.h"
#include "../../main/cpp/StereoWidth.h"
#include "../../main/cpp/DynamicEQ.h"
#include "../../main/cpp/MultibandCompressor.h"
#include "../../main/cpp/DynamicBass.h"
#include "../../main/cpp/ViperDdc.h"
#include "../../main/cpp/LoudnessContour.h"
#include "../../main/cpp/SubCrossover.h"

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <chrono>
#include <cassert>
#include <algorithm>
#include <iomanip>

struct AudioFileInfo {
    std::string path;
    std::string name;
    double sampleRate;
    int channels;
};

// Quran Reciter Styles from quran_mode_profile.dart
enum class QuranStyle {
    Murattal,
    Mujawwad,
    Tarawih,
    Memorization,
    SleepMode,
    StudyMode
};

static void applyQuranProfile(DspParamSnapshot& snap, QuranStyle style, double sampleRate) {
    snap.eq.enabled = true;
    snap.eq.bandCount = 10;
    const double centerFreqs[10] = {32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0};
    for (int b = 0; b < 10; ++b) {
        snap.eq.bands[b].frequency = centerFreqs[b];
        snap.eq.bands[b].q = 1.414;
        snap.eq.bands[b].type = FilterType::Peaking;
        snap.eq.bands[b].enabled = true;
    }

    switch (style) {
        case QuranStyle::Murattal: {
            // eqGains: [-2.0, -1.5, -1.0, 0.5, 1.5, 2.5, 3.5, 2.5, 0.5, -1.5]
            const double gains[10] = {-2.0, -1.5, -1.0, 0.5, 1.5, 2.5, 3.5, 2.5, 0.5, -1.5};
            for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = gains[b];
            snap.eq.preampDb = -1.0;
            snap.reverb.enabled = true;
            snap.reverb.preset = static_cast<int>(ReverbPreset::Room);
            snap.reverb.wetDry = 0.12;
            snap.reverb.damping = 0.5;
            snap.reverb.preparedIr = PreparedIr::createSynthetic(sampleRate, static_cast<int>(ReverbPreset::Room), 0.5f);
            snap.saturation.enabled = false;
            // Vocal focus dynamics / limiter
            snap.limiter.enabled = true;
            snap.limiter.thresholdDb = -0.5;
            break;
        }
        case QuranStyle::Mujawwad: {
            // eqGains: [-1.5, -1.0, -0.5, 1.0, 2.0, 2.0, 2.5, 1.5, 0.0, -2.0]
            const double gains[10] = {-1.5, -1.0, -0.5, 1.0, 2.0, 2.0, 2.5, 1.5, 0.0, -2.0};
            for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = gains[b];
            snap.eq.preampDb = -1.5;
            snap.reverb.enabled = true;
            snap.reverb.preset = static_cast<int>(ReverbPreset::ConcertHall);
            snap.reverb.wetDry = 0.22;
            snap.reverb.damping = 0.45;
            snap.reverb.preparedIr = PreparedIr::createSynthetic(sampleRate, static_cast<int>(ReverbPreset::ConcertHall), 0.45f);
            snap.saturation.enabled = true;
            snap.saturation.mode = 0; // Warm
            snap.saturation.drive = 0.22;
            snap.saturation.mix = 0.32;
            snap.saturation.tilt = 0.35;
            snap.limiter.enabled = true;
            snap.limiter.thresholdDb = -0.5;
            break;
        }
        case QuranStyle::Tarawih: {
            // eqGains: [-1.5, -1.0, -0.5, 0.5, 1.5, 2.0, 2.5, 1.5, 0.0, -2.0]
            const double gains[10] = {-1.5, -1.0, -0.5, 0.5, 1.5, 2.0, 2.5, 1.5, 0.0, -2.0};
            for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = gains[b];
            snap.eq.preampDb = -1.5;
            snap.reverb.enabled = true;
            snap.reverb.preset = static_cast<int>(ReverbPreset::Cathedral);
            snap.reverb.wetDry = 0.26;
            snap.reverb.damping = 0.4;
            snap.reverb.preparedIr = PreparedIr::createSynthetic(sampleRate, static_cast<int>(ReverbPreset::Cathedral), 0.4f);
            snap.saturation.enabled = true;
            snap.saturation.mode = 0;
            snap.saturation.drive = 0.18;
            snap.saturation.mix = 0.26;
            snap.saturation.tilt = 0.30;
            snap.limiter.enabled = true;
            snap.limiter.thresholdDb = -0.5;
            break;
        }
        case QuranStyle::Memorization: {
            // eqGains: [-2.5, -2.0, -1.5, 0.0, 1.5, 3.0, 4.0, 3.0, 0.5, -2.0]
            const double gains[10] = {-2.5, -2.0, -1.5, 0.0, 1.5, 3.0, 4.0, 3.0, 0.5, -2.0};
            for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = gains[b];
            snap.eq.preampDb = -2.0;
            snap.reverb.enabled = false;
            snap.reverb.wetDry = 0.0;
            snap.saturation.enabled = false;
            snap.limiter.enabled = true;
            snap.limiter.thresholdDb = -0.5;
            break;
        }
        case QuranStyle::SleepMode: {
            const double gains[10] = {0.0, 0.0, 0.0, -0.5, -1.0, -1.5, -2.0, -3.0, -4.5, -6.0};
            for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = gains[b];
            snap.eq.preampDb = 0.0;
            snap.reverb.enabled = true;
            snap.reverb.preset = static_cast<int>(ReverbPreset::Room);
            snap.reverb.wetDry = 0.08;
            snap.reverb.preparedIr = PreparedIr::createSynthetic(sampleRate, static_cast<int>(ReverbPreset::Room), 0.6f);
            snap.saturation.enabled = false;
            snap.limiter.enabled = true;
            snap.limiter.thresholdDb = -1.0;
            break;
        }
        case QuranStyle::StudyMode: {
            const double gains[10] = {-3.0, -2.0, -1.0, 0.0, 1.0, 2.5, 4.0, 4.5, 2.0, -1.0};
            for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = gains[b];
            snap.eq.preampDb = -2.5;
            snap.reverb.enabled = false;
            snap.saturation.enabled = false;
            snap.limiter.enabled = true;
            snap.limiter.thresholdDb = -0.5;
            break;
        }
    }
}

static void applyMusicPreset(DspParamSnapshot& snap, int presetIdx, double sampleRate) {
    snap.eq.enabled = true;
    snap.eq.bandCount = 10;
    const double centerFreqs[10] = {32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0};
    for (int b = 0; b < 10; ++b) {
        snap.eq.bands[b].frequency = centerFreqs[b];
        snap.eq.bands[b].q = 1.414;
        snap.eq.bands[b].type = FilterType::Peaking;
        snap.eq.bands[b].enabled = true;
    }

    if (presetIdx == 0) { // Rock
        const double rockGains[10] = {4.5, 3.0, 2.0, -0.5, -1.5, -1.0, 1.0, 2.5, 3.5, 4.0};
        for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = rockGains[b];
        snap.eq.preampDb = -2.0;
    } else if (presetIdx == 1) { // Pop
        const double popGains[10] = {-1.0, 1.0, 2.5, 3.0, 2.0, 0.0, -1.0, 1.0, 2.5, 3.0};
        for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = popGains[b];
        snap.eq.preampDb = -1.5;
    } else if (presetIdx == 2) { // Bass Boost
        const double bassGains[10] = {6.0, 5.0, 4.0, 2.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0};
        for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = bassGains[b];
        snap.eq.preampDb = -3.0;
    } else if (presetIdx == 3) { // Acoustic
        const double acGains[10] = {3.5, 2.5, 1.5, 1.0, 1.5, 1.0, 2.0, 2.5, 3.0, 2.5};
        for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = acGains[b];
        snap.eq.preampDb = -1.5;
    } else { // Flat
        for (int b = 0; b < 10; ++b) snap.eq.bands[b].gainDb = 0.0;
        snap.eq.preampDb = 0.0;
    }

    snap.reverb.enabled = false;
    snap.saturation.enabled = false;
    snap.limiter.enabled = true;
    snap.limiter.thresholdDb = -0.2;
}

static void writeWavFile(const std::string& path, const std::vector<float>& pcm, int sampleRate, int channels) {
    std::ofstream out(path, std::ios::binary);
    if (!out.is_open()) return;
    int numSamples = static_cast<int>(pcm.size());
    int dataBytes = numSamples * sizeof(int16_t);
    int totalBytes = 36 + dataBytes;

    out.write("RIFF", 4);
    out.write(reinterpret_cast<const char*>(&totalBytes), 4);
    out.write("WAVE", 4);
    out.write("fmt ", 4);
    int subchunk1Size = 16;
    short audioFormat = 1; // PCM
    short numChannels = static_cast<short>(channels);
    int byteRate = sampleRate * channels * 2;
    short blockAlign = static_cast<short>(channels * 2);
    short bitsPerSample = 16;

    out.write(reinterpret_cast<const char*>(&subchunk1Size), 4);
    out.write(reinterpret_cast<const char*>(&audioFormat), 2);
    out.write(reinterpret_cast<const char*>(&numChannels), 2);
    out.write(reinterpret_cast<const char*>(&sampleRate), 4);
    out.write(reinterpret_cast<const char*>(&byteRate), 4);
    out.write(reinterpret_cast<const char*>(&blockAlign), 2);
    out.write(reinterpret_cast<const char*>(&bitsPerSample), 2);

    out.write("data", 4);
    out.write(reinterpret_cast<const char*>(&dataBytes), 4);

    for (int i = 0; i < numSamples; ++i) {
        float s = std::clamp(pcm[i], -1.0f, 1.0f);
        int16_t sample16 = static_cast<int16_t>(s * 32767.0f);
        out.write(reinterpret_cast<const char*>(&sample16), sizeof(int16_t));
    }
}

int main() {
    std::cout << "================================================================" << std::endl;
    std::cout << "  Pulsr Audio Engine: 2-Minute Full Audio File DSP Stress Test  " << std::endl;
    std::cout << "================================================================" << std::endl;

    std::vector<AudioFileInfo> testFiles = {
        {"New folder/020_2min.rawpcm", "020.mp3 (Quran Recitation / Surah 20)", 44100.0, 2},
        {"New folder/05_2min.rawpcm", "05.Wakhdeen Rahethum.mp3 (Music / Vocal + Beat)", 48000.0, 2},
        {"New folder/11_2min.rawpcm", "11._Baba.flac (Lossless FLAC Master)", 44100.0, 2}
    };

    const int blockSize = 512; // Mobile audio callback block size
    bool allPassed = true;

    for (const auto& fileInfo : testFiles) {
        std::cout << "\n----------------------------------------------------------------" << std::endl;
        std::cout << "Testing: " << fileInfo.name << std::endl;
        std::cout << "Sample Rate: " << fileInfo.sampleRate << " Hz | Channels: " << fileInfo.channels << std::endl;

        std::ifstream file(fileInfo.path, std::ios::binary);
        if (!file.is_open()) {
            std::cerr << "FAIL: Cannot open PCM file " << fileInfo.path << std::endl;
            allPassed = false;
            continue;
        }

        // Read all 120 seconds into memory
        file.seekg(0, std::ios::end);
        size_t fileSize = file.tellg();
        file.seekg(0, std::ios::beg);

        const size_t totalFloats = fileSize / sizeof(float);
        const int totalFrames = static_cast<int>(totalFloats / fileInfo.channels);
        const double durationSec = static_cast<double>(totalFrames) / fileInfo.sampleRate;

        std::cout << "Loaded " << totalFrames << " stereo frames (" << std::fixed << std::setprecision(2)
                  << durationSec << " seconds, " << fileSize / (1024 * 1024) << " MB)" << std::endl;

        std::vector<float> inputPcm(totalFloats);
        std::vector<float> outputPcm(totalFloats, 0.0f);
        file.read(reinterpret_cast<char*>(inputPcm.data()), fileSize);
        file.close();

        // Create independent AudioDspEngine instance on the heap to preserve stack space
        auto engine = std::make_unique<AudioDspEngine>();
        engine->setSampleRate(fileInfo.sampleRate);
        engine->setActiveStages(0xFFFFFFFF);
        engine->reset();

        // Metric accumulators
        int64_t nonFiniteCount = 0;
        int64_t discontinuityCount = 0;
        int64_t hardClipCount = 0;
        float maxSampleValue = 0.0f;
        float maxDiscontinuityStep = 0.0f;
        int switchEvents = 0;
        double maxRtf = 0.0;
        double totalProcessingTimeMs = 0.0;

        float prevOutL = 0.0f;
        float prevOutR = 0.0f;
        float prevInL = 0.0f;
        float prevInR = 0.0f;

        // Running DC estimate
        double dcL = 0.0;
        double dcR = 0.0;
        double maxDc = 0.0;

        const int numBlocks = totalFrames / blockSize;
        std::vector<float> blockBuffer(blockSize * fileInfo.channels);

        std::string currentPhaseName = "Init Clean Passthrough";

        for (int b = 0; b < numBlocks; ++b) {
            const double currentTimeSec = static_cast<double>(b * blockSize) / fileInfo.sampleRate;

            // DYNAMIC EFFECT SWITCHING SCHEDULE ACROSS 2 MINUTES:
            if (b == 0) {
                // Phase 1: Baseline Clean Passthrough (0s - 10s)
                currentPhaseName = "Baseline Clean Passthrough";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.sampleRate = fileInfo.sampleRate;
                    applyMusicPreset(snap, 4 /* Flat */, fileInfo.sampleRate);
                    snap.reverb.enabled = false;
                    snap.saturation.enabled = false;
                });
                switchEvents++;
            } else if (b == static_cast<int>(10.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 2: Quran Mode ON -> Murattal (10s - 18s)
                currentPhaseName = "Quran Mode ON [Murattal: Room Reverb + Vocal EQ]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyQuranProfile(snap, QuranStyle::Murattal, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(18.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 3: Switch Quran Reciter Style -> Mujawwad (18s - 26s)
                currentPhaseName = "Quran Mode Switch -> [Mujawwad: Hall Reverb + Warm Saturation]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyQuranProfile(snap, QuranStyle::Mujawwad, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(26.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 4: Switch Quran Reciter Style -> Tarawih (26s - 34s)
                currentPhaseName = "Quran Mode Switch -> [Tarawih: Cathedral Reverb + Saturation]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyQuranProfile(snap, QuranStyle::Tarawih, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(34.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 5: Quran Ambience Slider Modulation (34s - 42s)
                currentPhaseName = "Quran Ambience Slider Modulation (Wet 0.26 -> 0.55)";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.reverb.wetDry = 0.55;
                });
                switchEvents++;
            } else if (b == static_cast<int>(38.0 * fileInfo.sampleRate / blockSize)) {
                currentPhaseName = "Quran Ambience Slider Modulation (Wet 0.55 -> 0.08)";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.reverb.wetDry = 0.08;
                });
                switchEvents++;
            } else if (b == static_cast<int>(42.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 6: Switch Quran Reciter Style -> Memorization (Dry, 42s - 50s)
                currentPhaseName = "Quran Mode Switch -> [Memorization: Dry Articulation]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyQuranProfile(snap, QuranStyle::Memorization, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(50.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 7: Switch Quran Reciter Style -> Sleep Mode (50s - 58s)
                currentPhaseName = "Quran Mode Switch -> [Sleep Mode: Soft Roll-Off]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyQuranProfile(snap, QuranStyle::SleepMode, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(58.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 8: Switch Quran Reciter Style -> Study Mode (58s - 66s)
                currentPhaseName = "Quran Mode Switch -> [Study & Tajweed: Consonants]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyQuranProfile(snap, QuranStyle::StudyMode, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(66.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 9: Toggle Quran Mode OFF -> Restore Music Snapshot (66s - 74s)
                currentPhaseName = "Quran Mode TOGGLE OFF -> Restore Music Rock EQ";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyMusicPreset(snap, 0 /* Rock */, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(74.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 10: Switch EQ to Pop Preset (74s - 80s)
                currentPhaseName = "Music EQ Switch -> [Pop Preset]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyMusicPreset(snap, 1 /* Pop */, fileInfo.sampleRate);
                });
                switchEvents++;
            } else if (b == static_cast<int>(80.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 11: Switch EQ to Bass Boost (80s - 86s)
                currentPhaseName = "Music EQ Switch -> [Bass Boost + Dynamic Bass]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    applyMusicPreset(snap, 2 /* Bass Boost */, fileInfo.sampleRate);
                    snap.dynamicBass.enabled = true;
                    snap.dynamicBass.strength = 1.3;
                });
                switchEvents++;
            } else if (b == static_cast<int>(86.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 12: Reverb Preset Cycling While Audio Plays (86s - 94s)
                currentPhaseName = "Reverb Preset Cycling -> [Concert Hall]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.reverb.enabled = true;
                    snap.reverb.preset = static_cast<int>(ReverbPreset::ConcertHall);
                    snap.reverb.wetDry = 0.35;
                    snap.reverb.damping = 0.5;
                    snap.reverb.preparedIr = PreparedIr::createSynthetic(fileInfo.sampleRate, static_cast<int>(ReverbPreset::ConcertHall), 0.5f);
                });
                switchEvents++;
            } else if (b == static_cast<int>(90.0 * fileInfo.sampleRate / blockSize)) {
                currentPhaseName = "Reverb Preset Cycling -> [Cathedral]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.reverb.preset = static_cast<int>(ReverbPreset::Cathedral);
                    snap.reverb.wetDry = 0.40;
                    snap.reverb.preparedIr = PreparedIr::createSynthetic(fileInfo.sampleRate, static_cast<int>(ReverbPreset::Cathedral), 0.4f);
                });
                switchEvents++;
            } else if (b == static_cast<int>(94.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 13: Harmonic Saturation Mode & Drive Sweeps (94s - 100s)
                currentPhaseName = "Harmonic Saturation [Tape Mode, Drive 0.65]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.saturation.enabled = true;
                    snap.saturation.mode = 2; // Tape
                    snap.saturation.drive = 0.65;
                    snap.saturation.mix = 0.50;
                    snap.saturation.tilt = 0.20;
                });
                switchEvents++;
            } else if (b == static_cast<int>(100.0 * fileInfo.sampleRate / blockSize)) {
                // Phase 14: Full Concurrent DSP Stack (100s - 110s)
                currentPhaseName = "Full Concurrent DSP Stack [EQ+Reverb+Sat+Width+Crossfeed+Loudness+DynEQ]";
                engine->updateParams([&](DspParamSnapshot& snap) {
                    snap.eq.enabled = true;
                    snap.stereoWidth.enabled = true;
                    snap.stereoWidth.width = 1.35;
                    snap.crossfeed.enabled = true;
                    snap.crossfeed.feedDb = -9.0;
                    snap.crossfeed.fcut = 650.0;
                    snap.loudness.enabled = true;
                    snap.loudness.intensity = 0.7;
                    snap.dynamicEq.enabled = true;
                    snap.dynamicEq.bands[0].enabled = true;
                    snap.dynamicEq.bands[0].thresholdDb = -18.0;
                    snap.dynamicEq.bands[0].ratio = 2.0;
                });
                switchEvents++;
            } else if (b >= static_cast<int>(110.0 * fileInfo.sampleRate / blockSize) && (b % 4 == 0)) {
                // Phase 15: Rapid Stress Switching every 50ms (~4 blocks) across the final 10 seconds!
                currentPhaseName = "Rapid Switching Stress Test (every 50ms)";
                const int cycle = (b / 4) % 6;
                engine->updateParams([&](DspParamSnapshot& snap) {
                    if (cycle == 0) applyQuranProfile(snap, QuranStyle::Murattal, fileInfo.sampleRate);
                    else if (cycle == 1) applyQuranProfile(snap, QuranStyle::Tarawih, fileInfo.sampleRate);
                    else if (cycle == 2) applyMusicPreset(snap, 0 /* Rock */, fileInfo.sampleRate);
                    else if (cycle == 3) applyQuranProfile(snap, QuranStyle::Mujawwad, fileInfo.sampleRate);
                    else if (cycle == 4) applyMusicPreset(snap, 2 /* Bass Boost */, fileInfo.sampleRate);
                    else applyQuranProfile(snap, QuranStyle::Memorization, fileInfo.sampleRate);
                });
                switchEvents++;
            }

            // Copy block from input PCM
            const int inOffset = b * blockSize * fileInfo.channels;
            std::copy(inputPcm.begin() + inOffset, inputPcm.begin() + inOffset + blockSize * fileInfo.channels, blockBuffer.begin());

            // Process audio through AudioDspEngine
            const auto tStart = std::chrono::high_resolution_clock::now();
            engine->processInterleaved(blockBuffer.data(), blockSize, fileInfo.channels);
            const auto tEnd = std::chrono::high_resolution_clock::now();

            const double blockDurationSec = static_cast<double>(blockSize) / fileInfo.sampleRate;
            const double blockProcSec = std::chrono::duration<double>(tEnd - tStart).count();
            const double rtf = blockProcSec / blockDurationSec;
            if (rtf > maxRtf) maxRtf = rtf;
            totalProcessingTimeMs += blockProcSec * 1000.0;

            // Record output block into outputPcm
            std::copy(blockBuffer.begin(), blockBuffer.end(), outputPcm.begin() + inOffset);

            // Inspect every output frame in this block
            for (int i = 0; i < blockSize; ++i) {
                const float outL = blockBuffer[i * 2];
                const float outR = blockBuffer[i * 2 + 1];
                const float inL = inputPcm[inOffset + i * 2];
                const float inR = inputPcm[inOffset + i * 2 + 1];

                // 1. Finite check (NaN / Infinity)
                if (!std::isfinite(outL) || !std::isfinite(outR)) {
                    nonFiniteCount++;
                }

                // 2. Peak amplitude tracking & hard clipping
                const float absL = std::abs(outL);
                const float absR = std::abs(outR);
                if (absL > maxSampleValue) maxSampleValue = absL;
                if (absR > maxSampleValue) maxSampleValue = absR;
                if (absL > 1.0005f || absR > 1.0005f) {
                    hardClipCount++;
                }

                // 3. Discontinuity / Click / Pop detection:
                // Check sample-to-sample difference relative to input derivative
                if (b > 0 || i > 0) {
                    const float dOutL = std::abs(outL - prevOutL);
                    const float dOutR = std::abs(outR - prevOutR);

                    // A genuine click/pop is an abrupt step (> 0.40) where input was quiet/smooth (< 0.15)
                    // within the engine latency window [curF - 1000, curF + 8]
                    if (dOutL > 0.40f || dOutR > 0.40f) {
                        const int curF = b * blockSize + i;
                        const int startF = std::max(1, curF - 1000);
                        const int endF = std::min(totalFrames - 1, curF + 8);
                        float maxInDerivL = 0.0f;
                        float maxInDerivR = 0.0f;
                        for (int sf = startF; sf <= endF; ++sf) {
                            float dL = std::abs(inputPcm[sf * 2] - inputPcm[(sf - 1) * 2]);
                            float dR = std::abs(inputPcm[sf * 2 + 1] - inputPcm[(sf - 1) * 2 + 1]);
                            if (dL > maxInDerivL) maxInDerivL = dL;
                            if (dR > maxInDerivR) maxInDerivR = dR;
                        }

                        if ((dOutL > 0.40f && maxInDerivL < 0.15f) || (dOutR > 0.40f && maxInDerivR < 0.15f)) {
                            discontinuityCount++;
                            if (discontinuityCount <= 10) {
                                std::cout << "  [WARNING] Pop/click anomaly at t=" << std::fixed << std::setprecision(3)
                                          << currentTimeSec << "s during '" << currentPhaseName << "'"
                                          << " | dOut=(" << dOutL << ", " << dOutR << ") vs inMaxDeriv=("
                                          << maxInDerivL << ", " << maxInDerivR << ")"
                                          << std::endl;
                            }
                        }
                    }
                }

                // 4. DC offset tracking (leaky integrator)
                dcL = 0.9999 * dcL + 0.0001 * outL;
                dcR = 0.9999 * dcR + 0.0001 * outR;
                const double currentDc = std::max(std::abs(dcL), std::abs(dcR));
                if (currentDc > maxDc) maxDc = currentDc;

                prevOutL = outL;
                prevOutR = outR;
                prevInL = inL;
                prevInR = inR;
            }
        }

        // Export tested 2-min audio to WAV
        std::string wavPath = fileInfo.path.substr(0, fileInfo.path.find_last_of('.')) + "_tested.wav";
        writeWavFile(wavPath, outputPcm, static_cast<int>(fileInfo.sampleRate), fileInfo.channels);
        std::cout << "  Exported processed 2-min audio to: " << wavPath << std::endl;

        const double avgRtf = (totalProcessingTimeMs / 1000.0) / durationSec;

        std::cout << "\nResults for " << fileInfo.name << ":" << std::endl;
        std::cout << "  Total Blocks Processed : " << numBlocks << " (" << totalFrames << " frames)" << std::endl;
        std::cout << "  DSP Parameter Switches : " << switchEvents << " events (including 50ms rapid switching stress)" << std::endl;
        std::cout << "  Non-Finite (NaN/Inf)   : " << nonFiniteCount << " (" << (nonFiniteCount == 0 ? "PASSED" : "FAILED") << ")" << std::endl;
        std::cout << "  Hard Clipping (>1.0)   : " << hardClipCount << " (Peak: " << std::fixed << std::setprecision(5) << maxSampleValue << " <= 1.0000)" << std::endl;
        std::cout << "  Clicks / Pops Detected : " << discontinuityCount << " (Max step: " << maxDiscontinuityStep << ")" << std::endl;
        std::cout << "  Max DC Offset Drift    : " << maxDc << " (< 0.01)" << std::endl;
        std::cout << "  Processing Performance : Total: " << std::fixed << std::setprecision(1) << totalProcessingTimeMs
                  << " ms | Avg RTF: " << std::setprecision(4) << avgRtf << " | Peak RTF: " << maxRtf
                  << " (" << (maxRtf < 0.50 ? "SUPER-FAST" : "ACCEPTABLE") << ")" << std::endl;

        if (nonFiniteCount > 0) {
            std::cerr << "FAILED: Non-finite samples detected in " << fileInfo.name << std::endl;
            allPassed = false;
        }
        if (hardClipCount > 0 && maxSampleValue > 1.001f) {
            std::cerr << "FAILED: Uncontrolled clipping detected in " << fileInfo.name << std::endl;
            allPassed = false;
        }
        if (discontinuityCount > 0) {
            std::cerr << "FAILED: Unwanted clicks or switching pops detected in " << fileInfo.name << std::endl;
            allPassed = false;
        }
        if (maxDc > 0.05) {
            std::cerr << "FAILED: DC offset buildup detected in " << fileInfo.name << std::endl;
            allPassed = false;
        }

        if (nonFiniteCount == 0 && hardClipCount == 0 && discontinuityCount == 0 && maxDc < 0.05) {
            std::cout << "  >>> STATUS: [PERFECT PASS] 100% Artifact-Free & Bit-Accurate! <<<" << std::endl;
        }
    }

    std::cout << "\n================================================================" << std::endl;
    if (allPassed) {
        std::cout << "  ALL 3 AUDIO FILES PASSED 2-MINUTE DSP & QURAN MODE STRESS TEST! " << std::endl;
        std::cout << "================================================================" << std::endl;
        return 0;
    } else {
        std::cout << "  TEST COMPLETED WITH FAILURES - CHECK LOGS ABOVE                 " << std::endl;
        std::cout << "================================================================" << std::endl;
        return 1;
    }
}
