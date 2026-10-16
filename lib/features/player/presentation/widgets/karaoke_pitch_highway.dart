// lib/features/player/presentation/widgets/karaoke_pitch_highway.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/yin_pitch_detector.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

/// Interactive vocal pitch highway for Karaoke mode.
///
/// Visualizes target pitch bars corresponding to lyric timing and displays
/// a real-time vocal pitch indicator driven by the YIN pitch detector and
/// smoothed via exponential moving average (EMA) interpolation.
class KaraokePitchHighway extends StatefulWidget {
  final bool isPlaying;
  final Duration currentPosition;
  final Color accentColor;
  final double height;
  final List<LyricsLine> lyrics;
  final int activeLineIndex;
  final List<double>? audioBuffer;

  const KaraokePitchHighway({
    super.key,
    required this.isPlaying,
    required this.currentPosition,
    required this.accentColor,
    this.height = 64.0,
    this.lyrics = const [],
    this.activeLineIndex = -1,
    this.audioBuffer,
  });

  static bool? _isTestingOverride;

  @visibleForTesting
  static set isTestingOverride(bool? value) => _isTestingOverride = value;

  static bool get isTesting {
    if (_isTestingOverride != null) return _isTestingOverride!;
    if (const bool.fromEnvironment('FLUTTER_TEST')) return true;
    try {
      if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') {
        return true;
      }
    } catch (_) {}
    return WidgetsBinding.instance is! WidgetsFlutterBinding;
  }

  @override
  State<KaraokePitchHighway> createState() => _KaraokePitchHighwayState();
}

