// lib/features/player/presentation/now_playing_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
import '../../../core/utils/adaptive.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'themes/card_player_theme.dart';
import 'themes/cassette_player_theme.dart';
import 'themes/circle_player_theme.dart';
import 'themes/classic_player_theme.dart';
import 'themes/lyrics_player_theme.dart';
import 'themes/minimal_player_theme.dart';
import 'themes/player_theme.dart';
import 'themes/vinyl_player_theme.dart';
import 'themes/waveform_player_theme.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  @override
  void initState() {
    super.initState();
    // Always default to Cover (Track) view when opening Now Playing screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlayerCubit>().resetOverlayViews();
      }
    });
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
                ? const Color(0xFF14172B)
                : Theme.of(context).colorScheme.surface);

        final props = PlayerThemeProps(
          state: state,
          cubit: cubit,
          activeColor: activeColor,
          bgColor: bgColor,
        );

        Widget themeWidget;
        switch (settingsConfig.playerThemeMode) {
          case PlayerThemeMode.classic:
            themeWidget = ClassicPlayerTheme(props: props);
            break;
          case PlayerThemeMode.card:
            themeWidget = CardPlayerTheme(props: props);
            break;
          case PlayerThemeMode.circle:
            themeWidget = CirclePlayerTheme(props: props);
            break;
          case PlayerThemeMode.minimal:
            themeWidget = MinimalPlayerTheme(props: props);
            break;
          case PlayerThemeMode.vinyl:
            themeWidget = VinylPlayerTheme(props: props);
            break;
          case PlayerThemeMode.cassette:
            themeWidget = CassettePlayerTheme(props: props);
            break;
          case PlayerThemeMode.waveform:
            themeWidget = WaveformPlayerTheme(props: props);
            break;
          case PlayerThemeMode.lyricsFocus:
            themeWidget = LyricsPlayerTheme(props: props);
            break;
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          child: Scaffold(
            backgroundColor: bgColor,
            body: _SwipeDownToDismiss(
              onDismiss: () =>
                  context.canPop() ? context.pop() : context.go('/'),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: context.isLandscape
                        ? (context.isTablet ? 1160.0 : 960.0)
                        : (context.isTablet ? 780.0 : 560.0),
                  ),
                  child: Stack(
                    children: [
                      themeWidget,
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
  late Animation<double> _anim;
  double _dragOffset = 0.0;
  int _activePointers = 0;
  bool get _singleTouch => _activePointers <= 1;

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
    _anim = Tween<double>(begin: 0.0, end: 0.0).animate(_curvedAnimation);
    _animController.addListener(() {
      setState(() {
        _dragOffset = _anim.value;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animController.duration = context.motionMs(240);
  }

  @override
  void dispose() {
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
        _anim = Tween<double>(begin: _dragOffset, end: 0.0)
            .animate(_curvedAnimation);
        _animController.forward(from: 0.0);
      }
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 100 || velocity > 450) {
      widget.onDismiss();
    } else if (_dragOffset > 0) {
      _anim =
          Tween<double>(begin: _dragOffset, end: 0.0).animate(_curvedAnimation);
      _animController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);

    // Only introduce the (saveLayer-backed) opacity layer while a dismiss drag
    // is actually in progress: at rest the subtree paints exactly as before.
    // The RepaintBoundary lets the compositor reuse the cached subtree layer
    // across drag frames instead of re-rasterising it per frame (A-16).
    final child = progress > 0.0
        ? Opacity(
            opacity: (1.0 - progress * 0.4).clamp(0.0, 1.0),
            child: RepaintBoundary(child: widget.child),
          )
        : widget.child;

    return Listener(
      onPointerDown: (_) => _activePointers++,
      onPointerUp: (_) => _activePointers = (_activePointers - 1).clamp(0, 10),
      onPointerCancel: (_) =>
          _activePointers = (_activePointers - 1).clamp(0, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: child,
        ),
      ),
    );
  }
}

class _NowPlayingGestureHintOverlay extends StatefulWidget {
  const _NowPlayingGestureHintOverlay();

  @override
  State<_NowPlayingGestureHintOverlay> createState() =>
      _NowPlayingGestureHintOverlayState();
}

class _NowPlayingGestureHintOverlayState
    extends State<_NowPlayingGestureHintOverlay> {
  static const String _prefKey = 'pulsr_gesture_hints_dismissed';
  bool _dismissed = true;
  bool _visible = false;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_prefKey) ?? false;
      if (!seen && mounted) {
        setState(() {
          _dismissed = false;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted && !_dismissed) {
          setState(() => _visible = true);
          _autoHideTimer = Timer(const Duration(seconds: 7), _dismiss);
        }
      }
    } catch (_) {}
  }

  Future<void> _dismiss() async {
    if (!mounted || _dismissed) return;
    setState(() => _visible = false);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _dismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final p = context.palette;
    final isTablet = context.isTablet;

    return Positioned(
      left: isTablet ? 32 : 16,
      right: isTablet ? 32 : 16,
      bottom: isTablet ? 120 : 76,
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: context.motionMs(300),
          curve: context.motionCurve(Curves.easeInOut),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (p.isDark ? const Color(0xFF161824) : Colors.white)
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: p.accent.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.15),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.touch_app_rounded,
                        color: p.accent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '↓ Pull down to close • ↔ Swipe art to skip',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
