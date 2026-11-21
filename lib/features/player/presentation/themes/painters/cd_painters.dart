part of '../cd_player_theme.dart';

/// Custom painter for the realistic iridescent Compact Disc (CD) surface.
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

    // 1. CD Polycarbonate Base Substrate (Silvery Titanium Gradient)
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          PlayerMaterialColors.cdSurfaceTop,
          PlayerMaterialColors.cdSurfaceUpper,
          PlayerMaterialColors.cdSurfaceMid,
          PlayerMaterialColors.cdSurfaceLower,
          PlayerMaterialColors.cdSurfaceBottom,
        ],
        stops: const [0.38, 0.55, 0.75, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 2. Prismatic Rainbow Diffraction Sheen (spins with the disc via the
    // compositor transform, so it is drawn once in disc-local space)
    final rainbowPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          surface.ledGlow.withValues(alpha: 0.18),
          AppColors.azure.withValues(alpha: 0.22),
          AppColors.swatchPurple.withValues(alpha: 0.20),
          AppColors.swatchPink.withValues(alpha: 0.24),
          AppColors.amberDeep.withValues(alpha: 0.22),
          AppColors.swatchGreen.withValues(alpha: 0.18),
          surface.ledGlow.withValues(alpha: 0.18),
          AppColors.azure.withValues(alpha: 0.22),
          AppColors.swatchPurple.withValues(alpha: 0.20),
          AppColors.swatchPink.withValues(alpha: 0.24),
          AppColors.amberDeep.withValues(alpha: 0.22),
          surface.ledGlow.withValues(alpha: 0.18),
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
    final labelRadius = radius * 0.44;
    final leadOutRadius = radius - 5;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final isGpuSaver = GpuBudget.isGpuSaverActive;
    final trackStep = isGpuSaver ? 4.8 : 2.2;
    for (double r = labelRadius + 10; r < leadOutRadius; r += trackStep) {
      final isSubTrack = (r > labelRadius + 32 && r < labelRadius + 35) ||
          (r > labelRadius + 68 && r < labelRadius + 71) ||
          (r > labelRadius + 105 && r < labelRadius + 108);

      if (isSubTrack) {
        trackPaint.color = surface.specularAt(0.12);
        trackPaint.strokeWidth = 0.9;
      } else {
        final variance =
            ((math.sin(r * 1.2) + 1.0) * 0.035 + 0.02).clamp(0.015, 0.075);
        trackPaint.color = surface.specularAt(variance);
        trackPaint.strokeWidth = 0.45;
      }
      canvas.drawCircle(center, r, trackPaint);
    }

    // 5. Clear Inner Clamping / Mirror Band (Characteristic CD inner ring)
    final mirrorPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          surface.specularAt(0.18),
          surface.specularAt(0.05),
          surface.specularAt(0.15),
          surface.specularAt(0.04),
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
      ..color = activeColor.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, labelRadius + 9, laserRingPaint);

    // 6. Outer Polycarbonate Clear Rim with Glass Refraction
    final outerRimPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          surface.specularAt(0.45),
          surface.specularAt(0.15),
          surface.specularAt(0.50),
          surface.specularAt(0.12),
          surface.specularAt(0.45),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, outerRimPaint);

    final innerBevelPaint = Paint()
      ..color = surface.shadowAt(0.35)
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

  _CdFlarePainter({this.labelRatio = 0.44});

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

/// Paints the jewel case that seats the disc: translucent lid, hinge spine,
/// recessed tray and the gloss band that sweeps the lid on play/pause.
///
/// The case is what makes this deck read as a CD jewel box instead of a second
/// turntable. Everything here is anchored to the stage box, so it repaints only
/// when the gloss animation ticks or the case geometry changes.
class _CdJewelCasePainter extends CustomPainter {
  final double spineWidth;
  final Rect trayRect;
  final Offset discCenter;
  final double discRadius;
  final Color activeColor;
  final bool isPlaying;
  final PlayerSurfacePalette surface;

  _CdJewelCasePainter({
    required this.spineWidth,
    required this.trayRect,
    required this.discCenter,
    required this.discRadius,
    required this.activeColor,
    required this.isPlaying,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final caseRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final caseRRect = RRect.fromRectAndRadius(
      caseRect.deflate(0.5),
      const Radius.circular(AppRadii.r14),
    );

    // 1. Case lift-off shadow.
    canvas.drawRRect(
      caseRRect.shift(const Offset(0, 8)),
      Paint()
        ..color = surface.shadowAt(0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // 2. Translucent polycarbonate lid. It stays dark enough to keep the white
    // VFD read-out legible in the light theme.
    canvas.drawRRect(
      caseRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surface.cassetteShell.withValues(alpha: 0.97),
            PlayerMaterialColors.cdTrayGradStart,
            surface.tapeWindow,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(caseRect),
    );

    // 3. Clear plastic edge bevel: bright where the light hits, dim opposite.
    canvas.drawRRect(
      caseRRect.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surface.specularAt(0.30),
            surface.specularAt(0.06),
            surface.specularAt(0.16),
          ],
        ).createShader(caseRect),
    );

    // 4. The tray the disc clips into: a recessed panel, darker than the lid.
    final trayRRect = RRect.fromRectAndRadius(
      trayRect,
      const Radius.circular(AppRadii.r10),
    );
    canvas.drawRRect(
      trayRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface.vinylGroove.withValues(alpha: 0.55),
            PlayerMaterialColors.cdSurfaceBottom.withValues(alpha: 0.78),
          ],
        ).createShader(trayRect),
    );
    canvas.drawRRect(
      trayRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = surface.specularAt(0.10),
    );

