// lib/features/player/presentation/widgets/eq_curve_visualizer.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/headphone_target_curve.dart';

import '../../../../core/utils/pulsr_haptics.dart';

class _ListDoubleTween extends Tween<List<double>> {
  _ListDoubleTween({super.begin, super.end});

  @override
  List<double> lerp(double t) {
    final b = begin ?? [];
    final e = end ?? [];
    if (b.isEmpty) return e;
    if (e.isEmpty) return b;
    final len = math.max(b.length, e.length);
    return List<double>.generate(len, (i) {
      final startVal = i < b.length ? b[i] : 0.0;
      final endVal = i < e.length ? e[i] : 0.0;
      return ui.lerpDouble(startVal, endVal, t) ?? endVal;
    });
  }
}

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

  /// Optional reference target drawn as a dashed line behind the correction.
  /// When null the chart plots the correction alone.
  final HeadphoneTargetCurve? targetCurve;

  /// Whether the compact corner selector for [HeadphoneTargetCurve.all] is
  /// shown. It is skipped automatically on charts too short to host it
  /// without covering the 0 dB line.
  final bool showTargetCurveSelector;

  /// Notified after the corner selector changes the drawn target curve.
  final ValueChanged<HeadphoneTargetCurve?>? onTargetCurveChanged;

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
    this.targetCurve,
    this.showTargetCurveSelector = true,
    this.onTargetCurveChanged,
  });

  @override
  State<EqCurveVisualizer> createState() => _EqCurveVisualizerState();
}

class _EqCurveVisualizerState extends State<EqCurveVisualizer> {
  int? _activeDraggingBand;
  List<double>? _prevGains;
  HeadphoneTargetCurve? _selectedTargetCurve;

  @override
  void initState() {
    super.initState();
    _selectedTargetCurve = widget.targetCurve;
  }

