// android/app/src/main/cpp/HrtfBinaural.cpp
#include "HrtfBinaural.h"

#include <fstream>
#include <sstream>
#include <cstring>
#include <cassert>

namespace pulsr {

namespace {

inline uint32_t readBe32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8)  |
           (static_cast<uint32_t>(p[3]));
}

inline uint64_t readBe64(const uint8_t* p) {
    return (static_cast<uint64_t>(readBe32(p)) << 32) |
           (static_cast<uint64_t>(readBe32(p + 4)));
}

inline float readBeFloat(const uint8_t* p) {
    uint32_t u = readBe32(p);
    float f;
    std::memcpy(&f, &u, sizeof(float));
    return f;
}

inline double readBeDouble(const uint8_t* p) {
    uint64_t u = readBe64(p);
    double d;
    std::memcpy(&d, &u, sizeof(double));
    return d;
}

inline float readLeFloat(const uint8_t* p) {
    float f;
    std::memcpy(&f, p, sizeof(float));
    return f;
}

inline int16_t readLeInt16(const uint8_t* p) {
    return static_cast<int16_t>(p[0] | (static_cast<uint16_t>(p[1]) << 8));
}

// Bounded string read helper for NetCDF-3
bool readNetCdfString(const uint8_t* data, size_t size, size_t& offset, std::string& outStr) {
    if (offset + 4 > size) return false;
    uint32_t len = readBe32(data + offset);
    offset += 4;
    size_t paddedLen = ((len + 3) / 4) * 4;
    if (offset + paddedLen > size) return false;
    outStr.assign(reinterpret_cast<const char*>(data + offset), len);
    offset += paddedLen;
    return true;
}

bool skipNetCdfAttrs(const uint8_t* data, size_t size, size_t& offset) {
    if (offset + 4 > size) return false;
    uint32_t tag = readBe32(data + offset);
    offset += 4;
    if (tag == 0) return true; // NC_UNSPECIFIED
    if (tag != 0x0000000C) return false; // NC_ATTRIBUTE
    if (offset + 4 > size) return false;
    uint32_t count = readBe32(data + offset);
    offset += 4;
    for (uint32_t i = 0; i < count; ++i) {
        std::string name;
        if (!readNetCdfString(data, size, offset, name)) return false;
        if (offset + 8 > size) return false;
        uint32_t type = readBe32(data + offset);
        uint32_t len = readBe32(data + offset + 4);
        offset += 8;
        size_t elemSize = 1;
        if (type == 3) elemSize = 2; // short
        else if (type == 4 || type == 5) elemSize = 4; // int/float
        else if (type == 6) elemSize = 8; // double
        size_t bytes = len * elemSize;
        size_t paddedBytes = ((bytes + 3) / 4) * 4;
        if (offset + paddedBytes > size) return false;
        offset += paddedBytes;
    }
    return true;
}

} // namespace

bool SofaDataset::findNearestHrir(double targetAzimuthDeg, double targetElevationDeg,
                                  std::vector<float>& outLeftEar,
                                  std::vector<float>& outRightEar) const {
    if (numMeasurements <= 0 || irLength <= 0 || irData.empty()) return false;

    // Normalize target angles
    while (targetAzimuthDeg > 180.0) targetAzimuthDeg -= 360.0;
    while (targetAzimuthDeg < -180.0) targetAzimuthDeg += 360.0;
    targetElevationDeg = std::clamp(targetElevationDeg, -90.0, 90.0);

    double targetAzRad = targetAzimuthDeg * M_PI / 180.0;
    double targetElRad = targetElevationDeg * M_PI / 180.0;
    double targetX = std::cos(targetElRad) * std::cos(targetAzRad);
    double targetY = std::cos(targetElRad) * std::sin(targetAzRad);
    double targetZ = std::sin(targetElRad);

    int bestIdx = 0;
    double bestDistSq = 1e9;

    for (int m = 0; m < numMeasurements; ++m) {
        double az = azimuths[m];
        while (az > 180.0) az -= 360.0;
        while (az < -180.0) az += 360.0;
        double el = std::clamp(elevations[m], -90.0, 90.0);

        double azRad = az * M_PI / 180.0;
        double elRad = el * M_PI / 180.0;
        double x = std::cos(elRad) * std::cos(azRad);
        double y = std::cos(elRad) * std::sin(azRad);
        double z = std::sin(elRad);

        double dx = targetX - x;
        double dy = targetY - y;
        double dz = targetZ - z;
        double distSq = dx * dx + dy * dy + dz * dz;

        if (distSq < bestDistSq) {
            bestDistSq = distSq;
            bestIdx = m;
        }
    }

    outLeftEar.resize(irLength);
    outRightEar.resize(irLength);

    size_t stride = static_cast<size_t>(numReceivers) * irLength;
    size_t baseL = static_cast<size_t>(bestIdx) * stride;
    size_t baseR = baseL + irLength;

    if (baseR + irLength > irData.size()) return false;

    std::copy_n(irData.data() + baseL, irLength, outLeftEar.begin());
    std::copy_n(irData.data() + baseR, irLength, outRightEar.begin());
    return true;
}

