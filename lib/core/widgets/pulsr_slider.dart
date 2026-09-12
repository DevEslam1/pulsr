// lib/core/widgets/pulsr_slider.dart
import 'package:flutter/material.dart';
import '../theme/aura_theme.dart';

/// A lightweight custom-painted slider used across the app.
///
/// Unlike the Material [Slider], this renders via a single
/// [CustomPainter], which keeps the widget tree small and paint work cheap
/// on low-end devices. The track uses a gradient fill with a rounded
/// glow thumb for a premium feel.
class PulsrSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String? semanticLabel;

  /// Height of the track container.
  final double height;

  const PulsrSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.onChanged,
    this.divisions,
    this.semanticLabel,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            void updateFromDx(double dx) {
              if (divisions == null || divisions! <= 0) {
                onChanged(((dx / width).clamp(0.0, 1.0) * (max - min)) + min);
              } else {
                final ratio = (dx / width).clamp(0.0, 1.0);
                final quantized =
                    (ratio * divisions!).round() / divisions! * (max - min) + min;
                onChanged(quantized);
              }
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => updateFromDx(d.localPosition.dx),
              onHorizontalDragStart: (d) => updateFromDx(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => updateFromDx(d.localPosition.dx),
              child: CustomPaint(
                painter: _PulsrSliderPainter(
                  t: t,
                  inactiveColor: p.hairline.withValues(alpha: 0.6),
                  activeColor: p.accent,
                  thumbColor: p.surface,
                  glowColor: p.glow,
                ),
                size: Size.infinite,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PulsrSliderPainter extends CustomPainter {
  final double t;
  final Color inactiveColor;
  final Color activeColor;
  final Color thumbColor;
  final Color glowColor;

  _PulsrSliderPainter({
    required this.t,
    required this.inactiveColor,
    required this.activeColor,
    required this.thumbColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 6.0;
    const thumbRadius = 8.5;
    final centerY = size.height / 2;
    final thumbX = t * size.width;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(thumbX, centerY),
      Offset(size.width, centerY),
      inactivePaint,
    );

    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: [activeColor.withValues(alpha: 0.7), activeColor],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, centerY), Offset(thumbX, centerY), activePaint);

    // Soft glow behind the thumb.
    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius + 3, glowPaint);

    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);

    final ringPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius - 2, ringPaint);
  }

  @override
  bool shouldRepaint(_PulsrSliderPainter old) =>
      old.t != t ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.thumbColor != thumbColor ||
      old.glowColor != glowColor;
}
