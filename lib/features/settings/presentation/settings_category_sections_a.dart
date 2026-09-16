part of 'settings_screen.dart';

mixin SettingsCategorySectionsA on State<SettingsScreen> {
  Widget _buildAppearanceSection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.themeAndAppearance,
      context.l10n.settingsAppearanceSectionSubtitle,
      [
        // Theme selector segment
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.themeModeLabel,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return p.accent.withValues(alpha: 0.18);
                      }
                      return Colors.transparent;
                    }),
                    side: WidgetStatePropertyAll(
                      BorderSide(color: p.hairline),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: AppThemeMode.system,
                      label: Text(
                        context.l10n.systemDefault,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: state.themeMode == AppThemeMode.system
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.brightness_auto_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.light,
                      label: Text(
                        context.l10n.themeLight,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: state.themeMode == AppThemeMode.light
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.light_mode_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.dark,
                      label: Text(
                        context.l10n.themeDark,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: state.themeMode == AppThemeMode.dark
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.dark_mode_rounded, size: 15),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.amoled,
                      label: Text(
                        context.l10n.amoledLabel,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: state.themeMode == AppThemeMode.amoled
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.contrast_rounded, size: 15),
                    ),
                  ],
                  selected: {state.themeMode},
                  onSelectionChanged: (sel) => cubit.setThemeMode(sel.first),
                ),
              ),
            ],
          ),
        ),

        // Accent Color Palette
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.accentColor,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.hairline),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: AppColors.customAccents.map((color) {
                    final isSelected =
                        state.customAccentColorValue == color.toARGB32();
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => cubit.setCustomAccentColor(color),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? p.textPrimary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 22,
                                  color: color.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        _divider(p),
        _switchTile(
          context,
          Icons.nightlight_round,
          context.l10n.settingsAutoDarkModeTitle,
          context.l10n.settingsAutoDarkModeSubtitle,
          value: state.autoThemeByTime,
          onChanged: cubit.setAutoThemeByTime,
        ),
        _divider(p),
        _switchTile(
          context,
          Icons.contrast_rounded,
          context.l10n.settingsHighContrastTitle,
          context.l10n.settingsHighContrastSubtitle,
          value: state.highContrast,
          onChanged: cubit.setHighContrast,
        ),
        _divider(p),
        _switchTile(
          context,
          Icons.motion_photos_off_rounded,
          context.l10n.settingsReduceMotionTitle,
          context.l10n.settingsReduceMotionSubtitle,
          value: state.reduceMotion,
          onChanged: cubit.setReduceMotion,
        ),
        _divider(p),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.blur_on_rounded, size: 22, color: p.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (_) {
                            final title = context.l10n.settingsLiquidGlassTitle;
                            return Text(
                              title,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (_) {
                            final subtitle =
                                context.l10n.settingsLiquidGlassSubtitle;
                            return Text(
                              subtitle,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12.5,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(state.liquidGlassTint * 100).round()}%',
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: p.accent,
                  inactiveTrackColor: p.accent.withValues(alpha: 0.15),
                  thumbColor: p.accent,
                  overlayColor: p.accent.withValues(alpha: 0.12),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: state.liquidGlassTint,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  onChanged: cubit.setLiquidGlassTint,
                ),
              ),
            ],
          ),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.art_track_rounded,
          context.l10n.nowPlayingTheme,
          getThemeModeTitle(state.playerThemeMode, context.l10n),
          trailingBadge: context.l10n.settingsBadgeStyle,
          onTap: () =>
              showThemePickerSheet(context, cubit, state.playerThemeMode),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.graphic_eq_rounded,
          context.l10n.visualizerStyle,
          getVisualizerStyleTitle(state.visualizerStyle, context.l10n),
          trailingBadge: context.l10n.settingsBadgeDsp,
          onTap: () => showVisualizerStylePickerSheet(
              context, cubit, state.visualizerStyle),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.palette_outlined,
          context.l10n.colorSource,
          getColorSourceTitle(state.themeColorSource, context.l10n),
          trailingBadge: context.l10n.settingsBadgePalette,
          onTap: () => showColorSourcePickerSheet(
              context, cubit, state.themeColorSource),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.language_rounded,
          context.l10n.language,
          getLanguageTitle(state.languageCode, context.l10n),
          trailingBadge: state.languageCode.toUpperCase(),
          onTap: () =>
              showLanguagePickerSheet(context, cubit, state.languageCode),
        ),
      ],
      key: _catById('appearance').key,
    );
  }

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
          getNowPlayingArtworkSwipeTitle(state.nowPlayingArtworkSwipe, context.l10n),
          onTap: () => showNowPlayingArtworkSwipePickerSheet(
            context,
            cubit,
            state.nowPlayingArtworkSwipe,
          ),
        ),
      ],
      key: _catById('gestures').key,
    );
  }

  Widget _buildLibrarySection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.libraryAndScanning,
      context.l10n.settingsLibrarySectionSubtitle,
      [
        _navTile(
          context,
          Icons.folder_off_rounded,
          context.l10n.hiddenAndExcludedFolders,
          state.autoHideSystemMedia
              ? context.l10n.autoFilteringVoiceMemos
              : context.l10n.manageExcludedDirectories,
          onTap: () => context.push('/hidden-folders'),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.refresh_rounded,
          state.isScanning
              ? context.l10n.scanningStorage
              : context.l10n.rescanLibrary,
          state.scanResultCount != null
              ? context.l10n.lastScanTracks(state.scanResultCount!)
              : context.l10n.scanDeviceStorageForAudio,
          trailing: state.isScanning
              ? StreamBuilder<double>(
                  stream: cubit.scanProgress,
                  initialData: 0.0,
                  builder: (context, snapshot) {
                    final progress = (snapshot.data ?? 0.0).clamp(0.0, 1.0);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(progress * 100).round()}%',
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                )
              : null,
          onTap: state.isScanning ? () {} : () => cubit.rescanLibrary(),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.filter_list_rounded,
          context.l10n.shortAudioFilter,
          context.l10n.ignoreFilesUnder(state.minDurationSec),
          trailingBadge: '${state.minDurationSec}s',
          onTap: () =>
              _showDurationFilterDialog(context, cubit, state.minDurationSec),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.cleaning_services_rounded,
          context.l10n.removeMissingFiles,
          context.l10n.removeMissingFilesSubtitle,
          onTap: () => _removeMissingFiles(context, cubit),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.image_search_rounded,
          context.l10n.fetchMissingArtworkTooltip,
          context.l10n.fetchMissingArtworkBody,
          onTap: () => _fetchMissingArtwork(context),
        ),
      ],
      key: _catById('library').key,
    );
  }
















































  // Requires: provided by the composing class (same library).
  _Category _catById(String id);

  // Requires: provided by the composing class (same library).
  Widget _divider(PulsrPalette p);

  // Requires: provided by the composing class (same library).
  Future<void> _fetchMissingArtwork(BuildContext context);

  // Requires: provided by the composing class (same library).
  Widget _navTile( BuildContext context, IconData icon, String title, String subtitle, { Widget? trailing, String? trailingBadge, VoidCallback? onTap, });

  // Requires: provided by the composing class (same library).
  Future<void> _removeMissingFiles( BuildContext context, SettingsCubit cubit, );

  // Requires: provided by the composing class (same library).
  Widget _section( BuildContext context, String title, String subtitle, List<Widget> children, { GlobalKey? key, });

  // Requires: provided by the composing class (same library).
  void _showDurationFilterDialog( BuildContext context, SettingsCubit cubit, int currentSec, );

  // Requires: provided by the composing class (same library).
  Widget _switchTile( BuildContext context, IconData icon, String title, String subtitle, { required bool value, required ValueChanged<bool> onChanged, });
}
