// lib/domain/models/audio_signal_path.dart
import 'audio_output_info.dart';
import 'bit_perfect_state.dart';

/// Real-time 4-stage "Audio Signal Path" diagnostic snapshot:
/// Source File Format -> Decoder Output -> Active Output Route -> Hardware Output Rate.
class AudioSignalPath {
  /// Stage 1: Source File Format.
  final String sourceCodec;
  final int sourceSampleRate;
  final int sourceBitDepth;
  final bool isDsdSource;
  final String sourceSummary;

  /// Stage 2: Decoder Output (unwrapped PCM / float / DoP stream).
  final int decoderSampleRate;
  final int decoderBitDepth;
  final int decoderPcmEncoding;
  final String decoderEncodingName;
  final String decoderSummary;

  /// Stage 3: Active Output Route (3.5mm Wired / USB DAC / Type-C / Bluetooth).
  final String routeCategory; // usb | wired | type_c | bluetooth | speaker
  final String routeLabel;
  final String deviceName;
  final String? bluetoothCodec;
  final int? bluetoothBitrateKbps;
  final List<String> deviceEncodings;
  final List<int> deviceChannelCounts;
  final String routeSummary;

  /// Stage 4: Final Hardware Output Rate & Driver Custody.
  final String driverPath;
  final int hardwareSampleRate;
  final int hardwareBitDepth;
  final int hardwareChannels;
  final bool isBitPerfect;
  final bool isDirectPath;
  final String statusTag;
  final String hardwareSummary;

  const AudioSignalPath({
    required this.sourceCodec,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    this.isDsdSource = false,
    required this.sourceSummary,
    required this.decoderSampleRate,
    required this.decoderBitDepth,
    required this.decoderPcmEncoding,
    required this.decoderEncodingName,
    required this.decoderSummary,
    required this.routeCategory,
    required this.routeLabel,
    required this.deviceName,
    this.bluetoothCodec,
    this.bluetoothBitrateKbps,
    this.deviceEncodings = const <String>[],
    this.deviceChannelCounts = const <int>[],
    required this.routeSummary,
    required this.driverPath,
    required this.hardwareSampleRate,
    required this.hardwareBitDepth,
    this.hardwareChannels = 2,
    required this.isBitPerfect,
    required this.isDirectPath,
    this.statusTag = '',
    required this.hardwareSummary,
  });

  /// Canonical single-line signal-path trace suitable for session logs & copyable diagnostics.
  String toChainString() =>
      '$sourceSummary -> $decoderSummary -> $routeSummary -> $hardwareSummary';

  static String formatRate(int hz) {
    if (hz <= 0) return 'Unknown rate';
    final khz = hz / 1000.0;
    return khz == khz.truncateToDouble()
        ? '${khz.toInt()} kHz'
        : '${khz.toStringAsFixed(1)} kHz';
  }

  /// Decodes Android `AudioFormat.ENCODING_PCM_*` integer constants into readable names.
  /// Falls back gracefully to inferring PCM bit depth from [fallbackBitDepth] (e.g. 'PCM 24-bit')
  /// when [encoding] is 0 (unprobed).
  static String pcmEncodingName(int encoding, [int fallbackBitDepth = 0]) => switch (encoding) {
        2 => 'PCM 16-bit',
        3 => 'PCM 8-bit',
        4 => 'PCM Float 32',
        21 => 'PCM 24-bit Packed',
        22 => 'PCM 32-bit',
        _ => encoding > 0
            ? 'PCM (enc $encoding)'
            : (fallbackBitDepth > 0 ? 'PCM $fallbackBitDepth-bit' : 'PCM Unprobed'),
      };