bool HrtfBinaural::parseSofaNetCdf3(const uint8_t* data, size_t size, SofaDataset& outDataset) {
    if (!data || size < 32) return false;

    // Check magic
    bool is64BitOffset = false;
    if (data[0] == 'C' && data[1] == 'D' && data[2] == 'F' && data[3] == 1) {
        is64BitOffset = false;
    } else if (data[0] == 'C' && data[1] == 'D' && data[2] == 'F' && data[3] == 2) {
        is64BitOffset = true;
    } else {
        return false;
    }

    size_t offset = 4;
    // numrecs
    offset += 4;

    // Dimensions
    if (offset + 4 > size) return false;
    uint32_t dimTag = readBe32(data + offset);
    offset += 4;
    if (dimTag != 0 && dimTag != 0x0000000A) return false;

    uint32_t dimCount = (dimTag == 0x0000000A) ? readBe32(data + offset) : 0;
    if (dimTag == 0x0000000A) offset += 4;

    int dimM = 0; // measurements
    int dimR = 2; // receivers
    int dimN = 0; // samples
    int dimC = 3; // coordinate dimensions
    int dimE = 1; // emitters

    std::vector<std::pair<std::string, uint32_t>> dims;
    for (uint32_t i = 0; i < dimCount; ++i) {
        std::string dimName;
        if (!readNetCdfString(data, size, offset, dimName)) return false;
        if (offset + 4 > size) return false;
        uint32_t len = readBe32(data + offset);
        offset += 4;
        dims.push_back({dimName, len});

        if (dimName == "M") dimM = static_cast<int>(len);
        else if (dimName == "R") dimR = static_cast<int>(len);
        else if (dimName == "N") dimN = static_cast<int>(len);
        else if (dimName == "C") dimC = static_cast<int>(len);
        else if (dimName == "E") dimE = static_cast<int>(len);
    }

    // Skip global attributes
    if (!skipNetCdfAttrs(data, size, offset)) return false;

    // Variables
    if (offset + 4 > size) return false;
    uint32_t varTag = readBe32(data + offset);
    offset += 4;
    if (varTag != 0 && varTag != 0x0000000B) return false;

    uint32_t varCount = (varTag == 0x0000000B) ? readBe32(data + offset) : 0;
    if (varTag == 0x0000000B) offset += 4;

    struct VarInfo {
        std::string name;
        std::vector<uint32_t> dimIds;
        uint32_t type = 0;
        uint32_t vsize = 0;
        uint64_t begin = 0;
    };
    std::vector<VarInfo> vars;

    for (uint32_t i = 0; i < varCount; ++i) {
        VarInfo vi;
        if (!readNetCdfString(data, size, offset, vi.name)) return false;
        if (offset + 4 > size) return false;
        uint32_t vDimCount = readBe32(data + offset);
        offset += 4;
        for (uint32_t d = 0; d < vDimCount; ++d) {
            if (offset + 4 > size) return false;
            vi.dimIds.push_back(readBe32(data + offset));
            offset += 4;
        }
        if (!skipNetCdfAttrs(data, size, offset)) return false;
        if (offset + 8 > size) return false;
        vi.type = readBe32(data + offset);
        vi.vsize = readBe32(data + offset + 4);
        offset += 8;

        if (is64BitOffset) {
            if (offset + 8 > size) return false;
            vi.begin = readBe64(data + offset);
            offset += 8;
        } else {
            if (offset + 4 > size) return false;
            vi.begin = readBe32(data + offset);
            offset += 4;
        }
        vars.push_back(vi);
    }

    // Find variables: Data.IR, SourcePosition, Data.SamplingRate
    const VarInfo* irVar = nullptr;
    const VarInfo* posVar = nullptr;
    const VarInfo* srVar = nullptr;

    for (const auto& vi : vars) {
        if (vi.name == "Data.IR") irVar = &vi;
        else if (vi.name == "SourcePosition") posVar = &vi;
        else if (vi.name == "Data.SamplingRate") srVar = &vi;
    }

    if (!irVar || !posVar) return false;
    if (dimM <= 0 || dimN <= 0 || dimN > MAX_HRIR_TAPS) return false;

    outDataset.numMeasurements = dimM;
    outDataset.numReceivers = dimR;
    outDataset.irLength = dimN;
    outDataset.sampleRate = 48000.0;

    // Parse sampling rate if present
    if (srVar && srVar->begin < size) {
        if (srVar->type == 6 && srVar->begin + 8 <= size) {
            outDataset.sampleRate = readBeDouble(data + srVar->begin);
        } else if (srVar->type == 5 && srVar->begin + 4 <= size) {
            outDataset.sampleRate = readBeFloat(data + srVar->begin);
        }
    }

    // Parse SourcePosition [M, C=3]: azimuth, elevation, distance
    outDataset.azimuths.resize(dimM);
    outDataset.elevations.resize(dimM);
    size_t posOffset = posVar->begin;
    for (int m = 0; m < dimM; ++m) {
        double az = 0.0, el = 0.0;
        if (posVar->type == 6) { // double
            if (posOffset + 16 > size) return false;
            az = readBeDouble(data + posOffset);
            el = readBeDouble(data + posOffset + 8);
            posOffset += dimC * 8;
        } else if (posVar->type == 5) { // float
            if (posOffset + 8 > size) return false;
            az = readBeFloat(data + posOffset);
            el = readBeFloat(data + posOffset + 4);
            posOffset += dimC * 4;
        }
        outDataset.azimuths[m] = az;
        outDataset.elevations[m] = el;
    }

    // Parse Data.IR [M, R, N]
    size_t totalSamples = static_cast<size_t>(dimM) * dimR * dimN;
    outDataset.irData.resize(totalSamples);
    size_t irOffset = irVar->begin;

    if (irVar->type == 6) { // double
        if (irOffset + totalSamples * 8 > size) return false;
        for (size_t i = 0; i < totalSamples; ++i) {
            outDataset.irData[i] = static_cast<float>(readBeDouble(data + irOffset + i * 8));
        }
    } else if (irVar->type == 5) { // float
        if (irOffset + totalSamples * 4 > size) return false;
        for (size_t i = 0; i < totalSamples; ++i) {
            outDataset.irData[i] = readBeFloat(data + irOffset + i * 4);
        }
    } else {
        return false;
    }

    return true;
}

