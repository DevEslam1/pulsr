part of '../vinyl_player_theme.dart';

/// Full-screen warm brushed-aluminum / dark walnut analog hi-fi backdrop painter.
/// Strictly zero raw hex literals and zero `Colors.*` references.
class _VinylBrushedChassisPainter extends CustomPainter {
  final Color topColor;
  final Color midColor;
  final Color bottomColor;
  final Color grainLight;
  final Color grainDark;
  final Color amberGlow;

  _VinylBrushedChassisPainter({
    required this.topColor,
    required this.midColor,
    required this.bottomColor,
    required this.grainLight,
    required this.grainDark,
    required this.amberGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Base vertical brushed-chassis gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, midColor, bottomColor],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // 2. Warm analog studio lamp radial halo behind the turntable stage
    final glowCenter = Offset(size.width * 0.5, size.height * 0.34);
    final glowRadius = math.max(size.width, size.height) * 0.58;
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          amberGlow,
          amberGlow.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawRect(rect, haloPaint);

    // 3. Subtle horizontal brushed-metal / walnut grain striations
    final isGpuSaver = GpuBudget.isGpuSaverActive;
    final stepY = isGpuSaver ? 14.0 : 6.0;
    final lightLinePaint = Paint()
      ..color = grainLight
      ..strokeWidth = 0.8;
    final darkLinePaint = Paint()
      ..color = grainDark
      ..strokeWidth = 0.7;

    int idx = 0;
    for (double y = 0; y < size.height; y += stepY) {
      final isLight = idx.isEven;
      final wave = (math.sin(idx * 0.73) * 0.5 + 0.5);
      final paint = isLight ? lightLinePaint : darkLinePaint;
      if (wave > 0.32) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      idx++;
    }
  }

  @override
  bool shouldRepaint(covariant _VinylBrushedChassisPainter oldDelegate) =>
      oldDelegate.topColor != topColor ||
      oldDelegate.midColor != midColor ||
      oldDelegate.bottomColor != bottomColor ||
      oldDelegate.grainLight != grainLight ||
      oldDelegate.grainDark != grainDark ||
      oldDelegate.amberGlow != amberGlow;
}

/// Subtle brushed-surface sheen & machined corner rivets for the turntable plinth.
class _PlinthBrushedOverlayPainter extends CustomPainter {
  final Color highlight;
  final Color brassCorner;

