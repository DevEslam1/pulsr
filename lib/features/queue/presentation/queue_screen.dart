// lib/features/queue/presentation/queue_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/utils/formatters.dart';
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

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final song = queue[index];
              final isCurrent = song.id == currentSong?.id;

              return Container(
                key: ValueKey(song.id),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                    trailing: Icon(
                      isCurrent ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                      color: isCurrent ? p.accent : p.textTertiary,
                    ),
                    onTap: () {
                      context.read<PlayerCubit>().playSong(song, queue: queue);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
