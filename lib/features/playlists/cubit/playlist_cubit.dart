// lib/features/playlists/cubit/playlist_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/error_logger.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import 'playlist_state.dart';

@injectable
class PlaylistCubit extends Cubit<PlaylistState> {
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription? _playlistsSub;
  StreamSubscription? _playlistSongsSub;
  final Map<int, StreamSubscription> _smartSubscriptions = {};
  bool _isSeedingChecked = false;

  PlaylistCubit({required PlaylistUseCases playlistUseCases})
      : _playlistUseCases = playlistUseCases,
        super(const PlaylistState()) {
    _init();
  }

  void _init() {
    _playlistsSub = _playlistUseCases.watchPlaylists().listen((result) {
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (playlists) {
          emit(state.copyWith(playlists: playlists, errorMessage: null));
          _updateSmartCounts(playlists);
          if (!_isSeedingChecked) {
            _isSeedingChecked = true;
            _checkSeeding(playlists);
          }
        },
      );
    });
  }

  Future<void> _checkSeeding(List playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seeded = prefs.getBool('smart_playlists_seeded') ?? false;
      if (!seeded) {
        await prefs.setBool('smart_playlists_seeded', true);
        final hasSmart = playlists.any((p) => p.isSmart);
        if (!hasSmart) {
          await _playlistUseCases.seedDefaultSmartPlaylists();
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to check or seed default smart playlists', error: e, stackTrace: st, category: 'PlaylistCubit');
    }
  }

  void _updateSmartCounts(List playlists) {
    final currentSmartIds = <int>{};
    for (final playlist in playlists) {
      if (playlist.isSmart && playlist.smartCriteria != null) {
        currentSmartIds.add(playlist.id);
        if (!_smartSubscriptions.containsKey(playlist.id)) {
          final criteria = SmartCriteria.fromJsonString(playlist.smartCriteria!);
          _smartSubscriptions[playlist.id] =
              _playlistUseCases.watchSmartPlaylistSongs(criteria).listen((songs) {
            if (isClosed) return;
            final updatedCounts = Map<int, int>.from(state.smartPlaylistCounts);
            updatedCounts[playlist.id] = songs.length;
            emit(state.copyWith(smartPlaylistCounts: updatedCounts));
          });
        }
      }
    }
    // Remove subscriptions for deleted smart playlists
    final staleIds = _smartSubscriptions.keys.where((id) => !currentSmartIds.contains(id)).toList();
    for (final id in staleIds) {
      _smartSubscriptions[id]?.cancel();
      _smartSubscriptions.remove(id);
    }
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  void loadPlaylistSongs(int playlistId) {
    _playlistSongsSub?.cancel();
    _playlistSongsSub = _playlistUseCases.watchPlaylistSongs(playlistId).listen((result) {
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (songs) => emit(state.copyWith(currentPlaylistSongs: songs, errorMessage: null)),
      );
    });
  }

  Future<void> createPlaylist(String name, {bool isSmart = false, String? criteria}) async {
    final result = await _playlistUseCases.createPlaylist(name, isSmart: isSmart, smartCriteria: criteria);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final result = await _playlistUseCases.renamePlaylist(playlistId, newName);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> deletePlaylist(int playlistId) async {
    final result = await _playlistUseCases.deletePlaylist(playlistId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final result = await _playlistUseCases.addSongToPlaylist(playlistId, songId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    final result = await _playlistUseCases.addSongsToPlaylist(playlistId, songIds);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final result = await _playlistUseCases.removeSongFromPlaylist(playlistId, songId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  @override
  Future<void> close() {
    _playlistsSub?.cancel();
    _playlistSongsSub?.cancel();
    for (final sub in _smartSubscriptions.values) {
      sub.cancel();
    }
    _smartSubscriptions.clear();
    return super.close();
  }
}
