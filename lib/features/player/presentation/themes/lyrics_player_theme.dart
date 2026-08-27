// lib/features/player/presentation/themes/lyrics_player_theme.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
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
                AudioQualityBadge(song: song, activeColor: props.activeColor),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            child: Container(
              decoration: BoxDecoration(
                color: p.surfaceContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: LyricsView(
                lyrics: state.lyrics,
                currentPosition: state.position,
                isLoading: state.isLoadingLyrics,
                activeColor: props.activeColor,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Seek Bar
          PlayerSeekBar(
            position: state.position,
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
  }
}