bool HrtfBinaural::parseWavHrir(const uint8_t* data, size_t size,
                               std::vector<float>& outL, std::vector<float>& outR,
                               int& outChannels, double& outSampleRate) {
    if (!data || size < 44) return false;
    if (std::memcmp(data, "RIFF", 4) != 0 || std::memcmp(data + 8, "WAVE", 4) != 0) return false;

    size_t offset = 12;
    int channels = 0;
    int format = 0;
    int bitsPerSample = 0;
    uint32_t sampleRate = 0;
    const uint8_t* dataPtr = nullptr;
    size_t dataLen = 0;

    while (offset + 8 <= size) {
        char chunkId[5] = {};
        std::memcpy(chunkId, data + offset, 4);
        uint32_t chunkSize = static_cast<uint32_t>(data[offset + 4]) |
                             (static_cast<uint32_t>(data[offset + 5]) << 8) |
                             (static_cast<uint32_t>(data[offset + 6]) << 16) |
                             (static_cast<uint32_t>(data[offset + 7]) << 24);
        offset += 8;

        if (std::memcmp(chunkId, "fmt ", 4) == 0) {
            if (chunkSize < 16 || offset + 16 > size) return false;
            format = readLeInt16(data + offset);
            channels = readLeInt16(data + offset + 2);
            sampleRate = static_cast<uint32_t>(data[offset + 4]) |
                         (static_cast<uint32_t>(data[offset + 5]) << 8) |
                         (static_cast<uint32_t>(data[offset + 6]) << 16) |
                         (static_cast<uint32_t>(data[offset + 7]) << 24);
            bitsPerSample = readLeInt16(data + offset + 14);
        } else if (std::memcmp(chunkId, "data", 4) == 0) {
            dataPtr = data + offset;
            dataLen = std::min<size_t>(chunkSize, size - offset);
        }
        offset += ((chunkSize + 1) & ~1U);
    }

    if (!dataPtr || channels < 2 || sampleRate == 0) return false;

    int bytesPerSample = bitsPerSample / 8;
    if (bytesPerSample <= 0) return false;
    int numFrames = static_cast<int>(dataLen / (channels * bytesPerSample));
    if (numFrames <= 0) return false;
    numFrames = std::min(numFrames, MAX_HRIR_TAPS);

    outL.resize(numFrames);
    outR.resize(numFrames);
    outChannels = channels;
    outSampleRate = static_cast<double>(sampleRate);

    for (int i = 0; i < numFrames; ++i) {
        const uint8_t* samplePtr = dataPtr + i * channels * bytesPerSample;
        if (format == 3 && bitsPerSample == 32) { // IEEE float
            outL[i] = readLeFloat(samplePtr);
            outR[i] = readLeFloat(samplePtr + 4);
        } else if (format == 1 && bitsPerSample == 16) { // PCM 16
            outL[i] = readLeInt16(samplePtr) / 32768.0f;
            outR[i] = readLeInt16(samplePtr + 2) / 32768.0f;
        } else if (format == 1 && bitsPerSample == 24) { // PCM 24
            int32_t vL = (static_cast<int32_t>(samplePtr[0]) << 8) |
                         (static_cast<int32_t>(samplePtr[1]) << 16) |
                         (static_cast<int32_t>(static_cast<int8_t>(samplePtr[2])) << 24);
            int32_t vR = (static_cast<int32_t>(samplePtr[3]) << 8) |
                         (static_cast<int32_t>(samplePtr[4]) << 16) |
                         (static_cast<int32_t>(static_cast<int8_t>(samplePtr[5])) << 24);
            outL[i] = vL / 2147483648.0f;
            outR[i] = vR / 2147483648.0f;
        } else {
            return false;
        }
    }
    return true;
}

