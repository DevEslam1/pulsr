part of '../waveform_player_theme.dart';

/// Tall, studio-grade interactive audio oscilloscope centerpiece.
///
/// Replaces any standard thin progress slider with a full dB/time-gridded
/// waveform viewport driven by real decoded PCM peaks from [WaveformService].
/// - Instant 0ms frame-1 display via [WaveformService.getInstantWaveform],
///   upgraded asynchronously via [WaveformService.getWaveform] (cached per
///   track identity so playback ticks never trigger I/O).
/// - Smooth tap & horizontal drag-to-seek (`cubit.seek`) with RTL awareness,
///   floating monospace scrub time + delta HUD pill, glowing active playhead
///   cursor, A/B loop markers when active, and optional subtle FFT trace.
/// - Position updates are strictly isolated inside [BlocSelector] so parent
///   widgets never rebuild on playback ticks.
class _StudioOscilloscopeBay extends StatefulWidget {
  final PlayerThemeProps props;
  final bool isCompact;
  final bool isPreview;
  final bool customGlow;

  const _StudioOscilloscopeBay({
    super.key,
    required this.props,
    required this.isCompact,
    required this.isPreview,
    this.customGlow = false,
  });

  @override
  State<_StudioOscilloscopeBay> createState() => _StudioOscilloscopeBayState();
}

class _StudioOscilloscopeBayState extends State<_StudioOscilloscopeBay> {
  double? _dragMs;
  double? _dragStartMs;
  bool _dragStarted = false;
  bool _showRemaining = false;

  int? _loadedSongId;
  String? _loadedFilePath;
  List<double> _instantSamples = const <double>[];
  Future<List<double>>? _samplesFuture;

  void _syncSamplesForSong(SongsTableData? song) {
    final int songId = song?.id ?? 42;
    final String? filePath = song?.path;
    if (_loadedSongId == songId &&
        _loadedFilePath == filePath &&
        _instantSamples.isNotEmpty) {
      return;
    }

    _loadedSongId = songId;
    _loadedFilePath = filePath;
    _dragMs = null;
    _dragStartMs = null;
    _dragStarted = false;

    _instantSamples = WaveformService.instance.getInstantWaveform(
      songId: songId,
      filePath: filePath,
    );

    if (widget.isPreview || song == null) {
      _samplesFuture = null;
      return;
    }

    _samplesFuture = WaveformService.instance.getWaveform(
      songId: songId,
      filePath: filePath,
    );
  }

  @override
  void initState() {
    super.initState();
    _syncSamplesForSong(widget.props.state.currentSong);
  }

