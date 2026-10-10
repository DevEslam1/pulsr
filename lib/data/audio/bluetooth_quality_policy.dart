// lib/data/audio/bluetooth_quality_policy.dart
//
// Pure, side-effect-free policy for "Bluetooth Hi-Res" playback.
//
// Bluetooth A2DP is a lossy codec link (SBC/AAC/aptX/LDAC/LC3), so this can
// never be bit-perfect. What it CAN do is stop the app from making the link
// worse than it needs to be:
//
//   * item 1 - keep the app's DSP/output path at float so the decoded 24/32-bit
//     samples are not truncated to 16-bit in-app before the codec encoder;
//   * item 3 - ask the codec for the track's native rate when the codec actually
//     advertises it, so the platform does not resample 44.1 kHz -> 48 kHz;
//   * item 4 - classify the active codec / LE Audio so the UI can recommend the
//     best available link instead of the default SBC;
//   * item 5 - permit the native TPDF dither stage to run on Bluetooth at the
//     codec's own bit depth (opt-in; off by default because a lossy codec
//     re-quantises downstream).
//
// Everything here is pure: no I/O, no platform calls, no player. The caller
// owns the side effects (pushFloatOutput, setDitherParams, setBluetoothSampleRate).

/// Quality class of the active Bluetooth codec. Purely advisory.
enum BluetoothCodecTier {
  /// Unknown / no codec reported.
  unknown,

  /// SBC - the always-available baseline.
  low,

  /// AAC / aptX - better than SBC, still 16-bit-class lossy.
  standard,

  /// LDAC / aptX HD / aptX Adaptive / LC3 - 24-bit-capable lossy.
  high,
}

/// How good the current Bluetooth link is, and what the app should do about it.
class BluetoothQualityPlan {
  /// Item 1: keep the float DSP path on so the app never truncates to 16-bit.
  final bool keepFloatPath;

  /// Item 5: allow the native TPDF dither stage to run on this BT route.
  final bool allowBluetoothDither;

  /// Item 5: target bit depth for the dither stage (16/24/32).
  final int ditherBitDepth;

  /// Item 3: the rate to ask the codec to switch to (null = leave it alone).
  final int? alignCodecSampleRateTo;

  /// Item 4: quality class of the active codec.
  final BluetoothCodecTier codecTier;

  /// Item 4: the route is LE Audio (LC3), which A2DP codec controls do not apply to.
  final bool isLeAudio;

  /// Item 4: this link is one of the 24-bit-capable high-quality codecs.
  bool get isHighQuality => codecTier == BluetoothCodecTier.high;

  /// Machine-readable reason (safe to log / persist).
  final String reason;

  const BluetoothQualityPlan({
    required this.keepFloatPath,
    required this.allowBluetoothDither,
    required this.ditherBitDepth,
    required this.alignCodecSampleRateTo,
    required this.codecTier,
    required this.isLeAudio,
    required this.reason,
  });

  @override
  String toString() => 'BluetoothQualityPlan(codecTier: ${codecTier.name}, '
      'leAudio: $isLeAudio, keepFloat: $keepFloatPath, '
      'btDither: $allowBluetoothDither@$ditherBitDepth, '
      'alignRate: $alignCodecSampleRateTo, reason: $reason)';
}

/// Classifies a codec name reported by the platform. Case/space/`-` insensitive.
BluetoothCodecTier bluetoothCodecTier(String? codecName) {
  final c = (codecName ?? '').toUpperCase().replaceAll('-', ' ').trim();
  if (c.isEmpty) return BluetoothCodecTier.unknown;
  if (c.contains('LDAC') ||
      c.contains('LC3PLUS') ||
      c.contains('LC3 PLUS') ||
      c.contains('APTX HD') ||
      c.contains('APTX ADAPTIVE') ||
      c.contains('APTX LOSSLESS')) {
    return BluetoothCodecTier.high;
  }
  // Bare LC3 is the LE Audio codec; A2DP codec controls do not apply.
  if (c == 'LC3') return BluetoothCodecTier.high;
  if (c.contains('APTX') || c.contains('AAC')) {
    return BluetoothCodecTier.standard;
  }
  if (c.contains('SBC')) return BluetoothCodecTier.low;
  return BluetoothCodecTier.standard;
}

/// Clamps a bit depth to the three values the native dither stage accepts.
int sanitizeDitherBitDepth(int? bits) =>
    (bits == 24 || bits == 32) ? bits! : 16;

/// Decides the Bluetooth Hi-Res plan. Pure: no I/O, no platform calls.
BluetoothQualityPlan resolveBluetoothQualityPlan({
  required bool bluetoothHiResEnabled,
  required bool ditherEnabled,
  required String? codecName,
  required int? codecSampleRateHz,
  required int? codecBitDepth,
  required bool isLeAudio,
  required int trackSampleRate,
  required int trackBitDepth,
  required List<int> codecSelectableSampleRates,
  required List<int> codecSelectableBitDepths,
}) {
  final tier = bluetoothCodecTier(codecName);
  final isLc3 = (codecName ?? '').toUpperCase().replaceAll('-', ' ').trim() ==
      'LC3';
  final leAudio = isLeAudio || isLc3;

  // Item 1: only the opt-in forces the float path; without it the historical
  // default is left untouched.
  final keepFloatPath = bluetoothHiResEnabled;

  // Item 5: dither is only permitted on BT when the user opted into Hi-Res AND
  // actually has the dither stage enabled. Never force dither on by itself.
  final allowBluetoothDither = bluetoothHiResEnabled && ditherEnabled;

  // Prefer the codec's own depth so the LSB scale matches the link; fall back to
  // the track depth when the codec reports nothing.
  final ditherBitDepth =
      sanitizeDitherBitDepth(codecBitDepth ?? trackBitDepth);

  // Item 3: only align when the user asked for Hi-Res, the track rate is known,
  // the codec advertises a *different* rate that it can actually switch to.
  int? alignRate;
  if (bluetoothHiResEnabled &&
      trackSampleRate > 0 &&
      codecSampleRateHz != null &&
      trackSampleRate != codecSampleRateHz &&
      codecSelectableSampleRates.contains(trackSampleRate)) {
    alignRate = trackSampleRate;
  }

  final reason = !bluetoothHiResEnabled
      ? 'bt-hires-off'
      : alignRate != null
          ? 'bt-hires-align-rate'
          : leAudio
              ? 'bt-hires-le-audio'
              : tier == BluetoothCodecTier.high
                  ? 'bt-hires-high-codec'
                  : 'bt-hires-lossy-codec';

  return BluetoothQualityPlan(
    keepFloatPath: keepFloatPath,
    allowBluetoothDither: allowBluetoothDither,
    ditherBitDepth: ditherBitDepth,
    alignCodecSampleRateTo: alignRate,
    codecTier: tier,
    isLeAudio: leAudio,
    reason: reason,
  );
}
