// lib/features/player/presentation/themes/milkdrop_player_theme.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/constants/channels.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../data/visualizer/milkdrop_preset_store.dart';
import '../../../../domain/models/milkdrop_preset.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/visualizer/milkdrop_renderer.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';

/// Theme 8: Milkdrop Visualizer — Full-Screen GPU Canvas.
///
/// Decoupled from `PlayerThemeScaffold` via [PlayerSurfaceShell]:
/// 1. Edge-to-edge 100% full-screen [MilkdropRenderer] driving
///    `shaders/milkdrop.frag` ([MilkdropGpuPainter]) and falling back
///    seamlessly to [MilkdropCanvasPainter] under [GpuBudget.isGpuSaverActive]
///    or when runtime shaders are unavailable (never downgrading to bars).
/// 2. Live preset cycling across [MilkdropPresetLibrary.presets] (plus any
///    imported `.milk` preset) via a sleek frosted preset badge in the top bar.
/// 3. Minimal floating frosted glass capsule housing compact album art
///    thumbnail, track title/artist, favorite heart, slim interactive progress
///    bar (`BlocSelector` position), and compact transport + Lyrics/Queue buttons.
/// 4. Auto-dim / tap-to-immerse mode: tapping the open canvas smoothly fades
///    the chrome to ~0.08 with [IgnorePointer] so the Milkdrop canvas owns
///    100% of the screen; tapping anywhere restores controls. Disabled in
///    [PlayerThemePreviewScope] so mini-previews remain crisp.
class MilkdropPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const MilkdropPlayerTheme({super.key, required this.props});

  @override
  State<MilkdropPlayerTheme> createState() => _MilkdropPlayerThemeState();
}

bool _isTestEnvironment() =>
    const bool.fromEnvironment('FLUTTER_TEST') ||
    WidgetsBinding.instance is! WidgetsFlutterBinding;

class _MilkdropPlayerThemeState extends State<MilkdropPlayerTheme> {
  final List<MilkdropPreset> _presets =
      List<MilkdropPreset>.from(MilkdropPresetLibrary.presets);
  int _presetIndex = 0;
  bool _isImmersed = false;

  MilkdropPreset get _activePreset => _presets[_presetIndex % _presets.length];

  @override
  void initState() {
    super.initState();
    if (!_isTestEnvironment()) {
      unawaited(_loadImportedPreset());
    }
  }

  Future<void> _loadImportedPreset() async {
    try {
      final loaded = await MilkdropPresetStore().load();
      if (!mounted) return;
      final existingIdx = _presets.indexWhere((p) => p.name == loaded.name);
      if (existingIdx >= 0) {
        if (existingIdx != _presetIndex) {
          setState(() => _presetIndex = existingIdx);
        }
      } else {
        setState(() {
          _presets.add(loaded);
          _presetIndex = _presets.length - 1;
        });
      }
    } catch (_) {
      // Built-in MilkdropPresetLibrary remains active on store errors.
    }
  }

  void _cyclePreset() {
    PulsrHaptics.selectionClick();
    setState(() {
      _presetIndex = (_presetIndex + 1) % _presets.length;
    });
  }

  void _toggleImmersion() {
    PulsrHaptics.selectionClick();
    setState(() => _isImmersed = !_isImmersed);
  }

  void _exitImmersion() {
    if (!_isImmersed) return;
    PulsrHaptics.selectionClick();
    setState(() => _isImmersed = false);
  }

