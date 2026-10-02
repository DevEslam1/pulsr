// lib/features/player/presentation/widgets/eq_curve_visualizer.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/l10n_extensions.dart';

/// Real-time interactive Equalizer Curve visualizer utilizing centripetal
/// Catmull-Rom spline interpolation, dB reference grid lines, frequency
/// markers, and direct drag interaction on band nodes.
class EqCurveVisualizer extends StatefulWidget {
  final List<double> gains;
  final Color activeColor;
  final double height;
  final List<double>? spectrumData;
  final List<double>? frequencies;
  final double maxGain;
  final bool showGrid;
  final bool showLabels;
  final int? selectedBandIndex;
  final void Function(int bandIndex, double gain)? onGainChanged;
  final ValueChanged<int>? onBandSelected;

  const EqCurveVisualizer({
    super.key,
    required this.gains,
    required this.activeColor,
    this.height = 80,
    this.spectrumData,
    this.frequencies,
    this.maxGain = 15.0,
    this.showGrid = true,
    this.showLabels = false,
    this.selectedBandIndex,
    this.onGainChanged,
    this.onBandSelected,
  });

  @override
  State<EqCurveVisualizer> createState() => _EqCurveVisualizerState();
}

class _EqCurveVisualizerState extends State<EqCurveVisualizer> {
  int? _activeDraggingBand;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onGainChanged != null;

    Widget visualizer = RepaintBoundary(
      child: Semantics(
        label: context.l10n.equalizer,
        value: '${widget.gains.length} ${context.l10n.bandsLabel}',
        child: CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _CatmullRomEqPainter(
            gains: widget.gains,
            color: widget.activeColor,
            spectrumData: widget.spectrumData,
            frequencies: widget.frequencies,
            maxGain: widget.maxGain,
            showGrid: widget.showGrid,
            showLabels: widget.showLabels && widget.height >= 70,
            selectedBandIndex: _activeDraggingBand ?? widget.selectedBandIndex,
          ),
        ),
      ),
    );

    if (isInteractive && widget.gains.isNotEmpty) {
      visualizer = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _handlePanStart(details.localPosition),
        onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
        onPanEnd: (_) => _handlePanEnd(),
        onPanCancel: () => _handlePanEnd(),
        child: visualizer,
      );
    }

    return Semantics(
      label: context.l10n.equalizerResponseCurve,
      child: visualizer,
    );
  }

  void _handlePanStart(Offset localPos) {
    if (widget.gains.isEmpty) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final stepX = widget.gains.length > 1
        ? size.width / (widget.gains.length - 1)
        : size.width;

    // Find nearest band index within reach
    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < widget.gains.length; i++) {
      final bandX = i * stepX;
      final dist = (localPos.dx - bandX).abs();
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    // Hit tolerance: half step or 32 logical pixels, whichever is larger
    final hitTolerance = math.max(stepX / 2, 32.0);
    if (minDistance <= hitTolerance) {
      setState(() => _activeDraggingBand = closestIndex);
      widget.onBandSelected?.call(closestIndex);
      if (context.motionEnabled) {
        HapticFeedback.selectionClick();
      }
      _updateGainForPosition(closestIndex, localPos.dy, size.height);
    }
  }

  void _handlePanUpdate(Offset localPos) {
    if (_activeDraggingBand == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    _updateGainForPosition(
        _activeDraggingBand!, localPos.dy, renderBox.size.height);
  }

  void _updateGainForPosition(int bandIndex, double yPos, double totalHeight) {
    final midY = totalHeight / 2;
    final effectiveSpan = (totalHeight / 2) * 0.9;
    // Invert Y: top is +maxGain, bottom is -maxGain
    final rawGain = ((midY - yPos) / effectiveSpan) * widget.maxGain;
    final clampedGain = rawGain.clamp(-widget.maxGain, widget.maxGain);
    widget.onGainChanged?.call(bandIndex, clampedGain);
  }

  void _handlePanEnd() {
    if (_activeDraggingBand != null) {
      setState(() => _activeDraggingBand = null);
    }
  }
}

class _CatmullRomEqPainter extends CustomPainter {
  final List<double> gains;
  final Color color;
  final List<double>? spectrumData;
  final List<double>? frequencies;
  final double maxGain;
  final bool showGrid;
  final bool showLabels;
  final int? selectedBandIndex;

