import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/ab_loop_manager.dart';
import 'package:pulsr/data/audio/track_delay_manager.dart';
import 'package:pulsr/data/audio/hedged_stream_resolver.dart';
import 'package:pulsr/data/audio/adaptive_quality_manager.dart';
import 'package:pulsr/core/services/bluetooth_latency_calibrator.dart';
import 'package:pulsr/data/audio/gapless_trim_handler.dart';
import 'package:pulsr/data/audio/ducking_controller.dart';
import 'package:pulsr/data/audio/dsp_snapshot_store.dart';
import 'package:pulsr/data/audio/silence_skip_controller.dart';
import 'package:pulsr/data/audio/playback_bookmark_store.dart';

void main() {
  group('F1 AB Loop', () {
    test('wraps past B back to A', () {
      final m = AbLoopManager();
      m.setA(const Duration(seconds: 10), songId: 1);
      m.setB(const Duration(seconds: 20), songId: 1);
      expect(m.isEnabled, isTrue);
      expect(m.wrapTarget(const Duration(seconds: 21), songId: 1),
          const Duration(seconds: 10));
      expect(m.wrapTarget(const Duration(seconds: 15), songId: 1), isNull);
    });
    test('invalidates on song change', () {
      final m = AbLoopManager();
      m.setA(const Duration(seconds: 5), songId: 1);
      m.setB(const Duration(seconds: 9), songId: 1);
      m.onSongChanged(2);
      expect(m.isEnabled, isFalse);
    });
  });

  group('F2 per-track delay', () {
    test('compensates position and clamps', () {
      final m = TrackDelayManager();
      m.setDelay('id:1', 500);
      expect(m.compensatedPosition('id:1', const Duration(seconds: 10)),
          const Duration(milliseconds: 9500));
      m.setDelay('id:1', 99999);
      expect(m.getDelayMs('id:1'), 2000);
      m.setDelay('id:1', 0);
      expect(m.getDelayMs('id:1'), 0);
    });
  });

  group('F3 hedged resolver', () {
    test('takes first success', () async {
      final v = await HedgedStreamResolver.race<String>([
        () async {
          await Future.delayed(const Duration(milliseconds: 100));
          return 'slow';
        },
        () async => 'fast',
      ], hedgeDelay: Duration.zero);
      expect(v, 'fast');
    });
    test('throws first error when all fail', () async {
      await expectLater(
        HedgedStreamResolver.race<String>([
          () async => throw StateError('a'),
          () async => throw StateError('b'),
        ], hedgeDelay: Duration.zero),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('F4 adaptive quality', () {
    test('steps down after underruns, up after healthy', () async {
      final mgr = AdaptiveQualityManager(
          currentQuality: 'high',
          onSwitchRequested: (_) async {},
          cooldown: Duration.zero);
      expect(await mgr.reportUnderrun(), isNull);
      expect(await mgr.reportUnderrun(), 'medium');
      mgr.setQuality('medium');
      for (var i = 0; i < 3; i++) {
        expect(await mgr.reportHealthy(), isNull);
      }
      expect(await mgr.reportHealthy(), 'high');
    });
    test('qualityRank ordering', () {
      expect(qualityRank('low') < qualityRank('high'), isTrue);
    });
  });

  group('F5 BT calibration', () {
    test('codec table estimates', () {
      expect(estimateBtLatencyForCodec('SBC'), 220);
      expect(estimateBtLatencyForCodec('LDAC'), 250);
      expect(estimateBtLatencyForCodec(null), 180);
    });
    test('calibrate combines codec + probe', () async {
      final c = BluetoothLatencyCalibrator();
      final r = await c.calibrate(
          codecName: 'SBC', probe: () async => 100, samples: 3);
      // 220*0.6 + 100*0.4 = 172
      expect(r.offsetMs, 172);
      expect(r.probeSamples, 3);
    });
  });

  group('F6 gapless trim', () {
    test('opus gets preskip, mp3/aac get codec trims (B3)', () {
      final opus = GaplessTrimHandler.trimFor(path: 'a.opus');
      expect(opus.preSkip, GaplessTrimHandler.opusPreSkip);
      // B3: MP3 now carries the LAME encoder delay/padding trim.
      final mp3 = GaplessTrimHandler.trimFor(path: 'a.mp3', codec: 'MP3');
      expect(mp3.preSkip, GaplessTrimHandler.mp3EncoderDelay);
      expect(mp3.postTrim, GaplessTrimHandler.mp3EncoderPadding);
      // AAC containers carry the iTunes priming pre-skip.
      final aac = GaplessTrimHandler.trimFor(path: 'a.m4a');
      expect(aac.preSkip, GaplessTrimHandler.aacEncoderDelay);
      // Lossless stays untouched.
      expect(GaplessTrimHandler.trimFor(path: 'a.flac').isEmpty, isTrue);
    });
    test('header overrides win and effective end trims tail', () {
      final t = GaplessTrimHandler.trimFor(
          path: 'a.ogg', preSkipOverrideMs: 100, postTrimOverrideMs: 200);
      expect(t.preSkip, const Duration(milliseconds: 100));
      expect(
          GaplessTrimHandler.effectiveEnd(
              const Duration(seconds: 10), t),
          const Duration(milliseconds: 9800));
    });
  });

  group('F7 ducking', () {
    test('duck factor math + modes', () {
      final d = DuckingController(mode: DuckingMode.duck, level: 0.3);
      expect(d.duckedVolume(1.0), closeTo(0.3, 1e-9));
      expect(d.shouldDuck, isTrue);
      d.setMode(DuckingMode.pause);
      expect(d.shouldPause, isTrue);
      d.setLevel(99);
      expect(d.level, 1.0);
    });
  });

  group('F9 DSP snapshots', () {
    test('album > artist > genre precedence', () {
      final s = DspSnapshotStore();
      final now = DateTime.now();
      s.save(DspSnapshotStore.genreKey('Rock'),
          DspSnapshot(presetName: 'G', gains: [1], savedAt: now));
      s.save(DspSnapshotStore.artistKey('A'),
          DspSnapshot(presetName: 'Ar', gains: [2], savedAt: now));
      s.save(DspSnapshotStore.albumKey('Al', 'A'),
          DspSnapshot(presetName: 'Al', gains: [3], savedAt: now));
      expect(
          s.recallFor(album: 'Al', artist: 'A', genre: 'Rock')!.presetName,
          'Al');
      expect(s.recallFor(artist: 'A', genre: 'Rock')!.presetName, 'Ar');
      expect(s.recallFor(genre: 'Rock')!.presetName, 'G');
    });
  });

  group('F10 silence skip', () {
    test('sensitivity mapping', () {
      final c = SilenceSkipController();
      c.setSensitivity(0);
      expect(c.enabled, isFalse);
      c.setSensitivity(100);
      expect(c.enabled, isTrue);
      expect(c.thresholdDb, closeTo(-20.0, 1e-9));
      expect(c.minSilenceDuration.inMilliseconds, 200);
      c.setSensitivity(1);
      expect(c.minSilenceDuration.inMilliseconds, greaterThan(1900));
    });
  });

  group('F11 bookmarks', () {
    test('long tracks bookmark, short do not qualify', () {
      expect(PlaybackBookmarkStore.shouldBookmark(durationMs: 20 * 60 * 1000),
          isTrue);
      expect(
          PlaybackBookmarkStore.shouldBookmark(
              durationMs: 180000, genre: 'Podcast'),
          isTrue);
      expect(
          PlaybackBookmarkStore.shouldBookmark(
              durationMs: 180000, genre: 'Pop'),
          isFalse);
    });
    test('save/recall/finish eviction', () {
      final s = PlaybackBookmarkStore();
      s.save('id:1', 60000, durationMs: 3600000);
      expect(s.recall('id:1')!.positionMs, 60000);
      s.save('id:1', 3590000, durationMs: 3600000);
      expect(s.recall('id:1'), isNull); // finished → evicted
      s.save('id:2', 1000, durationMs: 3600000);
      expect(s.recall('id:2'), isNull); // trivial head ignored
    });
  });
}
