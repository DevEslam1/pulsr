import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/services/room_correction_service.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

void main() {
  group('tonePlan', () {
    test('log-spaced, ascending, within range', () {
      final tones = RoomCorrectionService.tonePlan();
      expect(tones.length, RoomCorrectionService.defaultToneCount);
      expect(tones.first, greaterThanOrEqualTo(20.0));
      expect(tones.last, lessThanOrEqualTo(16000.0));
      for (var i = 1; i < tones.length; i++) {
        expect(tones[i], greaterThan(tones[i - 1]));
      }
    });
  });

  group('synthSweepWav', () {
    test('produces a valid mono 16-bit WAV of the right duration', () {
      final tones = RoomCorrectionService.tonePlan(count: 6);
      final wav = RoomCorrectionService.synthSweepWav(tones,
          sampleRate: 48000, toneMs: 200, amp: 0.35);
      expect(wav.length, greaterThan(44));
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final dataLen = ByteData.sublistView(wav).getUint32(40, Endian.little);
      expect(wav.length - 44, dataLen);
      expect(dataLen, 6 * (48000 * 200 ~/ 1000) * 2);
      // Non-silence signal present.
      final samples = Int16List.view(
          wav.buffer, wav.offsetInBytes + 44, dataLen ~/ 2);
      final peak = samples.fold<int>(0, (m, s) => math.max(m, s.abs()));
      expect(peak, greaterThan(1000));
    });
  });

  group('analyzeResponse + fitCorrection (end-to-end synthetic)', () {
    test('recovers an injected -6 dB dip and fits flattening correction',
        () async {
      final tones = RoomCorrectionService.tonePlan(count: 24);
      // Injected response: -6 dB at the 1 kHz region (index 8-10 of 24),
      // everything else at 0 dB relative.
      const dipIndex = 8;
      final devDb = List<double>.generate(24, (i) {
        if (i == dipIndex || i == dipIndex + 1) return -6.0;
        if (i == dipIndex - 1) return -3.0;
        return 0.0;
      });

      // Build the "recorded" PCM: play each tone at its deviated amplitude,
      // exactly as the room would attenuate it.
      const sampleRate = 48000;
      const toneMs = 350;
      const amp = 0.35;
      final framesPerTone = sampleRate * toneMs ~/ 1000;
      final pcm = Int16List(framesPerTone * tones.length);
      var w = 0;
      for (var i = 0; i < tones.length; i++) {
        final a = amp * math.pow(10.0, devDb[i] / 20.0);
        for (var j = 0; j < framesPerTone; j++) {
          final t = j / sampleRate;
          var env = 1.0;
          if (j < 100) env = j / 100;
          if (j > framesPerTone - 100) env = (framesPerTone - j) / 100;
          pcm[w++] =
              (math.sin(2 * math.pi * tones[i] * t) * a * env * 32767).round();
        }
      }

      final response =
          RoomCorrectionService.analyzeResponse(pcm, sampleRate, tones);
      expect(response.length, tones.length);
      // The dip region reads close to its injected deviation.
      expect(response[dipIndex], closeTo(-6.0, 1.0));
      expect(response[dipIndex + 1], closeTo(-6.0, 1.0));
      // Flat regions stay near 0 dB after normalization.
      expect(response[2], closeTo(0.0, 1.0));
      expect(response[20], closeTo(0.0, 1.0));

      final gains = RoomCorrectionService.fitCorrection(response, tones);
      expect(gains.length, EqPreset.centerFrequencies.length);
      // Every gain is clamped to the EQ range.
      for (final g in gains) {
        expect(g, inInclusiveRange(-15.0, 15.0));
      }
      // The band nearest the injected dip (~163 Hz region) gets positive
      // (boosting) correction, and adjacent-band smoothing keeps every gain
      // within 8 dB of its neighbor.
      final dipHz = tones[dipIndex];
      var nearestBand = 0;
      var nearestDist = double.infinity;
      for (var i = 0; i < EqPreset.centerFrequencies.length; i++) {
        final d =
            (math.log(EqPreset.centerFrequencies[i]) - math.log(dipHz)).abs();
        if (d < nearestDist) {
          nearestDist = d;
          nearestBand = i;
        }
      }
      expect(gains[nearestBand], greaterThan(2.0));
      for (var i = 1; i < gains.length; i++) {
        expect((gains[i] - gains[i - 1]).abs(), lessThanOrEqualTo(8.0 + 1e-9));
      }
    });

    test('a hot +6 dB peak gets negative (cutting) correction', () {
      final tones = RoomCorrectionService.tonePlan(count: 12);
      final response = List<double>.filled(12, 0.0);
      response[6] = 6.0;
      response[7] = 6.0;
      final gains = RoomCorrectionService.fitCorrection(response, tones,
          centers: tones);
      // Correction inverts: the peak bands get cuts.
      expect(gains[6], lessThan(-2.0));
      expect(gains[7], lessThan(-2.0));
    });
  });

  group('buildPreset', () {
    test('produces the Room Correction preset over 10 ISO bands', () {
      final preset =
          RoomCorrectionService.buildPreset([0, -1, 2, 0, 0, 0, 0, 0, 0, 1]);
      expect(preset.name, 'Room Correction');
      expect(preset.gains.length, EqPreset.centerFrequencies.length);
      expect(preset.bassBoost, 0.0);
    });
  });
}