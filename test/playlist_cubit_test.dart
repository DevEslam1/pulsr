// test/playlist_cubit_test.dart
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
  late AppDatabase db;
  late MusicRepository repo;
  late SmartPlaylistEngine smartEngine;
  late PlaylistUseCases playlistUseCases;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
    smartEngine = SmartPlaylistEngine(db);
    playlistUseCases = PlaylistUseCases(repo, smartEngine);
  });

  tearDown(() async {
    await db.close();
  });

  group('PlaylistCubit Tests', () {
    test('Creates playlist and emits updated playlist list', () async {
      final cubit = PlaylistCubit(playlistUseCases: playlistUseCases);

      await cubit.createPlaylist('Chill Vibrations');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.playlists.any((p) => p.name == 'Chill Vibrations'), isTrue);

      await cubit.close();
    });

    test('Adds and removes song in playlist', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(101),
        title: 'Playlist Song',
        path: '/path/song.mp3',
      );
      await db.into(db.songsTable).insert(song);

      final playlistId = (await repo.createPlaylist('Test List')).getOrElse((_) => -1);
      final cubit = PlaylistCubit(playlistUseCases: playlistUseCases);

      await cubit.addSongToPlaylist(playlistId, 101);
      cubit.loadPlaylistSongs(playlistId);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.currentPlaylistSongs.length, equals(1));
      expect(cubit.state.currentPlaylistSongs.first.id, equals(101));

      await cubit.removeSongFromPlaylist(playlistId, 101);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.currentPlaylistSongs.length, equals(0));

      await cubit.close();
    });

    test('Deletes playlist', () async {
      final playlistId = (await repo.createPlaylist('To Delete')).getOrElse((_) => -1);
      final cubit = PlaylistCubit(playlistUseCases: playlistUseCases);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.playlists.any((p) => p.id == playlistId), isTrue);

      await cubit.deletePlaylist(playlistId);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.playlists.any((p) => p.id == playlistId), isFalse);

      await cubit.close();
    });
  });
}
