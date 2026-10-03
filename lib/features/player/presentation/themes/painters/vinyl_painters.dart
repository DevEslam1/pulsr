part of '../vinyl_player_theme.dart';

class _VinylGroovesPainter extends CustomPainter {
  final Color activeColor;

  _VinylGroovesPainter({required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Vinyl base sheen (radial gradient from center to rim)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF181A22),
          Color(0xFF101116),
          Color(0xFF090A0D),
          Color(0xFF14151C),
        ],
        stops: const [0.3, 0.65, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 2. Bilateral specular reflection (the classic vinyl "butterfly" sheen)
    final sheenPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          AppColors.specularAt(0.0),
          AppColors.specularAt(0.08),
          AppColors.specularAt(0.0),
          AppColors.specularAt(0.0),
          AppColors.specularAt(0.08),
          AppColors.specularAt(0.0),
        ],
        stops: const [0.0, 0.22, 0.44, 0.50, 0.72, 0.94],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(center, radius - 4, sheenPaint);

    // 3. Concentric microgrooves in bands
    final labelRadius = radius * 0.36;
    final leadInRadius = radius - 6;

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    for (double r = labelRadius + 14; r < leadInRadius; r += 2.5) {
      final isBandGap = (r > labelRadius + 38 && r < labelRadius + 42) ||
          (r > labelRadius + 74 && r < labelRadius + 78);
      if (isBandGap) {
        groovePaint.color = AppColors.scrimAt(0.4);
        groovePaint.strokeWidth = 1.2;
      } else {
        final opacity =
            ((math.sin(r * 0.8) + 1.0) * 0.025 + 0.02).clamp(0.015, 0.055);
        groovePaint.color = AppColors.specularAt(opacity);
        groovePaint.strokeWidth = 0.6;
      }
      canvas.drawCircle(center, r, groovePaint);
    }

    // 4. Run-out dead wax groove
    final deadWaxPaint = Paint()
      ..color = AppColors.specularAt(0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, labelRadius + 5, deadWaxPaint);
    canvas.drawCircle(center, labelRadius + 9, deadWaxPaint);

    // Outer rim bead
    final rimPaint = Paint()
      ..color = const Color(0xFF2B2E3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) => false;
}

