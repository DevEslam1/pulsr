// test/backup_usecases_test.dart
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/usecases/backup_usecases.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('Backup UseCases Tests', () {
    test('Export produces valid JSON with version 1', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(1),
              title: 'Song 1',
              path: '/storage/music/song1.mp3',
              isFavorite: const Value(true),
              playCount: const Value(5),
            ),
          );

      final exported = await exportUseCase.execute();
      expect(exported, isNotEmpty);

      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      expect(decoded['version'], equals(1));
      expect(decoded['favorites'], contains('/storage/music/song1.mp3'));
      expect(decoded['settings'], isA<Map<String, dynamic>>());
      expect(decoded['playHistory'], isA<List<dynamic>>());
    });

    test('Import restores favorites, playlists, history, and excluded folders',
        () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(10),
              title: 'Track A',
              path: '/storage/music/track_a.mp3',
              isFavorite: const Value(false),
            ),
          );

      final backupData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'favorites': ['/storage/music/track_a.mp3'],
        'playlists': [
          {
            'name': 'My Rock',
            'isSmart': false,
            'songPaths': ['/storage/music/track_a.mp3'],
          }
        ],
        'settings': {
          'gaplessPlayback': true,
          'crossfadeSeconds': 3.5,
        },
        'playHistory': [
          {
            'path': '/storage/music/track_a.mp3',
            'playCount': 12,
            'lastPlayed': 1700000000,
          }
        ],
        'excludedFolders': ['/storage/emulated/0/WhatsApp/Media'],
      };

      final jsonString = jsonEncode(backupData);
      final result = await importUseCase.execute(jsonString);

      expect(result.restoredFavoritesCount, equals(1));
      expect(result.restoredPlaylistsCount, equals(1));
      expect(result.restoredHistoryCount, equals(1));
      expect(result.restoredExcludedFoldersCount, equals(1));

      // Verify DB updates
      final song = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(song.isFavorite, isTrue);
      expect(song.playCount, equals(12));
    });

    test('Import throws FormatException when payload exceeds 10 MB', () async {
      final oversizedString = 'x' * (10 * 1024 * 1024 + 10);
      expect(
        () => importUseCase.execute(oversizedString),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('10 MB'),
        )),
      );
    });

    test('Import throws FormatException on invalid or corrupted JSON',
        () async {
      expect(
        () => importUseCase.execute('not-valid-json { ['),
        throwsA(isA<FormatException>()),
      );
    });

    test('Import throws FormatException on unsupported version', () async {
      final badVersionJson = jsonEncode({'version': 0});
      expect(
        () => importUseCase.execute(badVersionJson),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('version'),
        )),
      );
    });

    test(
        'Import matches by parent folder + filename and avoids cross-matching duplicates',
        () async {
      // Two songs with the same filename in different album directories
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(101),
              title: 'Track 01 (Album A)',
              path: '/storage/music/AlbumA/track01.mp3',
              isFavorite: const Value(false),
            ),
          );
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(102),
              title: 'Track 01 (Album B)',
              path: '/storage/music/AlbumB/track01.mp3',
              isFavorite: const Value(false),
            ),
          );

      // Restore targeting AlbumB with changed base mount point
      final backupData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'favorites': ['/old_phone/sdcard/AlbumB/track01.mp3'],
      };

      final result = await importUseCase.execute(jsonEncode(backupData));
      expect(result.restoredFavoritesCount, equals(1));

      final songA = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(101)))
          .getSingle();
      final songB = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(102)))
          .getSingle();

      expect(songA.isFavorite, isFalse);
      expect(songB.isFavorite, isTrue); // Correctly matched AlbumB!
    });
  });
}
