// android/app/src/test/cpp/test_uac2_volume.cpp
//
// Host test for the UAC2 hardware-volume codec: Q8.8 conversion, range
// validation, position mapping with snapping and clamping, and round trips.
#include "../../main/cpp/Uac2Volume.h"

#include <cmath>
#include <cstdint>
#include <iostream>

namespace {

int gFailures = 0;

void Check(bool ok, const char* what) {
    if (ok) {
        std::cout << "  OK " << what << std::endl;
        return;
    }
    std::cout << "  FAIL " << what << std::endl;
    ++gFailures;
}

bool NearlyEqual(double got, double want, double tolerance = 1e-12) {
    return std::fabs(got - want) <= tolerance;
}

pulsr::Uac2VolumeRange Range(int minQ8, int maxQ8, int resQ8) {
    pulsr::Uac2VolumeRange range;
    range.minQ8 = static_cast<int16_t>(minQ8);
    range.maxQ8 = static_cast<int16_t>(maxQ8);
    range.resQ8 = static_cast<int16_t>(resQ8);
    return range;
}

}  // namespace

int main() {
    std::cout << "[TEST] Running UAC2 volume codec tests..." << std::endl;

    // ---------------------------------------------------------------------
    // 1. dB <-> Q8.8 (1/256 dB), including the wire-documented endpoints.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::Uac2VolumeToQ8(0.0) == 0, "0 dB -> 0x0000");
        Check(pulsr::Uac2VolumeToQ8(1.0) == 256, "1 dB -> 0x0100");
        Check(pulsr::Uac2VolumeToQ8(-1.0) == -256, "-1 dB -> 0xFF00");
        Check(pulsr::Uac2VolumeToQ8(0.5) == 128, "0.5 dB -> 128");
        Check(pulsr::Uac2VolumeToQ8(-0.5) == -128, "-0.5 dB -> -128");
        Check(pulsr::Uac2VolumeToQ8(-60.0) == -15360, "-60 dB -> -15360 (0xC400)");
        Check(pulsr::Uac2VolumeToQ8(-127.5) == -32640, "-127.5 dB -> -32640");
        Check(pulsr::Uac2VolumeToQ8(200.0) == 32767, "out-of-range positive dB clamps");
        Check(pulsr::Uac2VolumeToQ8(-200.0) == -32768, "out-of-range negative dB clamps");
        Check(pulsr::Uac2VolumeToQ8(1.0 / 512.0) == 1, "half a Q8 step rounds away from zero");
        Check(pulsr::Uac2VolumeToQ8(-1.0 / 512.0) == -1, "negative half step rounds away from zero");
        Check(pulsr::Uac2VolumeToQ8(std::nan("")) == 0, "NaN maps to the neutral 0 dB");
        Check(pulsr::Uac2VolumeToQ8(HUGE_VAL) == 32767, "+inf clamps high");
        Check(pulsr::Uac2VolumeToQ8(-HUGE_VAL) == -32768, "-inf clamps low");
    }
    {
        Check(NearlyEqual(pulsr::Uac2VolumeFromQ8(0), 0.0), "0x0000 -> 0 dB");
        Check(NearlyEqual(pulsr::Uac2VolumeFromQ8(256), 1.0), "0x0100 -> 1 dB");
        Check(NearlyEqual(pulsr::Uac2VolumeFromQ8(-15360), -60.0), "0xC400 -> -60 dB");
        Check(NearlyEqual(pulsr::Uac2VolumeFromQ8(-32640), -127.5), "-32640 -> -127.5 dB");
        Check(NearlyEqual(pulsr::Uac2VolumeFromQ8(32767), 127.99609375),
              "0x7FFF -> +127.99609375 dB");
        Check(NearlyEqual(pulsr::Uac2VolumeFromQ8(-32768), -128.0), "0x8000 -> -128 dB");
    }
    {
        const double decibels[] = {-60.0, -30.0, -12.5, -6.0, -0.5, 0.0, 3.5};
        bool ok = true;
        for (const double db : decibels) {
            if (!NearlyEqual(pulsr::Uac2VolumeFromQ8(pulsr::Uac2VolumeToQ8(db)), db)) {
                ok = false;
            }
        }
        Check(ok, "dB -> Q8 -> dB round trip is exact for 1/256 dB values");
    }

    // ---------------------------------------------------------------------
    // 2. Range validation.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::IsValidRange(Range(-12800, 0, 256)), "typical -50..0 dB range is valid");
        Check(pulsr::IsValidRange(Range(-32768, 32767, 1)), "full int16 range is valid");
        Check(!pulsr::IsValidRange(Range(0, 0, 256)), "min == max rejected");
        Check(!pulsr::IsValidRange(Range(100, -100, 256)), "min > max rejected");
        Check(!pulsr::IsValidRange(Range(-12800, 0, 0)), "resolution 0 rejected");
        Check(!pulsr::IsValidRange(Range(-12800, 0, -256)), "negative resolution rejected");
        Check(!pulsr::IsValidRange(Range(-12800, -12800, 1)), "coincident endpoints rejected");
    }

    // ---------------------------------------------------------------------
    // 3. Position -> Q8: linear in dB over the device range.
    // ---------------------------------------------------------------------
    {
        const pulsr::Uac2VolumeRange range = Range(-12800, 0, 256);  // -50..0 dB, 1 dB steps
        bool ok = true;
        for (int step = 0; step <= 50; ++step) {
            const double position = static_cast<double>(step) / 50.0;
            const int want = -12800 + step * 256;
            if (pulsr::Uac2VolumePositionToQ8(position, range) != want) ok = false;
        }
        Check(ok, "positions 0..1 map onto the -50..0 dB grid");
        Check(pulsr::Uac2VolumePositionToQ8(0.0, range) == -12800, "position 0 is min");
        Check(pulsr::Uac2VolumePositionToQ8(1.0, range) == 0, "position 1 is max");
        Check(pulsr::Uac2VolumePositionToQ8(0.5, range) == -6400, "position 0.5 is -25 dB");
    }
    {
        // A device that does not report RES: 1/256 dB steps, still mapped.
        const pulsr::Uac2VolumeRange range = Range(-1000, 0, 0);
        Check(pulsr::Uac2VolumePositionToQ8(0.5, range) == -500,
              "res 0 falls back to 1 Q8 steps");
        Check(!pulsr::IsValidRange(range), "...and that range is still flagged invalid");
    }

    // ---------------------------------------------------------------------
    // 4. Snapping to resQ8.
    // ---------------------------------------------------------------------
    {
        const pulsr::Uac2VolumeRange range = Range(-12800, 0, 512);  // 2 dB steps
        // target for 0.1 = -11520; (target - min) / 512 = 2.5 -> 3 -> -11264
        Check(pulsr::Uac2VolumePositionToQ8(0.1, range) == -11264,
              "0.1 snaps to the 2 dB grid (2.5 steps rounds away from zero)");
        // target for 0.05 = -12160; 640 / 512 = 1.25 -> 1 -> -12288
        Check(pulsr::Uac2VolumePositionToQ8(0.05, range) == -12288,
              "0.05 snaps down to the 2 dB grid");
        // target for 0.30 = -8960; 3840 / 512 = 7.5 -> 8 -> -8704
        Check(pulsr::Uac2VolumePositionToQ8(0.30, range) == -8704,
              "0.30 snaps up to the 2 dB grid");
    }
    {
        // Every value sent to the device must sit on the advertised grid.
        const pulsr::Uac2VolumeRange range = Range(-12800, 0, 512);
        bool ok = true;
        for (int step = 0; step <= 100; ++step) {
            const int q8 = pulsr::Uac2VolumePositionToQ8(step / 100.0, range);
            if (((q8 - range.minQ8) % range.resQ8) != 0) ok = false;
            if (q8 < range.minQ8 || q8 > range.maxQ8) ok = false;
        }
        Check(ok, "all 101 sampled positions land on the grid and inside the range");
    }
    {
        // maxQ8 is not required to sit on the grid; the top step clamps to it.
        const pulsr::Uac2VolumeRange range = Range(-1000, 0, 512);
        Check(pulsr::Uac2VolumePositionToQ8(1.0, range) == 0,
              "off-grid max is reached exactly at position 1");
        Check(pulsr::Uac2VolumePositionToQ8(0.99, range) <= 0,
              "off-grid max is never exceeded");
    }

    // ---------------------------------------------------------------------
    // 5. Clamping and degenerate positions.
    // ---------------------------------------------------------------------
    {
        const pulsr::Uac2VolumeRange range = Range(-12800, 0, 256);
        Check(pulsr::Uac2VolumePositionToQ8(-3.0, range) == -12800, "position below 0 clamps to min");
        Check(pulsr::Uac2VolumePositionToQ8(7.0, range) == 0, "position above 1 clamps to max");
        Check(pulsr::Uac2VolumePositionToQ8(-HUGE_VAL, range) == -12800, "-inf clamps to min");
        Check(pulsr::Uac2VolumePositionToQ8(HUGE_VAL, range) == 0, "+inf clamps to max");
        Check(pulsr::Uac2VolumePositionToQ8(std::nan(""), range) == -12800,
              "NaN resolves to the quietest value, never full scale");
    }

    // ---------------------------------------------------------------------
    // 6. Q8 -> position (inverse mapping, clamping, degenerate range).
    // ---------------------------------------------------------------------
    {
        const pulsr::Uac2VolumeRange range = Range(-12800, 0, 256);
        bool ok = true;
        for (int step = 0; step <= 50; ++step) {
            const int q8 = -12800 + step * 256;
            const double want = static_cast<double>(step) / 50.0;
            if (!NearlyEqual(pulsr::Uac2VolumeQ8ToPosition(static_cast<int16_t>(q8), range),
                             want)) {
                ok = false;
            }
        }
        Check(ok, "Q8 -> position is the exact inverse on the grid");
        Check(NearlyEqual(pulsr::Uac2VolumeQ8ToPosition(-6400, range), 0.5), "-6400 -> 0.5");
        Check(pulsr::Uac2VolumeQ8ToPosition(-20000, range) == 0.0, "below min clamps to 0");
        Check(pulsr::Uac2VolumeQ8ToPosition(5000, range) == 1.0, "above max clamps to 1");
        Check(pulsr::Uac2VolumeQ8ToPosition(-500, Range(-1000, 0, 512)) == 0.5,
              "inverse ignores the grid");
    }
    {
        Check(pulsr::Uac2VolumeQ8ToPosition(-6400, Range(0, 0, 256)) == 0.0,
              "degenerate range yields position 0");
        Check(pulsr::Uac2VolumeQ8ToPosition(-6400, Range(100, -100, 256)) == 0.0,
              "reversed range yields position 0");
    }

    // ---------------------------------------------------------------------
    // 7. Round trip position -> Q8 -> position.
    // ---------------------------------------------------------------------
    {
        const pulsr::Uac2VolumeRange range = Range(-12800, 0, 256);
        bool ok = true;
        for (int step = 0; step <= 50; ++step) {
            const double position = static_cast<double>(step) / 50.0;
            const int q8 = pulsr::Uac2VolumePositionToQ8(position, range);
            const double back =
                pulsr::Uac2VolumeQ8ToPosition(static_cast<int16_t>(q8), range);
            if (!NearlyEqual(back, position, 1e-9)) ok = false;
        }
        Check(ok, "position -> Q8 -> position round trip is stable");
    }

    // ---------------------------------------------------------------------
    // 8. Degenerate ranges never resolve to a loud surprise.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::Uac2VolumePositionToQ8(1.0, Range(0, 0, 256)) == 0,
              "coincident endpoints return that single value");
        Check(pulsr::Uac2VolumePositionToQ8(1.0, Range(100, -100, 256)) == -100,
              "reversed range returns the quieter endpoint");
        Check(pulsr::Uac2VolumePositionToQ8(0.0, Range(100, -100, -1)) == -100,
              "reversed range with bad res still returns the quieter endpoint");
    }

    // ---------------------------------------------------------------------
    // 9. Monotonicity across the whole range (a slider must never go backwards).
    // ---------------------------------------------------------------------
    {
        const pulsr::Uac2VolumeRange range = Range(-32768, 32767, 1);
        bool ok = true;
        int16_t previous = pulsr::Uac2VolumePositionToQ8(0.0, range);
        for (int step = 1; step <= 200; ++step) {
            const int16_t current =
                pulsr::Uac2VolumePositionToQ8(step / 200.0, range);
            if (current < previous) ok = false;
            previous = current;
        }
        Check(ok, "mapping is monotonic over the full int16 range");
        Check(pulsr::Uac2VolumePositionToQ8(0.0, range) == -32768,
              "full range: position 0 is -32768");
        Check(pulsr::Uac2VolumePositionToQ8(1.0, range) == 32767,
              "full range: position 1 is 32767");
    }

    // ---------------------------------------------------------------------
    // 10. UAC CS_MUTE control requests, payloads, and per-channel read-back.
    // ---------------------------------------------------------------------
    {
        Check(pulsr::kUacCsMute == 0x01, "kUacCsMute is 0x01");
        Check(pulsr::kUacCsVolume == 0x02, "kUacCsVolume is 0x02");

        // SET_CUR request for mute: bmRequestType = 0x21, bRequest = 0x01,
        // wValue = (CS_MUTE << 8) | channel, wIndex = (unitId << 8) | interfaceNumber, wLength = 1
        const auto setReq = pulsr::BuildUacMuteSetRequest(5, 1, 2);
        Check(setReq.bmRequestType == 0x21, "SET_CUR bmRequestType is 0x21");
        Check(setReq.bRequest == 0x01, "SET_CUR bRequest is 0x01");
        Check(setReq.wValue == ((0x01 << 8) | 2), "SET_CUR wValue has CS_MUTE in high byte, ch 2 in low");
        Check(setReq.wIndex == ((5 << 8) | 1), "SET_CUR wIndex has unitId 5 in high byte, iface 1 in low");
        Check(setReq.wLength == 1, "SET_CUR wLength is 1 byte");

        // GET_CUR request for mute in UAC2: bRequest = 0x81
        const auto getReqUac2 = pulsr::BuildUacMuteGetRequest(5, 1, 0, 2);
        Check(getReqUac2.bmRequestType == 0xA1, "GET_CUR bmRequestType is 0xA1");
        Check(getReqUac2.bRequest == 0x81, "UAC2 GET_CUR bRequest is 0x81");
        Check(getReqUac2.wValue == (0x01 << 8), "GET_CUR master channel wValue has ch 0 in low byte");
        Check(getReqUac2.wLength == 1, "GET_CUR wLength is 1 byte");

        // GET_CUR request for mute in UAC1: bRequest = 0x81
        const auto getReqUac1 = pulsr::BuildUacMuteGetRequest(5, 1, 1, 1);
        Check(getReqUac1.bRequest == 0x81, "UAC1 GET_CUR bRequest is 0x81");

        // Volume SET_CUR and GET_CUR shared builder
        const auto volSet = pulsr::BuildUacVolumeSetRequest(5, 1, 1);
        Check(volSet.bmRequestType == 0x21, "Volume SET_CUR bmRequestType is 0x21");
        Check(volSet.bRequest == 0x01, "Volume SET_CUR bRequest is 0x01");
        Check(volSet.wValue == ((0x02 << 8) | 1), "Volume SET_CUR wValue has CS_VOLUME in high byte");
        Check(volSet.wLength == 2, "Volume SET_CUR wLength is 2 bytes");

        const auto volGetUac2 = pulsr::BuildUacVolumeGetRequest(5, 1, 1, 2);
        Check(volGetUac2.bmRequestType == 0xA1, "Volume GET_CUR bmRequestType is 0xA1");
        Check(volGetUac2.bRequest == 0x81, "Volume UAC2 GET_CUR bRequest is 0x81");
        Check(volGetUac2.wValue == ((0x02 << 8) | 1), "Volume GET_CUR wValue has CS_VOLUME in high byte");
        Check(volGetUac2.wLength == 2, "Volume GET_CUR wLength is 2 bytes");

        // Payload encoding and decoding
        Check(pulsr::EncodeUacMutePayload(true) == 0x01, "mute true encodes to 0x01");
        Check(pulsr::EncodeUacMutePayload(false) == 0x00, "mute false encodes to 0x00");
        Check(pulsr::DecodeUacMutePayload(0x01) == true, "0x01 decodes to mute true");
        Check(pulsr::DecodeUacMutePayload(0xFF) == true, "non-zero decodes to mute true");
        Check(pulsr::DecodeUacMutePayload(0x00) == false, "0x00 decodes to mute false");

        // Per-channel read-back evaluation
        const uint8_t bothMuted[] = {0x01, 0x01};
        const uint8_t oneMuted[] = {0x01, 0x00};
        const uint8_t noneMuted[] = {0x00, 0x00};
        Check(pulsr::AllChannelsMuted(bothMuted, 2) == true, "all channels muted passes");
        Check(pulsr::AllChannelsMuted(oneMuted, 2) == false, "mismatched channel mute fails");
        Check(pulsr::AllChannelsMuted(noneMuted, 2) == false, "unmuted channels fail");
        Check(pulsr::AllChannelsMuted(nullptr, 2) == false, "null pointer fails");
        Check(pulsr::AllChannelsMuted(bothMuted, 0) == false, "zero channel count fails");
    }

    if (gFailures == 0) {
        std::cout << "[TEST] UAC2 volume codec: all checks passed." << std::endl;
        return 0;
    }
    std::cout << "[TEST] UAC2 volume codec: " << gFailures << " failure(s)." << std::endl;
    return 1;
}