  @override
  void didUpdateWidget(EqCurveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.gains, widget.gains)) {
      _prevGains = oldWidget.gains;
    }
    if (widget.targetCurve != oldWidget.targetCurve) {
      _selectedTargetCurve = widget.targetCurve;
    }
  }

  String _buildSemanticValue(BuildContext context) {
    final parts = <String>[
      '${widget.gains.length} ${context.l10n.bandsLabel}',
    ];
    if (widget.gains.isNotEmpty) {
      var minDb = widget.gains.first;
      var maxDb = widget.gains.first;
      for (final g in widget.gains) {
        if (g < minDb) minDb = g;
        if (g > maxDb) maxDb = g;
      }
      if (minDb.abs() < 0.05 && maxDb.abs() < 0.05) {
        parts.add('0.0 dB');
      } else {
        final minStr = '${minDb > 0 ? '+' : ''}${minDb.toStringAsFixed(1)}';
        final maxStr = '${maxDb > 0 ? '+' : ''}${maxDb.toStringAsFixed(1)}';
        parts.add('$minStr to $maxStr dB');
      }
    }
    final activeIdx = _activeDraggingBand ?? widget.selectedBandIndex;
    if (activeIdx != null && activeIdx >= 0 && activeIdx < widget.gains.length) {
      final db = widget.gains[activeIdx];
      final dbStr = '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
      parts.add('${context.l10n.eqBandLabel(activeIdx + 1)}: $dbStr');
    }
    if (_selectedTargetCurve != null) {
      parts.add('${context.l10n.autoeqTargetCurve}: ${_selectedTargetCurve!.name}');
    }
    return parts.join(', ');
  }

  String? _buildSemanticHint(BuildContext context, bool isInteractive) {
    if (!isInteractive) return null;
    return '${context.l10n.featureInfoEqualizerSubtitle}. '
        '${context.l10n.eqBandLabel(1)}–${widget.gains.length}';
  }

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onGainChanged != null;
    final shouldAnimate =
        _activeDraggingBand == null && PulsrMotion.shouldAnimate(context);
    final surfacePalette = context.playerSurfacePalette;
    final curveDuration =
        shouldAnimate ? context.motionMs(260) : Duration.zero;

    Widget visualizer = RepaintBoundary(
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<List<double>>(
          tween: _ListDoubleTween(
            begin: _prevGains ?? widget.gains,
            end: widget.gains,
          ),
          duration: curveDuration,
          curve: PulsrMotion.resolveCurve(context, PulsrMotion.enter),
          onEnd: () {
            _prevGains = widget.gains;
          },
          builder: (context, animatedGains, _) => CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _CatmullRomEqPainter(
              gains: animatedGains,
              color: widget.activeColor,
              specularColor: surfacePalette.highContrastInk,
              spectrumData: widget.spectrumData,
              frequencies: widget.frequencies,
              targetCurve: _selectedTargetCurve,
              maxGain: widget.maxGain,
              showGrid: widget.showGrid,
              showLabels: widget.showLabels && widget.height >= 70,
              selectedBandIndex:
                  _activeDraggingBand ?? widget.selectedBandIndex,
            ),
          ),
        ),
      ),
    );

    if (isInteractive && widget.gains.isNotEmpty) {
      visualizer = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) => _handleDoubleTap(details.localPosition),
        onTapUp: (details) {
          _handlePanStart(details.localPosition);
          _handlePanEnd();
        },
        onPanStart: (details) => _handlePanStart(details.localPosition),
        onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
        onPanEnd: (_) => _handlePanEnd(),
        onPanCancel: () => _handlePanEnd(),
        child: visualizer,
      );
    }

    visualizer = Semantics(
      container: true,
      label: context.l10n.equalizerResponseCurve,
      value: _buildSemanticValue(context),
      hint: _buildSemanticHint(context, isInteractive),
      liveRegion: _activeDraggingBand != null,
      child: visualizer,
    );

    // Target-curve selector: overlaid on the chart rather than stacked above it
    // because the host layouts give this widget a fixed height (52–72 px), and
    // kept outside the GestureDetector so its taps cannot be read as a band
    // drag or delayed by the double-tap recogniser.
    if (widget.showTargetCurveSelector && widget.height >= 48) {
      visualizer = Stack(
        children: [
          visualizer,
          PositionedDirectional(
            top: 0,
            end: 2,
            child: _TargetCurvePicker(
              selected: _selectedTargetCurve,
              color: widget.activeColor,
              maxHeight: widget.height,
              onSelected: _handleTargetCurveSelected,
            ),
          ),
        ],
      );
    }

    return visualizer;
  }

  void _handleTargetCurveSelected(HeadphoneTargetCurve? curve) {
    setState(() => _selectedTargetCurve = curve);
    PulsrHaptics.selectionClick();
    widget.onTargetCurveChanged?.call(curve);
  }

  void _handleDoubleTap(Offset localPos) {
    if (widget.gains.isEmpty) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final stepX = widget.gains.length > 1
        ? size.width / (widget.gains.length - 1)
        : size.width;

    final hasFreqs = widget.frequencies != null &&
        widget.frequencies!.length == widget.gains.length &&
        widget.frequencies!.length > 1;
    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);
    final logSpan = maxLog - minLog;

    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < widget.gains.length; i++) {
      double bandX;
      if (hasFreqs) {
        final f = widget.frequencies![i].clamp(20.0, 20000.0);
        bandX = ((math.log(f) - minLog) / logSpan) * size.width;
      } else {
        bandX = i * stepX;
      }
      final dist = (localPos.dx - bandX).abs();
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    final hitTolerance = math.max(stepX / 2, 32.0);
    if (minDistance <= hitTolerance) {
      widget.onBandSelected?.call(closestIndex);
      PulsrHaptics.mediumImpact();
      widget.onGainChanged?.call(closestIndex, 0.0);
    }
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
    final hasFreqs = widget.frequencies != null &&
        widget.frequencies!.length == widget.gains.length &&
        widget.frequencies!.length > 1;
    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);
    final logSpan = maxLog - minLog;

    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < widget.gains.length; i++) {
      double bandX;
      if (hasFreqs) {
        final f = widget.frequencies![i].clamp(20.0, 20000.0);
        bandX = ((math.log(f) - minLog) / logSpan) * size.width;
      } else {
        bandX = i * stepX;
      }
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
        PulsrHaptics.selectionClick();
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
    final roundedGain = (clampedGain * 10).roundToDouble() / 10;
    widget.onGainChanged?.call(bandIndex, roundedGain);
  }

  void _handlePanEnd() {
    if (_activeDraggingBand != null) {
      setState(() => _activeDraggingBand = null);
    }
  }
}

