// F5: Bluetooth latency auto-calibration (codec table + round-trip probe).
import 'dart:math' as math;

/// Estimated downstream buffering latency per Bluetooth codec (ms).
/// Values are conservative mid-range figures from AOSP codec docs.
const Map<String, int> kBtCodecLatencyMs = {
  'sbc': 220,
  'aac': 200,
  'aptx': 150,
  'aptx_hd': 200,
  'aptx_adaptive': 120,
  'ldac': 250,
  'lc3': 60,
  'opus': 100,
  'lhdc': 180,
  'default': 180,
};

int estimateBtLatencyForCodec(String? codecName) {
  if (codecName == null || codecName.isEmpty) return kBtCodecLatencyMs['default']!;
  final key = codecName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  // Match the most specific alias first: 'aptxhd'/'aptxadaptive' must win over
  // the generic 'aptx' entry, which would otherwise always match first.
  final candidates = kBtCodecLatencyMs.keys
      .where((k) => k != 'default')
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final candidate in candidates) {
    if (key.contains(candidate.replaceAll('_', ''))) {
      return kBtCodecLatencyMs[candidate]!;
    }
  }
  return kBtCodecLatencyMs['default']!;
}

/// Result of an auto-calibration run.
class BtCalibrationResult {
  final int offsetMs;
  final String codec;
  final int probeSamples;
  final double jitterMs;
  const BtCalibrationResult({
    required this.offsetMs,
    required this.codec,
    required this.probeSamples,
    required this.jitterMs,
  });
}

typedef BtProbeFn = Future<int> Function();

/// Runs a small round-trip probe (AVRCP/play-position delta samples) and
/// combines it with the codec estimate: result = clamp(codecEst*0.6 + probe*0.4).
class BluetoothLatencyCalibrator {
  final int minMs;
  final int maxMs;

  BluetoothLatencyCalibrator({this.minMs = 0, this.maxMs = 500});

  int clampOffset(int ms) => ms.clamp(minMs, maxMs);

  /// Interactive tap test: user taps when they HEAR each beep. [tapDeltasMs]
  /// holds tapTime - beepEmitTime per trial (includes ~180ms human reaction).
  /// Returns a clamped offset with the reaction baseline removed.
  int offsetFromTapDeltas(List<int> tapDeltasMs,
      {int reactionBaselineMs = 180}) {
    final valid =
        tapDeltasMs.where((d) => d >= 0 && d <= 1500).toList()..sort();
    if (valid.isEmpty) return estimateBtLatencyForCodec(null);
    final trimmed =
        valid.length >= 4 ? valid.sublist(1, valid.length - 1) : valid;
    final mean = (trimmed.reduce((a, b) => a + b) / trimmed.length).round();
    return clampOffset(mean - reactionBaselineMs);
  }

  Future<BtCalibrationResult> calibrate({    String? codecName,
    BtProbeFn? probe,
    int samples = 5,
  }) async {
    final codec = (codecName ?? 'default').toLowerCase();
    final codecEst = estimateBtLatencyForCodec(codecName);
    var probeAvg = codecEst;
    var jitter = 0.0;
    var taken = 0;
    if (probe != null) {
      final vals = <int>[];
      for (var i = 0; i < samples; i++) {
        try {
          final v = await probe();
          if (v >= 0 && v <= 1000) {
            vals.add(v);
            taken++;
          }
        } catch (_) {}
      }
      if (vals.isNotEmpty) {
        vals.sort();
        // Trimmed mean: drop min/max when we have enough samples.
        final trimmed = vals.length >= 4 ? vals.sublist(1, vals.length - 1) : vals;
        probeAvg = (trimmed.reduce((a, b) => a + b) / trimmed.length).round();
        final mean = probeAvg.toDouble();
        final variance = trimmed
                .map((v) => (v - mean) * (v - mean))
                .reduce((a, b) => a + b) /
            trimmed.length;
        jitter = math.sqrt(variance);
      }
    }
    final combined = (codecEst * 0.6 + probeAvg * 0.4).round();
    return BtCalibrationResult(
      offsetMs: clampOffset(combined),
      codec: codec,
      probeSamples: taken,
      jitterMs: jitter,
    );
  }
}
