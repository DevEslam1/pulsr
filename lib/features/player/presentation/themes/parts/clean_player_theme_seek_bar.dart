part of '../clean_player_theme.dart';

/// Apple Music-inspired thick translucent capsule scrubber (no thumb knob)
/// that expands smoothly during active scrub.
///
/// Strictly isolates playback position updates inside a
/// `BlocSelector<PlayerCubit, PlayerState, ...>` so position ticks never
/// trigger full-theme rebuilds.
class _CleanSeekBar extends StatefulWidget {
  final PlayerThemeProps props;
  final Duration duration;
  final SongsTableData? song;
  final Color activeColor;
  final double horizontalPadding;
  final bool isCompact;
  final bool isPreview;

  const _CleanSeekBar({
    required this.props,
    required this.duration,
    required this.song,
    required this.activeColor,
    this.horizontalPadding = 24.0,
    this.isCompact = false,
    this.isPreview = false,
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

  @override
  Widget build(BuildContext context) {
    final waveformEnabled = context.select<SettingsCubit, bool>(
      (c) => c.state.waveformSeekBarEnabled,
    );
    final deck = _CleanDeckColors.of(context);

    return BlocSelector<
        PlayerCubit,
        PlayerState,
        ({
          Duration position,
          bool isPlaying,
          bool isBuffering,
        })>(
      selector: (s) => (
        position: s.position,
        isPlaying: s.isPlaying,
        isBuffering: s.isBuffering,
      ),
      builder: (context, tick) {
        final double maxDuration = widget.duration.inMilliseconds.toDouble();
        final double safeMax = maxDuration > 0 ? maxDuration : 1.0;
        final double currentPos = tick.position.inMilliseconds.toDouble();
        final double effectiveValue =
            (_dragValue ?? currentPos).clamp(0.0, safeMax);
        final bool isDragging = _dragValue != null;
        final Duration currentDuration = isDragging
            ? Duration(milliseconds: _dragValue!.round())
            : tick.position;

        final Duration remaining = widget.duration > currentDuration
            ? widget.duration - currentDuration
            : Duration.zero;

        final bool showWaveform =
            !widget.isPreview && waveformEnabled && widget.song != null;

        final Widget scrubber;
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

          scrubber = FutureBuilder<List<double>>(
            key: ValueKey(songId),
            initialData: instantSamples,
            future: _cachedWaveformFuture,
            builder: (context, snapshot) {
              final samples = (snapshot.hasData && snapshot.data!.isNotEmpty)
                  ? snapshot.data!
                  : instantSamples;
              if (samples.isNotEmpty) {
                return WaveformSeekBar(
                  position: tick.position,
                  duration: widget.duration,
                  onSeek: (pos) => widget.props.cubit.seek(pos),
                  samples: samples,
                  enabled: !tick.isBuffering,
                  activeColor: deck.sliderActive,
                  height: widget.isCompact ? 28.0 : 36.0,
                );
              }
              return _CleanCapsuleScrubber(
                progress: (effectiveValue / safeMax).clamp(0.0, 1.0),
                isDragging: isDragging,
                isCompact: widget.isCompact,
                activeColor:
                    isDragging ? deck.sliderActiveScrub : deck.sliderActive,
                inactiveColor: deck.sliderInactive,
                onScrubStart: (fraction) {
                  PulsrHaptics.selectionClick();
                  setState(() => _dragValue = fraction * safeMax);
                },
                onScrubUpdate: (fraction) {
                  setState(() => _dragValue = fraction * safeMax);
                },
                onScrubEnd: (fraction) {
                  final targetMs = (fraction * safeMax).round();
                  widget.props.cubit.seek(Duration(milliseconds: targetMs));
                  setState(() => _dragValue = null);
                },
                onScrubCancel: () => setState(() => _dragValue = null),
              );
            },
          );
        } else {
          scrubber = _CleanCapsuleScrubber(
            progress: (effectiveValue / safeMax).clamp(0.0, 1.0),
            isDragging: isDragging,
            isCompact: widget.isCompact,
            activeColor:
                isDragging ? deck.sliderActiveScrub : deck.sliderActive,
            inactiveColor: deck.sliderInactive,
            onScrubStart: (fraction) {
              PulsrHaptics.selectionClick();
              setState(() => _dragValue = fraction * safeMax);
            },
            onScrubUpdate: (fraction) {
              setState(() => _dragValue = fraction * safeMax);
            },
            onScrubEnd: (fraction) {
              final targetMs = (fraction * safeMax).round();
              widget.props.cubit.seek(Duration(milliseconds: targetMs));
              setState(() => _dragValue = null);
            },
            onScrubCancel: () => setState(() => _dragValue = null),
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

        final String trailingTimeText = _showRemainingTime
            ? '-${Formatters.formatDuration(remaining)}'
            : Formatters.formatDuration(widget.duration);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Isolated slider semantics node (never fuses with tap/button).
              Semantics(
                slider: true,
                label: context.l10n.seekLabel,
                value: seekLabelFor(currentDuration),
                increasedValue:
                    seekLabelFor(clampSeek(const Duration(seconds: 10))),
                decreasedValue:
                    seekLabelFor(clampSeek(const Duration(seconds: -10))),
                onIncrease: () => widget.props.cubit
                    .seek(clampSeek(const Duration(seconds: 10))),
                onDecrease: () => widget.props.cubit
                    .seek(clampSeek(const Duration(seconds: -10))),
                excludeSemantics: true,
                child: scrubber,
              ),
              const SizedBox(height: AppSpacing.s2),
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
                  Flexible(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _CleanLosslessBadgePill(
                          song: widget.song,
                          activeColor: widget.activeColor,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: trailingTimeText,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        PulsrHaptics.selectionClick();
                        setState(
                          () => _showRemainingTime = !_showRemainingTime,
                        );
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            trailingTimeText,
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
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Thick translucent capsule scrubber with zero thumb knob that expands
/// vertically while scrubbing.
class _CleanCapsuleScrubber extends StatelessWidget {
  final double progress;
  final bool isDragging;
  final bool isCompact;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;
  final VoidCallback onScrubCancel;

  const _CleanCapsuleScrubber({
    required this.progress,
    required this.isDragging,
    required this.isCompact,
    required this.activeColor,
    required this.inactiveColor,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onScrubCancel,
  });

  double _fractionFor(
    double localDx,
    double width,
    TextDirection direction,
  ) {
    if (width <= 0) return 0.0;
    final dx = direction == TextDirection.rtl ? width - localDx : localDx;
    return (dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final double hitHeight = isCompact ? 36.0 : AppSpacing.minTouchTarget;
    final double idleHeight = isCompact ? 5.5 : 7.0;
    final double dragHeight = isCompact ? 10.5 : 13.0;
    final double barHeight = isDragging ? dragHeight : idleHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double trackWidth = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final frac =
                _fractionFor(details.localPosition.dx, trackWidth, direction);
            onScrubStart(frac);
            onScrubEnd(frac);
          },
          onHorizontalDragStart: (details) {
            onScrubStart(
              _fractionFor(details.localPosition.dx, trackWidth, direction),
            );
          },
          onHorizontalDragUpdate: (details) {
            onScrubUpdate(
              _fractionFor(details.localPosition.dx, trackWidth, direction),
            );
          },
          onHorizontalDragEnd: (_) {
            onScrubEnd(progress);
          },
          onHorizontalDragCancel: onScrubCancel,
          child: SizedBox(
            height: hitHeight,
            width: double.infinity,
            child: Center(
              child: AnimatedContainer(
                duration: context.motionMs(120),
                curve: context.motionCurve(Curves.easeOutCubic),
                height: barHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: inactiveColor,
                  borderRadius: AppRadii.full,
                ),
                clipBehavior: Clip.antiAlias,
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: AppRadii.full,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Translucent audio quality / Lossless pill centered below the capsule
/// scrubber. Tapping opens [AudioQualitySheet].
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
      return const SizedBox(height: 24);
    }

    final streamingQuality = context.select<SettingsCubit, YtmAudioQuality>(
      (c) => c.state.streamingQuality,
    );
    final info = AudioQualityInfo.fromSong(
      song,
      streamingQuality: streamingQuality,
    );

    final String label = (info.tier == AudioQualityTier.lossless ||
            info.shortBadgeLabel.toLowerCase().contains('lossless'))
        ? context.l10n.badgeLossless
        : (info.tier == AudioQualityTier.hiResLossless
            ? context.l10n.badgeHiResLossless
            : info.shortBadgeLabel);

    final deck = _CleanDeckColors.of(context);

    return Semantics(
      button: true,
      label: '${context.l10n.audioQuality}: $label',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            PulsrHaptics.selectionClick();
            AudioQualitySheet.show(context, song!, activeColor);
          },
          borderRadius: AppRadii.chipRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Center(
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: deck.chipFill,
                  borderRadius: AppRadii.chipRadius,
                  border: Border.all(color: deck.chipBorder, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 13,
                      color: deck.secondary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      label,
                      style: TextStyle(
                        color: deck.secondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        letterSpacing: AppTracking.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
