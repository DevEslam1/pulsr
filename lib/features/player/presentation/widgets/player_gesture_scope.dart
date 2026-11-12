// lib/features/player/presentation/widgets/player_gesture_scope.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';

/// Centralized gesture handler wrapping artwork / stage in player themes.
///
/// Implements:
/// - Single tap: toggle lyrics visibility (or custom onTap).
/// - Double tap: honors [NowPlayingDoubleTapAction] (favorite, lyrics, none).
/// - Horizontal swipe: honors [NowPlayingArtworkSwipeAction] (next / prev track).
class PlayerGestureScope extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final HitTestBehavior behavior;

  const PlayerGestureScope({
    super.key,
    required this.child,
    this.onTap,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  Widget build(BuildContext context) {
    final (:nowPlayingDoubleTap, :nowPlayingArtworkSwipe) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
        })>(
      (c) => (
        nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
        nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
      ),
    );

    return GestureDetector(
      behavior: behavior,
      onTap: onTap ?? () => context.read<PlayerCubit>().toggleLyricsVisibility(),
      onDoubleTap: () {
        final cubit = context.read<PlayerCubit>();
        final song = cubit.state.currentSong;
        switch (nowPlayingDoubleTap) {
          case NowPlayingDoubleTapAction.toggleFavorite:
            if (song != null) {
              PulsrHaptics.selectionClick();
              cubit.toggleFavorite(song.id);
            }
            break;
          case NowPlayingDoubleTapAction.toggleLyrics:
            PulsrHaptics.selectionClick();
            cubit.toggleLyricsVisibility();
            break;
          case NowPlayingDoubleTapAction.none:
            break;
        }
      },
      onHorizontalDragEnd: (details) {
        if (nowPlayingArtworkSwipe != NowPlayingArtworkSwipeAction.nextPrev) return;
        final velocity = details.primaryVelocity;
        if (velocity == null) return;

        final cubit = context.read<PlayerCubit>();
        if (velocity < -200) {
          PulsrHaptics.lightImpact();
          cubit.next();
        } else if (velocity > 200) {
          PulsrHaptics.lightImpact();
          cubit.previous();
        }
      },
      child: child,
    );
  }
}
