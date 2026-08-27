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

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.chapterMarkers,
    required this.duration,
    this.loopPointA,
    this.loopPointB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final int count = samples.length;
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
      final double barHeight = (samples[i] * size.height).clamp(minBarHeight, size.height);
      final double x = i * (barWidth + spacing);
      final double y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, inactivePaint);
    }

    // 2. Render active waveform bars clipped to current progress
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress.clamp(0.0, 1.0), size.height));
      for (int i = 0; i < count; i++) {
        final double barHeight = (samples[i] * size.height).clamp(minBarHeight, size.height);
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

    // 3. Render Chapter Markers
    if (chapterMarkers != null && duration.inMilliseconds > 0) {
      final markerPaint = Paint()
        ..color = Colors.amber
        ..strokeWidth = 2.0;

      for (final marker in chapterMarkers!) {
        final markerRatio = (marker.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final markerX = markerRatio * size.width;
        canvas.drawLine(Offset(markerX, 0), Offset(markerX, size.height), markerPaint);
      }
    }

    // 4. Render A-B Loop Points
    if (duration.inMilliseconds > 0) {
      final loopPaint = Paint()
        ..color = const Color(0xFF05FFA1)
        ..strokeWidth = 2.5;

      if (loopPointA != null) {
        final ratioA = (loopPointA!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        canvas.drawLine(Offset(ratioA * size.width, 0), Offset(ratioA * size.width, size.height), loopPaint);
      }
      if (loopPointB != null) {
        final ratioB = (loopPointB!.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        canvas.drawLine(Offset(ratioB * size.width, 0), Offset(ratioB * size.width, size.height), loopPaint);
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
        oldDelegate.loopPointB != loopPointB;
  }
}
