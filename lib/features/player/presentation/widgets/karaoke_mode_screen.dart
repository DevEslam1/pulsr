// lib/features/player/presentation/widgets/karaoke_mode_screen.dart
import 'dart:math' as math;
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
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/error_logger.dart';

class KaraokeModeScreen extends StatefulWidget {
  const KaraokeModeScreen({super.key});

  @override
  State<KaraokeModeScreen> createState() => _KaraokeModeScreenState();
}

class _KaraokeModeScreenState extends State<KaraokeModeScreen>
    with WidgetsBindingObserver {
  // B9: pitch shift uses the real pitch API (setPlaybackPitch, 0.5..2.0) rather
  // than setSpeed, which changed tempo. The cubic range keeps the multiplier in
  // the cubit's supported window.
  static const int _minPitchSemitones = -12;
  static const int _maxPitchSemitones = 12;
  int _pitchSemitones = 0;
  double _fontSize = 26.0;
  bool _practiceMode = false;
  bool _pitchMeterEnabled = true;
  int? _lastScore;
  int _totalTaps = 0;
  int _scoreAccumulator = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _recordTapTiming(Duration currentPos, Duration targetTime) {
    HapticFeedback.lightImpact();
    final diffMs = (currentPos.inMilliseconds - targetTime.inMilliseconds).abs();
    // Timing precision: 0ms diff = 100%, 150ms diff = 90%, 500ms diff = 66%
    final score = math.max(0, 100 - (diffMs ~/ 15));
    setState(() {
      _lastScore = score;
      _totalTaps++;
      _scoreAccumulator += score;
    });
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
        final pos = rawPos.isNegative ? Duration.zero : rawPos;
        final song = state.currentSong;
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

        // Practice Mode: Loop current line
        if (_practiceMode && activeLine != null && nextLine != null && pos >= nextLine.timestamp) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.read<PlayerCubit>().seek(activeLine.timestamp);
          });
        }

        final durationMs = state.duration.inMilliseconds;
        final progressPct = durationMs > 0
            ? ((pos.inMilliseconds / durationMs).clamp(0.0, 1.0) * 100)
                .round()
            : 0;

        final avgScore = _totalTaps > 0 ? (_scoreAccumulator / _totalTaps).round() : null;

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
              if (avgScore != null)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: AppSpacing.s6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadii.r10),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        '$avgScore',
                        style: const TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w900,
                            color: Colors.amber),
                      ),
                    ],
                  ),
                ),
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
                      child: Builder(
                        builder: (_) {
                          final lineStart = activeLine.timestamp.inMilliseconds;
                          final lineEnd = (nextLine?.timestamp ??
                                  (activeLine.timestamp +
                                      const Duration(seconds: 4)))
                              .inMilliseconds;
                          final lineDuration =
                              math.max(1, lineEnd - lineStart);
                          final currentProgress =
                              ((pos.inMilliseconds - lineStart) / lineDuration)
                                  .clamp(0.0, 1.0);
                          final words = activeLine.text.split(' ');
                          final highlightedCount =
                              (currentProgress * words.length).ceil();

                          return Text.rich(
                            TextSpan(
                              children: [
                                for (int i = 0; i < words.length; i++) ...[
                                  TextSpan(
                                    text: words[i] +
                                        (i < words.length - 1 ? ' ' : ''),
                                    style: TextStyle(
                                      color: i < highlightedCount
                                          ? p.primary
                                          : p.primary.withValues(alpha: 0.38),
                                      fontWeight: i < highlightedCount
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      shadows: i < highlightedCount
                                          ? [
                                              Shadow(
                                                color: p.primary
                                                    .withValues(alpha: 0.8),
                                                blurRadius: 28,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: _fontSize,
                            ),
                          );
                        },
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
                          fontSize: math.max(14.0, _fontSize * 0.65),
                          fontWeight: FontWeight.w600,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),

              // Karaoke Controls Bar (Pitch shift, Practice mode, Font size, Rhythm Tap)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    // Practice Mode Toggle
                    IconButton.filledTonal(
                      tooltip: 'Practice Mode (Loop Current Line)',
                      isSelected: _practiceMode,
                      icon: const Icon(Icons.repeat_one_rounded, size: 20),
                      onPressed: () => setState(() => _practiceMode = !_practiceMode),
                    ),
                    // Vocal Pitch Meter Toggle
                    IconButton.filledTonal(
                      tooltip: 'Vocal Pitch Meter (YIN Algorithm)',
                      isSelected: _pitchMeterEnabled,
                      icon: const Icon(Icons.mic_external_on_rounded, size: 20),
                      onPressed: () => setState(() => _pitchMeterEnabled = !_pitchMeterEnabled),
                    ),
                    // Pitch Down
                    IconButton(
                      tooltip: context.l10n.dspPitchDownSemitone,
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                      onPressed: _pitchSemitones > _minPitchSemitones
                          ? () {
                              setState(() => _pitchSemitones--);
                              context.read<PlayerCubit>().setPlaybackPitch(
                                  math.pow(2.0, _pitchSemitones / 12.0)
                                      .toDouble());
                            }
                          : null,
                    ),
                    Text(
                      '${_pitchSemitones >= 0 ? "+" : ""}$_pitchSemitones st • '
                      '${math.pow(2.0, _pitchSemitones / 12.0).toStringAsFixed(2)}×',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    // Pitch Up
                    IconButton(
                      tooltip: context.l10n.dspPitchUpSemitone,
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                      onPressed: _pitchSemitones < _maxPitchSemitones
                          ? () {
                              setState(() => _pitchSemitones++);
                              context.read<PlayerCubit>().setPlaybackPitch(
                                  math.pow(2.0, _pitchSemitones / 12.0)
                                      .toDouble());
                            }
                          : null,
                    ),
                    // Font Size Cycle
                    IconButton(
                      tooltip: 'Lyrics Font Size',
                      icon: const Icon(Icons.format_size_rounded, size: 20),
                      onPressed: () {
                        setState(() {
                          _fontSize = _fontSize >= 34.0 ? 20.0 : _fontSize + 4.0;
                        });
                      },
                    ),
                    if (activeLine != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.withValues(alpha: 0.25),
                          foregroundColor: Colors.amber,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                        ),
                        onPressed: () => _recordTapTiming(pos, activeLine.timestamp),
                        icon: const Icon(Icons.touch_app_rounded, size: 16),
                        label: Text(_lastScore != null ? 'Score: $_lastScore' : 'Tap Rhythm'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Vocal Pitch Guidance Meter
              if (_pitchMeterEnabled) ...[
                _PitchMeterUnavailable(palette: p),
                const SizedBox(height: AppSpacing.sm),
              ],

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

/// B9: honest disabled state. The previous widget rendered a hardcoded
/// `PitchResult` (261.6 Hz / C4) as if it were live microphone data. Microphone
/// capture is not wired into this build, so the meter says so instead of faking.
class _PitchMeterUnavailable extends StatelessWidget {
  final PulsrPalette palette;

  const _PitchMeterUnavailable({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
            decoration: BoxDecoration(
              color: palette.textTertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.r8),
            ),
            child: Text(
              '--',
              style: TextStyle(
                color: palette.textTertiary,
                fontWeight: FontWeight.w900,
                fontSize: AppFontSize.bodyLarge,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.dspPitchMeterUnavailable,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

