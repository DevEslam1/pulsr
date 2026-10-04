part of '../settings_screen.dart';

mixin SettingsGesturesSection
    on
        SettingsSectionPrimitives,
        SettingsCategoryMetadata,
        State<SettingsScreen> {
  Widget _buildGesturesSection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.gestures,
      context.l10n.settingsGesturesSectionSubtitle,
      [
        _navTile(
          context,
          Icons.swipe_left_rounded,
          context.l10n.miniPlayerSwipeLeft,
          getMiniPlayerSwipeTitle(state.miniPlayerSwipeLeft, context.l10n),
          onTap: () => showMiniPlayerSwipePickerSheet(
            context,
            cubit,
            isLeft: true,
            currentAction: state.miniPlayerSwipeLeft,
          ),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.swipe_right_rounded,
          context.l10n.miniPlayerSwipeRight,
          getMiniPlayerSwipeTitle(state.miniPlayerSwipeRight, context.l10n),
          onTap: () => showMiniPlayerSwipePickerSheet(
            context,
            cubit,
            isLeft: false,
            currentAction: state.miniPlayerSwipeRight,
          ),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.touch_app_rounded,
          context.l10n.nowPlayingDoubleTap,
          getNowPlayingDoubleTapTitle(state.nowPlayingDoubleTap, context.l10n),
          onTap: () => showNowPlayingDoubleTapPickerSheet(
            context,
            cubit,
            state.nowPlayingDoubleTap,
          ),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.gesture_rounded,
          context.l10n.artworkSwipe,
          getNowPlayingArtworkSwipeTitle(
              state.nowPlayingArtworkSwipe, context.l10n),
          onTap: () => showNowPlayingArtworkSwipePickerSheet(
            context,
            cubit,
            state.nowPlayingArtworkSwipe,
          ),
        ),
      ],
    );
  }
}
