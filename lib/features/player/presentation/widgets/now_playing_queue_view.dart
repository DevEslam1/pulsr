// lib/features/player/presentation/widgets/now_playing_queue_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class NowPlayingQueueView extends StatelessWidget {
  const NowPlayingQueueView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final queue = state.queue;

        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: AppRadii.cardRadius,
          ),
          child: Column(
            children: [
              // Queue Slots Switcher Header (Queue 1, Queue 2, Queue 3)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Text(
                      'Queue',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const Spacer(),
                    ...List.generate(3, (slotIndex) {
                      final isSelected = state.activeQueueSlot == slotIndex;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () => cubit.switchQueueSlot(slotIndex),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.outline,
                              ),
                            ),
                            child: Text(
                              'Q${slotIndex + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const Divider(color: AppColors.outline, height: 1),

              // Reorderable Queue List
              Expanded(
                child: queue.isEmpty
                    ? const Center(
                        child: Text(
                          'Queue is empty',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 24, top: 4),
                        itemCount: queue.length,
                        onReorderItem: (oldIndex, newIndex) {
                          cubit.reorderQueue(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final song = queue[index];
                          final isCurrent = index == state.currentIndex;

                          return ListTile(
                            key: ValueKey('queue_${song.id}_$index'),
                            leading: CachedArtwork(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              size: 40,
                              borderRadius: 8,
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isCurrent
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrent)
                                  const Icon(Icons.equalizer_rounded,
                                      color: AppColors.primary, size: 20)
                                else
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18,
                                        color: AppColors.textSecondary),
                                    onPressed: () =>
                                        cubit.removeQueueItem(index),
                                  ),
                                const Icon(Icons.drag_handle_rounded,
                                    color: AppColors.textSecondary, size: 20),
                              ],
                            ),
                            onTap: () {
                              cubit.playSong(song, queue: queue);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
