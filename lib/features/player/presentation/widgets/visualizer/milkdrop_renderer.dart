// lib/features/player/presentation/widgets/visualizer/milkdrop_renderer.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import '../../../../../core/performance/gpu_budget.dart';
import '../../../../../domain/models/milkdrop_preset.dart';

/// Shared monotonic stopwatch so [MilkdropGpuPainter] and [MilkdropCanvasPainter]
/// never experience wall-clock jumps or 3600s modulo resets when no external
/// clock sample is provided.
final Stopwatch _fallbackMonotonicClock = Stopwatch()..start();

/// Dedicated MilkDrop visualizer renderer.
/// Renders via GPU fragment shader (`shaders/milkdrop.frag`) when available and
/// falls back seamlessly to a high-fidelity parameter-driven Canvas approximation
/// when running under GPU Saver or when runtime shader compilation is unsupported.
class MilkdropRenderer extends StatelessWidget {
  final ui.FragmentShader? shader;
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;
  final bool forceCanvasFallback;
  final bool transparentBackground;
  final int generation;
  final double? elapsedSeconds;

  const MilkdropRenderer({
    super.key,
    this.shader,
    required this.data,
    required this.color,
    required this.preset,
    this.forceCanvasFallback = false,
    this.transparentBackground = false,
    this.generation = 0,
    this.elapsedSeconds,
  });

  bool get isFallback =>
      forceCanvasFallback || shader == null || GpuBudget.isGpuSaverActive;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GpuBudget.enabled,
      builder: (context, isGpuSaver, _) {
        final useFallback = forceCanvasFallback || shader == null || isGpuSaver;
        return RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: (!useFallback && shader != null)
                ? MilkdropGpuPainter(
                    shader: shader!,
                    data: data,
                    color: color,
                    preset: preset,
                    transparentBackground: transparentBackground,
                    generation: generation,
                    elapsedSeconds: elapsedSeconds,
                  )
                : MilkdropCanvasPainter(
                    data: data,
                    color: color,
                    preset: preset,
                    transparentBackground: transparentBackground,
                    generation: generation,
                    elapsedSeconds: elapsedSeconds,
                  ),
          ),
        );
      },
    );
  }
}

double _sanitizeScalar(double value, double fallback, double min, double max) {
  if (!value.isFinite) return fallback;
  return value.clamp(min, max);
}

double _resolveMonotonicSeconds(double? elapsedSeconds) {
  if (elapsedSeconds != null && elapsedSeconds.isFinite && elapsedSeconds >= 0) {
    return elapsedSeconds;
  }
  return _fallbackMonotonicClock.elapsedMicroseconds / 1000000.0;
}

/// GPU shader painter for MilkDrop effects using `shaders/milkdrop.frag`.
class MilkdropGpuPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;
  final bool transparentBackground;
  final int generation;
  final double? elapsedSeconds;

  MilkdropGpuPainter({
    required this.shader,
    required this.data,
    required this.color,
    required this.preset,
    this.transparentBackground = false,
    this.generation = 0,
    this.elapsedSeconds,
  });

  double _avg(int a, int b) {
    if (data.isEmpty) return 0.0;
    final lo = a.clamp(0, data.length - 1);
    final hi = b.clamp(lo + 1, data.length);
    if (hi <= lo) return 0.0;
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      final v = data[i];
      if (v.isFinite) sum += v;
    }
    return sum / (hi - lo);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = _resolveMonotonicSeconds(elapsedSeconds);
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, t);
    shader.setFloat(3, _avg(0, 6));
    shader.setFloat(4, _avg(8, 18));
    shader.setFloat(5, _avg(22, 32));
    shader.setFloat(6, color.r);
    shader.setFloat(7, color.g);
    shader.setFloat(8, color.b);
    shader.setFloat(9, _sanitizeScalar(preset.waveR, 1.0, 0.0, 1.0));
    shader.setFloat(10, _sanitizeScalar(preset.waveG, 1.0, 0.0, 1.0));
    shader.setFloat(11, _sanitizeScalar(preset.waveB, 1.0, 0.0, 1.0));
    shader.setFloat(12, _sanitizeScalar(preset.zoom, 1.0, 0.2, 5.0));
    shader.setFloat(13, _sanitizeScalar(preset.rot, 0.0, -6.283185, 6.283185));
    shader.setFloat(14, _sanitizeScalar(preset.warp, 1.0, 0.05, 4.0));
    shader.setFloat(15, _sanitizeScalar(preset.decay, 0.95, 0.0, 1.0));
    shader.setFloat(16, transparentBackground ? 1.0 : 0.0);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant MilkdropGpuPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.elapsedSeconds != elapsedSeconds ||
      oldDelegate.generation != generation ||
      oldDelegate.color != color ||
      oldDelegate.preset != preset ||
      oldDelegate.transparentBackground != transparentBackground ||
      !listEquals(oldDelegate.data, data);
}

