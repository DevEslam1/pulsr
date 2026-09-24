// lib/features/player/presentation/widgets/now_playing_queue_view.dart
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class NowPlayingQueueView extends StatefulWidget {
  const NowPlayingQueueView({super.key});

  @override
  State<NowPlayingQueueView> createState() => _NowPlayingQueueViewState();
}

class _NowPlayingQueueViewState extends State<NowPlayingQueueView> {
  final ScrollController _scrollController = ScrollController();
  int _lastScrolledIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveIndex(int index) {
    if (index == _lastScrolledIndex || index < 0) return;
    _lastScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final targetOffset = (index * 68.0 - 100.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocConsumer<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) => prev.currentIndex != curr.currentIndex,
      listener: (context, state) => _scrollToActiveIndex(state.currentIndex),
      buildWhen: (prev, curr) =>
          prev.queue != curr.queue ||
          prev.currentIndex != curr.currentIndex ||
          prev.activeQueueSlot != curr.activeQueueSlot ||
          prev.currentSong?.id != curr.currentSong?.id ||
          prev.isPlaying != curr.isPlaying,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final queue = state.queue;
        final slotKeys = <Key>[];
        final occurrences = <String, int>{};
        for (final s in queue) {
          final id = 'queue_${s.id}_${s.remoteId ?? s.path}';
          final count = (occurrences[id] ?? 0) + 1;
          occurrences[id] = count;
          slotKeys.add(ValueKey('${id}_#$count'));
        }

        return Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadii.r24),
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Queue Slots Switcher Header (Queue 1, Queue 2, Queue 3)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Text(
                      context.l10n.queue,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: AppFontSize.bodyLarge,
                        color: p.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    ...List.generate(3, (slotIndex) {
                      final isSelected = state.activeQueueSlot == slotIndex;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(
                            start: AppSpacing.s6),
                        child: InkWell(
                          onTap: () => cubit.switchQueueSlot(slotIndex),
                          borderRadius: BorderRadius.circular(AppRadii.r10),
                          child: AnimatedContainer(
                            duration: context.motionMs(180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.s6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? p.accent
                                  : p.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(AppRadii.r10),
                              border: Border.all(
                                color: isSelected ? p.accent : p.hairline,
                              ),
                            ),
                            child: Text(
                              'Q${slotIndex + 1}',
                              style: TextStyle(
                                fontSize: AppFontSize.label,
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
                          context.l10n.queueEmpty,
                          style: TextStyle(color: p.textSecondary),
                        ),
                      )
                    : ReorderableListView.builder(
                        scrollController: _scrollController,
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) {
                              final animValue =
                                  Curves.easeInOut.transform(animation.value);
                              final elevation = lerpDouble(0, 8, animValue)!;
                              final scale = lerpDouble(1, 1.02, animValue)!;
                              return Transform.scale(
                                scale: scale,
                                child: Material(
                                  elevation: elevation,
                                  color: p.surfaceContainerHigh
                                      .withValues(alpha: 0.95),
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.35),
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.r16),
                                  child: child,
                                ),
                              );
                            },
                            child: child,
                          );
                        },
                        padding: const EdgeInsets.only(
                            bottom: AppSpacing.lg, top: AppSpacing.xxs),
                        itemCount: queue.length,
                        onReorderItem: (oldIndex, newIndex) {
                          cubit.reorderQueue(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final song = queue[index];
                          final isCurrent = index == state.currentIndex;

                          return Material(
                            key: slotKeys[index],
                            color: Colors.transparent,
                            child: ListTile(
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
                                  if (song.remoteId != null &&
                                      song.remoteId!.isNotEmpty)
                                    PositionedDirectional(
                                      end: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: p.surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: p.accent, width: 1),
                                        ),
                                        child: Icon(Icons.cloud_rounded,
                                            size: 9, color: p.accent),
                                      ),
                                    ),
                                  if (isCurrent)
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.5),
                                        borderRadius:
                                            BorderRadius.circular(AppRadii.r10),
                                      ),
                                      child: Center(
                                        child: NowPlayingIndicator(
                                            color: p.accent),
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
                                  fontSize: AppFontSize.bodySmall,
                                ),
                              ),
                              subtitle: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.label,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isCurrent)
                                    IconButton(
                                      icon: Icon(Icons.close_rounded,
                                          size: 18, color: p.textTertiary),
                                      tooltip: context.l10n.remove,
                                      constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget),
                                      onPressed: () =>
                                          cubit.removeQueueItem(index),
                                    ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Container(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.xs),
                                      constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget),
                                      alignment: Alignment.center,
                                      child: Icon(Icons.drag_handle_rounded,
                                          color: p.textTertiary, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                cubit.playSong(song, queue: queue);
                              },
                            ),
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
