// lib/features/playlist_detail/presentation/playlist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../player/cubit/player_cubit.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final PlaylistsTableData playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MusicRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: () async {
              await repository.deletePlaylist(playlist.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: StreamBuilder<List<SongsTableData>>(
        stream: repository.watchPlaylistSongs(playlist.id),
        builder: (context, snapshot) {
          final songs = snapshot.data ?? [];

          if (songs.isEmpty) {
            return const Center(
              child: Text('No tracks in this playlist yet.', style: TextStyle(color: AppColors.textSecondary)),
            );
          }

          return ListView(
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
                  trailing: IconButton(
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
          );
        },
      ),
    );
  }
}
