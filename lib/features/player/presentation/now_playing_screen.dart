// lib/features/player/presentation/now_playing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
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

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsCubit>().state;

    return BlocConsumer<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) => prev.currentSong?.id != curr.currentSong?.id,
      listener: (context, state) {
        final song = state.currentSong;
        // Read fresh SettingsCubit state to avoid stale closure (was capturing build's settingsState)
        final themeSource = context.read<SettingsCubit>().state.themeColorSource;
        if (song != null && themeSource == ThemeColorSource.artwork) {
          context.read<DynamicThemeCubit>().updateFromSong(song);
        }
      },
      // Skip rebuilds for position-only ticks (~5x/sec while playing). The
      // widgets that truly need live position (seek bar, lyrics highlight)
      // subscribe to it themselves via BlocSelector, so the visual output per
      // tick is unchanged — only the rebuild scope shrinks to the leaves.
      buildWhen: (prev, curr) => curr.differsFromBeyondPosition(prev),
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final dynamicTheme = context.watch<DynamicThemeCubit>().state;

        final activeColor = settingsState.dynamicThemingEnabled
            ? dynamicTheme.primaryColor
            : settingsState.customAccentColor;
        final bgColor = settingsState.dynamicThemingEnabled
            ? dynamicTheme.backgroundColor
            : const Color(0xFF14172B);

        final props = PlayerThemeProps(
          state: state,
          cubit: cubit,
          activeColor: activeColor,
          bgColor: bgColor,
        );

        Widget themeWidget;
        switch (settingsState.playerThemeMode) {
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
                    maxWidth: MediaQuery.orientationOf(context) ==
                            Orientation.landscape
                        ? 960
                        : 560,
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: themeWidget,
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
  late Animation<double> _fade;
  double _dragOffset = 0.0;
  bool _dragging = false;

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
    _fade = const AlwaysStoppedAnimation<double>(1.0);
    // The controller drives the release animation: the listener only records
    // the value — the translate/fade below are driven by the animation itself,
    // so there is no setState (and no full-screen rebuild) per tick.
    _animController.addListener(() {
      _dragOffset = _anim.value;
    });
  }

  @override
  void dispose() {
    _curvedAnimation.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta != null) {
      final newOffset = _dragOffset + details.primaryDelta!;
      if (newOffset >= 0) {
        _dragging = true;
        setState(() {
          _dragOffset = newOffset;
        });
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 100 || velocity > 450) {
      widget.onDismiss();
    } else if (_dragOffset > 0) {
      _anim =
          Tween<double>(begin: _dragOffset, end: 0.0).animate(_curvedAnimation);
      _fade = Tween<double>(
              begin: _fadeFor(_dragOffset, MediaQuery.sizeOf(context).height),
              end: 1.0)
          .animate(_curvedAnimation);
      _animController.forward(from: 0.0);
    }
  }

  /// Same fade curve as before: opacity = 1 - dragProgress * 0.4.
  double _fadeFor(double offset, double screenHeight) {
    final progress = (offset / screenHeight).clamp(0.0, 1.0);
    return (1.0 - progress * 0.4).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final offset = _dragging ? _dragOffset : _anim.value;
          return Transform.translate(
            offset: Offset(0, offset),
            child: FadeTransition(
              opacity: _dragging
                  ? AlwaysStoppedAnimation<double>(
                      _fadeFor(offset, screenHeight))
                  : _fade,
              child: child!,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
