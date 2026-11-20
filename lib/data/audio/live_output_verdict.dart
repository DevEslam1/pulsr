// lib/data/audio/live_output_verdict.dart
//
// The one place that turns live playback observations into a [BitPerfectState].
//
// `resolveBitPerfectOutput` already owns the rules (integer bypass, float
// carrier, gain, exclusive route...), but every caller still had to collect the
// same twelve facts by hand - and they drifted. The audio-quality sheet folded
// stereo balance, mono mix, dither, ReplayGain and DVC into "samples modified";
// the per-track session log folded only `dsp.isDspActive` and therefore wrote a
// verified bit-perfect session for a dithered, ReplayGain-scaled or DVC chain.
// Two screens describing one stream disagreed, which is exactly what the single
// assembler was meant to prevent.
//
// Callers now pass what they observed and this file decides what it means, so a
// new surface cannot forget a stage: the fold is behind one signature.

import '../../core/constants/audio_feature_info.dart';
import '../../domain/models/audio_output_info.dart';
import '../../domain/models/bit_perfect_output_facts.dart';
import '../../domain/models/bit_perfect_state.dart';
import 'bit_perfect_chain.dart';

/// Raw, unjudged observations of the live output chain.
///
/// Every value is something a caller can point at: the route snapshot, the
/// source tags, the user's preferences, and the transport/gain readings. The
/// booleans describing the DSP slice are kept separate (instead of one
/// "dspActive") so a caller cannot silently omit the stage it did not think of.
class LiveOutputObservation {
  /// The route snapshot. `null` means the platform has not reported a route.
  final AudioOutputInfo? output;

  /// Pulsr's own UAC2 isochronous sink currently owns the USB endpoint.
  final bool directStreamingActive;
  final int streamingSampleRate;
  final int streamingBitDepth;

  /// Raw integer depth the direct sink last delivered (0 = float/non-raw).
  final int rawPcmBitDepth;

  /// Frames the sink remapped (duplicated, silenced or dropped channels).
  final int channelMismatchFrames;

  /// The direct sink's clock/rate readback matched the requested format.
  final bool rateVerified;

  /// Source tags as the scanner read them; the decoder probe is folded in from
  /// [output] by [resolveLiveOutputVerdict].
  final int taggedSampleRate;
  final int taggedBitDepth;
  final String? codec;
  final String path;
  final bool isRadioSource;

  /// User preferences.
  final bool bitPerfectOutput;
  final bool strictBitPerfect;
  final bool bypassDspOnBitPerfect;

  /// Live processing facts. Each is a separate stage on purpose.
  final bool dspEffectsActive;
  final bool channelBalanceActive;
  final bool ditherActive;
  final bool replayGainActive;
  final bool dvcActive;
  final bool transportSamplesModified;

  /// Observed output gain. `null` means no readable gain (unknown, not unity).
  final double? softwareGain;

  final bool isDsdDop;
  final bool oversamplingActive;
  final bool pcmToDsdActive;

  const LiveOutputObservation({
    required this.output,
    required this.directStreamingActive,
    this.streamingSampleRate = 0,
    this.streamingBitDepth = 0,
    this.rawPcmBitDepth = 0,
    this.channelMismatchFrames = 0,
    this.rateVerified = true,
    required this.taggedSampleRate,
    required this.taggedBitDepth,
    this.codec,
    this.path = '',
    this.isRadioSource = false,
    required this.bitPerfectOutput,
    required this.strictBitPerfect,
    required this.bypassDspOnBitPerfect,
    this.dspEffectsActive = false,
    this.channelBalanceActive = false,
    this.ditherActive = false,
    this.replayGainActive = false,
    this.dvcActive = false,
    this.transportSamplesModified = false,
    this.softwareGain,
    this.isDsdDop = false,
    this.oversamplingActive = false,
    this.pcmToDsdActive = false,
  });
}

/// The verdict plus the resolved facts the callers also display.
///
/// The source rate/depth travel with the state so a caller cannot label the
/// chain with one source format while the verdict compared another.
class LiveOutputVerdict {
  final BitPerfectState state;
  final int sourceSampleRate;
  final int sourceBitDepth;
  final bool directUsbActive;
  final bool dspBypassed;
  final bool sourceLossy;
  final bool sourceCodecUnconfirmed;

