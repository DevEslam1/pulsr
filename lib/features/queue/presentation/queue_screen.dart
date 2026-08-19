// lib/features/queue/presentation/queue_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/formatters.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playing Queue'),
      ),
      body: BlocBuilder<PlayerCubit, PlayerState>(
        builder: (context, state) {
          final queue = state.queue;
          final currentSong = state.currentSong;

          if (queue.isEmpty) {
            return const Center(
              child: Text(
                'Queue is empty',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final song = queue[index];
              final isCurrent = song.id == currentSong?.id;

              return Container(
                key: ValueKey(song.id),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.primary.withValues(alpha: 0.12) : AppColors.card,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(
                    color: isCurrent ? AppColors.primary.withValues(alpha: 0.5) : AppColors.outline,
                    width: 1,
                  ),
                ),
                child: ListTile(
                  leading: CachedArtwork(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    size: 44,
                    borderRadius: 10,
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(
                    isCurrent ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                    color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                  ),
                  onTap: () {
                    context.read<PlayerCubit>().playSong(song, queue: queue);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
