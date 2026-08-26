// lib/core/widgets/pulsr_logo.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Highly optimized, scalable native vector rendering of the official Pulsr App Icon.
/// Renders with full neon glow, ambient concentric wave ripples, inner mesh, and theme-adaptive coloring.
class PulsrLogo extends StatefulWidget {
  final double size;
  final Color? color;
  final Color? glowColor;
  final bool showBackground;
  final bool animate;
  final double borderRadius;

  const PulsrLogo({
    super.key,
    this.size = 48,
    this.color,
    this.glowColor,
    this.showBackground = false,
    this.animate = false,
    this.borderRadius = 14,
  });

  @override
  State<PulsrLogo> createState() => _PulsrLogoState();
}

class _PulsrLogoState extends State<PulsrLogo> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(PulsrLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller ??= AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2400),
        )..repeat();
      } else {
        _controller?.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeAccent = widget.color ?? Theme.of(context).colorScheme.primary;
    final themeGlow = widget.glowColor ?? themeAccent;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller ?? const AlwaysStoppedAnimation(0.0),
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _PulsrLogoPainter(
              color: themeAccent,
              glowColor: themeGlow,
              showBackground: widget.showBackground,
              borderRadius: widget.borderRadius,
              animationValue: _controller?.value ?? 0.0,
            ),
          );
        },
      ),
    );
  }
}

class _PulsrLogoPainter extends CustomPainter {
  final Color color;
  final Color glowColor;
  final bool showBackground;
  final double borderRadius;
  final double animationValue;

  _PulsrLogoPainter({
    required this.color,
    required this.glowColor,
    required this.showBackground,
    required this.borderRadius,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512.0;

    canvas.save();
    canvas.scale(scale, scale);

    // 1. Optional App Icon Background
    if (showBackground) {
      final bgRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 512, 512),
        Radius.circular(borderRadius * (512.0 / size.width)),
      );
      final bgPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.75,
          colors: [
            color.withValues(alpha: 0.95),
            Color.lerp(color, const Color(0xFF002288), 0.5) ?? const Color(0xFF0077FF),
            const Color(0xFF001550),
            const Color(0xFF0A0C12),
          ],
          stops: const [0.0, 0.4, 0.75, 1.0],
        ).createShader(const Rect.fromLTWH(0, 0, 512, 512));

      canvas.drawRRect(bgRect, bgPaint);
    }

    // 2. Ambient Concentric Waves
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: showBackground ? 0.08 : 0.12);

    final animPhase = animationValue * 2 * math.pi;

    // Central framing waves
    for (final r in [140.0, 180.0, 220.0, 260.0, 300.0]) {
      final pulse = (math.sin(animPhase + r * 0.02) * 2).clamp(-3.0, 3.0);
      canvas.drawCircle(const Offset(256, 256), r + pulse, wavePaint);
    }

    // Bottom Bulb Waves (center: 210, 370)
    final bulbCenter = const Offset(210, 370);
    for (int i = 0; i < 9; i++) {
      final r = 60.0 + i * 30.0;
      final alpha = (0.12 - (i * 0.012)).clamp(0.02, 0.15);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: alpha);
      final pulse = (math.sin(animPhase + i * 0.4) * 2.5);
      canvas.drawCircle(bulbCenter, r + pulse, p);
    }

    // Top Hook Waves (center: 340, 165)
    final hookCenter = const Offset(340, 165);
    for (int i = 0; i < 6; i++) {
      final r = 50.0 + i * 30.0;
      final alpha = (0.12 - (i * 0.018)).clamp(0.02, 0.15);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: alpha);
      final pulse = (math.cos(animPhase + i * 0.5) * 2.0);
      canvas.drawCircle(hookCenter, r + pulse, p);
    }

    // 3. The Musical Note Vector Path
    final notePath = Path()
      ..moveTo(270, 120)
      ..cubicTo(320, 100, 370, 130, 380, 165)
      ..cubicTo(385, 185, 365, 190, 350, 175)
      ..cubicTo(335, 155, 310, 145, 295, 150)
      ..lineTo(295, 315)
      ..cubicTo(310, 290, 280, 265, 240, 260)
      ..cubicTo(170, 250, 120, 310, 140, 370)
      ..cubicTo(160, 430, 240, 430, 280, 380)
      ..cubicTo(295, 360, 295, 340, 295, 320)
      ..lineTo(295, 120)
      ..close();

    // 4. Note Base Fill & Glow
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = glowColor.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawPath(notePath, glowPaint);

    final noteBasePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: showBackground ? 0.20 : 0.10);
    canvas.drawPath(notePath, noteBasePaint);

    // 5. Concentric Internal Mesh Clipped Strictly Inside Note
    canvas.save();
    canvas.clipPath(notePath);

    final meshPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = (showBackground ? Colors.white : color).withValues(alpha: 0.90);

    // Bulb internal ripples
    for (double r = 5; r <= 152; r += 7) {
      canvas.drawCircle(bulbCenter, r, meshPaint);
    }
    // Hook internal ripples
    for (double r = 5; r <= 82; r += 7) {
      canvas.drawCircle(hookCenter, r, meshPaint);
    }
    canvas.restore();

    // 6. Outer Bright Contour Outlines
    final thickOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..color = showBackground ? Colors.white : color;
    canvas.drawPath(notePath, thickOutline);

    final crispOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawPath(notePath, crispOutline);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PulsrLogoPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.showBackground != showBackground ||
        oldDelegate.animationValue != animationValue;
  }
}
