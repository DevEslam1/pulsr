// lib/domain/models/bit_perfect_output_facts.dart
//
// The single assembler every surface uses to turn raw platform observations
// into the one [BitPerfectState].
//
// Before this file the same fold existed three times (live quality sheet,
// per-track session log, gain-gate builder) with small differences: one folded
// software gain into "samples modified", one never saw remapped channels, one
// never saw an unreadable gain. Duplicated truth drifts; a verdict must not
// depend on which screen asked.
//
// Domain-only: no Flutter, no I/O, no platform calls. Callers pass numbers and
// booleans exactly as the platform reported them; this file owns the rules for
// which observation wins and what it means.

import 'bit_perfect_chain.dart';
import 'bit_perfect_state.dart';

/// Raw observations of the live output chain.
///
/// Every field is a fact a caller can point at:
/// * [sinkSampleRate]/[sinkBitDepth] come from the Media3/AudioTrack routing
///   snapshot (the container the sink really opened, never a display value);
/// * [directStreamSampleRate]/[directStreamBitDepth] come from Pulsr's own
///   UAC2 isochronous sink when it owns the endpoint;
/// * [directRawPcmBitDepth] is the native sink's report of the last *delivered*
///   URB that carried raw integer PCM (0 when the last block went the float
///   path). Because the JNI tap only calls `WritePcm` after the engine observed
///   a bit-perfect block, a non-zero depth at or above the source depth is
///   direct evidence of an integer passthrough on the direct route.
class BitPerfectOutputFacts {
  /// The user's Bit-Perfect preference (or the platform reporting that the
  /// exclusive/direct request is live).
  final bool requested;

  /// The platform confirms an exclusive/direct sink is configured. Intent is
  /// not enough: a saved preference never sets this.
  final bool sinkActive;

  /// Pulsr's UAC2 isochronous sink currently owns the USB endpoint.
  final bool directUsbActive;

  /// The active route is a transcoded Bluetooth link, which can never be
  /// exclusive no matter what the sink reports.
  final bool bluetooth;

  final int sourceSampleRate;
  final int sourceBitDepth;

  /// Format the Media3 sink reported. Ignored when [directUsbActive] is true
  /// and when a float carrier collapsed the depth (see
  /// [floatCarrierDecodesSource]).
  final int sinkSampleRate;
  final int sinkBitDepth;

  /// Format Pulsr's own sink confirmed on the wire. Only meaningful while
  /// [directUsbActive] is true.
  final int directStreamSampleRate;
  final int directStreamBitDepth;

  /// Raw integer depth the direct sink last delivered (0 = float/non-raw).
  final int directRawPcmBitDepth;

  /// The Media3 sink carries the decoder grid in a float32 container. A float
  /// carrier is never treated as an integer bypass; on the direct route the
  /// carrier is upstream of the tee and is therefore irrelevant.
  final bool floatCarrierDecodesSource;

  /// The source's own representation is float (pcm_f32/64, 32-bit float WAV,
  /// ...). Float sources cannot be carried bit-exactly by integer DAC hardware,
  /// so they can never satisfy the integer-bypass fact even when the sink took
  /// an integer path for some other reason.
  final bool sourceFloat;

  /// The Media3 sink itself took the integer bit-perfect bypass
  /// (`PulsrAudioSink.integerBypassActiveForTelemetry`).
  final bool sinkIntegerBypass;

  /// Number of app-owned HAL effects enabled on the live session.
  final int halStagesActive;

  /// The OEM/system effect controller could not prove the vendor chain is
  /// bypassed. Published by AudioEffectsPlugin; unknown is not clean.
  final bool systemEffectsCompromised;

  /// The player's observed output gain. `null` means no readable gain, which
  /// is unknown - never unity, never attenuation.
  final double? softwareGain;

  /// A DSP stage (EQ, limiter, crossfeed, reverb, ...) is in the audible path.
  final bool dspProcessing;

  /// The transport itself edits the stream: speed/pitch != 1.0, silence skip,
  /// crossfade, sleep fade or ducking. Software gain does NOT belong here.
  final bool transportSamplesModified;

  /// The sink remapped channels (duplicated, silenced or dropped) at least once.
  final bool channelsAltered;

  /// The direct sink's clock/rate readback matched the requested format.
  final bool rateVerified;

  final bool isDsdDop;
  final bool isDsdNative;
  final bool sourceLossy;
  final bool sourceCodecUnconfirmed;

  /// The platform's own explanation when it refused the exclusive request.
  final String? failureReason;

