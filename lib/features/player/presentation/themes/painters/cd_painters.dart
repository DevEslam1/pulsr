part of '../cd_player_theme.dart';

/// Custom painter for the realistic iridescent Compact Disc (CD) surface with
/// cool-silver polycarbonate substrate and prismatic diffraction spectrum.
class _CdDiscPainter extends CustomPainter {
  final Color activeColor;
  final PlayerSurfacePalette surface;

  _CdDiscPainter({
    required this.activeColor,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. CD Polycarbonate Base Substrate (Bright Cool-Silver Titanium Gradient)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(
            PlayerMaterialColors.cdSurfaceMid,
            AppColors.discSilver,
            0.46,
          )!,
          Color.lerp(
            PlayerMaterialColors.cdSurfaceUpper,
            AppColors.surfaceGreyLight,
            0.38,
          )!,
          Color.lerp(
            PlayerMaterialColors.cdSurfaceMid,
            AppColors.discSilver,
            0.52,
          )!,
          Color.lerp(
            PlayerMaterialColors.cdSurfaceLower,
            AppColors.discAluminum,
            0.30,
          )!,
          PlayerMaterialColors.cdSurfaceTop,
        ],
        stops: const [0.38, 0.56, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 2. Prismatic Rainbow Diffraction Sheen (spins with the disc via the
    // compositor transform, so it is drawn once in disc-local space)
    final rainbowPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          AppColors.accentCyan.withValues(alpha: 0.24),
          AppColors.azure.withValues(alpha: 0.26),
          AppColors.swatchPurple.withValues(alpha: 0.22),
          AppColors.swatchPink.withValues(alpha: 0.24),
          AppColors.amberDeep.withValues(alpha: 0.22),
          AppColors.swatchGreen.withValues(alpha: 0.20),
          AppColors.accentCyan.withValues(alpha: 0.24),
          AppColors.azure.withValues(alpha: 0.26),
          AppColors.swatchPurple.withValues(alpha: 0.22),
          AppColors.swatchPink.withValues(alpha: 0.24),
          AppColors.amberDeep.withValues(alpha: 0.22),
          AppColors.accentCyan.withValues(alpha: 0.24),
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

    // 3. Fine Concentric Optical Tracks (Micro-pits data density)
    final labelRadius = radius * 0.45;
    final leadOutRadius = radius - 5;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final isGpuSaver = GpuBudget.isGpuSaverActive;
    final trackStep = isGpuSaver ? 4.8 : 2.2;
    for (double r = labelRadius + 10; r < leadOutRadius; r += trackStep) {
      final isSubTrack = (r > labelRadius + 30 && r < labelRadius + 33) ||
          (r > labelRadius + 64 && r < labelRadius + 67) ||
          (r > labelRadius + 98 && r < labelRadius + 101);

      if (isSubTrack) {
        trackPaint.color = AppColors.specularAt(0.18);
        trackPaint.strokeWidth = 0.9;
      } else {
        final variance =
            ((math.sin(r * 1.2) + 1.0) * 0.04 + 0.03).clamp(0.02, 0.09);
        trackPaint.color = AppColors.specularAt(variance);
        trackPaint.strokeWidth = 0.45;
      }
      canvas.drawCircle(center, r, trackPaint);
    }

    // 4. Clear Inner Clamping / Mirror Band (Characteristic CD inner ring)
    final mirrorPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.specularAt(0.28),
          AppColors.specularAt(0.08),
          AppColors.specularAt(0.24),
          AppColors.specularAt(0.06),
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: labelRadius + 10),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0;
    canvas.drawCircle(center, labelRadius + 4, mirrorPaint);

    // Subtle optical laser read-ring accent around clamping zone
    final laserRingPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, labelRadius + 9, laserRingPaint);

    // 5. Outer Polycarbonate Clear Rim with Glass Refraction
    final outerRimPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          AppColors.specularAt(0.60),
          AppColors.specularAt(0.20),
          AppColors.specularAt(0.65),
          AppColors.specularAt(0.18),
          AppColors.specularAt(0.60),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, outerRimPaint);

