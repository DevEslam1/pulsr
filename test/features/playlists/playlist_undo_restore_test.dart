// test/features/playlists/playlist_undo_restore_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MusicRepository repo;
  late PlaylistUseCases playlistUseCases;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
    playlistUseCases = PlaylistUseCases(repo, SmartPlaylistEngine(db));
  });

  tearDown(() async {
    await db.close();
  });

  group('Playlist delete undo', () {
    test('restores the playlist and its songs on Undo', () async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(201),
            title: 'Track A',
            path: '/music/a.mp3',
          ));
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(202),
            title: 'Track B',
            path: '/music/b.mp3',
          ));

      final playlistId =
          (await repo.createPlaylist('Roadtrip')).getOrElse((_) => -1);
      await repo.addSongsToPlaylist(playlistId, [201, 202]);

      final cubit = PlaylistCubit(playlistUseCases: playlistUseCases);

      // Mirror the screen: capture membership *before* removing the playlist.
      final captured =
          (await playlistUseCases.watchPlaylistSongs(playlistId).first)
              .fold((_) => <int>[], (songs) => [for (final s in songs) s.id]);
      expect(captured.toSet(), {201, 202});

      await cubit.deletePlaylist(playlistId);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.playlists.any((p) => p.name == 'Roadtrip'), isFalse);

      final restoredId = await cubit.restorePlaylist(
        'Roadtrip',
        songIds: captured,
      );
      expect(restoredId == null, isFalse);
      expect(restoredId, greaterThan(0));

      final restoredSongs =
          (await playlistUseCases.watchPlaylistSongs(restoredId!).first)
              .fold((_) => <int>[], (songs) => [for (final s in songs) s.id]);
      expect(restoredSongs.toSet(), {201, 202});

      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.playlists.any((p) => p.name == 'Roadtrip'), isTrue);

      await cubit.close();
    });
  });
}
