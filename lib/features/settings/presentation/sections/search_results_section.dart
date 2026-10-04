part of '../settings_screen.dart';

mixin SettingsSearchResults
    on SettingsSectionPrimitives, State<SettingsScreen> {
  // Requires: provided by the composing class (same library).
  TextEditingController get _searchController;

  // Requires: provided by the composing class (same library).
  String get _searchQuery;
  set _searchQuery(String value);

  // Requires: provided by the composing class (same library).
  set _selectedCategoryId(String value);

  List<_SearchItem>? _memoizedFilteredEntries;
  bool? _memoizedFilteredIsPro;
  List<_SearchItem>? _memoizedFilteredSourceRef;

  List<_SearchItem>? _memoizedSearchResults;
  String? _memoizedSearchResultsQuery;
  List<_SearchItem>? _memoizedSearchResultsSourceRef;

  @visibleForTesting
  List<dynamic>? get memoizedSearchResults => _memoizedSearchResults;

  Widget _buildSearchResultsList(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;
    final query = _searchQuery.trim().toLowerCase();

    // Collect all searchable setting entries (Professional-only entries are
    // hidden while in Normal mode so advanced features don't leak via search).
    final allEntries = _getSearchableEntries(context, state, cubit);
    final List<_SearchItem> entries;
    if (_memoizedFilteredEntries != null &&
        _memoizedFilteredIsPro == state.isProfessional &&
        identical(_memoizedFilteredSourceRef, allEntries)) {
      entries = _memoizedFilteredEntries!;
    } else {
      _memoizedFilteredSourceRef = allEntries;
      _memoizedFilteredIsPro = state.isProfessional;
      entries = _memoizedFilteredEntries =
          allEntries.where((e) => state.isProfessional || !e.pro).toList();
    }

    final List<_SearchItem> results;
    if (_memoizedSearchResults != null &&
        _memoizedSearchResultsQuery == query &&
        identical(_memoizedSearchResultsSourceRef, entries)) {
      results = _memoizedSearchResults!;
    } else {
      _memoizedSearchResultsQuery = query;
      _memoizedSearchResultsSourceRef = entries;
      results = _memoizedSearchResults = entries.where((e) {
        return e.title.toLowerCase().contains(query) ||
            e.subtitle.toLowerCase().contains(query) ||
            e.category.toLowerCase().contains(query) ||
            e.keywords.any((k) => k.toLowerCase().contains(query));
      }).toList();
    }

    if (results.isEmpty) {
      final suggestions = [
        'Equalizer',
        'Theme',
        'Downloads',
        'Smart Audio',
        'Volume',
        'Timer'
      ];
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
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
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.center,
                children: suggestions.map((s) {
                  return ActionChip(
                    label: Text(s,
                        style: TextStyle(
                            fontSize: AppFontSize.tiny, color: p.textPrimary)),
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
        bottom: PulsrLayoutMetrics.scrollBottom(context),
        top: 8,
        start: Adaptive.pagePadding(context),
        end: Adaptive.pagePadding(context),
      ),
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
            child: Text(
              context.l10n.settingsResultsCount(results.length),
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
              borderRadius: AppRadii.tileRadius,
              side: BorderSide(color: p.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: _iconBox(context, r.icon),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.12),
                          borderRadius: AppRadii.r6All,
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
                      if (r.pro) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s6,
                              vertical: AppSpacing.s2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                p.accent,
                                p.accent.withValues(alpha: 0.7)
                              ],
                            ),
                            borderRadius: AppRadii.r6All,
                          ),
                          child: Text(
                            "PRO",
                            style: TextStyle(
                              color: p.onAccent,
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w900,
                              letterSpacing: AppTracking.wide,
                            ),
                          ),
                        ),
                      ],
                    ],
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
                baseStyle: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.label),
                matchStyle: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.label,
                ),
              ),
              trailing: r.trailing ??
                  Icon(Icons.chevron_right_rounded,
                      color: p.textTertiary, size: 20),
              onTap: () {
                final catId = r.categoryId.isNotEmpty
                    ? r.categoryId
                    : _mapCategoryNameToId(r.category, context);
                r.onTap?.call();
                if (mounted) {
                  setState(() {
                    if (catId.isNotEmpty && catId != 'all') {
                      _selectedCategoryId = catId;
                    }
                    _searchController.clear();
                    _searchQuery = '';
                  });
                }
              },
            ),
          ),
        );
      },
    );
  }

  String _mapCategoryNameToId(String catName, BuildContext context) {
    if (catName == context.l10n.settingsCategoryAppearance ||
        catName == context.l10n.settingsSectionAppearanceGestures ||
        catName == context.l10n.gestures) {
      return 'look';
    }
    if (catName == context.l10n.audioAndSound ||
        catName == context.l10n.settingsSearchCategoryAudio ||
        catName == context.l10n.settingsSectionSoundPlayback ||
        catName == context.l10n.playback ||
        catName == context.l10n.settingsCategoryProfiles) {
      return 'sound';
    }
    if (catName == context.l10n.navLibrary ||
        catName == context.l10n.libraryAndScanning ||
        catName == context.l10n.storageAndCache) {
      return 'library';
    }
    if (catName == context.l10n.settingsCategoryOnline ||
        catName == context.l10n.youtubeMusicAndOnline ||
        catName == context.l10n.networkAndProxy) {
      return 'network';
    }
    if (catName == context.l10n.settingsCategoryPrivacy ||
        catName == context.l10n.privacyAndData) {
      return 'privacy';
    }
    if (catName == context.l10n.settingsCategoryAbout ||
        catName == context.l10n.about) {
      return 'about';
    }
    return 'all';
  }

  List<_SearchItem>? _memoizedSearchEntries;
  Locale? _memoizedSearchLocale;
  ({
    bool autoThemeByTime,
    bool highContrast,
    bool reduceMotion,
    Object? playerThemeMode,
    Object? visualizerStyle,
    Object? themeColorSource,
    String languageCode,
    int minDurationSec,
    Object? streamingQuality,
  })? _memoizedRelevantFields;

  List<_SearchItem> _getSearchableEntries(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final currentLocale = Localizations.localeOf(context);
    final relevantFields = (
      autoThemeByTime: state.autoThemeByTime,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      playerThemeMode: state.playerThemeMode,
      visualizerStyle: state.visualizerStyle,
      themeColorSource: state.themeColorSource,
      languageCode: state.languageCode,
      minDurationSec: state.minDurationSec,
      streamingQuality: state.streamingQuality,
    );
    if (_memoizedSearchEntries != null &&
        _memoizedSearchLocale == currentLocale &&
        _memoizedRelevantFields == relevantFields) {
      return _memoizedSearchEntries!;
    }
    _memoizedSearchLocale = currentLocale;
    _memoizedRelevantFields = relevantFields;

    final lookCat = context.l10n.settingsSectionAppearanceGestures;
    final soundCat = context.l10n.settingsSectionSoundPlayback;
    final libraryCat = context.l10n.libraryAndScanning;
    final networkCat = AppConfig.ytmEnabled
        ? context.l10n.youtubeMusicAndOnline
        : context.l10n.networkAndProxy;
    final privacyCat = context.l10n.privacyAndData;
    final aboutCat = context.l10n.about;

    return _memoizedSearchEntries = [
      // ════════ 6 TOP-LEVEL DESTINATION ENTRIES ════════
      _SearchItem(
        categoryId: 'sound',
        category: soundCat,
        title: soundCat,
        subtitle: context.l10n.settingsCategoryAudioSubtitle,
        icon: Icons.graphic_eq_rounded,
        keywords: [
          'sound',
          'audio',
          'playback',
          'music',
          'dsp',
          'dac',
          'equalizer',
          'volume',
          'smart audio'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'sound');
        },
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
        title: lookCat,
        subtitle: context.l10n.settingsCategoryAppearanceSubtitle,
        icon: Icons.palette_outlined,
        keywords: [
          'look',
          'appearance',
          'theme',
          'color',
          'gestures',
          'dark',
          'light',
          'contrast',
          'glass'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'look');
        },
      ),
      _SearchItem(
        categoryId: 'library',
        category: libraryCat,
        title: libraryCat,
        subtitle: context.l10n.settingsCategoryLibrarySubtitle,
        icon: Icons.library_music_outlined,
        keywords: [
          'library',
          'storage',
          'scan',
          'folders',
          'cache',
          'files',
          'music'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'library');
        },
      ),
      _SearchItem(
        categoryId: 'network',
        category: networkCat,
        title: networkCat,
        subtitle: context.l10n.settingsCategoryOnlineSubtitle,
        icon: Icons.cloud_outlined,
        keywords: [
          'network',
          'online',
          'ytm',
          'streaming',
          'proxy',
          'download',
          'wifi'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'network');
        },
      ),
      _SearchItem(
        categoryId: 'privacy',
        category: privacyCat,
        title: privacyCat,
        subtitle: context.l10n.settingsCategoryPrivacySubtitle,
        icon: Icons.shield_outlined,
        keywords: [
          'privacy',
          'data',
          'backup',
          'restore',
          'scrobble',
          'lastfm',
          'offline'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'privacy');
        },
      ),
      _SearchItem(
        categoryId: 'about',
        category: aboutCat,
        title: aboutCat,
        subtitle:
            context.l10n.settingsCategoryAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        keywords: [
          'about',
          'version',
          'info',
          'changelog',
          'licenses',
          'specs'
        ],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'about');
        },
      ),

      // ════════ LEAF SETTINGS ENTRIES ════════
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.settingsSearchThemeModeTitle,
        subtitle: context.l10n.settingsSearchThemeModeSubtitle,
        icon: Icons.brightness_auto_rounded,
        keywords: ['theme', 'dark', 'light', 'amoled', 'black', 'mode'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'look');
        },
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
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
          setState(() => _selectedCategoryId = 'look');
        },
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
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
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.settingsSearchHighContrastTitle,
        subtitle: context.l10n.settingsHighContrastSubtitle,
        icon: Icons.contrast_rounded,
        keywords: ['contrast', 'amoled', 'pure black', 'accessibility'],
        trailing: Switch.adaptive(
          value: state.highContrast,
          onChanged: cubit.setHighContrast,
        ),
        onTap: () => cubit.setHighContrast(!state.highContrast),
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.settingsDimWhitePointTitle,
        subtitle: context.l10n.settingsDimWhitePointSubtitle,
        icon: Icons.brightness_4_rounded,
        keywords: ['dim', 'white point', 'comfort', 'eye', 'night'],
        trailing: Switch.adaptive(
          value: state.dimWhitePoint,
          onChanged: cubit.setDimWhitePoint,
        ),
        onTap: () => cubit.setDimWhitePoint(!state.dimWhitePoint),
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
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
        categoryId: 'look',
        category: lookCat,
        title: 'UI Sound Effects',
        subtitle: 'Play subtle audio feedback for interactions',
        icon: Icons.volume_up_rounded,
        keywords: ['sound', 'audio', 'feedback', 'effects', 'click', 'haptic'],
        trailing: Switch.adaptive(
          value: SoundFeedbackService.enabled,
          onChanged: (val) => SoundFeedbackService.setEnabled(val),
        ),
        onTap: () =>
            SoundFeedbackService.setEnabled(!SoundFeedbackService.enabled),
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
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
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.settingsSearchVisualizerStyleTitle,
        subtitle: getVisualizerStyleTitle(state.visualizerStyle, context.l10n),
        icon: Icons.graphic_eq_rounded,
        keywords: ['visualizer', 'spectrum', 'waveform', 'bars', 'frequency'],
        onTap: () => showVisualizerStylePickerSheet(
            context, cubit, state.visualizerStyle),
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.colorSource,
        subtitle: getColorSourceTitle(state.themeColorSource, context.l10n),
        icon: Icons.palette_outlined,
        keywords: ['material you', 'dynamic', 'wallpaper', 'artwork'],
        onTap: () =>
            showColorSourcePickerSheet(context, cubit, state.themeColorSource),
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.language,
        subtitle: getLanguageTitle(state.languageCode, context.l10n),
        icon: Icons.language_rounded,
        keywords: ['language', 'locale', 'arabic', 'english', 'spanish'],
        onTap: () =>
            showLanguagePickerSheet(context, cubit, state.languageCode),
      ),
      _SearchItem(
        categoryId: 'sound',
        category: soundCat,
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
            setState(() => _selectedCategoryId = 'sound');
          }
        },
      ),
      _SearchItem(
        categoryId: 'sound',
        category: soundCat,
        title: context.l10n.settingsSearchBitPerfectTitle,
        subtitle: context.l10n.settingsSearchBitPerfectSubtitle,
        icon: Icons.album_rounded,
        keywords: ['dac', 'hires', 'bit-perfect', 'sample rate', 'khz', 'usb'],
        pro: true,
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'sound');
        },
      ),
      _SearchItem(
        categoryId: 'sound',
        category: soundCat,
        title: context.l10n.settingsSearchCrossfadeTitle,
        subtitle: context.l10n.settingsSearchCrossfadeSubtitle,
        icon: Icons.play_circle_outline_rounded,
        keywords: ['crossfade', 'gapless', 'transition', 'seconds', 'fade'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'sound');
        },
      ),
      _SearchItem(
        categoryId: 'sound',
        category: soundCat,
        title: context.l10n.sleepTimer,
        subtitle: context.l10n.settingsSearchSleepTimerSubtitle,
        icon: Icons.timer_outlined,
        keywords: ['sleep', 'timer', 'stop', 'night'],
        onTap: () => SleepTimerSheet.show(context),
      ),
      _SearchItem(
        categoryId: 'look',
        category: lookCat,
        title: context.l10n.settingsSearchSwipeTitle,
        subtitle: context.l10n.settingsSearchSwipeSubtitle,
        icon: Icons.swipe_rounded,
        keywords: ['swipe', 'miniplayer', 'gesture', 'left', 'right', 'volume'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'look');
        },
      ),
      _SearchItem(
        categoryId: 'library',
        category: libraryCat,
        title: context.l10n.settingsSearchRescanTitle,
        subtitle: context.l10n.settingsSearchRescanSubtitle,
        icon: Icons.refresh_rounded,
        keywords: ['scan', 'refresh', 'library', 'songs', 'tracks', 'storage'],
        onTap: () => cubit.rescanLibrary(),
      ),
      _SearchItem(
        categoryId: 'library',
        category: libraryCat,
        title: context.l10n.settingsRebuildSearchIndexTitle,
        subtitle: context.l10n.settingsRebuildSearchIndexSubtitle,
        icon: Icons.manage_search_rounded,
        keywords: ['fts', 'search', 'index', 'rebuild', 'results', 'missing'],
        onTap: () => cubit.rebuildSearchIndex(),
      ),
      _SearchItem(
        categoryId: 'library',
        category: libraryCat,
        title: context.l10n.hiddenAndExcludedFolders,
        subtitle: context.l10n.settingsSearchHiddenFoldersSubtitle,
        icon: Icons.folder_off_rounded,
        keywords: ['hidden', 'folders', 'exclude', 'voice memos', 'ringtones'],
        onTap: () => context.push('/hidden-folders'),
      ),
      _SearchItem(
        categoryId: 'library',
        category: libraryCat,
        title: context.l10n.shortAudioFilter,
        subtitle: context.l10n.ignoreFilesUnder(state.minDurationSec),
        icon: Icons.filter_list_rounded,
        keywords: ['filter', 'short', 'duration', 'seconds'],
        onTap: () =>
            _showDurationFilterDialog(context, cubit, state.minDurationSec),
      ),
      _SearchItem(
        categoryId: 'network',
        category: networkCat,
        title: context.l10n.proxySettings,
        subtitle: context.l10n.settingsSearchProxySubtitle,
        icon: Icons.vpn_lock_rounded,
        keywords: ['proxy', 'socks5', 'http', 'ip', 'port', 'vpn'],
        pro: true,
        onTap: () => context.push('/proxy-settings'),
      ),
      _SearchItem(
        categoryId: 'network',
        category: networkCat,
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
        categoryId: 'library',
        category: libraryCat,
        title: context.l10n.settingsSearchCacheTitle,
        subtitle: context.l10n.settingsSearchCacheSubtitle,
        icon: Icons.storage_rounded,
        keywords: ['cache', 'storage', 'clear', 'artwork', 'mb', 'disk'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'library');
        },
      ),
      _SearchItem(
        categoryId: 'privacy',
        category: privacyCat,
        title: context.l10n.settingsScrobblingTitle,
        subtitle: context.l10n.settingsSearchScrobblingSubtitle,
        icon: Icons.equalizer_outlined,
        keywords: ['scrobble', 'lastfm', 'listenbrainz', 'stats', 'history'],
        onTap: () => showScrobblerSettingsModal(context),
      ),
      _SearchItem(
        categoryId: 'privacy',
        category: privacyCat,
        title: context.l10n.settingsSearchPrivacyTitle,
        subtitle: context.l10n.settingsSearchPrivacySubtitle,
        icon: Icons.security_rounded,
        keywords: ['privacy', 'guarantee', 'offline', 'trackers', 'security'],
        onTap: () => showPrivacyGuaranteeSheet(context),
      ),
      _SearchItem(
        categoryId: 'about',
        category: aboutCat,
        title: context.l10n.about,
        subtitle:
            context.l10n.settingsSearchAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        keywords: ['about', 'version', 'license', 'developer'],
        onTap: () => showAboutSheet(context),
      ),
    ];
  }

  Widget _buildHighlightedText(
    String text,
    String query, {
    required TextStyle baseStyle,
    required TextStyle matchStyle,
  }) {
    return PulsrHighlightedText(
      text: text,
      query: query,
      baseStyle: baseStyle,
      matchStyle: matchStyle,
    );
  }
}
