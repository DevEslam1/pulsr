// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_slider.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'widgets/audio_sound_section.dart';
import 'widgets/automation_rules_sheet.dart';
import 'widgets/backup_section.dart';
import 'widgets/device_profiles_section.dart';
import 'widgets/playback_section.dart';
import 'widgets/scrobbler_settings_modal.dart';
import 'widgets/settings_hero_card.dart';
import 'widgets/settings_picker_sheets.dart';
import 'widgets/storage_cache_section.dart';
import 'widgets/ytm_account_disconnect_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _Category {
  final String id;
  final IconData icon;
  String title = '';
  final GlobalKey key;

  _Category(this.id, this.icon) : key = GlobalKey();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<_Category> _categories = [];

  String _selectedCategoryId = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        _assignCategoryTitles(context);

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: context.isTabletLandscape ? 1040 : 760,
                ),
                child: Column(
                  children: [
                    _buildTopHeader(context),
                    if (_searchQuery.isEmpty) _buildCategoryFilterBar(context),
                    const SizedBox(height: 6),
                    Expanded(
                      child: _searchQuery.isNotEmpty
                          ? _buildSearchResultsList(context, state, cubit)
                          : _buildSettingsBody(context, state, cubit),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // Header & Search Bar
  // ==========================================================================

  Widget _buildTopHeader(BuildContext context) {
    final p = context.palette;
    final horizontalPad = Adaptive.pagePadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, 14, horizontalPad, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settings,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pulsr v${AppConfig.appVersion} • Audiophile Music Experience',
                      style: TextStyle(
                        color: p.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Search Box
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: _searchQuery.isNotEmpty
                    ? p.accent.withValues(alpha: 0.5)
                    : p.hairline,
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Search settings, sound, appearance...',
                hintStyle: TextStyle(
                  color: p.textTertiary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _searchQuery.isNotEmpty ? p.accent : p.textTertiary,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: p.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Category Filter Bar (Pills)
  // ==========================================================================

  Widget _buildCategoryFilterBar(BuildContext context) {
    final p = context.palette;
    final items = [
      (id: 'all', title: 'All', icon: Icons.tune_rounded),
      (id: 'audio', title: 'Audio & Sound', icon: Icons.equalizer_rounded),
      (id: 'playback', title: 'Playback', icon: Icons.play_circle_outline_rounded),
      (id: 'appearance', title: 'Appearance', icon: Icons.palette_outlined),
      (id: 'gestures', title: 'Gestures', icon: Icons.swipe_rounded),
      (id: 'profiles', title: 'Profiles & Rules', icon: Icons.devices_other_rounded),
      (id: 'library', title: 'Library', icon: Icons.library_music_outlined),
      (id: 'online', title: 'Network & YTM', icon: Icons.cloud_outlined),
      (id: 'storage', title: 'Storage & Cache', icon: Icons.storage_rounded),
      (id: 'privacy', title: 'Privacy & Backup', icon: Icons.shield_outlined),
      (id: 'about', title: 'About', icon: Icons.info_outline_rounded),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
            horizontal: Adaptive.pagePadding(context)),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = _selectedCategoryId == item.id;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategoryId = item.id);
              if (item.id != 'all') {
                final ctx = _catById(item.id).key.currentContext;
                if (ctx != null) {
                  Scrollable.ensureVisible(
                    ctx,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    alignment: 0.04,
                  );
                }
              } else {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                }
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? p.accent.withValues(alpha: 0.16)
                    : p.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? p.accent : p.hairline,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 15,
                    color: isSelected ? p.accent : p.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected ? p.accent : p.textPrimary,
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================================================
  // Main Settings Body
  // ==========================================================================

  Widget _buildSettingsBody(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final showAll = _selectedCategoryId == 'all';

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: 160,
        top: 10,
        left: Adaptive.pagePadding(context),
        right: Adaptive.pagePadding(context),
      ),
      children: [
        // Top Hero Account Card
        if (showAll || _selectedCategoryId == 'privacy')
          const SettingsHeroCard(),

        // Audio & Sound
        if (showAll || _selectedCategoryId == 'audio')
          _catSection(context, 'audio', AudioSoundSection(state: state)),

        // Playback
        if (showAll || _selectedCategoryId == 'playback')
          _catSection(context, 'playback', PlaybackSection(state: state)),

        // Appearance
        if (showAll || _selectedCategoryId == 'appearance')
          _buildAppearanceSection(context, state, cubit),

        // Gestures
        if (showAll || _selectedCategoryId == 'gestures')
          _buildGesturesSection(context, state, cubit),

        // Device Profiles & Automation
        if (showAll || _selectedCategoryId == 'profiles') ...[
          _section(
            context,
            'DEVICE PROFILES',
            'Per-output DAC and Bluetooth profile mappings',
            [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: DeviceProfilesSection(),
              ),
            ],
            key: _catById('profiles').key,
          ),
          _section(
            context,
            'AUTOMATION RULES',
            'Trigger profiles automatically on hardware events',
            [
              _navTile(
                context,
                Icons.auto_awesome_rounded,
                'Automation Rules',
                'Apply profiles on headphone plug, Bluetooth or charge events',
                onTap: () => showAutomationRulesSheet(context),
              ),
            ],
            key: _catById('automation').key,
          ),
        ],

        // Library & Scanning
        if (showAll || _selectedCategoryId == 'library')
          _buildLibrarySection(context, state, cubit),

        // Online / YouTube Music / Proxy
        if (showAll || _selectedCategoryId == 'online')
          _buildOnlineSection(context, state, cubit),

        // Storage & Cache
        if (showAll || _selectedCategoryId == 'storage')
          _section(
            context,
            context.l10n.storageAndCache,
            'Manage disk usage and audio cache',
            [const StorageCacheSection()],
            key: _catById('storage').key,
          ),

        // Privacy & Backup
        if (showAll || _selectedCategoryId == 'privacy')
          _buildPrivacyBackupSection(context),

        // About
        if (showAll || _selectedCategoryId == 'about')
          _section(
            context,
            context.l10n.about,
            'Version info, licenses and architecture',
            [
              _navTile(
                context,
                Icons.info_outline_rounded,
                context.l10n.appTitle,
                'Version ${AppConfig.appVersion} • Open-source Audiophile Engine',
                onTap: () => showAboutSheet(context),
              ),
            ],
            key: _catById('about').key,
          ),
      ],
    );
  }

  // ==========================================================================
  // Appearance Section
  // ==========================================================================

  Widget _buildAppearanceSection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.themeAndAppearance,
      'Theme, accent colors, visualizer and player UI style',
      [
        // Theme selector segment
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THEME MODE',
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
                        'AMOLED',
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
                              color: isSelected ? p.textPrimary : Colors.transparent,
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
          'Auto Dark Mode by Time',
          'Follow a 7 PM – 6 AM day/night schedule',
          value: state.autoThemeByTime,
          onChanged: cubit.setAutoThemeByTime,
        ),
        _divider(p),
        _switchTile(
          context,
          Icons.contrast_rounded,
          'High Contrast',
          'Boost contrast with an AMOLED-friendly palette',
          value: state.highContrast,
          onChanged: cubit.setHighContrast,
        ),
        _divider(p),
        _navTile(
          context,
          Icons.art_track_rounded,
          context.l10n.nowPlayingTheme,
          getThemeModeTitle(state.playerThemeMode),
          trailingBadge: 'STYLE',
          onTap: () => showThemePickerSheet(context, cubit, state.playerThemeMode),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.graphic_eq_rounded,
          context.l10n.visualizerStyle,
          getVisualizerStyleTitle(state.visualizerStyle),
          trailingBadge: 'DSP',
          onTap: () =>
              showVisualizerStylePickerSheet(context, cubit, state.visualizerStyle),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.palette_outlined,
          context.l10n.colorSource,
          getColorSourceTitle(state.themeColorSource),
          trailingBadge: 'PALETTE',
          onTap: () =>
              showColorSourcePickerSheet(context, cubit, state.themeColorSource),
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

  // ==========================================================================
  // Gestures Section
  // ==========================================================================

  Widget _buildGesturesSection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.gestures,
      'Configure swipe and double-tap gestures across mini-player and artwork',
      [
        _navTile(
          context,
          Icons.swipe_left_rounded,
          context.l10n.miniPlayerSwipeLeft,
          getMiniPlayerSwipeTitle(state.miniPlayerSwipeLeft),
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
          getMiniPlayerSwipeTitle(state.miniPlayerSwipeRight),
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
          getNowPlayingDoubleTapTitle(state.nowPlayingDoubleTap),
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
          getNowPlayingArtworkSwipeTitle(state.nowPlayingArtworkSwipe),
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

  // ==========================================================================
  // Library & Scanning Section
  // ==========================================================================

  Widget _buildLibrarySection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.libraryAndScanning,
      'Device media indexing, exclusion rules and cleanup',
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
      ],
      key: _catById('library').key,
    );
  }

  // ==========================================================================
  // Online / Streaming Section
  // ==========================================================================

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
      'Online streams, downloads, proxy routing and quality settings',
      [
        if (AppConfig.ytmEnabled) ...[
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
                    '${ytmAccount.accountName ?? "Connected"} • Tap to manage',
                    trailingBadge: 'CONNECTED',
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
              getQualityTitle(state.streamingQuality),
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
              getQualityTitle(state.downloadQuality),
              trailingBadge: state.downloadQuality.name.toUpperCase(),
              onTap: () => showQualityPickerSheet(
                context,
                cubit,
                isStreaming: false,
                currentQuality: state.downloadQuality,
              ),
            ),
            _divider(p),
            _navTile(
              context,
              Icons.folder_zip_rounded,
              'Downloads',
              'View and manage offline tracks and downloads',
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
              ? '${state.proxyType.displayName} • ${state.proxyHost.isNotEmpty ? "${state.proxyHost}:${state.proxyPort}" : "Enabled"}'
              : 'Disabled • Tap to configure HTTP / SOCKS5',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.proxyEnabled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: p.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: p.success,
                      fontSize: 10,
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

  // ==========================================================================
  // Privacy & Backup Section
  // ==========================================================================

  Widget _buildPrivacyBackupSection(BuildContext context) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.privacyAndData,
      'Data sovereignty, database backups and scrobbler integrations',
      [
        const BackupSection(),
        _divider(p),
        _navTile(
          context,
          Icons.equalizer_outlined,
          'Scrobbling (Last.fm & ListenBrainz)',
          'Direct API scrobbling and Now Playing metadata broadcast',
          onTap: () => showScrobblerSettingsModal(context),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.bar_chart_rounded,
          'Scrobble Stats',
          'Listening history and scrobble analytics overview',
          onTap: () => context.push('/scrobble-stats'),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.cloud_sync_rounded,
          'Cloud Backup Dashboard',
          'Manage synchronized devices and cloud backup snapshots',
          onTap: () => context.push('/cloud-backup-dashboard'),
        ),
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

  // ==========================================================================
  // Live Instant Search Mode
  // ==========================================================================

  Widget _buildSearchResultsList(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;
    final query = _searchQuery.trim().toLowerCase();

    // Collect all searchable setting entries
    final entries = _getSearchableEntries(context, state, cubit);
    final results = entries.where((e) {
      return e.title.toLowerCase().contains(query) ||
          e.subtitle.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query) ||
          e.keywords.any((k) => k.toLowerCase().contains(query));
    }).toList();

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
              const SizedBox(height: 16),
              Text(
                'No settings found for "$_searchQuery"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Try searching for "equalizer", "dark mode", "crossfade", "proxy", "cache", or "scrobble".',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: 160,
        top: 8,
        left: Adaptive.pagePadding(context),
        right: Adaptive.pagePadding(context),
      ),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.tile),
              side: BorderSide(color: p.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
            leading: _iconBox(context, r.icon),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    r.title,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.category.toUpperCase(),
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              r.subtitle,
              style: TextStyle(color: p.textSecondary, fontSize: 12),
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
        category: 'Appearance',
        title: 'Theme Mode',
        subtitle: 'System Default, Light, Dark, or AMOLED high contrast',
        icon: Icons.brightness_auto_rounded,
        keywords: ['theme', 'dark', 'light', 'amoled', 'black', 'mode'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'appearance');
        },
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'Accent Color',
        subtitle: 'Custom color accent palette for buttons and active highlights',
        icon: Icons.color_lens_rounded,
        keywords: ['color', 'accent', 'palette', 'tint', 'pink', 'blue', 'orange'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'appearance');
        },
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'Auto Dark Mode by Time',
        subtitle: 'Follow a 7 PM – 6 AM day/night schedule',
        icon: Icons.nightlight_round,
        keywords: ['auto', 'night', 'schedule', 'dark'],
        trailing: Switch.adaptive(
          value: state.autoThemeByTime,
          onChanged: cubit.setAutoThemeByTime,
        ),
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'High Contrast Mode',
        subtitle: 'Boost contrast with an AMOLED-friendly palette',
        icon: Icons.contrast_rounded,
        keywords: ['contrast', 'amoled', 'pure black'],
        trailing: Switch.adaptive(
          value: state.highContrast,
          onChanged: cubit.setHighContrast,
        ),
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'Now Playing Theme Style',
        subtitle: getThemeModeTitle(state.playerThemeMode),
        icon: Icons.art_track_rounded,
        keywords: ['player', 'vinyl', 'cassette', 'waveform', 'card', 'lyrics', 'theme'],
        onTap: () => showThemePickerSheet(context, cubit, state.playerThemeMode),
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'Visualizer Style',
        subtitle: getVisualizerStyleTitle(state.visualizerStyle),
        icon: Icons.graphic_eq_rounded,
        keywords: ['visualizer', 'spectrum', 'waveform', 'bars', 'frequency'],
        onTap: () => showVisualizerStylePickerSheet(
            context, cubit, state.visualizerStyle),
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'Color Source',
        subtitle: getColorSourceTitle(state.themeColorSource),
        icon: Icons.palette_outlined,
        keywords: ['material you', 'dynamic', 'wallpaper', 'artwork'],
        onTap: () => showColorSourcePickerSheet(
            context, cubit, state.themeColorSource),
      ),
      _SearchItem(
        category: 'Appearance',
        title: 'Language',
        subtitle: getLanguageTitle(state.languageCode, context.l10n),
        icon: Icons.language_rounded,
        keywords: ['language', 'locale', 'arabic', 'english', 'spanish'],
        onTap: () =>
            showLanguagePickerSheet(context, cubit, state.languageCode),
      ),
      _SearchItem(
        category: 'Audio',
        title: 'Equalizer & Sound Effects',
        subtitle: '10-band equalizer, bass boost, virtualizer, reverb',
        icon: Icons.equalizer_rounded,
        keywords: ['eq', 'equalizer', 'bass', 'treble', 'sound', 'dsp', 'reverb'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'audio');
        },
      ),
      _SearchItem(
        category: 'Audio',
        title: 'Bit-Perfect & Hi-Res Output',
        subtitle: 'Direct USB DAC hardware sample-rate matching',
        icon: Icons.album_rounded,
        keywords: ['dac', 'hires', 'bit-perfect', 'sample rate', 'khz', 'usb'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'audio');
        },
      ),
      _SearchItem(
        category: 'Playback',
        title: 'Crossfade & Gapless',
        subtitle: 'Seamless transitions and crossfade seconds slider',
        icon: Icons.play_circle_outline_rounded,
        keywords: ['crossfade', 'gapless', 'transition', 'seconds', 'fade'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'playback');
        },
      ),
      _SearchItem(
        category: 'Playback',
        title: 'Sleep Timer',
        subtitle: 'Automatically stop playback after duration or end of track',
        icon: Icons.timer_outlined,
        keywords: ['sleep', 'timer', 'stop', 'night'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'playback');
        },
      ),
      _SearchItem(
        category: 'Gestures',
        title: 'Mini-Player Swipe Gestures',
        subtitle: 'Left & Right swipe actions (Skip, Previous, Volume)',
        icon: Icons.swipe_rounded,
        keywords: ['swipe', 'miniplayer', 'gesture', 'left', 'right', 'volume'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'gestures');
        },
      ),
      _SearchItem(
        category: 'Library',
        title: 'Rescan Device Storage',
        subtitle: 'Discover newly downloaded songs and update metadata',
        icon: Icons.refresh_rounded,
        keywords: ['scan', 'refresh', 'library', 'songs', 'tracks', 'storage'],
        onTap: () => cubit.rescanLibrary(),
      ),
      _SearchItem(
        category: 'Library',
        title: 'Hidden & Excluded Folders',
        subtitle: 'Exclude voice memos, ringtones, and specific directories',
        icon: Icons.folder_off_rounded,
        keywords: ['hidden', 'folders', 'exclude', 'voice memos', 'ringtones'],
        onTap: () => context.push('/hidden-folders'),
      ),
      _SearchItem(
        category: 'Library',
        title: 'Short Audio Filter',
        subtitle: 'Ignore files under ${state.minDurationSec} seconds',
        icon: Icons.filter_list_rounded,
        keywords: ['filter', 'short', 'duration', 'seconds'],
        onTap: () =>
            _showDurationFilterDialog(context, cubit, state.minDurationSec),
      ),
      _SearchItem(
        category: 'Network',
        title: 'Proxy Settings',
        subtitle: 'HTTP & SOCKS5 proxy routing with latency checks',
        icon: Icons.vpn_lock_rounded,
        keywords: ['proxy', 'socks5', 'http', 'ip', 'port', 'vpn'],
        onTap: () => context.push('/proxy-settings'),
      ),
      _SearchItem(
        category: 'Network',
        title: 'Streaming & Download Audio Quality',
        subtitle: 'Bitrate preferences for online streaming and saved files',
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
        category: 'Storage',
        title: 'Artwork & Audio Cache',
        subtitle: 'Clear cached cover artwork and stream chunks',
        icon: Icons.storage_rounded,
        keywords: ['cache', 'storage', 'clear', 'artwork', 'mb', 'disk'],
        onTap: () {
          _searchController.clear();
          setState(() => _selectedCategoryId = 'storage');
        },
      ),
      _SearchItem(
        category: 'Privacy',
        title: 'Scrobbling (Last.fm & ListenBrainz)',
        subtitle: 'Track listening history and broadcast Now Playing status',
        icon: Icons.equalizer_outlined,
        keywords: ['scrobble', 'lastfm', 'listenbrainz', 'stats', 'history'],
        onTap: () => showScrobblerSettingsModal(context),
      ),
      _SearchItem(
        category: 'Privacy',
        title: 'Privacy Guarantee',
        subtitle: 'Offline-first principles and permissions explanations',
        icon: Icons.security_rounded,
        keywords: ['privacy', 'guarantee', 'offline', 'trackers', 'security'],
        onTap: () => showPrivacyGuaranteeSheet(context),
      ),
      _SearchItem(
        category: 'About',
        title: 'About Pulsr',
        subtitle: 'Version ${AppConfig.appVersion}, build details and licenses',
        icon: Icons.info_outline_rounded,
        keywords: ['about', 'version', 'license', 'developer'],
        onTap: () => showAboutSheet(context),
      ),
    ];
  }

  // ==========================================================================
  // Category IDs & Helper Navigation
  // ==========================================================================

  static const _categoryIds = [
    'audio',
    'playback',
    'appearance',
    'gestures',
    'profiles',
    'automation',
    'library',
    'online',
    'storage',
    'privacy',
    'about',
  ];

  void _assignCategoryTitles(BuildContext context) {
    for (final id in _categoryIds) {
      final c = _catById(id);
      switch (id) {
        case 'audio':
          c.title = 'Audio & Sound';
          break;
        case 'playback':
          c.title = 'Playback';
          break;
        case 'appearance':
          c.title = context.l10n.themeAndAppearance;
          break;
        case 'gestures':
          c.title = context.l10n.gestures;
          break;
        case 'profiles':
          c.title = 'Device Profiles';
          break;
        case 'automation':
          c.title = 'Automation';
          break;
        case 'library':
          c.title = context.l10n.libraryAndScanning;
          break;
        case 'online':
          c.title = AppConfig.ytmEnabled
              ? context.l10n.youtubeMusicAndOnline
              : context.l10n.networkAndProxy;
          break;
        case 'storage':
          c.title = context.l10n.storageAndCache;
          break;
        case 'privacy':
          c.title = context.l10n.privacyAndData;
          break;
        case 'about':
          c.title = context.l10n.about;
          break;
      }
    }
  }

  _Category _catById(String id) =>
      _categories.firstWhere((c) => c.id == id, orElse: () {
        final c = _Category(id, _iconFor(id));
        _categories.add(c);
        return c;
      });

  Widget _catSection(BuildContext context, String id, Widget child) =>
      KeyedSubtree(key: _catById(id).key, child: child);

  IconData _iconFor(String id) => switch (id) {
        'audio' => Icons.equalizer_rounded,
        'playback' => Icons.play_circle_outline_rounded,
        'appearance' => Icons.palette_outlined,
        'gestures' => Icons.swipe_rounded,
        'profiles' => Icons.phone_android_rounded,
        'automation' => Icons.auto_awesome_rounded,
        'library' => Icons.library_music_outlined,
        'online' => Icons.cloud_outlined,
        'storage' => Icons.storage_rounded,
        'privacy' => Icons.privacy_tip_outlined,
        'about' => Icons.info_outline_rounded,
        _ => Icons.circle_outlined,
      };

  // ==========================================================================
  // Section & Tile UI Builders
  // ==========================================================================

  Widget _section(
    BuildContext context,
    String title,
    String subtitle,
    List<Widget> children, {
    GlobalKey? key,
  }) {
    final p = context.palette;
    return KeyedSubtree(
      key: key,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Row(
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '• $subtitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Material(
              color: p.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                side: BorderSide(color: p.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(PulsrPalette p) =>
      Divider(height: 1, indent: 68, color: p.hairline);

  Widget _iconBox(BuildContext context, IconData icon) {
    final p = context.palette;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: p.accentContainer,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: p.accent, size: 19),
    );
  }

  Widget _navTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    Widget? trailing,
    String? trailingBadge,
    VoidCallback? onTap,
  }) {
    final p = context.palette;
    return ListTile(
      leading: _iconBox(context, icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: p.textSecondary, fontSize: 12),
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingBadge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trailingBadge,
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  color: p.textTertiary, size: 20),
            ],
          ),
      onTap: onTap,
    );
  }

  Widget _switchTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final p = context.palette;
    return ListTile(
      leading: _iconBox(context, icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: p.textSecondary, fontSize: 12),
      ),
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: p.accent,
        activeThumbColor: Colors.white,
        onChanged: onChanged,
      ),
    );
  }

  // ==========================================================================
  // Dialogs
  // ==========================================================================

  void _showDurationFilterDialog(
    BuildContext context,
    SettingsCubit cubit,
    int currentSec,
  ) {
    int selected = currentSec;
    PulsrDialogHelper.showPulsrDialog<void>(
      context,
      title: Text(context.l10n.minDuration),
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.excludeTracksUnder(selected),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.settings_backup_restore,
                      size: 20,
                      color: selected == 30
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.38)
                          : context.palette.accent),
                  tooltip: context.l10n.resetToDefault30s,
                  visualDensity: VisualDensity.compact,
                  onPressed: selected == 30
                      ? null
                      : () => setDialogState(() => selected = 30),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PulsrSlider(
              value: selected.toDouble(),
              min: 0,
              max: 120,
              divisions: 12,
              onChanged: (val) {
                setDialogState(() => selected = val.toInt());
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel)),
        ElevatedButton(
          onPressed: () {
            cubit.setMinDuration(selected);
            Navigator.pop(context);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }

  Future<void> _removeMissingFiles(
    BuildContext context,
    SettingsCubit cubit,
  ) async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showPulsrDialog<bool>(
      context,
      title: Text(l10n.removeMissingFilesConfirmTitle),
      content: Text(l10n.removeMissingFilesConfirmBody),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel)),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.remove),
        ),
      ],
    );
    if (confirmed != true) return;
    final removed = await cubit.removeMissingFiles();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.removedMissingTracks(removed)),
      ),
    );
  }
}

class _SearchItem {
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keywords;
  final Widget? trailing;
  final VoidCallback? onTap;

  _SearchItem({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keywords,
    this.trailing,
    this.onTap,
  });
}