  @override
  void didUpdateWidget(covariant _StudioOscilloscopeBay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.props.state.currentSong?.id !=
            widget.props.state.currentSong?.id ||
        oldWidget.props.state.currentSong?.path !=
            widget.props.state.currentSong?.path ||
        oldWidget.isPreview != widget.isPreview) {
      _syncSamplesForSong(widget.props.state.currentSong);
    }
  }

  double _ratioForDx(double dx, double width, TextDirection direction) {
    if (width <= 0) return 0.0;
    final effectiveDx = direction == TextDirection.rtl ? width - dx : dx;
    return (effectiveDx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final activeColor = widget.props.activeColor;
    final song = state.currentSong;
    final duration = state.duration;
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);
    final bayRadius = resolveCustomRadius(context, AppRadii.r18).clamp(
      AppRadii.r6,
      AppRadii.r28,
    );

    final Color screenBg = p.isDark
        ? Color.lerp(surface.tapeWindow, p.bg, 0.25) ?? surface.tapeWindow
        : Color.lerp(p.surfaceContainerHigh, p.surface, 0.35) ??
            p.surfaceContainerHigh;
    final Color gridColor = p.isDark ? AppColors.specularAt(0.08) : p.hairline;
    final Color gridAccentColor = p.isDark
        ? AppColors.specularAt(0.16)
        : p.textSecondary.withValues(alpha: 0.25);
    final Color gridLabelColor = p.isDark
        ? AppColors.specularAt(0.36)
        : p.textSecondary.withValues(alpha: 0.65);
    final Color unplayedWaveColor = p.isDark
        ? AppColors.specularAt(0.24)
        : p.textSecondary.withValues(alpha: 0.30);

    final Duration? loopA = widget.isPreview ? null : state.abPointA;
    final Duration? loopB = widget.isPreview ? null : state.abPointB;
    final bool abEnabled = !widget.isPreview && state.abLoopEnabled;

    return PlayerGestureScope(
      behavior: HitTestBehavior.deferToChild,
      child: Container(
        decoration: BoxDecoration(
          color: screenBg,
          borderRadius: AppRadii.circular(bayRadius),
          border: Border.all(
            color: activeColor.withValues(
              alpha: p.isDark
                  ? (widget.customGlow ? 0.50 : 0.28)
                  : (widget.customGlow ? 0.45 : 0.26),
            ),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrimAt(p.isDark ? 0.45 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            if (widget.customGlow)
              BoxShadow(
                color: activeColor.withValues(alpha: p.isDark ? 0.26 : 0.16),
                blurRadius: 24,
                spreadRadius: -2,
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Main interactive oscilloscope waveform viewport.
            Expanded(
              child: FutureBuilder<List<double>>(
                future: _samplesFuture,
                initialData: _instantSamples,
                builder: (context, snapshot) {
                  final samples =
                      (snapshot.hasData && snapshot.data!.isNotEmpty)
                          ? snapshot.data!
                          : _instantSamples;

                  return BlocSelector<PlayerCubit, PlayerState, Duration>(
                    selector: (s) => s.position,
                    builder: (context, position) {
                      final double maxMs = duration.inMilliseconds.toDouble();
                      final double currentMs =
                          position.inMilliseconds.toDouble();
                      final double effectiveMs = (_dragMs ?? currentMs).clamp(
                        0.0,
                        maxMs > 0 ? maxMs : 1.0,
                      );
                      final double progress = maxMs > 0
                          ? (effectiveMs / maxMs).clamp(0.0, 1.0)
                          : 0.0;
                      final Duration effectiveDur = _dragMs != null
                          ? Duration(milliseconds: _dragMs!.round())
                          : position;

                      Duration clampSeek(Duration delta) {
                        final target = effectiveDur + delta;
                        if (target < Duration.zero) return Duration.zero;
                        if (target > duration) return duration;
                        return target;
                      }

                      String readout(Duration d) =>
                          '${Formatters.formatDuration(d)} / '
                          '${Formatters.formatDuration(duration)}';

                      final direction = Directionality.of(context);

                      return Semantics(
                        // Explicit merge boundary so parent PlayerGestureScope's
                        // tap action never merges into the slider semantics node.
                        container: true,
                        slider: true,
                        label: context.l10n.seekLabel,
                        value: readout(effectiveDur),
                        increasedValue:
                            readout(clampSeek(const Duration(seconds: 10))),
                        decreasedValue:
                            readout(clampSeek(const Duration(seconds: -10))),
                        onIncrease: isBuffering
                            ? null
                            : () => cubit
                                .seek(clampSeek(const Duration(seconds: 10))),
                        onDecrease: isBuffering
                            ? null
                            : () => cubit
                                .seek(clampSeek(const Duration(seconds: -10))),
                        excludeSemantics: true,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double viewportW = constraints.maxWidth;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragStart: (d) {
                                if (isBuffering || maxMs <= 0) return;
                                _dragStarted = true;
                                PulsrHaptics.selectionClick();
                                final ratio = _ratioForDx(
                                  d.localPosition.dx,
                                  viewportW,
                                  direction,
                                );
                                final targetMs =
                                    (ratio * maxMs).clamp(0.0, maxMs);
                                setState(() {
                                  _dragStartMs = currentMs;
                                  _dragMs = targetMs;
                                });
                              },
                              onHorizontalDragUpdate: (d) {
                                if (isBuffering || maxMs <= 0) return;
                                final ratio = _ratioForDx(
                                  d.localPosition.dx,
                                  viewportW,
                                  direction,
                                );
                                final targetMs =
                                    (ratio * maxMs).clamp(0.0, maxMs);
                                setState(() => _dragMs = targetMs);
                              },
                              onHorizontalDragEnd: (_) {
                                _dragStarted = false;
                                if (_dragMs != null) {
                                  PulsrHaptics.lightImpact();
                                  cubit.seek(
                                    Duration(milliseconds: _dragMs!.round()),
                                  );
                                  setState(() {
                                    _dragMs = null;
                                    _dragStartMs = null;
                                  });
                                }
                              },
                              onHorizontalDragCancel: () {
                                _dragStarted = false;
                                if (_dragMs != null) {
                                  setState(() {
                                    _dragMs = null;
                                    _dragStartMs = null;
                                  });
                                }
                              },
                              onTapUp: (d) {
                                if (isBuffering || _dragStarted || maxMs <= 0) {
                                  return;
                                }
                                PulsrHaptics.selectionClick();
                                final ratio = _ratioForDx(
                                  d.localPosition.dx,
                                  viewportW,
                                  direction,
                                );
                                cubit.seek(
                                  Duration(
                                    milliseconds: (ratio * maxMs).round(),
                                  ),
                                );
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 1. Studio dB / time reticle gridlines.
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _OscilloscopeGridPainter(
                                        gridColor: gridColor,
                                        axisColor: gridAccentColor,
                                        labelColor: gridLabelColor,
                                        isCompact: widget.isCompact,
                                      ),
                                    ),
                                  ),

                                  // 2. Optional subtle live FFT trace layer
                                  //    behind the decoded peak waveform.
                                  if (visualizerStyle != VisualizerStyle.off &&
                                      !widget.isPreview)
                                    IgnorePointer(
                                      child: RepaintBoundary(
                                        child: Opacity(
                                          opacity: isPlaying ? 0.24 : 0.10,
                                          child: AudioVisualizer(
                                            style: visualizerStyle,
                                            color: activeColor,
                                            isPlaying: isPlaying,
                                            audioSessionId:
                                                state.audioSessionId,
                                            trackId: song?.id,
                                            trackPath: song?.path,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 3. Real decoded waveform bars + luminous
                                  //    oscilloscope crest + A/B markers +
                                  //    glowing active playhead cursor.
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _OscilloscopeWaveformPainter(
                                        samples: samples,
                                        progress: progress,
                                        activeColor: activeColor,
                                        unplayedColor: unplayedWaveColor,
                                        playheadCoreColor: p.isDark
                                            ? AppColors.onPrimary
                                            : p.textPrimary,
                                        duration: duration,
                                        loopPointA: loopA,
                                        loopPointB: loopB,
                                        abLoopEnabled: abEnabled,
                                        isPlaying: isPlaying,
                                        isDragging: _dragMs != null,
                                        isRtl: direction == TextDirection.rtl,
                                        isDark: p.isDark,
                                      ),
                                    ),
                                  ),

                                  // 4. Floating monospace scrub time & delta
                                  //    HUD bubble while dragging.
                                  if (_dragMs != null && viewportW > 80)
                                    () {
                                      final deltaMs = _dragStartMs != null
                                          ? (_dragMs! - _dragStartMs!).round()
                                          : 0;
                                      final sign = deltaMs >= 0 ? '+' : '-';
                                      final deltaStr =
                                          Formatters.formatDuration(
                                        Duration(milliseconds: deltaMs.abs()),
                                      );
                                      final hudText =
                                          '${Formatters.formatDuration(effectiveDur)} ($sign$deltaStr)';
                                      final double visualRatio =
                                          direction == TextDirection.rtl
                                              ? 1.0 - progress
                                              : progress;
                                      final double pillStart =
                                          (visualRatio * viewportW - 60.0)
                                              .clamp(
                                        AppSpacing.xs,
                                        math.max(
                                          AppSpacing.xs,
                                          viewportW - 128.0,
                                        ),
                                      );
                                      return PositionedDirectional(
                                        top: AppSpacing.xs,
                                        start: pillStart,
                                        child: IgnorePointer(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.s8,
                                              vertical: AppSpacing.s4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: p.surfaceContainerHigh
                                                  .withValues(alpha: 0.94),
                                              borderRadius: AppRadii.r8All,
                                              border: Border.all(
                                                color: activeColor.withValues(
                                                  alpha: 0.60,
                                                ),
                                                width: 1.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color:
                                                      AppColors.scrimAt(0.32),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              hudText,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: AppFontSize.caption,
                                                fontWeight: FontWeight.w800,
                                                color: p.textPrimary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }(),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Bottom integrated monospace oscilloscope timecode bezel bar
            // driven strictly by BlocSelector (zero parent rebuilds).
            Container(
              decoration: BoxDecoration(
                color: p.isDark
                    ? AppColors.scrimAt(0.28)
                    : p.surface.withValues(alpha: 0.72),
                border: Border(
                  top: BorderSide(color: gridAccentColor, width: 0.9),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: BlocSelector<PlayerCubit, PlayerState,
                  ({Duration position, Duration duration})>(
                selector: (s) => (position: s.position, duration: s.duration),
                builder: (context, span) {
                  final effectivePos = _dragMs != null
                      ? Duration(milliseconds: _dragMs!.round())
                      : span.position;
                  final remaining = span.duration > effectivePos
                      ? span.duration - effectivePos
                      : Duration.zero;
                  final elapsedText = Formatters.formatDuration(effectivePos);
                  final trailingText = _showRemaining
                      ? '-${Formatters.formatDuration(remaining)}'
                      : Formatters.formatDuration(span.duration);

                  final bool hasLoop = loopA != null || loopB != null;
                  final String loopSummary = hasLoop
                      ? 'A ${loopA != null ? Formatters.formatDuration(loopA) : '--:--'} · B ${loopB != null ? Formatters.formatDuration(loopB) : '--:--'}'
                      : '${span.duration.inMilliseconds > 0 ? ((effectivePos.inMilliseconds / span.duration.inMilliseconds) * 100).clamp(0, 100).round() : 0}%';

                  return Row(
                    children: [
                      Text(
                        elapsedText,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w800,
                          color: _dragMs != null ? activeColor : p.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Center(
                          child: Text(
                            loopSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              color: abEnabled ? activeColor : p.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Semantics(
                        button: true,
                        label: trailingText,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            PulsrHaptics.selectionClick();
                            setState(
                              () => _showRemaining = !_showRemaining,
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
                                trailingText,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.label,
                                  fontWeight: FontWeight.w700,
                                  color: p.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints studio oscilloscope dB reference lines, vertical time-division
/// reticle ticks, center 0-axis hairline, and subtle dB scale calibrations.
class _OscilloscopeGridPainter extends CustomPainter {
  static final Paint _gridPaint = Paint()..strokeWidth = 0.75;
  static final Paint _axisPaint = Paint()..strokeWidth = 1.0;
  static final Map<String, TextPainter> _labelPainters = {};
  static Color? _cachedLabelColor;

  final Color gridColor;
  final Color axisColor;
  final Color labelColor;
  final bool isCompact;

  _OscilloscopeGridPainter({
    required this.gridColor,
    required this.axisColor,
    required this.labelColor,
    required this.isCompact,
  });

  static TextPainter _getTextPainter(String text, Color color) {
    if (_cachedLabelColor != color) {
      _labelPainters.clear();
      _cachedLabelColor = color;
    }
    return _labelPainters.putIfAbsent(
      text,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = _gridPaint..color = gridColor;
    final axisPaint = _axisPaint..color = axisColor;

    // 1. Horizontal amplitude / dB reference lines (top +0dB, ±6dB, center 0).
    final double midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), axisPaint);

    for (final double frac in const [0.16, 0.33, 0.67, 0.84]) {
      final y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Vertical time-division reticle lines (8 equal studio divisions) +
    //    crisp top/bottom calibration tick marks.
    const int divisions = 8;
    for (int i = 1; i < divisions; i++) {
      final x = (size.width / divisions) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, 5.0), axisPaint);
      canvas.drawLine(
        Offset(x, size.height - 5.0),
        Offset(x, size.height),
        axisPaint,
      );
    }

    // 3. Subtle dB scale calibration markings along the leading edge.
    if (!isCompact && size.height >= 120 && size.width >= 200) {
      const labels = ['0 dB', '-6 dB', '-6 dB'];
      const fracs = [0.16, 0.33, 0.67];
      for (int i = 0; i < 3; i++) {
        final y = size.height * fracs[i];
        final painter = _getTextPainter(labels[i], labelColor);
        painter.paint(canvas, Offset(AppSpacing.xs, y - painter.height - 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OscilloscopeGridPainter oldDelegate) =>
      oldDelegate.gridColor != gridColor ||
      oldDelegate.axisColor != axisColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.isCompact != isCompact;
}

/// Paints the studio oscilloscope waveform peaks, luminous played crest line,
/// A/B loop shaded region + pins, and glowing vertical playhead cursor.
class _OscilloscopeWaveformPainter extends CustomPainter {
  static final Path _topEnvelope = Path();
  static final Path _bottomEnvelope = Path();
  static final Path _topCap = Path();
  static final Path _bottomCap = Path();

  static final Paint _loopShadePaint = Paint();
  static final Paint _loopPinLinePaint = Paint()..strokeWidth = 1.4;
  static final Paint _loopBadgePaint = Paint();
  static final Paint _unplayedPaint = Paint();
  static final Paint _playedPaint = Paint();
  static final Paint _crestPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..strokeJoin = StrokeJoin.round;
  static final Paint _playheadGlowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
  static final Paint _playheadCorePaint = Paint()..strokeCap = StrokeCap.round;
  static final Paint _markerPaint = Paint();

  static final Map<String, TextPainter> _pinTextPainters = {};
  static Color? _lastPinTextColor;

  static List<double>? _cachedBars;
  static List<double>? _lastSamples;
  static int? _lastTargetBars;

  static Shader? _cachedPlayedShader;
  static int? _lastShaderKey;

  final List<double> samples;
  final double progress;
  final Color activeColor;
  final Color unplayedColor;
  final Color playheadCoreColor;
  final Duration duration;
  final Duration? loopPointA;
  final Duration? loopPointB;
  final bool abLoopEnabled;
  final bool isPlaying;
  final bool isDragging;
  final bool isRtl;
  final bool isDark;

  _OscilloscopeWaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.unplayedColor,
    required this.playheadCoreColor,
    required this.duration,
    required this.loopPointA,
    required this.loopPointB,
    required this.abLoopEnabled,
    required this.isPlaying,
    required this.isDragging,
    required this.isRtl,
    required this.isDark,
  });

  static TextPainter _getPinTextPainter(String tag, Color activeColor) {
    final textColor = AppColors.textOnAccent(activeColor);
    if (_lastPinTextColor != textColor) {
      _pinTextPainters.clear();
      _lastPinTextColor = textColor;
    }
    return _pinTextPainters.putIfAbsent(
      tag,
      () => TextPainter(
        text: TextSpan(
          text: tag,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    if (isRtl) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    final double padX = AppSpacing.sm;
    final double usableW = math.max(1.0, size.width - padX * 2);
    final double usableH = math.max(12.0, size.height - AppSpacing.md * 2);
    final double midY = size.height / 2;
    final double playheadX = padX + usableW * progress.clamp(0.0, 1.0);

    // 1. A/B Loop shaded region & markers (when active).
    final int durMs = duration.inMilliseconds;
    if (durMs > 0 && (loopPointA != null || loopPointB != null)) {
      final double? ax = loopPointA != null
          ? padX +
              usableW * (loopPointA!.inMilliseconds / durMs).clamp(0.0, 1.0)
          : null;
      final double? bx = loopPointB != null
          ? padX +
              usableW * (loopPointB!.inMilliseconds / durMs).clamp(0.0, 1.0)
          : null;

      if (ax != null && bx != null) {
        final left = math.min(ax, bx);
        final right = math.max(ax, bx);
        canvas.drawRect(
          Rect.fromLTRB(left, 0, right, size.height),
          _loopShadePaint
            ..color = activeColor.withValues(
              alpha: abLoopEnabled ? 0.16 : 0.08,
            ),
        );
      }

      void drawPin(double x, String tag) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          _loopPinLinePaint
            ..color = activeColor.withValues(alpha: abLoopEnabled ? 0.85 : 0.55)
            ..strokeWidth = 1.4,
        );
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 9, 4, 18, 16),
          const Radius.circular(AppRadii.r4),
        );
        canvas.drawRRect(
          badgeRect,
          _loopBadgePaint..color = activeColor,
        );
        final tp = _getPinTextPainter(tag, activeColor);
        if (isRtl) {
          canvas.save();
          canvas.translate(x, 12);
          canvas.scale(-1, 1);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
        } else {
          tp.paint(canvas, Offset(x - tp.width / 2, 12 - tp.height / 2));
        }
      }

      if (ax != null) drawPin(ax, 'A');
      if (bx != null) drawPin(bx, 'B');
    }

    // 2. Resample peaks smoothly to match viewport density (~3.5dp per bar).
    final int targetBars = (usableW / 4.2).round().clamp(24, 110);
    final List<double> bars;
    if (identical(_lastSamples, samples) &&
        _lastTargetBars == targetBars &&
        _cachedBars != null) {
      bars = _cachedBars!;
    } else {
      bars = List<double>.generate(targetBars, (i) {
        final double pos = samples.length == 1
            ? 0.0
            : (i / (targetBars - 1)) * (samples.length - 1);
        final int lo = pos.floor().clamp(0, samples.length - 1);
        final int hi = (lo + 1).clamp(0, samples.length - 1);
        final double frac = pos - lo;
        return (samples[lo] * (1.0 - frac) + samples[hi] * frac)
            .clamp(0.05, 1.0);
      }, growable: false);
      _lastSamples = samples;
      _lastTargetBars = targetBars;
      _cachedBars = bars;
    }

    final double slot = usableW / targetBars;
    final double barW = math.max(1.8, slot * 0.56);
    final double ampScale = isDragging ? 1.08 : 0.96;

    final unplayedPaint = _unplayedPaint..color = unplayedColor;
    final int shaderKey = Object.hash(
      activeColor,
      playheadCoreColor,
      isDark,
      padX,
      usableW,
      size.height,
    );
    if (_lastShaderKey != shaderKey || _cachedPlayedShader == null) {
      _lastShaderKey = shaderKey;
      _cachedPlayedShader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          activeColor.withValues(alpha: 0.95),
          Color.lerp(activeColor, playheadCoreColor, isDark ? 0.28 : 0.10)!,
          activeColor.withValues(alpha: 0.95),
        ],
      ).createShader(Rect.fromLTWH(padX, 0, usableW, size.height));
    }
    final playedPaint = _playedPaint..shader = _cachedPlayedShader;

    final topEnvelope = _topEnvelope..reset();
    final bottomEnvelope = _bottomEnvelope..reset();

    for (int i = 0; i < targetBars; i++) {
      final double cx = padX + slot * (i + 0.5);
      final double peakH = (bars[i] * usableH * ampScale).clamp(4.0, usableH);
      final double topY = midY - peakH / 2;
      final double bottomY = midY + peakH / 2;

      if (i == 0) {
        topEnvelope.moveTo(cx, topY);
        bottomEnvelope.moveTo(cx, bottomY);
      } else {
        topEnvelope.lineTo(cx, topY);
        bottomEnvelope.lineTo(cx, bottomY);
      }

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, midY),
          width: barW,
          height: peakH,
        ),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rrect, cx <= playheadX ? playedPaint : unplayedPaint);
    }

    // 3. Luminous oscilloscope trace crest clipped to the played region.
    if (progress > 0.005) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(padX, 0, playheadX, size.height));
      final crestPaint = _crestPaint
        ..color = Color.lerp(activeColor, playheadCoreColor, 0.45)!
            .withValues(alpha: isDark ? 0.72 : 0.55);
      canvas.drawPath(topEnvelope, crestPaint);
      canvas.drawPath(bottomEnvelope, crestPaint);
      canvas.restore();
    }

    // 4. Glowing active oscilloscope playhead cursor + diamond reticle caps.
    if (!GpuBudget.isGpuSaverActive && (isPlaying || isDragging)) {
      canvas.drawLine(
        Offset(playheadX, 2),
        Offset(playheadX, size.height - 2),
        _playheadGlowPaint
          ..color = activeColor.withValues(alpha: isDragging ? 0.65 : 0.45)
          ..strokeWidth = isDragging ? 7.0 : 5.5,
      );
    }

    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      _playheadCorePaint
        ..color = playheadCoreColor
        ..strokeWidth = isDragging ? 2.2 : 1.8,
    );

    // Top & bottom precision triangular reticle markers.
    final markerPaint = _markerPaint..color = activeColor;
    final topCap = _topCap
      ..reset()
      ..moveTo(playheadX, 8)
      ..lineTo(playheadX - 5, 0)
      ..lineTo(playheadX + 5, 0)
      ..close();
    final bottomCap = _bottomCap
      ..reset()
      ..moveTo(playheadX, size.height - 8)
      ..lineTo(playheadX - 5, size.height)
      ..lineTo(playheadX + 5, size.height)
      ..close();
    canvas.drawPath(topCap, markerPaint);
    canvas.drawPath(bottomCap, markerPaint);

    if (isRtl) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OscilloscopeWaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.unplayedColor != unplayedColor ||
      oldDelegate.playheadCoreColor != playheadCoreColor ||
      oldDelegate.duration != duration ||
      oldDelegate.loopPointA != loopPointA ||
      oldDelegate.loopPointB != loopPointB ||
      oldDelegate.abLoopEnabled != abLoopEnabled ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.isDragging != isDragging ||
      oldDelegate.isRtl != isRtl ||
      oldDelegate.isDark != isDark;
}