    final innerBevelPaint = Paint()
      ..color = surface.shadowAt(0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 3, innerBevelPaint);
  }

  @override
  bool shouldRepaint(covariant _CdDiscPainter oldDelegate) =>
      oldDelegate.activeColor != activeColor || oldDelegate.surface != surface;
}

/// Bilateral specular flare anchored to the virtual light source. Painted once
/// above the spinning disc and clipped to the outer annulus so the artwork
/// label keeps its original appearance.
class _CdFlarePainter extends CustomPainter {
  final double labelRatio;
  Path? _cachedClipPath;
  Paint? _cachedFlarePaint;
  Size? _lastSize;

  _CdFlarePainter({this.labelRatio = 0.45});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    if (_cachedClipPath == null || _lastSize != size) {
      _lastSize = size;
      final outer = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius - 3));
      final inner = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius * labelRatio));
      _cachedClipPath = Path.combine(PathOperation.difference, outer, inner);

      _cachedFlarePaint = Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            AppColors.specularAt(0.0),
            AppColors.specularAt(0.18),
            AppColors.specularAt(0.42),
            AppColors.specularAt(0.18),
            AppColors.specularAt(0.0),
            AppColors.specularAt(0.0),
            AppColors.specularAt(0.18),
            AppColors.specularAt(0.42),
            AppColors.specularAt(0.18),
            AppColors.specularAt(0.0),
          ],
          stops: const [
            0.0,
            0.12,
            0.25,
            0.38,
            0.50,
            0.50,
            0.62,
            0.75,
            0.88,
            1.0
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.screen;
    }

    canvas.save();
    canvas.clipPath(_cachedClipPath!);
    canvas.drawCircle(center, radius - 3, _cachedFlarePaint!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CdFlarePainter oldDelegate) =>
      oldDelegate.labelRatio != labelRatio;
}

/// Paints the Y2K transparent polycarbonate CD jewel case:
/// - Translucent crystal acrylic outer shell with crisp beveled glass edge
/// - Realistic vertical ribbed translucent jewel-case spine on the left edge
/// - Molded top/bottom hinge pins & clear plastic booklet retainer clips
/// - Recessed circular disc tray with subtle machined teeth & optical well
class _CdJewelCasePainter extends CustomPainter {
  final double spineWidth;
  final Rect trayRect;
  final Offset discCenter;
  final double discRadius;
  final double caseRadius;
  final Color activeColor;
  final bool isPlaying;
  final bool isDark;
  final bool customGlow;
  final PlayerSurfacePalette surface;

