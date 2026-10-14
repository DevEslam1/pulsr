// lib/features/player/presentation/widgets/waveform_seek_bar.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../cubit/player_constants.dart';
import '../../cubit/player_cubit.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// Visual rendering style for the waveform seek bar.
enum WaveformVisualizerStyle {
  mirroredBars,
  roundedTopBars,
  continuousEnvelope,
  neonGlowLine,
}

/// Interactive gesture-driven waveform seek bar widget with pinch-to-zoom and chapter marker support.
class WaveformSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final List<double> samples;
  final Color activeColor;
  final Color? inactiveColor;
  final double height;
  final List<Duration>? chapterMarkers;
  final Duration? loopPointA;
  final Duration? loopPointB;
  final Duration? crossfadeDuration;
  final String? semanticLabel;
  final WaveformVisualizerStyle style;

  /// When false the bar renders but ignores scrub/tap seeks (e.g. while the
  /// engine is still loading/buffering). Pinch-to-zoom stays available.
  final bool enabled;

  const WaveformSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.samples,
    this.activeColor = Colors.white,
    this.inactiveColor,
    this.height = 44.0,
    this.chapterMarkers,
    this.loopPointA,
    this.loopPointB,
    this.crossfadeDuration,
    this.semanticLabel,
    this.style = WaveformVisualizerStyle.mirroredBars,
    this.enabled = true,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  double? _dragValue;
  double? _dragStartValue;
  double? _lastHapticCheckMs;
  ({int startIndex, int visibleCount})? _dragFrozenWindow;
  double _zoomScale = 1.0;
  int _lastScaleMs = 0;
  bool _dragStarted = false;

  void _checkHapticBoundaries(double oldVal, double newVal, BuildContext context) {
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
  void didUpdateWidget(covariant WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New track => new waveform/duration: reset zoom & transient scrub state so
    // the visible window always matches the samples being painted.
    if (!listEquals(oldWidget.samples, widget.samples) ||
        oldWidget.duration != widget.duration) {
      _zoomScale = 1.0;
      _dragFrozenWindow = null;
      if (_dragValue != null && widget.duration.inMilliseconds > 0) {
        _dragValue =
            _dragValue!.clamp(0.0, widget.duration.inMilliseconds.toDouble());
      }
    }
  }

  /// Raw visible-window computation for the current zoom, ignoring any frozen
  /// window. Kept separate so a zoom change mid-drag can refresh the freeze
  /// instead of reusing a stale range (BUG-08).
  ({int startIndex, int visibleCount}) _computeWindow(int totalCount) {
    if (totalCount <= 0) return (startIndex: 0, visibleCount: 0);
    if (totalCount == 1) return (startIndex: 0, visibleCount: 1);
    final int visibleCount = (totalCount /
            _zoomScale.clamp(PlayerConstants.waveformMinZoom,
                PlayerConstants.waveformMaxZoom))
        .round()
        .clamp(2, totalCount);
    final effectiveMs = widget.position.inMilliseconds.toDouble();
    final double centerRatio = widget.duration.inMilliseconds > 0
        ? effectiveMs / widget.duration.inMilliseconds
        : 0.0;
    final int centerIndex = (centerRatio.clamp(0.0, 1.0) * totalCount).round();
    final int halfVisible = visibleCount ~/ 2;
    final int startIndex =
        (centerIndex - halfVisible).clamp(0, totalCount - visibleCount);
    return (startIndex: startIndex, visibleCount: visibleCount);
  }

  // FIX-M8 / H-07 / B-9: Guard against totalCount <= 0 and freeze visible window during drag
  // to avoid coordinate feedback jitter on fast scrubbing.
  ({int startIndex, int visibleCount}) _visibleWindow(int totalCount) {
    if (_dragFrozenWindow != null) return _dragFrozenWindow!;
    return _computeWindow(totalCount);
  }

  /// Maps a local X coordinate to a global 0..1 ratio through the visible
  /// window, so zoomed scrubbing is accurate.
  double _ratioForDx(double dx, double trackWidth, int totalCount) {
    if (trackWidth <= 0 || totalCount <= 0) return 0.0;
    final window = _visibleWindow(totalCount);
    if (window.visibleCount <= 0) return 0.0;
    final double ratioInWindow = (dx / trackWidth).clamp(0.0, 1.0);
    final double globalRatio =
        (window.startIndex + ratioInWindow * window.visibleCount) / totalCount;
    return globalRatio.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final double maxDuration = widget.duration.inMilliseconds.toDouble();
    final double currentPos = widget.position.inMilliseconds.toDouble();
    final double effectiveValue = (_dragValue ?? currentPos)
        .clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
    final double progressPercent =
        maxDuration > 0 ? (effectiveValue / maxDuration).clamp(0.0, 1.0) : 0.0;
    final int totalCount = widget.samples.length;
    final window = _visibleWindow(totalCount);
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color inactiveColor = widget.inactiveColor ??
        (isDark
            ? AppColors.specularAt(0.22)
            : p.hairline.withValues(alpha: 0.8));

    final currentDuration = _dragValue != null
        ? Duration(milliseconds: _dragValue!.round())
        : widget.position;
    final durationStr =
        '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(widget.duration)}';
    final valueLabel = _zoomScale > 1.05
        ? '$durationStr (${_zoomScale.toStringAsFixed(1)}x zoom)'
        : durationStr;

    Duration clampDuration(Duration d) {
      if (d < Duration.zero) return Duration.zero;
      if (d > widget.duration) return widget.duration;
      return d;
    }

    String labelFor(Duration d) =>
        '${Formatters.formatDuration(d)} / ${Formatters.formatDuration(widget.duration)}';
    final increasedLabel =
        labelFor(clampDuration(currentDuration + const Duration(seconds: 10)));
    final decreasedLabel =
        labelFor(clampDuration(currentDuration - const Duration(seconds: 10)));

    return RepaintBoundary(
      child: Semantics(
        slider: true,
        label: widget.semanticLabel ?? context.l10n.seekLabel,
        value: valueLabel,
        increasedValue: increasedLabel,
        decreasedValue: decreasedLabel,
        onIncrease: widget.enabled
            ? () => widget.onSeek(
                clampDuration(currentDuration + const Duration(seconds: 10)))
            : null,
        onDecrease: widget.enabled
            ? () => widget.onSeek(
                clampDuration(currentDuration - const Duration(seconds: 10)))
            : null,
        child: Directionality(
          textDirection: Directionality.of(context),
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Interactive Waveform Area with Pinch-to-Zoom
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final trackWidth = constraints.maxWidth;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () {
                          if (_zoomScale > 1.0) {
                            HapticFeedback.selectionClick();
                            setState(() => _zoomScale = 1.0);
                          }
                        },
                        onScaleUpdate: (details) {
                          if (details.scale != 1.0) {
                            final now = DateTime.now().millisecondsSinceEpoch;
                            if (now - _lastScaleMs >= 33) {
                              _lastScaleMs = now;
                              setState(() {
                                // BUG-28: clamp the gesture factor before applying
                                // it so an extreme pinch cannot overflow.
                                final clampedScale =
                                    details.scale.clamp(0.1, 10.0);
                                _zoomScale = (_zoomScale * clampedScale).clamp(
                                    PlayerConstants.waveformMinZoom,
                                    PlayerConstants.waveformMaxZoom);
                                // BUG-08: if a scrub is in progress, re-freeze the
                                // window at the new zoom so coordinate mapping stays
                                // accurate.
                                if (_dragFrozenWindow != null) {
                                  _dragFrozenWindow =
                                      _computeWindow(totalCount);
                                  // AUDIT-FIX: Recompute _dragValue to keep thumb ratio stable under new window
                                  if (_dragValue != null &&
                                      widget.duration.inMilliseconds > 0) {
                                    final ratio = (_dragValue! /
                                            widget.duration.inMilliseconds)
                                        .clamp(0.0, 1.0);
                                    _dragValue = (ratio *
                                            widget.duration.inMilliseconds)
                                        .clamp(
                                            0.0,
                                            widget.duration.inMilliseconds
                                                .toDouble());
                                  }
                                }
                              });
                            }
                          }
                        },
                        onHorizontalDragStart: (details) {
                          if (!widget.enabled) return;
                          _dragStarted = true;
                          if (trackWidth > 0 && maxDuration > 0) {
                            HapticFeedback.selectionClick();
                            _dragFrozenWindow = _visibleWindow(totalCount);
                            final ratio = _ratioForDx(details.localPosition.dx,
                                trackWidth, totalCount);
                            final seekVal =
                                (ratio * maxDuration).clamp(0.0, maxDuration);
                            _dragStartValue = seekVal;
                            _lastHapticCheckMs = seekVal;
                            setState(() {
                              _dragValue = seekVal;
                            });
                          }
                        },
                        onHorizontalDragUpdate: (details) {
                          if (!widget.enabled) return;
                          if (trackWidth > 0 && maxDuration > 0) {
                            final ratio = _ratioForDx(details.localPosition.dx,
                                trackWidth, totalCount);
                            final seekVal =
                                (ratio * maxDuration).clamp(0.0, maxDuration);
                            if (_lastHapticCheckMs != null) {
                              _checkHapticBoundaries(
                                  _lastHapticCheckMs!, seekVal, context);
                            }
                            _lastHapticCheckMs = seekVal;
                            setState(() {
                              _dragValue = seekVal;
                            });
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (!widget.enabled) return;
                          _dragStarted = false;
                          if (_dragValue != null) {
                            HapticFeedback.lightImpact();
                            widget.onSeek(
                                Duration(milliseconds: _dragValue!.round()));
                            setState(() {
                              _dragValue = null;
                              _dragStartValue = null;
                              _lastHapticCheckMs = null;
                              _dragFrozenWindow = null;
                            });
                          }
                        },
                        onHorizontalDragCancel: () {
                          if (!widget.enabled) return;
                          _dragStarted = false;
                          if (_dragValue != null) {
                            setState(() {
                              _dragValue = null;
                              _dragStartValue = null;
                              _lastHapticCheckMs = null;
                              _dragFrozenWindow = null;
                            });
                          }
                        },
                        // A press that never becomes a drag seeks on release;
                        // the tap recognizer's deadline fires onTapDown on a
                        // slow press, so seeking there jumped playback before
                        // the drag could win the arena.
                        onTapUp: (details) {
                          if (!widget.enabled) return;
                          if (_dragStarted) return;
                          if (trackWidth > 0 && maxDuration > 0) {
                            HapticFeedback.selectionClick();
                            final ratio = _ratioForDx(details.localPosition.dx,
                                trackWidth, totalCount);
                            final seekMs = ratio * maxDuration;
                            widget
                                .onSeek(Duration(milliseconds: seekMs.round()));
                          }
                        },
                        child: AnimatedContainer(
                          duration: context.motionMs(200),
                          curve: Curves.easeOutCubic,
                          height: _dragValue != null
                              ? widget.height + 12.0
                              : widget.height,
                          width: double.infinity,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: Semantics(
                                    label: context.l10n.waveformSeekBar,
                                    value:
                                        '${Formatters.formatDuration(currentDuration)} / '
                                        '${Formatters.formatDuration(widget.duration)}',
                                    child: CustomPaint(
                                      painter: _WaveformPainter(
                                        samples: widget.samples,
                                        progress: progressPercent,
                                        activeColor: widget.activeColor,
                                        inactiveColor: inactiveColor,
                                        chapterMarkers: widget.chapterMarkers,
                                        duration: widget.duration,
                                        loopPointA: widget.loopPointA,
                                        loopPointB: widget.loopPointB,
                                        crossfadeDuration:
                                            widget.crossfadeDuration,
                                        zoomScale: _zoomScale,
                                        visibleStart: window.startIndex,
                                        visibleCount: window.visibleCount,
                                        style: widget.style,
                                        amplitudeScale:
                                            _dragValue != null ? 1.25 : 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Scrub preview bubble follows the finger while dragging.
                              if (_dragValue != null)
                                () {
                                  final deltaMs = _dragStartValue != null
                                      ? (_dragValue! - _dragStartValue!).round()
                                      : 0;
                                  final deltaStr = deltaMs == 0
                                      ? '±0:00'
                                      : '${deltaMs > 0 ? '+' : '-'}${Formatters.formatDuration(Duration(milliseconds: deltaMs.abs()))}';

                                  return PositionedDirectional(
                                    top: -34,
                                    start: (progressPercent * trackWidth - 48)
                                        .clamp(
                                            0.0,
                                            (trackWidth - 96)
                                                .clamp(0.0, trackWidth)),
                                    child: IgnorePointer(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.s8,
                                            vertical: AppSpacing.s4),
                                        decoration: BoxDecoration(
                                          color: context
                                              .palette.surfaceContainerHigh
                                              .withValues(alpha: 0.90),
                                          borderRadius: AppRadii.r12All,
                                          border: Border.all(
                                            color: context.palette.hairline
                                                .withValues(alpha: 0.6),
                                            width: 1.0,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.30),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
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
                                  );
                                }(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Timestamps Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Formatters.formatDuration(
                          _dragValue != null
                              ? Duration(milliseconds: _dragValue!.round())
                              : widget.position,
                        ),
                        style: TextStyle(
                          color: context.palette.textSecondary,
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_zoomScale > 1.05)
                        Semantics(
                          button: true,
                          label: context.l10n.resetWaveformZoom,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _zoomScale = 1.0);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s6,
                                  vertical: AppSpacing.s2),
                              decoration: BoxDecoration(
                                color: context.palette.accent
                                    .withValues(alpha: 0.15),
                                borderRadius: AppRadii.r6All,
                                border: Border.all(
                                  color: context.palette.accent
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_zoomScale.toStringAsFixed(1)}x',
                                    style: TextStyle(
                                      color: context.palette.accent,
                                      fontSize: AppFontSize.tiny,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s2),
                                  Icon(
                                    Icons.close_rounded,
                                    size: 12,
                                    color: context.palette.accent,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Text(
                        Formatters.formatDuration(widget.duration),
                        style: TextStyle(
                          color: context.palette.textSecondary,
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;
  final List<Duration>? chapterMarkers;
  final Duration duration;
  final Duration? loopPointA;
  final Duration? loopPointB;
  final Duration? crossfadeDuration;
  final double zoomScale;
  final int visibleStart;
  final int visibleCount;
  final WaveformVisualizerStyle style;
  final double amplitudeScale;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.chapterMarkers,
    required this.duration,
    this.loopPointA,
    this.loopPointB,
    this.crossfadeDuration,
    this.zoomScale = 1.0,
    this.visibleStart = 0,
    this.visibleCount = 0,
    this.style = WaveformVisualizerStyle.mirroredBars,
    this.amplitudeScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final int totalCount = samples.length;
    if (totalCount < 2) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, (size.height - 4) / 2, size.width, 4),
        const Radius.circular(AppRadii.r2),
      );
      canvas.drawRRect(rect, Paint()..color = inactiveColor);
      return;
    }

    // Window is computed by the widget so hit-testing and painting stay in sync.
    final int endBound = (visibleStart + visibleCount).clamp(2, totalCount);
    final int startIndex = visibleStart.clamp(0, endBound - 2);
    final int endIndex = endBound;
    // BUG-16: never call sublist with an inverted range.
    if (startIndex >= endIndex || endIndex > totalCount) return;
    final int visible = endIndex - startIndex;
    final visibleSamples = samples.sublist(startIndex, endIndex);

    final int count = visibleSamples.length;
    // FIX-M8: Guard visible < 2 and count < 2 to prevent division by zero
    if (count < 2 || visible < 2) return;
    const double spacing = 2.5;
    final double totalSpacing = spacing * (count - 1);
    final double barWidth =
        ((size.width - totalSpacing) / count).clamp(1.0, 12.0);
    const double minBarHeight = 4.0;

    final Paint inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final Paint activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    void drawWaveform(Paint paint) {
      switch (style) {
        case WaveformVisualizerStyle.mirroredBars:
          for (int i = 0; i < count; i++) {
            final double barHeight =
                (visibleSamples[i] * size.height * amplitudeScale)
                    .clamp(minBarHeight, size.height);
            final double x = i * (barWidth + spacing);
            final double y = (size.height - barHeight) / 2;
            final rect = RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, barWidth, barHeight),
              const Radius.circular(AppRadii.r2),
            );
            canvas.drawRRect(rect, paint);
          }
          break;
        case WaveformVisualizerStyle.roundedTopBars:
          for (int i = 0; i < count; i++) {
            final double barHeight =
                (visibleSamples[i] * size.height * amplitudeScale)
                    .clamp(minBarHeight, size.height);
            final double x = i * (barWidth + spacing);
            final double y = size.height - barHeight;
            final rect = RRect.fromRectAndCorners(
              Rect.fromLTWH(x, y, barWidth, barHeight),
              topLeft: const Radius.circular(AppRadii.r4),
              topRight: const Radius.circular(AppRadii.r4),
            );
            canvas.drawRRect(rect, paint);
          }
          break;
        case WaveformVisualizerStyle.continuousEnvelope:
          final topPath = Path();
          for (int i = 0; i < count; i++) {
            final double barHeight =
                (visibleSamples[i] * size.height * amplitudeScale)
                    .clamp(minBarHeight, size.height);
            final double x = i * (barWidth + spacing) + barWidth / 2;
            final double topY = (size.height - barHeight) / 2;
            if (i == 0) {
              topPath.moveTo(x, topY);
            } else {
              topPath.lineTo(x, topY);
            }
          }
          final combined = Path.from(topPath);
          combined.lineTo(size.width, size.height / 2);
          for (int i = count - 1; i >= 0; i--) {
            final double barHeight =
                (visibleSamples[i] * size.height * amplitudeScale)
                    .clamp(minBarHeight, size.height);
            final double x = i * (barWidth + spacing) + barWidth / 2;
            final double bottomY = (size.height + barHeight) / 2;
            combined.lineTo(x, bottomY);
          }
          combined.close();
          canvas.drawPath(combined, paint);
          break;
        case WaveformVisualizerStyle.neonGlowLine:
          final linePath = Path();
          for (int i = 0; i < count; i++) {
            final double barHeight =
                (visibleSamples[i] * size.height * amplitudeScale)
                    .clamp(minBarHeight, size.height);
            final double x = i * (barWidth + spacing) + barWidth / 2;
            final double y = (size.height - barHeight) / 2;
            if (i == 0) {
              linePath.moveTo(x, y);
            } else {
              linePath.lineTo(x, y);
            }
          }
          final glowPaint = Paint()
            ..color = paint.color.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0)
            ..strokeWidth = 3.5
            ..style = PaintingStyle.stroke;
          canvas.drawPath(linePath, glowPaint);
          final sharpPaint = Paint()
            ..color = paint.color
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          canvas.drawPath(linePath, sharpPaint);
          break;
      }
    }

    // 1. Render inactive waveform
    drawWaveform(inactivePaint);

    // 2. Render active waveform clipped to current progress in visible window
    final double visibleProgress =
        ((progress * totalCount - startIndex) / visible).clamp(0.0, 1.0);
    if (visibleProgress > 0) {
      canvas.save();
      canvas.clipRect(
          Rect.fromLTWH(0, 0, size.width * visibleProgress, size.height));
      drawWaveform(activePaint);
      canvas.restore();
    }

    // Helper for mapping global progress (0..1) to visible X coordinate
    double? mapToVisibleX(double globalRatio) {
      final sampleIdx = globalRatio * totalCount;
      if (sampleIdx < startIndex || sampleIdx > endIndex) return null;
      return ((sampleIdx - startIndex) / visible) * size.width;
    }

    // 3. Render Chapter Markers
    if (chapterMarkers != null && duration.inMilliseconds > 0) {
      final markerPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;

      for (final marker in chapterMarkers!) {
        final markerRatio =
            (marker.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final markerX = mapToVisibleX(markerRatio);
        if (markerX != null) {
          canvas.drawLine(
              Offset(markerX, 0), Offset(markerX, size.height), markerPaint);
        }
      }
    }

    // 4. Render A-B Loop Points (region + edges, theme-aware)
    if (duration.inMilliseconds > 0) {
      final loopPaint = Paint()
        ..color = activeColor
        ..strokeWidth = 2.5;

      double? xA;
      double? xB;
      if (loopPointA != null) {
        xA = mapToVisibleX(
            (loopPointA!.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0));
      }
      if (loopPointB != null) {
        xB = mapToVisibleX(
            (loopPointB!.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0));
      }

      // Shade the looping region so the A-B span reads clearly at any zoom scale.
      if (loopPointA != null && loopPointB != null) {
        final double ratioA =
            (loopPointA!.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        final double ratioB =
            (loopPointB!.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        final double globalMin = math.min(ratioA, ratioB);
        final double globalMax = math.max(ratioA, ratioB);

        final double minVisibleRatio = startIndex / totalCount;
        final double maxVisibleRatio = endIndex / totalCount;

        final double overlapMin = math.max(globalMin, minVisibleRatio);
        final double overlapMax = math.min(globalMax, maxVisibleRatio);

        if (overlapMin < overlapMax) {
          final double leftX =
              ((overlapMin * totalCount - startIndex) / visible) * size.width;
          final double rightX =
              ((overlapMax * totalCount - startIndex) / visible) * size.width;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(leftX, 0, rightX, size.height),
              const Radius.circular(AppRadii.r4),
            ),
            Paint()..color = activeColor.withValues(alpha: 0.22),
          );
        }
      }

      if (xA != null) {
        canvas.drawLine(Offset(xA, 0), Offset(xA, size.height), loopPaint);
      }
      if (xB != null) {
        canvas.drawLine(Offset(xB, 0), Offset(xB, size.height), loopPaint);
      }
    }

    // 5. Render Crossfade Region if configured
    if (crossfadeDuration != null &&
        crossfadeDuration! > Duration.zero &&
        duration > crossfadeDuration!) {
      final double fadeStartRatio =
          ((duration - crossfadeDuration!).inMilliseconds /
                  duration.inMilliseconds)
              .clamp(0.0, 1.0);
      final double? fadeStartX = mapToVisibleX(fadeStartRatio);
      final double? fadeEndX = mapToVisibleX(1.0);
      if (fadeStartX != null && fadeEndX != null && fadeStartX < fadeEndX) {
        final fadeRect = Rect.fromLTRB(fadeStartX, 0, fadeEndX, size.height);
        final fadePaint = Paint()
          ..shader = LinearGradient(
            colors: [
              activeColor.withValues(alpha: 0.0),
              activeColor.withValues(alpha: 0.16),
            ],
          ).createShader(fadeRect);
        canvas.drawRect(fadeRect, fadePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.chapterMarkers != chapterMarkers ||
        oldDelegate.duration != duration ||
        oldDelegate.loopPointA != loopPointA ||
        oldDelegate.loopPointB != loopPointB ||
        oldDelegate.crossfadeDuration != crossfadeDuration ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.visibleStart != visibleStart ||
        oldDelegate.visibleCount != visibleCount ||
        oldDelegate.style != style ||
        oldDelegate.amplitudeScale != amplitudeScale ||
        !listEquals(oldDelegate.samples, samples);
  }
}
