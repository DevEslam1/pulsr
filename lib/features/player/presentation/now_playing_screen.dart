// lib/features/player/presentation/now_playing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/gesture_hint_overlay.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'themes/player_theme.dart';
import 'themes/theme_registry.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late final PlayerCubit _playerCubit;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    _playerCubit = context.read<PlayerCubit>();
    _playerCubit.resetOverlayViews();
  }

  @override
  void dispose() {
    _playerCubit.resetOverlayViews();
    super.dispose();
  }

  void _safePop(BuildContext context) {
    if (_isPopping) return;
    _isPopping = true;
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
          PlayerThemeMode playerThemeMode
        })>((c) => (
          dynamicThemingEnabled: c.state.dynamicThemingEnabled,
          customAccentColor: c.state.customAccentColor,
          playerThemeMode: c.state.playerThemeMode,
        ));

    return BlocConsumer<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) => prev.differsFromBeyondPosition(curr),
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
            DynamicThemeCubit,
            ({Color primaryColor, Color backgroundColor})>((c) => (
              primaryColor: c.state.primaryColor,
              backgroundColor: c.state.backgroundColor,
            ));

        final activeColor = settingsConfig.dynamicThemingEnabled
            ? dynamicThemeConfig.primaryColor
            : settingsConfig.customAccentColor;
        final isDark =
            Theme.of(context).brightness == Brightness.dark;
        final bgColor = settingsConfig.dynamicThemingEnabled
            ? dynamicThemeConfig.backgroundColor
            : (isDark
                ? AppColors.darkSurface
                : Theme.of(context).colorScheme.surface);

        final props = PlayerThemeProps(
          state: state,
          cubit: cubit,
          activeColor: activeColor,
          bgColor: bgColor,
        );

        final themeWidget = ThemeRegistry.build(settingsConfig.playerThemeMode, props);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _safePop(context);
          },
          child: Scaffold(
            backgroundColor: bgColor,
            body: _SwipeDownToDismiss(
              onDismiss: () => _safePop(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: context.isLandscape
                        ? (context.isTablet ? 1160.0 : 960.0)
                        : (context.isTablet ? 780.0 : 560.0),
                  ),
                  child: Stack(
                    children: [
                      AnimatedSwitcher(
                        duration: context.motionMs(350),
                        switchInCurve:
                            context.motionCurve(Curves.easeInOutCubic),
                        switchOutCurve:
                            context.motionCurve(Curves.easeInOutCubic),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: KeyedSubtree(
                          key: ValueKey(settingsConfig.playerThemeMode),
                          child: themeWidget,
                        ),
                      ),
                      const _NowPlayingGestureHintOverlay(),
                    ],
                  ),
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

  const _SwipeDownToDismiss({
    required this.child,
    required this.onDismiss,
  });

  @override
  State<_SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<_SwipeDownToDismiss>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final CurvedAnimation _curvedAnimation;
  late final Tween<double> _tween;
  late Animation<double> _anim;
  double _dragOffset = 0.0;
  final Set<int> _activePointerIds = <int>{};
  bool get _singleTouch => _activePointerIds.length <= 1;

  @override
  void didUpdateWidget(covariant _SwipeDownToDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    // H-10: Clean stale pointers on rebuild when idle
    if (_dragOffset == 0.0 && !_animController.isAnimating) {
      _activePointerIds.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _curvedAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _tween = Tween<double>(begin: 0.0, end: 0.0);
    _anim = _tween.animate(_curvedAnimation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animController.duration = context.motionMs(240);
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
    if (!_singleTouch) return;
    _animController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_singleTouch) return;
    if (details.primaryDelta != null) {
      final newOffset = _dragOffset + details.primaryDelta!;
      if (newOffset >= 0) {
        setState(() {
          _dragOffset = newOffset;
        });
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_singleTouch) {
      // Second finger joined mid-gesture — snap back instead of dismissing.
      if (_dragOffset > 0) {
        _tween.begin = _dragOffset;
        _tween.end = 0.0;
        _animController.forward(from: 0.0);
      }
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 100 || velocity > 450) {
      widget.onDismiss();
    } else if (_dragOffset > 0) {
      _tween.begin = _dragOffset;
      _tween.end = 0.0;
      _animController.forward(from: 0.0);
    }
  }

  void _onVerticalDragCancel() {
    _activePointerIds.clear();
    if (_dragOffset > 0) {
      _tween.begin = _dragOffset;
      _tween.end = 0.0;
      _animController.forward(from: 0.0);
    }
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
      child: Listener(
        onPointerDown: (e) => _activePointerIds.add(e.pointer),
        onPointerUp: (e) => _activePointerIds.remove(e.pointer),
        onPointerCancel: (e) => _activePointerIds.remove(e.pointer),
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
              // Only introduce the (saveLayer-backed) opacity layer while a
              // dismiss drag is actually in progress.
              final content = progress > 0.0
                  ? Opacity(
                      opacity: (1.0 - progress * 0.4).clamp(0.0, 1.0),
                      child: child,
                    )
                  : child;
              return Transform.translate(
                offset: Offset(0, offset),
                child: content,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NowPlayingGestureHintOverlay extends StatelessWidget {
  const _NowPlayingGestureHintOverlay();

  @override
  Widget build(BuildContext context) {
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
