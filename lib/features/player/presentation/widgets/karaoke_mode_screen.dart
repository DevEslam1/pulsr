// lib/features/player/presentation/widgets/karaoke_mode_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_visualizer.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../../core/utils/error_logger.dart';

class KaraokeModeScreen extends StatefulWidget {
  const KaraokeModeScreen({super.key});

  @override
  State<KaraokeModeScreen> createState() => _KaraokeModeScreenState();
}

class _KaraokeModeScreenState extends State<KaraokeModeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore the app's edge-to-edge chrome cleanly when leaving karaoke mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final p = context.palette;
    final audibleOffset = context.select<SettingsCubit, Duration>(
      (c) => c.state.audibleLatencyOffset,
    );

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.position != curr.position ||
          prev.currentSong != curr.currentSong ||
          prev.duration != curr.duration ||
          prev.isPlaying != curr.isPlaying ||
          prev.isLoadingLyrics != curr.isLoadingLyrics ||
          prev.lyrics != curr.lyrics,
      builder: (context, state) {
        final rawPos = state.position - audibleOffset;
        // Latency offset can exceed a near-zero position; never show/render a
        // negative time.
        final pos = rawPos.isNegative ? Duration.zero : rawPos;
        final song = state.currentSong;

        // Use the live state only. Falling back to the constructor list showed
        // the PREVIOUS song's lyrics during the window after a track change
        // (state.lyrics is cleared while the new track's lyrics load).
        final effectiveLyrics = state.lyrics;

        // Determine current active line index
        int activeIdx = -1;
        for (int i = 0; i < effectiveLyrics.length; i++) {
          if (pos >= effectiveLyrics[i].timestamp) {
            activeIdx = i;
          } else {
            break;
          }
        }

        final activeLine =
            (activeIdx >= 0 && activeIdx < effectiveLyrics.length)
                ? effectiveLyrics[activeIdx]
                : null;
        final nextLine =
            (activeIdx + 1 >= 0 && activeIdx + 1 < effectiveLyrics.length)
                ? effectiveLyrics[activeIdx + 1]
                : (activeIdx == -1 && effectiveLyrics.isNotEmpty
                    ? effectiveLyrics[0]
                    : null);

        // Real playback progress (replaces the previously hardcoded metric).
        final durationMs = state.duration.inMilliseconds;
        final progressPct = durationMs > 0
            ? ((pos.inMilliseconds / durationMs).clamp(0.0, 1.0) * 100)
                .round()
            : 0;

        return PulsrPagePopScope(
          child: Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.close_rounded, color: p.textPrimary),
                tooltip: context.l10n.close,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                song?.title ?? context.l10n.dspKaraokeMode,
                style: TextStyle(
                    color: p.textPrimary, fontWeight: FontWeight.w700),
              ),
            actions: [
              Container(
                margin: const EdgeInsetsDirectional.only(end: AppSpacing.md),
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadii.r10),
                  border: Border.all(color: p.primary),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timelapse_rounded, size: 16, color: p.primary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '$progressPct%',
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
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
              if (effectiveLyrics.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    state.isLoadingLyrics
                        ? context.l10n.dspLoadingLyrics
                        : context.l10n.noLyricsFound,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              // Active Lyric Line with Glow & Tap-to-Seek
              if (activeLine != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<PlayerCubit>().seek(activeLine.timestamp);
                    },
                    borderRadius: BorderRadius.circular(AppRadii.r16),
                    splashColor: p.primary.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(

                          vertical: AppSpacing.xs, horizontal: AppSpacing.sm),
                      child: Text(
                        activeLine.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFontSize.displayLarge,
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
                )
              else if (effectiveLyrics.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_note_rounded,
                          size: 32, color: p.primary.withValues(alpha: 0.7)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '•••',
                        style: TextStyle(
                          fontSize: AppFontSize.display,
                          fontWeight: FontWeight.w700,
                          color: p.textTertiary,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              // Next Upcoming Line (Tappable)
              if (nextLine != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<PlayerCubit>().seek(nextLine.timestamp);
                    },
                    borderRadius: BorderRadius.circular(AppRadii.r12),
                    splashColor: p.primary.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(

                          vertical: AppSpacing.s6, horizontal: AppSpacing.sm),
                      child: Text(
                        nextLine.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w600,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),

              // Audio / Mic Level Visualizer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AudioVisualizer(
                  style: VisualizerStyle.wave,
                  color: p.primary,
                  height: 60,
                  isPlaying: state.isPlaying,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Bottom Progress Bar & Time
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Formatters.formatDuration(pos),
                      style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.bodySmall),
                    ),
                    Text(
                      Formatters.formatDuration(state.duration),
                      style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
        );
      },
    );
    } catch (e, st) {
      ErrorLogger.log('KaraokeModeScreen build failed',
          error: e, stackTrace: st, category: 'Karaoke');
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      rethrow;
    }
  }
}
