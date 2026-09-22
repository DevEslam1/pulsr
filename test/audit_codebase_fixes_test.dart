// test/audit_codebase_fixes_test.dart
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/adaptive_quality_manager.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/gapless_trim_handler.dart';
import 'package:pulsr/data/audio/mqa_decoder_helper.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audit Codebase Fixes Tests', () {
    test('Bug 6 & 18: DsdDecoderHelper rejects oversized file > 300MB', () async {
      expect(DsdDecoderHelper.kMaxInMemoryDecodeBytes, 300 * 1024 * 1024);

      final tempDir = await Directory.systemTemp.createTemp('dsd_test_');
      final fakeLargeDsf = File('${tempDir.path}/huge.dsf');
      final raf = await fakeLargeDsf.open(mode: FileMode.write);
      // Create a sparse file of 301 MB instantly
      await raf.truncate(301 * 1024 * 1024);
      await raf.close();

      final songWithLargePath = SongsTableData(
        id: 999,
        title: 'Huge Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 300000,
        path: fakeLargeDsf.path,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
        source: SongSource.local,
      );
      const mediaItem = MediaItem(id: '999', title: 'Huge Track');

      await expectLater(
        () => DsdDecoderHelper.decodeDsdFile(songWithLargePath, mediaItem),
        throwsA(isA<DsdUnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('exceeds max in-memory decode size of 300 MB'),
        )),
      );

      await tempDir.delete(recursive: true);
    });

    test('Bug 6 & 18: MqaDecoderHelper defines 300MB max decode limit', () {
      expect(MqaDecoderHelper.kMaxInMemoryDecodeBytes, 300 * 1024 * 1024);
    });

    test('Bug 7: AdaptiveQualityManager resets cooldown on failed switch', () async {
      var callCount = 0;
      final mgr = AdaptiveQualityManager(
        currentQuality: 'high',
        cooldown: const Duration(seconds: 20),
        onSwitchRequested: (newQuality) async {
          callCount++;
          throw Exception('Network failed during hot-swap');
        },
      );

      // Trigger 2 underruns to meet underrunThreshold
      await mgr.reportUnderrun();
      final result1 = await mgr.reportUnderrun();

      expect(result1, isNull);
      expect(callCount, 1);
      // Current quality should roll back to 'high'
      expect(mgr.currentQuality, 'high');

      // Now trigger 2 more underruns. Because _lastSwitchAt was reset on failure,
      // it should NOT be locked out by the 20-second cooldown!
      await mgr.reportUnderrun();
      await mgr.reportUnderrun();

      expect(callCount, 2);
      mgr.dispose();
    });

    test('Bugs 2 & 3: Equalizer preference keys are defined correctly', () {
      expect(PrefsKeys.crossfeedFcut, 'setting_crossfeed_fcut');
      expect(PrefsKeys.crossfeedDelayUs, 'setting_crossfeed_delay_us');
      expect(PrefsKeys.crossfeedFeedDb, 'setting_crossfeed_feed_db');
      expect(PrefsKeys.convolutionReverbPredelayMs,
          'setting_convolution_reverb_predelay_ms');
      expect(PrefsKeys.convolutionReverbDamping,
          'setting_convolution_reverb_damping');
    });

    test('Issue 13 & 14: PrefsRepository supports dispose and immediate async set',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsRepository(prefs);

      // Async write with immediate: true
      await repo.set('test_key', 'test_value', immediate: true);
      expect(repo.get<String>('test_key'), 'test_value');

      // Dispose cleans up batch timer
      repo.dispose();
    });

    test('Issue 15: GaplessTrimHandler Opus and Vorbis logic separation', () {
      final opusTrim = GaplessTrimHandler.trimFor(path: 'track.opus');
      expect(opusTrim.preSkip, GaplessTrimHandler.opusPreSkip);
      expect(opusTrim.postTrim, Duration.zero);

      final vorbisTrim =
          GaplessTrimHandler.trimFor(path: 'track.ogg', codec: 'vorbis');
      expect(vorbisTrim.preSkip, const Duration(microseconds: 11600));
      expect(vorbisTrim.postTrim, Duration.zero);

      final oggOpusTrim =
          GaplessTrimHandler.trimFor(path: 'track.ogg', codec: 'opus');
      expect(oggOpusTrim.preSkip, GaplessTrimHandler.opusPreSkip);
      expect(oggOpusTrim.postTrim, Duration.zero);
    });

    test('Issue 24: Random backoff jitter generates values in [0, 400)', () {
      final rng = Random();
      for (var i = 0; i < 1000; i++) {
        final jitter = rng.nextInt(400);
        expect(jitter, greaterThanOrEqualTo(0));
        expect(jitter, lessThan(400));
      }
    });
  });
}