HrirQuad HrtfBinaural::synthesizeDefaultHrir(double azimuthDeg, double elevationDeg,
                                            double sampleRate, int taps) {
    HrirQuad quad;
    quad.taps = std::clamp(taps, 64, MAX_HRIR_TAPS);
    quad.sampleRate = sampleRate;
    quad.azimuthDeg = azimuthDeg;
    quad.elevationDeg = elevationDeg;

    quad.hLL.assign(quad.taps, 0.0f);
    quad.hLR.assign(quad.taps, 0.0f);
    quad.hRL.assign(quad.taps, 0.0f);
    quad.hRR.assign(quad.taps, 0.0f);

    // Virtual speakers placed symmetrically at -azimuth (Left) and +azimuth (Right)
    const double headRadius = 0.0875; // 8.75 cm head radius
    const double speedOfSound = 343.0; // m/s
    const double maxDelaySec = headRadius / speedOfSound * (M_PI / 2.0 + 1.0); // ~0.65ms

    // Woodworth model for angle theta (radians)
    auto computeEarImpulse = [&](double thetaRad, std::vector<float>& ipsi, std::vector<float>& contra) {
        double sinTheta = std::sin(thetaRad);
        double delaySec = 0.0;
        if (sinTheta >= 0.0) {
            delaySec = (headRadius / speedOfSound) * (thetaRad + sinTheta);
        } else {
            delaySec = -(headRadius / speedOfSound) * sinTheta;
        }
        delaySec = std::clamp(delaySec, 0.0, maxDelaySec);

        int delaySamples = static_cast<int>(std::round(delaySec * sampleRate));
        delaySamples = std::clamp(delaySamples, 0, quad.taps / 2);

        // Ipsilateral ear receives direct arrival with slight pinna reflection
        int ipsiOnset = 4;
        if (ipsiOnset < quad.taps) ipsi[ipsiOnset] = 0.95f;
        if (ipsiOnset + 3 < quad.taps) ipsi[ipsiOnset + 3] = -0.15f; // pinna notch
        if (ipsiOnset + 7 < quad.taps) ipsi[ipsiOnset + 7] = 0.08f;

        // Contralateral ear receives head-shadowed arrival with ITD delay and low-pass filter
        int contraOnset = ipsiOnset + delaySamples;
        double shadowFactor = std::max(0.25, 1.0 - 0.7 * std::abs(sinTheta));
        float h0 = static_cast<float>(0.5 * shadowFactor);
        float h1 = static_cast<float>(0.35 * shadowFactor);
        float h2 = static_cast<float>(0.15 * shadowFactor);

        if (contraOnset < quad.taps) contra[contraOnset] = h0;
        if (contraOnset + 1 < quad.taps) contra[contraOnset + 1] = h1;
        if (contraOnset + 2 < quad.taps) contra[contraOnset + 2] = h2;

        // Apply smooth cosine taper to tail to prevent truncation clicks
        int taperLen = std::min(16, quad.taps / 4);
        int taperStart = quad.taps - taperLen;
        for (int i = taperStart; i < quad.taps; ++i) {
            float phase = static_cast<float>(i - taperStart) / static_cast<float>(taperLen);
            float w = 0.5f * (1.0f + std::cos(static_cast<float>(M_PI) * phase));
            ipsi[i] *= w;
            contra[i] *= w;
        }
    };

    double azRad = std::abs(azimuthDeg) * M_PI / 180.0;
    // Left speaker (at -azimuth):
    // hLL is ipsilateral (Left ear), hLR is contralateral (Right ear)
    computeEarImpulse(azRad, quad.hLL, quad.hLR);

    // Right speaker (at +azimuth):
    // hRR is ipsilateral (Right ear), hRL is contralateral (Left ear)
    computeEarImpulse(azRad, quad.hRR, quad.hRL);

    return quad;
}

