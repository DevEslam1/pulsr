import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/services/waveform_service.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import 'waveform_seek_bar.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

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

  /// Dynamic waveform height to adapt across different screen heights.
  final double? waveformHeight;

  /// Test seam: when set, waveform decoding uses this loader instead of
  /// [WaveformService.instance].
  @visibleForTesting
  static Future<List<double>> Function(int songId, String? filePath)?
      waveformLoaderOverride;

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
    this.waveformHeight,
  });

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  static const Duration _waveformDebounceDelay = Duration(milliseconds: 160);

  double? _dragValue;
  double? _dragStartValue;
  double? _lastHapticCheckMs;
  bool _tapSeekPending = false;
  double? _tapSeekRatio;
  int? _lastSongId;
  String? _lastFilePath;
  Future<List<double>>? _cachedWaveformFuture;
  int _waveformGeneration = 0;
  Timer? _waveformDebounce;

  void _checkHapticBoundaries(
      double oldVal, double newVal, BuildContext context) {
    final markers = <double>[];
    if (widget.loopPointA != null) {
      markers.add(widget.loopPointA!.inMilliseconds.toDouble());
    }
    if (widget.loopPointB != null) {
      markers.add(widget.loopPointB!.inMilliseconds.toDouble());
    }
    try {
      final cubit = context.read<PlayerCubit>();
      for (final seg in cubit.sponsorBlockSegments) {
        markers.add(seg.start.inMilliseconds.toDouble());
        markers.add(seg.end.inMilliseconds.toDouble());
      }
    } catch (_) {}

    final minV = math.min(oldVal, newVal);
    final maxV = math.max(oldVal, newVal);
    for (final marker in markers) {
      if (marker > minV && marker <= maxV) {
        PulsrHaptics.light();
        break;
      }
    }
  }

  @override
  void dispose() {
    _waveformDebounce?.cancel();
    _waveformDebounce = null;
    super.dispose();
  }

  /// Debounces the decode so rapid browsing does not start a decode per track,
  /// and drops any late result whose song has since been replaced.
  Future<List<double>> _requestWaveform(
      int songId, String? filePath, int generation) {
    final completer = Completer<List<double>>();
    _waveformDebounce?.cancel();
    _waveformDebounce = Timer(_waveformDebounceDelay, () async {
      _waveformDebounce = null;
      if (generation != _waveformGeneration) {
        completer.complete(const <double>[]);
        return;
      }
      try {
        final loader = PlayerSeekBar.waveformLoaderOverride;
        final samples = loader != null
            ? await loader(songId, filePath)
            : await WaveformService.instance
                .getWaveform(songId: songId, filePath: filePath);
        completer.complete(
            generation == _waveformGeneration ? samples : const <double>[]);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

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
    final isBuffering =
        context.select<PlayerCubit, bool>((c) => c.state.isBuffering);

    final effectiveSongId = widget.songId ?? songId;
    final effectiveFilePath = widget.filePath ?? songPath;

    double crossfadeSec = 0.0;
    try {
      crossfadeSec = context.select<SettingsCubit, double>(
        (c) => c.state.crossfadeSeconds,
      );
    } on ProviderNotFoundException {
      // M-2: Only catch missing-provider failures, not all exceptions.
      final fallback =
          getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null;
      crossfadeSec = fallback?.state.crossfadeSeconds ?? 0.0;
    }

    if (_lastSongId != effectiveSongId || _lastFilePath != effectiveFilePath) {
      _lastSongId = effectiveSongId;
      _lastFilePath = effectiveFilePath;
      _dragValue = null;
      _tapSeekPending = false;
      _tapSeekRatio = null;
      _cachedWaveformFuture = null;
      _waveformGeneration++;
      _waveformDebounce?.cancel();
      _waveformDebounce = null;
    }

    final Widget seekWidget;
    // Check if Waveform Seek Bar is enabled in settings and song ID is available
    if (waveformEnabled && effectiveSongId != null) {
      final instantSamples = WaveformService.instance.getInstantWaveform(
        songId: effectiveSongId,
        filePath: effectiveFilePath,
      );

      _cachedWaveformFuture ??= _requestWaveform(
          effectiveSongId, effectiveFilePath, _waveformGeneration);

      seekWidget = FutureBuilder<List<double>>(
        key: ValueKey(effectiveSongId),
        initialData: instantSamples,
        future: _cachedWaveformFuture,
        builder: (context, snapshot) {
          final samples = (snapshot.hasData && snapshot.data!.isNotEmpty)
              ? snapshot.data!
              : instantSamples;

          if (samples.isNotEmpty) {
            return _withPosition((position) => WaveformSeekBar(
                  position: position,
                  duration: widget.duration,
                  onSeek: widget.onSeek,
                  samples: samples,
                  enabled: !isBuffering,
                  activeColor: widget.activeColor,
                  height: widget.waveformHeight ?? 44.0,
                  semanticLabel: widget.semanticLabel,
                  loopPointA: widget.loopPointA,
                  loopPointB: widget.loopPointB,
                  crossfadeDuration: crossfadeSec > 0
                      ? Duration(milliseconds: (crossfadeSec * 1000).round())
                      : null,
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
          return _buildStandardSeekBar(context, crossfadeSec, !isBuffering);
        },
      );
    } else {
      seekWidget = _buildStandardSeekBar(context, crossfadeSec, !isBuffering);
    }

    return _withUpNext(seekWidget);
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
    final nextTrackInfo =
        context.select<PlayerCubit, ({String title, String? artist})?>((c) {
      final q = c.state.queue;
      final i = c.state.currentIndex;
      if (i < 0 || i + 1 >= q.length) return null;
      final song = q[i + 1];
      return (title: song.title, artist: song.artist);
    });
    if (nextTrackInfo == null || nextTrackInfo.title.isEmpty) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final cubit = context.read<PlayerCubit>();
    final displayText = (nextTrackInfo.artist != null &&
            nextTrackInfo.artist!.isNotEmpty &&
            !nextTrackInfo.title
                .toLowerCase()
                .contains(nextTrackInfo.artist!.toLowerCase()))
        ? '${nextTrackInfo.artist} - ${nextTrackInfo.title}'
        : nextTrackInfo.title;

    final isCompact =
        widget.waveformHeight != null && widget.waveformHeight! < 38.0;

    return Padding(
      padding: EdgeInsetsDirectional.only(
          start: AppSpacing.lg,
          end: AppSpacing.lg,
          top: isCompact ? 2.0 : AppSpacing.xxs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          cubit.toggleQueueVisibility();
        },
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: isCompact ? 2.0 : AppSpacing.xxs),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [
                widget.activeColor.withValues(alpha: 0.10),
                AppColors.highlightSoft,
              ],
            ),
            borderRadius: AppRadii.r12All,
            border: Border.all(
              color: widget.activeColor.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.skip_next_rounded,
                  size: 14, color: widget.activeColor.withValues(alpha: 0.90)),
              const SizedBox(width: AppSpacing.s6),
              Text(
                context.l10n.upNext,
                style: TextStyle(
                  color: widget.activeColor.withValues(alpha: 0.90),
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w800,
                  letterSpacing: AppTracking.overline,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: p.textTertiary,
              ),
            ],
          ),
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

  Widget _buildStandardSeekBar(BuildContext context,
      [double crossfadeSec = 0.0, bool enabled = true]) {
    bool isPlaying = false;
    try {
      isPlaying = context.select<PlayerCubit, bool>((c) => c.state.isPlaying);
    } on ProviderNotFoundException {
      // M-2: Only catch missing-provider failures, not all exceptions.
      final fallback =
          getIt.isRegistered<PlayerCubit>() ? getIt<PlayerCubit>() : null;
      isPlaying = fallback?.state.isPlaying ?? false;
    }
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
              // Modern wavy gesture-driven scrubber with interactive magnification & floating pill
              LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final isDragging = _dragValue != null;
                  final ratio = maxDuration > 0
                      ? (effectiveValue / maxDuration).clamp(0.0, 1.0)
                      : 0.0;
                  final deltaMs =
                      (_dragStartValue != null && _dragValue != null)
                          ? (_dragValue! - _dragStartValue!).round()
                          : 0;
                  final deltaStr = deltaMs == 0
                      ? '±0:00'
                      : '${deltaMs > 0 ? '+' : '-'}${Formatters.formatDuration(Duration(milliseconds: deltaMs.abs()))}';

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Semantics(
                        // The child PulsrSlider publishes its own slider node
                        // with a percentage value; without this exclusion the
                        // same control appeared twice (time and percent) and
                        // both increase handlers seeked 10s.
                        excludeSemantics: true,
                        value: valueLabel,
                        increasedValue: increasedLabel,
                        decreasedValue: decreasedLabel,
                        onIncrease: enabled
                            ? () => widget.onSeek(clampDuration(
                                currentDuration + const Duration(seconds: 10)))
                            : null,
                        onDecrease: enabled
                            ? () => widget.onSeek(clampDuration(
                                currentDuration - const Duration(seconds: 10)))
                            : null,
                        child: AnimatedContainer(
                          duration: context.motionMs(200),
                          curve: Curves.easeOutCubic,
                          height: isDragging ? 38.0 : 32.0,
                          child: RepaintBoundary(
                            child: PulsrSlider(
                              value: effectiveValue,
                              min: 0.0,
                              max: maxDuration > 0 ? maxDuration : 1.0,
                              height: isDragging ? 38.0 : 32.0,
                              semanticLabel: semanticLabel,
                              activeColor: widget.activeColor,
                              inactiveColor: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.specularStrong
                                  : context.palette.hairline
                                      .withValues(alpha: 0.8),
                              isWavy: true,
                              animateWave: isPlaying && enabled,
                              onChangeStart: enabled
                                  ? (val) {
                                      _tapSeekPending = true;
                                      _tapSeekRatio = val.clamp(
                                          0.0, maxDuration.toDouble());
                                      _dragStartValue = _tapSeekRatio;
                                      _lastHapticCheckMs = _tapSeekRatio;
                                      setState(
                                          () => _dragValue = _tapSeekRatio);
                                    }
                                  : null,
                              onChanged: enabled
                                  ? (val) {
                                      final clampedVal = val.clamp(
                                          0.0, maxDuration.toDouble());
                                      if (_tapSeekRatio != null &&
                                          (clampedVal - _tapSeekRatio!).abs() >
                                              200) {
                                        _tapSeekPending = false;
                                      }
                                      if (_lastHapticCheckMs != null) {
                                        _checkHapticBoundaries(
                                            _lastHapticCheckMs!,
                                            clampedVal,
                                            context);
                                      }
                                      _lastHapticCheckMs = clampedVal;
                                      setState(() => _dragValue = clampedVal);
                                    }
                                  : (_) {},
                              onChangeEnd: enabled
                                  ? (val) {
                                      final target = (_tapSeekPending &&
                                              _tapSeekRatio != null)
                                          ? _tapSeekRatio!.clamp(
                                              0.0, maxDuration.toDouble())
                                          : val.clamp(
                                              0.0, maxDuration.toDouble());
                                      widget.onSeek(Duration(
                                          milliseconds: target.round()));
                                      setState(() {
                                        _dragValue = null;
                                        _dragStartValue = null;
                                        _lastHapticCheckMs = null;
                                        _tapSeekPending = false;
                                        _tapSeekRatio = null;
                                      });
                                    }
                                  : null,
                              onChangeCancel: enabled
                                  ? () {
                                      setState(() {
                                        _dragValue = null;
                                        _dragStartValue = null;
                                        _lastHapticCheckMs = null;
                                        _tapSeekPending = false;
                                        _tapSeekRatio = null;
                                      });
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      // Floating glass timestamp pill above thumb while dragging
                      if (isDragging && trackWidth > 70)
                        PositionedDirectional(
                          top: -34,
                          start: (ratio * trackWidth - 48).clamp(
                              0.0, (trackWidth - 96).clamp(0.0, trackWidth)),
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s8,
                                  vertical: AppSpacing.s4),
                              decoration: BoxDecoration(
                                color: context.palette.surfaceContainerHigh,
                                borderRadius: AppRadii.r12All,
                                border: Border.all(
                                  color: context.palette.hairline,
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${Formatters.formatDuration(currentDuration)} ($deltaStr)',
                                style: TextStyle(
                                  color: context.palette.textPrimary,
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
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
                    if (crossfadeSec > 0 &&
                        widget.duration.inSeconds > (crossfadeSec * 2))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 11,
                            color:
                                context.palette.accent.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            '${crossfadeSec.toStringAsFixed(crossfadeSec.truncateToDouble() == crossfadeSec ? 0 : 1)}s ${context.l10n.browseCrossfade}',
                            style: TextStyle(
                              color: context.palette.accent
                                  .withValues(alpha: 0.75),
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
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
    Duration position;
    try {
      position = context.select<PlayerCubit, Duration>((c) => c.state.position);
    } on ProviderNotFoundException {
      // M-2: Only catch missing-provider failures, not all exceptions.
      final fallback =
          getIt.isRegistered<PlayerCubit>() ? getIt<PlayerCubit>() : null;
      position = fallback?.state.position ?? Duration.zero;
    }
    return builder(position);
  }
}
