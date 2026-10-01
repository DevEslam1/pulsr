// lib/features/player/presentation/themes/player_theme.dart
import 'package:flutter/material.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class PlayerThemeProps {
  final PlayerState state;
  final PlayerCubit cubit;
  final Color activeColor;
  final Color bgColor;

  const PlayerThemeProps({
    required this.state,
    required this.cubit,
    required this.activeColor,
    required this.bgColor,
  });
}

/// InheritedWidget that signals whether a player theme is being rendered
/// inside the tablet split-view left pane (persistent artwork + controls).
class PlayerSplitViewScope extends InheritedWidget {
  final bool isInSplitView;

  const PlayerSplitViewScope({
    super.key,
    required this.isInSplitView,
    required super.child,
  });

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PlayerSplitViewScope>()
            ?.isInSplitView ??
        false;
  }

  @override
  bool updateShouldNotify(PlayerSplitViewScope oldWidget) =>
      isInSplitView != oldWidget.isInSplitView;
}

