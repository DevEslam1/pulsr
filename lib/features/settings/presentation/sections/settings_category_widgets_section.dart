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
  /// Normal/Professional switch rendered above the Studio/DSP disclosure in Sound.
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
      case 'sound':
        return [
          // A. Smart Audio (prominent, first)
          SettingsSection(
            isProminent: true,
            icon: Icons.auto_awesome_rounded,
            title: context.l10n.smartAudioTitle,
            subtitle: context.l10n.settingsSmartAudioSectionSubtitle,
            trailing: TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
              ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: Text(
                context.l10n.settingsSetUpSound,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () =>
                  AudioSetupWizardSheet.show(context, cubit: cubit),
            ),
            children: const [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                child: SmartAudioSection(),
              ),
            ],
          ),

          // B. Output Device Card (device-adaptive surface)
          _catSection(
            context,
            'sound',
            SettingsSection(
              icon: Icons.speaker_group_rounded,
              title: context.l10n.settingsHardwareAudioOutput,
              children: [
                DeviceAdaptiveOutputSection(
                  state: state,
                  onShowDspPreference: (sheetContext, cubit, pref) {
                    // Reuse existing dsp preference picker
                  },
                ),
              ],
            ),
          ),

          // C. Playback Behavior
          PlaybackSection(state: state),
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

          // D. Loudness & Gain
          AudioGainSection(state: state),

          // Experience Mode Placement (above Studio/DSP disclosure)
          _experienceModeCard(context),

          // E. Effects & DSP
          AudioEffectsDspSection(state: state),

          // F. Device Profiles & Automation (Professional only)
          if (state.isProfessional) ...[
            _section(
              context,
              context.l10n.deviceProfilesTitle,
              context.l10n.settingsDeviceProfilesSectionSubtitle,
              [
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.xs),
                  child: DeviceProfilesSection(),
                ),
              ],
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
            ),
          ],

          const CastSection(),
        ];

      case 'look':
        return [
          _buildAppearanceSection(context, state, cubit),
          _buildAccessibilitySection(context, state, cubit),
          _buildGesturesSection(context, state, cubit),
        ];

      case 'library':
        return [
          _buildLibrarySection(context, state, cubit),
          _section(
            context,
            context.l10n.storageAndCache,
            context.l10n.settingsStorageSectionSubtitle,
            [const StorageCacheSection()],
          ),
        ];

      case 'network':
        return [_buildOnlineSection(context, state, cubit)];

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
                Icons.tune_rounded,
                context.l10n.experienceModeTitle,
                state.isProfessional
                    ? context.l10n.experienceModeProfessional
                    : context.l10n.experienceModeNormal,
                onTap: () => showStudioExplainerSheet(context),
              ),
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
