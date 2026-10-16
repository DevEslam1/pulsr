part of '../cd_player_theme.dart';

/// Custom painter for the realistic iridescent Compact Disc (CD) surface.
class _CdDiscPainter extends CustomPainter {
  final Color activeColor;
  final double rotationPhase;

  _CdDiscPainter({
    required this.activeColor,
    this.rotationPhase = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. CD Polycarbonate Base Substrate (Silvery Titanium Gradient)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF1E2129),
          Color(0xFF282D37),
          Color(0xFF323846),
          Color(0xFF20232C),
          Color(0xFF16181F),
        ],
        stops: const [0.38, 0.55, 0.75, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 2. Prismatic Rainbow Diffraction Sheen (Spins with rotation)
    final rainbowPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(rotationPhase * 2 * math.pi),
        colors: [
          Colors.cyanAccent.withValues(alpha: 0.18),
          Colors.blueAccent.withValues(alpha: 0.22),
          Colors.purpleAccent.withValues(alpha: 0.20),
          Colors.pinkAccent.withValues(alpha: 0.24),
          Colors.amberAccent.withValues(alpha: 0.22),
          Colors.greenAccent.withValues(alpha: 0.18),
          Colors.cyanAccent.withValues(alpha: 0.18),
          Colors.blueAccent.withValues(alpha: 0.22),
          Colors.purpleAccent.withValues(alpha: 0.20),
          Colors.pinkAccent.withValues(alpha: 0.24),
          Colors.amberAccent.withValues(alpha: 0.22),
          Colors.cyanAccent.withValues(alpha: 0.18),
        ],
        stops: const [
          0.0,
          0.09,
          0.18,
          0.27,
          0.36,
          0.45,
          0.54,
          0.63,
          0.72,
          0.81,
          0.90,
          1.0,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(center, radius - 2, rainbowPaint);

    // 3. Bilateral Radial Specular Flare (Counter-rotating to stay anchored to virtual light)
    final flarePaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(-rotationPhase * 2 * math.pi),
        colors: [
          AppColors.specularAt(0.0),
          AppColors.specularAt(0.16),
          AppColors.specularAt(0.35),
          AppColors.specularAt(0.16),
          AppColors.specularAt(0.0),
          AppColors.specularAt(0.0),
          AppColors.specularAt(0.16),
          AppColors.specularAt(0.35),
          AppColors.specularAt(0.16),
          AppColors.specularAt(0.0),
        ],
        stops: const [0.0, 0.12, 0.25, 0.38, 0.50, 0.50, 0.62, 0.75, 0.88, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(center, radius - 3, flarePaint);

    // 4. Fine Concentric Optical Tracks (Micro-pits data density)
    final labelRadius = radius * 0.44;
    final leadOutRadius = radius - 5;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (double r = labelRadius + 10; r < leadOutRadius; r += 2.2) {
      final isSubTrack = (r > labelRadius + 32 && r < labelRadius + 35) ||
          (r > labelRadius + 68 && r < labelRadius + 71) ||
          (r > labelRadius + 105 && r < labelRadius + 108);

      if (isSubTrack) {
        trackPaint.color = Colors.white.withValues(alpha: 0.12);
        trackPaint.strokeWidth = 0.9;
      } else {
        final variance =
            ((math.sin(r * 1.2) + 1.0) * 0.035 + 0.02).clamp(0.015, 0.075);
        trackPaint.color = Colors.white.withValues(alpha: variance);
        trackPaint.strokeWidth = 0.45;
      }
      canvas.drawCircle(center, r, trackPaint);
    }

    // 5. Clear Inner Clamping / Mirror Band (Characteristic CD inner ring)
    final mirrorPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.04),
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: labelRadius + 10),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0;
    canvas.drawCircle(center, labelRadius + 4, mirrorPaint);

    // 6. Outer Polycarbonate Clear Rim with Glass Refraction
    final outerRimPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.50),
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.45),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, outerRimPaint);

    final innerBevelPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 3, innerBevelPaint);
  }

  @override
  bool shouldRepaint(covariant _CdDiscPainter oldDelegate) =>
      oldDelegate.activeColor != activeColor ||
      oldDelegate.rotationPhase != rotationPhase;
}

/// Custom painter for the modern, sleek tonearm stick assembly.
class _CdTonearmPainter extends CustomPainter {
  final Offset pivot;
  final double angle;
  final Color activeColor;
  final double armLength;
  final double liftProgress;

  static const double _gimbalRadius = 20.0;
  static const double _innerPivotRadius = 13.0;

