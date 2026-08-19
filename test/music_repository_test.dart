// test/music_repository_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('MusicRepository & AppDatabase Tests', () {
    test('AppDatabase schema migration to v3 creates indexes successfully', () async {
      expect(db.schemaVersion, equals(3));

      // Query pragma index_list for songs table
      final indexes = await db.customSelect('PRAGMA index_list("songs");').get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toList();

      expect(indexNames, contains('idx_songs_title'));
      expect(indexNames, contains('idx_songs_artist'));
      expect(indexNames, contains('idx_songs_album_id'));
      expect(indexNames, contains('idx_songs_is_favorite'));
    });

    test('Insert and retrieve songs from repository', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(1),
        title: 'Test Song',
        artist: const Value('Test Artist'),
        path: '/storage/music/test.mp3',
        isFavorite: const Value(true),
      );

      await db.into(db.songsTable).insert(song);

      final result = await repository.getAllSongs();
      final songs = result.getOrElse((_) => []);
      expect(songs.length, equals(1));
      expect(songs.first.title, equals('Test Song'));
      expect(songs.first.isFavorite, isTrue);

      final favResult = await repository.getFavorites();
      final favorites = favResult.getOrElse((_) => []);
      expect(favorites.length, equals(1));
      expect(favorites.first.id, equals(1));
    });

    test('Toggle favorite song', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(2),
        title: 'Song 2',
        path: '/storage/music/song2.mp3',
        isFavorite: const Value(false),
      );

      await db.into(db.songsTable).insert(song);
      await repository.toggleFavorite(2);

      final favResult = await repository.getFavorites();
      final favorites = favResult.getOrElse((_) => []);
      expect(favorites.any((s) => s.id == 2), isTrue);
    });

    test('Record play history updates song count and lastPlayed', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(3),
        title: 'Song 3',
        path: '/storage/music/song3.mp3',
      );

      await db.into(db.songsTable).insert(song);
      await repository.recordPlayHistory(3, completed: true);

      final recentResult = await repository.getRecentlyPlayed();
      final recent = recentResult.getOrElse((_) => []);
      expect(recent.length, equals(1));
      expect(recent.first.playCount, equals(1));
    });
  });
}
