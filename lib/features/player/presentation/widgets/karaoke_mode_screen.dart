// lib/features/player/presentation/widgets/karaoke_mode_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_visualizer.dart';
import 'player_controls.dart';
import 'player_seek_bar.dart';
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
    final orientation = MediaQuery.orientationOf(context);
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
          if (_practiceMode &&
              activeLine != null &&
              nextLine != null &&
              pos >= nextLine.timestamp) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.read<PlayerCubit>().seek(activeLine.timestamp);
              }
            });
          }

          final durationMs = state.duration.inMilliseconds;
          final progressPct = durationMs > 0
              ? ((pos.inMilliseconds / durationMs).clamp(0.0, 1.0) * 100)
                  .round()
              : 0;

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
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadii.r10),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 16, color: Colors.amber),
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
                    margin:
                        const EdgeInsetsDirectional.only(end: AppSpacing.md),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadii.r10),
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
                  ),
                ],
              ),
              body: Builder(
                builder: (context) {
                  final isLandscape =
                      MediaQuery.orientationOf(context) == Orientation.landscape;

                  final lyricsWidget = Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (effectiveLyrics.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              context
                                  .read<PlayerCubit>()
                                  .seek(activeLine.timestamp);
                            },
                            borderRadius: BorderRadius.circular(AppRadii.r16),
                            splashColor: p.primary.withValues(alpha: 0.2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                  horizontal: AppSpacing.sm),
                              child: Builder(
                                builder: (_) {
                                  final lineStart =
                                      activeLine.timestamp.inMilliseconds;
                                  final lineEnd = (nextLine?.timestamp ??
                                          (activeLine.timestamp +
                                              const Duration(seconds: 4)))
                                      .inMilliseconds;
                                  final lineDuration =
                                      math.max(1, lineEnd - lineStart);
                                  final currentProgress =
                                      ((pos.inMilliseconds - lineStart) /
                                              lineDuration)
                                          .clamp(0.0, 1.0);
                                  final words = activeLine.text.split(' ');
                                  final highlightedCount =
                                      (currentProgress * words.length).ceil();

                                  return Text.rich(
                                    TextSpan(
                                      children: [
                                        for (int i = 0;
                                            i < words.length;
                                            i++) ...[
                                          TextSpan(
                                            text: words[i] +
                                                (i < words.length - 1 ? ' ' : ''),
                                            style: TextStyle(
                                              color: i < highlightedCount
                                                  ? p.primary
                                                  : p.primary
                                                      .withValues(alpha: 0.38),
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.music_note_rounded,
                                  size: 32,
                                  color: p.primary.withValues(alpha: 0.7)),
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
                                  vertical: AppSpacing.s6,
                                  horizontal: AppSpacing.sm),
                              child: Text(
                                nextLine.text,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: math.max(13.0, (isLandscape ? math.min(_fontSize, 22.0) : _fontSize) * 0.65),
                                  fontWeight: FontWeight.w600,
                                  color: p.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );

                  Widget buildKaraokeBar({required bool compact}) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
                            icon: const Icon(Icons.repeat_one_rounded, size: 18),
                            visualDensity: compact ? VisualDensity.compact : null,
                            onPressed: () =>
                                setState(() => _practiceMode = !_practiceMode),
                          ),
                          // Pitch Down
                          IconButton(
                            tooltip: context.l10n.dspPitchDownSemitone,
                            icon: const Icon(Icons.remove_circle_outline_rounded,
                                size: 18),
                            visualDensity: compact ? VisualDensity.compact : null,
                            onPressed: _pitchSemitones > _minPitchSemitones
                                ? () {
                                    setState(() => _pitchSemitones--);
                                    context.read<PlayerCubit>().setPlaybackPitch(
                                        math
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
                            visualDensity: compact ? VisualDensity.compact : null,
                            onPressed: _pitchSemitones < _maxPitchSemitones
                                ? () {
                                    setState(() => _pitchSemitones++);
                                    context.read<PlayerCubit>().setPlaybackPitch(
                                        math
                                            .pow(2.0, _pitchSemitones / 12.0)
                                            .toDouble());
                                  }
                                : null,
                          ),
                          // Font Size Cycle
                          IconButton(
                            tooltip: context.l10n.karaokeLyricsFontSize,
                            icon: const Icon(Icons.format_size_rounded, size: 18),
                            visualDensity: compact ? VisualDensity.compact : null,
                            onPressed: () {
                              setState(() {
                                _fontSize =
                                    _fontSize >= 34.0 ? 20.0 : _fontSize + 4.0;
                              });
                            },
                          ),
                          if (activeLine != null)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.amber.withValues(alpha: 0.25),
                                foregroundColor: Colors.amber,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.xxs),
                              ),
                              onPressed: () =>
                                  _recordTapTiming(pos, activeLine.timestamp),
                              icon: const Icon(Icons.touch_app_rounded, size: 14),
                              label: Text(
                                _lastScore != null
                                    ? context.l10n.karaokeScore(_lastScore!)
                                    : context.l10n.karaokeTapRhythm,
                                style: const TextStyle(fontSize: AppFontSize.caption),
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  Widget buildPlayerControlsSection({required bool isLandscape}) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Interactive Seek Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          child: PlayerSeekBar(
                            position: pos,
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
                          isShuffle: state.isShuffle,
                          repeatMode: state.repeatMode,
                          hasPrevious: state.hasPreviousNeighbour,
                          hasNext: state.hasNextNeighbour,
                          primaryColor: p.primary,
                          mainButtonSize: isLandscape ? 46.0 : 56.0,
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
                                child: lyricsWidget,
                              ),
                            ),
                          ),
                          const VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: Colors.white12,
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
                                      child: AudioVisualizer(
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
                              child: lyricsWidget,
                            ),
                          ),
                        ),
                        buildKaraokeBar(compact: false),
                        const SizedBox(height: AppSpacing.xs),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          child: AudioVisualizer(
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
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      rethrow;
    }
  }
}