  _CdJewelCasePainter({
    required this.spineWidth,
    required this.trayRect,
    required this.discCenter,
    required this.discRadius,
    required this.caseRadius,
    required this.activeColor,
    required this.isPlaying,
    required this.isDark,
    required this.customGlow,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final caseRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final radius = Radius.circular(caseRadius);
    final caseRRect = RRect.fromRectAndRadius(caseRect.deflate(0.5), radius);

    // 1. Case lift-off shadow (+ optional Theme Studio custom ambient glow).
    if (!GpuBudget.isGpuSaverActive) {
      canvas.drawRRect(
        caseRRect.shift(const Offset(0, 10)),
        Paint()
          ..color = surface.shadowAt(isDark ? 0.46 : 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      if (customGlow) {
        canvas.drawRRect(
          caseRRect.inflate(2),
          Paint()
            ..color = activeColor.withValues(alpha: isDark ? 0.28 : 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
        );
      }
    }

    // 2. Translucent Y2K clear acrylic body (cool frosted polycarbonate sheen).
    canvas.drawRRect(
      caseRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.specularAt(0.14),
                  PlayerMaterialColors.cdSurfaceTop.withValues(alpha: 0.72),
                  PlayerMaterialColors.cdTrayGradStart.withValues(alpha: 0.84),
                ]
              : [
                  AppColors.specularAt(0.76),
                  AppColors.lightCard.withValues(alpha: 0.58),
                  AppColors.discSilver.withValues(alpha: 0.52),
                ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(caseRect),
    );

    // 3. Recessed circular disc tray panel inside the right side of the case.
    final trayRRect = RRect.fromRectAndRadius(
      trayRect,
      Radius.circular(math.max(AppRadii.r6, caseRadius * 0.65)),
    );
    canvas.drawRRect(
      trayRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  PlayerMaterialColors.cdClampWell.withValues(alpha: 0.74),
                  PlayerMaterialColors.cdTrayGradEnd.withValues(alpha: 0.86),
                ]
              : [
                  AppColors.discSilver.withValues(alpha: 0.34),
                  AppColors.slate.withValues(alpha: 0.22),
                ],
        ).createShader(trayRect),
    );
    canvas.drawRRect(
      trayRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = isDark
            ? AppColors.specularAt(0.16)
            : AppColors.specularAt(0.65),
    );

    // 4. Translucent Ribbed Jewel-Case Spine along the leading (left) edge.
    canvas.save();
    canvas.clipRRect(caseRRect);

    final spineRect = Rect.fromLTWH(
      caseRect.left + 1.0,
      caseRect.top + 1.0,
      math.max(spineWidth - 1.0, 6.0),
      caseRect.height - 2.0,
    );
    canvas.drawRect(
      spineRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [
                  AppColors.specularAt(0.16),
                  PlayerMaterialColors.cdClampWell.withValues(alpha: 0.78),
                  AppColors.specularAt(0.20),
                ]
              : [
                  AppColors.specularAt(0.84),
                  AppColors.discSilver.withValues(alpha: 0.48),
                  AppColors.specularAt(0.72),
                ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(spineRect),
    );

    // Horizontal translucent acrylic grip flutes along the vertical spine.
    final double fluteStartY = spineRect.top + spineRect.height * 0.08;
    final double fluteEndY = spineRect.bottom - spineRect.height * 0.08;
    final double fluteStep = (spineRect.height / 24.0).clamp(6.0, 12.0);
    final fluteLight = Paint()
      ..color = AppColors.specularAt(isDark ? 0.24 : 0.72)
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    final fluteShadow = Paint()
      ..color = surface.shadowAt(isDark ? 0.34 : 0.14)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (double y = fluteStartY; y <= fluteEndY; y += fluteStep) {
      canvas.drawLine(
        Offset(spineRect.left + 3.5, y),
        Offset(spineRect.right - 3.5, y),
        fluteLight,
      );
      canvas.drawLine(
        Offset(spineRect.left + 3.5, y + 1.3),
        Offset(spineRect.right - 3.5, y + 1.3),
        fluteShadow,
      );
    }

    // Crisp vertical hinge seam separating the ribbed spine from the tray.
    canvas.drawLine(
      Offset(spineRect.right, spineRect.top),
      Offset(spineRect.right, spineRect.bottom),
      Paint()
        ..color = AppColors.specularAt(isDark ? 0.34 : 0.85)
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      Offset(spineRect.right + 1.4, spineRect.top),
      Offset(spineRect.right + 1.4, spineRect.bottom),
      Paint()
        ..color = surface.shadowAt(isDark ? 0.38 : 0.18)
        ..strokeWidth = 1.0,
    );

    // Molded top & bottom clear hinge pins at the spine seam.
    final pinPaint = Paint()
      ..color = AppColors.specularAt(isDark ? 0.36 : 0.82);
    for (final double frac in const [0.06, 0.94]) {
      final py = spineRect.top + spineRect.height * frac;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(spineRect.right - 1.5, py),
            width: 5.0,
            height: 9.0,
          ),
          const Radius.circular(AppRadii.r2),
        ),
        pinPaint,
      );
    }

    // Molded clear booklet retainer tabs at top & bottom of the lid.
    final tabPaint = Paint()
      ..color = AppColors.specularAt(isDark ? 0.20 : 0.62)
      ..style = PaintingStyle.fill;
    final tabStroke = Paint()
      ..color = AppColors.specularAt(isDark ? 0.34 : 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final tabX = trayRect.left + trayRect.width * 0.72;
    for (final bool isTop in const [true, false]) {
      final tabRect = Rect.fromCenter(
        center: Offset(tabX, isTop ? trayRect.top + 3 : trayRect.bottom - 3),
        width: math.min(26.0, trayRect.width * 0.12),
        height: 5.5,
      );
      final tabRRect =
          RRect.fromRectAndRadius(tabRect, const Radius.circular(AppRadii.r3));
      canvas.drawRRect(tabRRect, tabPaint);
      canvas.drawRRect(tabRRect, tabStroke);
    }

    canvas.restore();

    // 5. Recessed circular disc seat + molded tray notch arcs + active ring.
    canvas.drawCircle(
      discCenter,
      discRadius + 6.5,
      Paint()..color = surface.shadowAt(isDark ? 0.34 : 0.14),
    );
    canvas.drawCircle(
      discCenter,
      discRadius + 6.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AppColors.specularAt(isDark ? 0.16 : 0.52),
    );
    canvas.drawCircle(
      discCenter,
      discRadius + 3.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = activeColor.withValues(alpha: isPlaying ? 0.30 : 0.10),
    );

    // 6. Outer clear polycarbonate double-bevel rim (authentic jewel-case wall).
    canvas.drawRRect(
      caseRRect.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.specularAt(isDark ? 0.46 : 0.92),
            AppColors.specularAt(isDark ? 0.10 : 0.32),
            AppColors.specularAt(isDark ? 0.28 : 0.74),
          ],
        ).createShader(caseRect),
    );
    canvas.drawRRect(
      caseRRect.deflate(2.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = AppColors.specularAt(isDark ? 0.10 : 0.38),
    );
  }

