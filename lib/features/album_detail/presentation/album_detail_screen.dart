// lib/features/album_detail/presentation/album_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../player/cubit/player_cubit.dart';

import '../../../core/errors/failures.dart';

class AlbumDetailScreen extends StatelessWidget {
  final AlbumsTableData album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MusicRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(album.title),
      ),
      body: StreamBuilder<Result<List<SongsTableData>>>(
        stream: repository.watchAlbumSongs(album.id),
        builder: (context, snapshot) {
          final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              const SizedBox(height: 16),
              Center(
                child: Hero(
                  tag: 'album_${album.id}',
                  child: CachedArtwork(
                    id: album.id,
                    type: ArtworkType.ALBUM,
                    size: 200,
                    borderRadius: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  album.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '${album.artist} • ${Formatters.formatTrackCount(songs.length)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons (Play All, Shuffle)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: songs.isNotEmpty
                            ? () {
                                context.read<PlayerCubit>().playSong(songs.first, queue: songs);
                              }
                            : null,
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
                        onPressed: songs.isNotEmpty
                            ? () {
                                final shuffled = List<SongsTableData>.from(songs)..shuffle();
                                context.read<PlayerCubit>().playSong(shuffled.first, queue: shuffled);
                              }
                            : null,
                        icon: const Icon(Icons.shuffle_rounded, color: AppColors.primary),
                        label: const Text('Shuffle'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Track List
              ...songs.asMap().entries.map((entry) {
                final index = entry.key;
                final song = entry.value;
                return ListTile(
                  leading: SizedBox(
                    width: 28,
                    child: Center(
                      child: Text(
                        '${song.trackNumber ?? index + 1}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    Formatters.formatDuration(Duration(milliseconds: song.durationMs)),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onPressed: () {},
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
