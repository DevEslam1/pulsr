// lib/features/player/presentation/widgets/audio_visualizer.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';

enum VisualizerStyle {
  off,
  bar,
  wave,
  circular,
  particles,
  terrain3D,
  albumArtReactive,
  custom,
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
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);

    if (widget.isPlaying && widget.style != VisualizerStyle.off) {
      _startAnimation();
    }
    _initVisualizer();
  }

  void _startAnimation() {
    if (!_animController.isAnimating) {
      _animController.repeat();
    }
  }

  void _stopAnimation() {
    if (_animController.isAnimating) {
      _animController.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.isPlaying && widget.style != VisualizerStyle.off) {
        _startAnimation();
        _restartNativeStream();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopAnimation();
      _stopNativeStream();
    }
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioSessionId != widget.audioSessionId) {
      _restartNativeStream();
    }
    if (oldWidget.isPlaying != widget.isPlaying || oldWidget.style != widget.style) {
      if (widget.isPlaying && widget.style != VisualizerStyle.off) {
        _startAnimation();
        _restartNativeStream();
      } else {
        _stopAnimation();
        _stopNativeStream();
        _clearData();
      }
    }
  }

  void _clearData() {
    for (int i = 0; i < _numBands; i++) {
      _currentData[i] = 0.0;
      _targetData[i] = 0.0;
    }
    _dataNotifier.value = List.from(_currentData);
  }

  Future<void> _initVisualizer() async {
    if (!Platform.isAndroid || widget.style == VisualizerStyle.off) return;

    try {
      var status = await Permission.microphone.status;
      if (status.isDenied) {
        status = await Permission.microphone.request();
      }
      if (status.isGranted) {
        _subscribeToStream();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to init visualizer', error: e, stackTrace: st, category: 'Visualizer');
    }
  }

  void _subscribeToStream() {
    _subscription?.cancel();
    final sessionId = widget.audioSessionId ?? 0;
    _methodChannel.invokeMethod('setAudioSessionId', {'audioSessionId': sessionId}).catchError((_) {});

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is List) {
          _lastNativeDataTime = DateTime.now();
          final len = math.min(event.length, _numBands);
          for (int i = 0; i < len; i++) {
            final val = (event[i] as num).toDouble();
            _targetData[i] = (val / 255.0).clamp(0.0, 1.0);
          }
        }
      },
      onError: (dynamic error) {
        _subscription?.cancel();
        _subscription = null;
      },
    );
  }

  void _restartNativeStream() {
    _subscription?.cancel();
    _subscription = null;
    if (Platform.isAndroid && widget.style != VisualizerStyle.off && widget.isPlaying) {
      _subscribeToStream();
    }
  }

  void _stopNativeStream() {
    _subscription?.cancel();
    _subscription = null;
    if (Platform.isAndroid) {
      _methodChannel.invokeMethod('releaseVisualizer').catchError((_) {});
    }
  }

  void _onTick() {
    final now = DateTime.now();
    final isStale = now.difference(_lastNativeDataTime).inMilliseconds > 250;

    if (isStale && widget.isPlaying && widget.style != VisualizerStyle.off) {
      final t = now.millisecondsSinceEpoch / 1000.0;
      for (int i = 0; i < _numBands; i++) {
        final phase = i * 0.25;
        final wave1 = math.sin(t * 3.5 + phase);
        final wave2 = math.cos(t * 2.1 + phase * 1.5);
        final sim = ((wave1 + wave2) / 4.0 + 0.35).clamp(0.05, 0.85);
        _targetData[i] = sim;
      }
    } else if (!widget.isPlaying) {
      for (int i = 0; i < _numBands; i++) {
        _targetData[i] = 0.0;
      }
    }

    const attackCoeff = 0.45;
    const decayCoeff = 0.18;
    bool hasChanged = false;

    for (int i = 0; i < _numBands; i++) {
      final target = _targetData[i];
      final current = _currentData[i];
      final coeff = target > current ? attackCoeff : decayCoeff;
      final next = current + (target - current) * coeff;

      if ((next - current).abs() > 0.001) {
        _currentData[i] = next;
        hasChanged = true;
      }
    }

    if (hasChanged) {
      _dataNotifier.value = List.from(_currentData);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAnimation();
    _animController.dispose();
    _stopNativeStream();
    _dataNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == VisualizerStyle.off) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final activeColor = widget.color ?? p.accent;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: ValueListenableBuilder<List<double>>(
          valueListenable: _dataNotifier,
          builder: (context, data, _) {
            return CustomPaint(
              size: Size(widget.width, widget.height),
              painter: switch (widget.style) {
                VisualizerStyle.bar => _BarVisualizerPainter(data: data, color: activeColor),
                VisualizerStyle.wave => _WaveVisualizerPainter(data: data, color: activeColor),
                VisualizerStyle.circular => _CircularVisualizerPainter(data: data, color: activeColor),
                VisualizerStyle.particles => _ParticlesVisualizerPainter(data: data, color: activeColor),
                VisualizerStyle.terrain3D => _Terrain3DVisualizerPainter(data: data, color: activeColor),
                VisualizerStyle.albumArtReactive => _AlbumArtReactivePainter(data: data, color: activeColor),
                VisualizerStyle.custom => _CustomJsonVisualizerPainter(data: data, color: activeColor),
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

    // Draw base ring with glow
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: 0.4);
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

// --- PAINTER 4: PARTICLES VISUALIZER ---
class _ParticlesVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _ParticlesVisualizerPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final angle = (i / data.length) * 2 * math.pi;
      final mag = data[i].clamp(0.1, 1.0);
      final dist = (size.width / 3.0) * mag;
      final x = center.dx + dist * math.cos(angle);
      final y = center.dy + dist * math.sin(angle);

      paint.color = color.withValues(alpha: mag * 0.8);
      canvas.drawCircle(Offset(x, y), 3.0 + mag * 4.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesVisualizerPainter oldDelegate) => true;
}

// --- PAINTER 5: 3D TERRAIN VISUALIZER ---
class _Terrain3DVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _Terrain3DVisualizerPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rows = 5;
    for (int r = 0; r < rows; r++) {
      final path = Path();
      final rowY = size.height * 0.4 + (r * 14.0);
      final stepX = size.width / (data.length - 1);

      for (int i = 0; i < data.length; i++) {
        final x = i * stepX;
        final h = data[i] * 35.0 * (1.0 - (r * 0.15));
        final y = rowY - h;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Terrain3DVisualizerPainter oldDelegate) => true;
}

// --- PAINTER 6: ALBUM ART REACTIVE ---
class _AlbumArtReactivePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _AlbumArtReactivePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final bassMag = (data.take(4).fold<double>(0, (s, e) => s + e) / 4.0).clamp(0.0, 1.0);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: (bassMag * 0.4).clamp(0.0, 0.6))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);

    canvas.drawCircle(center, (size.width / 4) * (1.0 + bassMag * 0.2), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _AlbumArtReactivePainter oldDelegate) => true;
}

// --- PAINTER 7: CUSTOM JSON VISUALIZER ---
class _CustomJsonVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _CustomJsonVisualizerPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    final stepX = size.width / data.length;
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX + stepX / 2;
      final y = size.height - (data[i] * size.height * 0.9);
      canvas.drawCircle(Offset(x, y), 3.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CustomJsonVisualizerPainter oldDelegate) => true;
}
