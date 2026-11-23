// android/app/src/main/cpp/HrtfBinaural.cpp
#include "HrtfBinaural.h"

#include <fstream>
#include <sstream>
#include <cstring>
#include <cassert>
#include <chrono>
#include <thread>

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
    if (offset > size || size - offset < 4) return false;
    uint32_t len = readBe32(data + offset);
    offset += 4;
    if (len > 1024 * 1024) return false;
    uint64_t paddedLen = ((static_cast<uint64_t>(len) + 3ULL) / 4ULL) * 4ULL;
    if (paddedLen > static_cast<uint64_t>(size - offset)) return false;
    outStr.assign(reinterpret_cast<const char*>(data + offset), len);
    offset += static_cast<size_t>(paddedLen);
    return true;
}

bool skipNetCdfAttrs(const uint8_t* data, size_t size, size_t& offset) {
    if (offset > size || size - offset < 4) return false;
    uint32_t tag = readBe32(data + offset);
    offset += 4;
    if (tag == 0) return true; // NC_UNSPECIFIED
    if (tag != 0x0000000C) return false; // NC_ATTRIBUTE
    if (offset > size || size - offset < 4) return false;
    uint32_t count = readBe32(data + offset);
    offset += 4;
    if (count > 65536) return false;
    for (uint32_t i = 0; i < count; ++i) {
        std::string name;
        if (!readNetCdfString(data, size, offset, name)) return false;
        if (offset > size || size - offset < 8) return false;
        uint32_t type = readBe32(data + offset);
        uint32_t len = readBe32(data + offset + 4);
        offset += 8;
        size_t elemSize = 1;
        if (type == 3) elemSize = 2; // short
        else if (type == 4 || type == 5) elemSize = 4; // int/float
        else if (type == 6) elemSize = 8; // double
        uint64_t bytes = static_cast<uint64_t>(len) * static_cast<uint64_t>(elemSize);
        uint64_t paddedBytes = ((bytes + 3ULL) / 4ULL) * 4ULL;
        if (paddedBytes > static_cast<uint64_t>(size - offset)) return false;
        offset += static_cast<size_t>(paddedBytes);
    }
    return true;
}

inline double sincNorm(double x) {
    if (std::abs(x) < 1e-12) return 1.0;
    const double px = M_PI * x;
    return std::sin(px) / px;
}

// §8.9: short windowed-sinc resampler used only while PREPARING an HRIR on the
// control thread. It converts one finite impulse response from the dataset /
// file rate to the engine rate before convolution, so a 44.1 kHz SOFA HRIR is
// no longer convolved as if it were a 48 kHz one (which shortened ITD and
// shifted pinna notches). `out` receives exactly outTaps samples.
constexpr int kIrResampleHalfTaps = 8;

void resampleIr(const float* in, int inLen, double srcRate, double dstRate,
                float* out, int outTaps) {
    if (!out || outTaps <= 0) return;
    if (!in || inLen <= 0 || srcRate <= 0.0 || dstRate <= 0.0) {
        std::fill_n(out, outTaps, 0.0f);
        return;
    }
    // Exact same rate -> the stored HRIR already matches the engine grid.
    if (outTaps == inLen && std::abs(srcRate - dstRate) < 0.01) {
        std::copy_n(in, inLen, out);
        return;
    }
    const double step = srcRate / dstRate;
    const double ratio = dstRate / srcRate;
    // Anti-image (upsampling) / anti-alias (downsampling) cutoff.
    const double cutoff = ratio >= 1.0 ? 1.0 : ratio;
    const int half = kIrResampleHalfTaps;

    for (int n = 0; n < outTaps; ++n) {
        const double t = static_cast<double>(n) * step;
        const int center = static_cast<int>(std::floor(t));
        const double frac = t - static_cast<double>(center);
        double acc = 0.0;
        double weightSum = 0.0;
        for (int k = -half + 1; k <= half; ++k) {
            const double x = frac - static_cast<double>(k); // input-sample distance
            if (std::abs(x) >= static_cast<double>(half)) continue;
            // Hann window centred on the interpolation point.
            const double window = 0.5 * (1.0 + std::cos(M_PI * x / half));
            const double h = cutoff * sincNorm(cutoff * x) * window;
            const int idx = center + k;
            if (idx < 0 || idx >= inLen) continue;
            acc += static_cast<double>(in[idx]) * h;
            weightSum += h;
        }
        // Renormalise against the taps actually inside the IR so the first and
        // last samples do not lose level to edge truncation.
        out[n] = (std::abs(weightSum) > 1e-9f)
                     ? static_cast<float>(acc / weightSum)
                     : 0.0f;
    }
}

// Linear distance between two directions on the unit sphere, in radians.
inline double angularDistance(double azA, double elA, double azB, double elB) {
    const double azARad = azA * M_PI / 180.0;
    const double elARad = elA * M_PI / 180.0;
    const double azBRad = azB * M_PI / 180.0;
    const double elBRad = elB * M_PI / 180.0;
    const double xa = std::cos(elARad) * std::cos(azARad);
    const double ya = std::cos(elARad) * std::sin(azARad);
    const double za = std::sin(elARad);
    const double xb = std::cos(elBRad) * std::cos(azBRad);
    const double yb = std::cos(elBRad) * std::sin(azBRad);
    const double zb = std::sin(elBRad);
    const double dx = xa - xb, dy = ya - yb, dz = za - zb;
    return std::sqrt(dx * dx + dy * dy + dz * dz);
}

