// lib/features/player/presentation/widgets/mini_player/mini_player_progress_bar.dart
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../../core/motion/pulsr_motion.dart';
import '../../../../../core/performance/gpu_budget.dart';
import '../../../../../core/theme/aura_theme.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/l10n_extensions.dart';
import '../../../../../core/utils/pulsr_haptics.dart';
import '../../../cubit/player_cubit.dart';
import '../../../cubit/player_state.dart';

/// Scrubbable wavy progress bar rendered along the bottom of the compact mini
/// player. Scopes position rebuilds to its own [BlocSelector] so the parent
/// mini player does not rebuild on per-second ticks.
class MiniPlayerProgressBar extends StatelessWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final bool isPlaying;
  final bool isBuffering;
  final void Function(Duration) onSeek;

  const MiniPlayerProgressBar({
    super.key,
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.isPlaying,
    this.isBuffering = false,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return _MiniPlayerProgressBar(
      duration: duration,
      activeAccent: activeAccent,
      hairlineColor: hairlineColor,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      onSeek: onSeek,
    );
  }
}

class _MiniPlayerProgressBar extends StatefulWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final bool isPlaying;
  final bool isBuffering;
  final void Function(Duration) onSeek;

  const _MiniPlayerProgressBar({
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.isPlaying,
    this.isBuffering = false,
    required this.onSeek,
  });

  @override
  State<_MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends State<_MiniPlayerProgressBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  double? _dragProgress;
  // AUDIT-FIX: Monotonic stopwatch clock for optimistic seek timing
  final Stopwatch _optimisticClock = Stopwatch();
  Duration? _optimisticSeekPosition;
  Duration? _optimisticSeekTime;
  bool _isAppActive = true;
  bool? _lastAllowMotion;
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _isAppActive = false;
      _waveController.stop();
    } else {
      _isAppActive = true;
      _syncWave();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _waveController.duration = context.motionMs(2600);
    _syncWave();
  }

  bool _allowMotion(BuildContext context) =>
      PulsrMotion.shouldAnimate(context) && context.motionEnabled;

  void _syncWave({bool? allowMotionOverride}) {
    final isTest = const bool.fromEnvironment('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    final allowMotion = allowMotionOverride ?? _allowMotion(context);
    final shouldAnimate = _isAppActive &&
        widget.isPlaying &&
        !widget.isBuffering &&
        allowMotion &&
        !isTest;
    if (shouldAnimate) {
      if (!_waveController.isAnimating) _waveController.repeat();
    } else if (_waveController.isAnimating) {
      _waveController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.isBuffering != widget.isBuffering) {
      _syncWave();
    }
    if (_optimisticSeekPosition != null &&
        _optimisticClock.elapsed.inMilliseconds >= 350) {
      _clearOptimisticSeek();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waveController.dispose();
    _optimisticClock.stop();
    super.dispose();
  }

  void _recordSeek(Duration target) {
    _optimisticSeekPosition = target;
    _optimisticClock.reset();
    _optimisticClock.start();
    _optimisticSeekTime = _optimisticClock.elapsed;
    widget.onSeek(target);
  }

  void _clearOptimisticSeek() {
    _optimisticSeekPosition = null;
    _optimisticSeekTime = null;
    _optimisticClock.stop();
  }

  bool _shouldHoldOptimisticSeek(Duration enginePosition) {
    final target = _optimisticSeekPosition;
    if (target == null || _optimisticSeekTime == null) return false;
    final elapsed = _optimisticClock.elapsed;
    final diff = (enginePosition - target).abs();
    return elapsed.inMilliseconds < 350 && diff.inMilliseconds > 400;
  }

  // AUDIT-FIX (P3-28): Keep build pure — never mutate _optimistic* fields inside
  // _resolveEffectivePosition; clear via BlocListener or didUpdateWidget instead.
  Duration _resolveEffectivePosition(Duration enginePosition) =>
      _shouldHoldOptimisticSeek(enginePosition)
          ? _optimisticSeekPosition!
          : enginePosition;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;
    final allowMotion = _allowMotion(context);
    if (_lastAllowMotion != allowMotion) {
      _lastAllowMotion = allowMotion;
      if (!allowMotion && _waveController.isAnimating) {
        _waveController.stop();
      } else if (allowMotion) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncWave(allowMotionOverride: allowMotion);
        });
      }
    }

    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) =>
          _optimisticSeekPosition != null &&
          (prev.position != curr.position ||
              prev.currentSong?.id != curr.currentSong?.id),
      listener: (context, state) {
        if (!_shouldHoldOptimisticSeek(state.position)) {
          _clearOptimisticSeek();
        }
      },
      child: RepaintBoundary(
        child: Directionality(
          textDirection: Directionality.of(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              return BlocSelector<PlayerCubit, PlayerState, Duration>(
                selector: (s) => s.position,
                builder: (context, rawPosition) {
                  final position = _resolveEffectivePosition(rawPosition);
                  final progress = _dragProgress ??
                      (widget.duration.inMilliseconds > 0
                          ? (position.inMilliseconds /
                                  widget.duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0);
                  final currentDuration = _dragProgress != null
                      ? Duration(
                          milliseconds:
                              (widget.duration.inMilliseconds * _dragProgress!)
                                  .round())
                      : position;
                  final valueLabel =
                      '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(widget.duration)}';

                  Duration clampDuration(Duration d) {
                    if (d < Duration.zero) return Duration.zero;
                    if (d > widget.duration) return widget.duration;
                    return d;
                  }

                  String labelFor(Duration d) =>
                      '${Formatters.formatDuration(d)} / ${Formatters.formatDuration(widget.duration)}';
                  final increasedLabel = labelFor(clampDuration(
                      currentDuration + const Duration(seconds: 10)));
                  final decreasedLabel = labelFor(clampDuration(
                      currentDuration - const Duration(seconds: 10)));

                  final isDragging = _dragProgress != null;
                  final thumbAlignX = (progress * 2 - 1).clamp(-0.94, 0.94);

                  return Semantics(
                    slider: true,
                    label: context.l10n.seekLabel,
                    value: valueLabel,
                    increasedValue: increasedLabel,
                    decreasedValue: decreasedLabel,
                    onIncrease: widget.isBuffering
                        ? null
                        : () => _recordSeek(clampDuration(
                            currentDuration + const Duration(seconds: 10))),
                    onDecrease: widget.isBuffering
                        ? null
                        : () => _recordSeek(clampDuration(
                            currentDuration - const Duration(seconds: 10))),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: widget.isBuffering
                          ? null
                          : (details) {
                              if (trackWidth > 0 &&
                                  widget.duration.inMilliseconds > 0) {
                                PulsrHaptics.selectionClick();
                                final ratio =
                                    (details.localPosition.dx / trackWidth)
                                        .clamp(0.0, 1.0);
                                setState(() => _dragProgress = null);
                                final seekMs =
                                    (widget.duration.inMilliseconds * ratio)
                                        .round();
                                _recordSeek(Duration(milliseconds: seekMs));
                              }
                            },
                      onHorizontalDragStart: widget.isBuffering
                          ? null
                          : (details) {
                              if (trackWidth > 0 &&
                                  widget.duration.inMilliseconds > 0) {
                                PulsrHaptics.selectionClick();
                                final ratio =
                                    (details.localPosition.dx / trackWidth)
                                        .clamp(0.0, 1.0);
                                setState(() => _dragProgress = ratio);
                              }
                            },
                      onHorizontalDragUpdate: widget.isBuffering
                          ? null
                          : (details) {
                              if (trackWidth > 0 &&
                                  widget.duration.inMilliseconds > 0) {
                                final ratio =
                                    (details.localPosition.dx / trackWidth)
                                        .clamp(0.0, 1.0);
                                setState(() => _dragProgress = ratio);
                              }
                            },
                      onHorizontalDragEnd: widget.isBuffering
                          ? null
                          : (_) {
                              if (_dragProgress != null &&
                                  widget.duration.inMilliseconds > 0) {
                                final seekMs = (widget.duration.inMilliseconds *
                                        _dragProgress!)
                                    .round();
                                _recordSeek(Duration(milliseconds: seekMs));
                                setState(() => _dragProgress = null);
                              }
                            },
                      onHorizontalDragCancel: widget.isBuffering
                          ? null
                          : () {
                              setState(() => _dragProgress = null);
                            },
                      // Generous hit area so the thin wavy bar is easy to grab; the
                      // wave amplitude stays small so the card never grows.
                      child: SizedBox(
                        height: AppSpacing.s24,
                        width: double.infinity,
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, _) => Stack(
                            clipBehavior: Clip.none,
                            alignment: AlignmentDirectional.centerStart,
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.s10),
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _MiniProgressWavePainter(
                                        progress: progress,
                                        phase:
                                            _waveController.value * 2 * math.pi,
                                        activeColor: widget.activeAccent,
                                        inactiveColor: widget.hairlineColor,
                                        isPlaying:
                                            widget.isPlaying && allowMotion,
                                        isDragging: isDragging,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Scrub thumb & floating time readout while dragging
                              if (isDragging) ...[
                                PositionedDirectional(
                                  top: -24,
                                  start: 12,
                                  end: 12,
                                  child: Align(
                                    alignment: Alignment(
                                        thumbAlignX.clamp(-0.85, 0.85), 0),
                                    child: IgnorePointer(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: p.surfaceContainerHigh,
                                          borderRadius: AppRadii.r8All,
                                          border: Border.all(
                                            color: widget.activeAccent
                                                .withValues(alpha: 0.45),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: surface.shadowAt(0.25),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          valueLabel,
                                          style: TextStyle(
                                            color: p.textPrimary,
                                            fontSize: AppFontSize.caption,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.s10),
                                  child: Align(
                                    alignment: Alignment(thumbAlignX, 0),
                                    child: Container(
                                      width: 11,
                                      height: 11,
                                      decoration: BoxDecoration(
                                        color: widget.activeAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: surface.specularAt(0.85),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: widget.activeAccent
                                                .withValues(alpha: 0.55),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Draws the mini-player progress as the app's signature animated wave:
/// a thin inactive remainder plus a sine-enveloped active line with a soft glow,
/// matched to [PulsrSlider] so the mini player and seek bar feel like one system.
class _MiniProgressWavePainter extends CustomPainter {
  final double progress;
  final double phase;
  final Color activeColor;
  final Color inactiveColor;
  final bool isPlaying;
  final bool isDragging;

  _MiniProgressWavePainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
    required this.isPlaying,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackHeight = isDragging ? 3.8 : 2.8;
    final endX = (progress * size.width).clamp(0.0, size.width);

    if (endX < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 3.0 : 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(endX, centerY), Offset(size.width, centerY), inactivePaint);
    }
    if (endX <= 0.5) return;

    // Sine-enveloped wave so it leaves/returns to the centerline cleanly.
    final amplitude = (isPlaying && !isDragging) ? 1.8 : 0.0;
    const wavelength = 16.0;
    const fade = 10.0;
    const step = 2.0;
    final wavePath = Path()..moveTo(0, centerY);
    for (double x = 0; x <= endX; x += step) {
      double env = 1.0;
      if (x < fade) {
        env = x / fade;
      } else if (endX - x < fade) {
        env = ((endX - x) / fade).clamp(0.0, 1.0);
      }
      final y = centerY +
          amplitude * env * math.sin((x / wavelength) * 2 * math.pi - phase);
      wavePath.lineTo(x, y);
    }
    wavePath.lineTo(endX, centerY);

    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: isDragging ? 0.32 : 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight + 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = GpuBudget.isGpuSaverActive
          ? null
          : const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(wavePath, glowPaint);

    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: [activeColor.withValues(alpha: 0.78), activeColor],
      ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(wavePath, activePaint);

    // Subtle radiant leading glow bead matching activeColor when playing.
    if (isPlaying && !isDragging && endX > 2.0 && endX <= size.width) {
      final beadCenter = Offset(endX, centerY);
      if (!GpuBudget.isGpuSaverActive) {
        final haloPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.42)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawCircle(beadCenter, 4.0, haloPaint);
      }

      final corePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(beadCenter, 2.5, corePaint);

      final specularPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(beadCenter, 1.0, specularPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniProgressWavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.isPlaying != isPlaying ||
      old.isDragging != isDragging;
}
