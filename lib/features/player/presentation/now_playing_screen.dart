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
import 'themes/circle_player_theme.dart';
import 'themes/classic_player_theme.dart';
import 'themes/minimal_player_theme.dart';
import 'themes/player_theme.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsCubit>().state;

    return BlocConsumer<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) => prev.currentSong?.id != curr.currentSong?.id,
      listener: (context, state) {
        final song = state.currentSong;
        if (song != null && settingsState.dynamicThemingEnabled) {
          context.read<DynamicThemeCubit>().updateFromSong(song);
        }
      },
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
              onDismiss: () => context.canPop() ? context.pop() : context.go('/'),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.orientationOf(context) == Orientation.landscape ? 960 : 560,
                  ),
                  child: themeWidget,
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
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
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
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 100 || velocity > 450) {
      widget.onDismiss();
    } else if (_dragOffset > 0) {
      final start = _dragOffset;
      final anim = Tween<double>(begin: start, end: 0.0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
      );
      anim.addListener(() {
        setState(() {
          _dragOffset = anim.value;
        });
      });
      _animController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(
          opacity: (1.0 - progress * 0.4).clamp(0.0, 1.0),
          child: widget.child,
        ),
      ),
    );
  }
}
