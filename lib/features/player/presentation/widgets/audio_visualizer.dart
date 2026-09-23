// lib/features/player/presentation/widgets/audio_visualizer.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/channels.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/visualizer/milkdrop_preset_store.dart';
import '../../../../data/visualizer/visualizer_preset_store.dart';
import '../../../../domain/models/milkdrop_preset.dart';
import '../../../../domain/models/visualizer_preset.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

enum VisualizerStyle {
  off,
  bar,
  wave,
  circular,
  particles,
  terrain3D,
  albumArtReactive,
  custom,
  milkdrop,
}

class AudioVisualizer extends StatefulWidget {
  final VisualizerStyle style;
  final Color? color;
  final double width;
  final double height;
  final bool isPlaying;
  final int? audioSessionId;
  final int? trackSeed;
  final int? trackId;
  final String? trackPath;
  final MilkdropPreset? milkdropPreset;
  final VisualizerPreset? customPreset;
  final VoidCallback? onPermissionDenied;

  const AudioVisualizer({
    super.key,
    this.style = VisualizerStyle.bar,
    this.color,
    this.width = double.infinity,
    this.height = double.infinity,
    this.isPlaying = true,
    this.audioSessionId,
    this.trackSeed,
    this.trackId,
    this.trackPath,
    this.milkdropPreset,
    this.customPreset,
    this.onPermissionDenied,
  });

  /// Deterministic per-track seed (defect 16-05): prefers explicit trackSeed,
  /// then stable hash of trackId/trackPath, then session id. Never shares one
  /// constant across different tracks.
  static int resolveSeed({
    int? trackSeed,
    int? trackId,
    String? trackPath,
    int? audioSessionId,
  }) {
    if (trackSeed != null) return trackSeed;
    if (trackId != null) return Object.hash(trackId, 'pulsr_visualizer_seed');
    if (trackPath != null && trackPath.isNotEmpty) {
      return Object.hash(trackPath, 'pulsr_visualizer_seed');
    }
    if (audioSessionId != null) return audioSessionId;
    return 0;
  }

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _methodChannel =
      MethodChannel(PulsrChannels.visualizer);
  static const EventChannel _eventChannel =
      EventChannel(PulsrChannels.visualizerStream);

  StreamSubscription? _subscription;
  late AnimationController _animController;
  bool _isAppActive = true;
  bool _permissionAsked = false;
  bool _permissionDenied = false;

