import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/services/waveform_service.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import 'waveform_seek_bar.dart';

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

  const PlayerSeekBar({
    super.key,
    this.position,
    required this.duration,
    required this.onSeek,
    this.activeColor = Colors.white,
    this.songId,
    this.filePath,
    this.semanticLabel,
  });

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _dragValue;
  int? _lastSongId;
  String? _lastFilePath;
  Future<List<double>>? _cachedWaveformFuture;

  static final List<double> _loadingWaveformSamples = List.generate(
    100,
    (i) => 0.2 + 0.15 * math.sin(i * 0.15),
  );

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

    // Check if Waveform Seek Bar is enabled in settings and song ID is available
    if (waveformEnabled && effectiveSongId != null) {
      if (_lastSongId != effectiveSongId ||
          _lastFilePath != effectiveFilePath ||
          _cachedWaveformFuture == null) {
        _lastSongId = effectiveSongId;
        _lastFilePath = effectiveFilePath;
        _cachedWaveformFuture = WaveformService.instance.getWaveform(
          songId: effectiveSongId,
          filePath: effectiveFilePath,
        );
      }

      return FutureBuilder<List<double>>(
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
                ));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Keep themed WaveformSeekBar mounted with loading state
            return _withPosition((position) => WaveformSeekBar(
                  position: position,
                  duration: widget.duration,
                  onSeek: widget.onSeek,
                  samples: _loadingWaveformSamples,
                  activeColor: widget.activeColor.withValues(alpha: 0.45),
                  semanticLabel: widget.semanticLabel,
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
          // Hard failure fallback to standard seek bar
          return _buildStandardSeekBar(context);
        },
      );
    }

    return _buildStandardSeekBar(context);
  }

  /// When no position was passed in (preferred path), narrow the position
  /// subscription to this subtree so per-tick rebuilds stop at the seek bar.
  Widget _withPosition(Widget Function(Duration position) build) {
    final provided = widget.position;
    if (provided != null) return build(provided);
    return BlocSelector<PlayerCubit, PlayerState, Duration>(
      selector: (s) => s.position,
      builder: (context, position) => build(position),
    );
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
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      setState(() => _dragValue = val);
                    },
                    onChanged: (val) {
                      setState(() => _dragValue = val);
                    },
                    onChangeEnd: (val) {
                      widget.onSeek(Duration(milliseconds: val.round()));
                      setState(() => _dragValue = null);
                    },
                  ),
                ),
                const SizedBox(height: 2),
                // Timestamps
                Row(
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      Formatters.formatDuration(widget.duration),
                      style: TextStyle(
                        color: context.palette.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
