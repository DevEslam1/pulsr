import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/services/waveform_service.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import 'waveform_seek_bar.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class PlayerSeekBar extends StatefulWidget {
  /// Position shown by the bar.
  ///
  /// Optional for backwards compatibility: when null (the preferred usage from
  /// the player themes), the bar subscribes to `PlayerCubit` position itself
  /// via a [BlocSelector], so position ticks never rebuild the enclosing
  /// theme. When non-null, the given value is used as before.
  final Duration? position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final Color activeColor;
  final int? songId;
  final String? filePath;
  final String? semanticLabel;
  final Duration? loopPointA;
  final Duration? loopPointB;

  /// When true (default) a subtle "Up Next" strip renders below the bar so the
  /// next track is visible without opening the queue.
  final bool showUpNext;

  const PlayerSeekBar({
    super.key,
    this.position,
    required this.duration,
    required this.onSeek,
    this.activeColor = Colors.white,
    this.songId,
    this.filePath,
    this.semanticLabel,
    this.loopPointA,
    this.loopPointB,
    this.showUpNext = true,
  });

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _dragValue;
  bool _tapSeekPending = false;
  double? _tapSeekRatio;
  int? _lastSongId;
  String? _lastFilePath;
  Future<List<double>>? _cachedWaveformFuture;

  @override
  void didUpdateWidget(PlayerSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId ||
        oldWidget.filePath != widget.filePath) {
      _dragValue = null;
      _tapSeekPending = false;
      _tapSeekRatio = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final songId =
        context.select<PlayerCubit, int?>((c) => c.state.currentSong?.id);
    final songPath =
        context.select<PlayerCubit, String?>((c) => c.state.currentSong?.path);
    final waveformEnabled = context
        .select<SettingsCubit, bool>((c) => c.state.waveformSeekBarEnabled);

    final effectiveSongId = widget.songId ?? songId;
    final effectiveFilePath = widget.filePath ?? songPath;

    if (_lastSongId != effectiveSongId || _lastFilePath != effectiveFilePath) {
      _lastSongId = effectiveSongId;
      _lastFilePath = effectiveFilePath;
      _dragValue = null;
      _tapSeekPending = false;
      _tapSeekRatio = null;
      _cachedWaveformFuture = null;
    }

    // Check if Waveform Seek Bar is enabled in settings and song ID is available
    if (waveformEnabled && effectiveSongId != null) {
      _cachedWaveformFuture ??= WaveformService.instance.getWaveform(
        songId: effectiveSongId,
        filePath: effectiveFilePath,
      );

      return _withUpNext(
        FutureBuilder<List<double>>(
          key: ValueKey(effectiveSongId),
          future: _cachedWaveformFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return _withPosition((position) => WaveformSeekBar(
                    position: position,
                    duration: widget.duration,
                    onSeek: widget.onSeek,
                    samples: snapshot.data!,
                    activeColor: widget.activeColor,
                    semanticLabel: widget.semanticLabel,
                    loopPointA: widget.loopPointA,
                    loopPointB: widget.loopPointB,
                  ));
            }
            if (snapshot.hasError) {
              ErrorLogger.log(
                'Waveform calculation failed for song $effectiveSongId',
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
                category: 'WaveformSeekBar',
              );
            }
            // Accurate fallback while waveform is computing or on failure
            return _buildStandardSeekBar(context);
          },
        ),
      );
    }

    return _withUpNext(_buildStandardSeekBar(context));
  }

  /// Adds the "Up Next" strip below the seek bar (shared by every theme).
  Widget _withUpNext(Widget seek) {
    if (!widget.showUpNext) return seek;
    final hasNext = context.select<PlayerCubit, bool>((c) {
      final q = c.state.queue;
      final i = c.state.currentIndex;
      return i >= 0 && i + 1 < q.length && q[i + 1].title.isNotEmpty;
    });
    if (!hasNext) return seek;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [seek, _upNextRow(context)],
    );
  }

  Widget _upNextRow(BuildContext context) {
    final nextTitle = context.select<PlayerCubit, String?>((c) {
      final q = c.state.queue;
      final i = c.state.currentIndex;
      if (i < 0 || i + 1 >= q.length) return null;
      return q[i + 1].title;
    });
    if (nextTitle == null || nextTitle.isEmpty) return const SizedBox.shrink();

    final p = context.palette;
    final cubit = context.read<PlayerCubit>();
    return Padding(
      padding: const EdgeInsetsDirectional.only(
          start: AppSpacing.lg, end: AppSpacing.lg, top: AppSpacing.xxs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          cubit.toggleQueueVisibility();
        },
        child: Row(
          children: [
            Icon(Icons.skip_next_rounded, size: 14, color: p.textTertiary),
            const SizedBox(width: AppSpacing.s6),
            Text(
              context.l10n.queue.toUpperCase(),
              style: TextStyle(
                color: p.textTertiary,
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w800,
                letterSpacing: AppTracking.overline,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                nextTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// When no position was passed in (preferred path), narrow the position
  /// subscription to this subtree so per-tick rebuilds stop at the seek bar.
  Widget _withPosition(Widget Function(Duration position) build) {
    final provided = widget.position;
    if (provided != null) return build(provided);
    return _PlayerPositionScope(builder: build);
  }

  Widget _buildStandardSeekBar(BuildContext context) {
    final isPlaying =
        context.select<PlayerCubit, bool>((c) => c.state.isPlaying);
    return _withPosition((position) {
      final double maxDuration = widget.duration.inMilliseconds.toDouble();
      final double currentPos = position.inMilliseconds.toDouble();
      final double effectiveValue = (_dragValue ?? currentPos)
          .clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
      final currentDuration = _dragValue != null
          ? Duration(milliseconds: _dragValue!.round())
          : position;
      final valueLabel =
          '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(widget.duration)}';
      final semanticLabel = widget.semanticLabel ?? context.l10n.seekLabel;
      Duration clampDuration(Duration d) {
        if (d < Duration.zero) return Duration.zero;
        if (d > widget.duration) return widget.duration;
        return d;
      }

      String labelFor(Duration d) =>
          '${Formatters.formatDuration(d)} / ${Formatters.formatDuration(widget.duration)}';
      final increasedLabel = labelFor(
          clampDuration(currentDuration + const Duration(seconds: 10)));
      final decreasedLabel = labelFor(
          clampDuration(currentDuration - const Duration(seconds: 10)));

      return Directionality(
        textDirection: Directionality.of(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern wavy gesture-driven scrubber
              Semantics(
                value: valueLabel,
                increasedValue: increasedLabel,
                decreasedValue: decreasedLabel,
                onIncrease: () => widget.onSeek(
                    clampDuration(currentDuration + const Duration(seconds: 10))),
                onDecrease: () => widget.onSeek(
                    clampDuration(currentDuration - const Duration(seconds: 10))),
                child: PulsrSlider(
                  value: effectiveValue,
                  min: 0.0,
                  max: maxDuration > 0 ? maxDuration : 1.0,
                  height: 32,
                  semanticLabel: semanticLabel,
                  activeColor: widget.activeColor,
                  inactiveColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.14)
                      : context.palette.hairline.withValues(alpha: 0.8),
                  isWavy: true,
                  animateWave: isPlaying,
                  onChangeStart: (val) {
                    _tapSeekPending = true;
                    _tapSeekRatio = val.clamp(0.0, maxDuration.toDouble());
                    setState(() => _dragValue = _tapSeekRatio);
                  },
                  onChanged: (val) {
                    final clampedVal = val.clamp(0.0, maxDuration.toDouble());
                    if (_tapSeekRatio != null && (clampedVal - _tapSeekRatio!).abs() > 200) {
                      _tapSeekPending = false;
                    }
                    setState(() => _dragValue = clampedVal);
                  },
                  onChangeEnd: (val) {
                    final target = (_tapSeekPending && _tapSeekRatio != null)
                        ? _tapSeekRatio!.clamp(0.0, maxDuration.toDouble())
                        : val.clamp(0.0, maxDuration.toDouble());
                    widget.onSeek(Duration(milliseconds: target.round()));
                    setState(() {
                      _dragValue = null;
                      _tapSeekPending = false;
                      _tapSeekRatio = null;
                    });
                  },
                  onChangeCancel: () {
                    setState(() {
                      _dragValue = null;
                      _tapSeekPending = false;
                      _tapSeekRatio = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              // Timestamps
              RepaintBoundary(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Formatters.formatDuration(
                        _dragValue != null
                            ? Duration(milliseconds: _dragValue!.round())
                            : position,
                      ),
                      style: TextStyle(
                        color: context.palette.textSecondary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: AppTracking.label,
                      ),
                    ),
                    Text(
                      Formatters.formatDuration(widget.duration),
                      style: TextStyle(
                        color: context.palette.textSecondary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: AppTracking.label,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _PlayerPositionScope extends StatelessWidget {
  final Widget Function(Duration position) builder;
  const _PlayerPositionScope({required this.builder});

  @override
  Widget build(BuildContext context) {
    final position =
        context.select<PlayerCubit, Duration>((c) => c.state.position);
    return builder(position);
  }
}
