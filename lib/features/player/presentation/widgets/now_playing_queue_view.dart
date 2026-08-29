// lib/features/player/presentation/widgets/now_playing_queue_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/utils/list_content_diff.dart';
import '../../cubit/player_state.dart';

class NowPlayingQueueView extends StatelessWidget {
  const NowPlayingQueueView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      // Queue view only cares about queue contents + slot/index; position ticks
      // (10Hz while playing) must not rebuild this subtree.
      buildWhen: (a, b) =>
          listContentDiffers(a.queue, b.queue) ||
          a.queue.length != b.queue.length ||
          a.activeQueueSlot != b.activeQueueSlot ||
          a.currentIndex != b.currentIndex ||
          a.currentSong?.id != b.currentSong?.id,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final queue = state.queue;

        return Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Queue Slots Switcher Header (Queue 1, Queue 2, Queue 3)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      'Queue',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: p.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    ...List.generate(3, (slotIndex) {
                      final isSelected = state.activeQueueSlot == slotIndex;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () => cubit.switchQueueSlot(slotIndex),
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? p.accent
                                  : p.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? p.accent : p.hairline,
                              ),
                            ),
                            child: Text(
                              'Q${slotIndex + 1}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color:
                                    isSelected ? Colors.white : p.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              Divider(color: p.hairline, height: 1),

              // Reorderable Queue List
              Expanded(
                child: queue.isEmpty
                    ? Center(
                        child: Text(
                          'Queue is empty',
                          style: TextStyle(color: p.textSecondary),
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
                            leading: Stack(
                              alignment: Alignment.center,
                              children: [
                                CachedArtwork(
                                  id: song.id,
                                  remoteUrl: song.remoteArtworkUrl,
                                  type: ArtworkType.AUDIO,
                                  size: 42,
                                  borderRadius: 10,
                                ),
                                if (isCurrent)
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child:
                                          NowPlayingIndicator(color: p.accent),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isCurrent ? p.accent : p.textPrimary,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isCurrent)
                                  IconButton(
                                    icon: Icon(Icons.close_rounded,
                                        size: 18, color: p.textTertiary),
                                    onPressed: () =>
                                        cubit.removeQueueItem(index),
                                  ),
                                Icon(Icons.drag_handle_rounded,
                                    color: p.textTertiary, size: 20),
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
