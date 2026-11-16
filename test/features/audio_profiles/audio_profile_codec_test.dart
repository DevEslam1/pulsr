// test/features/audio_profiles/audio_profile_codec_test.dart
//
// Codec contract tests: round-trip, format-version rejection, unknown-key
// tolerance and the value/size ceilings that keep a shared file bounded.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/audio_profiles/audio_profile.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_keys.dart';

Map<String, Object?> _baseJson({
  int version = 1,
  Map<String, Object?> values = const <String, Object?>{},
}) =>
    <String, Object?>{
      'formatVersion': version,
      'id': 'ap_test',
      'name': 'Test profile',
      'createdAt': '2026-01-02T03:04:05Z',
      'appVersion': '1.2.3',
      'values': values,
    };

void main() {
  group('AudioProfile codec', () {
    test('round-trips every supported value type', () {
      final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final profile = AudioProfile(
        id: 'ap_roundtrip',
        name: 'USB DAC',
        createdAt: createdAt,
        appVersion: '2.3.4',
        deviceVid: 0x1234,
        devicePid: 0x5678,
        deviceName: 'Topping E30',
        values: <String, Object?>{
          PrefsKeys.eqEnabled: true,
          PrefsKeys.eqBandCount: 10,
          PrefsKeys.eqPreamp: -3.5,
          PrefsKeys.eqPresetName: 'Harman',
          PrefsKeys.eqGains: <String>['1.0', '2.0', '-1.5'],
        },
      );

      final decoded = AudioProfile.decodeBytes(profile.encode());

      expect(decoded.formatVersion, 1);
      expect(decoded.id, 'ap_roundtrip');
      expect(decoded.name, 'USB DAC');
      expect(decoded.createdAt, createdAt);
      expect(decoded.appVersion, '2.3.4');
      expect(decoded.deviceVid, 0x1234);
      expect(decoded.devicePid, 0x5678);
      expect(decoded.deviceName, 'Topping E30');
      expect(decoded.values[PrefsKeys.eqEnabled], isTrue);
      expect(decoded.values[PrefsKeys.eqBandCount], 10);
      expect(decoded.values[PrefsKeys.eqPreamp], -3.5);
      expect(decoded.values[PrefsKeys.eqPresetName], 'Harman');
      expect(
        decoded.values[PrefsKeys.eqGains],
        <String>['1.0', '2.0', '-1.5'],
      );
    });

    test('rejects a newer format version with ProfileFormatError', () {
      expect(
        () => AudioProfile.fromJson(_baseJson(version: 2)),
        throwsA(
          isA<ProfileFormatError>().having(
            (error) => error.code,
            'code',
            'audio-profile-version-newer',
          ),
        ),
      );
    });

    test('rejects a missing, non-integer or non-positive version', () {
      final Map<String, Object?> missing = _baseJson()..remove('formatVersion');
      expect(
        () => AudioProfile.fromJson(missing),
        throwsA(isA<ProfileFormatError>()),
      );
      expect(
        () => AudioProfile.fromJson(_baseJson(version: 0)),
        throwsA(isA<ProfileFormatError>()),
      );
      final Map<String, Object?> textVersion = _baseJson()
        ..['formatVersion'] = '1';
      expect(
        () => AudioProfile.fromJson(textVersion),
        throwsA(isA<ProfileFormatError>()),
      );
    });

    test('ignores unknown top-level keys and drops non-whitelisted settings',
        () {
      final Map<String, Object?> json = _baseJson(
        values: <String, Object?>{
          PrefsKeys.eqEnabled: false,
          'future_setting': 7,
          'library_path': '/music',
        },
      )..['futureSection'] = <String, Object?>{'a': 1};

      final profile = AudioProfile.fromJson(json);

      expect(profile.values[PrefsKeys.eqEnabled], isFalse);
      expect(profile.values.containsKey('future_setting'), isFalse);
      expect(profile.values.containsKey('library_path'), isFalse);
      expect(
          profile.ignoredKeys,
          containsAll(<String>[
            'future_setting',
            'library_path',
          ]));
      expect(profile.toJson().containsKey('futureSection'), isFalse);
      expect(
        profile.values.keys.every(AudioProfileKeys.isWhitelisted),
        isTrue,
      );
    });

    test('drops corrupt settings instead of failing the import', () {
      final profile = AudioProfile.fromJson(
        _baseJson(
          values: <String, Object?>{
            PrefsKeys.eqEnabled: true,
            PrefsKeys.eqGains: <Object?>[1, 2],
            PrefsKeys.eqPreamp: <String, Object?>{'nested': true},
            PrefsKeys.eqBandCount: null,
          },
        ),
      );

      expect(profile.values[PrefsKeys.eqEnabled], isTrue);
      expect(profile.values.containsKey(PrefsKeys.eqGains), isFalse);
      expect(profile.values.containsKey(PrefsKeys.eqPreamp), isFalse);
      expect(profile.values.containsKey(PrefsKeys.eqBandCount), isFalse);
      expect(profile.ignoredKeys, contains(PrefsKeys.eqGains));
      expect(profile.ignoredKeys, contains(PrefsKeys.eqPreamp));
      expect(profile.ignoredKeys, contains(PrefsKeys.eqBandCount));
    });

    test('degrades corrupt optional metadata but keeps required fields', () {
      final Map<String, Object?> json = _baseJson(
        values: <String, Object?>{PrefsKeys.eqEnabled: true},
      )
        ..['appVersion'] = 42
        ..['deviceVid'] = 'not-a-number'
        ..['devicePid'] = -3
        ..['deviceName'] = <String, Object?>{'nested': true};

      final profile = AudioProfile.fromJson(json);

      expect(profile.appVersion, 'unknown');
      expect(profile.deviceVid, isNull);
      expect(profile.devicePid, isNull);
      expect(profile.deviceName, isNull);
      expect(profile.values[PrefsKeys.eqEnabled], isTrue);
    });

    test('exposes values as an unmodifiable map', () {
      final profile = AudioProfile.fromJson(
        _baseJson(
          values: <String, Object?>{PrefsKeys.eqEnabled: true},
        ),
      );
      expect(
        () => profile.values[PrefsKeys.eqEnabled] = false,
        throwsUnsupportedError,
      );
    });

    test('rejects more than 200 settings', () {
      final values = <String, Object?>{
        for (var i = 0; i < AudioProfile.maxValueCount + 1; i++) 'key_$i': i,
      };
      expect(
        () => AudioProfile.fromJson(_baseJson(values: values)),
        throwsA(
          isA<ProfileFormatError>().having(
            (error) => error.code,
            'code',
            'audio-profile-too-many-values',
          ),
        ),
      );
    });

    test('enforces the 512 KB ceiling before parsing', () {
      expect(
        () => AudioProfile.decodeBytes(
          Uint8List(AudioProfile.maxFileBytes + 1),
        ),
        throwsA(
          isA<ProfileFormatError>().having(
            (error) => error.code,
            'code',
            'audio-profile-too-large',
          ),
        ),
      );

      final padding = 'a' * (AudioProfile.maxFileBytes + 1);
      final oversized = '{"formatVersion":1,"id":"a","name":"b",'
          '"createdAt":"2026-01-02T03:04:05Z","values":{"k":"$padding"}}';
      expect(
        () => AudioProfile.decodeString(oversized),
        throwsA(
          isA<ProfileFormatError>().having(
            (error) => error.code,
            'code',
            'audio-profile-too-large',
          ),
        ),
      );
    });

    test('rejects malformed JSON and non-object payloads', () {
      expect(
        () => AudioProfile.decodeString('{not json'),
        throwsA(isA<ProfileFormatError>()),
      );
      expect(
        () => AudioProfile.decodeString('[1,2,3]'),
        throwsA(isA<ProfileFormatError>()),
      );
    });

    test('rejects an empty id or name', () {
      final Map<String, Object?> emptyName = _baseJson()..['name'] = '  ';
      expect(
        () => AudioProfile.fromJson(emptyName),
        throwsA(isA<ProfileFormatError>()),
      );
    });

    test('rejects an empty setting key', () {
      expect(
        () => AudioProfile.fromJson(
          _baseJson(values: <String, Object?>{'': 1}),
        ),
        throwsA(
          isA<ProfileFormatError>().having(
            (error) => error.code,
            'code',
            'audio-profile-empty-key',
          ),
        ),
      );
    });

    test('rejects an id that could escape the profile folder', () {
      for (final id in <String>['../escape', 'a/b', 'a\\b', 'x' * 81]) {
        final json = _baseJson()..['id'] = id;
        expect(
          () => AudioProfile.fromJson(json),
          throwsA(
            isA<ProfileFormatError>().having(
              (error) => error.code,
              'code',
              'audio-profile-id-invalid',
            ),
          ),
          reason: 'id "$id" must be rejected',
        );
      }
    });
  });

  group('AudioProfileKeys whitelist', () {
    test('is unique and covers the capture families', () {
      final keys = AudioProfileKeys.whitelist;
      expect(keys.toSet().length, keys.length);
      expect(keys.length, greaterThan(60));
      expect(keys, contains(PrefsKeys.eqEnabled));
      expect(keys, contains(PrefsKeys.crossfeedEnabled));
      expect(keys, contains(PrefsKeys.dsdOutputMode));
      expect(keys, contains(PrefsKeys.strictBitPerfect));
      expect(keys, contains(PrefsKeys.aaudioOutputEnabled));
      expect(keys, contains(PrefsKeys.usbHardwareVolumeEnabled));
      expect(keys, contains(PrefsKeys.dacVoicingEnabled));
    });

    test('excludes non-audio preferences', () {
      expect(
        AudioProfileKeys.isWhitelisted(PrefsKeys.ytdlpBackendEnabled),
        isFalse,
      );
      expect(
        AudioProfileKeys.isWhitelisted(PrefsKeys.ytdlpBackendUrl),
        isFalse,
      );
      expect(AudioProfileKeys.isWhitelisted('random_key'), isFalse);
    });
  });
}
