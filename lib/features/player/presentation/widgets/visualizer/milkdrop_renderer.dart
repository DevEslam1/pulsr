// lib/features/player/presentation/widgets/visualizer/milkdrop_renderer.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../../core/performance/gpu_budget.dart';
import '../../../../../domain/models/milkdrop_preset.dart';

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

  const MilkdropRenderer({
    super.key,
    this.shader,
    required this.data,
    required this.color,
    required this.preset,
    this.forceCanvasFallback = false,
  });

  bool get isFallback =>
      forceCanvasFallback || shader == null || GpuBudget.isGpuSaverActive;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: (!isFallback && shader != null)
            ? MilkdropGpuPainter(
                shader: shader!,
                data: data,
                color: color,
                preset: preset,
              )
            : MilkdropCanvasPainter(
                data: data,
                color: color,
                preset: preset,
              ),
      ),
    );
  }
}

/// GPU shader painter for MilkDrop effects using `shaders/milkdrop.frag`.
class MilkdropGpuPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;

  MilkdropGpuPainter({
    required this.shader,
    required this.data,
    required this.color,
    required this.preset,
  });

  double _avg(int a, int b) {
    if (data.isEmpty) return 0.0;
    final lo = a.clamp(0, data.length - 1);
    final hi = b.clamp(lo + 1, data.length);
    if (hi <= lo) return 0.0;
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      sum += data[i];
    }
    return sum / (hi - lo);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, t);
    shader.setFloat(3, _avg(0, 6));
    shader.setFloat(4, _avg(8, 18));
    shader.setFloat(5, _avg(22, 32));
    shader.setFloat(6, color.r);
    shader.setFloat(7, color.g);
    shader.setFloat(8, color.b);
    shader.setFloat(9, preset.waveR.clamp(0.0, 1.0));
    shader.setFloat(10, preset.waveG.clamp(0.0, 1.0));
    shader.setFloat(11, preset.waveB.clamp(0.0, 1.0));
    shader.setFloat(12, preset.zoom);
    shader.setFloat(13, preset.rot);
    shader.setFloat(14, preset.warp);
    shader.setFloat(15, preset.decay.clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant MilkdropGpuPainter oldDelegate) => true;
}

/// Parameter-driven Canvas fallback approximation for MilkDrop presets.
class MilkdropCanvasPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;

  MilkdropCanvasPainter({
    required this.data,
    required this.color,
    required this.preset,
  });

  double _avg(int a, int b) {
    if (data.isEmpty) return 0.0;
    final lo = a.clamp(0, data.length - 1);
    final hi = b.clamp(lo + 1, data.length);
    if (hi <= lo) return 0.0;
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      sum += data[i];
    }
    return sum / (hi - lo);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final bass = _avg(0, 6);
    final mid = _avg(8, 18);
    final treb = _avg(22, 32);
    final center = Offset(size.width / 2, size.height / 2);

    final waveColor = Color.fromARGB(
      255,
      (preset.waveR.clamp(0.0, 1.0) * 255).round(),
      (preset.waveG.clamp(0.0, 1.0) * 255).round(),
      (preset.waveB.clamp(0.0, 1.0) * 255).round(),
    );
    final tint = Color.lerp(color, waveColor, 0.55)!;

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

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const rings = 12;
    final speed = (0.35 + bass * 1.1) * (0.6 + preset.decay);
    final baseRot = preset.rot * t * 6.28318 + (mid - 0.35) * 0.6;
    for (var r = 0; r < rings; r++) {
      final phase = ((t * speed) + r / rings) % 1.0;
      final depth = math.pow(phase, 1.5).toDouble();
      final radius = size.shortestSide * 0.52 * depth * preset.zoom;
      if (radius < 2) continue;
      final alpha = ((1.0 - phase) * (0.35 + bass * 0.65)).clamp(0.02, 0.9);
      ringPaint
        ..color = tint.withValues(alpha: alpha.toDouble())
        ..strokeWidth = 1.0 + depth * 2.5;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(baseRot + r * 0.18);
      final warpX = 1.0 + (preset.warp - 1.0) * depth * 0.35;
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
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 + bass * 2.0
        ..strokeCap = StrokeCap.round
        ..color = tint.withValues(alpha: 0.85);
      final path = Path();
      final n = data.length;
      for (var i = 0; i < n; i++) {
        final x = size.width * (i / (n - 1));
        final amp = size.height * (0.30 + bass * 0.18);
        final y = center.dy + (data[i] - 0.5) * amp * (1.0 + treb * 0.8);
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
      final m = data[i].clamp(0.02, 1.0);
      final angle = (i / data.length) * 6.28318 + t * 0.4;
      final dist = size.shortestSide * 0.5 * math.pow(m, 1.3).toDouble();
      final x = center.dx + dist * math.cos(angle);
      final y = center.dy + dist * math.sin(angle);
      particlePaint.color = tint.withValues(alpha: (m * 0.5).clamp(0.0, 0.6));
      canvas.drawCircle(Offset(x, y), 1.0 + m * 3.0, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant MilkdropCanvasPainter oldDelegate) => true;
}

// Deprecated typedefs to maintain backwards compatibility
@Deprecated('Use MilkdropGpuPainter instead')
typedef MilkdropGpuPainterAlias = MilkdropGpuPainter;

@Deprecated('Use MilkdropCanvasPainter instead')
typedef MilkdropPainterAlias = MilkdropCanvasPainter;