/// Compact corner control that switches the dashed reference target between
/// [HeadphoneTargetCurve.all] and none.
class _TargetCurvePicker extends StatelessWidget {
  const _TargetCurvePicker({
    required this.selected,
    required this.color,
    required this.maxHeight,
    required this.onSelected,
  });

  final HeadphoneTargetCurve? selected;
  final Color color;
  final double maxHeight;
  final ValueChanged<HeadphoneTargetCurve?> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected?.name ?? context.l10n.autoeqTargetCurve;
    final targetHeight = math.min(AppSpacing.minTouchTarget, maxHeight);
    return Semantics(
      button: true,
      label: context.l10n.autoeqTargetCurve,
      value: selected?.name ?? context.l10n.autoeqTargetCurveNone,
      child: PopupMenuButton<HeadphoneTargetCurve?>(
        tooltip: context.l10n.autoeqTargetCurve,
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          CheckedPopupMenuItem<HeadphoneTargetCurve?>(
            value: null,
            checked: selected == null,
            child: Text(context.l10n.autoeqTargetCurveNone),
          ),
          for (final curve in HeadphoneTargetCurve.all)
            CheckedPopupMenuItem<HeadphoneTargetCurve?>(
              value: curve,
              checked: selected == curve,
              child: Text(curve.name),
            ),
        ],
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: targetHeight,
          ),
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 2, 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: AppRadii.r8All,
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.straighten_rounded,
                      size: 11, color: color.withValues(alpha: 0.75)),
                  const SizedBox(width: 3),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 104),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.85),
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded,
                      size: 14, color: color.withValues(alpha: 0.75)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatmullRomEqPainter extends CustomPainter {
  static final Path _curvePath = Path();
  static final Path _fillPath = Path();

  static final Paint _fillPaint = Paint();
  static final Paint _glowPaint = Paint()
    ..strokeWidth = 3.6
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
  static final Paint _strokePaint = Paint()
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final Paint _specPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _gridPaint = Paint()..strokeWidth = 1.0;
  static final Paint _centerGridPaint = Paint()..strokeWidth = 1.2;
  static final Paint _targetPaint = Paint()
    ..strokeWidth = 1.4
    ..style = PaintingStyle.stroke;
  static final Paint _dotPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _haloPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _cursorPaint = Paint()
    ..strokeWidth = 1.2
    ..style = PaintingStyle.stroke;
  static final Paint _outerGlowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
  static final Paint _specularPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _zeroPaint = Paint()..style = PaintingStyle.fill;

  static final Map<String, TextPainter> _cachedDbTextPainters = {};
  static Color? _lastDbColor;
  static final Map<String, TextPainter> _cachedFreqTextPainters = {};
  static Color? _lastFreqColor;

  static Shader? _cachedFillShader;
  static int? _lastFillShaderKey;

  static List<Offset>? _cachedTargetPoints;
  static int? _lastTargetKey;

  final List<double> gains;
  final Color color;
  final Color specularColor;
  final List<double>? spectrumData;
  final List<double>? frequencies;
  final HeadphoneTargetCurve? targetCurve;
  final double maxGain;
  final bool showGrid;
  final bool showLabels;
  final int? selectedBandIndex;

  _CatmullRomEqPainter({
    required this.gains,
    required this.color,
    required this.specularColor,
    this.spectrumData,
    this.frequencies,
    this.targetCurve,
    required this.maxGain,
    required this.showGrid,
    required this.showLabels,
    this.selectedBandIndex,
  });

  static TextPainter _getDbTextPainter(String text, Color color) {
    if (_lastDbColor != color) {
      _cachedDbTextPainters.clear();
      _lastDbColor = color;
    }
    return _cachedDbTextPainters.putIfAbsent(
      text,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color.withValues(alpha: 0.38),
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  static TextPainter _getFreqTextPainter(String text, Color color) {
    if (_lastFreqColor != color) {
      _cachedFreqTextPainters.clear();
      _lastFreqColor = color;
    }
    return _cachedFreqTextPainters.putIfAbsent(
      text,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color.withValues(alpha: 0.28),
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

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

    // 2b. Dashed reference target, kept behind the correction curve so the EQ
    // response it is compared against stays the dominant stroke.
    final target = targetCurve;
    if (target != null && !target.isEmpty) {
      _paintTargetCurve(canvas, size, midY, verticalScale, target);
    }

    // 3. Compute Control Points (Logarithmic frequency spacing when available)
    final points = <Offset>[];
    final hasFreqs = frequencies != null &&
        frequencies!.length == gains.length &&
        frequencies!.length > 1;
    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);
    final logSpan = maxLog - minLog;

    for (int i = 0; i < gains.length; i++) {
      double x;
      if (hasFreqs) {
        final f = frequencies![i].clamp(20.0, 20000.0);
        x = ((math.log(f) - minLog) / logSpan) * size.width;
      } else {
        x = i * stepX;
      }
      final clampedGain = gains[i].clamp(-maxGain, maxGain);
      final y = midY - (clampedGain / maxGain) * verticalScale;
      points.add(Offset(x, y));
    }

    // 4. Construct Centripetal Catmull-Rom Spline Path
    final curvePath = _buildCentripetalCatmullRomSpline(points);

    // 5. Fill Area under Curve (Gradient towards 0 dB line)
    final fillPath = _fillPath
      ..reset()
      ..addPath(curvePath, Offset.zero)
      ..lineTo(points.last.dx, midY)
      ..lineTo(points.first.dx, midY)
      ..close();

    final int fillKey = Object.hash(color, size.width, size.height);
    if (_lastFillShaderKey != fillKey || _cachedFillShader == null) {
      _lastFillShaderKey = fillKey;
      _cachedFillShader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    final fillPaint = _fillPaint..shader = _cachedFillShader;
    canvas.drawPath(fillPath, fillPaint);

    // 6. Draw Curve Glow & Stroke
    final glowPaint = _glowPaint..color = color.withValues(alpha: 0.45);
    canvas.drawPath(curvePath, glowPaint);

    final strokePaint = _strokePaint..color = color;
    canvas.drawPath(curvePath, strokePaint);

    // 7. Draw Band Control Nodes & Selection Halos
    _paintBandNodes(canvas, points, midY, size);
  }

  void _paintSpectrum(Canvas canvas, Size size) {
    final specPaint = _specPaint..color = color.withValues(alpha: 0.14);

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
    final gridPaint = _gridPaint..color = color.withValues(alpha: 0.08);

    final centerPaint = _centerGridPaint..color = color.withValues(alpha: 0.22);

    // 0 dB reference line
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), centerPaint);

    // Secondary gridlines at fractions (e.g., +12, +6, -6, -12 dB)
    final gridLevels = [0.8, 0.4, -0.4, -0.8];
    for (final level in gridLevels) {
      final y = midY - (level * verticalScale);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (size.height >= 48) {
      final tpPlus = _getDbTextPainter('+${maxGain.toInt()} dB', color);
      tpPlus.paint(canvas, Offset(6, midY - verticalScale - 1));

      final tpZero = _getDbTextPainter('0 dB', color);
      tpZero.paint(canvas, Offset(6, midY - tpZero.height / 2));

      final tpMinus = _getDbTextPainter('-${maxGain.toInt()} dB', color);
      tpMinus.paint(canvas, Offset(6, midY + verticalScale - tpMinus.height));

      // Paint frequency markers along bottom when showLabels is true
      if (showLabels) {
        final fMarkers = [100.0, 1000.0, 10000.0];
        final fLabels = ['100', '1k', '10k'];
        for (int m = 0; m < fMarkers.length; m++) {
          final f = fMarkers[m];
          final x = ((math.log(f) - math.log(20.0)) /
                  (math.log(20000.0) - math.log(20.0))) *
              size.width;
          final tpMarker = _getFreqTextPainter(fLabels[m], color);
          tpMarker.paint(
              canvas,
              Offset((x - tpMarker.width / 2).clamp(24.0, size.width - 24.0),
                  size.height - tpMarker.height - 1));
        }
      }
    }
  }

  /// Draws [curve] as a dashed reference across the 20 Hz – 20 kHz log axis.
  /// Levels outside the chart are clipped rather than clamped, so the line
  /// leaves the plot at the true crossing point instead of hugging an edge
  /// (Harman targets fall well below −15 dB at 20 kHz).
  void _paintTargetCurve(Canvas canvas, Size size, double midY,
      double verticalScale, HeadphoneTargetCurve curve) {
    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);
    final span = maxLog - minLog;
    const samples = 160;

    final int targetKey =
        Object.hash(curve, maxGain, midY, verticalScale, size.width);
    final List<Offset> points;
    if (_lastTargetKey == targetKey && _cachedTargetPoints != null) {
      points = _cachedTargetPoints!;
    } else {
      points = <Offset>[];
      for (var i = 0; i <= samples; i++) {
        final t = i / samples;
        final hz = math.exp(minLog + span * t);
        final db = curve.interpolateDbAt(hz);
        final y = midY - (db / maxGain) * verticalScale;
        points.add(Offset(t * size.width, y));
      }
      _lastTargetKey = targetKey;
      _cachedTargetPoints = points;
    }

    final paint = _targetPaint..color = color.withValues(alpha: 0.55);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintDashedPolyline(canvas, points, paint,
        dashLength: 5.0, gapLength: 4.0);
    canvas.restore();
  }

  void _paintDashedPolyline(Canvas canvas, List<Offset> points, Paint paint,
      {required double dashLength, required double gapLength}) {
    var drawing = true;
    var remaining = dashLength;
    for (var i = 0; i < points.length - 1; i++) {
      var start = points[i];
      final end = points[i + 1];
      var segmentLength = (end - start).distance;
      if (segmentLength <= 0) continue;
      while (segmentLength > 0) {
        final step = math.min(remaining, segmentLength);
        final next = start + (end - start) * (step / segmentLength);
        if (drawing) canvas.drawLine(start, next, paint);
        start = next;
        segmentLength -= step;
        remaining -= step;
        if (remaining <= 1e-9) {
          drawing = !drawing;
          remaining = drawing ? dashLength : gapLength;
        }
      }
    }
  }

  Path _buildCentripetalCatmullRomSpline(List<Offset> points) {
    final path = _curvePath..reset();
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

  void _paintBandNodes(
      Canvas canvas, List<Offset> points, double midY, Size size) {
    final dotPaint = _dotPaint..color = color;

    final haloPaint = _haloPaint..color = color.withValues(alpha: 0.28);

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isSelected = selectedBandIndex == i;
      final hasGain = gains[i].abs() > 0.05;

      if (isSelected) {
        // Vertical frequency cursor line
        final cursorPaint = _cursorPaint..color = color.withValues(alpha: 0.40);
        canvas.drawLine(
          Offset(pt.dx, 0),
          Offset(pt.dx, size.height),
          cursorPaint,
        );

        // Highlighted node outer soft glow
        final outerGlowPaint = _outerGlowPaint
          ..color = color.withValues(alpha: 0.22);
        canvas.drawCircle(pt, 14.0, outerGlowPaint);

        canvas.drawCircle(pt, 9.0, haloPaint);
        canvas.drawCircle(pt, 4.5, dotPaint);

        // Specular center dot
        final specularPaint = _specularPaint
          ..color = specularColor.withValues(alpha: 0.90);
        canvas.drawCircle(pt, 1.8, specularPaint);
      } else if (hasGain) {
        canvas.drawCircle(pt, 3.2, dotPaint);
      } else {
        // Flat node on 0 dB line
        final zeroPaint = _zeroPaint..color = color.withValues(alpha: 0.45);
        canvas.drawCircle(pt, 2.0, zeroPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CatmullRomEqPainter oldDelegate) {
    return !listEquals(oldDelegate.gains, gains) ||
        oldDelegate.color != color ||
        oldDelegate.specularColor != specularColor ||
        !listEquals(oldDelegate.spectrumData, spectrumData) ||
        !listEquals(oldDelegate.frequencies, frequencies) ||
        oldDelegate.targetCurve != targetCurve ||
        oldDelegate.maxGain != maxGain ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.selectedBandIndex != selectedBandIndex;
  }
}
