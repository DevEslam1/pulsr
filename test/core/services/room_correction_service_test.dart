import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/room_correction_service.dart';
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
      final samples =
          Int16List.view(wav.buffer, wav.offsetInBytes + 44, dataLen ~/ 2);
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
      final gains =
          RoomCorrectionService.fitCorrection(response, tones, centers: tones);
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

  group('computeSafePreamp', () {
    test('returns a negative preamp bounded by the max boost', () {
      final preamp = RoomCorrectionService.computeSafePreamp(
          [0.0, 3, -2, 6, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
      expect(preamp, lessThan(0));
      // -(6 + 0.5) = -6.5
      expect(preamp, closeTo(-6.5, 0.001));
    });

    test('returns zero for a curve with no boost', () {
      expect(
          RoomCorrectionService.computeSafePreamp([0.0, -1.0, -2.0, 0.0]), 0.0);
    });

    test('bounds a max-boost curve to the headroom needed', () {
      final gains = [15.0, 12.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final preset = RoomCorrectionService.buildPreset(gains);
      final preamp = RoomCorrectionService.computeSafePreamp(preset.gains);
      expect(preamp, lessThanOrEqualTo(0.0));
      // -(15 + 0.5) = -15.5 would exceed the EQ preamp floor, so the value is
      // clamped to -15.0 — the headroom that is actually applied.
      expect(preamp, closeTo(-15.0, 0.001));
    });
  });

  group('predictCorrectedResponse + correctionGainDbAt', () {
    test('interpolates the applied curve and predicts a flattened response',
        () {
      final tones = RoomCorrectionService.tonePlan(count: 12);
      final pre = [
        ...List<double>.filled(5, 0.0),
        -6.0,
        -6.0,
        ...List<double>.filled(5, 0.0),
      ];
      final gains = RoomCorrectionService.fitCorrection(pre, tones);
      final post = RoomCorrectionService.predictCorrectedResponse(
        preResponseDb: pre,
        tones: tones,
        gains: gains,
      );
      expect(post.length, pre.length);
      final preRms =
          math.sqrt(pre.map((v) => v * v).reduce((a, b) => a + b) / pre.length);
      final postRms = math
          .sqrt(post.map((v) => v * v).reduce((a, b) => a + b) / post.length);
      expect(postRms, lessThan(preRms));
    });

    test('correctionGainDbAt holds the edge gain outside the center range', () {
      const gains = [4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final centers = EqPreset.centerFrequencies;
      expect(RoomCorrectionService.correctionGainDbAt(gains, centers, 1.0),
          closeTo(4.0, 1e-9));
      expect(RoomCorrectionService.correctionGainDbAt(gains, centers, 1e6),
          closeTo(0.0, 1e-9));
    });
  });

  group('fitCorrection sanitization', () {
    test('drops a non-finite response without shifting later pairs', () {
      final tones = RoomCorrectionService.tonePlan(count: 12);
      final response = List<double>.filled(12, 0.0);
      response[3] = double.nan;
      response[8] = -6.0;
      final centers = List<double>.from(tones);
      final gains = RoomCorrectionService.fitCorrection(response, tones,
          centers: centers);
      expect(gains.length, centers.length);
      expect(gains[8], greaterThan(2.0));
      for (final g in gains) {
        expect(g.isFinite, isTrue);
      }
    });
  });

  group('exportCorrectionImpulseResponse (FIR design)', () {
    double magnitudeAt(Float32List ir, double freq) {
      var re = 0.0;
      var im = 0.0;
      for (var i = 0; i < ir.length; i++) {
        final a =
            2 * math.pi * freq * i / RoomCorrectionService.captureSampleRate;
        re += ir[i] * math.cos(a);
        im -= ir[i] * math.sin(a);
      }
      return math.sqrt(re * re + im * im);
    }

    test('a mid-band boost is reproduced by the FIR magnitude response', () {
      final centers = EqPreset.centerFrequencies;
      final gains = List<double>.filled(centers.length, 0.0);
      gains[4] = 12.0; // +12 dB around 500 Hz
      final ir = RoomCorrectionService.exportCorrectionImpulseResponse(
        gains,
        centers: centers,
        taps: 127,
      );
      final gainDb = 20 * math.log(magnitudeAt(ir, centers[4])) / math.ln10;
      expect(gainDb, greaterThan(6.0));
    });

    test('a low-band boost is not flattened away by DC normalization', () {
      final centers = EqPreset.centerFrequencies;
      final gains = List<double>.filled(centers.length, 0.0);
      gains[0] = 12.0; // +12 dB on the lowest band
      final ir = RoomCorrectionService.exportCorrectionImpulseResponse(
        gains,
        centers: centers,
        taps: 127,
      );
      // The short window limits low-frequency accuracy, but the bass correction
      // must survive (previously it was normalized to exactly 0 dB).
      final dcGainDb = 20 * math.log(magnitudeAt(ir, 0.0)) / math.ln10;
      expect(dcGainDb, greaterThan(1.0));
    });

    test('a flat curve still yields a transparent near-unity DC gain', () {
      final gains = List<double>.filled(EqPreset.centerFrequencies.length, 0.0);
      final ir = RoomCorrectionService.exportCorrectionImpulseResponse(gains);
      var sum = 0.0;
      for (final v in ir) {
        sum += v;
      }
      expect(sum, closeTo(1.0, 0.05));
    });
  });

  group('computeConvergence (Pillar 2)', () {
    test('measures convergence score and variance reduction', () {
      final pre = [6.0, 5.0, -4.0, 3.0, -5.0, 4.0];
      final post = [0.8, 0.5, -0.6, 0.4, -0.5, 0.3];
      final res = RoomCorrectionService.computeConvergence(
        preResponseDb: pre,
        postResponseDb: post,
      );
      expect(res.converged, isTrue);
      expect(res.score, greaterThan(80.0));
      expect(res.residualVarianceDb, lessThan(res.initialVarianceDb));
      expect(res.maxResidualDeltaDb, lessThanOrEqualTo(0.8));
    });
  });

  group('evaluateLoopback (Pillar 1)', () {
    test('evaluates loopback within gate threshold of +/- 0.5 dB', () {
      final measured = [0.2, -0.3, 0.1, 0.4, -0.2, 0.3];
      final target = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final res = RoomCorrectionService.evaluateLoopback(
        measuredDb: measured,
        targetDb: target,
        gateThresholdDb: 0.5,
      );
      expect(res.isWithinGate, isTrue);
      expect(res.maxDeviationDb, lessThanOrEqualTo(0.5));
      expect(res.meanDeviationDb, lessThan(0.5));
    });

    test('fails gate when deviation exceeds threshold', () {
      final measured = [1.2, -0.3, 0.1, 0.4, -0.2, 0.3];
      final target = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final res = RoomCorrectionService.evaluateLoopback(
        measuredDb: measured,
        targetDb: target,
        gateThresholdDb: 0.5,
      );
      expect(res.isWithinGate, isFalse);
      expect(res.maxDeviationDb, greaterThan(0.5));
    });
  });

  group('verify (closed loop)', () {
    test('passes when the post response converges and sits within the gate',
        () {
      final pre = [6.0, 5.0, -4.0, 3.0, -5.0, 4.0];
      final post = [0.2, 0.1, -0.2, 0.15, -0.1, 0.2];
      final v = RoomCorrectionService.verify(
        preResponseDb: pre,
        postResponseDb: post,
      );
      expect(v.convergence.converged, isTrue);
      expect(v.loopback.isWithinGate, isTrue);
      expect(v.passed, isTrue);
      expect(v.convergence.score, greaterThan(80.0));
    });

    test('fails when the post response is still uneven', () {
      final pre = [6.0, 5.0, -4.0, 3.0, -5.0, 4.0];
      final post = [5.0, 4.5, -3.5, 2.8, -4.2, 3.6];
      final v = RoomCorrectionService.verify(
        preResponseDb: pre,
        postResponseDb: post,
      );
      expect(v.convergence.converged, isFalse);
      expect(v.passed, isFalse);
    });

    test('is safe on empty input', () {
      final v = RoomCorrectionService.verify(
        preResponseDb: const [],
        postResponseDb: const [],
      );
      expect(v.passed, isFalse);
      expect(v.convergence.score, 0.0);
    });
  });
}
