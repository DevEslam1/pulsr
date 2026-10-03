part of '../settings_screen.dart';

mixin SettingsCategoryWidgetsSection
    on
        SettingsSectionPrimitives,
        SettingsCategoryMetadata,
        SettingsAppearanceSection,
        SettingsGesturesSection,
        SettingsLibrarySection,
        SettingsOnlineSection,
        SettingsPrivacyBackupSection,
        State<SettingsScreen> {
  /// Always-visible Normal/Professional switch shown at the top of Settings.
  Widget _experienceModeCard(BuildContext context) => _section(
        context,
        context.l10n.experienceModeTitle,
        context.l10n.experienceModeSubtitle,
        [
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
            child: ExperienceModeSection(),
          ),
        ],
      );

  List<Widget> _buildCategoryWidgets(
    BuildContext context,
    String catId,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final widgets = [
      ..._buildCategoryWidgetsInner(context, catId, state, cubit),
    ];
    final hidden = _studioControlCounts[catId];
    if (hidden != null && !state.isProfessional) {
      widgets.add(StudioBridgeFooter(hiddenControls: hidden));
    }
    return widgets;
  }

  List<Widget> _buildCategoryWidgetsInner(
    BuildContext context,
    String catId,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    switch (catId) {
      case 'audio':
        return [
          _section(
            context,
            context.l10n.smartAudioTitle,
            context.l10n.settingsSmartAudioSectionSubtitle,
            [
              const Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                child: SmartAudioSection(),
              ),
            ],
          ),
          _catSection(context, 'audio', AudioSoundSection(state: state)),
        ];
      case 'playback':
        return [
          _catSection(context, 'playback', PlaybackSection(state: state)),
          _section(
            context,
            context.l10n.quranMode,
            context.l10n.reciterDesc,
            [
              _navTile(
                context,
                Icons.menu_book_rounded,
                context.l10n.quranMode,
                context.l10n.settingsQuranModeSubtitle,
                onTap: () => context.push('/quran-mode'),
              ),
            ],
          ),
        ];
      case 'appearance':
        return [_buildAppearanceSection(context, state, cubit)];
      case 'gestures':
        return [_buildGesturesSection(context, state, cubit)];
      case 'profiles':
        // Professional-only surface; Smart Audio now lives in Audio & Sound.
        if (!state.isProfessional) return const [];
        return [
          _section(
            context,
            context.l10n.deviceProfilesTitle,
            context.l10n.settingsDeviceProfilesSectionSubtitle,
            [
              const Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                child: DeviceProfilesSection(),
              ),
            ],
            key: _catById('profiles').key,
          ),
          _section(
            context,
            context.l10n.automationRules,
            context.l10n.settingsAutomationSectionSubtitle,
            [
              _navTile(
                context,
                Icons.auto_awesome_rounded,
                context.l10n.automationRules,
                context.l10n.settingsAutomationTileSubtitle,
                onTap: () => showAutomationRulesSheet(context),
              ),
            ],
            key: _catById('automation').key,
          ),
        ];
      case 'library':
        return [_buildLibrarySection(context, state, cubit)];
      case 'online':
        return [_buildOnlineSection(context, state, cubit)];
      case 'storage':
        return [
          _section(
            context,
            context.l10n.storageAndCache,
            context.l10n.settingsStorageSectionSubtitle,
            [const StorageCacheSection()],
            key: _catById('storage').key,
          ),
        ];
      case 'privacy':
        return [
          if (AppConfig.isCloudSyncAllowed || AppConfig.ytmEnabled)
            const SettingsHeroCard(),
          _buildPrivacyBackupSection(context),
        ];
      case 'about':
        return [
          _section(
            context,
            context.l10n.about,
            context.l10n.settingsAboutSectionSubtitle,
            [
              _navTile(
                context,
                Icons.info_outline_rounded,
                context.l10n.appTitle,
                context.l10n.settingsAboutVersionSubtitle(AppConfig.appVersion),
                onTap: () => showAboutSheet(context),
              ),
              _navTile(
                context,
                Icons.new_releases_outlined,
                context.l10n.whatsNew,
                context.l10n.whatsNewSubtitle(AppConfig.appVersion),
                onTap: () => showWhatsNewSheet(context),
              ),
              _navTile(
                context,
                Icons.person_outline_rounded,
                context.l10n.developer,
                AppConfig.developerName,
                onTap: () => showAboutSheet(context),
              ),
            ],
            key: _catById('about').key,
          ),
        ];
      default:
        return [];
    }
  }
}
