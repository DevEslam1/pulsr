// lib/features/playlists/cubit/playlist_state.dart
import '../../../data/db/app_database.dart';

class PlaylistState {
  final List<PlaylistsTableData> playlists;
  final List<SongsTableData> currentPlaylistSongs;
  final bool isLoading;
  final String? errorMessage;

  const PlaylistState({
    this.playlists = const [],
    this.currentPlaylistSongs = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  PlaylistState copyWith({
    List<PlaylistsTableData>? playlists,
    List<SongsTableData>? currentPlaylistSongs,
    bool? isLoading,
    String? errorMessage,
  }) {
    return PlaylistState(
      playlists: playlists ?? this.playlists,
      currentPlaylistSongs: currentPlaylistSongs ?? this.currentPlaylistSongs,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
