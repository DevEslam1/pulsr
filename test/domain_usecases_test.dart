// test/domain_usecases_test.dart
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);

    await db.into(db.songsTable).insert(
      SongsTableCompanion.insert(
        id: const Value(1),
        title: 'Song Alpha',
        artist: const Value('Artist One'),
        album: const Value('Album X'),
        genre: const Value('Rock'),
        year: const Value(2023),
        path: '/storage/music/rock/alpha.mp3',
        isFavorite: const Value(true),
      ),
    );
    await db.into(db.songsTable).insert(
      SongsTableCompanion.insert(
        id: const Value(2),
        title: 'Song Beta',
        artist: const Value('Artist Two'),
        album: const Value('Album Y'),
        genre: const Value('Jazz'),
        year: const Value(2021),
        path: '/storage/music/jazz/beta.mp3',
        isFavorite: const Value(false),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Domain UseCases Unit Tests', () {
    test('GetSongsUseCase watches song list', () async {
      final useCase = GetSongsUseCase(repo);
      final result = await useCase.watchSongs().first;
      final songs = result.getOrElse((_) => []);
      expect(songs.length, equals(2));
    });

    test('GetAlbumsUseCase watches albums', () async {
      final useCase = GetAlbumsUseCase(repo);
      final result = await useCase.watchAlbums().first;
      final albums = result.getOrElse((_) => []);
      expect(albums, isNotNull);
    });

    test('GetArtistsUseCase watches artists', () async {
      final useCase = GetArtistsUseCase(repo);
      final result = await useCase.watchArtists().first;
      final artists = result.getOrElse((_) => []);
      expect(artists, isNotNull);
    });

    test('GetFavoritesUseCase watches favorite songs', () async {
      final useCase = GetFavoritesUseCase(repo);
      final result = await useCase.watchFavorites().first;
      final favorites = result.getOrElse((_) => []);
      expect(favorites.length, equals(1));
      expect(favorites.first.title, equals('Song Alpha'));
    });

    test('ToggleFavoriteUseCase toggles favorite state of a song', () async {
      final toggleUseCase = ToggleFavoriteUseCase(repo);
      final getFavUseCase = GetFavoritesUseCase(repo);

      await toggleUseCase.call(2);
      final result = await getFavUseCase.watchFavorites().first;
      final favorites = result.getOrElse((_) => []);
      expect(favorites.length, equals(2));
    });

    test('SearchMusicUseCase watches search results', () async {
      final useCase = SearchMusicUseCase(repo);
      final result = await useCase.searchSongs('Alpha').first;
      final songs = result.getOrElse((_) => []);
      expect(songs.length, equals(1));
      expect(songs.first.title, equals('Song Alpha'));
    });

    test('FolderUseCases builds folder hierarchy correctly', () async {
      final useCase = FolderUseCases(repo);
      final result = await useCase.getFolderHierarchy();
      final items = result.getOrElse((_) => []);
      expect(items.isNotEmpty, isTrue);
    });

    test('FolderUseCases excludes YouTube rows from the folder hierarchy', () async {
      // A ytmusic:// sentinel path would otherwise collapse into one phantom
      // folder the user could "exclude". Only the two local folders should show.
      await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(
          id: const Value(-42),
          title: 'Streamed Track',
          artist: const Value('Remote Artist'),
          path: 'ytmusic://vid123',
          source: const Value(SongSource.youtube),
          remoteId: const Value('vid123'),
        ),
      );

      final useCase = FolderUseCases(repo);
      final result = await useCase.getFolderHierarchy();
      final items = result.getOrElse((_) => []);

      expect(items.length, equals(2));
      expect(items.any((f) => f.path.contains('ytmusic')), isFalse);
      expect(
        items.map((f) => f.path).toSet(),
        equals({'/storage/music/rock', '/storage/music/jazz'}),
      );
    });

    test('FolderUseCases.watchFolderSongs never yields YouTube rows', () async {
      await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(
          id: const Value(-43),
          title: 'Streamed Track',
          artist: const Value('Remote Artist'),
          path: 'ytmusic://vid456',
          source: const Value(SongSource.youtube),
          remoteId: const Value('vid456'),
        ),
      );

      final useCase = FolderUseCases(repo);
      final songs = await useCase.watchFolderSongs('/storage/music/rock').first
          .then((r) => r.getOrElse((_) => []));

      expect(songs.length, equals(1));
      expect(songs.first.title, equals('Song Alpha'));
      expect(songs.every((s) => s.source == SongSource.local), isTrue);
    });
  });
}
