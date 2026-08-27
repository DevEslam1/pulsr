// lib/features/player/presentation/widgets/karaoke_mode_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_visualizer.dart';

class KaraokeModeScreen extends StatelessWidget {
  final List<LyricsLine> lyrics;

  const KaraokeModeScreen({super.key, required this.lyrics});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final pos = state.position;
        final song = state.currentSong;

        // Determine current active line index
        int activeIdx = 0;
        for (int i = 0; i < lyrics.length; i++) {
          if (pos >= lyrics[i].timestamp) {
            activeIdx = i;
          } else {
            break;
          }
        }

        final activeLine = lyrics.isNotEmpty ? lyrics[activeIdx] : null;
        final nextLine = activeIdx + 1 < lyrics.length ? lyrics[activeIdx + 1] : null;

        return Scaffold(
          backgroundColor: const Color(0xFF08090E),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              song?.title ?? 'Karaoke Mode',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.primary),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 16, color: p.primary),
                    const SizedBox(width: 4),
                    Text(
                      'VOCAL SCORE: 96%',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: p.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const Spacer(),
              // Active Lyric Line with Glow & Tap-to-Seek
              if (activeLine != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<PlayerCubit>().seek(activeLine.timestamp);
                    },
                    borderRadius: BorderRadius.circular(16),
                    splashColor: p.primary.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Text(
                        activeLine.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: p.primary,
                          shadows: [
                            Shadow(
                              color: p.primary.withValues(alpha: 0.8),
                              blurRadius: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              // Next Upcoming Line (Tappable)
              if (nextLine != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<PlayerCubit>().seek(nextLine.timestamp);
                    },
                    borderRadius: BorderRadius.circular(12),
                    splashColor: p.primary.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: Text(
                        nextLine.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),

              // Audio / Mic Level Visualizer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AudioVisualizer(
                  style: VisualizerStyle.wave,
                  color: p.primary,
                  height: 60,
                  isPlaying: state.isPlaying,
                ),
              ),
              const SizedBox(height: 16),

              // Bottom Progress Bar & Time
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Formatters.formatDuration(pos),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                    ),
                    Text(
                      Formatters.formatDuration(state.duration),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
