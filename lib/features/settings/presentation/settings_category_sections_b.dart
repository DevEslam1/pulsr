part of 'settings_screen.dart';

mixin SettingsCategorySectionsB on State<SettingsScreen> {
  Widget _buildOnlineSection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      AppConfig.ytmEnabled
          ? context.l10n.youtubeMusicAndOnline
          : context.l10n.networkAndProxy,
      context.l10n.settingsOnlineSectionSubtitle,
      [
        if (AppConfig.ytmEnabled) ...[
          // Account + web-player entries trigger network; hide them when the
          // user has turned on offline-only mode (Home/Search already do).
          if (!state.offlineOnlyMode) ...[
            () {
              final ytmAccount = getIt<YtmAccountService>();
              return ValueListenableBuilder<bool>(
                valueListenable: ytmAccount.loginState,
                builder: (context, isLoggedIn, _) {
                  if (!isLoggedIn) {
                    return _navTile(
                      context,
                      Icons.account_circle_outlined,
                      context.l10n.connectYtmAccount,
                      context.l10n.connectYtmSubtitle,
                      onTap: () async {
                        final ok = await YtmWebLoginSheet.show(context);
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.ytmConnected),
                            ),
                          );
                        }
                      },
                    );
                  } else {
                    return _navTile(
                      context,
                      Icons.account_circle_rounded,
                      context.l10n.ytmConnected,
                      '${ytmAccount.accountName ?? context.l10n.castConnected} • ${context.l10n.settingsTapToManage}',
                      trailingBadge: context.l10n.settingsBadgeConnected,
                      onTap: () => showYtmAccountDisconnectDialog(context),
                    );
                  }
                },
              );
            }(),
            _divider(p),
            _navTile(
              context,
              Icons.language_rounded,
              context.l10n.openYtmWeb,
              context.l10n.openYtmWebSubtitle,
              onTap: () => showYtmWebOptionsSheet(context),
            ),
            _divider(p),
          ],
          _switchTile(
            context,
            Icons.cloud_off_rounded,
            context.l10n.offlineOnlyMode,
            context.l10n.offlineOnlySubtitle,
            value: state.offlineOnlyMode,
            onChanged: cubit.setOfflineOnlyMode,
          ),
          if (!state.offlineOnlyMode) ...[
            _divider(p),
            _switchTile(
              context,
              Icons.wifi_rounded,
              context.l10n.wifiOnlyMode,
              context.l10n.wifiOnlySubtitle,
              value: state.wifiOnlyMode,
              onChanged: cubit.setWifiOnlyMode,
            ),
            _divider(p),
            _navTile(
              context,
              Icons.travel_explore_rounded,
              context.l10n.searchYtm,
              context.l10n.searchYtmSubtitle,
              onTap: () => context.push('/ytm-search'),
            ),
            _divider(p),
            _navTile(
              context,
              Icons.wifi_tethering_rounded,
              context.l10n.streamingQuality,
              getQualityTitle(state.streamingQuality, context.l10n),
              trailingBadge: state.streamingQuality.name.toUpperCase(),
              onTap: () => showQualityPickerSheet(
                context,
                cubit,
                isStreaming: true,
                currentQuality: state.streamingQuality,
              ),
            ),
            _divider(p),
            _navTile(
              context,
              Icons.downloading_rounded,
              context.l10n.downloadQuality,
              getQualityTitle(state.downloadQuality, context.l10n),
              trailingBadge: state.downloadQuality.name.toUpperCase(),
              onTap: () => showQualityPickerSheet(
                context,
                cubit,
                isStreaming: false,
                currentQuality: state.downloadQuality,
              ),
            ),
            _divider(p),
            const DownloadConcurrencyTile(),
            _divider(p),
            const DownloadLocationTile(),
            _divider(p),
            _navTile(
              context,
              Icons.folder_zip_rounded,
              context.l10n.downloadsTitle,
              context.l10n.settingsDownloadsSubtitle,
              onTap: () => context.push('/downloads'),
            ),
          ],
          _divider(p),
        ],
        _navTile(
          context,
          Icons.vpn_lock_rounded,
          context.l10n.proxySettings,
          state.proxyEnabled
              ? '${state.proxyType.displayName} • ${state.proxyHost.isNotEmpty ? "${state.proxyHost}:${state.proxyPort}" : context.l10n.settingsProxyEnabled}'
              : context.l10n.settingsProxyDisabledHint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.proxyEnabled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                  margin: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: p.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadii.r6),
                  ),
                  child: Text(
                    context.l10n.activeLabel,
                    style: TextStyle(
                      color: p.success,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  color: p.textTertiary, size: 20),
            ],
          ),
          onTap: () => context.push('/proxy-settings'),
        ),
      ],
      key: _catById('online').key,
    );
  }

  Widget _buildPrivacyBackupSection(BuildContext context) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.privacyAndData,
      context.l10n.settingsPrivacySectionSubtitle,
      [
        const BackupSection(),
        _divider(p),
        _navTile(
          context,
          Icons.equalizer_outlined,
          context.l10n.settingsScrobblingTitle,
          context.l10n.settingsScrobblingSubtitle,
          onTap: () => showScrobblerSettingsModal(context),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.bar_chart_rounded,
          context.l10n.settingsScrobbleStatsTitle,
          context.l10n.settingsScrobbleStatsSubtitle,
          onTap: () => context.push('/scrobble-stats'),
        ),
        if (AppConfig.isCloudSyncAllowed) ...[
          _divider(p),
          _navTile(
            context,
            Icons.cloud_sync_rounded,
            context.l10n.settingsCloudBackupDashboard,
            context.l10n.settingsCloudBackupDashboardSubtitle,
            onTap: () => context.push('/cloud-backup-dashboard'),
          ),
        ],
        _divider(p),
        _navTile(
          context,
          Icons.security_rounded,
          context.l10n.privacyGuarantee,
          context.l10n.privacyGuaranteeSubtitle,
          onTap: () => showPrivacyGuaranteeSheet(context),
        ),
      ],
      key: _catById('privacy').key,
    );
  }

  Widget _buildSearchResultsList(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;
    final query = _searchQuery.trim().toLowerCase();

    // Collect all searchable setting entries (Professional-only entries are
    // hidden while in Normal mode so advanced features don't leak via search).
    final entries = _getSearchableEntries(context, state, cubit)
        .where((e) => state.isProfessional || !e.pro)
        .toList();
    final results = entries.where((e) {
      return e.title.toLowerCase().contains(query) ||
          e.subtitle.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query) ||
          e.keywords.any((k) => k.toLowerCase().contains(query));
    }).toList();

    if (results.isEmpty) {
      final suggestions = ['Equalizer', 'Theme', 'Downloads', 'Smart Audio', 'Volume', 'Timer'];
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.hairline),
                ),
                child: Icon(Icons.search_off_rounded,
                    color: p.textTertiary, size: 28),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.settingsNoSettingsFound(_searchQuery),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.bodyLarge,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.s6),
              Text(
                context.l10n.settingsSearchHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.center,
                children: suggestions.map((s) {
                  return ActionChip(
                    label: Text(s, style: TextStyle(fontSize: AppFontSize.tiny, color: p.textPrimary)),
                    backgroundColor: p.surfaceContainer,
                    side: BorderSide(color: p.hairline),
                    onPressed: () {
                      _searchController.text = s;
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      padding: EdgeInsetsDirectional.only(
        bottom: AppSpacing.scrollBottom,
        top: 8,
        start: Adaptive.pagePadding(context),
        end: Adaptive.pagePadding(context),
      ),
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
            child: Text(
              '${results.length} ${results.length == 1 ? "setting" : "settings"} found',
              style: TextStyle(
                color: p.textTertiary,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: AppTracking.label,
              ),
            ),
          );
        }
        final r = results[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Material(
            color: p.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.tile),
              side: BorderSide(color: p.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: _iconBox(context, r.icon),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.r6),
                    ),
                    child: Text(
                      r.category.toUpperCase(),
                      style: TextStyle(
                        color: p.accent,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.medium,
                      ),
                    ),
                  ),
                  _buildHighlightedText(
                    r.title,
                    query,
                    baseStyle: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: AppFontSize.body,
                    ),
                    matchStyle: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: AppFontSize.body,
                    ),
                  ),
                ],
              ),
              subtitle: _buildHighlightedText(
                r.subtitle,
                query,
                baseStyle: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
                matchStyle: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.label,
                ),
              ),
              trailing: r.trailing ??
                  Icon(Icons.chevron_right_rounded,
                      color: p.textTertiary, size: 20),
              onTap: r.onTap,
            ),
          ),
        );
      },
    );
  }

  List<_SearchItem> _getSearchableEntries(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    return [
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsSearchThemeModeTitle,
        subtitle: context.l10n.settingsSearchThemeModeSubtitle,
        icon: Icons.brightness_auto_rounded,
        keywords: ['theme', 'dark', 'light', 'amoled', 'black', 'mode'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'appearance');
        },
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsSearchAccentColorTitle,
        subtitle: context.l10n.settingsSearchAccentColorSubtitle,
        icon: Icons.color_lens_rounded,
        keywords: [
          'color',
          'accent',
          'palette',
          'tint',
          'pink',
          'blue',
          'orange'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'appearance');
        },
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsAutoDarkModeTitle,
        subtitle: context.l10n.settingsAutoDarkModeSubtitle,
        icon: Icons.nightlight_round,
        keywords: ['auto', 'night', 'schedule', 'dark'],
        trailing: Switch.adaptive(
          value: state.autoThemeByTime,
          onChanged: cubit.setAutoThemeByTime,
        ),
        onTap: () => cubit.setAutoThemeByTime(!state.autoThemeByTime),
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsSearchHighContrastTitle,
        subtitle: context.l10n.settingsHighContrastSubtitle,
        icon: Icons.contrast_rounded,
        keywords: ['contrast', 'amoled', 'pure black'],
        trailing: Switch.adaptive(
          value: state.highContrast,
          onChanged: cubit.setHighContrast,
        ),
        onTap: () => cubit.setHighContrast(!state.highContrast),
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsReduceMotionTitle,
        subtitle: context.l10n.settingsReduceMotionSubtitle,
        icon: Icons.motion_photos_off_rounded,
        keywords: ['motion', 'animation', 'accessibility', 'reduce'],
        trailing: Switch.adaptive(
          value: state.reduceMotion,
          onChanged: cubit.setReduceMotion,
        ),
        onTap: () => cubit.setReduceMotion(!state.reduceMotion),
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsSearchNowPlayingThemeTitle,
        subtitle: getThemeModeTitle(state.playerThemeMode, context.l10n),
        icon: Icons.art_track_rounded,
        keywords: [
          'player',
          'vinyl',
          'cassette',
          'waveform',
          'card',
          'lyrics',
          'theme'
        ],
        onTap: () =>
            showThemePickerSheet(context, cubit, state.playerThemeMode),
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.settingsSearchVisualizerStyleTitle,
        subtitle: getVisualizerStyleTitle(state.visualizerStyle, context.l10n),
        icon: Icons.graphic_eq_rounded,
        keywords: ['visualizer', 'spectrum', 'waveform', 'bars', 'frequency'],
        onTap: () => showVisualizerStylePickerSheet(
            context, cubit, state.visualizerStyle),
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.colorSource,
        subtitle: getColorSourceTitle(state.themeColorSource, context.l10n),
        icon: Icons.palette_outlined,
        keywords: ['material you', 'dynamic', 'wallpaper', 'artwork'],
        onTap: () =>
            showColorSourcePickerSheet(context, cubit, state.themeColorSource),
      ),
      _SearchItem(
        category: context.l10n.settingsCategoryAppearance,
        title: context.l10n.language,
        subtitle: getLanguageTitle(state.languageCode, context.l10n),
        icon: Icons.language_rounded,
        keywords: ['language', 'locale', 'arabic', 'english', 'spanish'],
        onTap: () =>
            showLanguagePickerSheet(context, cubit, state.languageCode),
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryAudio,
        title: context.l10n.equalizerAndSoundEffects,
        subtitle: context.l10n.settingsSearchEqualizerSubtitle,
        icon: Icons.equalizer_rounded,
        keywords: [
          'eq',
          'equalizer',
          'bass',
          'treble',
          'sound',
          'dsp',
          'reverb'
        ],
        onTap: () {
          if (PlatformCapabilities.hasEqualizer) {
            EqualizerSheet.show(context);
          } else {
            _searchController.clear();
            setState(() => _selectedCategoryId = 'audio');
          }
        },
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryAudio,
        title: context.l10n.settingsSearchBitPerfectTitle,
        subtitle: context.l10n.settingsSearchBitPerfectSubtitle,
        icon: Icons.album_rounded,
        keywords: ['dac', 'hires', 'bit-perfect', 'sample rate', 'khz', 'usb'],
        pro: true,
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'audio');
        },
      ),
      _SearchItem(
        category: context.l10n.playback,
        title: context.l10n.settingsSearchCrossfadeTitle,
        subtitle: context.l10n.settingsSearchCrossfadeSubtitle,
        icon: Icons.play_circle_outline_rounded,
        keywords: ['crossfade', 'gapless', 'transition', 'seconds', 'fade'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'playback');
        },
      ),
      _SearchItem(
        category: context.l10n.playback,
        title: context.l10n.sleepTimer,
        subtitle: context.l10n.settingsSearchSleepTimerSubtitle,
        icon: Icons.timer_outlined,
        keywords: ['sleep', 'timer', 'stop', 'night'],
        onTap: () => SleepTimerSheet.show(context),
      ),
      _SearchItem(
        category: context.l10n.gestures,
        title: context.l10n.settingsSearchSwipeTitle,
        subtitle: context.l10n.settingsSearchSwipeSubtitle,
        icon: Icons.swipe_rounded,
        keywords: ['swipe', 'miniplayer', 'gesture', 'left', 'right', 'volume'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'gestures');
        },
      ),
      _SearchItem(
        category: context.l10n.navLibrary,
        title: context.l10n.settingsSearchRescanTitle,
        subtitle: context.l10n.settingsSearchRescanSubtitle,
        icon: Icons.refresh_rounded,
        keywords: ['scan', 'refresh', 'library', 'songs', 'tracks', 'storage'],
        onTap: () => cubit.rescanLibrary(),
      ),
      _SearchItem(
        category: context.l10n.navLibrary,
        title: context.l10n.settingsRebuildSearchIndexTitle,
        subtitle: context.l10n.settingsRebuildSearchIndexSubtitle,
        icon: Icons.manage_search_rounded,
        keywords: ['fts', 'search', 'index', 'rebuild', 'results', 'missing'],
        onTap: () => cubit.rebuildSearchIndex(),
      ),
      _SearchItem(
        category: context.l10n.navLibrary,
        title: context.l10n.hiddenAndExcludedFolders,
        subtitle: context.l10n.settingsSearchHiddenFoldersSubtitle,
        icon: Icons.folder_off_rounded,
        keywords: ['hidden', 'folders', 'exclude', 'voice memos', 'ringtones'],
        onTap: () => context.push('/hidden-folders'),
      ),
      _SearchItem(
        category: context.l10n.navLibrary,
        title: context.l10n.shortAudioFilter,
        subtitle: context.l10n.ignoreFilesUnder(state.minDurationSec),
        icon: Icons.filter_list_rounded,
        keywords: ['filter', 'short', 'duration', 'seconds'],
        onTap: () =>
            _showDurationFilterDialog(context, cubit, state.minDurationSec),
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryNetwork,
        title: context.l10n.proxySettings,
        subtitle: context.l10n.settingsSearchProxySubtitle,
        icon: Icons.vpn_lock_rounded,
        keywords: ['proxy', 'socks5', 'http', 'ip', 'port', 'vpn'],
        pro: true,
        onTap: () => context.push('/proxy-settings'),
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryNetwork,
        title: context.l10n.settingsSearchQualityTitle,
        subtitle: context.l10n.settingsSearchQualitySubtitle,
        icon: Icons.wifi_tethering_rounded,
        keywords: ['quality', 'bitrate', 'streaming', 'download', 'kbps'],
        onTap: () => showQualityPickerSheet(
          context,
          cubit,
          isStreaming: true,
          currentQuality: state.streamingQuality,
        ),
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryStorage,
        title: context.l10n.settingsSearchCacheTitle,
        subtitle: context.l10n.settingsSearchCacheSubtitle,
        icon: Icons.storage_rounded,
        keywords: ['cache', 'storage', 'clear', 'artwork', 'mb', 'disk'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'storage');
        },
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryPrivacy,
        title: context.l10n.settingsScrobblingTitle,
        subtitle: context.l10n.settingsSearchScrobblingSubtitle,
        icon: Icons.equalizer_outlined,
        keywords: ['scrobble', 'lastfm', 'listenbrainz', 'stats', 'history'],
        onTap: () => showScrobblerSettingsModal(context),
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryPrivacy,
        title: context.l10n.settingsSearchPrivacyTitle,
        subtitle: context.l10n.settingsSearchPrivacySubtitle,
        icon: Icons.security_rounded,
        keywords: ['privacy', 'guarantee', 'offline', 'trackers', 'security'],
        onTap: () => showPrivacyGuaranteeSheet(context),
      ),
      _SearchItem(
        category: context.l10n.settingsSearchCategoryAbout,
        title: context.l10n.about,
        subtitle: context.l10n.settingsSearchAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        keywords: ['about', 'version', 'license', 'developer'],
        onTap: () => showAboutSheet(context),
      ),
    ];
  }




























































  // Requires: provided by the composing class (same library).
  _Category _catById(String id);

  // Requires: provided by the composing class (same library).
  Widget _divider(PulsrPalette p);

  // Requires: provided by the composing class (same library).
  Widget _iconBox(BuildContext context, IconData icon);

  // Requires: provided by the composing class (same library).
  Widget _navTile( BuildContext context, IconData icon, String title, String subtitle, { Widget? trailing, String? trailingBadge, VoidCallback? onTap, });

  // Requires: provided by the composing class (same library).
  TextEditingController get _searchController;

  // Requires: provided by the composing class (same library).
  String get _searchQuery;

  // Requires: provided by the composing class (same library).
  Widget _section( BuildContext context, String title, String subtitle, List<Widget> children, { GlobalKey? key, });

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  String get _selectedCategoryId;
  set _selectedCategoryId(String value);

  // Requires: provided by the composing class (same library).
  void _showDurationFilterDialog( BuildContext context, SettingsCubit cubit, int currentSec, );

  // Requires: provided by the composing class (same library).
  Widget _switchTile( BuildContext context, IconData icon, String title, String subtitle, { required bool value, required ValueChanged<bool> onChanged, });

  Widget _buildHighlightedText(
    String text,
    String query, {
    required TextStyle baseStyle,
    required TextStyle matchStyle,
  }) {
    if (query.isEmpty) return Text(text, style: baseStyle);
    final spans = <TextSpan>[];
    int start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final index = lower.indexOf(query, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      spans.add(TextSpan(text: text.substring(index, index + query.length), style: matchStyle));
      start = index + query.length;
    }
    return Text.rich(TextSpan(children: spans));
  }
}
