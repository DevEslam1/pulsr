// lib/features/playlist_detail/presentation/playlist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../player/cubit/player_cubit.dart';
import '../../smart_playlist_builder/smart_playlist_builder_screen.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final PlaylistsTableData playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  Future<void> _exportPlaylist(BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export an empty playlist.')),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    final file = await exportUseCase.exportToFile(playlist.name, songs);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported M3U to ${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePlaylist(BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot share an empty playlist.')),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    final file = await exportUseCase.exportToFile(playlist.name, songs);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'audio/x-mpegurl')],
      text: 'Playlist: ${playlist.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MusicRepository>();
    final playlistUseCases = context.read<PlaylistUseCases>();

    final Stream<List<SongsTableData>> songsStream = playlist.isSmart && playlist.smartCriteria != null
        ? playlistUseCases.watchSmartPlaylistSongs(SmartCriteria.fromJsonString(playlist.smartCriteria!))
        : repository.watchPlaylistSongs(playlist.id).map((res) => res.fold((l) => <SongsTableData>[], (r) => r));

    return StreamBuilder<List<SongsTableData>>(
      stream: songsStream,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? [];

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                if (playlist.isSmart) ...[
                  const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(playlist.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            actions: [
              if (playlist.isSmart)
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: AppColors.primary),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SmartPlaylistBuilderScreen(initialPlaylist: playlist),
                      ),
                    );
                  },
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  switch (value) {
                    case 'export':
                      await _exportPlaylist(context, songs);
                      break;
                    case 'share':
                      await _sharePlaylist(context, songs);
                      break;
                    case 'delete':
                      await repository.deletePlaylist(playlist.id);
                      if (context.mounted) Navigator.pop(context);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.download_rounded, color: AppColors.primary, size: 20),
                        SizedBox(width: 12),
                        Text('Export as M3U'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_rounded, color: AppColors.primary, size: 20),
                        SizedBox(width: 12),
                        Text('Share Playlist'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                        SizedBox(width: 12),
                        Text('Delete Playlist', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : songs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          playlist.isSmart
                              ? 'No tracks match the rules for this smart playlist.'
                              : 'No tracks in this playlist yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        // Header Controls
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    context.read<PlayerCubit>().playSong(songs.first, queue: songs);
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Play All'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    side: const BorderSide(color: AppColors.outline),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () {
                                    final shuffled = List<SongsTableData>.from(songs)..shuffle();
                                    context.read<PlayerCubit>().playSong(shuffled.first, queue: shuffled);
                                  },
                                  icon: const Icon(Icons.shuffle_rounded, color: AppColors.primary),
                                  label: const Text('Shuffle'),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Tracks List
                        ...songs.map((song) {
                          return ListTile(
                            leading: CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 44, borderRadius: 10),
                            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            trailing: playlist.isSmart
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppColors.textSecondary),
                                    onPressed: () {
                                      repository.removeSongFromPlaylist(playlist.id, song.id);
                                    },
                                  ),
                            onTap: () {
                              context.read<PlayerCubit>().playSong(song, queue: songs);
                            },
                          );
                        }),
                      ],
                    ),
        );
      },
    );
  }
}