  @override
  bool shouldRepaint(covariant _CdJewelCasePainter oldDelegate) =>
      oldDelegate.spineWidth != spineWidth ||
      oldDelegate.trayRect != trayRect ||
      oldDelegate.discCenter != discCenter ||
      oldDelegate.discRadius != discRadius ||
      oldDelegate.caseRadius != caseRadius ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.isDark != isDark ||
      oldDelegate.customGlow != customGlow ||
      oldDelegate.surface != surface;
}

/// Paints the optical pickup sled: the rail along the tray lip, the lens head
/// riding it, and the read beam that lands on the disc surface.
class _CdPickupSledPainter extends CustomPainter {
  final double railLeft;
  final double railRight;
  final double railY;
  final double lensX;

  /// 0 while the pickup is parked, 1 when it has engaged the disc.
  final double engage;
  final Color activeColor;
  final Offset discCenter;
  final double discRadius;
  final PlayerSurfacePalette surface;

  _CdPickupSledPainter({
    required this.railLeft,
    required this.railRight,
    required this.railY,
    required this.lensX,
    required this.engage,
    required this.activeColor,
    required this.discCenter,
    required this.discRadius,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final engaged = engage.clamp(0.0, 1.0);

    // 1. Rail: a machined groove with an end stop at either side.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(railLeft, railY - 3.0, railRight, railY + 3.0),
        const Radius.circular(AppRadii.r1_5),
      ),
      Paint()..color = PlayerMaterialColors.cdWeightLow,
    );
    canvas.drawLine(
      Offset(railLeft, railY),
      Offset(railRight, railY),
      Paint()
        ..color = AppColors.discSilver.withValues(alpha: 0.65)
        ..strokeWidth = 1.0,
    );
    final stopPaint = Paint()..color = PlayerMaterialColors.cdCollar;
    canvas.drawRect(
      Rect.fromLTRB(railLeft - 2, railY - 4.5, railLeft, railY + 4.5),
      stopPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(railRight, railY - 4.5, railRight + 2, railY + 4.5),
      stopPaint,
    );

