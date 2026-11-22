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
    final stateObj = this as SettingsScreenState;
    switch (catId) {
      case 'sound':
        return [
          // A. Smart Audio (prominent, first)
          KeyedSubtree(
            key: stateObj._sectionKeyFor('smart_audio'),
            child: SettingsSection(
              isProminent: true,
              icon: Icons.auto_awesome_rounded,
              title: context.l10n.smartAudioTitle,
              subtitle: context.l10n.settingsSmartAudioSectionSubtitle,
              trailing: TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    AppSpacing.minTouchTarget,
                    AppSpacing.minTouchTarget,
                  ),
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
                  padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md,
                      AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                  child: SmartAudioSection(),
                ),
              ],
            ),
          ),

          // A2. Reset Audio Engine to Recommended Guardrail
          KeyedSubtree(
            key: stateObj._sectionKeyFor('reset_audio_engine'),
            child: ResetAudioEngineGuardrailCard(cubit: cubit),
          ),

          // B. Output Device Card (device-adaptive surface)
          KeyedSubtree(
            key: stateObj._sectionKeyFor('output'),
            child: _catSection(
              context,
              'sound',
              SettingsSection(
                icon: Icons.speaker_group_rounded,
                title: context.l10n.settingsHardwareAudioOutput,
                children: [
                  DeviceAdaptiveOutputSection(
                    state: state,
                    onShowDspPreference: (sheetContext, cubit, pref) {
                      showDspPreferencePickerSheet(sheetContext, cubit, pref);
                    },
                  ),
                ],
              ),
            ),
          ),

          // C. Playback Behavior
          KeyedSubtree(
            key: stateObj._sectionKeyFor('playback'),
            child: PlaybackSection(state: state),
          ),
          KeyedSubtree(
            key: stateObj._sectionKeyFor('quran'),
            child: _section(
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
          ),

          // D. Loudness & Gain
          KeyedSubtree(
            key: stateObj._sectionKeyFor('gain'),
            child: AudioGainSection(state: state),
          ),

          // Experience Mode Placement (above Studio/DSP disclosure)
          KeyedSubtree(
            key: stateObj._sectionKeyFor('experience'),
            child: _experienceModeCard(context),
          ),

          // E. Effects & DSP
          KeyedSubtree(
            key: stateObj._sectionKeyFor('dsp'),
            child: AudioEffectsDspSection(state: state),
          ),

          // F. Device Profiles & Automation (Professional only)
          if (state.isProfessional) ...[
            KeyedSubtree(
              key: stateObj._sectionKeyFor('profiles'),
              child: _section(
                context,
                context.l10n.deviceProfilesTitle,
                context.l10n.settingsDeviceProfilesSectionSubtitle,
                [
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md,
                        AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                    child: DeviceProfilesSection(),
                  ),
                ],
              ),
            ),
            KeyedSubtree(
              key: stateObj._sectionKeyFor('automation'),
              child: _section(
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
            ),
          ],

          KeyedSubtree(
            key: stateObj._sectionKeyFor('cast'),
            child: const CastSection(),
          ),
        ];

      case 'look':
        return [
          KeyedSubtree(
            key: stateObj._sectionKeyFor('appearance'),
            child: _buildAppearanceSection(context, state, cubit),
          ),
          KeyedSubtree(
            key: stateObj._sectionKeyFor('accessibility'),
            child: _buildAccessibilitySection(context, state, cubit),
          ),
          KeyedSubtree(
            key: stateObj._sectionKeyFor('gestures'),
            child: _buildGesturesSection(context, state, cubit),
          ),
        ];

      case 'library':
        return [
          KeyedSubtree(
            key: stateObj._sectionKeyFor('library'),
            child: _buildLibrarySection(context, state, cubit),
          ),
          KeyedSubtree(
            key: stateObj._sectionKeyFor('storage'),
            child: _section(
              context,
              context.l10n.storageAndCache,
              context.l10n.settingsStorageSectionSubtitle,
              [const StorageCacheSection()],
            ),
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

      case 'tools':
        return [
          _section(
            context,
            context.l10n.extrasSettingsCategoryTitle,
            context.l10n.extrasSettingsCategorySubtitle,
            [
              _navTile(
                context,
                Icons.handyman_rounded,
                context.l10n.extrasTitle,
                context.l10n.extrasPlaybackSubtitle,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ExtrasScreen(),
                  ),
                ),
              ),
            ],
            key: _catById('tools').key,
          ),
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
              // The Play Store build has no INTERNET permission and does not
              // declare REQUEST_INSTALL_PACKAGES, so a GitHub self-updater
              // cannot work there; updates are delivered by Play instead.
              if (!AppConfig.isPure)
                _navTile(
                  context,
                  Icons.system_update_alt_rounded,
                  'Check for Updates',
                  'Check GitHub releases for new version',
                  onTap: () => AppUpdateService.instance
                      .checkForUpdates(context, userInitiated: true),
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
