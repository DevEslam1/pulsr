// lib/features/queue/presentation/queue_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/di/injection.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.queue),
        actions: [
          BlocBuilder<PlayerCubit, PlayerState>(builder: (context, state) {
            if (state.queue.isEmpty) return const SizedBox.shrink();
            return PopupMenuButton<String>(
              onSelected: (v) async {
                final cubit = context.read<PlayerCubit>();
                switch (v) {
                  case 'clear':
                    final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(context.l10n.queue), content: const Text('Clear entire queue?'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear'))]));
                    if (confirm == true) {
                      for (int i = state.queue.length - 1; i >= 0; i--) {
                        if (state.queue[i].id != state.currentSong?.id) await cubit.removeQueueItem(i);
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
                    final nameCtrl = TextEditingController(text: 'Queue ${DateTime.now().toIso8601String().substring(0,10)}');
                    final name = await showDialog<String>(context: context, builder: (c) => AlertDialog(title: const Text('Save as playlist'), content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Playlist name'), autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, nameCtrl.text.trim()), child: const Text('Save'))]));
                    if (name != null && name.isNotEmpty) {
                      if (!context.mounted) break;
                      try {
                        final repo = getIt<IMusicRepository>();
                        final createRes = await repo.createPlaylist(name);
                        await createRes.fold(
                          (failure) async {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to create playlist: ${failure.message}')),
                            );
                          },
                          (playlistId) async {
                            final ids = state.queue.map((s) => s.id).toList();
                            if (ids.isEmpty) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Queue saved as "$name" (0 tracks)')),
                              );
                              return;
                            }
                            final addRes = await repo.addSongsToPlaylist(playlistId, ids);
                            if (!context.mounted) return;
                            addRes.fold(
                              (failure) => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to add songs: ${failure.message}')),
                              ),
                              (_) => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Queue saved as "$name" (${state.queue.length} tracks)')),
                              ),
                            );
                          },
                        );
                      } catch (e) {
                        if (!context.mounted) break;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error saving playlist: $e')),
                        );
                      }
                    }
                    break;
                }
              },
              itemBuilder: (c) => [
                const PopupMenuItem(value: 'shuffle', child: Row(children: [Icon(Icons.shuffle), SizedBox(width: 8), Text('Shuffle queue')])),
                const PopupMenuItem(value: 'save', child: Row(children: [Icon(Icons.playlist_add), SizedBox(width: 8), Text('Save as playlist')])),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'clear', child: Row(children: [Icon(Icons.clear_all, color: Colors.red), SizedBox(width: 8), Text('Clear queue', style: TextStyle(color: Colors.red))])),
              ],
            );
          }),
        ],
      ),
      body: BlocBuilder<PlayerCubit, PlayerState>(
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
                      child: const Icon(Icons.delete_rounded, color: Colors.red),
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
    );
  }
}
