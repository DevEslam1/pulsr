import '../models/audio_output_info.dart';

/// How faithfully the current output route delivers the decoded signal.
enum OutputPathQuality {
  /// Unaltered stream to a USB DAC (Bit-Perfect active, DSP bypassed).
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
  static OutputPathVerdict of(AudioOutputInfo info, {bool dspActive = false}) {
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

    if (info.isUsbDac && info.isBitPerfectActive && !dspActive) {
      return OutputPathVerdict(
        OutputPathQuality.bitPerfect,
        'BIT-PERFECT',
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