HrtfBinaural::HrtfBinaural() {
    updateHrirQuad();
}

HrtfBinaural::~HrtfBinaural() = default;

void HrtfBinaural::setSampleRate(double sampleRate) {
    if (sampleRate <= 0.0 || sampleRate_ == sampleRate) return;
    sampleRate_ = sampleRate;
    updateHrirQuad();
    reset();
}

void HrtfBinaural::setEnabled(bool enabled) {
    enabled_.store(enabled, std::memory_order_relaxed);
}

void HrtfBinaural::setAzimuth(double azimuthDeg) {
    azimuthDeg = std::clamp(azimuthDeg, -90.0, 90.0);
    if (std::abs(targetAzimuthDeg_ - azimuthDeg) < 0.1) return;
    targetAzimuthDeg_ = azimuthDeg;
    updateHrirQuad();
}

void HrtfBinaural::setElevation(double elevationDeg) {
    elevationDeg = std::clamp(elevationDeg, -45.0, 45.0);
    if (std::abs(targetElevationDeg_ - elevationDeg) < 0.1) return;
    targetElevationDeg_ = elevationDeg;
    updateHrirQuad();
}

void HrtfBinaural::reset() {
    std::memset(historyL_, 0, sizeof(historyL_));
    std::memset(historyR_, 0, sizeof(historyR_));
    historyIdx_ = 0;
    smoothedEnabledMix_ = enabled_.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    crossfadeProgress_ = 1.0f;
}

void HrtfBinaural::updateHrirQuad() {
    auto newQuad = std::make_shared<HrirQuad>();

    if (sofaDataset_ && sofaDataset_->numMeasurements > 0) {
        newQuad->taps = std::min(sofaDataset_->irLength, MAX_HRIR_TAPS);
        newQuad->sampleRate = sofaDataset_->sampleRate;
        newQuad->azimuthDeg = targetAzimuthDeg_;
        newQuad->elevationDeg = targetElevationDeg_;

        // Left virtual speaker at -azimuth:
        sofaDataset_->findNearestHrir(-std::abs(targetAzimuthDeg_), targetElevationDeg_,
                                     newQuad->hLL, newQuad->hLR);
        // Right virtual speaker at +azimuth:
        sofaDataset_->findNearestHrir(+std::abs(targetAzimuthDeg_), targetElevationDeg_,
                                     newQuad->hRL, newQuad->hRR);
    } else {
        *newQuad = synthesizeDefaultHrir(targetAzimuthDeg_, targetElevationDeg_, sampleRate_);
    }

    if (activeQuad_) {
        oldQuad_ = activeQuad_;
        crossfadeProgress_ = 0.0f;
    } else {
        oldQuad_ = newQuad;
        crossfadeProgress_ = 1.0f;
    }
    activeQuad_ = newQuad;
}

