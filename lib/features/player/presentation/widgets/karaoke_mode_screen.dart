// lib/features/player/presentation/widgets/karaoke_mode_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/system_ui_controller.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_visualizer.dart';
import 'karaoke_pitch_highway.dart';
import 'player_controls.dart';
import 'player_seek_bar.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../domain/models/lyrics_line.dart';

import '../../../../core/utils/pulsr_haptics.dart';

class _KaraokeActiveLyricData {
  final int activeIdx;
  final int highlightedCount;

  const _KaraokeActiveLyricData({
    required this.activeIdx,
    required this.highlightedCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _KaraokeActiveLyricData &&
          other.activeIdx == activeIdx &&
          other.highlightedCount == highlightedCount;

  @override
  int get hashCode => Object.hash(activeIdx, highlightedCount);
}

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
  bool _showPitchHighway = true;
  int _practiceLoopLine = -1;
  bool _practiceLoopArmed = true;
  int? _lastScore;
  int _totalTaps = 0;
  int _scoreAccumulator = 0;
  PlayerCubit? _playerCubit;
  StreamSubscription<PlayerState>? _practiceLoopSub;
  double? _initialPitch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // System UI mode is applied exclusively in didChangeDependencies (which
    // always runs after initState and has the orientation info). Setting
    // immersiveSticky here unconditionally flashed the hidden status bar for
    // one frame when entering karaoke in portrait.
  }

