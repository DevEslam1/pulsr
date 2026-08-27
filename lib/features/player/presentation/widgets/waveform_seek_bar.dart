// lib/features/player/presentation/widgets/waveform_seek_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';

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
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  double? _dragValue;
  double _zoomScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final double maxDuration = widget.duration.inMilliseconds.toDouble();
    final double currentPos = widget.position.inMilliseconds.toDouble();
    final double effectiveValue = (_dragValue ?? currentPos).clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
    final double progressPercent = maxDuration > 0 ? (effectiveValue / maxDuration).clamp(0.0, 1.0) : 0.0;
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color inactiveColor = widget.inactiveColor ??
        (isDark ? Colors.white.withValues(alpha: 0.22) : p.hairline.withValues(alpha: 0.8));

    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Interactive Waveform Area with Pinch-to-Zoom
              LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleUpdate: (details) {
                      if (details.scale != 1.0) {
                        setState(() {
                          _zoomScale = (_zoomScale * details.scale).clamp(1.0, 4.0);
                        });
                      }
                    },
                    onHorizontalDragStart: (details) {
                      if (trackWidth > 0 && maxDuration > 0) {
                        HapticFeedback.selectionClick();
                        final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                        setState(() {
                          _dragValue = ratio * maxDuration;
                        });
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      if (trackWidth > 0 && maxDuration > 0) {
                        final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                        setState(() {
                          _dragValue = ratio * maxDuration;
                        });
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_dragValue != null) {
                        HapticFeedback.lightImpact();
                        widget.onSeek(Duration(milliseconds: _dragValue!.round()));
                        setState(() {
                          _dragValue = null;
                        });
                      }
                    },
                    onTapDown: (details) {
                      if (trackWidth > 0 && maxDuration > 0) {
                        HapticFeedback.selectionClick();
                        final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                        final seekMs = ratio * maxDuration;
                        widget.onSeek(Duration(milliseconds: seekMs.round()));
                      }
                    },
                    child: SizedBox(
                      height: widget.height,
                      width: double.infinity,
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
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              // Timestamps Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    Formatters.formatDuration(
                      _dragValue != null ? Duration(milliseconds: _dragValue!.round()) : widget.position,
                    ),
                    style: TextStyle(
                      color: context.palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    Formatters.formatDuration(widget.duration),
                    style: TextStyle(
                      color: context.palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final int totalCount = samples.length;
    if (totalCount < 2) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, (size.height - 4) / 2, size.width, 4),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = inactiveColor);
      return;
    }

    final int visibleCount = (totalCount / zoomScale.clamp(1.0, 8.0)).round().clamp(2, totalCount);
    final int centerIndex = (progress * totalCount).round();
    final int halfVisible = visibleCount ~/ 2;
    final int startIndex = (centerIndex - halfVisible).clamp(0, totalCount - visibleCount);
    final int endIndex = (startIndex + visibleCount).clamp(0, totalCount);
    final visibleSamples = samples.sublist(startIndex, endIndex);

    final int count = visibleSamples.length;
    const double spacing = 2.5;
    final double totalSpacing = spacing * (count - 1);
    final double barWidth = ((size.width - totalSpacing) / count).clamp(1.0, 12.0);
    const double minBarHeight = 4.0;

    final Paint inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final Paint activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    // 1. Render inactive waveform bars
    for (int i = 0; i < count; i++) {
      final double barHeight = (visibleSamples[i] * size.height).clamp(minBarHeight, size.height);
      final double x = i * (barWidth + spacing);
      final double y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, inactivePaint);
    }

    // 2. Render active waveform bars clipped to current progress in visible window
    final double visibleProgress = ((progress * totalCount - startIndex) / visibleCount).clamp(0.0, 1.0);
    if (visibleProgress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * visibleProgress, size.height));
      for (int i = 0; i < count; i++) {
        final double barHeight = (visibleSamples[i] * size.height).clamp(minBarHeight, size.height);
        final double x = i * (barWidth + spacing);
        final double y = (size.height - barHeight) / 2;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        );
        canvas.drawRRect(rect, activePaint);
      }
      canvas.restore();
    }

    // Helper for mapping global progress (0..1) to visible X coordinate
    double? mapToVisibleX(double globalRatio) {
      final sampleIdx = globalRatio * totalCount;
      if (sampleIdx < startIndex || sampleIdx > endIndex) return null;
      return ((sampleIdx - startIndex) / visibleCount) * size.width;
    }

    // 3. Render Chapter Markers
    if (chapterMarkers != null && duration.inMilliseconds > 0) {
      final markerPaint = Paint()
        ..color = Colors.amber
        ..strokeWidth = 2.0;

      for (final marker in chapterMarkers!) {
        final markerRatio = (marker.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final markerX = mapToVisibleX(markerRatio);
        if (markerX != null) {
          canvas.drawLine(Offset(markerX, 0), Offset(markerX, size.height), markerPaint);
        }
      }
    }

    // 4. Render A-B Loop Points
    if (duration.inMilliseconds > 0) {
      final loopPaint = Paint()
        ..color = const Color(0xFF05FFA1)
        ..strokeWidth = 2.5;

      if (loopPointA != null) {
        final ratioA = (loopPointA!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final xA = mapToVisibleX(ratioA);
        if (xA != null) {
          canvas.drawLine(Offset(xA, 0), Offset(xA, size.height), loopPaint);
        }
      }
      if (loopPointB != null) {
        final ratioB = (loopPointB!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final xB = mapToVisibleX(ratioB);
        if (xB != null) {
          canvas.drawLine(Offset(xB, 0), Offset(xB, size.height), loopPaint);
        }
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