  /// Builds the four-stage trace from the live output facts.
  ///
  /// [bitPerfectState] is the only source of a Bit-Perfect claim. The
  /// [AudioOutputInfo.isBitPerfectActive] flag reports what the app asked the
  /// platform to do, not what the platform then did to the samples: it stays
  /// true when a HAL AudioEffect, a float re-quantisation or an OS resample
  /// sits in the chain, and the sink only ever reports the format it opened.
  /// A preference flag floating alone is therefore not evidence.
  ///
  /// Without a state this method fails closed: only a directly-exclusive UAC2
  /// route to a non-Bluetooth sink is counted as bit-perfect, and the flag is
  /// never trusted by itself. Callers that have a [BitPerfectState] hand it in
  /// and its [BitPerfectState.isVerified] decides.
  factory AudioSignalPath.fromOutputInfo({
    required String sourceCodec,
    required int sourceSampleRate,
    required int sourceBitDepth,
    bool isDsdSource = false,
    AudioOutputInfo? output,
    bool uac2DirectActive = false,
    bool aaudioEnabled = false,
    bool floatOutputEnabled = false,
    BitPerfectState? bitPerfectState,
    bool dspActive = false,
    bool dspProcessing = false,
    bool dspEffectsActive = false,
    String? dspDescription,
  }) {
    final normCodec = sourceCodec.trim().isEmpty ? 'Audio' : sourceCodec.trim();
    final srcRateLabel =
        sourceSampleRate > 0 ? formatRate(sourceSampleRate) : 'Native rate';
    final srcBitsLabel = sourceBitDepth > 0 ? '$sourceBitDepth-bit' : 'Auto';
    final srcSummary = isDsdSource
        ? 'DSD ($normCodec • $srcRateLabel)'
        : '$normCodec ($srcBitsLabel / $srcRateLabel)';

    final decRate = output?.decodedSampleRate ?? 0;
    final decDepth = output?.decodedBitDepth ?? 0;
    final decEnc = output?.decodedPcmEncoding ?? 0;
    final effectiveDecRate = decRate > 0 ? decRate : sourceSampleRate;
    final effectiveDecDepth = decDepth > 0 ? decDepth : sourceBitDepth;
    final fallbackDepth =
        effectiveDecDepth > 0 ? effectiveDecDepth : sourceBitDepth;
    final decEncName = pcmEncodingName(decEnc, fallbackDepth);
    final decSummary = effectiveDecRate > 0 && effectiveDecDepth > 0
        ? '$decEncName ($effectiveDecDepth-bit / ${formatRate(effectiveDecRate)})'
        : (effectiveDecRate > 0
            ? '$decEncName (${formatRate(effectiveDecRate)})'
            : decEncName);

    final devName = output?.deviceName ?? 'System Output';
    final isBt = output?.isBt ?? false;
    final isUsb = output?.isUsb ?? false;
    final isWired = output?.isHeadphones ?? false;
    final hasTypeCHint = isUsb &&
        (devName.toLowerCase().contains('type-c') ||
            devName.toLowerCase().contains('usb-c') ||
            (output?.usbAudioClass ?? 0) == 0);

    final String routeCat;
    final String routeTitle;
    if (isBt) {
      routeCat = 'bluetooth';
      final codec = output?.btCodecName;
      final kbps = output?.btEstimatedBitrateKbps;
      routeTitle = codec != null && codec.isNotEmpty
          ? (kbps != null
              ? 'Bluetooth ($codec • $kbps kbps)'
              : 'Bluetooth ($codec)')
          : 'Bluetooth Audio';
    } else if (isUsb) {
      routeCat = hasTypeCHint && !uac2DirectActive && (output?.usbAudioClass ?? 0) == 0
          ? 'type_c'
          : 'usb';
      final uac = switch (output?.usbAudioClass ?? 0) {
        1 => 'UAC1',
        2 => 'UAC2',
        3 => 'UAC3',
        _ => 'USB Audio',
      };
      routeTitle =
          routeCat == 'type_c' ? 'USB-C Digital ($uac)' : 'USB-C DAC ($uac)';
    } else if (isWired) {
      routeCat = 'wired';
      routeTitle = '3.5mm Wired DAC';
    } else {
      routeCat = 'speaker';
      routeTitle = 'Internal Speaker';
    }

    final routeText = '$routeTitle • $devName';

    final hwRate = (isBt ? (output?.btSampleRateHz ?? output?.sampleRate) : output?.sampleRate) ?? 0;
    final hwDepth = (isBt ? (output?.btBitDepth ?? output?.bitDepth) : output?.bitDepth) ?? 0;
    final isDspEngaged = dspActive ||
        dspProcessing ||
        dspEffectsActive ||
        (dspDescription != null && dspDescription.trim().isNotEmpty) ||
        (bitPerfectState?.reasonCode == 'samples_modified');

    // Only a verified state is evidence. However, if DSP processing is
    // engaged, samples are altered in the DSP pipeline (EQ, Limiter, etc.),
    // so the claim must never be Bit-Perfect.
    final bitPerfect = !isDspEngaged && (bitPerfectState?.isVerified ?? false);
    final direct = output?.isDirectSupported == true || aaudioEnabled || uac2DirectActive;

    final String driver;
    if (uac2DirectActive) {
      driver = 'Pulsr UAC2 Isochronous';
    } else if (bitPerfect && isUsb) {
      driver = 'USB Exclusive Mixer';
    } else if (aaudioEnabled) {
      driver = 'AAudio Direct';
    } else if (floatOutputEnabled || isDspEngaged) {
      driver = 'Media3 Float DSP';
    } else {
      driver = 'Media3 AudioTrack';
    }

    final hwRateText = hwRate > 0 ? formatRate(hwRate) : 'Unverified rate';
    final hwDepthText = hwDepth > 0 ? '$hwDepth-bit' : 'Unknown depth';
    // Only a verified state may say Bit-Perfect. When a state exists and is
    // not verified, the honest tag is that the route is exclusive at best -
    // and `armed` is not exclusive at all: the platform never confirmed a sink,
    // so it is intent only and must not borrow the exclusive wording.
    // When DSP processing is engaged, the hardware summary / status tag
    // reflects DSP activity (e.g. '32-bit Float DSP (EQ Active)' or 'DSP Active').
    final tier = bitPerfectState?.tier;
    final String statusTag;
    if (isDspEngaged) {
      final desc = dspDescription?.trim();
      if (desc != null && desc.isNotEmpty) {
        if (desc == 'DSP Active' ||
            desc == '32-bit Float DSP (EQ Active)' ||
            desc.toLowerCase().contains('float dsp')) {
          statusTag = desc;
        } else {
          final clean = desc.replaceAll(RegExp(r'\s+Active$', caseSensitive: false), '').trim();
          statusTag = '32-bit Float DSP ($clean Active)';
        }
      } else {
        statusTag = 'DSP Active';
      }
    } else if (bitPerfect) {
      statusTag = 'Bit-Perfect';
    } else if (isBt) {
      statusTag = 'Lossy A2DP/LE';
    } else if (tier == BitPerfectTier.armed) {
      statusTag = 'Arming';
    } else if (tier != null && tier != BitPerfectTier.off) {
      statusTag = 'Exclusive / Unverified';
    } else {
      statusTag = direct ? 'Direct PCM' : 'OS Mixer';
    }
    final hwText = '$driver • $hwDepthText / $hwRateText ($statusTag)';

    return AudioSignalPath(
      sourceCodec: normCodec,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      isDsdSource: isDsdSource,
      sourceSummary: srcSummary,
      decoderSampleRate: effectiveDecRate,
      decoderBitDepth: effectiveDecDepth,
      decoderPcmEncoding: decEnc,
      decoderEncodingName: decEncName,
      decoderSummary: decSummary,
      routeCategory: routeCat,
      routeLabel: routeTitle,
      deviceName: devName,
      bluetoothCodec: output?.btCodecName,
      bluetoothBitrateKbps: output?.btEstimatedBitrateKbps,
      deviceEncodings: output?.supportedEncodings ?? const <String>[],
      deviceChannelCounts: output?.supportedChannelCounts ?? const <int>[],
      routeSummary: routeText,
      driverPath: driver,
      hardwareSampleRate: hwRate,
      hardwareBitDepth: hwDepth,
      hardwareChannels: output?.effectiveOutputChannels != null &&
              output!.effectiveOutputChannels > 0
          ? output.effectiveOutputChannels
          : (output?.decodedChannelCount ?? 2),
      isBitPerfect: bitPerfect,
      isDirectPath: direct,
      statusTag: statusTag,
      hardwareSummary: hwText,
    );
  }
}