bool HrtfBinaural::loadSofaFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return false;
    std::streamsize fileSize = file.tellg();
    if (fileSize <= 0 || fileSize > 64 * 1024 * 1024) return false; // 64 MB guard

    std::vector<uint8_t> buffer(fileSize);
    file.seekg(0, std::ios::beg);
    if (!file.read(reinterpret_cast<char*>(buffer.data()), fileSize)) return false;

    return loadSofaMemory(buffer.data(), buffer.size());
}

bool HrtfBinaural::loadSofaMemory(const uint8_t* data, size_t size) {
    auto dataset = std::make_shared<SofaDataset>();
    if (!parseSofaNetCdf3(data, size, *dataset)) {
        return false;
    }
    sofaDataset_ = dataset;
    updateHrirQuad();
    return true;
}

bool HrtfBinaural::loadWavHrir(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return false;
    std::streamsize fileSize = file.tellg();
    if (fileSize <= 0 || fileSize > 16 * 1024 * 1024) return false;

    std::vector<uint8_t> buffer(fileSize);
    file.seekg(0, std::ios::beg);
    if (!file.read(reinterpret_cast<char*>(buffer.data()), fileSize)) return false;

    return loadWavHrirMemory(buffer.data(), buffer.size());
}

bool HrtfBinaural::loadWavHrirMemory(const uint8_t* data, size_t size) {
    std::vector<float> wavL, wavR;
    int channels = 0;
    double wavSr = 48000.0;
    if (!parseWavHrir(data, size, wavL, wavR, channels, wavSr)) return false;

    auto quad = std::make_shared<HrirQuad>();
    quad->taps = std::min<int>(static_cast<int>(wavL.size()), MAX_HRIR_TAPS);
    quad->sampleRate = wavSr;
    quad->azimuthDeg = targetAzimuthDeg_;
    quad->elevationDeg = targetElevationDeg_;

    quad->hLL.assign(wavL.begin(), wavL.begin() + quad->taps);
    quad->hLR.assign(wavR.begin(), wavR.begin() + quad->taps);
    // Mirror for symmetric virtual stereo pair
    quad->hRR = quad->hLL;
    quad->hRL = quad->hLR;

    if (activeQuad_) {
        oldQuad_ = activeQuad_;
        crossfadeProgress_ = 0.0f;
    } else {
        oldQuad_ = quad;
        crossfadeProgress_ = 1.0f;
    }
    activeQuad_ = quad;
    return true;
}

bool HrtfBinaural::loadCustomIr(const float* ll, const float* lr, const float* rl, const float* rr,
                               int taps, double irSampleRate) {
    if (!ll || !lr || !rl || !rr || taps <= 0 || taps > MAX_HRIR_TAPS) return false;

    auto quad = std::make_shared<HrirQuad>();
    quad->taps = taps;
    quad->sampleRate = irSampleRate;
    quad->azimuthDeg = targetAzimuthDeg_;
    quad->elevationDeg = targetElevationDeg_;

    quad->hLL.assign(ll, ll + taps);
    quad->hLR.assign(lr, lr + taps);
    quad->hRL.assign(rl, rl + taps);
    quad->hRR.assign(rr, rr + taps);

    if (activeQuad_) {
        oldQuad_ = activeQuad_;
        crossfadeProgress_ = 0.0f;
    } else {
        oldQuad_ = quad;
        crossfadeProgress_ = 1.0f;
    }
    activeQuad_ = quad;
    return true;
}

