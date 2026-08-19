// lib/features/playlists/cubit/playlist_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import 'playlist_state.dart';

class PlaylistCubit extends Cubit<PlaylistState> {
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription? _playlistsSub;
  StreamSubscription? _playlistSongsSub;

  PlaylistCubit({required PlaylistUseCases playlistUseCases})
      : _playlistUseCases = playlistUseCases,
        super(const PlaylistState()) {
    _init();
  }

  void _init() {
    _playlistsSub = _playlistUseCases.watchPlaylists().listen((playlists) {
      emit(state.copyWith(playlists: playlists));
    });
  }

  void loadPlaylistSongs(int playlistId) {
    _playlistSongsSub?.cancel();
    _playlistSongsSub = _playlistUseCases.watchPlaylistSongs(playlistId).listen((songs) {
      emit(state.copyWith(currentPlaylistSongs: songs));
    });
  }

  Future<void> createPlaylist(String name, {bool isSmart = false, String? criteria}) async {
    await _playlistUseCases.createPlaylist(name, isSmart: isSmart, smartCriteria: criteria);
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    await _playlistUseCases.renamePlaylist(playlistId, newName);
  }

  Future<void> deletePlaylist(int playlistId) async {
    await _playlistUseCases.deletePlaylist(playlistId);
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    await _playlistUseCases.addSongToPlaylist(playlistId, songId);
  }

  Future<void> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    await _playlistUseCases.addSongsToPlaylist(playlistId, songIds);
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    await _playlistUseCases.removeSongFromPlaylist(playlistId, songId);
  }

  @override
  Future<void> close() {
    _playlistsSub?.cancel();
    _playlistSongsSub?.cancel();
    return super.close();
  }
}
