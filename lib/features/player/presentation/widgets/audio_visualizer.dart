// lib/features/player/presentation/widgets/audio_visualizer.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';

enum VisualizerStyle {
  off,
  bar,
  wave,
  circular,
}

class AudioVisualizer extends StatefulWidget {
  final VisualizerStyle style;
  final Color? color;
  final double width;
  final double height;
  final bool isPlaying;
  final int? audioSessionId;

  const AudioVisualizer({
    super.key,
    this.style = VisualizerStyle.bar,
    this.color,
    this.width = double.infinity,
    this.height = 120.0,
    this.isPlaying = true,
    this.audioSessionId,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _methodChannel = MethodChannel('com.pulsr.music/visualizer');
  static const EventChannel _eventChannel = EventChannel('com.pulsr.music/visualizer_stream');

  StreamSubscription? _subscription;
  late AnimationController _animController;

  static const int _numBands = 32;
  final List<double> _currentData = List.filled(_numBands, 0.0);
  final List<double> _targetData = List.filled(_numBands, 0.0);
  late final ValueNotifier<List<double>> _dataNotifier;
  DateTime _lastNativeDataTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataNotifier = ValueNotifier<List<double>>(List.from(_currentData));
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateFftFrame);

    if (widget.style != VisualizerStyle.off && widget.isPlaying) {
      _animController.repeat();
      if (Platform.isAndroid) {
        _startNativeVisualizer();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopNativeVisualizer();
      _animController.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.style != VisualizerStyle.off && widget.isPlaying) {
        if (!_animController.isAnimating) _animController.repeat();
        if (Platform.isAndroid) {
          _startNativeVisualizer();
        }
      }
    }
  }

  @override
  void didUpdateWidget(AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style != oldWidget.style) {
      if (widget.style == VisualizerStyle.off) {
        _animController.stop();
        _stopNativeVisualizer();
      } else if (widget.isPlaying) {
        if (!_animController.isAnimating) _animController.repeat();
        if (Platform.isAndroid) {
          _startNativeVisualizer();
        }
      }
    } else if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_animController.isAnimating) _animController.repeat();
        if (Platform.isAndroid) {
          _startNativeVisualizer();
        }
      } else {
        _stopNativeVisualizer();
      }
    } else if (widget.audioSessionId != oldWidget.audioSessionId &&
        widget.style != VisualizerStyle.off &&
        widget.isPlaying &&
        Platform.isAndroid) {
      // Session changed (first assignment, or a crossfade swap to the other
      // player) — rebind the native Visualizer to the new session id.
      _startNativeVisualizer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopNativeVisualizer();
    _animController.dispose();
    _dataNotifier.dispose();
    super.dispose();
  }

  static bool _hasPromptedRationale = false;

  Future<void> _startNativeVisualizer() async {
    if (widget.style == VisualizerStyle.off) return;
    try {
      if (Platform.isAndroid) {
        final status = await Permission.microphone.status;
        if (!status.isGranted) {
          if (_hasPromptedRationale) {
            // User already made a decision, seamlessly use simulation fallback
            return;
          }
          _hasPromptedRationale = true;
          if (mounted) {
            final shouldAsk = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(context.l10n.audioVisualizerPermission),
                content: Text(
                  context.l10n.audioVisualizerPermissionDesc,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(context.l10n.useSimulation),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(context.l10n.confirm),
                  ),
                ],
              ),
            );
            if (shouldAsk != true) return;
          }
          final res = await Permission.microphone.request();
          if (!res.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.visualizerSimulationNotice,
                  ),
                ),
              );
            }
            return;
          }
        }
      }
      await _subscription?.cancel();
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is List) {
            final raw = data.map((e) => (e as num).toDouble()).toList();
            if (raw.isNotEmpty) {
              _lastNativeDataTime = DateTime.now();
              // Logarithmic frequency band pooling across audible spectrum
              final rawLen = raw.length;
              for (int i = 0; i < _numBands; i++) {
                final pStart = math.pow(i / _numBands, 2.0);
                final pEnd = math.pow((i + 1) / _numBands, 2.0);
                final startIdx = (pStart * rawLen * 0.85).floor().clamp(0, rawLen - 1);
                final endIdx = (pEnd * rawLen * 0.85).ceil().clamp(startIdx + 1, rawLen);

                double bandMax = 0.0;
                double bandSum = 0.0;
                int count = 0;
                for (int j = startIdx; j < endIdx; j++) {
                  final val = raw[j];
                  if (val > bandMax) bandMax = val;
                  bandSum += val;
                  count++;
                }
                final avg = count > 0 ? bandSum / count : 0.0;
                final combined = (bandMax * 0.7 + avg * 0.3);

                // High-frequency treble gain compensation & logarithmic dynamic expansion
                final trebleGain = 1.0 + (i / _numBands) * 3.2;
                final boosted = (combined * trebleGain).clamp(0.0, 2.5);
                final scaled = (math.pow(boosted, 0.45).toDouble() * 1.1).clamp(0.18, 1.0);

                _targetData[i] = scaled;
              }
            }
          }
        },
        onError: (e, st) {
          ErrorLogger.log('Visualizer event stream error', error: e, stackTrace: st, category: 'AudioVisualizer');
        },
      );
      await _methodChannel.invokeMethod('start', {
        'audioSessionId': widget.audioSessionId ?? 0,
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to start native audio visualizer', error: e, stackTrace: st, category: 'AudioVisualizer');
    }
  }

  Future<void> _stopNativeVisualizer() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _methodChannel.invokeMethod('stop');
    } catch (e, st) {
      ErrorLogger.log('Failed to stop native audio visualizer', error: e, stackTrace: st, category: 'AudioVisualizer');
    }
  }

  void _updateFftFrame() {
    if (!mounted) return;
    final now = DateTime.now();
    final isNativeActive = now.difference(_lastNativeDataTime).inMilliseconds < 300;

    if (!widget.isPlaying) {
      // Smoothly decay to zero when paused/stopped
      bool allDecayed = true;
      for (int i = 0; i < _numBands; i++) {
        _currentData[i] *= 0.85;
        if (_currentData[i] > 0.01) allDecayed = false;
      }
      if (allDecayed) {
        _animController.stop();
      }
    } else if (isNativeActive) {
      // Interpolate target native FFT data with snappy physics
      for (int i = 0; i < _numBands; i++) {
        _currentData[i] += (_targetData[i] - _currentData[i]) * 0.45;
      }
    } else {
      // High-energy organic FFT frequencies across all bands
      final t = _animController.value * 2 * math.pi * 3;
      for (int i = 0; i < _numBands; i++) {
        final f1 = (i + 1) * 0.4;
        final f2 = (i + 2) * 0.65;
        final wave1 = math.sin(t * f1 + i * 0.45).abs();
        final wave2 = math.cos(t * f2 + i * 0.3).abs();
        final wave3 = math.sin(t * 1.8 + (i % 5) * 1.1).abs();

        final rawMag = (wave1 * 0.45 + wave2 * 0.35 + wave3 * 0.2).clamp(0.0, 1.0);
        final heightMultiplier = 0.5 + 0.5 * math.sin((i / _numBands) * math.pi);
        final simulated = (rawMag * (0.6 + heightMultiplier * 0.4) + 0.3).clamp(0.25, 1.0);

        _currentData[i] += (simulated - _currentData[i]) * 0.38;
      }
    }

    _dataNotifier.value = List.from(_currentData);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == VisualizerStyle.off) {
      return const SizedBox.shrink();
    }

    final activeColor = widget.color ?? context.palette.accent;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ValueListenableBuilder<List<double>>(
          valueListenable: _dataNotifier,
          builder: (context, data, _) {
            return CustomPaint(
              painter: switch (widget.style) {
                VisualizerStyle.bar => _BarVisualizerPainter(
                    data: data,
                    color: activeColor,
                  ),
                VisualizerStyle.wave => _WaveVisualizerPainter(
                    data: data,
                    color: activeColor,
                  ),
                VisualizerStyle.circular => _CircularVisualizerPainter(
                    data: data,
                    color: activeColor,
                  ),
                VisualizerStyle.off => null,
              },
            );
          },
        ),
      ),
    );
  }
}

