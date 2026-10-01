// lib/features/player/cubit/controllers/player_transport_favorites.dart
part of 'player_transport_controller.dart';

/// Favorite-toggle surface for [PlayerTransportController]. Kept in a part so
/// the main controller stays focused and under the 400-line hygiene cap.
extension PlayerTransportFavoritesExtension on PlayerTransportController {
  Future<void> toggleFavoriteSong(SongsTableData song) =>
      _executeToggleFavorite(song);

  Future<void> toggleFavoriteById(int songId) async {
    final state = _getState();
    final song = (state.currentSong?.id == songId)
        ? state.currentSong
        : (state.queue.where((s) => s.id == songId).firstOrNull ??
            _slotLookupCache?[songId]);
    if (song != null) {
      await _executeToggleFavorite(song);
    }
  }

  Future<void> toggleFavorite([dynamic target]) async {
    if (target is SongsTableData) {
      return toggleFavoriteSong(target);
    } else if (target is int) {
      return toggleFavoriteById(target);
    } else if (target == null) {
      final current = _getState().currentSong;
      if (current != null) return toggleFavoriteSong(current);
    }
  }

  Future<void> _executeToggleFavorite(SongsTableData song) async {
    if (_toggleFavoriteUseCase == null) return;
    final songId = song.id;
    final result = await _toggleFavoriteUseCase!(song.id);
    if (_isClosed()) return;
    result.fold(
      (failure) {
        final s = _getState();
        _emit(s.copyWith(
            playback: s.playback.copyWith(errorMessage: failure.message)));
      },
      (isFav) {
        final state = _getState();
        final updatedQueue = state.queue
            .map((s) => s.id == songId ? s.copyWith(isFavorite: isFav) : s)
            .toList();
        if (_slotLookupCache != null) {
          final cached = _slotLookupCache![songId];
          if (cached != null) {
            _slotLookupCache![songId] = cached.copyWith(isFavorite: isFav);
          }
        }
        _debouncedPersistQueueSlots?.call();
        // Push the change into the audio handler so the media notification's
        // favorite icon and its queue copy stay in sync with the app (and a
        // later notification tap toggles from the same value, not a stale one).
        try {
          _audioHandler.updateFavorite(songId, isFav);
        } catch (e, st) {
          ErrorLogger.log('Failed to sync favorite to audio handler',
              error: e, stackTrace: st, category: 'PlayerTransportController');
        }
        if (state.currentSong != null && state.currentSong!.id == songId) {
          _emit(
            state.copyWith(
              playback: state.playback.copyWith(
                currentSong: state.currentSong!.copyWith(isFavorite: isFav),
                errorMessage: null,
              ),
              queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
            ),
          );
          _updateWidgetThrottled?.call(force: true);
        } else if (state.queue.any((s) => s.id == songId)) {
          _emit(state.copyWith(
            queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
            playback: state.playback.copyWith(errorMessage: null),
          ));
        }
      },
    );
  }
}