  _PlinthBrushedOverlayPainter({
    required this.highlight,
    required this.brassCorner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          highlight,
          highlight.withValues(alpha: 0.0),
          highlight.withValues(alpha: 0.55),
          highlight.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.38, 0.68, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sheenPaint);

    // Four machined brass corner rivets
    const inset = 10.0;
    final rivets = [
      const Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ];
    final rivetPaint = Paint()
      ..color = brassCorner
      ..style = PaintingStyle.fill;
    for (final r in rivets) {
      canvas.drawCircle(r, 2.0, rivetPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlinthBrushedOverlayPainter oldDelegate) =>
      oldDelegate.highlight != highlight ||
      oldDelegate.brassCorner != brassCorner;
}

/// Precision analog calibration tick marks under the warm progress slider.
class _AnalogCalibrationTicksPainter extends CustomPainter {
  final Color tickColor;
  final Color accentColor;
  final double progress;

  _AnalogCalibrationTicksPainter({
    required this.tickColor,
    required this.accentColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int tickCount = 13;
    final activeIndex = (progress * (tickCount - 1)).round();
    for (int i = 0; i < tickCount; i++) {
      final x = (i / (tickCount - 1)) * size.width;
      final isMajor = i % 4 == 0;
      final h = isMajor ? size.height : size.height * 0.55;
      final yTop = (size.height - h) / 2;
      final paint = Paint()
        ..color = i <= activeIndex ? accentColor : tickColor
        ..strokeWidth = isMajor ? 1.3 : 0.9
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, yTop), Offset(x, yTop + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnalogCalibrationTicksPainter oldDelegate) =>
      oldDelegate.tickColor != tickColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.progress != progress;
}

/// Knurled perimeter notch markings painted inside the rotary Play/Pause dial.
class _RotaryDialKnurlPainter extends CustomPainter {
  final Color notchColor;
  final Color indicatorColor;

  _RotaryDialKnurlPainter({
    required this.notchColor,
    required this.indicatorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = (size.width / 2) - 2.2;
    final innerR = outerR - 3.2;
    final notchPaint = Paint()
      ..color = notchColor
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    const int notches = 24;
    for (int i = 0; i < notches; i++) {
      final angle = (i * 2 * math.pi) / notches;
      final p1 = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      canvas.drawLine(p1, p2, notchPaint);
    }

    // Top 12-o'clock engraved index pip
    final pipPaint = Paint()
      ..color = indicatorColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy - outerR + 1.4), 1.6, pipPaint);
  }

  @override
  bool shouldRepaint(covariant _RotaryDialKnurlPainter oldDelegate) =>
      oldDelegate.notchColor != notchColor ||
      oldDelegate.indicatorColor != indicatorColor;
}

class _VinylGroovesPainter extends CustomPainter {
  final Color activeColor;
  final PlayerSurfacePalette surface;

  _VinylGroovesPainter({
    required this.activeColor,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Vinyl base sheen (radial gradient from center to rim)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          PlayerMaterialColors.recordSheenCenter,
          surface.vinylGroove,
          PlayerMaterialColors.recordSheenDeep,
          PlayerMaterialColors.recordSheenRim,
        ],
        stops: const [0.3, 0.65, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 2. Concentric microgrooves in bands
    final labelRadius = radius * 0.36;
    final leadInRadius = radius - 6;

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    final isGpuSaver = GpuBudget.isGpuSaverActive;
    final grooveStep = isGpuSaver ? 5.0 : 2.5;
    for (double r = labelRadius + 14; r < leadInRadius; r += grooveStep) {
      final isBandGap = (r > labelRadius + 38 && r < labelRadius + 42) ||
          (r > labelRadius + 74 && r < labelRadius + 78);
      if (isBandGap) {
        groovePaint.color = surface.shadowAt(0.4);
        groovePaint.strokeWidth = 1.2;
      } else {
        final opacity =
            ((math.sin(r * 0.8) + 1.0) * 0.025 + 0.02).clamp(0.015, 0.055);
        groovePaint.color = surface.specularAt(opacity);
        groovePaint.strokeWidth = 0.6;
      }
      canvas.drawCircle(center, r, groovePaint);
    }

    // 4. Run-out dead wax groove
    final deadWaxPaint = Paint()
      ..color = surface.specularAt(0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, labelRadius + 5, deadWaxPaint);
    canvas.drawCircle(center, labelRadius + 9, deadWaxPaint);

    // Subtle warm accent halo ring right around the label perimeter
    final labelHaloPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, labelRadius + 2, labelHaloPaint);

    // Outer rim bead
    final rimPaint = Paint()
      ..color = PlayerMaterialColors.recordRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) =>
      oldDelegate.activeColor != activeColor || oldDelegate.surface != surface;
}

/// Specular reflection anchored to the virtual light source. It is painted
/// once above the spinning record instead of per animation tick, and clipped
/// to the vinyl annulus so the centre label stays untouched.
class _VinylSheenPainter extends CustomPainter {
  final double labelRatio;
  Path? _cachedClipPath;
  Paint? _cachedSheenPaint;
  Size? _lastSize;

  _VinylSheenPainter({this.labelRatio = 0.44});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    if (_cachedClipPath == null || _lastSize != size) {
      _lastSize = size;
      final outer = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius - 4));
      final inner = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius * labelRatio));
      _cachedClipPath = Path.combine(PathOperation.difference, outer, inner);