/// Parameter-driven Canvas fallback approximation for MilkDrop presets.
class MilkdropCanvasPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;
  final bool transparentBackground;
  final int generation;
  final double? elapsedSeconds;

  MilkdropCanvasPainter({
    required this.data,
    required this.color,
    required this.preset,
    this.transparentBackground = false,
    this.generation = 0,
    this.elapsedSeconds,
  });

  double _avg(int a, int b) {
    if (data.isEmpty) return 0.0;
    final lo = a.clamp(0, data.length - 1);
    final hi = b.clamp(lo + 1, data.length);
    if (hi <= lo) return 0.0;
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      final v = data[i];
      if (v.isFinite) sum += v;
    }
    return sum / (hi - lo);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = _resolveMonotonicSeconds(elapsedSeconds);
    final bass = _avg(0, 6);
    final mid = _avg(8, 18);
    final treb = _avg(22, 32);
    final center = Offset(size.width / 2, size.height / 2);

    final safeWaveR = _sanitizeScalar(preset.waveR, 1.0, 0.0, 1.0);
    final safeWaveG = _sanitizeScalar(preset.waveG, 1.0, 0.0, 1.0);
    final safeWaveB = _sanitizeScalar(preset.waveB, 1.0, 0.0, 1.0);
    final safeZoom = _sanitizeScalar(preset.zoom, 1.0, 0.2, 5.0);
    final safeRot = _sanitizeScalar(preset.rot, 0.0, -6.283185, 6.283185);
    final safeWarp = _sanitizeScalar(preset.warp, 1.0, 0.05, 4.0);
    final safeDecay = _sanitizeScalar(preset.decay, 0.95, 0.0, 1.0);

    final isWhiteTransparent = transparentBackground || color == Colors.white;
    final waveColor = isWhiteTransparent
        ? Colors.white
        : Color.fromARGB(
            255,
            (safeWaveR * 255).round(),
            (safeWaveG * 255).round(),
            (safeWaveB * 255).round(),
          );
    final tint =
        isWhiteTransparent ? Colors.white : Color.lerp(color, waveColor, 0.55)!;

    if (!transparentBackground) {
      final bg = Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(Colors.black, tint, 0.18 + bass * 0.30)!,
            Colors.black,
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.longestSide * 0.75),
        );
      canvas.drawRect(Offset.zero & size, bg);
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const rings = 12;
    final speed = (0.35 + bass * 1.1) * (0.6 + safeDecay);
    final baseRot = safeRot * t * 6.28318 + (mid - 0.35) * 0.6;
    for (var r = 0; r < rings; r++) {
      final phase = ((t * speed) + r / rings) % 1.0;
      final depth = math.pow(phase, 1.5).toDouble();
      final radius = size.shortestSide * 0.52 * depth * safeZoom;
      if (radius < 2) continue;
      final rawAlpha = ((1.0 - phase) * (0.35 + bass * 0.65)).clamp(0.02, 0.9);
      final alpha =
          isWhiteTransparent ? (rawAlpha * 0.55).clamp(0.04, 0.70) : rawAlpha;
      ringPaint
        ..color = tint.withValues(alpha: alpha.toDouble())
        ..strokeWidth = 1.0 + depth * 2.5;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(baseRot + r * 0.18);
      final rawWarpX = 1.0 + (safeWarp - 1.0) * depth * 0.35;
      final warpX =
          rawWarpX.isFinite ? rawWarpX.clamp(0.05, 4.0) : 1.0;
      canvas.scale(warpX, 1.0 / warpX);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 2,
          height: radius * 2 * 0.82,
        ),
        ringPaint,
      );
      canvas.restore();
    }

    if (data.isNotEmpty && data.length > 1) {
      final waveAlpha =
          isWhiteTransparent ? (0.35 + bass * 0.45).clamp(0.15, 0.85) : 0.85;
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 + bass * 2.0
        ..strokeCap = StrokeCap.round
        ..color = tint.withValues(alpha: waveAlpha);
      final path = Path();
      final n = data.length;
      for (var i = 0; i < n; i++) {
        final x = size.width * (i / (n - 1));
        final amp = size.height * (0.30 + bass * 0.18);
        final sample = data[i].isFinite ? data[i] : 0.5;
        final y = center.dy + (sample - 0.5) * amp * (1.0 + treb * 0.8);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wavePaint);
    }

    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < data.length; i += 2) {
      final sample = data[i].isFinite ? data[i] : 0.02;
      final m = sample.clamp(0.02, 1.0);
      final angle = (i / data.length) * 6.28318 + t * 0.4;
      final dist = size.shortestSide * 0.5 * math.pow(m, 1.3).toDouble();
      final x = center.dx + dist * math.cos(angle);
      final y = center.dy + dist * math.sin(angle);
      final particleAlpha = isWhiteTransparent
          ? (m * 0.45 + bass * 0.25).clamp(0.05, 0.65)
          : (m * 0.5).clamp(0.0, 0.6);
      particlePaint.color = tint.withValues(alpha: particleAlpha);
      canvas.drawCircle(Offset(x, y), 1.0 + m * 3.0, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant MilkdropCanvasPainter oldDelegate) =>
      oldDelegate.elapsedSeconds != elapsedSeconds ||
      oldDelegate.generation != generation ||
      oldDelegate.color != color ||
      oldDelegate.preset != preset ||
      oldDelegate.transparentBackground != transparentBackground ||
      !listEquals(oldDelegate.data, data);
}