  void _dismiss(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
        return;
      }
      router.go('/');
    } catch (_) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final surface = context.playerSurfacePalette;
    final customGlow = resolveCustomGlow(context);
    final capsuleRadius = resolveCustomRadius(context, AppRadii.r28);
    final artRadius = resolveCustomRadius(context, AppRadii.r12);

    return PlayerSurfaceShell(
      props: props,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(surface.shadowAt(0.55), props.bgColor),
              Color.alphaBlend(surface.shadowAt(0.82), props.bgColor),
            ],
          ),
        ),
      ),
      builder: (context, metrics, isInSplitView, isPreview) {
        final bool immersed = !isPreview && _isImmersed;
        final bool isCompact = metrics.isVeryShortHeight || metrics.isLandscape;
        final double horizontalPad =
            metrics.isTablet ? AppSpacing.lg : AppSpacing.md;
        final double chromeOpacity = immersed ? 0.08 : 1.0;

        final Widget canvasLayer = _MilkdropLiveCanvas(
          activeColor: activeColor,
          preset: _activePreset,
          isPlaying: state.isPlaying,
          isPreview: isPreview,
          audioSessionId: state.audioSessionId,
          trackId: song?.id,
          trackPath: song?.path,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 100% Edge-to-Edge Milkdrop GPU / Canvas Visualizer Stage
            Positioned.fill(
              child: isPreview
                  ? ExcludeSemantics(child: canvasLayer)
                  : PlayerGestureScope(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleImmersion,
                        child: ExcludeSemantics(child: canvasLayer),
                      ),
                    ),
            ),

            // Subtle vignette scrims so frosted glass pills read crisply over
            // bright shader bursts without obscuring the center warp tunnel.
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              height: isCompact ? 80 : 112,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: immersed ? 0.0 : 1.0,
                  duration: context.motionMs(260),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.scrimAt(0.56),
                          AppColors.scrimAt(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              height: isCompact ? 140 : 196,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: immersed ? 0.0 : 1.0,
                  duration: context.motionMs(260),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppColors.scrimAt(0.66),
                          AppColors.scrimAt(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. Floating Minimal Top Bar (Dismiss + Preset Switcher + Tools)
            if (!isPreview)
              PositionedDirectional(
                top: 0,
                start: 0,
                end: 0,
                child: SafeArea(
                  top: !isInSplitView,
                  bottom: false,
                  child: AnimatedOpacity(
                    opacity: chromeOpacity,
                    duration: context.motionMs(260),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    child: IgnorePointer(
                      ignoring: immersed,
                      child: _MilkdropTopBar(
                        props: props,
                        presetName: _activePreset.name,
                        activeColor: activeColor,
                        isInSplitView: isInSplitView,
                        horizontalPad: horizontalPad,
                        onDismiss: () => _dismiss(context),
                        onCyclePreset: _cyclePreset,
                      ),
                    ),
                  ),
                ),
              )
            else
              PositionedDirectional(
                top: AppSpacing.sm,
                start: horizontalPad,
                end: horizontalPad,
                child: Center(
                  child: _MilkdropPresetBadge(
                    presetName: _activePreset.name,
                    activeColor: activeColor,
                    isPreview: true,
                    onTap: null,
                  ),
                ),
              ),

            // 3. Minimal Floating Frosted Glass Metadata & Transport Capsule
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              child: SafeArea(
                top: false,
                bottom: !isInSplitView && !isPreview,
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    horizontalPad,
                    0,
                    horizontalPad,
                    isCompact ? AppSpacing.xs : AppSpacing.md,
                  ),
                  child: AnimatedOpacity(
                    opacity: chromeOpacity,
                    duration: context.motionMs(260),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    child: IgnorePointer(
                      ignoring: immersed,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: _MilkdropGlassCapsule(
                            props: props,
                            activeColor: activeColor,
                            capsuleRadius: capsuleRadius,
                            artRadius: artRadius,
                            isCompact: isCompact,
                            isInSplitView: isInSplitView,
                            isPreview: isPreview,
                            customGlow: customGlow,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. Tap-anywhere restore layer while in pure visual immersion
            if (immersed)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _exitImmersion,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Self-contained Milkdrop GPU / Canvas stage feeding [MilkdropRenderer]
/// directly so GPU Saver falls back to [MilkdropCanvasPainter] rather than
/// downgrading to cheap bars.
class _MilkdropLiveCanvas extends StatefulWidget {
  final Color activeColor;
  final MilkdropPreset preset;
  final bool isPlaying;
  final bool isPreview;
  final int? audioSessionId;
  final int? trackId;
  final String? trackPath;

  const _MilkdropLiveCanvas({
    required this.activeColor,
    required this.preset,
    required this.isPlaying,
    required this.isPreview,
    required this.audioSessionId,
    required this.trackId,
    required this.trackPath,
  });

  @override
  State<_MilkdropLiveCanvas> createState() => _MilkdropLiveCanvasState();
}

class _MilkdropLiveCanvasState extends State<_MilkdropLiveCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _numBands = 32;
  static const MethodChannel _methodChannel =
      MethodChannel(PulsrChannels.visualizer);
  static const EventChannel _eventChannel =
      EventChannel(PulsrChannels.visualizerStream);

  static ui.FragmentProgram? _cachedProgram;

  late final AnimationController _ticker;
  late final ValueNotifier<List<double>> _bandsNotifier;
  final List<double> _currentBands = List<double>.filled(_numBands, 0.0);
  final List<double> _targetBands = List<double>.filled(_numBands, 0.0);
  List<double> _spareSnapshot = List<double>.filled(_numBands, 0.0);
  int _snapshotGeneration = 0;
  bool _claimedNativeSession = false;
  final Stopwatch _phaseClock = Stopwatch()..start();

  StreamSubscription<dynamic>? _nativeSub;
  DateTime _lastNativeSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
  ui.FragmentShader? _shader;
  int _lastTickMs = 0;
  bool _isAppActive = true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isStaticMode => widget.isPreview || _isTestEnvironment();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seedStaticSnapshot();
    _bandsNotifier = ValueNotifier<List<double>>(
      List<double>.from(_currentBands),
    );
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33),
    )..addListener(_onTick);

    if (!_isStaticMode) {
      unawaited(_loadShader());
    }
  }

  void _seedStaticSnapshot() {
    final seed = AudioVisualizer.resolveSeed(
      trackId: widget.trackId,
      trackPath: widget.trackPath,
      audioSessionId: widget.audioSessionId,
    );
    final seedOffset = (seed.abs() % 100) / 100.0;
    for (int i = 0; i < _numBands; i++) {
      final phase = i * 0.24 + seedOffset * 3.14;
      final v =
          ((math.sin(phase + 1.1) + math.cos(phase * 1.6)) * 0.24 + 0.44)
              .clamp(0.12, 0.88);
      _currentBands[i] = v;
      _targetBands[i] = v;
    }
  }

  Future<void> _loadShader() async {
    if (_shader != null || _isStaticMode) return;
    try {
      final program = _cachedProgram ??
          await ui.FragmentProgram.fromAsset('shaders/milkdrop.frag');
      _cachedProgram ??= program;
      final shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (_) {
      // MilkdropRenderer falls back to MilkdropCanvasPainter automatically.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRunningState();
  }

  @override
  void didUpdateWidget(covariant _MilkdropLiveCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId ||
        oldWidget.trackPath != widget.trackPath) {
      if (_isStaticMode) {
        _seedStaticSnapshot();
        _snapshotGeneration++;
        _bandsNotifier.value = List<double>.from(_currentBands);
      }
    }
    if (oldWidget.audioSessionId != widget.audioSessionId) {
      _restartNativeStream();
    }
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.isPreview != widget.isPreview) {
      _syncRunningState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      _syncRunningState();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isAppActive = false;
      _stopTicker();
      _stopNativeStream();
    }
  }

  void _syncRunningState() {
    final bool allowMotion =
        context.motionEnabled && PulsrMotion.shouldAnimate(context);
    final bool isVisible = TickerMode.valuesOf(context).enabled;
    if (_isStaticMode || !allowMotion || !isVisible || !_isAppActive) {
      _stopTicker();
      _stopNativeStream();
      return;
    }
    if (widget.isPlaying) {
      _startTicker();
      _restartNativeStream();
    } else {
      _stopNativeStream();
      // Gently relax towards a calm ambient idle wave rather than dead black.
      for (int i = 0; i < _numBands; i++) {
        _targetBands[i] = 0.14;
      }
      _startTicker();
    }
  }

  void _startTicker() {
    if (_isStaticMode) return;
    if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _stopTicker() {
    if (_ticker.isAnimating) {
      _ticker.stop();
    }
  }

  void _restartNativeStream() {
    _stopNativeStream();
    if (!_isAndroid || _isStaticMode || !widget.isPlaying) return;
    final sessionId = widget.audioSessionId ?? 0;
    if (sessionId <= 0) return;

    _methodChannel
        .invokeMethod('setAudioSessionId', {'audioSessionId': sessionId})
        .catchError((_) {});

    if (!_claimedNativeSession) {
      _claimedNativeSession = true;
      AudioVisualizerState.acquireNativeVisualizerSession();
    }
    _nativeSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is List) {
          _lastNativeSampleAt = DateTime.now();
          final len = math.min(event.length, _numBands);
          for (int i = 0; i < len; i++) {
            final raw = event[i];
            if (raw is num && raw.isFinite) {
              _targetBands[i] = raw.toDouble().clamp(0.0, 1.0);
            }
          }
        }
      },
      onError: (_) {
        _stopNativeStream();
      },
    );
  }

  void _stopNativeStream() {
    _nativeSub?.cancel();
    _nativeSub = null;
    if (_claimedNativeSession) {
      _claimedNativeSession = false;
      AudioVisualizerState.releaseNativeVisualizerSession(
        isAndroid: _isAndroid,
      );
    }
  }

  void _onTick() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastTickMs < 32) return;
    _lastTickMs = nowMs;

    if (!mounted ||
        _isStaticMode ||
        !_isAppActive ||
        !context.motionEnabled ||
        !PulsrMotion.shouldAnimate(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _stopTicker();
      return;
    }

    if (widget.isPlaying) {
      final staleMs =
          DateTime.now().difference(_lastNativeSampleAt).inMilliseconds;
      if (staleMs > 250) {
        final t = _phaseClock.elapsedMilliseconds / 1000.0;
        final seed = AudioVisualizer.resolveSeed(
          trackId: widget.trackId,
          trackPath: widget.trackPath,
          audioSessionId: widget.audioSessionId,
        );
        final seedOffset = (seed.abs() % 100) / 100.0;
        for (int i = 0; i < _numBands; i++) {
          final phase = i * 0.25 + seedOffset;
          final w1 = math.sin(t * (3.2 + (seed.abs() % 4) * 0.12) + phase);
          final w2 =
              math.cos(t * (2.0 + (seed.abs() % 3) * 0.15) + phase * 1.45);
          _targetBands[i] = ((w1 + w2) * 0.25 + 0.42).clamp(0.08, 0.88);
        }
      }
    }

    const attack = 0.42;
    const decay = 0.16;
    bool settled = true;
    for (int i = 0; i < _numBands; i++) {
      final target = _targetBands[i];
      final current = _currentBands[i];
      final coeff = target > current ? attack : decay;
      final next = current + (target - current) * coeff;
      if ((next - current).abs() > 0.002) {
        _currentBands[i] = next;
        settled = false;
      } else {
        _currentBands[i] = target;
      }
    }

    final emit = _spareSnapshot;
    for (int i = 0; i < _numBands; i++) {
      emit[i] = _currentBands[i];
    }
    _spareSnapshot = _bandsNotifier.value;
    _snapshotGeneration++;
    _bandsNotifier.value = emit;

    if (!widget.isPlaying && settled) {
      _stopTicker();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicker();
    _ticker.dispose();
    _stopNativeStream();
    _bandsNotifier.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool allowMotion = PulsrMotion.shouldAnimate(context);
    final bool forceCanvas = _isStaticMode || !allowMotion;

    return ValueListenableBuilder<bool>(
      valueListenable: GpuBudget.enabled,
      builder: (context, isGpuSaver, _) {
        return ValueListenableBuilder<List<double>>(
          valueListenable: _bandsNotifier,
          builder: (context, bands, _) {
            return MilkdropRenderer(
              shader: (forceCanvas || isGpuSaver) ? null : _shader,
              data: bands,
              color: widget.activeColor,
              preset: widget.preset,
              forceCanvasFallback: forceCanvas || isGpuSaver,
              transparentBackground: false,
              generation: _snapshotGeneration,
              elapsedSeconds: _phaseClock.elapsedMicroseconds / 1000000.0,
            );
          },
        );
      },
    );
  }
}

