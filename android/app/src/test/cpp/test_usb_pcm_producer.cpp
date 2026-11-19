// Host test for the PCM reader-thread producer.
//
// Verifies the half the pull renderer was missing: a file-backed reader that
// fills the reservoir ahead of consumption, with bit-exact WAV passthrough,
// seek, pause and strict format matching (no hidden conversion).
#include "../../main/cpp/UsbPcmProducer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

int gChecks = 0;
int gFailures = 0;

void check(bool ok, const char* what) {
    ++gChecks;
    if (ok) {
        std::cout << "[ok] " << what << std::endl;
    } else {
        ++gFailures;
        std::cout << "[FAIL] " << what << std::endl;
    }
}

void putLe16(std::vector<uint8_t>& out, uint16_t v) {
    out.push_back(static_cast<uint8_t>(v & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
}

void putLe32(std::vector<uint8_t>& out, uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFF));
}

void putTag(std::vector<uint8_t>& out, const char* tag) {
    out.insert(out.end(), tag, tag + 4);
}

std::string writeWav(const std::vector<uint8_t>& pcm, int sampleRate, int channels,
                     int bits) {
    const int blockAlign = channels * (bits / 8);
    std::vector<uint8_t> wav;
    putTag(wav, "RIFF");
    putLe32(wav, static_cast<uint32_t>(36 + pcm.size()));
    putTag(wav, "WAVE");
    putTag(wav, "fmt ");
    putLe32(wav, 16);
    putLe16(wav, 1);  // PCM
    putLe16(wav, static_cast<uint16_t>(channels));
    putLe32(wav, static_cast<uint32_t>(sampleRate));
    putLe32(wav, static_cast<uint32_t>(sampleRate * blockAlign));
    putLe16(wav, static_cast<uint16_t>(blockAlign));
    putLe16(wav, static_cast<uint16_t>(bits));
    putTag(wav, "data");
    putLe32(wav, static_cast<uint32_t>(pcm.size()));
    wav.insert(wav.end(), pcm.begin(), pcm.end());

    const auto path = std::filesystem::temp_directory_path() /
                      "pulsr_usb_pcm_producer_test.wav";
    std::FILE* f = std::fopen(path.string().c_str(), "wb");
    if (f == nullptr) return {};
    std::fwrite(wav.data(), 1, wav.size(), f);
    std::fclose(f);
    return path.string();
}

std::vector<uint8_t> makePcm(int frames, int channels, int bits) {
    const int bytes = bits / 8;
    std::vector<uint8_t> pcm(static_cast<size_t>(frames) * channels * bytes);
    for (int f = 0; f < frames; ++f) {
        for (int c = 0; c < channels; ++c) {
            // Deterministic, full-scale-ish signed pattern including -1.0.
            int32_t v = static_cast<int32_t>((static_cast<int64_t>(f) * 2654435761u +
                                              static_cast<uint32_t>(c) * 40503u) &
                                             0x7FFFFF);
            if ((f & 1) == 0) v = -v;
            if (bits == 16) {
                const int16_t s = static_cast<int16_t>(v >> 8);
                const size_t at = (static_cast<size_t>(f) * channels + c) * 2;
                pcm[at] = static_cast<uint8_t>(s & 0xFF);
                pcm[at + 1] = static_cast<uint8_t>((s >> 8) & 0xFF);
            } else if (bits == 24) {
                const size_t at = (static_cast<size_t>(f) * channels + c) * 3;
                pcm[at] = static_cast<uint8_t>(v & 0xFF);
                pcm[at + 1] = static_cast<uint8_t>((v >> 8) & 0xFF);
                pcm[at + 2] = static_cast<uint8_t>((v >> 16) & 0xFF);
            } else {
                const size_t at = (static_cast<size_t>(f) * channels + c) * 4;
                for (int b = 0; b < 4; ++b) {
                    pcm[at + b] = static_cast<uint8_t>((v >> (8 * b)) & 0xFF);
                }
            }
        }
    }
    return pcm;
}

bool waitForFill(pulsr::UsbPullRenderer& r, size_t frames, int timeoutMs) {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(timeoutMs);
    while (std::chrono::steady_clock::now() < deadline) {
        if (r.availableFrames() >= frames) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return false;
}

}  // namespace

