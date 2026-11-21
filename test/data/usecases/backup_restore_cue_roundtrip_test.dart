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

  test('BackupRestoreUseCase round-trips CUE Track 1 (cueStartMs == 0) and moved CUE albums', () async {
    const oldAlbumPath = '/storage/emulated/0/Music/OldAlbum/album.flac';
    const newAlbumPath = '/storage/emulated/0/Music/MovedAlbum/album.flac';

    // 1. Insert original CUE album tracks (Track 1 has cueStartMs == 0)
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(1),
            title: 'Track 1 (Intro)',
            path: oldAlbumPath,
            cueStartMs: const Value(0),
            cueEndMs: const Value(180000),
            cueFile: const Value('/storage/emulated/0/Music/OldAlbum/album.cue'),
            isFavorite: const Value(true), // Track 1 is favorite!
          ),
        );
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(2),
            title: 'Track 2 (Main)',
            path: oldAlbumPath,
            cueStartMs: const Value(180000),
            cueEndMs: const Value(360000),
            cueFile: const Value('/storage/emulated/0/Music/OldAlbum/album.cue'),
            isFavorite: const Value(false),
          ),
        );

    // Queue has Track 1 at 0ms
    await db.into(db.queueItemsTable).insert(
          QueueItemsTableCompanion.insert(
            songId: 1,
            orderIndex: 0,
            isCurrent: const Value(true),
            positionMs: const Value(15000),
          ),
        );

    // 2. Export backup
    final backupJson = await exportUseCase.execute();
    final exportedData = jsonDecode(backupJson) as Map<String, dynamic>;

    // Verify Track 1 carries #pulsr_cue=0 in favorites and queue
    final favorites = (exportedData['favorites'] as List).cast<String>();
    expect(favorites, contains('$oldAlbumPath#pulsr_cue=0'),
        reason: 'Track 1 (cueStartMs == 0) must serialize with #pulsr_cue=0 rather than bare path');

    final queue = exportedData['queue'] as Map<String, dynamic>;
    final queuePaths = (queue['paths'] as List).cast<String>();
    expect(queuePaths, contains('$oldAlbumPath#pulsr_cue=0'));

    // 3. Clear database state and simulate that the album was MOVED to a new folder
    await db.delete(db.queueItemsTable).go();
    await db.delete(db.songsTable).go();

    // Re-insert songs at the NEW album path (with new positive/negative IDs)
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(101),
            title: 'Track 1 (Intro)',
            path: newAlbumPath,
            cueStartMs: const Value(0),
            cueEndMs: const Value(180000),
            cueFile: const Value('/storage/emulated/0/Music/MovedAlbum/album.cue'),
            isFavorite: const Value(false),
          ),
        );
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(102),
            title: 'Track 2 (Main)',
            path: newAlbumPath,
            cueStartMs: const Value(180000),
            cueEndMs: const Value(360000),
            cueFile: const Value('/storage/emulated/0/Music/MovedAlbum/album.cue'),
            isFavorite: const Value(false),
          ),
        );

    // 4. Restore backup
    final importResult = await importUseCase.execute(backupJson);

    expect(importResult.restoredFavoritesCount, equals(1));
    expect(importResult.unmatchedPaths, isEmpty);

    // 5. Verify favorites & queue correctly mapped to Track 1 (id 101) at new path
    final songs = await db.select(db.songsTable).get();
    final track1 = songs.firstWhere((s) => s.id == 101);
    final track2 = songs.firstWhere((s) => s.id == 102);

    expect(track1.isFavorite, isTrue, reason: 'Track 1 at new path should be marked favorite');
    expect(track2.isFavorite, isFalse);

    final restoredQueue = await db.select(db.queueItemsTable).get();
    expect(restoredQueue.length, equals(1));
    expect(restoredQueue.first.songId, equals(101));
    expect(restoredQueue.first.positionMs, equals(15000));
  });
}