/// Minimal translucent floating top bar: Dismiss + Preset Badge + Tools button.
class _MilkdropTopBar extends StatelessWidget {
  final PlayerThemeProps props;
  final String presetName;
  final Color activeColor;
  final bool isInSplitView;
  final double horizontalPad;
  final VoidCallback onDismiss;
  final VoidCallback onCyclePreset;

  const _MilkdropTopBar({
    required this.props,
    required this.presetName,
    required this.activeColor,
    required this.isInSplitView,
    required this.horizontalPad,
    required this.onDismiss,
    required this.onCyclePreset,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allowBlur = AppBlur.canBlur(context);
    final Color ink = AppColors.onPrimary;
    final Color glassFill = AppColors.scrimAt(
      allowBlur ? 0.36 : AppBlur.solidFallbackMinAlpha,
    );
    final isHighContrast = context.palette.isHighContrast ||
        MediaQuery.highContrastOf(context);
    final Color glassBorder = isHighContrast
        ? AppColors.specularAt(0.55)
        : AppColors.specularAt(0.22);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPad,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (!isInSplitView)
            PlayerIconActionButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: l10n.close,
              iconColor: ink,
              surfaceColor: glassFill,
              borderColor: glassBorder,
              iconSize: 26,
              blurSigma: AppBlur.chip,
              onTap: onDismiss,
            )
          else
            const SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
            ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Center(
              child: _MilkdropPresetBadge(
                presetName: presetName,
                activeColor: activeColor,
                isPreview: false,
                onTap: onCyclePreset,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          PlayerToolsTriggerButton(
            props: props,
            iconColor: ink,
            backgroundColor: glassFill,
            borderColor: glassBorder,
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}

/// Sleek frosted glass preset badge that cycles [MilkdropPresetLibrary.presets].
class _MilkdropPresetBadge extends StatelessWidget {
  final String presetName;
  final Color activeColor;
  final bool isPreview;
  final VoidCallback? onTap;

  const _MilkdropPresetBadge({
    required this.presetName,
    required this.activeColor,
    required this.isPreview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allowBlur = !isPreview && AppBlur.canBlur(context);
    final sigma = AppBlur.clampSigma(AppBlur.chip);
    final Color ink = AppColors.onPrimary;
    final Color fill = AppColors.scrimAt(
      allowBlur ? 0.42 : AppBlur.solidFallbackMinAlpha,
    );
    final Color border = Color.alphaBlend(
      activeColor.withValues(alpha: 0.38),
      AppColors.specularAt(0.24),
    );

    Widget badge = Material(
      color: fill,
      shape: StadiumBorder(
        side: BorderSide(color: border, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.blur_on_rounded,
                  size: 15,
                  color: Color.lerp(ink, activeColor, 0.45) ?? ink,
                ),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    presetName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.label,
                      color: ink,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.sync_rounded,
                    size: 13,
                    color: ink.withValues(alpha: 0.72),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (allowBlur) {
      badge = ClipRRect(
        borderRadius: AppRadii.full,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: badge,
        ),
      );
    }

    if (onTap == null) {
      return ExcludeSemantics(child: badge);
    }

    return Semantics(
      button: true,
      label: '${l10n.settingsVizLabelMilkdrop}: $presetName',
      excludeSemantics: true,
      child: badge,
    );
  }
}

/// Floating frosted glass capsule at the bottom of the Milkdrop stage containing
/// compact album art thumbnail, track title/artist, favorite heart, slim
/// interactive progress bar (`BlocSelector`), and compact transport controls.
class _MilkdropGlassCapsule extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final double capsuleRadius;
  final double artRadius;
  final bool isCompact;
  final bool isInSplitView;
  final bool isPreview;
  final bool customGlow;

  const _MilkdropGlassCapsule({
    required this.props,
    required this.activeColor,
    required this.capsuleRadius,
    required this.artRadius,
    required this.isCompact,
    required this.isInSplitView,
    required this.isPreview,
    required this.customGlow,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;
    final isFav = song?.isFavorite == true;

    final allowBlur = !isPreview && AppBlur.canBlur(context);
    final sigma = AppBlur.clampSigma(AppBlur.chip);
    final clampedRadius = capsuleRadius.clamp(14.0, 36.0);
    final clampedArtRadius = artRadius.clamp(4.0, 22.0);
    final corners = AppRadii.circular(clampedRadius);
    final double thumbSize = isCompact ? 38.0 : 44.0;

    // Dark cosmic frosted glass guarantees crisp legibility over bright shader
    // bursts in both Light and Dark app themes.
    final Color primaryInk = AppColors.onPrimary;
    final Color secondaryInk = AppColors.onPrimary.withValues(alpha: 0.76);
    final Color capsuleFill = Color.alphaBlend(
      activeColor.withValues(alpha: allowBlur ? 0.12 : 0.16),
      AppColors.darkSurface.withValues(
        alpha: allowBlur ? 0.62 : AppBlur.solidFallbackMinAlpha,
      ),
    );
    final isHighContrast =
        p.isHighContrast || MediaQuery.highContrastOf(context);
    final Color capsuleBorder = isHighContrast
        ? AppColors.specularAt(0.55)
        : Color.alphaBlend(
            activeColor.withValues(alpha: 0.24),
            AppColors.specularAt(0.20),
          );

    final Widget artThumb = Hero(
      tag: props.heroTag,
      child: Container(
        width: thumbSize,
        height: thumbSize,
        decoration: BoxDecoration(
          borderRadius: AppRadii.circular(clampedArtRadius),
          border: Border.all(
            color: AppColors.specularAt(state.isPlaying ? 0.34 : 0.20),
            width: 1.0,
          ),
        ),
        child: ClipRRect(
          borderRadius: AppRadii.circular(clampedArtRadius),
          child: PlayerArtworkSemantics(
            song: song,
            child: song != null
                ? CachedArtwork(
                    id: song.id,
                    albumId: song.albumId,
                    remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                    type: ArtworkType.AUDIO,
                    size: thumbSize,
                    borderRadius: clampedArtRadius,
                    highQuality: true,
                  )
                : ColoredBox(
                    color: AppColors.surfaceElevated,
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 18,
                      color: secondaryInk,
                    ),
                  ),
          ),
        ),
      ),
    );

    final String titleText = song?.title ?? l10n.noTrackSelected;
    final String artistText = song?.artist ?? l10n.unknownArtist;

    final shuffleLabel =
        state.isShuffle ? l10n.disableShuffle : l10n.enableShuffle;
    final repeatLabel = state.repeatMode == PlayerRepeatMode.one
        ? l10n.repeatOne
        : state.repeatMode == PlayerRepeatMode.all
            ? l10n.repeatAll
            : l10n.repeatOff;
    final repeatIcon = state.repeatMode == PlayerRepeatMode.one
        ? Icons.repeat_one_rounded
        : Icons.repeat_rounded;

    Widget capsule = Container(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.sm,
        isCompact ? AppSpacing.xs : AppSpacing.sm,
        AppSpacing.sm,
        isCompact ? AppSpacing.xxs : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: capsuleFill,
        borderRadius: corners,
        border: Border.all(color: capsuleBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(0.46),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          if (customGlow)
            BoxShadow(
              color: activeColor.withValues(alpha: 0.32),
              blurRadius: 30,
              spreadRadius: -2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Compact art thumbnail + Track title & artist + Favorite
          Row(
            children: [
              artThumb,
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPreview)
                      Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: FontWeight.w800,
                          color: primaryInk,
                          letterSpacing: AppTracking.title,
                        ),
                      )
                    else
                      MarqueeText(
                        text: titleText,
                        style: TextStyle(
                          fontSize: isCompact
                              ? AppFontSize.body
                              : AppFontSize.callout,
                          fontWeight: FontWeight.w800,
                          color: primaryInk,
                          letterSpacing: AppTracking.title,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      artistText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: secondaryInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isPreview)
                Material(
                  color: AppColors.fadeStopTransparent,
                  child: PlayerAnimatedFavoriteButton(
                    isFavorite: isFav,
                    favoriteColor: AppColors.favorite,
                    inactiveColor: secondaryInk,
                    iconSize: 21,
                    semanticLabel: isFav ? l10n.unlike : l10n.like,
                    onTap: () {
                      if (song != null) {
                        cubit.toggleFavorite(song.id);
                      }
                    },
                  ),
                ),
            ],
          ),

          SizedBox(height: isCompact ? AppSpacing.s2 : AppSpacing.xxs),

          // Row 2: Slim Interactive Progress Bar (BlocSelector position)
          _MilkdropProgressBar(
            duration: state.duration,
            activeColor: activeColor,
            primaryInk: primaryInk,
            secondaryInk: secondaryInk,
            isBuffering: state.isBuffering,
            isCompact: isCompact,
            onSeek: cubit.seek,
          ),

          // Row 3: Compact Transport + Lyrics / Queue (or Shuffle / Repeat in split)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (isInSplitView)
                  PlayerIconActionButton(
                    icon: Icons.shuffle_rounded,
                    tooltip: shuffleLabel,
                    isActive: state.isShuffle,
                    activeColor: activeColor,
                    iconColor: secondaryInk,
                    iconSize: 19,
                    showActiveDot: true,
                    onTap: cubit.toggleShuffle,
                  )
                else
                  PlayerIconActionButton(
                    icon: Icons.lyrics_rounded,
                    tooltip: l10n.lyrics,
                    isActive: state.isLyricsVisible,
                    activeColor: activeColor,
                    iconColor: secondaryInk,
                    iconSize: 20,
                    showActiveDot: true,
                    onTap: cubit.toggleLyricsVisibility,
                  ),
                PlayerIconActionButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: l10n.previous,
                  iconColor: state.hasPreviousNeighbour
                      ? primaryInk
                      : secondaryInk.withValues(alpha: 0.36),
                  iconSize: 26,
                  onTap: state.hasPreviousNeighbour ? cubit.previous : null,
                ),
                _MilkdropPlayPauseButton(
                  isPlaying: state.isPlaying,
                  activeColor: activeColor,
                  isCompact: isCompact,
                  onTap: cubit.togglePlayPause,
                ),
                PlayerIconActionButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: l10n.next,
                  iconColor: state.hasNextNeighbour
                      ? primaryInk
                      : secondaryInk.withValues(alpha: 0.36),
                  iconSize: 26,
                  onTap: state.hasNextNeighbour ? cubit.next : null,
                ),
                if (isInSplitView)
                  PlayerIconActionButton(
                    icon: repeatIcon,
                    tooltip: repeatLabel,
                    isActive: state.repeatMode != PlayerRepeatMode.off,
                    activeColor: activeColor,
                    iconColor: secondaryInk,
                    iconSize: 19,
                    showActiveDot: true,
                    onTap: cubit.toggleRepeat,
                  )
                else
                  PlayerIconActionButton(
                    icon: Icons.queue_music_rounded,
                    tooltip: l10n.queue,
                    isActive: state.isQueueVisible,
                    activeColor: activeColor,
                    iconColor: secondaryInk,
                    iconSize: 21,
                    showActiveDot: true,
                    onTap: cubit.toggleQueueVisibility,
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (allowBlur) {
      capsule = ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: capsule,
        ),
      );
    }

    return capsule;
  }
}

class _MilkdropPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final Color activeColor;
  final bool isCompact;
  final VoidCallback onTap;

  const _MilkdropPlayPauseButton({
    required this.isPlaying,
    required this.activeColor,
    required this.isCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final double size = isCompact ? AppSpacing.minTouchTarget : 52.0;

    return Semantics(
      button: true,
      label: isPlaying ? l10n.pause : l10n.play,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activeColor,
          boxShadow: [
            BoxShadow(
              color: activeColor.withValues(alpha: 0.42),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: AppColors.fadeStopTransparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              PulsrHaptics.lightImpact();
              onTap();
            },
            child: Center(
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 28,
                color: AppColors.textOnAccent(activeColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive slim progress bar strictly scoped to
/// `BlocSelector<PlayerCubit, PlayerState, Duration>`.
class _MilkdropProgressBar extends StatefulWidget {
  final Duration duration;
  final Color activeColor;
  final Color primaryInk;
  final Color secondaryInk;
  final bool isBuffering;
  final bool isCompact;
  final ValueChanged<Duration> onSeek;

  const _MilkdropProgressBar({
    required this.duration,
    required this.activeColor,
    required this.primaryInk,
    required this.secondaryInk,
    required this.isBuffering,
    required this.isCompact,
    required this.onSeek,
  });

  @override
  State<_MilkdropProgressBar> createState() => _MilkdropProgressBarState();
}

class _MilkdropProgressBarState extends State<_MilkdropProgressBar> {
  double? _dragMs;

  Duration _clampDuration(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (d > widget.duration) return widget.duration;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocSelector<PlayerCubit, PlayerState, Duration>(
      selector: (s) => s.position,
      builder: (context, position) {
        final double maxMs = widget.duration.inMilliseconds.toDouble();
        final double safeMax = maxMs > 0 ? maxMs : 1.0;
        final double effectiveMs =
            (_dragMs ?? position.inMilliseconds.toDouble()).clamp(0.0, safeMax);
        final Duration displayPos = _dragMs != null
            ? Duration(milliseconds: _dragMs!.round())
            : position;

        String formatPair(Duration d) =>
            '${Formatters.formatDuration(d)} / ${Formatters.formatDuration(widget.duration)}';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Formatters.formatDuration(displayPos),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: _dragMs != null
                        ? widget.primaryInk
                        : widget.secondaryInk,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  slider: true,
                  label: l10n.seekLabel,
                  value: formatPair(displayPos),
                  increasedValue: formatPair(
                    _clampDuration(displayPos + const Duration(seconds: 10)),
                  ),
                  decreasedValue: formatPair(
                    _clampDuration(displayPos - const Duration(seconds: 10)),
                  ),
                  onIncrease: widget.isBuffering
                      ? null
                      : () => widget.onSeek(
                            _clampDuration(
                              displayPos + const Duration(seconds: 10),
                            ),
                          ),
                  onDecrease: widget.isBuffering
                      ? null
                      : () => widget.onSeek(
                            _clampDuration(
                              displayPos - const Duration(seconds: 10),
                            ),
                          ),
                  excludeSemantics: true,
                  child: SizedBox(
                    height: widget.isCompact ? 24.0 : 28.0,
                    child: PulsrSlider(
                      value: effectiveMs,
                      min: 0.0,
                      max: safeMax,
                      height: widget.isCompact ? 24.0 : 28.0,
                      activeColor: widget.activeColor,
                      inactiveColor: AppColors.specularAt(0.22),
                      thumbColor: widget.primaryInk,
                      sliderStyle: PlayerSliderStyle.capsule,
                      isWavy: false,
                      animateWave: false,
                      onChangeStart: widget.isBuffering
                          ? null
                          : (val) {
                              PulsrHaptics.selectionClick();
                              setState(() => _dragMs = val);
                            },
                      onChanged: widget.isBuffering
                          ? (_) {}
                          : (val) => setState(() => _dragMs = val),
                      onChangeEnd: widget.isBuffering
                          ? null
                          : (val) {
                              widget.onSeek(Duration(milliseconds: val.round()));
                              setState(() => _dragMs = null);
                            },
                      onChangeCancel: () => setState(() => _dragMs = null),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Formatters.formatDuration(widget.duration),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: widget.secondaryInk,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