int main() {
    using pulsr::UsbPcmFormat;
    using pulsr::UsbPcmProducer;
    using pulsr::UsbPullRenderer;

    std::cout << "[TEST] USB PCM reader-thread producer..." << std::endl;

    constexpr int kRate = 48000;
    constexpr int kChannels = 2;
    constexpr int kBits = 16;
    constexpr int kFrames = kRate * 5;  // 5 seconds
    const int frameBytes = kChannels * (kBits / 8);
    const auto pcm = makePcm(kFrames, kChannels, kBits);
    const std::string path = writeWav(pcm, kRate, kChannels, kBits);
    check(!path.empty(), "test WAV written");

    // ---- Bit-exact fill, consume and EOF ---------------------------------
    UsbPullRenderer renderer;
    UsbPcmProducer producer;
    UsbPcmFormat target{kRate, kChannels, kBits / 8, kBits};
    check(producer.open(path, target, renderer, /*bufferMs=*/500),
          "producer opens a matching WAV");
    check(producer.isOpen(), "producer reports open");
    check(renderer.isConfigured(), "producer configured the pull renderer");

    producer.start();
    check(waitForFill(renderer, renderer.capacityFrames() / 2, 2000),
          "reader thread fills the reservoir ahead of consumption");

    std::vector<uint8_t> out(static_cast<size_t>(480) * frameBytes);
    size_t compared = 0;
    bool identical = true;
    while (compared < pcm.size()) {
        const size_t want = std::min<size_t>(480, (pcm.size() - compared) / frameBytes);
        if (!waitForFill(renderer, want, 2000)) {
            identical = false;
            break;
        }
        const int got = renderer.pullExact(out.data(), static_cast<int>(want));
        if (got != static_cast<int>(want)) {
            identical = false;
            break;
        }
        if (std::memcmp(out.data(), pcm.data() + compared, want * frameBytes) != 0) {
            identical = false;
            break;
        }
        compared += want * frameBytes;
    }
    check(identical, "every packet payload is bit-identical to the WAV data");
    check(compared == pcm.size(), "the whole file was consumed");

    // EOF: the reader thread must stop producing and report it.
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (!producer.finished() && std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    check(producer.finished(), "producer reports EOF");
    check(producer.framesWritten() == static_cast<uint64_t>(kFrames),
          "producer wrote exactly the file's frame count");

    // ---- Seek ------------------------------------------------------------
    const uint64_t seekFrame = 100000;
    producer.setPaused(true);
    check(waitForFill(renderer, 0, 100), "pause settled");
    // Drain whatever is buffered so the renderer is quiesced for the flush.
    std::vector<uint8_t> drain(static_cast<size_t>(8192) * frameBytes);
    while (renderer.availableFrames() > 0) {
        renderer.pull(drain.data(), 8192);
    }
    check(producer.seekToFrame(seekFrame), "seek request accepted");
    producer.setPaused(false);
    const auto seekDeadline = std::chrono::steady_clock::now() +
                              std::chrono::seconds(2);
    bool seekFilled = false;
    while (std::chrono::steady_clock::now() < seekDeadline) {
        if (renderer.availableFrames() >= 480) {
            seekFilled = true;
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    check(seekFilled, "reader refills after seek");
    check(renderer.pullExact(out.data(), 480) == 480,
          "post-seek packet available");
    check(std::memcmp(out.data(),
                      pcm.data() + static_cast<size_t>(seekFrame) * frameBytes,
                      out.size()) == 0,
          "post-seek payload matches the requested frame");

    // ---- Pause -----------------------------------------------------------
    producer.setPaused(true);
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    const uint64_t frozen = producer.framesWritten();
    std::this_thread::sleep_for(std::chrono::milliseconds(60));
    check(producer.framesWritten() == frozen, "paused producer writes nothing");
    producer.setPaused(false);
    producer.stop();
    producer.close();
    check(!producer.isOpen(), "close releases the producer");

    // ---- Strict format matching -----------------------------------------
    {
        UsbPullRenderer r2;
        UsbPcmProducer p2;
        const UsbPcmFormat wrong{kRate, kChannels, 3, 24};
        check(!p2.open(path, wrong, r2, 200), "24-bit target refuses a 16-bit WAV");
        check(p2.lastError() == "format_mismatch",
              "format mismatch reports format_mismatch");
    }

    // ---- Malformed file --------------------------------------------------
    {
        const auto bad = std::filesystem::temp_directory_path() /
                         "pulsr_usb_pcm_producer_bad.wav";
        std::FILE* f = std::fopen(bad.string().c_str(), "wb");
        const char junk[] = "not a wav at all";
        std::fwrite(junk, 1, sizeof(junk), f);
        std::fclose(f);
        UsbPullRenderer r3;
        UsbPcmProducer p3;
        check(!p3.open(bad.string().c_str(), target, r3, 200),
              "malformed WAV is refused");
        std::filesystem::remove(bad);
    }

    std::filesystem::remove(path);

    if (gFailures != 0) {
        std::cout << "[FAIL] " << gFailures << " of " << gChecks
                  << " PCM producer checks failed." << std::endl;
        return 1;
    }
    std::cout << "[PASS] USB PCM producer: " << gChecks
              << " checks (ahead fill, bit-exact WAV, seek, pause, strict format)."
              << std::endl;
    return 0;
}
