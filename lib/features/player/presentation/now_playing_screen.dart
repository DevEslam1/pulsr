// lib/features/player/presentation/now_playing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/core/constants/app_colors.dart';

import '../../../core/motion/pulsr_motion.dart';
import '../../../core/services/system_ui_controller.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/gesture_hint_overlay.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'responsive_player_layout.dart';
import 'themes/player_theme.dart';
import 'themes/theme_registry.dart';
import 'widgets/canvas_backdrop.dart';

import '../../../core/utils/pulsr_haptics.dart';
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with WidgetsBindingObserver {
  late final PlayerCubit _playerCubit;
  bool _isPopping = false;
  Orientation? _lastAppliedOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerCubit = context.read<PlayerCubit>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (orientation != _lastAppliedOrientation) {
      _lastAppliedOrientation = orientation;
      _syncSystemUiForOrientation(orientation);
    }
  }

  void _syncSystemUiForOrientation(Orientation orientation) {
    final isLandscape = orientation == Orientation.landscape;
    SystemUiController.instance
        .syncMode(owner: 'now_playing', immersive: isLandscape);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lastAppliedOrientation != null) {
      _syncSystemUiForOrientation(_lastAppliedOrientation!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isPopping) {
      _playerCubit.resetOverlayViews();
    }
    SystemUiController.instance.releaseImmersive('now_playing');
    super.dispose();
  }

  void _safePop(BuildContext context) {
    if (_isPopping) return;
    _isPopping = true;
    _playerCubit.resetOverlayViews();
    try {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/');
      }
    } catch (_) {
      try {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    // Narrow subscriptions: only the fields this screen actually renders.
    // Watching the whole SettingsCubit / DynamicThemeCubit states rebuilt the
    // entire theme tree on any unrelated settings change (A-16).
    final settingsConfig = context.select<
        SettingsCubit,
        ({
          bool dynamicThemingEnabled,
          Color customAccentColor,
          PlayerThemeMode playerThemeMode,
          AppThemeMode themeMode,
          bool canvasEnabled,
          bool canvasAsBackdrop,
        })>((c) => (
          dynamicThemingEnabled: c.state.dynamicThemingEnabled,
          customAccentColor: c.state.customAccentColor,
          playerThemeMode: c.state.playerThemeMode,
          themeMode: c.state.themeMode,
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
        ));

    // Only the skeuomorphic themes paint the transport position into their
    // artwork (mechanical counter, platter ring, VU progress). The other five
    // themes get position from PlayerSeekBar's own selector, so rebuilding the
    // whole screen every second for them is pure waste.
    final needsPositionTick = switch (settingsConfig.playerThemeMode) {
      PlayerThemeMode.circle ||
      PlayerThemeMode.vinyl ||
      PlayerThemeMode.cassette ||
      PlayerThemeMode.cd =>
        true,
      _ => false,
    };

    return BlocConsumer<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.differsFromBeyondPosition(curr) ||
          (needsPositionTick &&
              prev.position.inSeconds != curr.position.inSeconds),
      listenWhen: (prev, curr) => prev.currentSong?.id != curr.currentSong?.id,
      listener: (context, state) {
        final song = state.currentSong;
        if (song != null && settingsConfig.dynamicThemingEnabled) {
          context.read<DynamicThemeCubit>().updateFromSong(song);
        }
      },
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final dynamicThemeConfig = context.select<
                DynamicThemeCubit, ({Color primaryColor, Color backgroundColor})>(
            (c) => (
                  primaryColor: c.state.primaryColor,
                  backgroundColor: c.state.backgroundColor,
                ));

        final activeColor = settingsConfig.dynamicThemingEnabled
            ? dynamicThemeConfig.primaryColor
            : settingsConfig.customAccentColor;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isAmoled = settingsConfig.themeMode == AppThemeMode.amoled;
        final isCleanOverlay =
            settingsConfig.playerThemeMode == PlayerThemeMode.clean &&
                (state.isLyricsVisible || state.isQueueVisible);
        final baseBgColor = isAmoled
            ? Colors.black
            : (settingsConfig.dynamicThemingEnabled
                ? dynamicThemeConfig.backgroundColor
                : (isDark
                    ? AppColors.darkSurface
                    : Theme.of(context).colorScheme.surface));
        final bgColor = isCleanOverlay
            ? (isAmoled
                ? Colors.black
                : (isDark ? context.palette.deepShade : baseBgColor))
            : baseBgColor;

        final props = PlayerThemeProps(
          state: state,
          cubit: cubit,
          activeColor: activeColor,
          bgColor: bgColor,
        );

        final themeWidget =
            ThemeRegistry.build(settingsConfig.playerThemeMode, props);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _safePop(context);
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: AnimatedContainer(
              duration: context.motionMs(420),
              curve: context.motionCurve(Curves.easeOutCubic),
              color: bgColor,
              child: _SwipeDownToDismiss(
                activeColor: activeColor,
                onDismiss: () => _safePop(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (settingsConfig.canvasEnabled &&
                        settingsConfig.canvasAsBackdrop)
                      Positioned.fill(
                        child: CanvasBackdrop(
                          song: state.currentSong,
                          isPlaying: state.isPlaying,
                          isBackdropMode: true,
                        ),
                      ),

                    // Subtle top status-bar protection vignette for legibility (portrait only)
                    if (MediaQuery.orientationOf(context) !=
                            Orientation.landscape &&
                        ((!state.isLyricsVisible && !state.isQueueVisible) ||
                            settingsConfig.playerThemeMode !=
                                PlayerThemeMode.clean))
                      PositionedDirectional(
                      top: 0,
                      start: 0,
                      end: 0,
                      height: 88,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black
                                    .withValues(alpha: isDark ? 0.28 : 0.08),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    ResponsivePlayerLayout(
                      state: state,
                      cubit: cubit,
                      themeWidget: AnimatedSwitcher(
                        duration: context.motionMs(380),
                        switchInCurve: context.motionCurve(Curves.easeOutCubic),
                        switchOutCurve: context.motionCurve(Curves.easeInCubic),
                        transitionBuilder: (child, animation) {
                          final scale = Tween<double>(
                            begin: 0.965,
                            end: 1.0,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: scale,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(settingsConfig.playerThemeMode),
                          child: themeWidget,
                        ),
                      ),
                      activeColor: activeColor,
                      bgColor: bgColor,
                    ),

                    const _NowPlayingGestureHintOverlay(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwipeDownToDismiss extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  final Color activeColor;

  const _SwipeDownToDismiss({
    required this.child,
    required this.onDismiss,
    required this.activeColor,
  });

  @override
  State<_SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<_SwipeDownToDismiss>
    with SingleTickerProviderStateMixin {
  static const double _dismissThreshold = 108.0;
  static const double _dismissVelocity = 450.0;

  late final AnimationController _animController;
  late final CurvedAnimation _curvedAnimation;
  late final Tween<double> _tween;
  late Animation<double> _anim;
  double _dragOffset = 0.0;

  /// BUG-01: only the vertical dismiss gesture owns this flag. The previous
  /// Listener-based pointer set counted taps on child buttons as extra
  /// pointers, silently disabling the dismiss gesture.
  bool _isDragging = false;
  bool _crossedThreshold = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: PulsrDurations.layout,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _tween = Tween<double>(begin: 0.0, end: 0.0);
    _anim = _tween.animate(_curvedAnimation);
    // BUG-12: once a snap-back finishes, the resting offset must return to 0
    // so the next drag does not begin from a stale offset.
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _dragOffset = 0.0;
          _crossedThreshold = false;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animController.duration = context.motionMs(260);
  }

  @override
  void dispose() {
    // FIX-H7: Stop controller before disposal (listener no longer attached).
    _animController.stop();
    _curvedAnimation.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isDragging) return;
    // BUG-12: if a snap-back was running, continue from the currently painted
    // offset instead of jumping back to the pre-animation drag value.
    if (_animController.isAnimating) {
      _dragOffset = _anim.value;
    }
    _animController.stop();
    // AUDIT-FIX: Neutralise tween endpoints when stopping mid-animation
    _tween.begin = _dragOffset;
    _tween.end = _dragOffset;
    _isDragging = true;
    _crossedThreshold = _dragOffset > _dismissThreshold;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final delta = details.primaryDelta;
    if (delta != null) {
      // Weighted physical resistance as the sheet pulls further down
      final resistance = (1.0 - (_dragOffset / 900.0)).clamp(0.62, 1.0);
      final newOffset = _dragOffset + (delta * resistance);
      if (newOffset >= 0) {
        final nowCrossed = newOffset > _dismissThreshold;
        if (nowCrossed != _crossedThreshold) {
          _crossedThreshold = nowCrossed;
          PulsrHaptics.selectionClick();
        }
        setState(() {
          _dragOffset = newOffset;
        });
      }
    }
  }

  // AUDIT-FIX: Extract snap-back helper ensuring tween endpoints are reset
  void _snapBack() {
    if (_dragOffset > 0) {
      _tween.begin = _dragOffset;
      _tween.end = 0.0;
      _animController.forward(from: 0.0);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > _dismissThreshold || velocity > _dismissVelocity) {
      PulsrHaptics.lightImpact();
      widget.onDismiss();
    } else {
      _snapBack();
    }
  }

  void _onVerticalDragCancel() {
    _isDragging = false;
    _snapBack();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    // M-02: Drive the dismiss animation through AnimatedBuilder instead of a
    // per-frame setState listener. Only the transform/opacity layer rebuilds;
    // the (RepaintBoundary-wrapped) child subtree is passed through unchanged.
    final boundChild = RepaintBoundary(child: widget.child);

    final dismissAction = CustomSemanticsAction(
      label: context.l10n.dismissPlayer,
    );

    return Semantics(
      customSemanticsActions: {
        dismissAction: widget.onDismiss,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        onVerticalDragCancel: _onVerticalDragCancel,
        child: AnimatedBuilder(
          animation: _animController,
          child: boundChild,
          builder: (context, child) {
            // While the controller runs, read the animated value; otherwise
            // fall back to the live drag offset.
            final offset =
                _animController.isAnimating ? _anim.value : _dragOffset;
            final progress = (offset / screenHeight).clamp(0.0, 1.0);
            if (progress <= 0.0) {
              return child!;
            }

            final thresholdRatio = (offset / _dismissThreshold).clamp(0.0, 1.0);
            final scale = (1.0 - progress * 0.055).clamp(0.94, 1.0);
            final radiusValue = (28.0 * thresholdRatio).clamp(0.0, 28.0);
            final topRadius = Radius.circular(radiusValue);

            return Transform.translate(
              offset: Offset(0, offset),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: topRadius,
                      topRight: topRadius,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (0.45 * thresholdRatio).clamp(0.0, 0.45),
                        ),
                        blurRadius: 32 * thresholdRatio,
                        spreadRadius: 2,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: topRadius,
                      topRight: topRadius,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: (1.0 - progress * 0.35).clamp(0.0, 1.0),
                          child: child,
                        ),
                        // Top specular rim & dynamic grab pill during pull-down
                        PositionedDirectional(
                          top: 0,
                          start: 0,
                          end: 0,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: thresholdRatio,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 1.2,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          AppColors.specularAt(0.32),
                                          widget.activeColor
                                              .withValues(alpha: 0.55),
                                          AppColors.specularAt(0.32),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedContainer(
                                    duration: context.motion(PulsrMotion.tap),
                                    width: _crossedThreshold ? 48 : 36,
                                    height: 4.5,
                                    decoration: BoxDecoration(
                                      color: _crossedThreshold
                                          ? widget.activeColor
                                          : AppColors.specularAt(0.42),
                                      borderRadius: BorderRadius.circular(99),
                                      boxShadow: _crossedThreshold
                                          ? [
                                              BoxShadow(
                                                color: widget.activeColor
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 8,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NowPlayingGestureHintOverlay extends StatelessWidget {
  const _NowPlayingGestureHintOverlay();

  @override
  Widget build(BuildContext context) {
    if (context.isLandscape) {
      return const SizedBox.shrink();
    }
    final isTablet = context.isTablet;
    return PositionedDirectional(
      start: isTablet ? 32 : 16,
      end: isTablet ? 32 : 16,
      bottom: isTablet ? 120 : 76,
      child: GestureHintOverlay(
        hintKey: 'now_playing_screen',
        message: context.l10n.nowPlayingSwipeHint,
        padding: EdgeInsets.zero,
      ),
    );
  }
}