// lib/features/player/presentation/widgets/waveform_seek_bar.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';

/// A interactive gesture-driven waveform seek bar widget.
class WaveformSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final List<double> samples;
  final Color activeColor;
  final Color? inactiveColor;
  final double height;

  const WaveformSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.samples,
    this.activeColor = Colors.white,
    this.inactiveColor,
    this.height = 44.0,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final double maxDuration = widget.duration.inMilliseconds.toDouble();
    final double currentPos = widget.position.inMilliseconds.toDouble();
    final double effectiveValue = (_dragValue ?? currentPos).clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
    final double progressPercent = maxDuration > 0 ? (effectiveValue / maxDuration).clamp(0.0, 1.0) : 0.0;
    final Color inactiveColor = widget.inactiveColor ?? Colors.white.withValues(alpha: 0.25);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Interactive Waveform Area
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  if (trackWidth > 0 && maxDuration > 0) {
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
                    widget.onSeek(Duration(milliseconds: _dragValue!.round()));
                    setState(() {
                      _dragValue = null;
                    });
                  }
                },
                onTapDown: (details) {
                  if (trackWidth > 0 && maxDuration > 0) {
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
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
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
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.samples != samples ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
