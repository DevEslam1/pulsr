// test/data/usecases/backup_restore_type_corruption_test.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/usecases/backup_usecases.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MusicRepository repository;
  late ImportBackupUseCase importUseCase;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
    importUseCase = ImportBackupUseCase(repository, db);
  });

  tearDown(() async {
    await db.close();
  });

  test('schema-valid but type-corrupt fields degrade instead of aborting',
      () async {
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(10),
            title: 'Track A',
            path: '/storage/music/track_a.mp3',
          ),
        );

    final backup = jsonEncode({
      'version': 4,
      'favorites': ['/storage/music/track_a.mp3'],
      'playlists': [
        {
          'name': 'Mix',
          'isSmart': 'yes',
          'smartCriteria': 42,
          'songPaths': ['/storage/music/track_a.mp3'],
        }
      ],
      'settings': {
        'themeMode': 42,
        'customAccentColorValue': 'purple',
        'playerThemeMode': <Object>[],
        'visualizerStyle': {'a': 1},
      },
      'playHistory': [
        {
          'path': '/storage/music/track_a.mp3',
          'playCount': 'twelve',
          'lastPlayed': 'yesterday',
        }
      ],
      'downloads': [
        {'path': 42, 'remoteId': true}
      ],
      'queue': {
        'paths': ['/storage/music/track_a.mp3'],
        'currentIndex': 'one',
        'positionMs': 'zero',
      },
    });

    final result = await importUseCase.execute(backup);

    expect(result.restoredFavoritesCount, 1);
    expect(result.restoredPlaylistsCount, 1);
    expect(result.restoredHistoryCount, 1);
    expect(result.unmatchedPaths, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('setting_theme_mode'), 'dark');
    expect(prefs.getInt('setting_custom_accent'), 0xFFFF2A85);
    expect(prefs.getString('setting_player_theme_mode'), 'classic');
    expect(prefs.getString('setting_visualizer_style'), 'bar');

    final song = await (db.select(db.songsTable)..where((t) => t.id.equals(10)))
        .getSingle();
    expect(song.isFavorite, isTrue);
    expect(song.playCount, 0);

    final queue = await db.select(db.queueItemsTable).get();
    expect(queue, hasLength(1));
    expect(queue.single.songId, 10);
    expect(queue.single.isCurrent, isTrue);
  });
}
