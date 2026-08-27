// lib/features/player/presentation/themes/waveform_player_theme.dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';

class WaveformPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const WaveformPlayerTheme({super.key, required this.props});

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
          const SizedBox(height: 12),
          // Waveform & Artwork Center Stack
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Full Screen Wave Visualizer Backdrop
                Positioned.fill(
                  child: AudioVisualizer(
                    style: VisualizerStyle.wave,
                    color: p.primary.withValues(alpha: 0.6),
                    isPlaying: state.isPlaying,
                  ),
                ),
                // Center Album Art Floating Disc
                if (song != null)
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: p.primary.withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedArtwork(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      size: 170,
                      borderRadius: 999,
                      fallbackIcon: Icons.music_note_rounded,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Track Title & Artist
          Text(
            song?.title ?? 'No Track Playing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
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
              fontSize: 14,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Audio Quality & DAC Badge
          if (song != null)
            AudioQualityBadge(song: song, activeColor: props.activeColor),
          const SizedBox(height: 12),

          // Waveform Seek Bar
          PlayerSeekBar(
            position: state.position,
            duration: state.duration,
            activeColor: props.activeColor,
            songId: song?.id,
            filePath: song?.path,
            onSeek: (pos) => cubit.seek(pos),
          ),
          const SizedBox(height: 14),

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
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