inline void HrtfBinaural::processFrame(float inL, float inR, float& outL, float& outR,
                                      float currentEnabledMix, float crossfadeStep) {
    // Write new sample to circular buffer (doubled write for contiguous indexing)
    historyL_[historyIdx_] = inL;
    historyL_[historyIdx_ + MAX_HRIR_TAPS] = inL;
    historyR_[historyIdx_] = inR;
    historyR_[historyIdx_ + MAX_HRIR_TAPS] = inR;

    const float* histL = historyL_ + historyIdx_ + 1;
    const float* histR = historyR_ + historyIdx_ + 1;

    historyIdx_--;
    if (historyIdx_ < 0) {
        historyIdx_ = MAX_HRIR_TAPS - 1;
    }

    const HrirQuad* qNew = activeQuad_.get();
    const HrirQuad* qOld = oldQuad_.get();

    float wetL = 0.0f;
    float wetR = 0.0f;

    if (qNew && (!qOld || crossfadeProgress_ >= 1.0f)) {
        const int taps = qNew->taps;
        const float* hLL = qNew->hLL.data();
        const float* hLR = qNew->hLR.data();
        const float* hRL = qNew->hRL.data();
        const float* hRR = qNew->hRR.data();

        float accL = 0.0f;
        float accR = 0.0f;
        for (int k = 0; k < taps; ++k) {
            float sL = histL[k];
            float sR = histR[k];
            accL += sL * hLL[k] + sR * hRL[k];
            accR += sL * hLR[k] + sR * hRR[k];
        }
        wetL = accL;
        wetR = accR;
    } else if (qNew && qOld) {
        float alpha = crossfadeProgress_;
        float oneMinusAlpha = 1.0f - alpha;

        const int tapsNew = qNew->taps;
        float accLNew = 0.0f, accRNew = 0.0f;
        for (int k = 0; k < tapsNew; ++k) {
            float sL = histL[k];
            float sR = histR[k];
            accLNew += sL * qNew->hLL[k] + sR * qNew->hRL[k];
            accRNew += sL * qNew->hLR[k] + sR * qNew->hRR[k];
        }

        const int tapsOld = qOld->taps;
        float accLOld = 0.0f, accROld = 0.0f;
        for (int k = 0; k < tapsOld; ++k) {
            float sL = histL[k];
            float sR = histR[k];
            accLOld += sL * qOld->hLL[k] + sR * qOld->hRL[k];
            accROld += sL * qOld->hLR[k] + sR * qOld->hRR[k];
        }

        wetL = accLNew * alpha + accLOld * oneMinusAlpha;
        wetR = accRNew * alpha + accROld * oneMinusAlpha;

        crossfadeProgress_ = std::min(1.0f, crossfadeProgress_ + crossfadeStep);
        if (crossfadeProgress_ >= 1.0f) {
            oldQuad_ = activeQuad_;
        }
    }

    // Blend wet and dry according to smoothedEnabledMix_
    outL = inL + (wetL - inL) * currentEnabledMix;
    outR = inR + (wetR - inR) * currentEnabledMix;
}

void HrtfBinaural::process(const float* inL, const float* inR, float* outL, float* outR, int frames) {
    if (!inL || !inR || !outL || !outR || frames <= 0) return;

    bool enabled = enabled_.load(std::memory_order_relaxed);
    float targetMix = enabled ? 1.0f : 0.0f;
    float mixStep = (targetMix - smoothedEnabledMix_) / static_cast<float>(frames);
    float crossfadeStep = (sampleRate_ > 0.0) ? (1.0f / (0.015f * static_cast<float>(sampleRate_))) : 0.001f;

    for (int i = 0; i < frames; ++i) {
        smoothedEnabledMix_ += mixStep;
        processFrame(inL[i], inR[i], outL[i], outR[i], smoothedEnabledMix_, crossfadeStep);
    }
    smoothedEnabledMix_ = targetMix;
}

void HrtfBinaural::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels < 2) return;

    bool enabled = enabled_.load(std::memory_order_relaxed);
    float targetMix = enabled ? 1.0f : 0.0f;
    float mixStep = (targetMix - smoothedEnabledMix_) / static_cast<float>(frames);
    float crossfadeStep = (sampleRate_ > 0.0) ? (1.0f / (0.015f * static_cast<float>(sampleRate_))) : 0.001f;

    for (int i = 0; i < frames; ++i) {
        smoothedEnabledMix_ += mixStep;
        float inL = buffer[i * channels];
        float inR = buffer[i * channels + 1];
        float outL = inL, outR = inR;
        processFrame(inL, inR, outL, outR, smoothedEnabledMix_, crossfadeStep);
        buffer[i * channels] = outL;
        buffer[i * channels + 1] = outR;
    }
    smoothedEnabledMix_ = targetMix;
}

} // namespace pulsr