      _cachedSheenPaint = Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            AppColors.specularAt(0.0),
            AppColors.specularAt(0.09),
            AppColors.specularAt(0.0),
            AppColors.specularAt(0.0),
            AppColors.specularAt(0.09),
            AppColors.specularAt(0.0),
          ],
          stops: const [0.0, 0.22, 0.44, 0.50, 0.72, 0.94],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.screen;
    }

    canvas.save();
    canvas.clipPath(_cachedClipPath!);
    canvas.drawCircle(center, radius - 4, _cachedSheenPaint!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VinylSheenPainter oldDelegate) =>
      oldDelegate.labelRatio != labelRatio;
}

class _PlatterStrobePainter extends CustomPainter {
  final Color activeColor;
  final bool isPlaying;
  final PlayerSurfacePalette surface;

  _PlatterStrobePainter({
    this.activeColor = AppColors.amberDeep,
    this.isPlaying = true,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer aluminum platter bevel ring
    final bevelPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          surface.platterMetalDeep,
          surface.platterMetal,
          surface.platterMetalShadow,
          surface.platterMetalHighlight,
          surface.platterMetalDeep,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, radius - 2, bevelPaint);

    // Strobe lamp position (bottom-left quadrant at ~2.4 rad)
    const lampAngle = 2.4;
    final lampPos = Offset(
      center.dx + (radius - 2) * math.cos(lampAngle),
      center.dy + (radius - 2) * math.sin(lampAngle),
    );

    // Quartz-lock lamp ambient halo when playing
    if (isPlaying && !GpuBudget.isGpuSaverActive) {
      final haloPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(lampPos, 10.0, haloPaint);
    }

    // Strobe dots (Technics SL-1200 style with localized illumination)
    const numDots = 48;
    for (int i = 0; i < numDots; i++) {
      final angle = (i * 2 * math.pi) / numDots;
      final x = center.dx + (radius - 2) * math.cos(angle);
      final y = center.dy + (radius - 2) * math.sin(angle);

      Color dotColor = surface.specularAt(0.5);
      double dotRadius = 0.9;

      if (isPlaying) {
        double diff = (angle - lampAngle).abs();
        while (diff > math.pi) {
          diff = (2 * math.pi - diff).abs();
        }
        if (diff < 0.55) {
          final intensity = (1.0 - (diff / 0.55)).clamp(0.0, 1.0);
          dotColor = Color.lerp(dotColor, activeColor, intensity)!;
          dotRadius = 0.9 + (0.5 * intensity);

          // Subtle dot bloom under direct illumination
          if (intensity > 0.4 && !GpuBudget.isGpuSaverActive) {
            final bloomPaint = Paint()
              ..color = activeColor.withValues(alpha: 0.5 * intensity)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
            canvas.drawCircle(Offset(x, y), dotRadius * 1.6, bloomPaint);
          }
        }
      }

      final dotPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlatterStrobePainter oldDelegate) =>
      oldDelegate.activeColor != activeColor ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.surface != surface;
}

class _TonearmPainter extends CustomPainter {
  final Offset pivot;
  final double angle;
  final Color activeColor;
  final double armLength;
  final double liftProgress;
  final PlayerSurfacePalette surface;
  final bool isRtl;

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
    this.liftProgress = 1.0,
    required this.surface,
    this.isRtl = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isRtl) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

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
    if (isRtl) canvas.restore();
  }

  void _drawGimbalBase(Canvas canvas) {
    final basePaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          PlayerMaterialColors.gimbalHighlight,
          PlayerMaterialColors.gimbalMid,
          PlayerMaterialColors.gimbalShadow,
        ],
      ).createShader(Rect.fromCircle(center: pivot, radius: _gimbalRadius));
    canvas.drawCircle(pivot, _gimbalRadius, basePaint);

    final baseRimPaint = Paint()
      ..color = PlayerMaterialColors.gimbalRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pivot, _gimbalRadius, baseRimPaint);

    final screwPaint = Paint()..color = surface.platterMetal;
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
        colors: [
          PlayerMaterialColors.counterweightStemLight,
          PlayerMaterialColors.counterweightStemDark,
        ],
      ).createShader(const Rect.fromLTWH(-2.5, -34, 5, 34))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.5, -34, 5, 34),
        const Radius.circular(AppRadii.r2),
      ),
      stemPaint,
    );

    const weightRect = Rect.fromLTWH(-10, -28, 20, 16);
    final weightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          PlayerMaterialColors.counterweightEdge,
          PlayerMaterialColors.counterweightHighlight,
          PlayerMaterialColors.counterweightMid,
          PlayerMaterialColors.counterweightShadow,
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ).createShader(weightRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(weightRect, const Radius.circular(AppRadii.r4)),
      weightPaint,
    );

    const calibRect = Rect.fromLTWH(-10, -18, 20, 4);
    final calibPaint = Paint()..color = PlayerMaterialColors.calibrationStrip;
    canvas.drawRect(calibRect, calibPaint);

    final tickPaint = Paint()
      ..color = surface.mutedInk
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

    final p = liftProgress.clamp(0.0, 1.0);
    final offset =
        Offset.lerp(const Offset(11, 13), const Offset(3.5, 4.0), p)!;
    final blurSigma = 7.0 + (2.5 - 7.0) * p;

    final shadowPaint = Paint()
      ..color = AppColors.scrimLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..maskFilter = GpuBudget.isGpuSaverActive
          ? null
          : MaskFilter.blur(BlurStyle.normal, blurSigma);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
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
          surface.platterMetal,
          surface.highContrastInk,
          surface.platterMetalDeep,
          surface.platterMetalShadow,
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
      ..color = PlayerMaterialColors.collarMetal
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
        colors: [
          PlayerMaterialColors.headshellHighlight,
          PlayerMaterialColors.headshellShadow,
        ],
      ).createShader(
          Rect.fromLTWH(headshellEnd.dx - 6, headshellStart.dy, 12, 22));
    canvas.drawPath(headshellPath, headshellPaint);

    final stylusHousingRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(headshellEnd.dx - 3.5, headshellEnd.dy + 3, 7, 6),
      const Radius.circular(1.5),
    );
    final stylusHousingPaint = Paint()..color = activeColor;
    canvas.drawRRect(stylusHousingRect, stylusHousingPaint);

    // Subtle warm stylus contact glow when tonearm is dropped onto groove
    if (liftProgress > 0.8 && !GpuBudget.isGpuSaverActive) {
      final glowAlpha = ((liftProgress - 0.8) / 0.2).clamp(0.0, 1.0) * 0.45;
      final stylusGlowPaint = Paint()
        ..color = activeColor.withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(
        Offset(headshellEnd.dx, headshellEnd.dy + 11),
        4.0,
        stylusGlowPaint,
      );
    }

    final needlePaint = Paint()
      ..color = surface.highContrastInk
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
      ..color = surface.platterMetal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(fingerLiftPath, fingerLiftPaint);
  }

  void _drawPivotCap(Canvas canvas) {
    final bearingPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          surface.highContrastInk,
          surface.platterMetal,
          surface.platterMetalShadow,
        ],
      ).createShader(const Rect.fromLTWH(-7, -7, 14, 14));
    canvas.drawCircle(Offset.zero, _pivotBearingRadius, bearingPaint);

    final centerScrewPaint = Paint()
      ..color = PlayerMaterialColors.pivotCenterScrew;
    canvas.drawCircle(Offset.zero, _pivotCenterScrewRadius, centerScrewPaint);
  }

  void _drawArmRest(Canvas canvas, Offset pos) {
    // Rest post
    final postPaint = Paint()
      ..color = PlayerMaterialColors.armRestPost
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
      ..color = PlayerMaterialColors.armRestClip
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
        oldDelegate.pivot != pivot ||
        oldDelegate.liftProgress != liftProgress ||
        oldDelegate.surface != surface ||
        oldDelegate.isRtl != isRtl;
  }
}
