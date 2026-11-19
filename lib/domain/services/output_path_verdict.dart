import '../models/audio_output_info.dart';
import '../models/bit_perfect_state.dart';

/// How faithfully the current output route delivers the decoded signal.
enum OutputPathQuality {
  /// Verified unaltered stream to an exclusive/USB sink. Only a verified
  /// [BitPerfectState] reaches this quality.
  bitPerfect,

  /// Digital path to a wired/USB sink with no lossy stage, but DSP and/or the
  /// system mixer may still alter samples.
  losslessProcessed,

  /// Bluetooth classic (A2DP) with a lossy codec in the chain.
  lossyBluetooth,

  /// LE Audio (LC3): lossy, platform-negotiated, not app-configurable.
  lossyLeAudio,

  /// Built-in speaker or an output we can't classify.
  deviceOutput,
}

/// A one-line verdict plus a short detail string for the signal path card.
class OutputPathVerdict {
  final OutputPathQuality quality;

  /// Short label, e.g. "BIT-PERFECT", "LOSSY · LDAC".
  final String label;

  /// Detail, e.g. "96 kHz / 24-bit · ~990 kbps (est.)".
  final String detail;

  const OutputPathVerdict(this.quality, this.label, this.detail);

  bool get isLossy =>
      quality == OutputPathQuality.lossyBluetooth ||
      quality == OutputPathQuality.lossyLeAudio;

  /// Derives the verdict from the live output [info].
  ///
  /// [dspActive] is whether any DSP stage currently alters the signal; it only
  /// matters for distinguishing [OutputPathQuality.bitPerfect] from
  /// [OutputPathQuality.losslessProcessed] on a wired route.
  ///
  /// [bitPerfectState] is the only evidence that can produce BIT-PERFECT: it
  /// is resolved from observed facts, while
  /// [AudioOutputInfo.isBitPerfectActive] only records what the app asked the
  /// platform to do. A verified state is authoritative and [dspActive] cannot
  /// override it, because the state already folded every DSP/HAL/gain fact —
  /// an enabled-but-bypassed EQ is not a modified sample. Without a state the
  /// old flag is still honoured as an exclusive hint, but it is labelled
  /// EXCLUSIVE rather than BIT-PERFECT because nothing verified that the
  /// samples survived the route.
  static OutputPathVerdict of(
    AudioOutputInfo info, {
    bool dspActive = false,
    BitPerfectState? bitPerfectState,
  }) {
    if (info.isLeAudio) {
      return const OutputPathVerdict(
        OutputPathQuality.lossyLeAudio,
        'LOSSY · LC3',
        'LE Audio — codec negotiated by the system',
      );
    }

    if (info.isBluetooth) {
      final codec = info.btCodecName;
      final parts = <String>[
        if (info.btSampleRateHz != null && info.btSampleRateHz! > 0)
          _khz(info.btSampleRateHz!),
        if (info.btBitDepth != null && info.btBitDepth! > 0)
          '${info.btBitDepth}-bit',
      ];
      final rate = parts.join(' / ');
      final kbps = info.btEstimatedBitrateKbps;
      final detail = [
        if (rate.isNotEmpty) rate,
        if (kbps != null) '~$kbps kbps (est.)',
      ].join(' · ');
      return OutputPathVerdict(
        OutputPathQuality.lossyBluetooth,
        codec == null || codec.isEmpty ? 'LOSSY · BT' : 'LOSSY · $codec',
        detail.isEmpty ? 'Bluetooth codec details unavailable' : detail,
      );
    }

    final format = info.sampleRate > 0 && info.bitDepth > 0
        ? '${_khz(info.sampleRate)} / ${info.bitDepth}-bit'
        : 'Format unknown';

    if (bitPerfectState?.isVerified == true) {
      return OutputPathVerdict(
        OutputPathQuality.bitPerfect,
        'BIT-PERFECT',
        format,
      );
    }

    // Exclusive USB output whose samples nothing has verified. The state knows
    // why it is not verified; the bare flag is only a request, so the strongest
    // honest label is EXCLUSIVE, never BIT-PERFECT.
    final exclusiveButUnverified = bitPerfectState != null
        ? bitPerfectState.tier != BitPerfectTier.off &&
            info.isUsbDac &&
            !info.isBluetooth &&
            !dspActive
        : info.isUsbDac &&
            info.isBitPerfectActive &&
            !info.isBluetooth &&
            !dspActive;
    if (exclusiveButUnverified) {
      return OutputPathVerdict(
        OutputPathQuality.losslessProcessed,
        'EXCLUSIVE',
        // The format only. Why the chain is not verified belongs to the
        // diagnostics screen, which has the localized wording; a machine code
        // appended here ("· rate_unknown") is not user-facing text.
        format,
      );
    }

    if (info.isUsbDac || info.activeDeviceType == 'wired') {
      return OutputPathVerdict(
        OutputPathQuality.losslessProcessed,
        'LOSSLESS · PROCESSED',
        format,
      );
    }

    return OutputPathVerdict(
      OutputPathQuality.deviceOutput,
      'DEVICE OUTPUT',
      format,
    );
  }


  static String _khz(int hz) {
    final k = hz / 1000.0;
    final text =
        k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return '$text kHz';
  }
}
