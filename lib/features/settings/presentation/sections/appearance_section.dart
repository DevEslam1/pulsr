part of '../settings_screen.dart';

/// Segment order for the theme-mode [PulsrSegmentedControl]; the selected
/// index maps back to the mode on change.
const List<AppThemeMode> _themeModeOrder = [
  AppThemeMode.system,
  AppThemeMode.light,
  AppThemeMode.dark,
  AppThemeMode.amoled,
];

mixin SettingsAppearanceSection
    on
        SettingsSectionPrimitives,
        SettingsCategoryMetadata,
        State<SettingsScreen> {
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
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.themeModeLabel,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: AppTracking.overline,
                ),
              ),
              const SizedBox(height: AppSpacing.s10),
              SizedBox(
                width: double.infinity,
                child: PulsrSegmentedControl(
                  segments: [
                    PulsrSegment(
                      label: context.l10n.systemDefault,
                      icon: Icons.brightness_auto_rounded,
                    ),
                    PulsrSegment(
                      label: context.l10n.themeLight,
                      icon: Icons.light_mode_rounded,
                    ),
                    PulsrSegment(
                      label: context.l10n.themeDark,
                      icon: Icons.dark_mode_rounded,
                    ),
                    PulsrSegment(
                      label: context.l10n.amoledLabel,
                      icon: Icons.contrast_rounded,
                    ),
                  ],
                  selectedIndex: _themeModeOrder.indexOf(state.themeMode),
                  onChanged: (i) => cubit.setThemeMode(_themeModeOrder[i]),
                ),
              ),
            ],
          ),
        ),

        // Accent Color Palette
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
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
                      fontSize: AppFontSize.bodySmall,
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
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (final (index, color)
                        in AppColors.customAccents.indexed)
                      Builder(builder: (context) {
                        final isSelected =
                            state.customAccentColorValue == color.toARGB32();
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(
                              end: AppSpacing.sm),
                          child: Semantics(
                            button: true,
                            selected: isSelected,
                            label: '${context.l10n.accentColor} ${index + 1}',
                            child: GestureDetector(
                              onTap: () => cubit.setCustomAccentColor(color),
                              child: AnimatedContainer(
                                duration: context.motionMs(200),
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
                          ),
                        );
                      }),
                  ],
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
        if (state.autoThemeByTime) ...[
          const ThemeScheduleRow(),
          _divider(p),
        ],
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
          Icons.brightness_4_rounded,
          context.l10n.settingsDimWhitePointTitle,
          context.l10n.settingsDimWhitePointSubtitle,
          value: state.dimWhitePoint,
          onChanged: cubit.setDimWhitePoint,
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
        ValueListenableBuilder<bool>(
          valueListenable: SoundFeedbackService.enabledNotifier,
          builder: (context, soundEnabled, _) {
            return _switchTile(
              context,
              Icons.volume_up_rounded,
              'UI Sound Effects',
              'Play subtle audio feedback for interactions',
              value: soundEnabled,
              onChanged: (val) => SoundFeedbackService.setEnabled(val),
            );
          },
        ),
        _divider(p),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.blur_on_rounded, size: 22, color: p.accent),
                  const SizedBox(width: AppSpacing.s14),
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
                                fontSize: AppFontSize.callout,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Builder(
                          builder: (_) {
                            final subtitle =
                                context.l10n.settingsLiquidGlassSubtitle;
                            return Text(
                              subtitle,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.label,
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
                      fontSize: AppFontSize.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
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
        ValueListenableBuilder<DockStackMode>(
          valueListenable: DockStyleController.mode,
          builder: (context, dockMode, _) => _navTile(
            context,
            Icons.vertical_align_bottom_rounded,
            context.l10n.dockStyleTitle,
            dockStyleName(context, dockMode),
            trailingBadge: context.l10n.settingsBadgeStyle,
            onTap: () => DockStylePickerSheet.show(
              context,
              current: dockMode,
              onSelected: DockStyleController.set,
            ),
          ),
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
}
