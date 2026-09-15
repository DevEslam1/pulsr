// lib/features/queue/presentation/queue_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import '../../../domain/usecases/playlist_usecases.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';

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
          BlocBuilder<PlayerCubit, PlayerState>(
            buildWhen: (prev, curr) =>
                prev.queue.isEmpty != curr.queue.isEmpty ||
                prev.queue != curr.queue,
            builder: (context, state) {
            if (state.queue.isEmpty) return const SizedBox.shrink();
            return PopupMenuButton<String>(
              onSelected: (v) async {
                final cubit = context.read<PlayerCubit>();
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
                      final removed = List.of(state.queue);
                      final removedIndex = state.currentIndex;
                      await cubit.clearQueue();
                      if (context.mounted) {
                        // Undo for destructive clear (gap 10-03).
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.clearQueueConfirm),
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
                    final shuffled = List.of(state.queue)..shuffle();
                    // Rebuild queue with shuffled order centered on current
                    final current = state.currentSong;
                    if (current != null) await cubit.playSong(current, queue: shuffled);
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
                      final songIds = state.queue.map((s) => s.id).toList();
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
                PopupMenuItem(value: 'shuffle', child: Row(children: [const Icon(Icons.shuffle), const SizedBox(width: 8), Text(context.l10n.shuffle)])),
                PopupMenuItem(value: 'save', child: Row(children: [const Icon(Icons.playlist_add), const SizedBox(width: 8), Text(context.l10n.saveAsPlaylist)])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'clear', child: Row(children: [Icon(Icons.clear_all, color: p.error), const SizedBox(width: 8), Text(context.l10n.clearQueueConfirm.split('?').first, style: TextStyle(color: p.error))])),
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
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: ReorderableListView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: context.pagePadding,
                  vertical: 8,
                ).copyWith(bottom: 160),
                itemCount: queue.length,
                // ignore: deprecated_member_use — onReorderItem is 3.41+; keep onReorder for stable channel compat
                onReorder: (oldIdx, newIdx) => context.read<PlayerCubit>().reorderQueue(oldIdx, newIdx),
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isCurrent = song.id == currentSong?.id;

                  return Dismissible(
                    key: ValueKey('${song.id}-$index'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: AppRadii.cardRadius),
                      child: Icon(Icons.delete_rounded, color: p.error),
                    ),
                    onDismissed: (_) => context.read<PlayerCubit>().removeQueueItem(index),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Material(
                        color: isCurrent ? p.accentContainer : p.surfaceContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.cardRadius,
                          side: BorderSide(
                            color: isCurrent ? p.accent : p.hairline,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 44,
                            borderRadius: 10,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? p.accent : p.textPrimary,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: p.textSecondary, fontSize: 12),
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              isCurrent
                                  ? Icons.graphic_eq_rounded
                                  : Icons.music_note_rounded,
                              color: isCurrent ? p.accent : p.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.drag_handle_rounded, color: p.textTertiary.withValues(alpha: 0.5), size: 18),
                          ]),
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