// Fills an already-sized HrirQuad with the analytic synthetic model. The
// vectors are re-assigned (capacity, never size, is what matters), so calling
// this on a reserved slot does not allocate.
void fillSyntheticQuad(HrirQuad& quad, double azimuthDeg, double elevationDeg,
                       double sampleRate, int taps) {
    quad.taps = std::clamp(taps, 64, HrtfBinaural::MAX_HRIR_TAPS);
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
    const double safeSr = (sampleRate > 0.0 && std::isfinite(sampleRate)) ? sampleRate : 48000.0;
    const double srScale = safeSr / 48000.0;
    auto computeEarImpulse = [&](double thetaRad, std::vector<float>& ipsi, std::vector<float>& contra) {
        double sinTheta = std::sin(thetaRad);
        double delaySec = 0.0;
        if (sinTheta >= 0.0) {
            delaySec = (headRadius / speedOfSound) * (thetaRad + sinTheta);
        } else {
            delaySec = -(headRadius / speedOfSound) * sinTheta;
        }
        delaySec = std::clamp(delaySec, 0.0, maxDelaySec);

        int delaySamples = static_cast<int>(std::round(delaySec * safeSr));
        delaySamples = std::clamp(delaySamples, 0, quad.taps / 2);

        // Ipsilateral ear receives direct arrival with sample-rate-scaled pinna reflections
        const int ipsiOnset = std::clamp(static_cast<int>(std::round(4.0 * srScale)), 1, quad.taps / 4);
        const int notch1 = std::max(1, static_cast<int>(std::round(3.0 * srScale)));
        const int notch2 = std::max(notch1 + 1, static_cast<int>(std::round(7.0 * srScale)));
        if (ipsiOnset < quad.taps) ipsi[ipsiOnset] = 0.95f;
        if (ipsiOnset + notch1 < quad.taps) ipsi[ipsiOnset + notch1] = -0.15f; // pinna notch
        if (ipsiOnset + notch2 < quad.taps) ipsi[ipsiOnset + notch2] = 0.08f;

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
        int taperLen = std::min(quad.taps / 4, std::max(16, static_cast<int>(std::round(16.0 * srScale))));
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

bool SofaDataset::findInterpolatedHrir(double targetAzimuthDeg, double targetElevationDeg,
                                       double targetSampleRate, int maxTaps,
                                       std::vector<float>& outLeftEar,
                                       std::vector<float>& outRightEar,
                                       int& outTaps) const {
    outTaps = 0;
    if (numMeasurements <= 0 || irLength <= 0 || irData.empty()) return false;
    if (numReceivers < 2 || maxTaps <= 0) return false;
    if (!(targetSampleRate > 0.0) || !(sampleRate > 0.0)) return false;

    while (targetAzimuthDeg > 180.0) targetAzimuthDeg -= 360.0;
    while (targetAzimuthDeg < -180.0) targetAzimuthDeg += 360.0;
    targetElevationDeg = std::clamp(targetElevationDeg, -90.0, 90.0);

    // Inverse-distance weights over the four nearest measurements on the
    // sphere. For a one-measurement dataset this degenerates to the direct
    // (resampled) measurement; otherwise a target between grid points blends
    // real neighbouring HRIRs, which keeps ITD/ILD and notch depth continuous
    // instead of snapping to one measurement.
    constexpr int kNeighbors = 4;
    int neighborIdx[kNeighbors] = {0, 0, 0, 0};
    double neighborDist[kNeighbors] = {1e9, 1e9, 1e9, 1e9};
    int neighborCount = 0;

    for (int m = 0; m < numMeasurements; ++m) {
        const double dist = angularDistance(
            targetAzimuthDeg, targetElevationDeg, azimuths[m], elevations[m]);
        if (neighborCount < kNeighbors) {
            neighborIdx[neighborCount] = m;
            neighborDist[neighborCount] = dist;
            ++neighborCount;
        } else {
            int worst = 0;
            for (int k = 1; k < kNeighbors; ++k) {
                if (neighborDist[k] > neighborDist[worst]) worst = k;
            }
            if (dist < neighborDist[worst]) {
                neighborIdx[worst] = m;
                neighborDist[worst] = dist;
            }
        }
    }

    double weight[kNeighbors] = {0.0, 0.0, 0.0, 0.0};
    double weightSum = 0.0;
    for (int k = 0; k < neighborCount; ++k) {
        // Inverse-square distance with a small floor: an on-grid target is
        // dominated by its exact measurement, while ties (front/back, left/
        // right mirror) are split smoothly.
        weight[k] = 1.0 / (neighborDist[k] * neighborDist[k] + 1e-4);
        weightSum += weight[k];
    }
    if (weightSum <= 0.0) return false;
    for (int k = 0; k < neighborCount; ++k) weight[k] /= weightSum;

    const double ratio = targetSampleRate / sampleRate;
    int taps = static_cast<int>(std::ceil(static_cast<double>(irLength) * ratio));
    taps = std::clamp(taps, 1, maxTaps);
    if (taps > HrtfBinaural::MAX_HRIR_TAPS) taps = HrtfBinaural::MAX_HRIR_TAPS;

    outLeftEar.resize(static_cast<size_t>(taps));
    outRightEar.resize(static_cast<size_t>(taps));
    std::fill(outLeftEar.begin(), outLeftEar.end(), 0.0f);
    std::fill(outRightEar.begin(), outRightEar.end(), 0.0f);

    float scratch[HrtfBinaural::MAX_HRIR_TAPS];
    const size_t stride = static_cast<size_t>(numReceivers) * irLength;

    for (int k = 0; k < neighborCount; ++k) {
        const size_t base = static_cast<size_t>(neighborIdx[k]) * stride;
        if (base + stride > irData.size()) return false;
        const float* srcL = irData.data() + base;
        const float* srcR = srcL + irLength;
        resampleIr(srcL, irLength, sampleRate, targetSampleRate, scratch, taps);
        for (int n = 0; n < taps; ++n) {
            outLeftEar[static_cast<size_t>(n)] +=
                static_cast<float>(weight[k]) * scratch[n];
        }
        resampleIr(srcR, irLength, sampleRate, targetSampleRate, scratch, taps);
        for (int n = 0; n < taps; ++n) {
            outRightEar[static_cast<size_t>(n)] +=
                static_cast<float>(weight[k]) * scratch[n];
        }
    }

    outTaps = taps;
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
    if (offset > size || size - offset < 4) return false;
    uint32_t dimTag = readBe32(data + offset);
    offset += 4;
    if (dimTag != 0 && dimTag != 0x0000000A) return false;

    uint32_t dimCount = 0;
    if (dimTag == 0x0000000A) {
        if (offset > size || size - offset < 4) return false;
        dimCount = readBe32(data + offset);
        offset += 4;
    }
    if (dimCount > 1024) return false;

    int dimM = 0; // measurements
    int dimR = 2; // receivers
    int dimN = 0; // samples
    int dimC = 3; // coordinate dimensions
    int dimE = 1; // emitters

    std::vector<std::pair<std::string, uint32_t>> dims;
    dims.reserve(dimCount);
    for (uint32_t i = 0; i < dimCount; ++i) {
        std::string dimName;
        if (!readNetCdfString(data, size, offset, dimName)) return false;
        if (offset > size || size - offset < 4) return false;
        uint32_t len = readBe32(data + offset);
        offset += 4;
        if (len > 0x7FFFFFFFu) return false;
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
    if (offset > size || size - offset < 4) return false;
    uint32_t varTag = readBe32(data + offset);
    offset += 4;
    if (varTag != 0 && varTag != 0x0000000B) return false;

    uint32_t varCount = 0;
    if (varTag == 0x0000000B) {
        if (offset > size || size - offset < 4) return false;
        varCount = readBe32(data + offset);
        offset += 4;
    }
    if (varCount > 4096) return false;

    struct VarInfo {
        std::string name;
        std::vector<uint32_t> dimIds;
        uint32_t type = 0;
        uint32_t vsize = 0;
        uint64_t begin = 0;
    };
    std::vector<VarInfo> vars;
    vars.reserve(varCount);

    for (uint32_t i = 0; i < varCount; ++i) {
        VarInfo vi;
        if (!readNetCdfString(data, size, offset, vi.name)) return false;
        if (offset > size || size - offset < 4) return false;
        uint32_t vDimCount = readBe32(data + offset);
        offset += 4;
        if (vDimCount > 64) return false;
        vi.dimIds.reserve(vDimCount);
        for (uint32_t d = 0; d < vDimCount; ++d) {
            if (offset > size || size - offset < 4) return false;
            vi.dimIds.push_back(readBe32(data + offset));
            offset += 4;
        }
        if (!skipNetCdfAttrs(data, size, offset)) return false;
        if (offset > size || size - offset < 8) return false;
        vi.type = readBe32(data + offset);
        vi.vsize = readBe32(data + offset + 4);
        offset += 8;

        if (is64BitOffset) {
            if (offset > size || size - offset < 8) return false;
            vi.begin = readBe64(data + offset);
            offset += 8;
        } else {
            if (offset > size || size - offset < 4) return false;
            vi.begin = readBe32(data + offset);
            offset += 4;
        }
        vars.push_back(std::move(vi));
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
    if (dimM <= 0 || dimM > 100000 ||
        dimR < 2 || dimR > 8 ||
        dimC < 2 || dimC > 16 ||
        dimN <= 0 || dimN > MAX_HRIR_TAPS) {
        return false;
    }

    outDataset.numMeasurements = dimM;
    outDataset.numReceivers = dimR;
    outDataset.irLength = dimN;
    outDataset.sampleRate = 48000.0;

    // Parse sampling rate if present
    if (srVar && srVar->begin < size) {
        if (srVar->type == 6 && size - srVar->begin >= 8) {
            outDataset.sampleRate = readBeDouble(data + srVar->begin);
        } else if (srVar->type == 5 && size - srVar->begin >= 4) {
            outDataset.sampleRate = readBeFloat(data + srVar->begin);
        }
    }
    if (!(outDataset.sampleRate > 0.0) || !std::isfinite(outDataset.sampleRate)) {
        outDataset.sampleRate = 48000.0;
    }

    // Parse SourcePosition [M, C]: azimuth, elevation, (optional distance)
    const uint64_t posElemSize = (posVar->type == 6) ? 8ULL : (posVar->type == 5 ? 4ULL : 0ULL);
    if (posElemSize == 0) return false;
    const uint64_t posStrideBytes = static_cast<uint64_t>(dimC) * posElemSize;
    const uint64_t totalPosBytes = static_cast<uint64_t>(dimM) * posStrideBytes;
    if (totalPosBytes > static_cast<uint64_t>(size) ||
        posVar->begin > static_cast<uint64_t>(size) - totalPosBytes) {
        return false;
    }

    outDataset.azimuths.resize(dimM);
    outDataset.elevations.resize(dimM);
    size_t posOffset = static_cast<size_t>(posVar->begin);
    for (int m = 0; m < dimM; ++m) {
        double az = 0.0, el = 0.0;
        if (posVar->type == 6) { // double
            az = readBeDouble(data + posOffset);
            el = readBeDouble(data + posOffset + 8);
        } else { // float
            az = readBeFloat(data + posOffset);
            el = readBeFloat(data + posOffset + 4);
        }
        posOffset += static_cast<size_t>(posStrideBytes);
        outDataset.azimuths[m] = std::isfinite(az) ? az : 0.0;
        outDataset.elevations[m] = std::isfinite(el) ? el : 0.0;
    }

    // Parse Data.IR [M, R, N]
    const uint64_t totalSamples64 =
        static_cast<uint64_t>(dimM) * static_cast<uint64_t>(dimR) * static_cast<uint64_t>(dimN);
    if (totalSamples64 == 0 || totalSamples64 > 64ULL * 1024ULL * 1024ULL) return false;
    const uint64_t irElemSize = (irVar->type == 6) ? 8ULL : (irVar->type == 5 ? 4ULL : 0ULL);
    if (irElemSize == 0) return false;
    const uint64_t totalIrBytes = totalSamples64 * irElemSize;
    if (totalIrBytes > static_cast<uint64_t>(size) ||
        irVar->begin > static_cast<uint64_t>(size) - totalIrBytes) {
        return false;
    }

    const size_t totalSamples = static_cast<size_t>(totalSamples64);
    outDataset.irData.resize(totalSamples);
    const size_t irOffset = static_cast<size_t>(irVar->begin);

    if (irVar->type == 6) { // double
        for (size_t i = 0; i < totalSamples; ++i) {
            float v = static_cast<float>(readBeDouble(data + irOffset + i * 8));
            outDataset.irData[i] = std::isfinite(v) ? v : 0.0f;
        }
    } else { // float
        for (size_t i = 0; i < totalSamples; ++i) {
            float v = readBeFloat(data + irOffset + i * 4);
            outDataset.irData[i] = std::isfinite(v) ? v : 0.0f;
        }
    }

    return true;
}

bool HrtfBinaural::parseWavHrirQuad(const uint8_t* data, size_t size,
                                     std::vector<float>& outLL, std::vector<float>& outLR,
                                     std::vector<float>& outRL, std::vector<float>& outRR,
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
        const uint64_t paddedChunk = (static_cast<uint64_t>(chunkSize) + 1ULL) & ~1ULL;
        if (paddedChunk > size - offset) break;
        offset += static_cast<size_t>(paddedChunk);
    }

    if (!dataPtr || channels < 2 || sampleRate == 0) return false;

    int bytesPerSample = bitsPerSample / 8;
    if (bytesPerSample <= 0) return false;
    int numFrames = static_cast<int>(dataLen / (channels * bytesPerSample));
    if (numFrames <= 0) return false;
    numFrames = std::min(numFrames, MAX_HRIR_TAPS);

    outLL.resize(numFrames);
    outLR.resize(numFrames);
    if (channels >= 4) {
        outRL.resize(numFrames);
        outRR.resize(numFrames);
    } else {
        outRL.clear();
        outRR.clear();
    }
    outChannels = channels;
    outSampleRate = static_cast<double>(sampleRate);

    auto decodeSample = [&](const uint8_t* ptr, float& outVal) -> bool {
        if (format == 3 && bitsPerSample == 32) {
            outVal = readLeFloat(ptr);
            return true;
        }
        if (format == 1 && bitsPerSample == 16) {
            outVal = readLeInt16(ptr) / 32768.0f;
            return true;
        }
        if (format == 1 && bitsPerSample == 24) {
            const int32_t v = (static_cast<int32_t>(ptr[0]) << 8) |
                              (static_cast<int32_t>(ptr[1]) << 16) |
                              (static_cast<int32_t>(static_cast<int8_t>(ptr[2])) << 24);
            outVal = v / 2147483648.0f;
            return true;
        }
        return false;
    };

    for (int i = 0; i < numFrames; ++i) {
        const uint8_t* samplePtr = dataPtr + i * channels * bytesPerSample;
        if (!decodeSample(samplePtr, outLL[i]) ||
            !decodeSample(samplePtr + bytesPerSample, outLR[i])) {
            return false;
        }
        if (channels >= 4) {
            if (!decodeSample(samplePtr + 2 * bytesPerSample, outRL[i]) ||
                !decodeSample(samplePtr + 3 * bytesPerSample, outRR[i])) {
                return false;
            }
        }
    }
    return true;
}

bool HrtfBinaural::parseWavHrir(const uint8_t* data, size_t size,
                               std::vector<float>& outL, std::vector<float>& outR,
                               int& outChannels, double& outSampleRate) {
    std::vector<float> unusedRL, unusedRR;
    return parseWavHrirQuad(data, size, outL, outR, unusedRL, unusedRR, outChannels, outSampleRate);
}

HrirQuad HrtfBinaural::synthesizeDefaultHrir(double azimuthDeg, double elevationDeg,
                                            double sampleRate, int taps) {
    HrirQuad quad;
    fillSyntheticQuad(quad, azimuthDeg, elevationDeg, sampleRate, taps);
    return quad;
}

HrtfBinaural::HrtfBinaural() {
    // Reserve the full tap capacity in every slot once, on the owning (control)
    // thread, so every later prepare only ever changes vector *size*.
    for (auto& quad : slots_) {
        quad.hLL.reserve(MAX_HRIR_TAPS);
        quad.hLR.reserve(MAX_HRIR_TAPS);
        quad.hRL.reserve(MAX_HRIR_TAPS);
        quad.hRR.reserve(MAX_HRIR_TAPS);
    }
    prepareLocked(30.0, 0.0, 48000.0);
}

HrtfBinaural::~HrtfBinaural() = default;

void HrtfBinaural::setSampleRate(double sampleRate) {
    if (!(sampleRate > 0.0)) return;
    if (std::abs(engineSampleRate_.load(std::memory_order_relaxed) - sampleRate) < 0.01) return;
    prepare(targetAzimuthDeg_.load(std::memory_order_relaxed),
            targetElevationDeg_.load(std::memory_order_relaxed), sampleRate);
    // Defer buffer/filter state reset to the render thread so control-side rate
    // changes cannot race process()/processInterleaved().
    resetGen_.fetch_add(1, std::memory_order_release);
}

void HrtfBinaural::setEnabled(bool enabled) {
    enabled_.store(enabled, std::memory_order_relaxed);
}

void HrtfBinaural::setAzimuth(double azimuthDeg) {
    azimuthDeg = std::clamp(azimuthDeg, -90.0, 90.0);
    if (std::abs(targetAzimuthDeg_.load(std::memory_order_relaxed) - azimuthDeg) < 0.1) return;
    prepare(azimuthDeg, targetElevationDeg_.load(std::memory_order_relaxed),
            engineSampleRate_.load(std::memory_order_relaxed));
}

void HrtfBinaural::setElevation(double elevationDeg) {
    elevationDeg = std::clamp(elevationDeg, -45.0, 45.0);
    if (std::abs(targetElevationDeg_.load(std::memory_order_relaxed) - elevationDeg) < 0.1) return;
    prepare(targetAzimuthDeg_.load(std::memory_order_relaxed), elevationDeg,
            engineSampleRate_.load(std::memory_order_relaxed));
}

void HrtfBinaural::reset() {
    std::memset(historyL_, 0, sizeof(historyL_));
    std::memset(historyR_, 0, sizeof(historyR_));
    historyIdx_ = 0;
    smoothedEnabledMix_ = enabled_.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    // Drop back to the new-only path. The render thread acks the previous slot
    // on its next block (see process/processInterleaved), so a reset issued by
    // a control thread never releases a slot the renderer may still be reading.
    crossfadeProgress_ = 1.0f;
}

bool HrtfBinaural::prepare(double azimuthDeg, double elevationDeg, double engineSampleRate) {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    return prepareLocked(azimuthDeg, elevationDeg, engineSampleRate);
}

bool HrtfBinaural::prepareLocked(double azimuthDeg, double elevationDeg,
                                 double engineSampleRate) {
    if (!std::isfinite(azimuthDeg)) azimuthDeg = 30.0;
    if (!std::isfinite(elevationDeg)) elevationDeg = 0.0;
    if (!std::isfinite(engineSampleRate) || engineSampleRate < 8000.0) {
        engineSampleRate = 48000.0;
    }
    azimuthDeg = std::clamp(azimuthDeg, -90.0, 90.0);
    elevationDeg = std::clamp(elevationDeg, -45.0, 45.0);

    targetAzimuthDeg_.store(azimuthDeg, std::memory_order_relaxed);
    targetElevationDeg_.store(elevationDeg, std::memory_order_relaxed);
    engineSampleRate_.store(engineSampleRate, std::memory_order_relaxed);

    // A custom (WAV / raw) IR is geometry-independent: only a rate change or a
    // new source requires a rebuild.
    const bool geometryMatters = (source_ != IrSource::Custom);
    if (hasPublished_ &&
        std::abs(engineSampleRate - lastPreparedSampleRate_) < 0.01 &&
        (!geometryMatters ||
         (std::abs(azimuthDeg - lastPreparedAzimuthDeg_) < 0.01 &&
          std::abs(elevationDeg - lastPreparedElevationDeg_) < 0.01))) {
        return true;
    }

    int slot = -1;
    if (!acquireFreeSlotLocked(slot)) return false;

    if (!buildQuadLocked(slot, azimuthDeg, elevationDeg, engineSampleRate)) {
        // Never publish a half-built slot: fall back to the analytic model.
        if (source_ == IrSource::Synthetic) return false;
        source_ = IrSource::Synthetic;
        dataset_.reset();
        hasDataset_.store(false, std::memory_order_relaxed);
        if (!buildQuadLocked(slot, azimuthDeg, elevationDeg, engineSampleRate)) {
            return false;
        }
    }

    publishSlotLocked(slot);
    lastPreparedAzimuthDeg_ = azimuthDeg;
    lastPreparedElevationDeg_ = elevationDeg;
    lastPreparedSampleRate_ = engineSampleRate;
    hasPublished_ = true;
    return true;
}

bool HrtfBinaural::acquireFreeSlotLocked(int& outSlot) {
    // A slot is free when it is not pending (ready), not the active quad and
    // not the crossfade source. Read ready first: the render thread publishes
    // active/old before it clears ready, so an acquire-load of ready == -1 also
    // observes the slots it just claimed. Four slots against at most three
    // referenced guarantees a free slot even while playback is paused; the
    // bounded wait is only a safety net against an unexpected reader bug.
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(200);
    for (;;) {
        const int ready = readySlot_.load(std::memory_order_acquire);
        const int active = activeSlotAtomic_.load(std::memory_order_acquire);
        const int old = oldSlotAtomic_.load(std::memory_order_acquire);
        for (int s = 0; s < kHrirSlotCount; ++s) {
            if (s != ready && s != active && s != old) {
                outSlot = s;
                return true;
            }
        }
        if (std::chrono::steady_clock::now() >= deadline) return false;
        std::this_thread::yield();
    }
}

bool HrtfBinaural::buildQuadLocked(int slot, double azimuthDeg, double elevationDeg,
                                   double engineSampleRate) {
    HrirQuad& quad = slots_[slot];
    quad.sampleRate = engineSampleRate;
    quad.azimuthDeg = azimuthDeg;
    quad.elevationDeg = elevationDeg;

    if (source_ == IrSource::Dataset) {
        if (!dataset_ || dataset_->numMeasurements <= 0) return false;
        const SofaDataset& ds = *dataset_;
        const double ratio = engineSampleRate / ds.sampleRate;
        int taps = static_cast<int>(
            std::ceil(static_cast<double>(ds.irLength) * ratio));
        taps = std::clamp(taps, 1, MAX_HRIR_TAPS);
        quad.taps = taps;
        int outTapsL = 0;
        int outTapsR = 0;
        // Left virtual speaker at -azimuth, right at +azimuth (existing model).
        if (!ds.findInterpolatedHrir(-std::abs(azimuthDeg), elevationDeg,
                                     engineSampleRate, taps,
                                     quad.hLL, quad.hLR, outTapsL)) {
            return false;
        }
        if (!ds.findInterpolatedHrir(+std::abs(azimuthDeg), elevationDeg,
                                     engineSampleRate, taps,
                                     quad.hRL, quad.hRR, outTapsR)) {
            return false;
        }
        if (outTapsL != taps || outTapsR != taps) return false;
        return true;
    }

    if (source_ == IrSource::Custom) {
        if (!customIrSource_) return false;
        const int srcTaps = customIrSource_->taps;
        if (srcTaps <= 0 ||
            customIrSource_->hLL.size() < static_cast<size_t>(srcTaps) ||
            customIrSource_->hLR.size() < static_cast<size_t>(srcTaps) ||
            customIrSource_->hRL.size() < static_cast<size_t>(srcTaps) ||
            customIrSource_->hRR.size() < static_cast<size_t>(srcTaps)) {
            return false;
        }
        const double srcRate = customIrSource_->sampleRate > 0.0
                                   ? customIrSource_->sampleRate
                                   : 48000.0;
        int taps = static_cast<int>(
            std::ceil(static_cast<double>(srcTaps) * engineSampleRate / srcRate));
        taps = std::clamp(taps, 1, MAX_HRIR_TAPS);
        quad.taps = taps;
        quad.hLL.resize(static_cast<size_t>(taps));
        quad.hLR.resize(static_cast<size_t>(taps));
        quad.hRL.resize(static_cast<size_t>(taps));
        quad.hRR.resize(static_cast<size_t>(taps));
        resampleIr(customIrSource_->hLL.data(), srcTaps, srcRate, engineSampleRate,
                   quad.hLL.data(), taps);
        resampleIr(customIrSource_->hLR.data(), srcTaps, srcRate, engineSampleRate,
                   quad.hLR.data(), taps);
        resampleIr(customIrSource_->hRL.data(), srcTaps, srcRate, engineSampleRate,
                   quad.hRL.data(), taps);
        resampleIr(customIrSource_->hRR.data(), srcTaps, srcRate, engineSampleRate,
                   quad.hRR.data(), taps);
        return true;
    }

    const int synthTaps = std::clamp(
        static_cast<int>(std::round(static_cast<double>(DEFAULT_HRIR_TAPS) *
                                    (engineSampleRate / 48000.0))),
        DEFAULT_HRIR_TAPS, MAX_HRIR_TAPS);
    fillSyntheticQuad(quad, azimuthDeg, elevationDeg, engineSampleRate, synthTaps);
    return true;
}

void HrtfBinaural::publishSlotLocked(int slot) {
    // Release-store the fully built slot index. A later store (e.g. another
    // slider tick) simply coalesces: the render thread always claims the newest
    // ready slot, and the intermediate slot was never referenced by the reader.
    readySlot_.store(slot, std::memory_order_release);
}

void HrtfBinaural::applyPrepared() {
    const int ready = readySlot_.load(std::memory_order_acquire);
    if (ready >= 0 && ready < kHrirSlotCount) {
        const int previousActive = activeSlot_;
        activeSlot_ = ready;
        oldSlot_ = previousActive;
        // Crossfade only while the convolver is audible. While disabled the mix is
        // zero, so switching slots immediately avoids leaving a phantom ramp (and a
        // needless limiter/latency excursion) after a geometry change.
        const bool fadeIn = previousActive >= 0 && previousActive != ready &&
                            enabled_.load(std::memory_order_relaxed);
        crossfadeProgress_ = fadeIn ? 0.0f : 1.0f;
        // Publish active/old BEFORE clearing ready: the control writer reads ready
        // first, so it can never mistake this slot for free in the window between
        // claiming it and publishing the indices.
        activeSlotAtomic_.store(activeSlot_, std::memory_order_release);
        oldSlotAtomic_.store(oldSlot_, std::memory_order_release);
        int expected = ready;
        readySlot_.compare_exchange_strong(expected, -1,
                                           std::memory_order_acq_rel,
                                           std::memory_order_acquire);
    }
    const uint64_t pendingReset = resetGen_.load(std::memory_order_acquire);
    if (pendingReset != lastResetGen_) {
        reset();
        lastResetGen_ = pendingReset;
    }
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

    std::lock_guard<std::mutex> lock(prepareMutex_);
    // Swap the control-side dataset and force a rebuild. The render thread only
    // ever reads one of the immutable, preallocated quad slots, so installing a
    // dataset never mutates memory the render thread is convolving.
    dataset_ = std::move(dataset);
    customIrSource_.reset();
    source_ = IrSource::Dataset;
    hasDataset_.store(true, std::memory_order_relaxed);
    hasPublished_ = false;
    const bool prepared = prepareLocked(
        targetAzimuthDeg_.load(std::memory_order_relaxed),
        targetElevationDeg_.load(std::memory_order_relaxed),
        engineSampleRate_.load(std::memory_order_relaxed));
    // A dataset the quad builder cannot use (e.g. R < 2) falls back to the
    // synthetic model; report that as a failed load instead of claiming the
    // user's SOFA file is active.
    return prepared && hasDataset_.load(std::memory_order_relaxed);
}

bool HrtfBinaural::clearDataset() {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    dataset_.reset();
    customIrSource_.reset();
    hasDataset_.store(false, std::memory_order_relaxed);
    source_ = IrSource::Synthetic;
    hasPublished_ = false;
    return prepareLocked(targetAzimuthDeg_.load(std::memory_order_relaxed),
                         targetElevationDeg_.load(std::memory_order_relaxed),
                         engineSampleRate_.load(std::memory_order_relaxed));
}

void HrtfBinaural::setDataset(std::shared_ptr<const SofaDataset> dataset) {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    if (dataset == dataset_) return;
    if (dataset) {
        dataset_ = std::move(dataset);
        customIrSource_.reset();
        source_ = IrSource::Dataset;
        hasDataset_.store(true, std::memory_order_relaxed);
    } else {
        // A snapshot without a dataset (e.g. the user cleared it) only resets
        // a dataset-backed HRIR; a WAV/custom IR is geometry-independent and
        // owned by the direct load path, so it stays untouched.
        if (source_ != IrSource::Dataset) return;
        dataset_.reset();
        source_ = IrSource::Synthetic;
        hasDataset_.store(false, std::memory_order_relaxed);
    }
    hasPublished_ = false; // force the next prepare() to rebuild + publish
}

std::shared_ptr<const SofaDataset> HrtfBinaural::getDataset() const {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    return dataset_;
}

void HrtfBinaural::setCustomIr(std::shared_ptr<const HrirQuad> customIr) {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    if (customIr == customIrSource_) return;
    if (customIr) {
        customIrSource_ = std::move(customIr);
        dataset_.reset();
        source_ = IrSource::Custom;
        hasDataset_.store(false, std::memory_order_relaxed);
    } else {
        if (source_ != IrSource::Custom) return;
        customIrSource_.reset();
        source_ = IrSource::Synthetic;
        hasDataset_.store(false, std::memory_order_relaxed);
    }
    hasPublished_ = false;
}

std::shared_ptr<const HrirQuad> HrtfBinaural::getCustomIr() const {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    return customIrSource_;
}

void HrtfBinaural::applySnapshotSources(std::shared_ptr<const SofaDataset> dataset,
                                        std::shared_ptr<const HrirQuad> customIr) {
    std::lock_guard<std::mutex> lock(prepareMutex_);
    if (customIr) {
        if (customIr == customIrSource_ && source_ == IrSource::Custom) return;
        customIrSource_ = std::move(customIr);
        dataset_.reset();
        source_ = IrSource::Custom;
        hasDataset_.store(false, std::memory_order_relaxed);
        hasPublished_ = false;
        return;
    }
    if (dataset) {
        if (dataset == dataset_ && source_ == IrSource::Dataset) return;
        dataset_ = std::move(dataset);
        customIrSource_.reset();
        source_ = IrSource::Dataset;
        hasDataset_.store(true, std::memory_order_relaxed);
        hasPublished_ = false;
        return;
    }
    if (source_ != IrSource::Synthetic || dataset_ || customIrSource_) {
        dataset_.reset();
        customIrSource_.reset();
        source_ = IrSource::Synthetic;
        hasDataset_.store(false, std::memory_order_relaxed);
        hasPublished_ = false;
    }
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
    std::vector<float> wavLL, wavLR, wavRL, wavRR;
    int channels = 0;
    double wavSr = 48000.0;
    if (!parseWavHrirQuad(data, size, wavLL, wavLR, wavRL, wavRR, channels, wavSr)) return false;

    auto source = std::make_shared<HrirQuad>();
    source->taps = std::min<int>(static_cast<int>(wavLL.size()), MAX_HRIR_TAPS);
    source->sampleRate = wavSr;
    source->azimuthDeg = targetAzimuthDeg_.load(std::memory_order_relaxed);
    source->elevationDeg = targetElevationDeg_.load(std::memory_order_relaxed);

    source->hLL.assign(wavLL.begin(), wavLL.begin() + source->taps);
    source->hLR.assign(wavLR.begin(), wavLR.begin() + source->taps);
    if (channels >= 4 && static_cast<int>(wavRL.size()) >= source->taps &&
        static_cast<int>(wavRR.size()) >= source->taps) {
        source->hRL.assign(wavRL.begin(), wavRL.begin() + source->taps);
        source->hRR.assign(wavRR.begin(), wavRR.begin() + source->taps);
    } else {
        // Mirror for symmetric virtual stereo pair
        source->hRR = source->hLL;
        source->hRL = source->hLR;
    }

    std::lock_guard<std::mutex> lock(prepareMutex_);
    customIrSource_ = std::move(source);
    dataset_.reset();
    hasDataset_.store(false, std::memory_order_relaxed);
    source_ = IrSource::Custom;
    hasPublished_ = false;
    return prepareLocked(targetAzimuthDeg_.load(std::memory_order_relaxed),
                         targetElevationDeg_.load(std::memory_order_relaxed),
                         engineSampleRate_.load(std::memory_order_relaxed));
}

bool HrtfBinaural::loadCustomIr(const float* ll, const float* lr, const float* rl, const float* rr,
                               int taps, double irSampleRate) {
    if (!ll || !lr || !rl || !rr || taps <= 0 || taps > MAX_HRIR_TAPS) return false;

    auto source = std::make_shared<HrirQuad>();
    source->taps = taps;
    source->sampleRate = irSampleRate > 0.0 ? irSampleRate : 48000.0;
    source->azimuthDeg = targetAzimuthDeg_.load(std::memory_order_relaxed);
    source->elevationDeg = targetElevationDeg_.load(std::memory_order_relaxed);

    source->hLL.assign(ll, ll + taps);
    source->hLR.assign(lr, lr + taps);
    source->hRL.assign(rl, rl + taps);
    source->hRR.assign(rr, rr + taps);

    std::lock_guard<std::mutex> lock(prepareMutex_);
    customIrSource_ = std::move(source);
    dataset_.reset();
    hasDataset_.store(false, std::memory_order_relaxed);
    source_ = IrSource::Custom;
    hasPublished_ = false;
    return prepareLocked(targetAzimuthDeg_.load(std::memory_order_relaxed),
                         targetElevationDeg_.load(std::memory_order_relaxed),
                         engineSampleRate_.load(std::memory_order_relaxed));
}

bool HrtfBinaural::copyActiveQuad(HrirQuad& out) const {
    const int active = activeSlotAtomic_.load(std::memory_order_acquire);
    if (active < 0 || active >= kHrirSlotCount) return false;
    out = slots_[active];
    return true;
}

inline void HrtfBinaural::processFrame(float inL, float inR, float& outL, float& outR,
                                      float currentEnabledMix, float crossfadeStep,
                                      const HrirQuad* qNew, const HrirQuad* qOld) {
    if (!std::isfinite(inL)) inL = 0.0f;
    if (!std::isfinite(inR)) inR = 0.0f;
    // Write new sample to circular buffer (doubled write for contiguous indexing).
    // Reading from `historyIdx_` places x[n] at index 0, x[n-1] at 1, ...
    historyL_[historyIdx_] = inL;
    historyL_[historyIdx_ + MAX_HRIR_TAPS] = inL;
    historyR_[historyIdx_] = inR;
    historyR_[historyIdx_ + MAX_HRIR_TAPS] = inR;

    const float* histL = historyL_ + historyIdx_;
    const float* histR = historyR_ + historyIdx_;

    historyIdx_--;
    if (historyIdx_ < 0) {
        historyIdx_ = MAX_HRIR_TAPS - 1;
    }

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
        // The old slot is acknowledged at the block boundary (process /
        // processInterleaved), never mid-block: later frames in this block
        // still hold qOld and must not race a control writer reusing it.
    }

    // Blend wet and dry according to smoothedEnabledMix_
    outL = inL + (wetL - inL) * currentEnabledMix;
    outR = inR + (wetR - inR) * currentEnabledMix;
}

void HrtfBinaural::process(const float* inL, const float* inR, float* outL, float* outR, int frames) {
    if (!inL || !inR || !outL || !outR || frames <= 0) return;

    applyPrepared();

    // A reset (rate change / flush) forces the new-only path; release the
    // previous slot now that this render thread is no longer blending it.
    if (oldSlot_ != activeSlot_ && crossfadeProgress_ >= 1.0f) {
        oldSlot_ = activeSlot_;
        oldSlotAtomic_.store(activeSlot_, std::memory_order_release);
    }

    const bool enabled = enabled_.load(std::memory_order_relaxed);
    if (!enabled && smoothedEnabledMix_ <= 1e-6f) {
        smoothedEnabledMix_ = 0.0f;
        if (outL != inL) std::memcpy(outL, inL, static_cast<size_t>(frames) * sizeof(float));
        if (outR != inR) std::memcpy(outR, inR, static_cast<size_t>(frames) * sizeof(float));
        return;
    }

    const float targetMix = enabled ? 1.0f : 0.0f;
    const double sr = engineSampleRate_.load(std::memory_order_relaxed);
    const float effSr = (sr > 0.0 && std::isfinite(sr)) ? static_cast<float>(sr) : 48000.0f;
    const float mixStep = 1.0f / std::max(1.0f, 0.020f * effSr);
    const float crossfadeStep = 1.0f / std::max(1.0f, 0.015f * effSr);

    const HrirQuad* qNew = (activeSlot_ >= 0 && activeSlot_ < kHrirSlotCount)
                               ? &slots_[activeSlot_]
                               : nullptr;
    const HrirQuad* qOld = (oldSlot_ >= 0 && oldSlot_ < kHrirSlotCount &&
                            oldSlot_ != activeSlot_)
                               ? &slots_[oldSlot_]
                               : nullptr;

    for (int i = 0; i < frames; ++i) {
        if (smoothedEnabledMix_ < targetMix) {
            smoothedEnabledMix_ = std::min(targetMix, smoothedEnabledMix_ + mixStep);
        } else if (smoothedEnabledMix_ > targetMix) {
            smoothedEnabledMix_ = std::max(targetMix, smoothedEnabledMix_ - mixStep);
        }
        processFrame(inL[i], inR[i], outL[i], outR[i], smoothedEnabledMix_,
                     crossfadeStep, qNew, qOld);
    }

    if (oldSlot_ != activeSlot_ && crossfadeProgress_ >= 1.0f) {
        oldSlot_ = activeSlot_;
        oldSlotAtomic_.store(activeSlot_, std::memory_order_release);
    }
}

void HrtfBinaural::processInterleaved(float* buffer, int frames, int channels) {
    if (!buffer || frames <= 0 || channels < 2) return;

    applyPrepared();

    // See process(): release a previous slot that reset() stopped blending.
    if (oldSlot_ != activeSlot_ && crossfadeProgress_ >= 1.0f) {
        oldSlot_ = activeSlot_;
        oldSlotAtomic_.store(activeSlot_, std::memory_order_release);
    }

    const bool enabled = enabled_.load(std::memory_order_relaxed);
    if (!enabled && smoothedEnabledMix_ <= 1e-6f) {
        smoothedEnabledMix_ = 0.0f;
        return;
    }

    const float targetMix = enabled ? 1.0f : 0.0f;
    const double sr = engineSampleRate_.load(std::memory_order_relaxed);
    const float effSr = (sr > 0.0 && std::isfinite(sr)) ? static_cast<float>(sr) : 48000.0f;
    const float mixStep = 1.0f / std::max(1.0f, 0.020f * effSr);
    const float crossfadeStep = 1.0f / std::max(1.0f, 0.015f * effSr);

    const HrirQuad* qNew = (activeSlot_ >= 0 && activeSlot_ < kHrirSlotCount)
                               ? &slots_[activeSlot_]
                               : nullptr;
    const HrirQuad* qOld = (oldSlot_ >= 0 && oldSlot_ < kHrirSlotCount &&
                            oldSlot_ != activeSlot_)
                               ? &slots_[oldSlot_]
                               : nullptr;
    for (int i = 0; i < frames; ++i) {
        if (smoothedEnabledMix_ < targetMix) {
            smoothedEnabledMix_ = std::min(targetMix, smoothedEnabledMix_ + mixStep);
        } else if (smoothedEnabledMix_ > targetMix) {
            smoothedEnabledMix_ = std::max(targetMix, smoothedEnabledMix_ - mixStep);
        }
        float inL = buffer[i * channels];
        float inR = buffer[i * channels + 1];
        float outL = inL, outR = inR;
        processFrame(inL, inR, outL, outR, smoothedEnabledMix_, crossfadeStep,
                     qNew, qOld);
        buffer[i * channels] = outL;
        buffer[i * channels + 1] = outR;
    }

    if (oldSlot_ != activeSlot_ && crossfadeProgress_ >= 1.0f) {
        oldSlot_ = activeSlot_;
        oldSlotAtomic_.store(activeSlot_, std::memory_order_release);
    }
}

} // namespace pulsr