  const BitPerfectOutputFacts({
    required this.requested,
    required this.sinkActive,
    required this.directUsbActive,
    this.bluetooth = false,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    this.sinkSampleRate = 0,
    this.sinkBitDepth = 0,
    this.directStreamSampleRate = 0,
    this.directStreamBitDepth = 0,
    this.directRawPcmBitDepth = 0,
    this.floatCarrierDecodesSource = false,
    this.sourceFloat = false,
    this.sinkIntegerBypass = false,
    this.halStagesActive = 0,
    this.systemEffectsCompromised = false,
    this.softwareGain,
    this.dspProcessing = false,
    this.transportSamplesModified = false,
    this.channelsAltered = false,
    this.rateVerified = true,
    this.isDsdDop = false,
    this.isDsdNative = false,
    this.sourceLossy = false,
    this.sourceCodecUnconfirmed = false,
    this.failureReason,
  });
}

/// Resolves the one fail-closed [BitPerfectState] from [facts].
///
/// Rules that used to live in each caller:
/// * the direct sink's confirmed wire format outranks the Media3 snapshot,
///   because the AudioTrack is a muted HAL feed while the UAC2 sink owns the
///   DAC. If the direct format is unknown, no format is invented;
/// * a float carrier contributes no integer container depth, so it can never
///   agree its way to `verified`;
/// * integer bypass is either the Media3 sink's observed bypass or the direct
///   sink's delivered raw-integer depth at or above the source depth;
/// * software gain is only ever a volume fact. It is never folded into
///   [BitPerfectOutputFacts.transportSamplesModified], so a lowered slider
///   reports `digital_volume_attenuation`, not "samples modified by DSP".
BitPerfectState resolveBitPerfectOutput(BitPerfectOutputFacts facts) {
  final direct = facts.directUsbActive;
  final floatCarrier = facts.floatCarrierDecodesSource && !direct;

  // A direct stream's true output format is the one the UAC2 sink negotiated.
  // Falling back to the Media3 values would describe a HAL feed nobody hears.
  // A float carrier keeps its measured rate (informative) but contributes no
  // integer container depth, so it can never agree its way to `verified`.
  final sinkSampleRate =
      direct ? facts.directStreamSampleRate : facts.sinkSampleRate;
  final sinkBitDepth = direct
      ? facts.directStreamBitDepth
      : (floatCarrier ? 0 : facts.sinkBitDepth);

  final gain = trustedSoftwareGain(facts.softwareGain);

  // The integer path and the clock readback are separate facts: raw integers
  // can be delivered while the rate is still unverified, and the assessment
  // must be able to say so instead of blaming a float carrier.
  final directRawBypass = direct &&
      (facts.isDsdNative ||
          (facts.sourceBitDepth > 0 &&
              facts.directRawPcmBitDepth >= facts.sourceBitDepth));
  // A sink bypass is only meaningful when the sink's container is at least as
  // wide as the source; otherwise the platform truncated ahead of the bypass.
  final sinkBypass = facts.sinkIntegerBypass &&
      facts.sourceBitDepth > 0 &&
      sinkBitDepth >= facts.sourceBitDepth;
  // A float source cannot be delivered bit-exactly to integer hardware, no
  // matter what the sink did with the buffer it received.
  final integerBypass = !facts.sourceFloat && (sinkBypass || directRawBypass);

  return resolveBitPerfectState(
    requested: facts.requested,
    sinkActive: facts.sinkActive,
    sourceSampleRate: facts.sourceSampleRate,
    sourceBitDepth: facts.sourceBitDepth,
    sinkSampleRate: sinkSampleRate,
    sinkBitDepth: sinkBitDepth,
    exclusive: facts.sinkActive && !facts.bluetooth,
    integerBypass: integerBypass,
    halClean: facts.halStagesActive <= 0,
    systemEffectsCompromised: facts.systemEffectsCompromised,
    unityGain: gain != null && (gain - 1.0).abs() <= 1e-9,
    softwareGainUnknown: gain == null,
    samplesModified: facts.dspProcessing || facts.transportSamplesModified,
    channelsAltered: facts.channelsAltered,
    isDsdDop: facts.isDsdDop,
    isDsdNative: facts.isDsdNative,
    sourceLossy: facts.sourceLossy,
    sourceCodecUnconfirmed: facts.sourceCodecUnconfirmed,
    rateVerified: facts.rateVerified,
    failureReason: facts.failureReason,
  );
}
