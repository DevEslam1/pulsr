// test/features/audio_profiles/audio_profile_service_test.dart
//
// Service contract tests: whitelist filtering, file round-trips, the automatic
// backup and the rollback that runs when a preference setter rejects a write.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/audio_profiles/audio_profile.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_keys.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fails one specific write so the rollback path can be exercised.
class _RejectingService extends AudioProfileService {
  _RejectingService({
    required super.prefs,
    required super.rootDirectory,
    required super.clock,
  });

  @override
  Future<bool> writeKeyValue(String key, Object? value) {
    if (key == PrefsKeys.dsdOutputMode && value == 'pcm') {
      return Future<bool>.value(false);
    }
    return super.writeKeyValue(key, value);
  }
}

void main() {
  late Directory root;
  late SharedPreferences prefs;
  var tick = 0;

  DateTime clock() =>
      DateTime.utc(2026, 1, 1, 12).add(Duration(minutes: tick++));

  AudioProfileService buildService({DateTime Function()? clockSource}) =>
      AudioProfileService(
        prefs: prefs,
        rootDirectory: () async => root,
        appVersion: () => '9.9.9',
        clock: clockSource ?? clock,
      );

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    root = await Directory.systemTemp.createTemp('pulsr_profile_service_');
    tick = 0;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('captureCurrent', () {
    test('keeps only whitelisted keys', () async {
      await prefs.setBool(PrefsKeys.eqEnabled, true);
      await prefs.setStringList(PrefsKeys.eqGains, <String>['1', '2']);
      await prefs.setString(PrefsKeys.dsdOutputMode, 'dop');
      await prefs.setBool(PrefsKeys.ytdlpBackendEnabled, true);
      await prefs.setString('library_path', '/storage/emulated/0/Music');

      final profile = await buildService()
          .captureCurrent('  Desk  ', deviceName: 'Topping E30');

      expect(profile.name, 'Desk');
      expect(profile.appVersion, '9.9.9');
      expect(profile.deviceName, 'Topping E30');
      expect(profile.values[PrefsKeys.eqEnabled], isTrue);
      expect(profile.values[PrefsKeys.eqGains], <String>['1', '2']);
      expect(profile.values[PrefsKeys.dsdOutputMode], 'dop');
      expect(
          profile.values.containsKey(PrefsKeys.ytdlpBackendEnabled), isFalse);
      expect(profile.values.containsKey('library_path'), isFalse);
      expect(
        profile.values.keys.every(AudioProfileKeys.isWhitelisted),
        isTrue,
      );
    });

    test('rejects a blank name', () async {
      await expectLater(
        buildService().captureCurrent('   '),
        throwsA(
          isA<AudioProfileStoreError>().having(
            (error) => error.code,
            'code',
            'audio-profile-name-empty',
          ),
        ),
      );
    });
  });

  group('list', () {
    test('returns the newest profile first', () async {
      final service = buildService();
      final first = await service.captureCurrent('First');
      final second = await service.captureCurrent('Second');

      final listed = await service.list();

      expect(
        listed.map((profile) => profile.id).toList(),
        <String>[second.id, first.id],
      );
    });

    test('skips an unreadable file instead of failing', () async {
      final service = buildService();
      await service.captureCurrent('Good');
      final directory =
          Directory(p.join(root.path, AudioProfileService.directoryName));
      await File(p.join(directory.path, 'broken.json')).writeAsString('{oops');

      final listed = await service.list();

      expect(listed.length, 1);
      expect(listed.single.name, 'Good');
    });
  });

  group('apply', () {
    test('writes whitelisted keys and reports skipped ones', () async {
      await prefs.setBool(PrefsKeys.eqEnabled, true);
      final service = buildService();
      final profile = AudioProfile(
        id: 'ap_apply',
        name: 'Apply me',
        createdAt: clock(),
        appVersion: '1.0.0',
        values: <String, Object?>{
          PrefsKeys.eqEnabled: false,
          'evil_key': 'nope',
        },
      );

      final report = await service.apply(profile);

      expect(prefs.getBool(PrefsKeys.eqEnabled), isFalse);
      expect(prefs.getString('evil_key'), isNull);
      expect(report.appliedCount, 1);
      expect(report.skippedKeys, <String>['evil_key']);
      expect(report.backupSaved, isTrue);
    });

    test('keeps a backup of the pre-apply values', () async {
      await prefs.setBool(PrefsKeys.eqEnabled, true);
      final service = buildService();
      await service.apply(
        AudioProfile(
          id: 'ap_backup',
          name: 'Backup',
          createdAt: clock(),
          appVersion: '1.0.0',
          values: <String, Object?>{PrefsKeys.eqEnabled: false},
        ),
      );

      final backupDirectory = Directory(
        p.join(
          root.path,
          AudioProfileService.directoryName,
          AudioProfileService.backupDirectoryName,
        ),
      );
      final backups = backupDirectory.listSync().whereType<File>().toList();

      expect(backups, isNotEmpty);
      final backup = AudioProfile.decodeString(
        await backups.first.readAsString(),
      );
      expect(backup.values[PrefsKeys.eqEnabled], isTrue);
    });

    test('rolls back every written key when one write is rejected', () async {
      await prefs.setBool(PrefsKeys.eqEnabled, true);
      await prefs.setString(PrefsKeys.dsdOutputMode, 'dop');
      final service = _RejectingService(
        prefs: prefs,
        rootDirectory: () async => root,
        clock: clock,
      );
      final profile = AudioProfile(
        id: 'ap_fail',
        name: 'Fails',
        createdAt: clock(),
        appVersion: '1.0.0',
        values: <String, Object?>{
          PrefsKeys.eqEnabled: false,
          PrefsKeys.dsdOutputMode: 'pcm',
        },
      );

      await expectLater(
        service.apply(profile),
        throwsA(
          isA<AudioProfileApplyError>()
              .having((error) => error.rolledBack, 'rolledBack', isTrue)
              .having(
                (error) => error.appliedKeys,
                'appliedKeys',
                contains(PrefsKeys.eqEnabled),
              ),
        ),
      );

      expect(prefs.getBool(PrefsKeys.eqEnabled), isTrue);
      expect(prefs.getString(PrefsKeys.dsdOutputMode), 'dop');
    });
  });

  group('files', () {
    test('export writes a decodable temporary json file', () async {
      final service = buildService();
      final profile = await service.captureCurrent('Share me');

      final file = await service.export(profile);

      expect(await file.exists(), isTrue);
      expect(file.path.toLowerCase().endsWith('.json'), isTrue);
      final decoded = AudioProfile.decodeString(await file.readAsString());
      expect(decoded.id, profile.id);
    });

    test('import re-keys a profile whose id is already stored', () async {
      final service = buildService();
      final profile = await service.captureCurrent('Exportable');
      final file = await service.export(profile);

      final imported = await service.importFromFile(file.path);

      expect(imported.id, isNot(profile.id));
      expect(imported.name, 'Exportable');
      expect((await service.list()).length, 2);
    });

    test('import rejects a corrupt file with a typed error', () async {
      final bad = File(p.join(root.path, 'bad.json'))
        ..writeAsStringSync('{nope');

      await expectLater(
        buildService().importFromFile(bad.path),
        throwsA(isA<ProfileFormatError>()),
      );
    });

    test('delete removes the file and rejects unsafe ids', () async {
      final service = buildService();
      final profile = await service.captureCurrent('Temporary');

      await service.delete(profile.id);

      expect(await service.list(), isEmpty);
      await expectLater(
        service.delete('../escape'),
        throwsA(isA<AudioProfileStoreError>()),
      );
    });
  });
}
