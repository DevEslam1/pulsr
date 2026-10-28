// lib/core/widgets/pulsr_slider.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';

/// {@category DesignSystem}
/// A premium, interactive custom-painted slider with an organic wavy track.
class PulsrSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onChangeCancel;
  final String? semanticLabel;
  final double height;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final bool isWavy;
  final bool animateWave;

  const PulsrSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangeCancel,
    this.divisions,
    this.semanticLabel,
    this.height = 32,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.isWavy = true,
    this.animateWave = false,
  });

  @override
  State<PulsrSlider> createState() => _PulsrSliderState();
}

class _PulsrSliderState extends State<PulsrSlider>
    with TickerProviderStateMixin {
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;
  late final AnimationController _waveController;
  bool _isDragging = false;
  int? _lastDivisionTick;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  bool get _isTesting =>
      const bool.fromEnvironment('FLUTTER_TEST') ||
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expandController.duration = context.motionMs(180);
    _waveController.duration = context.motionMs(3200);
    _syncWave();
  }

  void _syncWave() {
    final shouldAnimate = context.motionEnabled &&
        widget.isWavy &&
        widget.animateWave &&
        !_isTesting;
    if (shouldAnimate) {
      if (!_waveController.isAnimating) {
        _waveController.repeat();
      }
    } else {
      if (_waveController.isAnimating) {
        _waveController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(PulsrSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.min != oldWidget.min ||
        widget.max != oldWidget.max ||
        widget.divisions != oldWidget.divisions) {
      _lastDivisionTick = null;
    }
    _syncWave();
  }

  @override
  void dispose() {
    _expandController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  double _calculateValue(double dx, double width, TextDirection direction) {
    final effectiveDx = direction == TextDirection.rtl ? width - dx : dx;
    final ratio = (effectiveDx / width).clamp(0.0, 1.0);
    if (widget.divisions == null || widget.divisions! <= 0) {
      return (ratio * (widget.max - widget.min)) + widget.min;
    }
    final quantizedStep = (ratio * widget.divisions!).round();
    if (_isDragging && quantizedStep != _lastDivisionTick) {
      _lastDivisionTick = quantizedStep;
      HapticFeedback.selectionClick();
    }
    return (quantizedStep / widget.divisions!) * (widget.max - widget.min) +
        widget.min;
  }

  bool _tapSeekPending = false;
  double _tapSeekValue = 0.0;

  void _onDragStart(double dx, double width, TextDirection direction) {
    setState(() => _isDragging = true);
    _expandController.forward();
    HapticFeedback.lightImpact();
    final val = _calculateValue(dx, width, direction);
    widget.onChangeStart?.call(val);
    widget.onChanged(val);
  }

  void _onDragUpdate(double dx, double width, TextDirection direction) {
    _tapSeekPending = false;
    final val = _calculateValue(dx, width, direction);
    widget.onChanged(val);
  }

  void _onDragEnd(double dx, double width, TextDirection direction) {
    setState(() => _isDragging = false);
    _expandController.reverse();
    final val =
        _tapSeekPending ? _tapSeekValue : _calculateValue(dx, width, direction);
    _tapSeekPending = false;
    _lastDivisionTick = null;
    widget.onChangeEnd?.call(val);
  }

  void _onTapDown(double dx, double width, TextDirection direction) {
    _tapSeekPending = true;
    _tapSeekValue = _calculateValue(dx, width, direction);
    _onDragStart(dx, width, direction);
  }

  bool _isFocused = false;
  bool _isHovered = false;

  void _stepValue(double multiplier) {
    final range = widget.max - widget.min;
    if (range <= 0) return;
    final step = (widget.divisions != null && widget.divisions! > 0)
        ? (range / widget.divisions!)
        : (range / 20.0);
    final target =
        (widget.value + (step * multiplier)).clamp(widget.min, widget.max);
    HapticFeedback.selectionClick();
    widget.onChanged(target);
    widget.onChangeEnd?.call(target);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final direction = Directionality.of(context);
    final l10n = context.l10n;
    final range = widget.max - widget.min;
    final t = range <= 0
        ? 0.0
        : ((widget.value - widget.min) / range).clamp(0.0, 1.0);

    return FocusableActionDetector(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onShowHoverHighlight: (hovered) => setState(() => _isHovered = hovered),
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.arrowRight):
            const _SliderStepIntent(1),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _SliderStepIntent(1),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft):
            const _SliderStepIntent(-1),
        LogicalKeySet(LogicalKeyboardKey.arrowDown):
            const _SliderStepIntent(-1),
        LogicalKeySet(LogicalKeyboardKey.pageUp): const _SliderStepIntent(4),
        LogicalKeySet(LogicalKeyboardKey.pageDown): const _SliderStepIntent(-4),
      },
      actions: <Type, Action<Intent>>{
        _SliderStepIntent: CallbackAction<_SliderStepIntent>(
          onInvoke: (intent) {
            _stepValue(intent.steps.toDouble());
            return null;
          },
        ),
      },
      child: Semantics(
        label: widget.semanticLabel,
        slider: true,
        value: '${(t * 100).round()}%',
        increasedValue: l10n.increase,
        decreasedValue: l10n.decrease,
        onIncrease: () => _stepValue(1),
        onDecrease: () => _stepValue(-1),
        child: Container(
          decoration: _isFocused
              ? BoxDecoration(
                  borderRadius: AppRadii.r8All,
                  border: Border.all(
                    color:
                        (widget.activeColor ?? p.accent).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                )
              : null,
          height: max(48.0, widget.height),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _onTapDown(d.localPosition.dx, width, direction),
                onTapUp: (d) =>
                    _onDragEnd(d.localPosition.dx, width, direction),
                onTapCancel: () {
                  _tapSeekPending = false;
                  _lastDivisionTick = null;
                  setState(() => _isDragging = false);
                  _expandController.reverse();
                },
                onHorizontalDragStart: (d) {
                  _tapSeekPending = false;
                  _onDragStart(d.localPosition.dx, width, direction);
                },
                onHorizontalDragUpdate: (d) =>
                    _onDragUpdate(d.localPosition.dx, width, direction),
                onHorizontalDragEnd: (d) =>
                    _onDragEnd(d.localPosition.dx, width, direction),
                onHorizontalDragCancel: () {
                  _tapSeekPending = false;
                  _lastDivisionTick = null;
                  setState(() => _isDragging = false);
                  _expandController.reverse();
                  widget.onChangeCancel?.call();
                },
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_expandAnimation, _waveController]),
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _PulsrSliderPainter(
                          t: t,
                          divisions: widget.divisions,
                          expandFactor: _isFocused || _isHovered
                              ? max(0.35, _expandAnimation.value)
                              : _expandAnimation.value,
                          wavePhase: widget.animateWave
                              ? _waveController.value * 2 * pi
                              : 0.0,
                          isWavy: widget.isWavy,
                          inactiveColor: widget.inactiveColor ??
                              (p.isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.14),
                          activeColor: widget.activeColor ?? p.accent,
                          thumbColor: widget.thumbColor ??
                              (p.isDark ? Colors.white : p.accent),
                          glowColor: p.glow,
                          isRtl: direction == TextDirection.rtl,
                        ),
                        size: Size.infinite,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SliderStepIntent extends Intent {
  final int steps;
  const _SliderStepIntent(this.steps);
}

class _PulsrSliderPainter extends CustomPainter {
  final double t;
  final int? divisions;
  final double expandFactor;
  final double wavePhase;
  final bool isWavy;
  final Color inactiveColor;
  final Color activeColor;
  final Color thumbColor;
  final Color glowColor;
  final bool isRtl;

  _PulsrSliderPainter({
    required this.t,
    required this.divisions,
    required this.expandFactor,
    required this.wavePhase,
    required this.isWavy,
    required this.inactiveColor,
    required this.activeColor,
    required this.thumbColor,
    required this.glowColor,
    required this.isRtl,
  });

  double _smoothstep(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (isRtl) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final trackHeight = 4.2 + (3.6 * expandFactor);
    final thumbRadius = 6.8 + (3.2 * expandFactor);
    final centerY = size.height / 2;
    final thumbX = (t * size.width).clamp(0.0, size.width);

    // 1. Inactive background track (with subtle gap near thumb for modern separation)
    final inactiveStart = (thumbX + thumbRadius + 4.0).clamp(0.0, size.width);
    if (inactiveStart < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight * 0.85
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(inactiveStart, centerY),
        Offset(size.width, centerY),
        inactivePaint,
      );

      // Subtle division ticks if divisions are specified and reasonable
      if (divisions != null && divisions! > 1 && divisions! <= 24) {
        final tickPaint = Paint()
          ..color = inactiveColor.withValues(alpha: 0.45)
          ..style = PaintingStyle.fill;
        for (int i = 1; i < divisions!; i++) {
          final tickX = (i / divisions!) * size.width;
          if (tickX > inactiveStart + 4 && tickX < size.width - 4) {
            canvas.drawCircle(Offset(tickX, centerY), 1.4, tickPaint);
          }
        }
      }
    }

    // 2. Active foreground progress track (from 0 to thumb)
    if (thumbX > 0.5) {
      final activePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            activeColor.withValues(alpha: 0.80),
            activeColor,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (!isWavy || thumbX < 16.0) {
        canvas.drawLine(
            Offset(0, centerY), Offset(thumbX, centerY), activePaint);
      } else {
        final wavePath = Path()..moveTo(0, centerY);

        const wavelength = 26.0;
        final amplitude = 3.2 + (2.2 * expandFactor);
        const fadeDistance = 16.0;
        const step = 2.0;

        for (double x = 0; x <= thumbX; x += step) {
          double env = 1.0;
          if (x < fadeDistance) {
            env = _smoothstep(x / fadeDistance);
          } else if (thumbX - x < fadeDistance) {
            env = _smoothstep((thumbX - x) / fadeDistance);
          }
          final y = centerY +
              amplitude * env * sin((x / wavelength) * 2 * pi - wavePhase);
          wavePath.lineTo(x, y);
        }
        wavePath.lineTo(thumbX, centerY);

        final waveGlowPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.18 + (0.18 * expandFactor))
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackHeight + 3.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

        canvas.drawPath(wavePath, waveGlowPaint);
        canvas.drawPath(wavePath, activePaint);
      }
    }

    // 3. Ambient halo behind thumb
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.22 + (0.36 * expandFactor))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY),
        thumbRadius + 4.5 + (2.0 * expandFactor), glowPaint);

    // 4. Elevation drop shadow
    final shadowPaint = Paint()
      ..color = AppColors.scrimAt(0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawCircle(Offset(thumbX, centerY + 1.5), thumbRadius, shadowPaint);

    // 5. Solid thumb core
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);

    // 6. Crisp outer accent ring
    final ringPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, ringPaint);

    if (isRtl) canvas.restore();
  }

  @override
  bool shouldRepaint(_PulsrSliderPainter old) =>
      old.t != t ||
      old.divisions != divisions ||
      old.expandFactor != expandFactor ||
      old.wavePhase != wavePhase ||
      old.isWavy != isWavy ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.thumbColor != thumbColor ||
      old.glowColor != glowColor ||
      old.isRtl != isRtl;
}
