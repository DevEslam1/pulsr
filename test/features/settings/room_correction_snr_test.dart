import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/settings/presentation/widgets/room_correction_sheet.dart';

void main() {
  group('M-19: RoomCorrectionSheet SNR calculation', () {
    test('calculateSnr returns 0.0 for empty PCM instead of misleading 20.0', () {
      final pcm = Int16List(0);
      expect(RoomCorrectionSheet.calculateSnr(pcm), equals(0.0));
    });

    test('calculateSnr returns 0.0 for PCM shorter than window size (1024)', () {
      final pcm = Int16List(500);
      for (int i = 0; i < pcm.length; i++) {
        pcm[i] = 1000;
      }
      expect(RoomCorrectionSheet.calculateSnr(pcm), equals(0.0));
    });

    test('calculateSnr returns 0.0 for pure silence (all zeros)', () {
      final pcm = Int16List(4096);
      expect(RoomCorrectionSheet.calculateSnr(pcm), equals(0.0));
    });

    test('calculateSnr correctly calculates positive SNR for valid signal with noise floor', () {
      // 2 windows: first window is quiet noise (~100 RMS), second window is loud signal (~10000 RMS)
      final pcm = Int16List(2048);
      // Window 1: low noise
      for (int i = 0; i < 1024; i++) {
        pcm[i] = 100;
      }
      // Window 2: loud signal (sine wave amplitude 15000)
      for (int i = 1024; i < 2048; i++) {
        pcm[i] = (15000 * math.sin(2 * math.pi * (i - 1024) / 32)).round();
      }

      final snr = RoomCorrectionSheet.calculateSnr(pcm);
      // Expected: 20 * log10(maxRms / minRms) > 30 dB
      expect(snr, greaterThan(30.0));
      expect(snr, lessThanOrEqualTo(50.0));
    });
  });
}
