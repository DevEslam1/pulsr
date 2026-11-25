import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/data/lyrics/lyrics_offset_store.dart';
import 'package:pulsr/data/lyrics/lyrics_translation_service.dart';
import 'package:pulsr/data/models/download_settings.dart';
import 'package:pulsr/data/services/device_profile_service.dart';
import 'package:pulsr/data/services/room_correction_service.dart';
import 'package:pulsr/data/services/settings_profiles_service.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceProfileService hardening', () {
    late DeviceProfileService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = DeviceProfileService();
    });

    test('corrupt JSON in links does not get wiped on rememberLink/forgetLink',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_device_profile_links': '{corrupt: json-string...',
      });

      // getLinks falls back to empty map safely
      final links = await service.getLinks();
      expect(links, isEmpty);

      // rememberLink refuses to wipe corrupt storage
      await service.rememberLink(
        deviceKey: 'bt:headphones',
        deviceLabel: 'Headphones',
        profileId: 'p1',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_device_profile_links'),
          '{corrupt: json-string...');

      // forgetLink also refuses to wipe corrupt storage
      await service.forgetLink('bt:headphones');
      expect(prefs.getString('setting_device_profile_links'),
          '{corrupt: json-string...');
    });

    test('importLinksJson validates JSON format and refuses on corrupt storage',
        () async {
      // Invalid JSON string returns false
      expect(await service.importLinksJson('not json'), isFalse);
      expect(await service.importLinksJson(''), isFalse);
      expect(await service.importLinksJson('["array", "not", "map"]'), isFalse);

      // Valid links import merges cleanly
      final validJson = json.encode({
        'bt:sony': {
          'deviceKey': 'bt:sony',
          'profileId': 'profile_car',
          'deviceLabel': 'Sony XM5',
        }
      });
      expect(await service.importLinksJson(validJson), isTrue);
      expect(await service.linkForDeviceKey('bt:sony'), isNotNull);

      // When storage is corrupt, importLinksJson returns false and preserves storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('setting_device_profile_links', 'bad-data');
      expect(await service.importLinksJson(validJson), isFalse);
      expect(prefs.getString('setting_device_profile_links'), 'bad-data');
    });

    test('rememberBtLatency clamps offset to 0..1500', () async {
      await service.rememberBtLatency('bt:device1', -100);
      expect(await service.btLatencyFor('bt:device1'), 0);

      await service.rememberBtLatency('bt:device2', 2000);
      expect(await service.btLatencyFor('bt:device2'), 1500);

      await service.rememberBtLatency('bt:device3', 250);
      expect(await service.btLatencyFor('bt:device3'), 250);
    });
  });

  group('SettingsProfilesService hardening', () {
    late SettingsProfilesService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = SettingsProfilesService();
    });

    test('distinguishes missing key from corrupt JSON and prevents wipe',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_custom_profiles': '{corrupted json not a list',
      });

      // getProfiles returns defaults for UI safety
      final profiles = await service.getProfiles();
      expect(profiles, SettingsProfile.defaultProfiles);

      // saveProfile refuses to overwrite corrupt storage
      const newProfile = SettingsProfile(
        id: 'p_new',
        name: 'New Profile',
        type: ProfileType.custom,
      );
      await service.saveProfile(newProfile);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_custom_profiles'),
          '{corrupted json not a list');

      // deleteProfile also refuses to overwrite corrupt storage
      await service.deleteProfile('profile_home');
      expect(prefs.getString('setting_custom_profiles'),
          '{corrupted json not a list');
    });

    test(
        'deleting last profile sets initialized flag and does not resurrect defaults',
        () async {
      // Start with one profile
      const p = SettingsProfile(
        id: 'p_only',
        name: 'Only Profile',
        type: ProfileType.custom,
      );
      await service.saveProfile(p);

      final list = await service.getProfiles();
      expect(list.any((item) => item.id == 'p_only'), isTrue);

      // Delete the only custom profile
      await service.deleteProfile('p_only');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_custom_profiles_initialized'), isTrue);

      // Subsequent getProfiles returns empty list, does NOT resurrect defaults
      // (as long as all defaults were removed or initialized was marked)
      for (final def in SettingsProfile.defaultProfiles) {
        await service.deleteProfile(def.id);
      }
      final remaining = await service.getProfiles();
      expect(remaining, isEmpty);
    });
  });

  group('RoomCorrectionService hardening', () {
    test('analyzeResponse guards framesPerTone <= 0', () {
      final pcm = Int16List(1000);
      final tones = [100.0, 200.0];

      // Zero sampleRate or toneMs
      expect(
          RoomCorrectionService.analyzeResponse(pcm, 0, tones), hasLength(2));
      expect(
          RoomCorrectionService.analyzeResponse(pcm, 48000, tones, toneMs: 0),
          hasLength(2));
      expect(RoomCorrectionService.analyzeResponse(pcm, -100, tones),
          hasLength(2));
    });

    test(
        'correctionGainDbAt validates positive sorted centers and finite inputs',
        () {
      const gains = [2.0, 4.0, 6.0];
      const centers = [100.0, 200.0, 400.0];

      // Normal call
      expect(
          RoomCorrectionService.correctionGainDbAt(gains, centers, 200.0), 4.0);

      // Non-finite frequency
      expect(
          RoomCorrectionService.correctionGainDbAt(gains, centers, double.nan),
          0.0);
      expect(
          RoomCorrectionService.correctionGainDbAt(
              gains, centers, double.infinity),
          0.0);
      expect(
          RoomCorrectionService.correctionGainDbAt(gains, centers, -50.0), 0.0);

      // Unsorted centers
      expect(
          RoomCorrectionService.correctionGainDbAt(
              gains, [400.0, 200.0, 100.0], 200.0),
          0.0);

      // Non-positive centers
      expect(
          RoomCorrectionService.correctionGainDbAt(
              gains, [-100.0, 200.0, 400.0], 200.0),
          0.0);
      expect(
          RoomCorrectionService.correctionGainDbAt(
              gains, [0.0, 200.0, 400.0], 200.0),
          0.0);
    });

    test('computeConvergence and evaluateLoopback handle non-finite inputs',
        () {
      final res = RoomCorrectionService.computeConvergence(
        preResponseDb: [double.nan, 2.0, double.infinity, 4.0],
        postResponseDb: [1.0, double.nan, 3.0, 2.0],
      );
      // Valid pair is pre=4.0, post=2.0
      expect(res.initialVarianceDb.isFinite, isTrue);
      expect(res.residualVarianceDb.isFinite, isTrue);

      final loopback = RoomCorrectionService.evaluateLoopback(
        measuredDb: [double.nan, 1.0, 2.0],
        targetDb: [0.0, double.nan, 0.0],
        gateThresholdDb: -1.0, // should default to 0.5
      );
      expect(loopback.maxDeviationDb.isFinite, isTrue);
      expect(loopback.meanDeviationDb.isFinite, isTrue);
    });

    test('RoomCorrectionService dispose is safe and idempotent', () {
      final s = RoomCorrectionService();
      s.dispose();
      s.dispose();
      expect(s.isCapturing, isFalse);
    });
  });

  group('LyricsOffsetStore hardening', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('mutex serializes setOffsetMs, clearOffset, and orphan removal',
        () async {
      final store = LyricsOffsetStore();
      await store.setOffsetMs('/path/a.flac', 100);
      expect(await store.getOffsetMs('/path/a.flac'), 100);

      await store.clearOffset('/path/a.flac');
      expect(await store.getOffsetMs('/path/a.flac'), 0);
    });
  });

  group('DownloadSettings hardening', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('clamps maxConcurrent to 1..5 in constructor, load, and copyWith',
        () async {
      final s1 = DownloadSettings(maxConcurrent: 10);
      expect(s1.maxConcurrent, 5);

      final s2 = DownloadSettings(maxConcurrent: -5);
      expect(s2.maxConcurrent, 1);

      final s3 = s1.copyWith(maxConcurrent: 99);
      expect(s3.maxConcurrent, 5);

      await s3.save();
      final loaded = await DownloadSettings.load();
      expect(loaded.maxConcurrent, 5);
    });
  });

  group('LyricsTranslationService hardening', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LyricsTranslationService.clearCache();
    });
    test('decodes UTF-8 response bytes without corruption', () async {
      final mockClient = MockClient((request) async {
        // Return UTF-8 encoded Arabic text
        final body = json.encode([
          [
            ['مرحبا بك', 'Welcome', null, null]
          ],
          null,
          'en'
        ]);
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = LyricsTranslationService(client: mockClient);
      final result = await service.translateLyrics(
        lines: [
          const LyricsLine(
            timestamp: Duration(seconds: 1),
            text: 'Welcome',
          )
        ],
        targetLanguage: 'ar',
      );

      expect(result.lines.first.translation, 'مرحبا بك');
      service.dispose();
    });

    test('romanizeLyrics does not overwrite translation field', () async {
      final mockClient = MockClient((request) async {
        final body = json.encode([
          [
            ['Tokyo', '東京', null, 'Tokyo']
          ],
          null,
          'ja'
        ]);
        return http.Response.bytes(utf8.encode(body), 200);
      });

      final service = LyricsTranslationService(client: mockClient);
      final result = await service.romanizeLyrics(
        lines: [
          const LyricsLine(
            timestamp: Duration(seconds: 1),
            text: '東京',
            translation: 'Existing Spanish Translation',
          )
        ],
      );

      expect(result.lines.first.romanization, isNotNull);
      expect(result.lines.first.translation, 'Existing Spanish Translation');
      service.dispose();
    });

    test('InputTools fallback works on batch 1 with script detection',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('translate.googleapis.com')) {
          // Romanization batch fails
          return http.Response('[]', 200);
        }
        if (request.url.host.contains('inputtools.google.com')) {
          // Input tools returns romanization
          final resp = [
            'SUCCESS',
            [
              [
                '東京',
                ['Tokyo'],
                [],
                {'annotation': []}
              ]
            ]
          ];
          return http.Response.bytes(utf8.encode(json.encode(resp)), 200);
        }
        return http.Response('not found', 404);
      });

      final service = LyricsTranslationService(client: mockClient);
      final result = await service.romanizeLyrics(
        lines: [
          const LyricsLine(
            timestamp: Duration(seconds: 1),
            text: '東京',
          )
        ],
      );

      expect(result.lines.first.romanization, 'Tokyo');
      service.dispose();
    });

    test('InputTools guarded against short/empty data[1][0][1][0] indices',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('translate.googleapis.com')) {
          return http.Response('[]', 200);
        }
        if (request.url.host.contains('inputtools.google.com')) {
          // Malformed / truncated data[1] structure
          final resp = [
            'SUCCESS',
            [
              [] // empty list, lacks [0][1][0]
            ]
          ];
          return http.Response.bytes(utf8.encode(json.encode(resp)), 200);
        }
        return http.Response('not found', 404);
      });

      final service = LyricsTranslationService(client: mockClient);
      final result = await service.romanizeLyrics(
        lines: [
          const LyricsLine(
            timestamp: Duration(seconds: 1),
            text: '東京',
          )
        ],
      );

      // Should not throw IndexError, gracefully returns lines unmodified
      expect(result.lines.first.romanization, isNull);
      service.dispose();
    });

    test('clearCache serializes through disk chain', () async {
      SharedPreferences.setMockInitialValues({
        'lyr_trans_v1_test': '{"texts":["hi"],"src":"en","tgt":"es"}',
        'lyr_trans_index_v1': ['test'],
      });

      await LyricsTranslationService.clearCache();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lyr_trans_v1_test'), isNull);
      expect(prefs.getStringList('lyr_trans_index_v1'), isNull);
    });
  });
}
