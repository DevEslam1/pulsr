// test/features/audio_profiles/audio_profile_service_test.dart
//
// Service contract tests: whitelist filtering, file round-trips, the automatic
// backup and the rollback that runs when a preference setter rejects a write.

import 'dart:convert';
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
    super.reloadSettings,
    super.resyncEffects,
  });

  @override
  Future<bool> writeKeyValue(String key, Object? value) {
    if (key == PrefsKeys.dsdOutputMode && value == 'pcm') {
      return Future<bool>.value(false);
    }
    return super.writeKeyValue(key, value);
  }
}

class _LiveStateProbe {
  int reloads = 0;
  int resyncs = 0;

  Future<void> reload() async => reloads++;

  Future<void> resync() async => resyncs++;
}

void main() {
  late Directory root;
  late SharedPreferences prefs;
  var tick = 0;

  DateTime clock() =>
      DateTime.utc(2026, 1, 1, 12).add(Duration(minutes: tick++));

  AudioProfileService buildService({
    DateTime Function()? clockSource,
    Future<void> Function()? reloadSettings,
    Future<void> Function()? resyncEffects,
  }) =>
      AudioProfileService(
        prefs: prefs,
        rootDirectory: () async => root,
        appVersion: () => '9.9.9',
        clock: clockSource ?? clock,
        reloadSettings: reloadSettings,
        resyncEffects: resyncEffects,
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
      expect(
        report.statusOf(PrefsKeys.eqEnabled),
        AudioProfileApplyStatus.applied,
      );
      expect(report.statusOf('evil_key'), AudioProfileApplyStatus.skipped);
    });

    test('refreshes settings and effects after a successful apply', () async {
      final probe = _LiveStateProbe();
      final service = buildService(
        reloadSettings: probe.reload,
        resyncEffects: probe.resync,
      );
      final report = await service.apply(
        AudioProfile(
          id: 'ap_live',
          name: 'Live',
          createdAt: clock(),
          appVersion: '1.0.0',
          values: <String, Object?>{PrefsKeys.eqEnabled: true},
        ),
      );

      expect(probe.reloads, 1);
      expect(probe.resyncs, 1);
      expect(report.liveStateRefreshed, isTrue);
    });

    test('refreshes effects before reloading settings on live state update',
        () async {
      final order = <String>[];
      final service = buildService(
        resyncEffects: () async => order.add('resync'),
        reloadSettings: () async => order.add('reload'),
      );

      await service.apply(
        AudioProfile(
          id: 'ap_order',
          name: 'Order',
          createdAt: clock(),
          appVersion: '1.0.0',
          values: <String, Object?>{PrefsKeys.eqEnabled: true},
        ),
      );

      expect(order, <String>['resync', 'reload']);
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
      final probe = _LiveStateProbe();
      final service = _RejectingService(
        prefs: prefs,
        rootDirectory: () async => root,
        clock: clock,
        reloadSettings: probe.reload,
        resyncEffects: probe.resync,
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
              )
              .having(
                (error) => error.failedKeys,
                'failedKeys',
                <String>[PrefsKeys.dsdOutputMode],
              )
              .having(
                (error) => error.statusOf(PrefsKeys.eqEnabled),
                'eqEnabled status',
                AudioProfileApplyStatus.applied,
              )
              .having(
                (error) => error.statusOf(PrefsKeys.dsdOutputMode),
                'dsdOutputMode status',
                AudioProfileApplyStatus.failed,
              ),
        ),
      );

      expect(prefs.getBool(PrefsKeys.eqEnabled), isTrue);
      expect(prefs.getString(PrefsKeys.dsdOutputMode), 'dop');
      // The rolled-back values must also be pushed to the live state.
      expect(probe.reloads, 1);
      expect(probe.resyncs, 1);
    });

    test('reports a per-key failure for a single rejected write', () async {
      await prefs.setString(PrefsKeys.dsdOutputMode, 'dop');
      final probe = _LiveStateProbe();
      final service = _RejectingService(
        prefs: prefs,
        rootDirectory: () async => root,
        clock: clock,
        reloadSettings: probe.reload,
        resyncEffects: probe.resync,
      );

      await expectLater(
        service.apply(
          AudioProfile(
            id: 'ap_fail_only',
            name: 'Fails only',
            createdAt: clock(),
            appVersion: '1.0.0',
            values: <String, Object?>{PrefsKeys.dsdOutputMode: 'pcm'},
          ),
        ),
        throwsA(isA<AudioProfileApplyError>()),
      );

      expect(probe.reloads, 1);
      expect(probe.resyncs, 1);
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
      await service.cleanupExport(file);
    });

    test('cleanupExport deletes the temp folder created by export', () async {
      final service = buildService();
      final profile = await service.captureCurrent('Share me');
      final file = await service.export(profile);
      final directory = file.parent;
      expect(await directory.exists(), isTrue);

      final removed = await service.cleanupExport(file);

      expect(removed, isTrue);
      expect(await directory.exists(), isFalse);
    });

    test('cleanupExport never deletes a user-chosen file', () async {
      final userFile = File(p.join(root.path, 'my-backup.json'))
        ..writeAsStringSync('{"user":true}');

      final removed = await buildService().cleanupExport(userFile);

      expect(removed, isFalse);
      expect(await userFile.exists(), isTrue);
      expect(await userFile.readAsString(), '{"user":true}');
    });

    test('import re-keys a profile whose id is already stored', () async {
      final probe = _LiveStateProbe();
      final service = buildService(
        reloadSettings: probe.reload,
        resyncEffects: probe.resync,
      );
      final profile = await service.captureCurrent('Exportable');
      final file = await service.export(profile);

      final imported = await service.importFromFile(file.path);

      expect(imported.id, isNot(profile.id));
      expect(imported.name, 'Exportable');
      expect((await service.list()).length, 2);
      expect(probe.reloads, 1);
      expect(probe.resyncs, 1);
      await service.cleanupExport(file);
    });

    test('import drops corrupt and non-whitelisted settings', () async {
      final json = <String, Object?>{
        'formatVersion': 1,
        'id': 'ap_import_skips',
        'name': 'Mixed',
        'createdAt': '2026-01-02T03:04:05Z',
        'appVersion': '1.0.0',
        'values': <String, Object?>{
          PrefsKeys.eqEnabled: true,
          PrefsKeys.eqGains: <Object?>[1, 2],
          'library_path': '/music',
        },
      };
      final file = File(p.join(root.path, 'mixed.json'))
        ..writeAsStringSync(jsonEncode(json));

      final imported = await buildService().importFromFile(file.path);

      expect(imported.values[PrefsKeys.eqEnabled], isTrue);
      expect(imported.values.containsKey(PrefsKeys.eqGains), isFalse);
      expect(imported.values.containsKey('library_path'), isFalse);
      expect(imported.ignoredKeys, contains(PrefsKeys.eqGains));
      expect(imported.ignoredKeys, contains('library_path'));
      expect(await file.exists(), isTrue);
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

  group('setGlobalDefaults', () {
    test('stores, exposes and clears the default profile id', () async {
      final service = buildService();
      final profile = await service.captureCurrent('Default me');

      expect(service.defaultProfileId, isNull);
      expect(await service.setGlobalDefaults(profile.id), isTrue);
      expect(service.defaultProfileId, profile.id);
      expect(
        prefs.getString(AudioProfileService.defaultProfileKey),
        profile.id,
      );

      expect(await service.setGlobalDefaults(null), isTrue);
      expect(service.defaultProfileId, isNull);
      expect(
        prefs.containsKey(AudioProfileService.defaultProfileKey),
        isFalse,
      );
    });

    test('returns false for an unknown profile and keeps the old default',
        () async {
      final service = buildService();
      final profile = await service.captureCurrent('Known');
      await service.setGlobalDefaults(profile.id);

      expect(await service.setGlobalDefaults('ap_does_not_exist'), isFalse);
      expect(service.defaultProfileId, profile.id);
    });

    test('rejects an unsafe profile id', () async {
      final service = buildService();

      await expectLater(
        service.setGlobalDefaults('../escape'),
        throwsA(
          isA<AudioProfileStoreError>().having(
            (error) => error.code,
            'code',
            'audio-profile-invalid-id',
          ),
        ),
      );
      expect(service.defaultProfileId, isNull);
    });

    test('deleting the default profile clears the selection', () async {
      final service = buildService();
      final profile = await service.captureCurrent('Short lived');
      await service.setGlobalDefaults(profile.id);

      await service.delete(profile.id);

      expect(service.defaultProfileId, isNull);
      expect(await service.list(), isEmpty);
    });
  });

  group('corrupt preferences', () {
    test('capture skips a corrupt value instead of failing', () async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsKeys.eqEnabled: true,
        PrefsKeys.eqGains: <Object?>[1, 2],
      });
      prefs = await SharedPreferences.getInstance();

      final profile = await buildService().captureCurrent('Corrupt');

      expect(profile.values[PrefsKeys.eqEnabled], isTrue);
      expect(profile.values.containsKey(PrefsKeys.eqGains), isFalse);
      expect(profile.ignoredKeys, contains(PrefsKeys.eqGains));
    });
  });
}
