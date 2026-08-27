import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/crossfade_manager.dart';

/// Mini waveform preview displaying the crossfade transition overlap between outgoing and incoming tracks.
class CrossfadeOverlapPreview extends StatelessWidget {
  final Duration duration;
  final CrossfadeCurve curve;
  final double height;

  const CrossfadeOverlapPreview({
    super.key,
    required this.duration,
    this.curve = CrossfadeCurve.equalPower,
    this.height = 72.0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.primary.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Crossfade Overlap (${duration.inSeconds}s)',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  curve.label,
                  style: TextStyle(
                    color: p.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _CrossfadeCurvePainter(
                duration: duration,
                curve: curve,
                primaryColor: p.primary,
                secondaryColor: p.accent,
                textColor: p.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrossfadeCurvePainter extends CustomPainter {
  final Duration duration;
  final CrossfadeCurve curve;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textColor;

  _CrossfadeCurvePainter({
    required this.duration,
    required this.curve,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final outPaint = Paint()
      ..color = secondaryColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final inPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final gridPaint = Paint()
      ..color = textColor.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    // Draw center guideline
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      gridPaint,
    );

    final outPath = Path();
    final inPath = Path();
    final steps = 60;

    final manager = CrossfadeManager()..curve = curve;

    for (int i = 0; i <= steps; i++) {
      final fraction = i / steps;
      final x = fraction * size.width;

      final inVal = manager.evaluateCurve(fraction, true);
      final outVal = manager.evaluateCurve(fraction, false);

      final inY = size.height - (inVal * (size.height - 4));
      final outY = size.height - (outVal * (size.height - 4));

      if (i == 0) {
        inPath.moveTo(x, inY);
        outPath.moveTo(x, outY);
      } else {
        inPath.lineTo(x, inY);
        outPath.lineTo(x, outY);
      }
    }

    canvas.drawPath(outPath, outPaint);
    canvas.drawPath(inPath, inPaint);
  }

  @override
  bool shouldRepaint(covariant _CrossfadeCurvePainter oldDelegate) {
    return oldDelegate.duration != duration ||
        oldDelegate.curve != curve ||
        oldDelegate.primaryColor != primaryColor;
  }
}
