// lib/features/queue/presentation/queue_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/playlist_suggestions_service.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const PulsrBackButton(),
          title: Text(context.l10n.queue),
        actions: [
          BlocSelector<PlayerCubit, PlayerState, bool>(
            selector: (state) => state.queue.isEmpty,
            builder: (context, queueIsEmpty) {
            if (queueIsEmpty) return const SizedBox.shrink();
            return PopupMenuButton<String>(
              onSelected: (v) async {
                final cubit = context.read<PlayerCubit>();
                final playerState = cubit.state;
                switch (v) {
                  case 'clear':
                    final confirm = await PulsrDialogHelper.showConfirmDialog(
                      context,
                      title: context.l10n.queue,
                      message: context.l10n.clearQueueConfirm,
                      icon: Icons.clear_all_rounded,
                      confirmLabel: context.l10n.clear,
                      isDestructive: true,
                    );
                    if (confirm == true && context.mounted) {
                      HapticFeedback.mediumImpact();
                      final removed = List.of(playerState.queue);
                      final removedIndex = playerState.currentIndex;
                      await cubit.clearQueue();
                      if (context.mounted) {
                        // Undo for destructive clear (gap 10-03).
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.queueCleared),
                            action: SnackBarAction(
                              label: context.l10n.undo,
                              onPressed: () {
                                try {
                                  cubit.restoreQueue(removed, removedIndex);
                                } catch (e, st) {
                                  ErrorLogger.log('Queue undo failed',
                                      error: e,
                                      stackTrace: st,
                                      category: 'Queue');
                                }
                              },
                            ),
                          ),
                        );
                      }
                    }
                    break;
                  case 'shuffle':
                    HapticFeedback.selectionClick();
                    final shuffled = List.of(playerState.queue)..shuffle();
                    // Rebuild queue with shuffled order centered on current
                    final current = playerState.currentSong;
                    if (current != null) await cubit.playSong(current, queue: shuffled);
                    break;
                  case 'autodj':
                    // Auto-DJ: append tracks similar to the current song.
                    final seed = playerState.currentSong;
                    if (seed == null) break;
                    final songsRes =
                        await getIt<GetSongsUseCase>().getAllSongs();
                    if (!context.mounted) break;
                    final all = songsRes.fold(
                        (l) => <SongsTableData>[], (r) => r);
                    if (all.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.autoDjEmpty)),
                      );
                      break;
                    }
                    final exclude =
                        playerState.queue.map((s) => s.id).toSet();
                    final dj = getIt<PlaylistSuggestionsService>()
                        .buildAutoDjQueue(seed, all,
                            limit: 10, excludeIds: exclude);
                    if (!context.mounted) break;
                    if (dj.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.autoDjEmpty)),
                      );
                    } else {
                      await cubit.addAllToQueue(dj);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(context.l10n.autoDjAdded(dj.length))),
                        );
                      }
                    }
                    break;
                  case 'save':
                    final defaultName =
                        '${context.l10n.queue} ${DateTime.now().toIso8601String().substring(0, 10)}';
                    final name = await PulsrDialogHelper.showInputDialog(
                      context,
                      title: context.l10n.saveAsPlaylist,
                      initialText: defaultName,
                      icon: Icons.playlist_add_rounded,
                      confirmLabel: context.l10n.save,
                      cancelLabel: context.l10n.cancel,
                    );
                    if (name != null && name.isNotEmpty && context.mounted) {
                      final songIds = playerState.queue.map((s) => s.id).toList();
                      final result = await getIt<PlaylistUseCases>().createPlaylist(name);
                      result.fold(
                        (failure) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${context.l10n.saveFailed}: ${failure.message}')),
                            );
                          }
                        },
                        (playlistId) async {
                          await getIt<PlaylistUseCases>().addSongsToPlaylist(playlistId, songIds);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(context.l10n.queueSaved)),
                            );
                          }
                        },
                      );
                    }
                    break;
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'shuffle', child: Row(children: [const Icon(Icons.shuffle), const SizedBox(width: AppSpacing.xs), Text(context.l10n.shuffle)])),
                PopupMenuItem(value: 'autodj', child: Row(children: [const Icon(Icons.auto_awesome_rounded), const SizedBox(width: AppSpacing.xs), Text(context.l10n.autoMix)])),
                PopupMenuItem(value: 'save', child: Row(children: [const Icon(Icons.playlist_add), const SizedBox(width: AppSpacing.xs), Text(context.l10n.saveAsPlaylist)])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'clear', child: Row(children: [Icon(Icons.clear_all, color: p.error), const SizedBox(width: AppSpacing.xs), Text(context.l10n.clearQueueConfirm.split('?').first, style: TextStyle(color: p.error))])),
              ],
            );
          }),
        ],
      ),
      body: BlocBuilder<PlayerCubit, PlayerState>(
        buildWhen: (prev, curr) =>
            prev.queue != curr.queue ||
            prev.currentIndex != curr.currentIndex ||
            prev.currentSong?.id != curr.currentSong?.id ||
            prev.isPlaying != curr.isPlaying,
        builder: (context, state) {
          final queue = state.queue;
          final currentSong = state.currentSong;

          if (queue.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.queue_music_rounded,
              title: context.l10n.queue,
              subtitle: context.l10n.noSongsSubtitle,
              primaryActionLabel: context.l10n.navLibrary,
              primaryActionIcon: Icons.library_music_rounded,
              onPrimaryAction: () {
                context.go('/library');
              },
            );
          }

          final slotKeys = <Key>[];
          final occurrences = <String, int>{};
          for (final s in queue) {
            final id = 'queue_${s.id}_${s.remoteId ?? s.path}';
            final count = (occurrences[id] ?? 0) + 1;
            occurrences[id] = count;
            slotKeys.add(ValueKey('${id}_#$count'));
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: ReorderableListView.builder(
                padding: EdgeInsets.symmetric(

                  horizontal: context.pagePadding,
                  vertical: AppSpacing.xs,
                ).copyWith(bottom: AppSpacing.scrollBottom),
                itemCount: queue.length,
                onReorderItem: (oldIdx, newIdx) {
                  if (oldIdx == newIdx) return;
                  context.read<PlayerCubit>().reorderQueue(oldIdx, newIdx);
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.queue),
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: context.l10n.undo,
                        onPressed: () {
                          context.read<PlayerCubit>().reorderQueue(newIdx, oldIdx);
                        },
                      ),
                    ),
                  );
                },
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isCurrent = song.id == currentSong?.id;

                  return Container(
                    key: slotKeys[index],
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.cardRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: p.isDark ? 0.12 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      clipBehavior: Clip.antiAlias,
                      color: isCurrent ? p.accentContainer : p.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.cardRadius,
                        side: BorderSide(
                          color: isCurrent ? p.accent : p.hairline,
                          width: 1,
                        ),
                      ),
                      child: Semantics(
                        button: true,
                        label: '${song.title} by ${song.artist}',
                        child: ListTile(
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CachedArtwork(
                                id: song.id,
                                remoteUrl: song.remoteArtworkUrl,
                                type: ArtworkType.AUDIO,
                                size: 44,
                                borderRadius: 10,
                              ),
                              if (song.remoteId != null &&
                                  song.remoteId!.isNotEmpty)
                                PositionedDirectional(
                                  end: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: p.surface,
                                      shape: BoxShape.circle,
                                      border:
                                          Border.all(color: p.accent, width: 1),
                                    ),
                                    child: Icon(Icons.cloud_rounded,
                                        size: 10, color: p.accent),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? p.accent : p.textPrimary,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                              fontSize: AppFontSize.body,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              if (song.remoteId != null && song.remoteId!.isNotEmpty) ...[
                                Icon(
                                  Icons.cloud_outlined,
                                  size: 13,
                                  color: p.accent.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                              ],
                              Expanded(
                                child: Text(
                                  '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCurrent) ...[
                                Icon(
                                  Icons.graphic_eq_rounded,
                                  color: p.accent,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                              ],
                              IconButton(
                                icon: Icon(Icons.close_rounded, color: p.textTertiary, size: 20),
                                tooltip: context.l10n.delete,
                                constraints: const BoxConstraints(
                                  minWidth: AppSpacing.minTouchTarget,
                                  minHeight: AppSpacing.minTouchTarget,
                                ),
                                onPressed: () {
                                  HapticFeedback.heavyImpact();
                                  context.read<PlayerCubit>().removeQueueItem(index);
                                },
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Semantics(
                                  label: 'Reorder ${song.title}',
                                  child: Container(
                                    padding: const EdgeInsets.all(AppSpacing.xs),
                                    constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: p.textTertiary.withValues(alpha: 0.5),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            context
                                .read<PlayerCubit>()
                                .playSong(song, queue: queue);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}
}
