// lib/data/audio/dsd_transport_resolver.dart
//
// Single decision point for how a DSD (DSF/DFF) track reaches the output.
//
// The user selects one of three transports (PCM decode, DoP, Native DSD). The
// selection is a *preference*, never a promise: DoP needs a bit-perfect
// pipeline (DSP volume math would corrupt the 0x05/0xFA markers) and a carrier
// rate, and Native DSD needs a DAC that advertises raw DSD alt settings. The
// resolver therefore returns the transport that will actually be used plus a
// machine-readable reason, and the fallback chain is explicit:
//
//   native  ->  DoP  ->  PCM
//
// Keeping this pure (no channels, no prefs, no platform checks) makes the
// entire matrix testable without an Android device attached.

/// The transport actually used for a DSD track.
enum DsdTransport {
  /// Decode DSD to PCM in native code and play it as ordinary PCM.
  pcm,

  /// Frame DSD as DSD-over-PCM (v1.1 markers) inside a PCM container.
  dop,

  /// Send the raw DSD bitstream and let the DAC decode it.
  native,
}

/// Why a transport was chosen; surfaced in diagnostics and used by tests.
enum DsdTransportReason {
  /// The selected transport is usable.
  selected,

  /// The user asked for PCM.
  userPcm,

  /// DoP/Native require the DSP chain to be bypassed (bit-perfect).
  requiresBitPerfect,

  /// The connected DAC does not advertise native DSD alt settings.
  deviceLacksNativeDsd,

  /// The connected DAC does not advertise a usable DoP carrier.
  deviceLacksDop,

  /// Above DSD256 there is no standard DoP carrier, so DoP cannot carry it.
  noDopCarrierAtRate,

  /// Unknown/zero DSD rate: decode to PCM rather than guess a carrier.
  unknownDsdRate,
}

/// The resolved plan for one track.
class DsdTransportPlan {
  final DsdTransport transport;
  final DsdTransportReason reason;

  /// The transport the user asked for (before capability gating).
  final DsdTransport requested;

  const DsdTransportPlan({
    required this.transport,
    required this.reason,
    required this.requested,
  });

  bool get isNative => transport == DsdTransport.native;
  bool get isDop => transport == DsdTransport.dop;

  /// True when the plan differs from the request, i.e. a fallback happened.
  bool get isFallback => transport != requested;

  @override
  String toString() => 'DsdTransportPlan(requested: ${requested.name}, '
      'transport: ${transport.name}, reason: ${reason.name})';
}

/// Maximum DoP rate multiple that has a standard carrier (DSD256 over 705.6 kHz
/// PCM in a 24-bit frame). Higher rates are native-only.
const int kMaxDopRateMultiple = 256;

/// Resolves the transport for a DSD track.
///
/// [mode] is the persisted `PrefsKeys.dsdOutputMode` value (`'pcm'`, `'dop'`
/// or `'native'`); an unknown value is treated as PCM. [bitPerfectActive] is
/// true only when the DSP chain is bypassed for this track (strict bit-perfect,
/// or bit-perfect with DSP bypass). [dopCapable] and [nativeCapable] come from
/// the native probe (`DsdDacCapabilities.canUseDop` / `.canUseNativeDsd`).
/// [dsdRateMultiple] is 64/128/256/512 (0 when the header could not be read).
DsdTransportPlan resolveDsdTransport({
  required String mode,
  required bool bitPerfectActive,
  required bool dopCapable,
  required bool nativeCapable,
  required int dsdRateMultiple,
}) {
  final requested = switch (mode) {
    'native' => DsdTransport.native,
    'dop' => DsdTransport.dop,
    _ => DsdTransport.pcm,
  };

  if (requested == DsdTransport.pcm) {
    return const DsdTransportPlan(
      transport: DsdTransport.pcm,
      reason: DsdTransportReason.userPcm,
      requested: DsdTransport.pcm,
    );
  }

  if (!bitPerfectActive) {
    return planFallback(
      requested: requested,
      reason: DsdTransportReason.requiresBitPerfect,
      dopCapable: dopCapable,
      dsdRateMultiple: dsdRateMultiple,
      bitPerfectActive: false,
    );
  }

  if (dsdRateMultiple <= 0) {
    return DsdTransportPlan(
      transport: DsdTransport.pcm,
      reason: DsdTransportReason.unknownDsdRate,
      requested: requested,
    );
  }

  if (requested == DsdTransport.native) {
    if (nativeCapable) {
      return DsdTransportPlan(
        transport: DsdTransport.native,
        reason: DsdTransportReason.selected,
        requested: requested,
      );
    }
    return planFallback(
      requested: requested,
      reason: DsdTransportReason.deviceLacksNativeDsd,
      dopCapable: dopCapable,
      dsdRateMultiple: dsdRateMultiple,
      bitPerfectActive: true,
    );
  }

  // requested == dop
  if (dsdRateMultiple > kMaxDopRateMultiple) {
    return DsdTransportPlan(
      transport: DsdTransport.pcm,
      reason: DsdTransportReason.noDopCarrierAtRate,
      requested: requested,
    );
  }
  if (!dopCapable) {
    return DsdTransportPlan(
      transport: DsdTransport.pcm,
      reason: DsdTransportReason.deviceLacksDop,
      requested: requested,
    );
  }
  return DsdTransportPlan(
    transport: DsdTransport.dop,
    reason: DsdTransportReason.selected,
    requested: requested,
  );
}

/// Builds the fallback plan for a request that cannot be honoured as asked.
///
/// The chain is fixed: Native DSD degrades to DoP (when the pipeline is
/// bit-perfect, the rate has a carrier and the DAC advertises one), and any
/// other request degrades to PCM. A DoP request never upgrades to Native: the
/// user did not ask for it, and native framing is the riskier path on unknown
/// hardware.
///
/// [bitPerfectActive] is enforced here, not just by the caller: DoP framing
/// embeds 0x05/0xFA markers that DSP volume/gain math corrupts, so a fallback
/// produced for a non-bit-perfect pipeline must always land on PCM.
DsdTransportPlan planFallback({
  required DsdTransport requested,
  required DsdTransportReason reason,
  required bool dopCapable,
  required int dsdRateMultiple,
  required bool bitPerfectActive,
}) {
  final dopUsable = bitPerfectActive &&
      dopCapable &&
      dsdRateMultiple > 0 &&
      dsdRateMultiple <= kMaxDopRateMultiple;
  if (requested == DsdTransport.native && dopUsable) {
    return DsdTransportPlan(
      transport: DsdTransport.dop,
      reason: reason,
      requested: requested,
    );
  }
  return DsdTransportPlan(
    transport: DsdTransport.pcm,
    reason: reason,
    requested: requested,
  );
}
