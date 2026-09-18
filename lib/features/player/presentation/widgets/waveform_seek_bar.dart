// lib/features/player/presentation/widgets/waveform_seek_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  final String? semanticLabel;

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
    this.semanticLabel,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  double? _dragValue;
  double _zoomScale = 1.0;

  @override
  void didUpdateWidget(covariant WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New track => new waveform/duration: reset zoom & transient scrub state so
    // the visible window always matches the samples being painted.
    if (!identical(oldWidget.samples, widget.samples) ||
        oldWidget.duration != widget.duration) {
      _zoomScale = 1.0;
      _dragValue = null;
    }
  }

  /// The slice of samples currently rendered, centered on the committed
  /// playback position. Gesture hit-testing and the painter MUST agree on this
  /// window, otherwise a zoomed seek lands on the wrong timestamp.
  ({int startIndex, int visibleCount}) _visibleWindow(int totalCount) {
    if (totalCount < 2) return (startIndex: 0, visibleCount: totalCount);
    final int visibleCount = (totalCount / _zoomScale.clamp(1.0, 8.0))
        .round()
        .clamp(2, totalCount);
    final double centerRatio = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;
    final int centerIndex = (centerRatio * totalCount).round();
    final int halfVisible = visibleCount ~/ 2;
    final int startIndex =
        (centerIndex - halfVisible).clamp(0, totalCount - visibleCount);
    return (startIndex: startIndex, visibleCount: visibleCount);
  }

  /// Maps a local X coordinate to a global 0..1 ratio through the visible
  /// window, so zoomed scrubbing is accurate.
  double _ratioForDx(double dx, double trackWidth, int totalCount) {
    if (trackWidth <= 0 || totalCount <= 0) return 0.0;
    final window = _visibleWindow(totalCount);
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
            ? Colors.white.withValues(alpha: 0.22)
            : p.hairline.withValues(alpha: 0.8));

    final currentDuration = _dragValue != null
        ? Duration(milliseconds: _dragValue!.round())
        : widget.position;
    final valueLabel =
        '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(widget.duration)}';

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

    return Semantics(
      slider: true,
      label: widget.semanticLabel ?? context.l10n.seekLabel,
      value: valueLabel,
      increasedValue: increasedLabel,
      decreasedValue: decreasedLabel,
      onIncrease: () => widget.onSeek(
          clampDuration(currentDuration + const Duration(seconds: 10))),
      onDecrease: () => widget.onSeek(
          clampDuration(currentDuration - const Duration(seconds: 10))),
      child: Directionality(
      textDirection: TextDirection.ltr,
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
                        setState(() {
                          _zoomScale =
                              (_zoomScale * details.scale).clamp(1.0, 4.0);
                        });
                      }
                    },
                    onHorizontalDragStart: (details) {
                      if (trackWidth > 0 && maxDuration > 0) {
                        HapticFeedback.selectionClick();
                        final ratio =
                            _ratioForDx(details.localPosition.dx, trackWidth, totalCount);
                        setState(() {
                          _dragValue = ratio * maxDuration;
                        });
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      if (trackWidth > 0 && maxDuration > 0) {
                        final ratio =
                            _ratioForDx(details.localPosition.dx, trackWidth, totalCount);
                        setState(() {
                          _dragValue = ratio * maxDuration;
                        });
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_dragValue != null) {
                        HapticFeedback.lightImpact();
                        widget.onSeek(
                            Duration(milliseconds: _dragValue!.round()));
                        setState(() {
                          _dragValue = null;
                        });
                      }
                    },
                    onTapDown: (details) {
                      if (trackWidth > 0 && maxDuration > 0) {
                        HapticFeedback.selectionClick();
                        final ratio =
                            _ratioForDx(details.localPosition.dx, trackWidth, totalCount);
                        final seekMs = ratio * maxDuration;
                        widget.onSeek(Duration(milliseconds: seekMs.round()));
                      }
                    },
                    child: SizedBox(
                      height: widget.height,
                      width: double.infinity,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
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
                                zoomScale: _zoomScale,
                                visibleStart: window.startIndex,
                                visibleCount: window.visibleCount,
                              ),
                            ),
                          ),
                          // Scrub preview bubble follows the finger while dragging.
                          if (_dragValue != null)
                            PositionedDirectional(
                              top: -30,
                              start: (progressPercent * trackWidth - 32)
                                  .clamp(0.0, (trackWidth - 64).clamp(0.0, trackWidth)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.s2),
                                decoration: BoxDecoration(
                                  color: context.palette.surfaceContainerHigh,
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.r8),
                                  border:
                                      Border.all(color: context.palette.hairline),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  Formatters.formatDuration(currentDuration),
                                  style: TextStyle(
                                    color: context.palette.textPrimary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xxs),
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
  final double zoomScale;
  final int visibleStart;
  final int visibleCount;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.chapterMarkers,
    required this.duration,
    this.loopPointA,
    this.loopPointB,
    this.zoomScale = 1.0,
    this.visibleStart = 0,
    this.visibleCount = 0,
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
    final int visible = endIndex - startIndex;
    final visibleSamples = samples.sublist(startIndex, endIndex);

    final int count = visibleSamples.length;
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

    // 1. Render inactive waveform bars
    for (int i = 0; i < count; i++) {
      final double barHeight =
          (visibleSamples[i] * size.height).clamp(minBarHeight, size.height);
      final double x = i * (barWidth + spacing);
      final double y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(AppRadii.r2),
      );
      canvas.drawRRect(rect, inactivePaint);
    }

    // 2. Render active waveform bars clipped to current progress in visible window
    final double visibleProgress =
        ((progress * totalCount - startIndex) / visible).clamp(0.0, 1.0);
    if (visibleProgress > 0) {
      canvas.save();
      canvas.clipRect(
          Rect.fromLTWH(0, 0, size.width * visibleProgress, size.height));
      for (int i = 0; i < count; i++) {
        final double barHeight =
            (visibleSamples[i] * size.height).clamp(minBarHeight, size.height);
        final double x = i * (barWidth + spacing);
        final double y = (size.height - barHeight) / 2;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(AppRadii.r2),
        );
        canvas.drawRRect(rect, activePaint);
      }
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

      // Shade the looping region so the A-B span reads at a glance.
      if (xA != null && xB != null) {
        final left = xA < xB ? xA : xB;
        final right = xA < xB ? xB : xA;
        canvas.drawRect(
          Rect.fromLTRB(left, 0, right, size.height),
          Paint()..color = activeColor.withValues(alpha: 0.12),
        );
      }

      if (xA != null) {
        canvas.drawLine(Offset(xA, 0), Offset(xA, size.height), loopPaint);
      }
      if (xB != null) {
        canvas.drawLine(Offset(xB, 0), Offset(xB, size.height), loopPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.samples != samples ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.chapterMarkers != chapterMarkers ||
        oldDelegate.loopPointA != loopPointA ||
        oldDelegate.loopPointB != loopPointB ||
        oldDelegate.zoomScale != zoomScale;
  }
}