class _PlatterStrobePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer aluminum platter bevel ring
    final bevelPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.grey.shade600,
          Colors.grey.shade400,
          Colors.grey.shade700,
          Colors.grey.shade500,
          Colors.grey.shade600,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, radius - 2, bevelPaint);

    // Strobe dots (like Technics SL-1200)
    final dotPaint = Paint()
      ..color = AppColors.specularAt(0.5)
      ..style = PaintingStyle.fill;

    const numDots = 48;
    for (int i = 0; i < numDots; i++) {
      final angle = (i * 2 * math.pi) / numDots;
      final x = center.dx + (radius - 2) * math.cos(angle);
      final y = center.dy + (radius - 2) * math.sin(angle);
      canvas.drawCircle(Offset(x, y), 0.9, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TonearmPainter extends CustomPainter {
  final Offset pivot;
  final double angle;
  final Color activeColor;
  final double armLength;

  static const double _gimbalRadius = 22.0;
  static const double _screwCircleRadius = 16.0;
  static const double _collarRadius = 3.2;
  static const double _pivotBearingRadius = 6.5;
  static const double _pivotCenterScrewRadius = 2.5;

  _TonearmPainter({
    required this.pivot,
    required this.angle,
    required this.activeColor,
    required this.armLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Arm Rest / Cradle at fixed position
    final restBase = pivot + const Offset(-6, 44);
    _drawArmRest(canvas, restBase);

    // 2. Gimbal Base Mounting Plate (below the pivot)
    _drawGimbalBase(canvas);

    // Save canvas to rotate the tonearm around the pivot
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    // --- EVERYTHING BELOW IS IN LOCAL TONEARM COORDINATES (pivot at 0,0) ---
    final l = armLength;

    // 3. Counterweight
    _drawCounterweight(canvas);

    // 4. Drop Shadow
    _drawTonearmShadow(canvas, l);

    // 5. Tonearm Tube
    _drawTube(canvas, l);

    // 6 & 7. Headshell & Cartridge
    _drawHeadshell(canvas, l);

    // 8. Pivot Bearing Cap
    _drawPivotCap(canvas);

    canvas.restore();
  }

  void _drawGimbalBase(Canvas canvas) {
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF2C2F3C),
          Color(0xFF1B1D26),
          Color(0xFF0F1015),
        ],
      ).createShader(Rect.fromCircle(center: pivot, radius: _gimbalRadius));
    canvas.drawCircle(pivot, _gimbalRadius, basePaint);

    final baseRimPaint = Paint()
      ..color = const Color(0xFF424658)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pivot, _gimbalRadius, baseRimPaint);

    final screwPaint = Paint()..color = Colors.grey.shade400;
    for (int i = 0; i < 4; i++) {
      final a = (i * math.pi) / 2 + 0.4;
      final sx = pivot.dx + _screwCircleRadius * math.cos(a);
      final sy = pivot.dy + _screwCircleRadius * math.sin(a);
      canvas.drawCircle(Offset(sx, sy), 1.2, screwPaint);
    }
  }

  void _drawCounterweight(Canvas canvas) {
    final stemPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF8B8E9B), Color(0xFF535664)],
      ).createShader(const Rect.fromLTWH(-2.5, -34, 5, 34))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.5, -34, 5, 34),
        const Radius.circular(AppRadii.r2),
      ),
      stemPaint,
    );

    final weightRect = const Rect.fromLTWH(-10, -28, 20, 16);
    final weightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF9EA2B2),
          Color(0xFFE2E4EB),
          Color(0xFF5A5D6C),
          Color(0xFF383A46),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ).createShader(weightRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(weightRect, const Radius.circular(AppRadii.r4)),
      weightPaint,
    );

    final calibRect = const Rect.fromLTWH(-10, -18, 20, 4);
    final calibPaint = Paint()..color = const Color(0xFF14151B);
    canvas.drawRect(calibRect, calibPaint);

    final tickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 0.8;
    for (double tx = -7; tx <= 7; tx += 3.5) {
      canvas.drawLine(Offset(tx, -18), Offset(tx, -14), tickPaint);
    }
  }

  void _drawTonearmShadow(Canvas canvas, double l) {
    final shadowPath = Path();
    shadowPath.moveTo(0, 8);
    shadowPath.cubicTo(6, l * 0.30, -8, l * 0.65, -3, l * 0.90);
    shadowPath.lineTo(-6, l);

    final shadowPaint = Paint()
      ..color = AppColors.scrimLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

    canvas.save();
    canvas.translate(7, 7);
    canvas.drawPath(shadowPath, shadowPaint);
    canvas.restore();
  }

  void _drawTube(Canvas canvas, double l) {
    final tubePath = Path();
    tubePath.moveTo(0, 6);
    tubePath.cubicTo(6, l * 0.30, -8, l * 0.65, -3, l * 0.90);

    final tubePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.grey.shade400,
          Colors.white,
          Colors.grey.shade600,
          Colors.grey.shade800,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(-10, 0, 20, l))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(tubePath, tubePaint);
  }

  void _drawHeadshell(Canvas canvas, double l) {
    final collarPaint = Paint()
      ..color = const Color(0xFFC0C3D0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-3, l * 0.90), _collarRadius, collarPaint);

    final headshellStart = Offset(-3, l * 0.90);
    final headshellEnd = Offset(-7, l);

    final headshellPath = Path();
    headshellPath.moveTo(headshellStart.dx - 4, headshellStart.dy);
    headshellPath.lineTo(headshellStart.dx + 4, headshellStart.dy);
    headshellPath.lineTo(headshellEnd.dx + 5, headshellEnd.dy + 8);
    headshellPath.lineTo(headshellEnd.dx - 5, headshellEnd.dy + 8);
    headshellPath.close();

    final headshellPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF323544), Color(0xFF161820)],
      ).createShader(
          Rect.fromLTWH(headshellEnd.dx - 6, headshellStart.dy, 12, 22));
    canvas.drawPath(headshellPath, headshellPaint);

    final stylusHousingRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(headshellEnd.dx - 3.5, headshellEnd.dy + 3, 7, 6),
      const Radius.circular(1.5),
    );
    final stylusHousingPaint = Paint()..color = activeColor;
    canvas.drawRRect(stylusHousingRect, stylusHousingPaint);

    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(headshellEnd.dx, headshellEnd.dy + 9),
      Offset(headshellEnd.dx, headshellEnd.dy + 12),
      needlePaint,
    );

    final fingerLiftPath = Path();
    fingerLiftPath.moveTo(headshellEnd.dx + 4, headshellEnd.dy + 2);
    fingerLiftPath.cubicTo(
      headshellEnd.dx + 12,
      headshellEnd.dy + 1,
      headshellEnd.dx + 14,
      headshellEnd.dy - 6,
      headshellEnd.dx + 11,
      headshellEnd.dy - 10,
    );
    final fingerLiftPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(fingerLiftPath, fingerLiftPaint);
  }

  void _drawPivotCap(Canvas canvas) {
    final bearingPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.grey.shade400,
          Colors.grey.shade800,
        ],
      ).createShader(const Rect.fromLTWH(-7, -7, 14, 14));
    canvas.drawCircle(Offset.zero, _pivotBearingRadius, bearingPaint);

    final centerScrewPaint = Paint()..color = const Color(0xFF1A1C24);
    canvas.drawCircle(Offset.zero, _pivotCenterScrewRadius, centerScrewPaint);
  }

  void _drawArmRest(Canvas canvas, Offset pos) {
    // Rest post
    final postPaint = Paint()
      ..color = const Color(0xFF282B36)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: 8, height: 14),
        const Radius.circular(AppRadii.r2),
      ),
      postPaint,
    );

    // Rest cradle clip (small curved fork)
    final clipPaint = Paint()
      ..color = const Color(0xFF4A4E60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawArc(
      Rect.fromCenter(center: pos + const Offset(0, -3), width: 10, height: 6),
      0,
      math.pi,
      false,
      clipPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) {
    return oldDelegate.angle != angle ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.armLength != armLength ||
        oldDelegate.pivot != pivot;
  }
}
