// android/app/src/main/cpp/Uac2Volume.h
//
// UAC2 hardware volume codec. Pure arithmetic over the values a device reports
// through its AudioStreaming interface, with no USB transport in this file: the
// platform layer performs the control transfers, this module decides *what*
// value to send and how to interpret what came back
// (test_uac2_volume.cpp).
//
// Units
// -----
// UAC2 volume is a signed 16-bit quantity in 1/256 dB ("Q8.8" in the spec's
// wording, although it is a plain 8.8 fixed-point dB value, not a fraction of
// full scale). 0x0100 = 1.00 dB, 0xFF00 = -1.00 dB, 0x8000 = -128.00 dB and
// 0x7FFF = +127.996 dB. Values travel little-endian on the wire, so a device
// reporting MIN_CUR = -60 dB sends 0x00 0xC4 (-15360). The codec works on the
// host-order int16_t; byte swapping belongs to the transport.
//
// Wire shape (must be implemented exactly by the transport)
// --------------------------------------------------------
//   SET_CUR  bmRequestType = 0x21 (OUT | CLASS | INTERFACE)
//            bRequest      = 0x01
//            wValue        = (0x01 << 8) | channel   // mute (CS_MUTE = 0x01)
//                            (0x02 << 8) | channel   // volume (CS_VOLUME = 0x02)
//            wIndex        = entity ID in high byte | interface number in low byte
//   GET_CUR  bmRequestType = 0xA1, bRequest = 0x81 (UAC1 and UAC2)
//   GET_MIN  bmRequestType = 0xA1, bRequest = 0x82
//   GET_MAX  bmRequestType = 0xA1, bRequest = 0x83
//   GET_RES  bmRequestType = 0xA1, bRequest = 0x84
// All four range requests return a 2-byte little-endian value for the channel's
// volume control (a mute control, if queried, returns 1 byte).
//
// Never assume a 0..-60 dB range, and never assume min/max/res are ordered the
// way a particular DAC family orders them: read GET_MIN/GET_MAX/GET_RES once,
// validate with IsValidRange(), then map UI positions through these helpers.
// The mapping is linear in dB - that is what the hardware control itself is -
// and the value that leaves this module is always one the device advertised:
// snapped to resQ8 and clamped into [minQ8, maxQ8].
#ifndef PULSR_UAC2_VOLUME_H_
#define PULSR_UAC2_VOLUME_H_

#include <cstddef>
#include <cstdint>

namespace pulsr {

/// UAC Feature Unit Control Selectors
constexpr uint8_t kUacCsMute = 0x01;
constexpr uint8_t kUacCsVolume = 0x02;

/// Standard USB Control Transfer Request layout.
struct UacControlRequest {
    uint8_t bmRequestType = 0;
    uint8_t bRequest = 0;
    uint16_t wValue = 0;
    uint16_t wIndex = 0;
    uint16_t wLength = 0;
};

/// Builds a standard UAC control transfer request (SET_CUR = 0x01, GET_CUR = 0x81 on both UAC1 and UAC2).
UacControlRequest BuildUacControlRequest(
    bool write,
    uint8_t controlSelector,
    uint8_t unitId,
    uint8_t interfaceNumber,
    uint8_t channel,
    uint16_t length,
    int uacVersion = 2);

/// Builds a SET_CUR control request for the Feature Unit CS_MUTE control.
UacControlRequest BuildUacMuteSetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel);

/// Builds a GET_CUR control request for the Feature Unit CS_MUTE control.
UacControlRequest BuildUacMuteGetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel, int uacVersion = 2);

/// Builds a SET_CUR control request for the Feature Unit CS_VOLUME control.
UacControlRequest BuildUacVolumeSetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel);

/// Builds a GET_CUR control request for the Feature Unit CS_VOLUME control.
UacControlRequest BuildUacVolumeGetRequest(uint8_t unitId, uint8_t interfaceNumber, uint8_t channel, int uacVersion = 2);

/// Encodes a boolean mute state into the single-byte payload (0x01 = muted, 0x00 = unmuted).
uint8_t EncodeUacMutePayload(bool muted);

/// Decodes the single-byte mute payload (non-zero = muted).
bool DecodeUacMutePayload(uint8_t payload);

/// Evaluates per-channel mute readbacks. Returns true only if count > 0 and all channel bytes decode to muted.
bool AllChannelsMuted(const uint8_t* channelBytes, size_t count);

/// A device's volume range as reported by GET_MIN / GET_MAX / GET_RES, in
/// 1/256 dB units.
struct Uac2VolumeRange {
    int16_t minQ8 = 0;
    int16_t maxQ8 = 0;
    int16_t resQ8 = 0;
};

/// Converts decibels to the 1/256 dB wire unit, rounded to nearest and clamped
/// to the int16_t range. NaN maps to 0 (0 dB, the neutral value) because this
/// function has no range context; use Uac2VolumePositionToQ8() when a UI
/// position is involved - that path resolves NaN to the quietest permitted
/// value instead.
int16_t Uac2VolumeToQ8(double db);

/// Converts a 1/256 dB wire value back to decibels.
double Uac2VolumeFromQ8(int16_t raw);

/// True when the range can be used for mapping: min < max and res > 0.
bool IsValidRange(const Uac2VolumeRange& range);

/// Maps a 0..1 UI position onto the device range (linear in dB), snaps the
/// result to the resQ8 grid measured from minQ8, and clamps it into
/// [minQ8, maxQ8]. Position is clamped to 0..1 first; NaN resolves to 0, i.e.
/// the quietest permitted value.
///
/// A degenerate range (min >= max) never resolves to a loud surprise: the
/// function returns the quieter of the two endpoints. resQ8 <= 0 is treated as
/// a 1/256 dB grid rather than being rejected, so a device that omits GET_RES
/// still gets sane values; callers that care should gate on IsValidRange()
/// first.
int16_t Uac2VolumePositionToQ8(double position, const Uac2VolumeRange& range);

/// Inverse of the linear mapping, for painting a slider from a GET_CUR value.
/// The result is clamped to 0..1 and is *not* snapped (it reports where the
/// device actually sits). Returns 0.0 for a degenerate range.
double Uac2VolumeQ8ToPosition(int16_t q8, const Uac2VolumeRange& range);

}  // namespace pulsr

#endif  // PULSR_UAC2_VOLUME_H_