  _CdTonearmPainter({
    required this.pivot,
    required this.angle,
    required this.activeColor,
    required this.armLength,
    this.liftProgress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Arm Rest / Cradle at fixed parked position
    final restBase = pivot + const Offset(-4, 38);
    _drawArmRest(canvas, restBase);

    // 2. Gimbal Base (Pivot Mount)
    _drawGimbalBase(canvas);

    // Save canvas to rotate the tonearm stick around the pivot
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    final l = armLength;

    // 3. Counterweight / Back Stem
    _drawCounterweight(canvas);

    // 4. Realistic Drop Shadow on the CD beneath the arm
    _drawTonearmShadow(canvas, l);

    // 5. Tonearm Stick (Cylindrical metallic rod)
    _drawStickTube(canvas, l);

    // 6. Modern Cartridge & Stylus Head
    _drawStylusHead(canvas, l);

    // 7. Pivot Cap & Bearing
    _drawPivotCap(canvas);

    canvas.restore();
  }

  void _drawArmRest(Canvas canvas, Offset base) {
    // Cradle pillar
    final restPaint = Paint()
      ..color = const Color(0xFF1E212A)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: base, width: 7, height: 16),
        const Radius.circular(2),
      ),
      restPaint,
    );

    // Cradle top fork
    final forkPaint = Paint()
      ..color = const Color(0xFF383C4D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final forkPath = Path()
      ..moveTo(base.dx - 5, base.dy - 6)
      ..lineTo(base.dx, base.dy - 3)
      ..lineTo(base.dx + 5, base.dy - 6);
    canvas.drawPath(forkPath, forkPaint);
  }

  void _drawGimbalBase(Canvas canvas) {
    // Outer base plate with shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(pivot + const Offset(0, 3), _gimbalRadius, shadowPaint);

    // Base body gradient
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF3A3F4E),
          Color(0xFF232733),
          Color(0xFF141720),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: pivot, radius: _gimbalRadius));
    canvas.drawCircle(pivot, _gimbalRadius, basePaint);

    // Metallic rim ring
    final rimPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.grey.shade400,
          Colors.grey.shade700,
          Colors.grey.shade300,
          Colors.grey.shade800,
          Colors.grey.shade400,
        ],
      ).createShader(Rect.fromCircle(center: pivot, radius: _gimbalRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pivot, _gimbalRadius, rimPaint);

    // Inner concentric bezel
    final innerBezelPaint = Paint()
      ..color = const Color(0xFF161922)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pivot, _innerPivotRadius, innerBezelPaint);

    // Ambient status indicator ring (glows with activeColor)
    final ledPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(pivot, _innerPivotRadius, ledPaint);
  }

  void _drawCounterweight(Canvas canvas) {
    // Rear stem extension behind pivot
    final stemPaint = Paint()..color = const Color(0xFF2C303D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3, -26, 6, 26),
        const Radius.circular(2),
      ),
      stemPaint,
    );

    // Cylindrical counterweight cylinder
    final weightRect = const Rect.fromLTWH(-7, -23, 14, 15);
    final weightPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF5A6072),
          Color(0xFF353945),
          Color(0xFF21242C),
          Color(0xFF4B5162),
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(weightRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(weightRect, const Radius.circular(3)),
      weightPaint,
    );

    // Calibration groove
    final groovePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(-7, -15), const Offset(7, -15), groovePaint);
  }

  void _drawTonearmShadow(Canvas canvas, double l) {
    final p = liftProgress.clamp(0.0, 1.0);
    final offset =
        Offset.lerp(const Offset(11, 13), const Offset(3.5, 4.0), p)!;
    final blurSigma = 7.0 + (2.5 - 7.0) * p;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final shadowPath = Path()
      ..moveTo(0, 6)
      ..lineTo(0, l - 18)
      ..lineTo(-5, l);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawPath(shadowPath, shadowPaint);
    canvas.restore();
  }

  void _drawStickTube(Canvas canvas, double l) {
    final tubeLength = l - 22;
    final tubeRect = Rect.fromLTWH(-2.2, 0, 4.4, tubeLength);

    // Precision cylindrical aluminum specular highlight
    final tubePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.grey.shade400,
          Colors.white,
          Colors.grey.shade300,
          Colors.grey.shade600,
        ],
        stops: const [0.0, 0.28, 0.65, 1.0],
      ).createShader(tubeRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(tubeRect, const Radius.circular(2.2)),
      tubePaint,
    );

    // Subtle edge specular stroke
    final tubeEdgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawLine(
        const Offset(-1.5, 2), Offset(-1.5, tubeLength - 2), tubeEdgePaint);
  }

  void _drawStylusHead(Canvas canvas, double l) {
    // Stylus cartridge connector collar
    final collarRect = Rect.fromLTWH(-3.5, l - 24, 7, 5);
    final collarPaint = Paint()..color = const Color(0xFF282C38);
    canvas.drawRRect(
      RRect.fromRectAndRadius(collarRect, const Radius.circular(1.5)),
      collarPaint,
    );

    // Angled contemporary headshell (like the sleek stick in the photo)
    final headshellPath = Path()
      ..moveTo(-3, l - 19)
      ..lineTo(3, l - 19)
      ..lineTo(2, l - 2)
      ..lineTo(-5, l)
      ..lineTo(-5, l - 10)
      ..close();

    final headRect = Rect.fromLTWH(-5, l - 19, 8, 20);
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF454B5C),
          const Color(0xFF252833),
          const Color(0xFF171920),
        ],
      ).createShader(headRect);
    canvas.drawPath(headshellPath, headPaint);

    // Stylus edge bevel highlight
    final headEdgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(headshellPath, headEdgePaint);

    // Stylus Cartridge Needle / Accent Light Indicator
    final needlePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-3.5, l - 1), 1.8, needlePaint);

    // Glow dot on stylus
    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(-3.5, l - 1), 3.0, glowPaint);
  }

  void _drawPivotCap(Canvas canvas) {
    // Center pivot bearing cap
    final capRect = const Rect.fromLTWH(-7, -7, 14, 14);
    final capPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.grey.shade300,
          Colors.grey.shade600,
          Colors.grey.shade200,
          Colors.grey.shade700,
          Colors.grey.shade300,
        ],
      ).createShader(capRect);
    canvas.drawCircle(Offset.zero, 6.5, capPaint);

    // Center screw dot
    final screwPaint = Paint()..color = const Color(0xFF181A22);
    canvas.drawCircle(Offset.zero, 2.4, screwPaint);
  }

  @override
  bool shouldRepaint(covariant _CdTonearmPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.armLength != armLength ||
      oldDelegate.pivot != pivot ||
      oldDelegate.liftProgress != liftProgress;
}
