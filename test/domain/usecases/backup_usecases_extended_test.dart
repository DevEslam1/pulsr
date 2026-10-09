// test/domain/usecases/backup_usecases_extended_test.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/usecases/backup_usecases.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFile {
  final int fileLength;
  final String contents;
  final bool throwOnRead;

  _FakeFile(this.fileLength, this.contents, {this.throwOnRead = false});

  Future<int> length() async => fileLength;

  Future<String> readAsString() async {
    if (throwOnRead) throw StateError('cannot read');
    return contents;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MusicRepository repository;
  late ExportBackupUseCase exportUseCase;
  late ImportBackupUseCase importUseCase;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
    exportUseCase = ExportBackupUseCase(repository);
    importUseCase = ImportBackupUseCase(repository, db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertSong({
    required int id,
    required String title,
    String? path,
    String? remoteId,
    int playCount = 0,
    int? lastPlayed,
    bool isDownloaded = false,
    bool isFavorite = false,
    String source = SongSource.local,
    String artist = 'Artist',
    String album = 'Album',
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          artist: Value(artist),
          album: Value(album),
          path: path ?? '/music/$title.mp3',
          remoteId: Value(remoteId),
          playCount: Value(playCount),
          lastPlayed: Value(lastPlayed),
          isDownloaded: Value(isDownloaded),
          isFavorite: Value(isFavorite),
          source: Value(source),
        ));
  }

  group('ExportBackupUseCase', () {
    test('includes downloads, history, queue, settings and per-song data',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_gapless': false,
        'setting_crossfade': 3.0,
        'setting_min_duration': 45,
        'setting_theme_color_source': 'album',
        PrefsKeys.customEqProfiles: jsonEncode([
          {'name': 'Flat'}
        ]),
        'setting_automation_rules': jsonEncode([
          {'trigger': 'x'}
        ]),
        'dsp_snapshot_store_v1': '{"a":1}',
        'setting_device_profile_links': '{"b":2}',
        'setting_device_registry': '{"c":3}',
        'setting_custom_profiles': '{"d":4}',
        'song_ratings_v1': jsonEncode({'id:1': 5}),
        'per_track_bpm_overrides_v1': jsonEncode({'id:1': 128.0}),
        'per_song_eq_overrides_v1': jsonEncode({'id:1': 'eq'}),
        'per_song_volume_overrides_v1': jsonEncode({'id:1': 0.5}),
        'playback_bookmarks_v1': jsonEncode({'id:1': 42000}),
      });

      await insertSong(
          id: 1,
          title: 'Downloaded',
          remoteId: 'vid1',
          playCount: 7,
          lastPlayed: 1700000000,
          isDownloaded: true,
          isFavorite: true);
      await insertSong(id: 2, title: 'Other', path: '/music/other.mp3');

      await repository.saveQueue([1, 2], 1, 500);

      final exported = await exportUseCase.execute();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;

      expect(decoded['version'], 4);
      expect(decoded['favorites'], contains('/music/Downloaded.mp3'));
      expect(decoded['downloads'], isA<List>());
      expect((decoded['downloads'] as List).first['remoteId'], 'vid1');
      expect(decoded['playHistory'], isA<List>());
      expect(decoded['excludedFolders'], isA<List>());
      expect(decoded['customEqProfiles'], isA<List>());
      expect(decoded['automationRules'], isA<List>());
      expect(decoded['dspSnapshots'], '{"a":1}');
      expect(decoded['deviceProfiles'], '{"b":2}');
      expect(decoded['deviceRegistry'], '{"c":3}');
      expect(decoded['settingsProfiles'], '{"d":4}');
      expect(decoded['ratings'], isA<Map>());
      expect(decoded['bpmOverrides'], isA<Map>());
      expect(decoded['perSongEq'], isA<Map>());
      expect(decoded['perSongVolume'], isA<Map>());
      expect(decoded['bookmarks'], isA<Map>());
      expect(decoded['queue'], isA<Map>());
      expect((decoded['queue'] as Map)['currentIndex'], 1);
      expect((decoded['queue'] as Map)['positionMs'], 500);
    });

    test('per-song ratings key is portable (remote id preferred)', () async {
      SharedPreferences.setMockInitialValues({
        'song_ratings_v1': jsonEncode({'id:9': 4}),
      });
      await insertSong(
          id: 9, title: 'Portable', remoteId: 'remote9',
          path: '/music/portable.mp3');
      final decoded =
          jsonDecode(await exportUseCase.execute()) as Map<String, dynamic>;
      expect((decoded['ratings'] as Map).keys, ['yt:remote9']);
    });

    test('tolerates corrupt per-song JSON without throwing', () async {
      SharedPreferences.setMockInitialValues({
        'song_ratings_v1': 'not-json',
      });
      await insertSong(id: 1, title: 'X');
      final exported = await exportUseCase.execute();
      expect(exported, isNotEmpty);
    });
  });

  group('ImportBackupUseCase input handling', () {
    test('executeFromFile rejects files larger than the cap', () async {
      await expectLater(
        importUseCase.executeFromFile(
            _FakeFile(ImportBackupUseCase.maxBackupSizeBytes + 1, '{}')),
        throwsA(isA<FormatException>()),
      );
    });

    test('executeFromFile reads valid content', () async {
      final json = jsonEncode({'version': 1, 'favorites': []});
      final result = await importUseCase
          .executeFromFile(_FakeFile(json.length, json));
      expect(result.restoredFavoritesCount, 0);
    });

    test('executeFromFile wraps read failures in FormatException', () async {
      await expectLater(
        importUseCase.executeFromFile(_FakeFile(10, '', throwOnRead: true)),
        throwsA(isA<FormatException>()),
      );
    });

    test('execute accepts a String directly', () async {
      final result = await importUseCase
          .execute(jsonEncode({'version': 1, 'favorites': []}));
      expect(result.restoredFavoritesCount, 0);
    });

    test('rejects oversized knownByteLength', () async {
      await expectLater(
        importUseCase.execute('{}',
            knownByteLength: ImportBackupUseCase.maxBackupSizeBytes + 1),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-map JSON roots', () async {
      await expectLater(
        importUseCase.execute('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('validateSchema', () {
    void expectInvalid(Map<String, dynamic> data) =>
        expect(() => ImportBackupUseCase.validateSchema(data),
            throwsA(isA<FormatException>()));

    test('accepts a minimal valid schema', () {
      ImportBackupUseCase.validateSchema({'version': 1});
    });

    test('rejects invalid versions', () {
      expectInvalid({});
      expectInvalid({'version': 'one'});
      expectInvalid({'version': 0});
      expectInvalid({'version': 99});
    });

    test('rejects malformed collection fields', () {
      expectInvalid({'version': 1, 'favorites': 'x'});
      expectInvalid({'version': 1, 'playlists': 'x'});
      expectInvalid({
        'version': 1,
        'playlists': ['not-a-map']
      });
      expectInvalid({
        'version': 1,
        'playlists': [
          {'name': '   '}
        ]
      });
      expectInvalid({
        'version': 1,
        'playlists': [
          {'name': 'ok', 'songPaths': 'x'}
        ]
      });
      expectInvalid({'version': 1, 'settings': 'x'});
      expectInvalid({'version': 1, 'playHistory': 'x'});
      expectInvalid({'version': 1, 'excludedFolders': 'x'});
      expectInvalid({'version': 1, 'customEqProfiles': 'x'});
      expectInvalid({'version': 1, 'automationRules': 'x'});
      expectInvalid({'version': 1, 'downloads': 'x'});
    });

    test('accepts valid playlists and customEqProfiles shapes', () {
      ImportBackupUseCase.validateSchema({
        'version': 1,
        'playlists': [
          {'name': 'List', 'songPaths': <String>[]}
        ],
        'customEqProfiles': {'preset': 'x'},
      });
    });
  });

  group('ImportBackupUseCase restore', () {
    test('restores favorites, history, excluded folders, settings and downloads',
        () async {
      await insertSong(id: 10, title: 'A', path: '/music/a.mp3');
      await insertSong(id: 11, title: 'B', path: '/music/b.mp3');
      await insertSong(id: 12, title: 'C', path: 'ytmusic://vidC',
          remoteId: 'vidC', source: SongSource.youtube);
      await repository.toggleFolderExclusion('/already/excluded');

      final payload = {
        'version': 4,
        'favorites': ['/music/a.mp3', '/missing/file.mp3'],
        'playHistory': [
          {'path': '/music/b.mp3', 'playCount': 42, 'lastPlayed': 123456},
        ],
        'excludedFolders': ['/already/excluded', '/new/excluded'],
        'settings': {
          'gaplessPlayback': false,
          'crossfadeSeconds': 5,
          'minDurationSec': 12,
          'dynamicThemingEnabled': false,
          'themeColorSource': 'album',
          'resumeAfterInterruption': false,
          'themeMode': 'light',
          'customAccentColorValue': 123,
          'playerThemeMode': 'minimal',
          'visualizerStyle': 'wave',
          'replayGainMode': 'album',
          'replayGainPreampWithRg': 1.5,
          'replayGainPreampWithoutRg': -2.5,
          'wifiOnlyMode': true,
          'offlineOnlyMode': true,
          'bitPerfectMode': true,
          'dspPreference': 'oem',
          'streamingQuality': 'low',
          'downloadQuality': 'low',
          'isLosslessMode': true,
          'eqEnabled': true,
          'eqGains': 'gains',
          'eqPreset': 'Rock',
          'eqPreamp': 2.0,
          'eqBandCount': 10,
          'eqCustomFrequencies': 'freqs',
          'eqCustom32Frequencies': 'freqs32',
          'eqCustom64Frequencies': 'freqs64',
          'playbackSpeed': 1.25,
        },
        'downloads': [
          {'path': '/music/b.mp3', 'remoteId': null},
          {'path': 'missing', 'remoteId': 'vidC'},
        ],
        'playlists': [
          {
            'name': 'Restored',
            'isSmart': false,
            'songPaths': ['/music/a.mp3', '/music/b.mp3'],
          }
        ],
      };

      final result = await importUseCase.execute(jsonEncode(payload));

      expect(result.restoredFavoritesCount, 1);
      expect(result.restoredHistoryCount, 1);
      expect(result.restoredExcludedFoldersCount, 1);
      expect(result.restoredPlaylistsCount, 1);
      expect(result.restoredDownloadsCount, 2);
      expect(result.unmatchedPaths, contains('/missing/file.mp3'));
      expect(result.restoredSettingsCount,
          (payload['settings']! as Map).length);

      final songA = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(songA.isFavorite, isTrue);
      final songB = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(11)))
          .getSingle();
      expect(songB.playCount, 42);
      expect(songB.lastPlayed, 123456);
      expect(songB.isDownloaded, isTrue);
      final songC = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(12)))
          .getSingle();
      expect(songC.isDownloaded, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_gapless'), isFalse);
      expect(prefs.getDouble('setting_crossfade'), 5.0);
      expect(prefs.getInt('setting_min_duration'), 12);
      expect(prefs.getString(PrefsKeys.eqPresetName), 'Rock');
      expect(prefs.getString(PrefsKeys.eqGains), 'gains');
      expect(prefs.getDouble(PrefsKeys.eqPreamp), 2.0);
      expect(prefs.getInt(PrefsKeys.eqBandCount), 10);
      expect(prefs.getString(PrefsKeys.eqCustomFrequencies), 'freqs');
      expect(prefs.getDouble('setting_playback_speed'), 1.25);
      expect(
          (await repository.getExcludedFolderPaths()).getOrElse((_) => []),
          containsAll(['/already/excluded', '/new/excluded']));
    });

    test('restores per-song data remapped onto fresh ids', () async {
      await insertSong(id: 50, title: 'Song', remoteId: 'v50',
          path: '/music/song.mp3');
      final payload = {
        'version': 4,
        'ratings': {'yt:v50': 5},
        'bpmOverrides': {'path:/music/song.mp3': 120.0},
        'perSongEq': {'id:50': 'eq'},
        'perSongVolume': {'id:50': 0.3},
        'bookmarks': {'yt:v50': 1000},
      };
      await importUseCase.execute(jsonEncode(payload));

      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('song_ratings_v1')!), {'50': 5});
      expect(jsonDecode(prefs.getString('per_track_bpm_overrides_v1')!),
          {'50': 120.0});
      expect(jsonDecode(prefs.getString('per_song_eq_overrides_v1')!),
          {'50': 'eq'});
      expect(jsonDecode(prefs.getString('per_song_volume_overrides_v1')!),
          {'50': 0.3});
      expect(jsonDecode(prefs.getString('playback_bookmarks_v1')!),
          {'yt:v50': 1000});
    });

    test('restores queue and smart playlist update', () async {
      await insertSong(id: 1, title: 'Q1', path: '/music/q1.mp3');
      await insertSong(id: 2, title: 'Q2', path: '/music/q2.mp3');
      final existing = (await repository.createPlaylist('Existing')).fold(
          (_) => -1, (r) => r);

      final payload = {
        'version': 4,
        'queue': {
          'paths': ['/music/q1.mp3', '/music/q2.mp3'],
          'currentIndex': 1,
          'positionMs': 4242,
        },
        'playlists': [
          {
            'name': 'Existing',
            'isSmart': true,
            'smartCriteria': '{"rules":[]}',
            'songPaths': <String>[],
          }
        ],
      };
      final result = await importUseCase.execute(jsonEncode(payload));
      expect(result.restoredPlaylistsCount, 1);

      final queue = (await repository.getSavedQueue()).getOrElse((_) => []);
      expect(queue.length, 2);
      final current = queue.firstWhere((q) => q.isCurrent);
      expect(current.songId, 2);
      expect(current.positionMs, 4242);

      final pl = (await repository.getPlaylistById(existing))
          .getOrElse((_) => null);
      expect(pl!.smartCriteria, '{"rules":[]}');
    });

    test('restores v2 profile blobs and customEqProfiles', () async {
      final payload = {
        'version': 4,
        'customEqProfiles': [
          {'name': 'Profile'}
        ],
        'automationRules': [
          {'trigger': 'wifi'}
        ],
        'dspSnapshots': '{"snap":1}',
        'deviceProfiles': '{"dev":1}',
        'deviceRegistry': '{"reg":1}',
        'settingsProfiles': '{"set":1}',
      };
      final result = await importUseCase.execute(jsonEncode(payload));
      expect(result.restoredEqProfilesCount, 1);
      expect(result.restoredAutomationRulesCount, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dsp_snapshot_store_v1'), '{"snap":1}');
      expect(prefs.getString('setting_device_profile_links'), '{"dev":1}');
      expect(prefs.getString('setting_device_registry'), '{"reg":1}');
      expect(prefs.getString('setting_custom_profiles'), '{"set":1}');
    });

    test('matches by unique filename when the full path changed', () async {
      await insertSong(id: 60, title: 'Unique', path: '/old/device/unique.mp3');
      final payload = {
        'version': 1,
        'favorites': ['/new/device/unique.mp3'],
      };
      final result = await importUseCase.execute(jsonEncode(payload));
      expect(result.restoredFavoritesCount, 1);
      final song = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(60)))
          .getSingle();
      expect(song.isFavorite, isTrue);
    });

    test('handles large playHistory in batches', () async {
      await insertSong(id: 70, title: 'Batch', path: '/music/batch.mp3');
      final history = List.generate(
        150,
        (_) => {
          'path': '/music/batch.mp3',
          'playCount': 3,
          'lastPlayed': 1000,
        },
      );
      final result = await importUseCase
          .execute(jsonEncode({'version': 1, 'playHistory': history}));
      expect(result.restoredHistoryCount, 150);
    });
  });
}
