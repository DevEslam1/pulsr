// lib/features/player/presentation/themes/lyrics_player_theme.dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';

class LyricsPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const LyricsPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final p = context.palette;
    final song = state.currentSong;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoPane = context.isTwoPane || constraints.maxWidth >= 680;

        final lyricsContainer = Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: LyricsView(
            lyrics: state.lyrics,
            isLoading: state.isLoadingLyrics,
            activeColor: props.activeColor,
          ),
        );

        final controlsColumn = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isTwoPane && song != null) ...[
              Center(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: props.activeColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CachedArtwork(
                    id: song.id,
                    remoteUrl: song.remoteArtworkUrl,
                    type: ArtworkType.AUDIO,
                    size: 140,
                    borderRadius: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              song?.title ?? 'No Track Playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              song?.artist ?? 'Unknown Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: p.textSecondary,
              ),
            ),
            if (song != null) ...[
              const SizedBox(height: 6),
              AudioQualityBadge(song: song, activeColor: props.activeColor),
            ],
            const SizedBox(height: 12),
            PlayerSeekBar(
              duration: state.duration,
              activeColor: props.activeColor,
              songId: song?.id,
              filePath: song?.path,
              onSeek: (pos) => cubit.seek(pos),
            ),
            const SizedBox(height: 8),
            PlayerControls(
              isPlaying: state.isPlaying,
              isShuffle: state.isShuffle,
              repeatMode: state.repeatMode,
              primaryColor: props.activeColor,
              mainButtonSize: isTwoPane ? 56 : 64,
              onPlayPause: () => cubit.togglePlayPause(),
              onNext: () => cubit.next(),
              onPrevious: () => cubit.previous(),
              onToggleShuffle: () => cubit.toggleShuffle(),
              onToggleRepeat: () => cubit.toggleRepeat(),
            ),
          ],
        );

        if (isTwoPane) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    child: controlsColumn,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 6,
                  child: lyricsContainer,
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Compact Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.title ?? 'No Track Playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          song?.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (song != null) ...[
                    AudioQualityBadge(
                        song: song, activeColor: props.activeColor),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mic_rounded, size: 14, color: p.primary),
                        const SizedBox(width: 4),
                        Text(
                          'KARAOKE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: p.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Full Immersion Lyrics View
              Expanded(
                child: lyricsContainer,
              ),
              const SizedBox(height: 16),

              // Seek Bar
              PlayerSeekBar(
                duration: state.duration,
                activeColor: props.activeColor,
                songId: song?.id,
                filePath: song?.path,
                onSeek: (pos) => cubit.seek(pos),
              ),
              const SizedBox(height: 10),

              // Playback Controls
              PlayerControls(
                isPlaying: state.isPlaying,
                isShuffle: state.isShuffle,
                repeatMode: state.repeatMode,
                primaryColor: props.activeColor,
                onPlayPause: () => cubit.togglePlayPause(),
                onNext: () => cubit.next(),
                onPrevious: () => cubit.previous(),
                onToggleShuffle: () => cubit.toggleShuffle(),
                onToggleRepeat: () => cubit.toggleRepeat(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