    // 2. Read beam: only drawn when engaged so a parked sled shows no light.
    if (engaged > 0) {
      final dx = lensX - discCenter.dx;
      final inside = discRadius * discRadius - dx * dx;
      if (inside > 0) {
        final spotY = discCenter.dy + math.sqrt(inside);
        canvas.drawLine(
          Offset(lensX, railY - 11),
          Offset(lensX, spotY),
          Paint()
            ..color = activeColor.withValues(alpha: 0.48 * engaged)
            ..strokeWidth = 1.1,
        );
        canvas.drawCircle(
          Offset(lensX, spotY),
          3.2,
          Paint()
            ..color = activeColor.withValues(alpha: 0.58 * engaged)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }

    // 3. Lens head: sled block, objective lens and its glow while engaged.
    final headRect = Rect.fromCenter(
      center: Offset(lensX, railY - 6.5),
      width: 16,
      height: 13,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        headRect,
        const Radius.circular(AppRadii.r3),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PlayerMaterialColors.cdHeadHigh,
            PlayerMaterialColors.cdHeadMid,
            PlayerMaterialColors.cdHeadLow,
          ],
        ).createShader(headRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        headRect,
        const Radius.circular(AppRadii.r3),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = AppColors.specularAt(0.24),
    );

    final objective = Offset(lensX, railY - 9.5);
    canvas.drawCircle(
      objective,
      2.5,
      Paint()..color = activeColor.withValues(alpha: 0.30 + (0.70 * engaged)),
    );
    if (engaged > 0) {
      canvas.drawCircle(
        objective,
        4.8,
        Paint()
          ..color = activeColor.withValues(alpha: 0.45 * engaged)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CdPickupSledPainter oldDelegate) =>
      oldDelegate.railLeft != railLeft ||
      oldDelegate.railRight != railRight ||
      oldDelegate.railY != railY ||
      oldDelegate.lensX != lensX ||
      oldDelegate.engage != engage ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.discCenter != discCenter ||
      oldDelegate.discRadius != discRadius ||
      oldDelegate.surface != surface;
}

/// Static transparent acrylic lid reflection + animated play/pause gloss sweep
/// painted above the spinning disc so the jewel case reads as crystal clear
/// Y2K polycarbonate.
class _CdLidGlossPainter extends CustomPainter {
  final Animation<double> gloss;
  final double caseRadius;
  final double spineWidth;
  final PlayerSurfacePalette surface;

  _CdLidGlossPainter({
    required this.gloss,
    required this.caseRadius,
    required this.spineWidth,
    required this.surface,
  }) : super(repaint: gloss);

  @override
  void paint(Canvas canvas, Size size) {
    final caseRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(0.8),
      Radius.circular(caseRadius),
    );

    canvas.save();
    canvas.clipRRect(caseRRect);

    // Subtle permanent diagonal clear-acrylic specular streak across upper-left
    // of the lid.
    final staticHighlight = Path()
      ..moveTo(spineWidth + size.width * 0.04, 0)
      ..lineTo(spineWidth + size.width * 0.28, 0)
      ..lineTo(spineWidth + size.width * 0.02, size.height * 0.34)
      ..lineTo(spineWidth, size.height * 0.22)
      ..close();
    canvas.drawPath(
      staticHighlight,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.specularAt(0.14),
            AppColors.specularAt(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.36)),
    );

    // Play/pause animated specular sweep across the acrylic lid.
    final sweep = gloss.value;
    if (sweep > 0.0 && sweep < 1.0) {
      final bandWidth = size.width * 0.34;
      final x = -bandWidth + (size.width + bandWidth * 2) * sweep;
      canvas.translate(x, 0);
      canvas.rotate(-0.32);
      final bandRect =
          Rect.fromLTWH(0, -size.height, bandWidth, size.height * 3);
      canvas.drawRect(
        bandRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.specularAt(0.0),
              AppColors.specularAt(0.20),
              AppColors.specularAt(0.0),
            ],
          ).createShader(bandRect)
          ..blendMode = BlendMode.screen,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CdLidGlossPainter oldDelegate) =>
      oldDelegate.gloss != gloss ||
      oldDelegate.caseRadius != caseRadius ||
      oldDelegate.spineWidth != spineWidth ||
      oldDelegate.surface != surface;
}
