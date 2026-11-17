part of '../clean_player_theme.dart';

/// Sleek seek bar with flanking timestamps and the centered "Lossless" pill.
///
/// Owns its own scrub state so dragging never rebuilds the whole theme, and
/// publishes a single slider semantics node with ±10 s actions.
class _CleanSeekBar extends StatefulWidget {
  final PlayerThemeProps props;
  final Duration duration;
  final SongsTableData? song;
  final Color activeColor;
  final PlayerSliderStyle sliderStyle;
  final double horizontalPadding;
  final bool isCompact;

  const _CleanSeekBar({
    required this.props,
    required this.duration,
    required this.song,
    required this.activeColor,
    required this.sliderStyle,
    this.horizontalPadding = 24.0,
    this.isCompact = false,
  });

  @override
  State<_CleanSeekBar> createState() => _CleanSeekBarState();
}

class _CleanSeekBarState extends State<_CleanSeekBar> {
  double? _dragValue;
  bool _showRemainingTime = true;
  Future<List<double>>? _cachedWaveformFuture;
  int? _lastSongId;
  String? _lastFilePath;

  @override
  void didUpdateWidget(covariant _CleanSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song?.id != oldWidget.song?.id) {
      _dragValue = null;
      _cachedWaveformFuture = null;
    }
  }

  Widget _buildPulsrSlider(
    double effectiveValue,
    double maxDuration,
    PlayerSliderStyle effectiveStyle,
    bool isPlaying,
    bool isBuffering,
  ) {
    final deck = _CleanDeckColors.of(context);
    return SizedBox(
      height: widget.isCompact ? 22.0 : 28.0,
      child: PulsrSlider(
        value: effectiveValue,
        min: 0.0,
        max: maxDuration > 0 ? maxDuration : 1.0,
        height: widget.isCompact ? 22.0 : 28.0,
        activeColor: deck.sliderActive,
        inactiveColor: deck.sliderInactive,
        thumbColor: deck.sliderActive,
        sliderStyle: effectiveStyle,
        isWavy: effectiveStyle == PlayerSliderStyle.wavy,
        animateWave: isPlaying && !isBuffering,
        onChangeStart: (val) {
          PulsrHaptics.selectionClick();
          setState(() => _dragValue = val);
        },
        onChanged: (val) {
          setState(() => _dragValue = val);
        },
        onChangeEnd: (val) {
          widget.props.cubit.seek(Duration(milliseconds: val.round()));
          setState(() => _dragValue = null);
        },
        onChangeCancel: () {
          setState(() => _dragValue = null);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position =
        context.select<PlayerCubit, Duration>((c) => c.state.position);
    final isPlaying =
        context.select<PlayerCubit, bool>((c) => c.state.isPlaying);
    final isBuffering =
        context.select<PlayerCubit, bool>((c) => c.state.isBuffering);
    final waveformEnabled = context
        .select<SettingsCubit, bool>((c) => c.state.waveformSeekBarEnabled);

    final deck = _CleanDeckColors.of(context);

    final double maxDuration = widget.duration.inMilliseconds.toDouble();
    final double currentPos = position.inMilliseconds.toDouble();
    final double effectiveValue = (_dragValue ?? currentPos)
        .clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
    final isDragging = _dragValue != null;
    final currentDuration =
        isDragging ? Duration(milliseconds: _dragValue!.round()) : position;

    final remaining = widget.duration > currentDuration
        ? widget.duration - currentDuration
        : Duration.zero;

    final effectiveStyle = widget.sliderStyle;
    final showWaveform = waveformEnabled && widget.song != null;

    final Widget sliderWidget;
    if (showWaveform) {
      final songId = widget.song!.id;
      final songPath = widget.song!.path;
      if (_lastSongId != songId || _lastFilePath != songPath) {
        _lastSongId = songId;
        _lastFilePath = songPath;
        _cachedWaveformFuture = null;
      }
      final instantSamples = WaveformService.instance.getInstantWaveform(
        songId: songId,
        filePath: songPath,
      );
      _cachedWaveformFuture ??= WaveformService.instance
          .getWaveform(songId: songId, filePath: songPath);

      sliderWidget = FutureBuilder<List<double>>(
        key: ValueKey(songId),
        initialData: instantSamples,
        future: _cachedWaveformFuture,
        builder: (context, snapshot) {
          final samples = (snapshot.hasData && snapshot.data!.isNotEmpty)
              ? snapshot.data!
              : instantSamples;
          if (samples.isNotEmpty) {
            return WaveformSeekBar(
              position: position,
              duration: widget.duration,
              onSeek: (pos) => widget.props.cubit.seek(pos),
              samples: samples,
              enabled: !isBuffering,
              activeColor: deck.sliderActive,
              height: widget.isCompact ? 28.0 : 36.0,
            );
          }
          return _buildPulsrSlider(
            effectiveValue,
            maxDuration,
            effectiveStyle,
            isPlaying,
            isBuffering,
          );
        },
      );
    } else {
      sliderWidget = _buildPulsrSlider(
        effectiveValue,
        maxDuration,
        effectiveStyle,
        isPlaying,
        isBuffering,
      );
    }

    Duration clampSeek(Duration delta) {
      final target = currentDuration + delta;
      if (target < Duration.zero) return Duration.zero;
      if (target > widget.duration) return widget.duration;
      return target;
    }

    String seekLabelFor(Duration value) =>
        '${Formatters.formatDuration(value)} / '
        '${Formatters.formatDuration(widget.duration)}';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PulsrSlider publishes a percentage node of its own; replace it with
          // an elapsed/total time node so TalkBack and VoiceOver read progress.
          Semantics(
            slider: true,
            label: context.l10n.seekLabel,
            value: seekLabelFor(currentDuration),
            increasedValue:
                seekLabelFor(clampSeek(const Duration(seconds: 10))),
            decreasedValue:
                seekLabelFor(clampSeek(const Duration(seconds: -10))),
            onIncrease: () =>
                widget.props.cubit.seek(clampSeek(const Duration(seconds: 10))),
            onDecrease: () => widget.props.cubit
                .seek(clampSeek(const Duration(seconds: -10))),
            excludeSemantics: true,
            child: sliderWidget,
          ),
          const SizedBox(height: 3),
          // Row with: 0:46 (left), Lossless badge pill (center), -1:30 (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                Formatters.formatDuration(currentDuration),
                style: TextStyle(
                  color: isDragging ? deck.primary : deck.secondary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              // Centered Lossless badge pill matching Apple Music. It is the
              // longest element in this row, so let it shrink under 200% text
              // scaling instead of overflowing the timestamps.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _CleanLosslessBadgePill(
                    song: widget.song,
                    activeColor: widget.activeColor,
                  ),
                ),
              ),
              // Right timestamp (toggleable remaining time or duration). The
              // 48 dp wide box keeps the tap target honest without moving the
              // digits, which stay pinned to the trailing edge.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _showRemainingTime = !_showRemainingTime),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: 36,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      _showRemainingTime
                          ? '-${Formatters.formatDuration(remaining)}'
                          : Formatters.formatDuration(widget.duration),
                      style: TextStyle(
                        color: deck.secondary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Translucent "Lossless" badge pill matching the photo. Tapping it opens the
/// audio quality sheet, which is the only honest place to explain a tier.
class _CleanLosslessBadgePill extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;

  const _CleanLosslessBadgePill({
    required this.song,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (song == null) {
      return const SizedBox(height: 22);
    }

    final streamingQuality = context.select<SettingsCubit, YtmAudioQuality>(
      (c) => c.state.streamingQuality,
    );
    final info =
        AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);

    final String label = (info.tier == AudioQualityTier.lossless ||
            info.shortBadgeLabel.toLowerCase().contains('lossless'))
        ? context.l10n.badgeLossless
        : (info.tier == AudioQualityTier.hiResLossless
            ? context.l10n.badgeHiResLossless
            : info.shortBadgeLabel);

    final deck = _CleanDeckColors.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AudioQualitySheet.show(context, song!, activeColor),
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          decoration: BoxDecoration(
            color: deck.chipFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: deck.chipBorder, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, size: 12, color: deck.secondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: deck.secondary,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