  void _recordTapTiming(Duration currentPos, Duration targetTime) {
    PulsrHaptics.lightImpact();
    final diffMs =
        (currentPos.inMilliseconds - targetTime.inMilliseconds).abs();
    // Timing precision: 0ms diff = 100%, 150ms diff = 90%, 500ms diff = 66%
    final score = math.max(0, 100 - (diffMs ~/ 15));
    setState(() {
      _lastScore = score;
      _totalTaps++;
      _scoreAccumulator += score;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _playerCubit ??= context.read<PlayerCubit>();
      final cubit = _playerCubit;
      if (cubit != null) {
        // Practice-loop scheduling listens to the position stream instead of
        // running inside build(), where a seek was a build-time side effect.
        _practiceLoopSub ??= cubit.stream.listen(
          (state) => _syncPracticeLoop(cubit, state),
        );
      }
      if (_initialPitch == null) {
        final entryPitch = _playerCubit!.state.playbackPitch;
        _initialPitch = entryPitch;
        // AUDIT-FIX (P2-14): Derive initial semitone offset from the live entry
        // pitch so +/- steps increment from the actual pitch instead of 0 st.
        if (entryPitch > 0) {
          _pitchSemitones = (12.0 * (math.log(entryPitch) / math.ln2))
              .round()
              .clamp(_minPitchSemitones, _maxPitchSemitones);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Karaoke pitch state unavailable',
          error: e, stackTrace: st, category: 'Karaoke');
    }
    final orientation = MediaQuery.orientationOf(context);
    SystemUiController.instance.syncMode(
      owner: 'karaoke',
      immersive: orientation == Orientation.landscape,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final isLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      SystemUiController.instance.syncMode(
        owner: 'karaoke',
        immersive: isLandscape,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _practiceLoopSub?.cancel();
    _practiceLoopSub = null;
    // Restore the app's system UI cleanly when leaving karaoke mode
    SystemUiController.instance.releaseImmersive('karaoke');
    final initialPitch = _initialPitch;
    final cubit = _playerCubit;
    if (initialPitch != null && cubit != null) {
      try {
        unawaited(cubit.setPlaybackPitch(initialPitch).catchError((e, st) {
          ErrorLogger.log('Failed to restore karaoke pitch',
              error: e, stackTrace: st, category: 'Karaoke');
        }));
      } catch (e, st) {
        ErrorLogger.log('Failed to restore karaoke pitch',
            error: e, stackTrace: st, category: 'Karaoke');
      }
    }
    super.dispose();
  }

  /// Practice-loop probe, driven by the position listener and the practice
  /// toggle (never by [build]).
  ///
  /// [_practiceLoopArmed] keeps one seek in flight while the engine catches up
  /// and is only re-armed once the position is back inside the looped window,
  /// so one window can never loop twice.
  void _syncPracticeLoop(PlayerCubit cubit, PlayerState state) {
    if (!mounted) return;
    if (!_practiceMode) {
      _practiceLoopLine = -1;
      _practiceLoopArmed = true;
      return;
    }
    final lyrics = state.lyrics;
    if (lyrics.isEmpty) return;

    var pos = state.position;
    try {
      pos -= context.read<SettingsCubit>().state.audibleLatencyOffset;
    } catch (_) {}
    if (pos.isNegative) pos = Duration.zero;

    int activeIdx = -1;
    for (int i = 0; i < lyrics.length; i++) {
      if (pos >= lyrics[i].timestamp) {
        activeIdx = i;
      } else {
        break;
      }
    }
    if (activeIdx < 0) return;

    // Lock onto the line being practised; re-lock when playback moves back
    // before it (restart, scrub, previous track) or the lyric list changed.
    var loopIndex = _practiceLoopLine;
    if (loopIndex < 0 || loopIndex >= lyrics.length || activeIdx < loopIndex) {
      loopIndex = activeIdx;
      _practiceLoopLine = loopIndex;
      _practiceLoopArmed = true;
    }
    // The line's end is the next line's timestamp (or a short fallback after
    // the last line); comparing against the *next* line is what the old
    // build-time check could never reach.
    final lineStart = lyrics[loopIndex].timestamp;
    final nextIndex = loopIndex + 1;
    final lineEnd =
        (nextIndex < lyrics.length && lyrics[nextIndex].timestamp > lineStart)
            ? lyrics[nextIndex].timestamp
            : lineStart + const Duration(seconds: 4);
    if (pos < lineEnd) {
      _practiceLoopArmed = true;
      return;
    }
    if (!_practiceLoopArmed) return;
    _practiceLoopArmed = false;
    try {
      unawaited(cubit.seek(lineStart));
    } catch (e, st) {
      ErrorLogger.log('Practice loop seek failed',
          error: e, stackTrace: st, category: 'Karaoke');
    }
  }

  /// Enables/disables practice mode and probes the loop immediately, so
  /// toggling it on while parked past a line end loops right away.
  void _togglePracticeMode() {
    final enabling = !_practiceMode;
    setState(() {
      _practiceMode = enabling;
      if (!enabling) {
        _practiceLoopLine = -1;
        _practiceLoopArmed = true;
      }
    });
    if (enabling) {
      final cubit = context.read<PlayerCubit>();
      _syncPracticeLoop(cubit, cubit.state);
    }
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
            prev.currentSong != curr.currentSong ||
            prev.duration != curr.duration ||
            prev.isPlaying != curr.isPlaying ||
            prev.isLoadingLyrics != curr.isLoadingLyrics ||
            prev.lyrics != curr.lyrics,
        builder: (context, state) {
          final song = state.currentSong;
          final effectiveLyrics = state.lyrics;

          final avgScore =
              _totalTaps > 0 ? (_scoreAccumulator / _totalTaps).round() : null;

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
                      margin:
                          const EdgeInsetsDirectional.only(end: AppSpacing.s6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: p.warningSoft,
                        borderRadius: AppRadii.r10All,
                        border: Border.all(color: p.warning),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.star_rounded,
                              size: 16, color: p.warning),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            '$avgScore',
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w900,
                                color: p.warning),
                          ),
                        ],
                      ),
                    ),
                  BlocSelector<PlayerCubit, PlayerState, int>(
                    selector: (s) {
                      final rawPos = s.position - audibleOffset;
                      final pos = rawPos.isNegative ? Duration.zero : rawPos;
                      final durationMs = s.duration.inMilliseconds;
                      return durationMs > 0
                          ? ((pos.inMilliseconds / durationMs).clamp(0.0, 1.0) *
                                  100)
                              .round()
                          : 0;
                    },
                    builder: (context, progressPct) {
                      return Container(
                        margin:
                            const EdgeInsetsDirectional.only(end: AppSpacing.md),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                        decoration: BoxDecoration(
                          color: p.primary.withValues(alpha: 0.2),
                          borderRadius: AppRadii.r10All,
                          border: Border.all(color: p.primary),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timelapse_rounded,
                                size: 16, color: p.primary),
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
                      );
                    },
                  ),
                ],
              ),
              body: Builder(
                builder: (context) {
                  final isLandscape = MediaQuery.orientationOf(context) ==
                      Orientation.landscape;

                  Widget buildLyricsWidget({required bool isLandscape}) {
                    if (effectiveLyrics.isEmpty) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xl),
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
                        ],
                      );
                    }

                    return BlocSelector<PlayerCubit, PlayerState,
                        _KaraokeActiveLyricData>(
                      selector: (s) {
                        final rawPos = s.position - audibleOffset;
                        final pos = rawPos.isNegative ? Duration.zero : rawPos;
                        int activeIdx = -1;
                        for (int i = 0; i < effectiveLyrics.length; i++) {
                          if (pos >= effectiveLyrics[i].timestamp) {
                            activeIdx = i;
                          } else {
                            break;
                          }
                        }
                        if (activeIdx < 0 ||
                            activeIdx >= effectiveLyrics.length) {
                          return const _KaraokeActiveLyricData(
                              activeIdx: -1, highlightedCount: 0);
                        }
                        final line = effectiveLyrics[activeIdx];
                        final next = (activeIdx + 1 < effectiveLyrics.length)
                            ? effectiveLyrics[activeIdx + 1]
                            : null;
                        final lineStart = line.timestamp.inMilliseconds;
                        final lineEnd = (next?.timestamp ??
                                (line.timestamp + const Duration(seconds: 4)))
                            .inMilliseconds;
                        final lineDuration = math.max(1, lineEnd - lineStart);
                        final currentProgress =
                            ((pos.inMilliseconds - lineStart) / lineDuration)
                                .clamp(0.0, 1.0);
                        final words = line.text.split(' ');
                        final highlightedCount =
                            (currentProgress * words.length).ceil();
                        return _KaraokeActiveLyricData(
                          activeIdx: activeIdx,
                          highlightedCount: highlightedCount,
                        );
                      },
                      builder: (context, lyricData) {
                        final activeIdx = lyricData.activeIdx;
                        final activeLine = (activeIdx >= 0 &&
                                activeIdx < effectiveLyrics.length)
                            ? effectiveLyrics[activeIdx]
                            : null;
                        final nextLine = (activeIdx + 1 >= 0 &&
                                activeIdx + 1 < effectiveLyrics.length)
                            ? effectiveLyrics[activeIdx + 1]
                            : (activeIdx == -1 && effectiveLyrics.isNotEmpty
                                ? effectiveLyrics[0]
                                : null);

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Active Lyric Line with Glow & Tap-to-Seek
                            if (activeLine != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xl),
                                child: InkWell(
                                  onTap: () {
                                    PulsrHaptics.selectionClick();
                                    context
                                        .read<PlayerCubit>()
                                        .seek(activeLine.timestamp);
                                  },
                                  borderRadius: AppRadii.r16All,
                                  splashColor:
                                      p.primary.withValues(alpha: 0.2),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.xs,
                                        horizontal: AppSpacing.sm),
                                    child: Builder(
                                      builder: (_) {
                                        final words =
                                            activeLine.text.split(' ');
                                        final highlightedCount =
                                            lyricData.highlightedCount;

                                        return Text.rich(
                                          TextSpan(
                                            children: [
                                              for (int i = 0;
                                                  i < words.length;
                                                  i++) ...[
                                                TextSpan(
                                                  text: words[i] +
                                                      (i < words.length - 1
                                                          ? ' '
                                                          : ''),
                                                  style: TextStyle(
                                                    color: i < highlightedCount
                                                        ? p.primary
                                                        : p.primary.withValues(
                                                            alpha: 0.38),
                                                    fontWeight:
                                                        i < highlightedCount
                                                            ? FontWeight.w900
                                                            : FontWeight.w700,
                                                    shadows: i <
                                                            highlightedCount
                                                        ? [
                                                            Shadow(
                                                              color: p.primary
                                                                  .withValues(
                                                                      alpha:
                                                                          0.8),
                                                              blurRadius: 10,
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
                                            fontSize: isLandscape
                                                ? math.min(_fontSize, 22.0)
                                                : _fontSize,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              )
                            else if (effectiveLyrics.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xl),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.music_note_rounded,
                                        size: 32,
                                        color:
                                            p.primary.withValues(alpha: 0.7)),
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
                            const SizedBox(height: AppSpacing.md),
                            // Next Upcoming Line (Tappable)
                            if (nextLine != null)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 36),
                                child: InkWell(
                                  onTap: () {
                                    PulsrHaptics.selectionClick();
                                    context
                                        .read<PlayerCubit>()
                                        .seek(nextLine.timestamp);
                                  },
                                  borderRadius: AppRadii.r12All,
                                  splashColor:
                                      p.primary.withValues(alpha: 0.15),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.s6,
                                        horizontal: AppSpacing.sm),
                                    child: Text(
                                      nextLine.text,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: math.max(
                                            13.0,
                                            (isLandscape
                                                    ? math.min(
                                                        _fontSize, 22.0)
                                                    : _fontSize) *
                                                0.65),
                                        fontWeight: FontWeight.w600,
                                        color: p.textTertiary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  }

                  Widget buildKaraokeBar({required bool compact}) {
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: compact ? AppSpacing.xxs : AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        children: [
                          // Practice Mode Toggle
                          IconButton.filledTonal(
                            tooltip: context.l10n.karaokePracticeMode,
                            isSelected: _practiceMode,
                            icon:
                                const Icon(Icons.repeat_one_rounded, size: 18),
                            visualDensity:
                                compact ? VisualDensity.compact : null,
                            onPressed: _togglePracticeMode,
                          ),
                          // Pitch Down
                          IconButton(
                            tooltip: context.l10n.dspPitchDownSemitone,
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                size: 18),
                            visualDensity:
                                compact ? VisualDensity.compact : null,
                            onPressed: _pitchSemitones > _minPitchSemitones
                                ? () {
                                    setState(() => _pitchSemitones--);
                                    context
                                        .read<PlayerCubit>()
                                        .setPlaybackPitch(math
                                            .pow(2.0, _pitchSemitones / 12.0)
                                            .toDouble());
                                  }
                                : null,
                          ),
                          Text(
                            '${_pitchSemitones >= 0 ? "+" : ""}$_pitchSemitones st',
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          // Pitch Up
                          IconButton(
                            tooltip: context.l10n.dspPitchUpSemitone,
                            icon: const Icon(Icons.add_circle_outline_rounded,
                                size: 18),
                            visualDensity:
                                compact ? VisualDensity.compact : null,
                            onPressed: _pitchSemitones < _maxPitchSemitones
                                ? () {
                                    setState(() => _pitchSemitones++);
                                    context
                                        .read<PlayerCubit>()
                                        .setPlaybackPitch(math
                                            .pow(2.0, _pitchSemitones / 12.0)
                                            .toDouble());
                                  }
                                : null,
                          ),
                          // Pitch Highway Toggle
                          IconButton.filledTonal(
                            tooltip: context.l10n.karaokePitchGuideHighway,
                            isSelected: _showPitchHighway,
                            icon:
                                const Icon(Icons.graphic_eq_rounded, size: 18),
                            visualDensity:
                                compact ? VisualDensity.compact : null,
                            onPressed: () => setState(
                                () => _showPitchHighway = !_showPitchHighway),
                          ),
                          // Font Size Cycle
                          IconButton(
                            tooltip: context.l10n.karaokeLyricsFontSize,
                            icon:
                                const Icon(Icons.format_size_rounded, size: 18),
                            visualDensity:
                                compact ? VisualDensity.compact : null,
                            onPressed: () {
                              setState(() {
                                _fontSize =
                                    _fontSize >= 34.0 ? 20.0 : _fontSize + 4.0;
                              });
                            },
                          ),
                          BlocSelector<PlayerCubit, PlayerState, LyricsLine?>(
                            selector: (s) {
                              if (effectiveLyrics.isEmpty) return null;
                              final rawPos = s.position - audibleOffset;
                              final pPos =
                                  rawPos.isNegative ? Duration.zero : rawPos;
                              for (int i = effectiveLyrics.length - 1;
                                  i >= 0;
                                  i--) {
                                if (pPos >= effectiveLyrics[i].timestamp) {
                                  return effectiveLyrics[i];
                                }
                              }
                              return null;
                            },
                            builder: (context, activeLine) {
                              if (activeLine == null) {
                                return const SizedBox.shrink();
                              }
                              return ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: p.warningSoft,
                                  foregroundColor: p.warning,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                      vertical: AppSpacing.xxs),
                                ),
                                onPressed: () {
                                  final raw = context
                                          .read<PlayerCubit>()
                                          .state
                                          .position -
                                      audibleOffset;
                                  final pPos =
                                      raw.isNegative ? Duration.zero : raw;
                                  _recordTapTiming(pPos, activeLine.timestamp);
                                },
                                icon: const Icon(Icons.touch_app_rounded,
                                    size: 14),
                                label: Text(
                                  _lastScore != null
                                      ? context.l10n.karaokeScore(_lastScore!)
                                      : context.l10n.karaokeTapRhythm,
                                  style: const TextStyle(
                                      fontSize: AppFontSize.caption),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  Widget buildPlayerControlsSection(
                      {required bool isLandscape}) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Interactive Seek Bar (position: null delegates to internal BlocSelector)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          child: PlayerSeekBar(
                            duration: state.duration,
                            activeColor: p.primary,
                            songId: song?.id,
                            filePath: song?.path,
                            showUpNext: false,
                            onSeek: (newPos) =>
                                context.read<PlayerCubit>().seek(newPos),
                          ),
                        ),
                        SizedBox(height: isLandscape ? 2 : AppSpacing.xxs),
                        // Transport Buttons (Shuffle, Prev, Play/Pause, Next, Repeat)
                        PlayerControls(
                          isPlaying: state.isPlaying,
                          isBuffering: state.isBuffering,
                          isShuffle: state.isShuffle,
                          repeatMode: state.repeatMode,
                          hasPrevious: state.hasPreviousNeighbour,
                          hasNext: state.hasNextNeighbour,
                          primaryColor: p.primary,
                          mainButtonSize: isLandscape ? 48.0 : 56.0,
                          onPlayPause: () =>
                              context.read<PlayerCubit>().togglePlayPause(),
                          onNext: () => context.read<PlayerCubit>().next(),
                          onPrevious: () =>
                              context.read<PlayerCubit>().previous(),
                          onToggleShuffle: () =>
                              context.read<PlayerCubit>().toggleShuffle(),
                          onToggleRepeat: () =>
                              context.read<PlayerCubit>().toggleRepeat(),
                        ),
                      ],
                    );
                  }

                  Widget buildPitchHighwayWidget({required double height}) {
                    return BlocSelector<PlayerCubit, PlayerState,
                        ({Duration pos, int activeIdx})>(
                      selector: (s) {
                        final rawPos = s.position - audibleOffset;
                        final pPos =
                            rawPos.isNegative ? Duration.zero : rawPos;
                        int activeIdx = -1;
                        for (int i = 0; i < effectiveLyrics.length; i++) {
                          if (pPos >= effectiveLyrics[i].timestamp) {
                            activeIdx = i;
                          } else {
                            break;
                          }
                        }
                        return (pos: pPos, activeIdx: activeIdx);
                      },
                      builder: (context, data) => KaraokePitchHighway(
                        isPlaying: state.isPlaying,
                        currentPosition: data.pos,
                        accentColor: p.primary,
                        height: height,
                        lyrics: effectiveLyrics,
                        activeLineIndex: data.activeIdx,
                      ),
                    );
                  }

                  if (isLandscape) {
                    return SafeArea(
                      child: Row(
                        children: [
                          // Left Pane: Lyric content
                          Expanded(
                            flex: 5,
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs),
                                child: buildLyricsWidget(isLandscape: true),
                              ),
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: p.hairline,
                          ),
                          // Right Pane: Tools + Visualizer + Transport Controls
                          Expanded(
                            flex: 5,
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    buildKaraokeBar(compact: true),
                                    const SizedBox(height: AppSpacing.xs),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.md),
                                      child: _showPitchHighway
                                          ? buildPitchHighwayWidget(height: 36)
                                          : AudioVisualizer(
                                              style: VisualizerStyle.wave,
                                              color: p.primary,
                                              height: 32,
                                              isPlaying: state.isPlaying,
                                            ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    buildPlayerControlsSection(
                                        isLandscape: true),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Portrait Layout: Stacked vertically with full controls always visible
                  return SafeArea(
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm),
                              child: buildLyricsWidget(isLandscape: false),
                            ),
                          ),
                        ),
                        buildKaraokeBar(compact: false),
                        const SizedBox(height: AppSpacing.xs),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          child: _showPitchHighway
                              ? buildPitchHighwayWidget(height: 52)
                              : AudioVisualizer(
                                  style: VisualizerStyle.wave,
                                  color: p.primary,
                                  height: 44,
                                  isPlaying: state.isPlaying,
                                ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        buildPlayerControlsSection(isLandscape: false),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    } catch (e, st) {
      ErrorLogger.log('KaraokeModeScreen build failed',
          error: e, stackTrace: st, category: 'Karaoke');
      SystemUiController.instance.releaseImmersive('karaoke');
      rethrow;
    }
  }
}
