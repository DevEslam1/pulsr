import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../cubit/settings_accessibility_ext.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import '../../../core/utils/platform_capabilities.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import 'widgets/audio_sound_section.dart';
import 'widgets/automation_rules_sheet.dart';
import 'widgets/backup_section.dart';
import 'widgets/device_profiles_section.dart';
import 'widgets/experience_mode_section.dart';
import 'widgets/smart_audio_section.dart';
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

class _SettingsCategoryItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tintColor;

  const _SettingsCategoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tintColor,
  });
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

        final isTabletView =
            context.isLargeTablet || MediaQuery.sizeOf(context).width >= 900;
        final effectiveCategoryId =
            (isTabletView && _selectedCategoryId == 'all')
                ? 'audio'
                : _selectedCategoryId;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: isTabletView
                ? _buildTabletLayout(context, state, cubit, effectiveCategoryId)
                : _buildPhoneLayout(context, state, cubit),
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
                      context.l10n.settingsHeaderTagline(AppConfig.appVersion),
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
                hintText: context.l10n.settingsSearchPlaceholder,
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
  // ==========================================================================
  // Category Metadata & Definitions
  // ==========================================================================

  List<_SettingsCategoryItem> _getCategories(BuildContext context,
      {bool pro = true}) {
    final categories = <_SettingsCategoryItem>[
      _SettingsCategoryItem(
        id: 'audio',
        title: context.l10n.audioAndSound,
        subtitle: context.l10n.settingsCategoryAudioSubtitle,
        icon: Icons.equalizer_rounded,
        tintColor: const Color(0xFFFF9500),
      ),
      _SettingsCategoryItem(
        id: 'playback',
        title: context.l10n.playback,
        subtitle: context.l10n.settingsCategoryPlaybackSubtitle,
        icon: Icons.play_circle_outline_rounded,
        tintColor: const Color(0xFFAF52DE),
      ),
      _SettingsCategoryItem(
        id: 'appearance',
        title: context.l10n.settingsCategoryAppearance,
        subtitle: context.l10n.settingsCategoryAppearanceSubtitle,
        icon: Icons.palette_outlined,
        tintColor: const Color(0xFFFF2D55),
      ),
      _SettingsCategoryItem(
        id: 'gestures',
        title: context.l10n.gestures,
        subtitle: context.l10n.settingsCategoryGesturesSubtitle,
        icon: Icons.swipe_rounded,
        tintColor: const Color(0xFF007AFF),
      ),
      _SettingsCategoryItem(
        id: 'profiles',
        title: context.l10n.settingsCategoryProfiles,
        subtitle: context.l10n.settingsCategoryProfilesSubtitle,
        icon: Icons.devices_other_rounded,
        tintColor: const Color(0xFF5856D6),
      ),
      _SettingsCategoryItem(
        id: 'library',
        title: context.l10n.navLibrary,
        subtitle: context.l10n.settingsCategoryLibrarySubtitle,
        icon: Icons.library_music_outlined,
        tintColor: const Color(0xFF34C759),
      ),
      _SettingsCategoryItem(
        id: 'online',
        title: context.l10n.settingsCategoryOnline,
        subtitle: context.l10n.settingsCategoryOnlineSubtitle,
        icon: Icons.cloud_outlined,
        tintColor: const Color(0xFF5AC8FA),
      ),
      _SettingsCategoryItem(
        id: 'storage',
        title: context.l10n.storageAndCache,
        subtitle: context.l10n.settingsCategoryStorageSubtitle,
        icon: Icons.storage_rounded,
        tintColor: const Color(0xFFFFCC00),
      ),
      _SettingsCategoryItem(
        id: 'privacy',
        title: context.l10n.settingsCategoryPrivacy,
        subtitle: context.l10n.settingsCategoryPrivacySubtitle,
        icon: Icons.shield_outlined,
        tintColor: const Color(0xFF30B0C7),
      ),
      _SettingsCategoryItem(
        id: 'about',
        title: context.l10n.settingsCategoryAbout,
        subtitle: context.l10n.settingsCategoryAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        tintColor: const Color(0xFF8E8E93),
      ),
    ];
    // Normal mode hides the advanced "Profiles & Rules" surface (device-profile
    // mappings and automation triggers). Smart Audio lives in Audio & Sound.
    if (!pro) {
      categories.removeWhere((c) => c.id == 'profiles');
    }
    return categories;
  }

  // ==========================================================================
  // Category Filter Bar (Pills for Phone)
  // ==========================================================================

  Widget _buildCategoryFilterBar(BuildContext context, SettingsState state) {
    final p = context.palette;
    final categories = _getCategories(context, pro: state.isProfessional);
    final items = [
      (id: 'all', title: context.l10n.all, icon: Icons.tune_rounded, color: p.accent),
      ...categories.map(
          (c) => (id: c.id, title: c.title, icon: c.icon, color: c.tintColor)),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding:
            EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = _selectedCategoryId == item.id;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategoryId = item.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
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
                    color: isSelected ? p.accent : item.color,
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
  // Layouts: Tablet Master-Detail & Phone Category Views
  // ==========================================================================

  Widget _buildTabletLayout(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
    String activeCatId,
  ) {
    final p = context.palette;
    final categories = _getCategories(context, pro: state.isProfessional);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Master Navigation Pane
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabletMasterHeader(context),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  physics: const BouncingScrollPhysics(),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final cat = categories[i];
                    final isSelected = activeCatId == cat.id;

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedCategoryId = cat.id;
                            if (_searchQuery.isNotEmpty) {
                              _searchController.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? p.accent.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            border: Border.all(
                              color: isSelected
                                  ? p.accent.withValues(alpha: 0.45)
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: cat.tintColor.withValues(
                                      alpha: isSelected ? 0.22 : 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  cat.icon,
                                  size: 20,
                                  color: cat.tintColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected
                                            ? p.accent
                                            : p.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      cat.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: isSelected
                                    ? p.accent
                                    : p.textTertiary.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Vertical hairline divider
        Container(
          width: 1,
          color: p.hairline,
        ),

        // Right Detail Pane
        Expanded(
          child: _searchQuery.isNotEmpty
              ? _buildSearchResultsList(context, state, cubit)
              : _buildDetailPane(context, state, cubit, activeCatId),
        ),
      ],
    );
  }

  Widget _buildTabletMasterHeader(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.settings,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.settingsHeaderTaglineShort(AppConfig.appVersion),
            style: TextStyle(
              color: p.textTertiary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // Search Box
          Container(
            height: 42,
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
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.settingsSearchPlaceholder,
                hintStyle: TextStyle(
                  color: p.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _searchQuery.isNotEmpty ? p.accent : p.textTertiary,
                  size: 19,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: p.textSecondary, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPane(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
    String activeCatId,
  ) {
    final categories = _getCategories(context, pro: state.isProfessional);
    final currentCat = categories.firstWhere(
      (c) => c.id == activeCatId,
      orElse: () => categories.first,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(activeCatId),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Adaptive.pagePadding(context),
                18,
                Adaptive.pagePadding(context),
                160,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildCategoryHeroHeader(context, currentCat),
                const SizedBox(height: 16),
                _experienceModeCard(context),
                ..._buildCategoryWidgets(context, activeCatId, state, cubit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneLayout(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            _buildTopHeader(context),
            if (_searchQuery.isEmpty) _buildCategoryFilterBar(context, state),
            const SizedBox(height: 6),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResultsList(context, state, cubit)
                  : _buildPhoneCategoryView(context, state, cubit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneCategoryView(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    if (_selectedCategoryId == 'all') {
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
          if (AppConfig.isCloudSyncAllowed || AppConfig.ytmEnabled)
            const SettingsHeroCard(),
          _experienceModeCard(context),
          ..._buildCategoryWidgets(context, 'audio', state, cubit),
          ..._buildCategoryWidgets(context, 'playback', state, cubit),
          ..._buildCategoryWidgets(context, 'appearance', state, cubit),
          ..._buildCategoryWidgets(context, 'gestures', state, cubit),
          if (state.isProfessional)
            ..._buildCategoryWidgets(context, 'profiles', state, cubit),
          ..._buildCategoryWidgets(context, 'library', state, cubit),
          ..._buildCategoryWidgets(context, 'online', state, cubit),
          ..._buildCategoryWidgets(context, 'storage', state, cubit),
          _buildPrivacyBackupSection(context),
          ..._buildCategoryWidgets(context, 'about', state, cubit),
        ],
      );
    }

    final categories = _getCategories(context, pro: state.isProfessional);
    final currentCat = categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => categories.first,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_selectedCategoryId),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: 160,
            top: 10,
            left: Adaptive.pagePadding(context),
            right: Adaptive.pagePadding(context),
          ),
          children: [
            _buildCategoryHeroHeader(context, currentCat),
            const SizedBox(height: 14),
            ..._buildCategoryWidgets(
                context, _selectedCategoryId, state, cubit),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryHeroHeader(
    BuildContext context,
    _SettingsCategoryItem cat,
  ) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cat.tintColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(cat.icon, color: cat.tintColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.title,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cat.subtitle,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Always-visible Normal/Professional switch shown at the top of Settings.
  Widget _experienceModeCard(BuildContext context) => _section(
        context,
        context.l10n.experienceModeTitle,
        context.l10n.experienceModeSubtitle,
        [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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
    switch (catId) {
      case 'audio':
        return [
          _section(
            context,
            context.l10n.smartAudioTitle,
            context.l10n.settingsSmartAudioSectionSubtitle,
            [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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
            ],
            key: _catById('about').key,
          ),
        ];
      default:
        return [];
    }
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
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: p.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    context.l10n.activeLabel,
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
                context.l10n.settingsNoSettingsFound(_searchQuery),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.settingsSearchHint,
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
            showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const EqualizerSheet(),
            );
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
        onTap: () => showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const SleepTimerSheet(),
        ),
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
          c.title = context.l10n.audioAndSound;
          break;
        case 'playback':
          c.title = context.l10n.playback;
          break;
        case 'appearance':
          c.title = context.l10n.themeAndAppearance;
          break;
        case 'gestures':
          c.title = context.l10n.gestures;
          break;
        case 'profiles':
          c.title = context.l10n.deviceProfilesTitle;
          break;
        case 'automation':
          c.title = context.l10n.settingsAutomationTitle;
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
      onTap: () => onChanged(!value),
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

  /// Professional-only setting; hidden from Normal-mode search.
  final bool pro;

  _SearchItem({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keywords,
    this.trailing,
    this.onTap,
    this.pro = false,
  });
}