  const LiveOutputVerdict({
    required this.state,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    required this.directUsbActive,
    required this.dspBypassed,
    required this.sourceLossy,
    required this.sourceCodecUnconfirmed,
  });

  bool get isBitPerfect => state.isVerified;
  bool get isDirectUsb => directUsbActive;
  bool get isLossy => sourceLossy;
}

typedef OutputVerdict = LiveOutputVerdict;

/// Folds [observation] into the single fail-closed [BitPerfectState].
LiveOutputVerdict resolveLiveOutputVerdict(LiveOutputObservation observation) {
  final output = observation.output;

  // Ownership is an observation, not a preference: neither the AAudio toggle
  // nor an attached DAC proves the endpoint belongs to us.
  final direct = observation.directStreamingActive &&
      output?.isUsbDac == true &&
      output?.isBluetooth != true;

  final sourceSampleRate = effectiveSourceSampleRate(
    tagged: observation.taggedSampleRate,
    decoded: output?.decodedSampleRate ?? 0,
  );
  final sourceBitDepth = effectiveSourceBitDepth(
    tagged: observation.taggedBitDepth,
    decoded: output?.decodedBitDepth ?? 0,
  );

  final codecState = AudioConflicts.classifySourceCodec(
    path: observation.path,
    codec: observation.codec,
  );
  final dspBypassed = observation.strictBitPerfect ||
      AudioConflicts.dspBypassActive(
        bitPerfectOutput: observation.bitPerfectOutput,
        bypassDspOnBitPerfect: observation.bypassDspOnBitPerfect,
        device: output,
      );

  // Any stage the engine can run belongs here: an enabled-but-bypassed EQ is
  // not a modified sample, but a dither, a balance trim or a DVC gain is.
  final stages = observation.dspEffectsActive ||
      observation.channelBalanceActive ||
      observation.ditherActive ||
      observation.replayGainActive ||
      observation.dvcActive;

  final facts = BitPerfectOutputFacts(
    requested: observation.bitPerfectOutput ||
        (output?.bitPerfectRequested ?? false),
    sinkActive: direct || output?.isBitPerfectActive == true,
    directUsbActive: direct,
    bluetooth: output?.isBluetooth == true,
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    sourceFloat: AudioConflicts.classifySourceSampleFormat(
          codec: observation.codec,
        ) ==
        AudioSourceSampleFormat.float,
    sinkSampleRate: output?.sinkSampleRate ?? 0,
    sinkBitDepth: output?.sinkBitDepth ?? 0,
    directStreamSampleRate: observation.streamingSampleRate,
    directStreamBitDepth: observation.streamingBitDepth,
    directRawPcmBitDepth: observation.rawPcmBitDepth,
    floatCarrierDecodesSource: output?.floatCarrierDecodesSource == true,
    sinkIntegerBypass: output?.integerBypassActive == true,
    halStagesActive: output?.halStagesActive ?? 0,
    systemEffectsCompromised: output?.systemEffectsCompromised == true,
    softwareGain: observation.softwareGain,
    dspProcessing: !dspBypassed && stages,
    transportSamplesModified: observation.transportSamplesModified,
    channelsAltered: direct && observation.channelMismatchFrames > 0,
    rateVerified: !direct || observation.rateVerified,
    isDsdDop: observation.isDsdDop,
    oversamplingActive: observation.oversamplingActive,
    pcmToDsdActive: observation.pcmToDsdActive,
    sourceLossy: observation.isRadioSource ||
        codecState == AudioSourceCodecState.lossy,
    sourceCodecUnconfirmed: codecState == AudioSourceCodecState.unknown,
    failureReason: output?.bitPerfectFailureReason,
  );

  return LiveOutputVerdict(
    state: resolveBitPerfectOutput(facts),
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    directUsbActive: direct,
    dspBypassed: dspBypassed,
    sourceLossy: facts.sourceLossy,
    sourceCodecUnconfirmed: facts.sourceCodecUnconfirmed,
  );
}
