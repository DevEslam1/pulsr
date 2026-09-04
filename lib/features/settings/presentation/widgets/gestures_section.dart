// lib/features/settings/presentation/widgets/gestures_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'settings_section.dart';
import 'settings_tiles.dart';

/// Mini-player swipe gestures and Now Playing touch actions.
class GesturesSection extends StatelessWidget {
  final SettingsState state;

  const GesturesSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    return SettingsSection(
      icon: Icons.swipe_rounded,
      title: context.l10n.gestures,
      children: [
        SettingsNavTile(
            Icons.swipe_left_rounded,
            context.l10n.miniPlayerSwipeLeft,
            _getMiniPlayerSwipeTitle(state.miniPlayerSwipeLeft),
            onTap: () => _showMiniPlayerSwipePickerSheet(
                context, cubit,
                isLeft: true,
                currentAction: state.miniPlayerSwipeLeft)),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.swipe_right_rounded,
            context.l10n.miniPlayerSwipeRight,
            _getMiniPlayerSwipeTitle(state.miniPlayerSwipeRight),
            onTap: () => _showMiniPlayerSwipePickerSheet(
                context, cubit,
                isLeft: false,
                currentAction: state.miniPlayerSwipeRight)),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.touch_app_rounded,
            context.l10n.nowPlayingDoubleTap,
            _getNowPlayingDoubleTapTitle(state.nowPlayingDoubleTap),
            onTap: () => _showNowPlayingDoubleTapPickerSheet(
                context, cubit, state.nowPlayingDoubleTap)),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.gesture_rounded,
            context.l10n.artworkSwipe,
            _getNowPlayingArtworkSwipeTitle(state.nowPlayingArtworkSwipe),
            onTap: () => _showNowPlayingArtworkSwipePickerSheet(
                context, cubit, state.nowPlayingArtworkSwipe)),
      ],
    );
  }

  String _getMiniPlayerSwipeTitle(MiniPlayerSwipeAction action) {
    switch (action) {
      case MiniPlayerSwipeAction.next:
        return 'Next Track';
      case MiniPlayerSwipeAction.prev:
        return 'Previous Track';
      case MiniPlayerSwipeAction.volume:
        return 'Adjust Volume';
      case MiniPlayerSwipeAction.none:
        return 'Disabled';
    }
  }

  String _getNowPlayingDoubleTapTitle(NowPlayingDoubleTapAction action) {
    switch (action) {
      case NowPlayingDoubleTapAction.toggleFavorite:
        return 'Toggle Favorite';
      case NowPlayingDoubleTapAction.toggleLyrics:
        return 'Toggle Lyrics';
      case NowPlayingDoubleTapAction.none:
        return 'Disabled';
    }
  }

  String _getNowPlayingArtworkSwipeTitle(NowPlayingArtworkSwipeAction action) {
    switch (action) {
      case NowPlayingArtworkSwipeAction.nextPrev:
        return 'Next / Previous Track';
      case NowPlayingArtworkSwipeAction.none:
        return 'Disabled';
    }
  }

  void _showMiniPlayerSwipePickerSheet(
    BuildContext context,
    SettingsCubit cubit, {
    required bool isLeft,
    required MiniPlayerSwipeAction currentAction,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor =
        Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
        context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
        context.palette.textSecondary;

    final options = [
      (
        action: MiniPlayerSwipeAction.next,
        title: 'Next Track',
        subtitle: 'Skip to the next song in the queue',
        icon: Icons.skip_next_rounded,
      ),
      (
        action: MiniPlayerSwipeAction.prev,
        title: 'Previous Track',
        subtitle: 'Skip to the previous song or restart track',
        icon: Icons.skip_previous_rounded,
      ),
      (
        action: MiniPlayerSwipeAction.volume,
        title: 'Adjust Volume',
        subtitle: isLeft ? 'Lower playback volume' : 'Raise playback volume',
        icon: isLeft ? Icons.volume_down_rounded : Icons.volume_up_rounded,
      ),
      (
        action: MiniPlayerSwipeAction.none,
        title: 'Disabled',
        subtitle: 'Ignore swipe gesture',
        icon: Icons.block_rounded,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                isLeft
                    ? 'MiniPlayer Swipe Left Action'
                    : 'MiniPlayer Swipe Right Action',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.action == currentAction;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.12)
                      : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon,
                        color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      if (isLeft) {
                        cubit.setMiniPlayerSwipeLeft(opt.action);
                      } else {
                        cubit.setMiniPlayerSwipeRight(opt.action);
                      }
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showNowPlayingDoubleTapPickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    NowPlayingDoubleTapAction currentAction,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor =
        Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
        context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
        context.palette.textSecondary;

    final options = [
      (
        action: NowPlayingDoubleTapAction.toggleFavorite,
        title: 'Toggle Favorite',
        subtitle: 'Add or remove active song from favorites',
        icon: Icons.favorite_rounded,
      ),
      (
        action: NowPlayingDoubleTapAction.toggleLyrics,
        title: 'Toggle Lyrics',
        subtitle: 'Show or hide synchronized lyrics overlay',
        icon: Icons.lyrics_rounded,
      ),
      (
        action: NowPlayingDoubleTapAction.none,
        title: 'Disabled',
        subtitle: 'Ignore double-tap gesture',
        icon: Icons.block_rounded,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Now Playing Double-Tap Action',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.action == currentAction;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.12)
                      : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon,
                        color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setNowPlayingDoubleTap(opt.action);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showNowPlayingArtworkSwipePickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    NowPlayingArtworkSwipeAction currentAction,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor =
        Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
        context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
        context.palette.textSecondary;

    final options = [
      (
        action: NowPlayingArtworkSwipeAction.nextPrev,
        title: 'Next / Previous Track',
        subtitle: 'Swipe left for next track, swipe right for previous track',
        icon: Icons.swipe_rounded,
      ),
      (
        action: NowPlayingArtworkSwipeAction.none,
        title: 'Disabled',
        subtitle: 'Ignore horizontal swipe on album artwork',
        icon: Icons.block_rounded,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Now Playing Artwork Swipe',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.action == currentAction;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.12)
                      : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon,
                        color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setNowPlayingArtworkSwipe(opt.action);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
