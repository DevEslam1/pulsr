// lib/features/player/presentation/themes/player_theme.dart
import 'package:flutter/material.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

/// Stable per-theme Hero tag for the full-screen artwork. Using one shared tag
/// meant two themes coexisting during the AnimatedSwitcher crossfade could
/// collide ("multiple heroes share the same tag") if a route transition began
/// mid-fade.
String nowPlayingArtHeroTag(PlayerThemeMode mode) =>
    'now_playing_art_${mode.name}';

class PlayerThemeProps {
  final PlayerState state;
  final PlayerCubit cubit;
  final Color activeColor;
  final Color bgColor;
  final String heroTag;

  const PlayerThemeProps({
    required this.state,
    required this.cubit,
    required this.activeColor,
    required this.bgColor,
    this.heroTag = 'now_playing_art_full',
  });

  PlayerThemeProps copyWith({String? heroTag}) => PlayerThemeProps(
        state: state,
        cubit: cubit,
        activeColor: activeColor,
        bgColor: bgColor,
        heroTag: heroTag ?? this.heroTag,
      );
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
