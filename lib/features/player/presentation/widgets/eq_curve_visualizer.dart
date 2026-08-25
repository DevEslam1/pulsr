// lib/features/player/presentation/widgets/eq_curve_visualizer.dart
import 'package:flutter/material.dart';

class EqCurveVisualizer extends StatelessWidget {
  final List<double> gains;
  final Color activeColor;
  final double height;

  const EqCurveVisualizer({
    super.key,
    required this.gains,
    required this.activeColor,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _EqCurvePainter(gains: gains, color: activeColor),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final List<double> gains;
  final Color color;

  _EqCurvePainter({required this.gains, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;

    final midY = size.height / 2;
    final stepX = gains.length > 1 ? size.width / (gains.length - 1) : size.width;
    const maxGain = 15.0;

    // Draw 0 dB center reference line
    final centerPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), centerPaint);

    // Draw smooth cubic spline gain curve
    final path = Path();
    for (int i = 0; i < gains.length; i++) {
      final x = i * stepX;
      final y = midY - (gains[i].clamp(-maxGain, maxGain) / maxGain) * (size.height / 2 * 0.9);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = midY - (gains[i - 1].clamp(-maxGain, maxGain) / maxGain) * (size.height / 2 * 0.9);
        final ctrlX = (prevX + x) / 2;
        path.cubicTo(ctrlX, prevY, ctrlX, y, x, y);
      }
    }

    // Fill area under curve towards center 0 dB line
    final fillPath = Path.from(path)
      ..lineTo(size.width, midY)
      ..lineTo(0, midY)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw main curve stroke
    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, curvePaint);

    // Draw points on each band
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (int i = 0; i < gains.length; i++) {
      final x = i * stepX;
      final y = midY - (gains[i].clamp(-maxGain, maxGain) / maxGain) * (size.height / 2 * 0.9);
      if (gains[i].abs() > 0.1) {
        canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    if (oldDelegate.color != color || oldDelegate.gains.length != gains.length) return true;
    for (int i = 0; i < gains.length; i++) {
      if (oldDelegate.gains[i] != gains[i]) return true;
    }
    return false;
  }
}
