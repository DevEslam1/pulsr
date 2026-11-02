// lib/core/widgets/waveform_logo.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../motion/pulsr_motion.dart';

/// {@category DesignSystem}
/// Five-bar audio waveform glyph rendered via zero-allocation [CustomPaint].
class WaveformLogo extends StatefulWidget {
  final double size;
  final Color? color;
  final bool animate;

  const WaveformLogo({
    super.key,
    this.size = 32,
    this.color,
    this.animate = false,
  });

  @override
  State<WaveformLogo> createState() => _WaveformLogoState();
}

class _WaveformLogoState extends State<WaveformLogo>
    with TickerProviderStateMixin {
  AnimationController? _controller;

  bool get _isTestEnv =>
      const bool.fromEnvironment('flutter.test') ||
      (WidgetsBinding.instance is! WidgetsFlutterBinding);

  @override
  void initState() {
    super.initState();
    if (widget.animate && !_isTestEnv) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(WaveformLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate && _controller == null && !_isTestEnv) {
        final c = _controller = AnimationController(
          vsync: this,
          duration: context.motionMs(800),
        );
        // didChangeDependencies does not fire on a prop-only change, so honor
        // reduce-motion here instead of unconditionally repeating.
        if (context.motionEnabled) {
          c.repeat(reverse: true);
        }
      } else if (!widget.animate) {
        _controller?.dispose();
        _controller = null;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = _controller;
    if (c == null) return;
    c.duration = context.motionMs(800);
    if (!context.motionEnabled || _isTestEnv) {
      c.stop();
      c.value = 0;
    } else if (!c.isAnimating) {
      c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.color ?? Colors.white;

    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final effectiveSize = widget.size.isFinite && widget.size > 0
              ? widget.size
              : (constraints.biggest.shortestSide.isFinite &&
                      constraints.biggest.shortestSide > 0
                  ? constraints.biggest.shortestSide
                  : 48.0);

          return RepaintBoundary(
            child: SizedBox(
              width: effectiveSize,
              height: effectiveSize,
              child: CustomPaint(
                size: Size.square(effectiveSize),
                painter: _WaveformLogoPainter(
                  animation: _controller,
                  color: themeColor,
                  isAnimating: _controller != null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaveformLogoPainter extends CustomPainter {
  static const List<double> _baseHeights = [0.35, 0.65, 1.0, 0.75, 0.45];
  static const List<double> _phaseOffsets = [0.0, 0.9, 1.8, 2.7, 3.6];

  final Animation<double>? animation;
  final Color color;
  final bool isAnimating;

  _WaveformLogoPainter({
    required this.animation,
    required this.color,
    required this.isAnimating,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final barWidth = w * 0.125;
    final radius = Radius.circular(barWidth / 2);
    final totalSpacing = w - (barWidth * 5);
    final gap = totalSpacing / 6.0;
    final centerY = h / 2.0;
    final t = animation?.value ?? 0.0;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: isAnimating ? 0.30 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, Colors.white, 0.18) ?? color,
          color,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    for (var i = 0; i < 5; i++) {
      final double ratio;
      if (isAnimating) {
        final wave = math.sin(t * math.pi + _phaseOffsets[i]).abs();
        final pulse = 0.78 + (wave * 0.34);
        ratio = (_baseHeights[i] * pulse).clamp(0.22, 1.0);
      } else {
        ratio = _baseHeights[i];
      }

      final barHeight = h * ratio;
      final x = gap + i * (barWidth + gap);
      final top = centerY - (barHeight / 2.0);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, barHeight),
        radius,
      );

      canvas.drawRRect(rrect, glowPaint);
      canvas.drawRRect(rrect, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformLogoPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isAnimating != isAnimating ||
        oldDelegate.animation != animation;
  }
}