// --- PAINTER 1: BAR VISUALIZER ---
class _BarVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _BarVisualizerPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final count = data.length;
    final gap = 3.0;
    final totalGap = gap * (count - 1);
    final barWidth = ((size.width - totalGap) / count).clamp(3.0, 14.0);
    final totalWidth = count * barWidth + totalGap;
    final startX = (size.width - totalWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0.35),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < count; i++) {
      final x = startX + i * (barWidth + gap);
      final magnitude = data[i].clamp(0.12, 1.0);
      final barHeight = (magnitude * size.height).clamp(6.0, size.height);
      final y = size.height - barHeight;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarVisualizerPainter oldDelegate) => true;
}

// --- PAINTER 2: WAVE VISUALIZER ---
class _WaveVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _WaveVisualizerPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final count = data.length;
    final stepX = size.width / (count - 1);

    final path = Path();
    final fillPath = Path();

    final points = <Offset>[];
    final midY = size.height / 2;

    for (int i = 0; i < count; i++) {
      final x = i * stepX;
      final waveOffset = (data[i] - 0.5) * (size.height * 0.8);
      final y = (midY + waveOffset).clamp(4.0, size.height - 4.0);
      points.add(Offset(x, y));
    }

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
      fillPath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _WaveVisualizerPainter oldDelegate) => true;
}

// --- PAINTER 3: CIRCULAR VISUALIZER ---
class _CircularVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _CircularVisualizerPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final minDim = math.min(size.width, size.height);
    final baseRadius = minDim * 0.28;
    final maxBarLength = minDim * 0.22;

    final count = data.length;
    final angleStep = (2 * math.pi) / count;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Draw base ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.3);
    canvas.drawCircle(center, baseRadius, ringPaint);

    for (int i = 0; i < count; i++) {
      final angle = i * angleStep - (math.pi / 2);
      final magnitude = data[i].clamp(0.05, 1.0);
      final barLength = magnitude * maxBarLength;

      final startX = center.dx + baseRadius * math.cos(angle);
      final startY = center.dy + baseRadius * math.sin(angle);
      final endX = center.dx + (baseRadius + barLength) * math.cos(angle);
      final endY = center.dy + (baseRadius + barLength) * math.sin(angle);

      paint.color = color.withValues(alpha: (0.4 + magnitude * 0.6).clamp(0.0, 1.0));
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularVisualizerPainter oldDelegate) => true;
}
