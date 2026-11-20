// android/app/src/main/cpp/Uac2Volume.cpp
//
// See Uac2Volume.h for the units and the wire request shape.
#include "Uac2Volume.h"

#include <cmath>
#include <cstdint>

namespace pulsr {
namespace {

constexpr double kQ8PerDb = 256.0;
constexpr int kQ8Min = -32768;
constexpr int kQ8Max = 32767;

}  // namespace

UacControlRequest BuildUacControlRequest(
    bool write,
    uint8_t controlSelector,
    uint8_t unitId,
    uint8_t interfaceNumber,
    uint8_t channel,
    uint16_t length,
    int /*uacVersion*/) {
    UacControlRequest req;
    req.bmRequestType = write ? 0x21 : 0xA1;  // 0x21: Host to device | Class | Interface; 0xA1: Device to host
    req.bRequest = write ? 0x01 : 0x81;       // SET_CUR = 0x01, GET_CUR = 0x81 on both UAC1 and UAC2
    req.wValue = static_cast<uint16_t>((static_cast<uint16_t>(controlSelector) << 8) | channel);
    req.wIndex = static_cast<uint16_t>((static_cast<uint16_t>(unitId) << 8) | interfaceNumber);
    req.wLength = length;
    return req;
}

UacControlRequest BuildUacMuteSetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel) {
    return BuildUacControlRequest(true, kUacCsMute, unitId, interfaceNumber, channel, 1);
}

UacControlRequest BuildUacMuteGetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel, int uacVersion) {
    return BuildUacControlRequest(false, kUacCsMute, unitId, interfaceNumber, channel, 1, uacVersion);
}

UacControlRequest BuildUacVolumeSetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel) {
    return BuildUacControlRequest(true, kUacCsVolume, unitId, interfaceNumber, channel, 2);
}

UacControlRequest BuildUacVolumeGetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel, int uacVersion) {
    return BuildUacControlRequest(false, kUacCsVolume, unitId, interfaceNumber, channel, 2, uacVersion);
}

uint8_t EncodeUacMutePayload(bool muted) {
    return muted ? 0x01 : 0x00;
}

bool DecodeUacMutePayload(uint8_t payload) {
    return payload != 0x00;
}

bool AllChannelsMuted(const uint8_t* channelBytes, size_t count) {
    if (channelBytes == nullptr || count == 0) return false;
    for (size_t i = 0; i < count; ++i) {
        if (!DecodeUacMutePayload(channelBytes[i])) return false;
    }
    return true;
}

int16_t Uac2VolumeToQ8(double db) {
    if (std::isnan(db)) return 0;
    const double scaled = db * kQ8PerDb;
    if (scaled >= static_cast<double>(kQ8Max)) return static_cast<int16_t>(kQ8Max);
    if (scaled <= static_cast<double>(kQ8Min)) return static_cast<int16_t>(kQ8Min);
    return static_cast<int16_t>(std::lround(scaled));
}

double Uac2VolumeFromQ8(int16_t raw) {
    return static_cast<double>(raw) / kQ8PerDb;
}

bool IsValidRange(const Uac2VolumeRange& range) {
    return range.minQ8 < range.maxQ8 && range.resQ8 > 0;
}

int16_t Uac2VolumePositionToQ8(double position, const Uac2VolumeRange& range) {
    if (range.minQ8 >= range.maxQ8) {
        // Degenerate or reversed: pick the quieter endpoint rather than
        // letting a bad descriptor claim full scale.
        return (range.maxQ8 < range.minQ8) ? range.maxQ8 : range.minQ8;
    }

    const int minQ8 = static_cast<int>(range.minQ8);
    const int span = static_cast<int>(range.maxQ8) - minQ8;
    const int step = (range.resQ8 > 0) ? static_cast<int>(range.resQ8) : 1;

    double clamped = position;
    if (std::isnan(clamped)) clamped = 0.0;  // never treat NaN as full scale
    if (clamped < 0.0) clamped = 0.0;
    if (clamped > 1.0) clamped = 1.0;

    const double target =
        static_cast<double>(minQ8) + clamped * static_cast<double>(span);
    const int steps =
        static_cast<int>(std::llround((target - static_cast<double>(minQ8)) /
                                     static_cast<double>(step)));
    // The clamp is not redundant: maxQ8 does not have to sit on the res grid,
    // so the last snapped step can overshoot it. Clamping to the range (not to
    // the int16 limits) is what keeps a 2 dB grid honest on a 1000 Q8 span.
    int snapped = minQ8 + steps * step;
    if (snapped < minQ8) snapped = minQ8;
    if (snapped > static_cast<int>(range.maxQ8)) snapped = static_cast<int>(range.maxQ8);
    return static_cast<int16_t>(snapped);
}

double Uac2VolumeQ8ToPosition(int16_t q8, const Uac2VolumeRange& range) {
    if (range.minQ8 >= range.maxQ8) return 0.0;
    const double minQ8 = static_cast<double>(range.minQ8);
    const double span = static_cast<double>(range.maxQ8) - minQ8;
    const double position = (static_cast<double>(q8) - minQ8) / span;
    if (!(position >= 0.0)) return 0.0;  // also catches NaN
    if (position > 1.0) return 1.0;
    return position;
}

}  // namespace pulsr
