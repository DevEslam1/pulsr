import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/bluetooth_latency_calibrator.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_quality_sheet.dart';

void main() {
  test('tap deltas yield reaction-compensated offset', () {
    final c = BluetoothLatencyCalibrator();
    // 6 taps ~430ms after beep -> trimmed mean 431 - 180 = 251ms.
    expect(
      c.offsetFromTapDeltas([428, 432, 431, 429, 433, 430]),
      251,
    );
  });

  test('tap outliers trimmed + empty falls back to default', () {
    final c = BluetoothLatencyCalibrator();
    // 2000ms trial ignored; min/max trimmed.
    final offset = c.offsetFromTapDeltas([100, 430, 431, 429, 433, 2000]);
    expect(offset, greaterThanOrEqualTo(0));
    expect(offset, lessThanOrEqualTo(500));
    expect(c.offsetFromTapDeltas([]), 180);
  });

  test('A2DP hides LE-only codecs, LE keeps all', () {
    const repo = ['SBC', 'AAC', 'aptX', 'LDAC', 'LC3', 'Opus'];
    final a2dp =
        visibleBtCodecsForRoute(repoCodecs: repo, isLeAudio: false);
    expect(a2dp, ['SBC', 'AAC', 'aptX', 'LDAC']);
    final le = visibleBtCodecsForRoute(repoCodecs: repo, isLeAudio: true);
    expect(le, repo);
  });
}