  _CatmullRomEqPainter({
    required this.gains,
    required this.color,
    this.spectrumData,
    this.frequencies,
    required this.maxGain,
    required this.showGrid,
    required this.showLabels,
    this.selectedBandIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;

    final midY = size.height / 2;
    final stepX =
        gains.length > 1 ? size.width / (gains.length - 1) : size.width;
    final verticalScale = (size.height / 2 * 0.9);

    // 1. Draw Real-time FFT Spectrum background if provided
    if (spectrumData != null && spectrumData!.isNotEmpty) {
      _paintSpectrum(canvas, size);
    }

    // 2. Draw Gridlines (+12, +6, 0 dB, -6, -12 dB)
    if (showGrid) {
      _paintGrid(canvas, size, midY, verticalScale);
    }

    // 3. Compute Control Points
    final points = <Offset>[];
    for (int i = 0; i < gains.length; i++) {
      final x = i * stepX;
      final clampedGain = gains[i].clamp(-maxGain, maxGain);
      final y = midY - (clampedGain / maxGain) * verticalScale;
      points.add(Offset(x, y));
    }

    // 4. Construct Centripetal Catmull-Rom Spline Path
    final curvePath = _buildCentripetalCatmullRomSpline(points);

    // 5. Fill Area under Curve (Gradient towards 0 dB line)
    final fillPath = Path.from(curvePath)
      ..lineTo(points.last.dx, midY)
      ..lineTo(points.first.dx, midY)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // 6. Draw Curve Stroke
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(curvePath, strokePaint);

    // 7. Draw Band Control Nodes & Selection Halos
    _paintBandNodes(canvas, points, midY);
  }

  void _paintSpectrum(Canvas canvas, Size size) {
    final specPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;

    final specWidth = size.width / spectrumData!.length;
    for (int i = 0; i < spectrumData!.length; i++) {
      final val = spectrumData![i].clamp(0.0, 1.0);
      final barH = val * size.height * 0.85;
      final x = i * specWidth + 1.0;
      final y = size.height - barH;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, math.max(1.0, specWidth - 2.0), barH),
        const Radius.circular(AppRadii.r2),
      );
      canvas.drawRRect(rect, specPaint);
    }
  }

  void _paintGrid(Canvas canvas, Size size, double midY, double verticalScale) {
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final centerPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 1.2;

    // 0 dB reference line
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), centerPaint);

    // Secondary gridlines at fractions (e.g., +12, +6, -6, -12 dB)
    final gridLevels = [0.8, 0.4, -0.4, -0.8];
    for (final level in gridLevels) {
      final y = midY - (level * verticalScale);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  Path _buildCentripetalCatmullRomSpline(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.moveTo(points.first.dx, points.first.dy);
      return path;
    }

    path.moveTo(points.first.dx, points.first.dy);

    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    // Extended points with clamped virtual boundaries
    final extPoints = <Offset>[
      points.first * 2 - points[1],
      ...points,
      points.last * 2 - points[points.length - 2],
    ];

    // Centripetal Catmull-Rom (alpha = 0.5) to cubic Bezier conversion
    for (int i = 1; i < extPoints.length - 2; i++) {
      final p0 = extPoints[i - 1];
      final p1 = extPoints[i];
      final p2 = extPoints[i + 1];
      final p3 = extPoints[i + 2];

      final d1 = math.pow((p1 - p0).distanceSquared, 0.25).toDouble();
      final d2 = math.pow((p2 - p1).distanceSquared, 0.25).toDouble();
      final d3 = math.pow((p3 - p2).distanceSquared, 0.25).toDouble();

      final eps = 1e-4;
      final safeD1 = d1 > eps ? d1 : eps;
      final safeD2 = d2 > eps ? d2 : eps;
      final safeD3 = d3 > eps ? d3 : eps;

      // Closed-form centripetal Bezier control points
      final c1 = p1 +
          (p2 - p0) * (safeD2 / (3 * (safeD1 + safeD2))) +
          (p2 - p1) * (safeD1 / (3 * (safeD1 + safeD2)));
      final c2 = p2 -
          (p3 - p1) * (safeD2 / (3 * (safeD3 + safeD2))) +
          (p2 - p1) * (safeD3 / (3 * (safeD3 + safeD2)));

      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    return path;
  }

  void _paintBandNodes(Canvas canvas, List<Offset> points, double midY) {
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final haloPaint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isSelected = selectedBandIndex == i;
      final hasGain = gains[i].abs() > 0.05;

      if (isSelected) {
        canvas.drawCircle(pt, 9.0, haloPaint);
        canvas.drawCircle(pt, 4.5, dotPaint);
      } else if (hasGain) {
        canvas.drawCircle(pt, 3.2, dotPaint);
      } else {
        // Flat node on 0 dB line
        final zeroPaint = Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 2.0, zeroPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CatmullRomEqPainter oldDelegate) {
    return oldDelegate.gains != gains ||
        oldDelegate.color != color ||
        oldDelegate.spectrumData != spectrumData ||
        oldDelegate.frequencies != frequencies ||
        oldDelegate.maxGain != maxGain ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.selectedBandIndex != selectedBandIndex;
  }
}
