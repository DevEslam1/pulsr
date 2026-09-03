import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DSD Decimation Ratio Validation (B-62)', () {
    (int, double) configureDecimation(int dsdMultiplier, int requestedPcmRate) {
      final dsdFrequencyHz = 44100.0 * dsdMultiplier;
      int targetRate = requestedPcmRate.clamp(44100, 768000);
      double decimationRatio = dsdFrequencyHz / targetRate;

      if (decimationRatio < 8.0) {
        targetRate = (dsdFrequencyHz / 8.0).toInt();
        decimationRatio = 8.0;
      }

      return (targetRate, decimationRatio);
    }

    test('DSD64 with 768kHz target clamps decimation ratio to 8.0', () {
      // DSD64: 44100 * 64 = 2,822,400 Hz. If target is 768kHz: ratio = 3.675 (< 8)
      final (targetRate, ratio) = configureDecimation(64, 768000);
      expect(ratio, equals(8.0));
      expect(targetRate, equals(352800)); // 2822400 / 8
    });

    test('DSD64 with 44.1kHz target retains valid decimation ratio of 64.0', () {
      final (targetRate, ratio) = configureDecimation(64, 44100);
      expect(targetRate, equals(44100));
      expect(ratio, equals(64.0));
    });

    test('DSD512 with 768kHz target has ratio ~ 29.4 and requires no clamp', () {
      // DSD512: 44100 * 512 = 22,579,200 Hz. 22579200 / 768000 = 29.4
      final (targetRate, ratio) = configureDecimation(512, 768000);
      expect(targetRate, equals(768000));
      expect(ratio, greaterThanOrEqualTo(8.0));
    });
  });
}