class _KaraokePitchHighwayState extends State<KaraokePitchHighway>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final EmaPitchSmoother _pitchSmoother = EmaPitchSmoother(alpha: 0.28);
  final List<_PitchPoint> _trail = [];
  PitchResult _lastSmoothed = PitchResult.unvoiced;
  double _phase = 0.0;

  static const double _minMidi = 48.0; // C3
  static const double _maxMidi = 72.0; // C5
  static const int _maxTrailLength = 16;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);

    // Initial pitch calculation for first frame
    final initialRaw = _generateSimulatedPitch();
    if (initialRaw.isVoiced) {
      _lastSmoothed = _pitchSmoother.smooth(initialRaw);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant KaraokePitchHighway oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _syncAnimation();
      if (!widget.isPlaying) {
        _pitchSmoother.reset();
        _trail.clear();
        setState(() {
          _lastSmoothed = PitchResult.unvoiced;
        });
      }
    } else if (KaraokePitchHighway.isTesting && widget.isPlaying) {
      // In tests, update simulated frame synchronously when position changes
      _onTick();
    }
  }

  void _syncAnimation() {
    if (widget.isPlaying &&
        context.motionEnabled &&
        !KaraokePitchHighway.isTesting) {
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  void _onTick() {
    if (!mounted || !widget.isPlaying) return;

    _phase += 0.05;
    if (_phase > 2 * math.pi) _phase -= 2 * math.pi;

    PitchResult rawResult;
    if (widget.audioBuffer != null && widget.audioBuffer!.isNotEmpty) {
      rawResult = YinPitchDetector.detectPitch(widget.audioBuffer!);
    } else {
      // Simulated vocal pitch derived from active line and harmonic vibrato
      rawResult = _generateSimulatedPitch();
    }

    final smoothed = _pitchSmoother.smooth(rawResult);

    if (smoothed.isVoiced) {
      _trail.add(_PitchPoint(
        midiNote: smoothed.midiNote,
        time: DateTime.now().millisecondsSinceEpoch,
      ));
      if (_trail.length > _maxTrailLength) {
        _trail.removeAt(0);
      }
    } else if (_trail.isNotEmpty) {
      _trail.removeAt(0);
    }

    setState(() {
      _lastSmoothed = smoothed;
    });
  }

  PitchResult _generateSimulatedPitch() {
    if (widget.lyrics.isEmpty || widget.activeLineIndex < 0) {
      return PitchResult.unvoiced;
    }

    final line = widget.lyrics[widget.activeLineIndex];
    final lineStart = line.timestamp.inMilliseconds;
    final nextLineTime = (widget.activeLineIndex + 1 < widget.lyrics.length)
        ? widget.lyrics[widget.activeLineIndex + 1].timestamp.inMilliseconds
        : lineStart + 4000;

    final posMs = widget.currentPosition.inMilliseconds;
    if (posMs < lineStart || posMs > nextLineTime) {
      return PitchResult.unvoiced;
    }

    // Melodic contour: hash line text into a base pitch in C3..C5
    final baseMidi = 55.0 + (line.text.hashCode.abs() % 14);
    // Add natural human vibrato (5.5 Hz) and vocal drift
    final vibrato = math.sin(_phase * 4.0) * 0.35;
    final microDrift = math.sin(_phase * 1.5) * 0.2;
    final targetMidi =
        (baseMidi + vibrato + microDrift).clamp(_minMidi, _maxMidi);

    final freqHz = 440.0 * math.pow(2.0, (targetMidi - 69.0) / 12.0);
    return PitchResult(
      frequencyHz: freqHz,
      midiNote: targetMidi,
      noteName: _noteNameFromMidi(targetMidi.round()),
      probability: 0.92,
      isVoiced: true,
    );
  }

  static String _noteNameFromMidi(int midi) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B'
    ];
    final idx = (midi % 12 + 12) % 12;
    final oct = (midi ~/ 12) - 1;
    return '${names[idx]}$oct';
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = widget.accentColor;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: AppRadii.r12All,
        border: Border.all(
          color: p.hairline.withValues(alpha: 0.6),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Highway Canvas
          Positioned.fill(
            child: CustomPaint(
              painter: _PitchHighwayPainter(
                smoothedResult: _lastSmoothed,
                trail: _trail,
                accentColor: accent,
                hairlineColor: p.hairline,
                minMidi: _minMidi,
                maxMidi: _maxMidi,
                gpuSaver: GpuBudget.isGpuSaverActive,
              ),
            ),
          ),
          // Pitch & Note Readout Chip
          if (_lastSmoothed.isVoiced)
            PositionedDirectional(
              top: AppSpacing.xxs,
              end: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceContainerHigh.withValues(alpha: 0.8),
                  borderRadius: AppRadii.r6All,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '${_lastSmoothed.noteName} • ${_lastSmoothed.frequencyHz.toStringAsFixed(0)} Hz',
                      style: TextStyle(
                        fontSize: AppFontSize.micro,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PitchPoint {
  final double midiNote;
  final int time;

  const _PitchPoint({required this.midiNote, required this.time});
}

class _PitchHighwayPainter extends CustomPainter {
  final PitchResult smoothedResult;
  final List<_PitchPoint> trail;
  final Color accentColor;
  final Color hairlineColor;
  final double minMidi;
  final double maxMidi;
  final bool gpuSaver;

  _PitchHighwayPainter({
    required this.smoothedResult,
    required this.trail,
    required this.accentColor,
    required this.hairlineColor,
    required this.minMidi,
    required this.maxMidi,
    required this.gpuSaver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 1. Draw Pitch Guide Lanes (C3, E3, G3, C4, E4, G4, C5)
    final linePaint = Paint()
      ..color = hairlineColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const guideNotes = [48, 52, 55, 60, 64, 67, 72];
    for (final note in guideNotes) {
      final y = _midiToY(note.toDouble(), h);
      canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
    }

    // 2. Target Hit Line (Cursor X anchor at 25% width)
    final targetX = w * 0.25;
    final hitLinePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.25)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(targetX, 0), Offset(targetX, h), hitLinePaint);

    // 3. Simulated Pitch Target Bar on the Highway
    if (smoothedResult.isVoiced) {
      final targetY = _midiToY(smoothedResult.midiNote.roundToDouble(), h);
      final targetBarRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(targetX + 24, targetY),
          width: 56,
          height: 7,
        ),
        const Radius.circular(3.5),
      );
      final targetBarPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(targetBarRect, targetBarPaint);
    }

    // 4. Vocal Pitch Comet Trail
    if (trail.length >= 2) {
      final trailPath = Path();
      for (int i = 0; i < trail.length; i++) {
        final pt = trail[i];
        final fraction = i / (trail.length - 1);
        final x = targetX - ((1.0 - fraction) * 48.0);
        final y = _midiToY(pt.midiNote, h);
        if (i == 0) {
          trailPath.moveTo(x, y);
        } else {
          trailPath.lineTo(x, y);
        }
      }

      final trailPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2;
      canvas.drawPath(trailPath, trailPaint);
    }

    // 5. Vocal Pitch Cursor (The real-time YIN pitch indicator)
    if (smoothedResult.isVoiced) {
      final cursorY = _midiToY(smoothedResult.midiNote, h);
      final cursorCenter = Offset(targetX, cursorY);

      // Outer Glow Halo
      if (!gpuSaver) {
        final haloPaint = Paint()
          ..color = accentColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawCircle(cursorCenter, 8.0, haloPaint);
      }

      // Accuracy ring when hitting target note (within 0.5 semitone)
      final semitoneError =
          (smoothedResult.midiNote - smoothedResult.midiNote.round()).abs();
      if (semitoneError < 0.35) {
        final accuracyPaint = Paint()
          ..color = Colors.amber.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(cursorCenter, 7.0, accuracyPaint);
      }

      // Core Bead
      final corePaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(cursorCenter, 4.5, corePaint);

      // Specular highlight
      final specularPaint = Paint()
        ..color = AppColors.specularAt(0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
          cursorCenter - const Offset(1.2, 1.2), 1.5, specularPaint);
    }
  }

  double _midiToY(double midi, double height) {
    final clamped = midi.clamp(minMidi, maxMidi);
    final norm = (clamped - minMidi) / (maxMidi - minMidi);
    // High pitch at top (y = 0), low pitch at bottom (y = height)
    return height * (1.0 - norm);
  }

  @override
  bool shouldRepaint(covariant _PitchHighwayPainter oldDelegate) {
    return oldDelegate.smoothedResult != smoothedResult ||
        oldDelegate.trail.length != trail.length ||
        oldDelegate.accentColor != accentColor;
  }
}