    // 5. Hinge spine along the leading edge, with the lid seam and ribs.
    final spineRect = Rect.fromLTWH(
      caseRect.left + 1.5,
      caseRect.top + 1.5,
      math.max(spineWidth - 1.5, 4.0),
      caseRect.height - 3.0,
    );
    canvas.drawRect(
      spineRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            PlayerMaterialColors.cdClampWell,
            PlayerMaterialColors.cdTrayGradStart,
          ],
        ).createShader(spineRect),
    );
    canvas.drawLine(
      Offset(spineRect.right, spineRect.top),
      Offset(spineRect.right, spineRect.bottom),
      Paint()
        ..color = surface.specularAt(0.14)
        ..strokeWidth = 1.0,
    );
    final ribPaint = Paint()
      ..color = surface.specularAt(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (final double fraction in const [0.22, 0.5, 0.78]) {
      final y = spineRect.top + spineRect.height * fraction;
      canvas.drawLine(
        Offset(spineRect.left + 4, y),
        Offset(spineRect.right - 4, y),
        ribPaint,
      );
    }

    // 6. Disc seat: a shadowed well with a lit rim, plus the accent ring that
    // brightens while the deck is playing.
    canvas.drawCircle(
      discCenter,
      discRadius + 7,
      Paint()..color = surface.shadowAt(0.30),
    );
    canvas.drawCircle(
      discCenter,
      discRadius + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = surface.specularAt(0.08),
    );
    canvas.drawCircle(
      discCenter,
      discRadius + 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = activeColor.withValues(alpha: isPlaying ? 0.20 : 0.08),
    );

    // The lid gloss itself is painted above the disc by _CdLidGlossPainter, so
    // the sweep crosses the disc like light over clear plastic.
  }

  @override
  bool shouldRepaint(covariant _CdJewelCasePainter oldDelegate) =>
      oldDelegate.spineWidth != spineWidth ||
      oldDelegate.trayRect != trayRect ||
      oldDelegate.discCenter != discCenter ||
      oldDelegate.discRadius != discRadius ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.isPlaying != isPlaying ||
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
        Rect.fromLTRB(railLeft, railY - 3.5, railRight, railY + 3.5),
        const Radius.circular(AppRadii.r1_5),
      ),
      Paint()..color = PlayerMaterialColors.cdWeightLow,
    );
    canvas.drawLine(
      Offset(railLeft, railY),
      Offset(railRight, railY),
      Paint()
        ..color = PlayerMaterialColors.cdWeightRim.withValues(alpha: 0.8)
        ..strokeWidth = 1.0,
    );
    final stopPaint = Paint()..color = PlayerMaterialColors.cdCollar;
    canvas.drawRect(
      Rect.fromLTRB(railLeft - 2, railY - 5, railLeft, railY + 5),
      stopPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(railRight, railY - 5, railRight + 2, railY + 5),
      stopPaint,
    );

    // 2. Read beam: only the ray that actually leaves the lens and lands on the
    // disc is drawn, so a parked sled shows no phantom light.
    if (engaged > 0) {
      final dx = lensX - discCenter.dx;
      final inside = discRadius * discRadius - dx * dx;
      if (inside > 0) {
        final spotY = discCenter.dy + math.sqrt(inside);
        canvas.drawLine(
          Offset(lensX, railY - 12),
          Offset(lensX, spotY),
          Paint()
            ..color = activeColor.withValues(alpha: 0.45 * engaged)
            ..strokeWidth = 1.1,
        );
        canvas.drawCircle(
          Offset(lensX, spotY),
          3.2,
          Paint()
            ..color = activeColor.withValues(alpha: 0.55 * engaged)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }

    // 3. Lens head: sled block, objective lens and its glow while engaged.
    final headRect = Rect.fromCenter(
      center: Offset(lensX, railY - 7),
      width: 16,
      height: 14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        headRect,
        const Radius.circular(AppRadii.r3),
      ),
      Paint()
        ..shader = LinearGradient(
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
        ..color = surface.specularAt(0.18),
    );

    final objective = Offset(lensX, railY - 10);
    canvas.drawCircle(
      objective,
      2.6,
      Paint()..color = activeColor.withValues(alpha: 0.30 + (0.70 * engaged)),
    );
    if (engaged > 0) {
      canvas.drawCircle(
        objective,
        5.0,
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

/// The lid highlight that sweeps across the closed case when playback starts or
/// stops. It is painted above the disc — light crossing clear plastic — and is
/// driven straight from the gloss animation so no widget rebuilds per frame.
class _CdLidGlossPainter extends CustomPainter {
  final Animation<double> gloss;
  final PlayerSurfacePalette surface;

  _CdLidGlossPainter({required this.gloss, required this.surface})
      : super(repaint: gloss);

  @override
  void paint(Canvas canvas, Size size) {
    final sweep = gloss.value;
    if (sweep <= 0.0 || sweep >= 1.0) return;

    final caseRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(0.5),
      const Radius.circular(AppRadii.r14),
    );
    final bandWidth = size.width * 0.34;
    final x = -bandWidth + (size.width + bandWidth * 2) * sweep;

    canvas.save();
    canvas.clipRRect(caseRRect);
    canvas.translate(x, 0);
    canvas.rotate(-0.32);
    final bandRect = Rect.fromLTWH(0, -size.height, bandWidth, size.height * 3);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            surface.specularAt(0.0),
            surface.specularAt(0.16),
            surface.specularAt(0.0),
          ],
        ).createShader(bandRect)
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CdLidGlossPainter oldDelegate) =>
      oldDelegate.gloss != gloss || oldDelegate.surface != surface;
}