  static const int _numBands = 32;
  final List<double> _currentData = List.filled(_numBands, 0.0);
  final List<double> _targetData = List.filled(_numBands, 0.0);
  late final ValueNotifier<List<double>> _dataNotifier;
  DateTime _lastNativeDataTime = DateTime.fromMillisecondsSinceEpoch(0);
  MilkdropPreset _milkPreset = MilkdropPresetLibrary.defaultPreset;
  VisualizerPreset _customPreset = VisualizerPreset.fallback;
  ui.FragmentShader? _milkShader;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataNotifier = ValueNotifier<List<double>>(List.from(_currentData));
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);

    if (widget.style == VisualizerStyle.milkdrop) {
      _loadMilkPreset();
      _loadMilkShader();
    } else if (widget.style == VisualizerStyle.custom) {
      _loadCustomPreset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isVisible = TickerMode.valuesOf(context).enabled;
    // Cosmetic audio-reactive animation: stop entirely under Reduce Motion or when invisible
    if (!isVisible || !context.motionEnabled) {
      _stopAnimation();
      return;
    }
    // Motion decisions must not read MediaQuery during initState.
    if (widget.isPlaying && widget.style != VisualizerStyle.off) {
      _startAnimation();
      _initVisualizer();
    } else {
      _stopAnimation();
    }
  }

  /// Loads the GPU Milkdrop warp shader. Falls back to the Canvas painter if the
  /// runtime effect is unavailable on this platform/build.
  /// Honest degradation (defect 16-01): [_shaderFailed] is surfaced to the UI
  /// so a silent style swap never claims to be MilkDrop.
  bool _shaderFailed = false;

  /// True when the GPU shader path is unavailable and the Canvas fallback is
  /// rendering. Exposed for tests / UI badge.
  bool get isFallbackActive => _shaderFailed || _milkShader == null;
  Future<void> _loadMilkShader() async {
    if (_milkShader != null) return;
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/milkdrop.frag');
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() {
        _milkShader = shader;
        _shaderFailed = false;
      });
    } catch (e, st) {
      ErrorLogger.log('Visualizer shader failed; using Canvas fallback',
          error: e, stackTrace: st, category: 'Visualizer');
      if (mounted) setState(() => _shaderFailed = true);
    }
  }

  Future<void> _loadMilkPreset() async {
    try {
      final preset = await MilkdropPresetStore().load();
      if (mounted) setState(() => _milkPreset = preset);
    } catch (e, st) {
      ErrorLogger.log('Visualizer preset load failed',
          error: e, stackTrace: st, category: 'Visualizer');
    }
  }

  Future<void> _loadCustomPreset() async {
    try {
      final preset = await VisualizerPresetStore().load();
      if (mounted) setState(() => _customPreset = preset);
    } catch (e, st) {
      ErrorLogger.log('Visualizer custom preset load failed',
          error: e, stackTrace: st, category: 'Visualizer');
    }
  }

  void _startAnimation() {
    if (!context.motionEnabled) {
      _stopAnimation();
      return;
    }
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
      _isAppActive = true;
      if (widget.isPlaying && widget.style != VisualizerStyle.off) {
        _startAnimation();
        _restartNativeStream();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isAppActive = false;
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
    if (oldWidget.style != widget.style &&
        widget.style == VisualizerStyle.milkdrop) {
      _loadMilkPreset();
      _loadMilkShader();
    }
    if (oldWidget.style != widget.style &&
        widget.style == VisualizerStyle.custom) {
      _loadCustomPreset();
    }
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.style != widget.style) {
      if (widget.isPlaying && widget.style != VisualizerStyle.off) {
        _startAnimation();
        _initVisualizer();
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
      if (status.isDenied && !_permissionAsked) {
        _permissionAsked = true;
        status = await Permission.microphone.request();
      }
      if (!mounted) return;
      if (status.isGranted) {
        if (_permissionDenied && mounted) {
          setState(() => _permissionDenied = false);
        }
        _subscribeToStream();
      } else {
        if (!_permissionDenied) {
          widget.onPermissionDenied?.call();
        }
        if (mounted) setState(() => _permissionDenied = true);
        if (status.isPermanentlyDenied) {
          ErrorLogger.log(
              'Microphone permission permanently denied for visualizer',
              category: 'Visualizer');
          if (mounted) {
            PulsrToast.show(
              context,
              message: context.l10n.rcMicNeeded,
              actionLabel: 'Settings',
              onActionPressed: () => openAppSettings(),
            );
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to init visualizer',
          error: e, stackTrace: st, category: 'Visualizer');
    }
  }

  void _subscribeToStream() {
    _subscription?.cancel();
    final sessionId = widget.audioSessionId ?? 0;
    _methodChannel.invokeMethod(
        'setAudioSessionId', {'audioSessionId': sessionId}).catchError((_) {});

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is List) {
          _lastNativeDataTime = DateTime.now();
          final len = math.min(event.length, _numBands);
          for (int i = 0; i < len; i++) {
            final val = (event[i] as num).toDouble();
            _targetData[i] = val.clamp(0.0, 1.0);
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
    if (Platform.isAndroid &&
        widget.style != VisualizerStyle.off &&
        widget.isPlaying) {
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
    if (!mounted || !_isAppActive || !widget.isPlaying) return;

    final now = DateTime.now();
    final staleMs = now.difference(_lastNativeDataTime).inMilliseconds;
    final isStale = staleMs > 250;

    if (isStale && widget.isPlaying && widget.style != VisualizerStyle.off) {
      if (Platform.isAndroid && _lastNativeDataTime.millisecondsSinceEpoch > 0 && staleMs > 1500) {
        // Native stream stopped delivering samples; decay to zero to avoid misleading synthetic animation
        for (int i = 0; i < _numBands; i++) {
          _targetData[i] = 0.0;
        }
      } else {
        final t = now.millisecondsSinceEpoch / 1000.0;
        final seed = AudioVisualizer.resolveSeed(
          trackSeed: widget.trackSeed,
          trackId: widget.trackId,
          trackPath: widget.trackPath,
          audioSessionId: widget.audioSessionId,
        );
        final seedOffset = (seed.abs() % 100) / 100.0;
        for (int i = 0; i < _numBands; i++) {
          final phase = i * 0.25 + seedOffset;
          final wave1 = math.sin(t * (3.5 + (seed.abs() % 4) * 0.1) + phase);
          final wave2 =
              math.cos(t * (2.1 + (seed.abs() % 3) * 0.1) + phase * 1.5);
          final sim = ((wave1 + wave2) / 4.0 + 0.35).clamp(0.05, 0.85);
          _targetData[i] = sim;
        }
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
    _milkShader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == VisualizerStyle.off) {
      return const SizedBox.shrink();
    }
    // GPU budget mode: heavy GPU styles fall back to cheap bars.
    final effectiveStyle = GpuBudget.isEnabled &&
            (widget.style == VisualizerStyle.milkdrop ||
                widget.style == VisualizerStyle.terrain3D ||
                widget.style == VisualizerStyle.particles ||
                widget.style == VisualizerStyle.albumArtReactive)
        ? VisualizerStyle.bar
        : widget.style;

    final p = context.palette;
    final activeColor = widget.color ?? p.accent;

    return ExcludeSemantics(
      child: Stack(
        children: [
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: ClipRect(
              child: ValueListenableBuilder<List<double>>(
          valueListenable: _dataNotifier,
          builder: (context, data, _) {
            return RepaintBoundary(
              child: CustomPaint(
                size: Size(widget.width, widget.height),
                painter: switch (effectiveStyle) {
                  VisualizerStyle.bar =>
                    _BarVisualizerPainter(data: data, color: activeColor),
                  VisualizerStyle.wave =>
                    _WaveVisualizerPainter(data: data, color: activeColor),
                  VisualizerStyle.circular =>
                    _CircularVisualizerPainter(data: data, color: activeColor),
                  VisualizerStyle.particles =>
                    _ParticlesVisualizerPainter(data: data, color: activeColor),
                  VisualizerStyle.terrain3D =>
                    _Terrain3DVisualizerPainter(data: data, color: activeColor),
                  VisualizerStyle.albumArtReactive =>
                    _AlbumArtReactivePainter(data: data, color: activeColor),
                  VisualizerStyle.custom => _CustomJsonVisualizerPainter(
                      data: data,
                      color: activeColor,
                      preset: widget.customPreset ?? _customPreset,
                    ),
                  VisualizerStyle.milkdrop => (_milkShader != null)
                      ? _MilkdropGpuPainter(
                          shader: _milkShader!,
                          data: data,
                          color: activeColor,
                          preset: widget.milkdropPreset ?? _milkPreset,
                        )
                      : _MilkdropPainter(
                          data: data,
                          color: activeColor,
                          preset: widget.milkdropPreset ?? _milkPreset,
                        ),
                  VisualizerStyle.off => null,
                },
              ),
            );
          },
        ),
        ),
      ),
          // Honest degradation (16-01): when the MilkDrop GPU shader failed to
          // compile, the Canvas painter above is NOT MilkDrop — say so instead
          // of letting the user believe they are seeing it.
          if (widget.style == VisualizerStyle.milkdrop && isFallbackActive)
            PositionedDirectional(
              top: 6,
              end: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadii.r8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                  child: Text(
                    context.l10n.visualizerCpuFallbackBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          if (_permissionDenied && Platform.isAndroid)
            Center(
              child: ActionChip(
                avatar: const Icon(Icons.mic_none_rounded, size: 16),
                label: Text(context.l10n.rcMicNeeded),
                onPressed: () async {
                  final status = await Permission.microphone.request();
                  if (status.isGranted) {
                    _initVisualizer();
                  } else {
                    await openAppSettings();
                  }
                },
              ),
            ),
        ],
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

      paint.color =
          color.withValues(alpha: (0.4 + magnitude * 0.6).clamp(0.0, 1.0));
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
    final bassMag =
        (data.take(4).fold<double>(0, (s, e) => s + e) / 4.0).clamp(0.0, 1.0);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: (bassMag * 0.4).clamp(0.0, 0.6))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);

    canvas.drawCircle(
        center, (size.width / 4) * (1.0 + bassMag * 0.2), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _AlbumArtReactivePainter oldDelegate) => true;
}

// --- PAINTER 7: CUSTOM JSON VISUALIZER ---
//
// Renders a user-authored JSON preset (`VisualizerPreset`): shape family,
// colors, bar count, rotation, glow, sensitivity and mirror. This replaces the
// previous label-only implementation that never parsed any JSON.
class _CustomJsonVisualizerPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final VisualizerPreset preset;

  _CustomJsonVisualizerPainter({
    required this.data,
    required this.color,
    required this.preset,
  });

  double _sample(double t) {
    if (data.isEmpty) return 0.0;
    final n = data.length;
    final x = t.clamp(0.0, 1.0) * (n - 1);
    final i = x.floor();
    final j = (i + 1).clamp(0, n - 1);
    final f = x - i;
    return (data[i] * (1 - f) + data[j] * f).clamp(0.0, 1.0);
  }

  double _valueAt(int i, int count) {
    if (preset.mirror) {
      final half = (count / 2).ceil();
      final src = i < half ? i : (count - 1 - i);
      return _sample(src / (half - 1).clamp(1, count));
    }
    return _sample(i / (count - 1).clamp(1, count));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final primary = Color(preset.primaryColor);
    final secondary = Color(preset.secondaryColor);
    if (preset.backgroundColor != 0) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Color(preset.backgroundColor));
    }

    final count = preset.barCount;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final rot = preset.rotationSpeed * t * 2 * math.pi;

    switch (preset.shape) {
      case VisualizerShape.bars:
        _paintBars(canvas, size, count, primary, secondary);
        break;
      case VisualizerShape.wave:
        _paintWave(canvas, size, count, primary, secondary);
        break;
      case VisualizerShape.radial:
        _paintRadial(canvas, size, count, primary, secondary, rot);
        break;
      case VisualizerShape.particles:
        _paintParticles(canvas, size, count, primary, secondary, t);
        break;
      case VisualizerShape.lissajous:
        _paintLissajous(canvas, size, count, primary, secondary, t);
        break;
    }
  }

  void _paintBars(
      Canvas canvas, Size size, int count, Color primary, Color secondary) {
    const gap = 2.0;
    final barW = ((size.width - gap * (count - 1)) / count).clamp(1.5, 16.0);
    final totalW = count * barW + gap * (count - 1);
    final startX = (size.width - totalW) / 2;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    for (var i = 0; i < count; i++) {
      final v = (_valueAt(i, count) * preset.sensitivity).clamp(0.0, 1.0);
      final h = (v * size.height).clamp(2.0, size.height);
      final x = startX + i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
    }
  }

  void _paintWave(
      Canvas canvas, Size size, int count, Color primary, Color secondary) {
    final midY = size.height / 2;
    final path = Path();
    final fill = Path()..moveTo(0, size.height);
    for (var i = 0; i < count; i++) {
      final x = size.width * (i / (count - 1).clamp(1, count));
      final v = (_valueAt(i, count) * preset.sensitivity).clamp(0.0, 1.0);
      final y = midY - (v - 0.5) * size.height * 0.9;
      if (i == 0) {
        path.moveTo(x, y);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          colors: [primary.withValues(alpha: 0.5), secondary.withValues(alpha: 0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + preset.glow * 3
        ..strokeCap = StrokeCap.round
        ..color = primary,
    );
  }

  void _paintRadial(Canvas canvas, Size size, int count, Color primary,
      Color secondary, double rot) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide * 0.22;
    final maxLen = size.shortestSide * 0.26;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final angle = i / count * 2 * math.pi + rot;
      final v = (_valueAt(i, count) * preset.sensitivity).clamp(0.0, 1.0);
      final len = v * maxLen;
      final start =
          center + Offset(math.cos(angle), math.sin(angle)) * base;
      final end = center +
          Offset(math.cos(angle), math.sin(angle)) * (base + len);
      paint
        ..color = Color.lerp(primary, secondary, v)!.withValues(alpha: 0.85)
        ..strokeWidth = 2.0 + preset.glow * 3;
      canvas.drawLine(start, end, paint);
    }
  }

  void _paintParticles(Canvas canvas, Size size, int count, Color primary,
      Color secondary, double t) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final v = (_valueAt(i, count) * preset.sensitivity).clamp(0.0, 1.0);
      final angle = i / count * 2 * math.pi + t * 0.5;
      final dist = size.shortestSide * 0.5 * math.pow(v, 1.3).toDouble();
      final p = center + Offset(math.cos(angle), math.sin(angle)) * dist;
      paint.color = Color.lerp(primary, secondary, v)!
          .withValues(alpha: (0.25 + v * 0.65).clamp(0.0, 1.0));
      canvas.drawCircle(p, 1.5 + v * 4.0, paint);
    }
  }

  void _paintLissajous(Canvas canvas, Size size, int count, Color primary,
      Color secondary, double t) {
    final a = _sample(0.1) * preset.sensitivity + 1.0;
    final b = _sample(0.4) * preset.sensitivity + 2.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.4;
    final path = Path();
    final steps = math.max(count * 4, 64);
    for (var i = 0; i <= steps; i++) {
      final p = i / steps * 2 * math.pi;
      final x = center.dx + radius * math.sin(a * p + t);
      final y = center.dy + radius * math.sin(b * p + t * 0.5);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + preset.glow * 3
        ..shader = LinearGradient(
          colors: [primary, secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _CustomJsonVisualizerPainter oldDelegate) =>
      true;
}

// --- PAINTER 8: MILKDROP PRESET VISUALIZER ---
//
// GPU path: drives `shaders/milkdrop.frag` (a Flutter runtime effect) from the
// parsed `.milk` preset scalars and the live audio bands. The original HSLSL/EEL
// preset code is not transpiled; the shader reproduces the preset's motion.
class _MilkdropGpuPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;

  _MilkdropGpuPainter({
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
  bool shouldRepaint(covariant _MilkdropGpuPainter oldDelegate) => true;
}

// --- MILKDROP CANVAS FALLBACK ---
//
// Parameter-driven approximation used when the runtime effect is unavailable.

class _MilkdropPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final MilkdropPreset preset;

  _MilkdropPainter({
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
  bool shouldRepaint(covariant _MilkdropPainter oldDelegate) => true;
}
