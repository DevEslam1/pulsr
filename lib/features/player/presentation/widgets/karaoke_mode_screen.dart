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

  /// O(n) scan mapping a position to the active line index (last line whose
  /// timestamp is <= position). Used as a [BlocSelector] output so the lyric
  /// subtree only rebuilds when the active line actually changes.
  static int _activeIndexOf(Duration pos, List<LyricsLine> lines) {
    int activeIdx = 0;
    for (int i = 0; i < lines.length; i++) {
      if (pos >= lines[i].timestamp) {
        activeIdx = i;
      } else {
        break;
      }
    }
    return activeIdx;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Gate the scaffold against position ticks: only song/isPlaying/duration
    // changes rebuild it. The active line and the elapsed time subscribe to
    // position themselves via [BlocSelector] leaves below.
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.currentSong?.id != b.currentSong?.id ||
          a.currentSong?.title != b.currentSong?.title ||
          a.isPlaying != b.isPlaying ||
          a.duration != b.duration,
      builder: (context, state) {
        final song = state.currentSong;

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
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: p.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const Spacer(),
              // Active / upcoming lyric lines — rebuild only when the active
              // line index changes, not on every position tick.
              BlocSelector<PlayerCubit, PlayerState,
                  ({LyricsLine? active, LyricsLine? next})>(
                selector: (s) {
                  if (lyrics.isEmpty) {
                    return (active: null, next: null);
                  }
                  final idx = _activeIndexOf(s.position, lyrics);
                  return (
                    active: lyrics[idx],
                    next: idx + 1 < lyrics.length ? lyrics[idx + 1] : null,
                  );
                },
                builder: (context, lines) {
                  final activeLine = lines.active;
                  final nextLine = lines.next;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Active Lyric Line with Glow & Tap-to-Seek
                      if (activeLine != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              context
                                  .read<PlayerCubit>()
                                  .seek(activeLine.timestamp);
                            },
                            borderRadius: BorderRadius.circular(16),
                            splashColor: p.primary.withValues(alpha: 0.2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
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
                              context
                                  .read<PlayerCubit>()
                                  .seek(nextLine.timestamp);
                            },
                            borderRadius: BorderRadius.circular(12),
                            splashColor: p.primary.withValues(alpha: 0.15),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 12),
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
                    ],
                  );
                },
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

              // Bottom Progress Bar & Time — position-driven leaf so the
              // elapsed label still ticks without rebuilding the scaffold.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: BlocSelector<PlayerCubit, PlayerState,
                    ({Duration position, Duration duration})>(
                  selector: (s) => (position: s.position, duration: s.duration),
                  builder: (context, progress) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Formatters.formatDuration(progress.position),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13),
                        ),
                        Text(
                          Formatters.formatDuration(progress.duration),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13),
                        ),
                      ],
                    );
                  },
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
