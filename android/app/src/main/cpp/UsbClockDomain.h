// android/app/src/main/cpp/UsbClockDomain.h
//
// Public clock-domain vocabulary shared by the USB Audio Class transport and
// the Kotlin/Dart telemetry surfaces.
//
// The three live domains describe what the USB path is actually doing to the
// bitstream, not what the user asked for:
//
//   BitPerfectLocked - the DAC's async feedback endpoint (or a verified
//                      nominal-rate path with no feedback) is followed by
//                      adjusting packet cadence only. Frame payloads are
//                      handed through untouched.
//   Asrc             - the sink clock cannot be tracked by cadence alone
//                      (+/-0.5% beyond the packet-sizing range), so the
//                      polyphase sinc in UsbAsrcClockSync resamples. Samples
//                      are no longer bit-exact; the domain says so.
//   BestEffort       - either no feedback is available and the producer clock
//                      is free-running, or a fallback path is in use. Dropouts
//                      are absorbed by the ring, not by the clock.
//
// Status is a plain value type: it is copied across a JNI boundary and into
// Dart, so it must stay trivially copyable and hold no pointers.
#ifndef PULSR_USB_CLOCK_DOMAIN_H_
#define PULSR_USB_CLOCK_DOMAIN_H_

#include <cstdint>

namespace pulsr {

enum class UsbClockDomain : int32_t {
    Unknown = 0,
    BitPerfectLocked = 1,
    Asrc = 2,
    BestEffort = 3,
};

struct UsbClockStatus {
    UsbClockDomain domain = UsbClockDomain::Unknown;
    // Signed producer-minus-sink rate error, parts per million. Positive means
    // the producer clock is running fast relative to the DAC.
    int clockDriftPpm = 0;
    // Round-trip ring occupancy in milliseconds, as last reported by the sink.
    int ringFillMs = 0;
    // True when the DAC exposed an asynchronous feedback endpoint and the sink
    // decoded at least one plausible sample from it.
    bool feedbackPresent = false;
    uint64_t underrunCount = 0;
    uint64_t overrunCount = 0;
};

// Stable wire names. These strings are consumed by Kotlin/Dart telemetry, so
// they are part of the contract and must not be renamed or localized.
inline const char* UsbClockDomainName(UsbClockDomain domain) {
    switch (domain) {
        case UsbClockDomain::BitPerfectLocked: return "bitPerfectLocked";
        case UsbClockDomain::Asrc: return "asrc";
        case UsbClockDomain::BestEffort: return "bestEffort";
        case UsbClockDomain::Unknown: break;
    }
    return "unknown";
}

// Keeps status structs cheap to copy and safe to memcpy across the JNI
// boundary; a future field that needs a destructor would break that contract.
static_assert(sizeof(UsbClockStatus) <= 32,
              "UsbClockStatus must stay a compact value type for JNI transport");

}  // namespace pulsr

#endif  // PULSR_USB_CLOCK_DOMAIN_H_
