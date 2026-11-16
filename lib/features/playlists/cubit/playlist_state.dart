// lib/features/playlists/cubit/playlist_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/errors/app_error.dart';
import '../../../data/db/app_database.dart';

part 'playlist_state.freezed.dart';

@freezed
abstract class PlaylistState with _$PlaylistState {
  const PlaylistState._();

  const factory PlaylistState({
    @Default([]) List<PlaylistsTableData> playlists,
    @Default([]) List<SongsTableData> currentPlaylistSongs,
    @Default({}) Map<int, int> smartPlaylistCounts,
    @Default(false) bool isLoading,
    AppError? error,
  }) = _PlaylistState;

  /// Display copy for the typed failure (existing UI contract).
  String? get errorMessage => error?.userMessage;
}
