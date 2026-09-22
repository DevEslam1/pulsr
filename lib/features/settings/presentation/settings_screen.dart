import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/missing_artwork_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/pulsr_slider.dart';
import '../../../core/widgets/pulsr_switch.dart';
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
import 'widgets/download_settings_tiles.dart';
import 'widgets/experience_mode_section.dart';
import 'widgets/smart_audio_section.dart';
import 'widgets/playback_section.dart';
import 'widgets/scrobbler_settings_modal.dart';
import 'widgets/settings_hero_card.dart';
import 'widgets/settings_picker_sheets.dart';
import 'widgets/settings_section.dart';
import 'widgets/storage_cache_section.dart';
import 'widgets/theme_schedule_row.dart';
import 'widgets/ytm_account_disconnect_dialog.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
part 'settings_category_sections_a.dart';
part 'settings_category_sections_b.dart';

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

class _SettingsScreenState extends State<SettingsScreen>
    with SettingsCategorySectionsA, SettingsCategorySectionsB {
  final ScrollController _scrollController = ScrollController();
  @override
  final TextEditingController _searchController = TextEditingController();
  late final List<_Category> _categories;

  @override
  String _selectedCategoryId = 'all';
  @override
  String _searchQuery = '';

  bool _soundPlaybackExpanded = true;
  bool _appearanceGesturesExpanded = true;
  bool _systemPrivacyExpanded = true;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _categories = _categoryIds.map((id) => _Category(id, _iconFor(id))).toList();
    // FIX-H05: Debounce search results via Timer with immediate clear on empty
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text.isEmpty && _searchQuery.isNotEmpty) {
        _searchDebounce?.cancel();
        if (mounted) setState(() => _searchQuery = '');
        return;
      }
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        final q = text.trim().toLowerCase();
        if (mounted && q != _searchQuery) {
          setState(() => _searchQuery = q);
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _assignCategoryTitles(context);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();

        final isTabletView =
            Adaptive.widthOf(context) >= 720 || context.isTwoPane;
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
      padding: EdgeInsetsDirectional.fromSTEB(horizontalPad, AppSpacing.md, horizontalPad, AppSpacing.xs),
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
                        fontSize: AppFontSize.display,
                        fontWeight: FontWeight.w900,
                        letterSpacing: AppTracking.heading,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      context.l10n.settingsHeaderTagline(AppConfig.appVersion),
                      style: TextStyle(
                        color: p.textTertiary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Search Box
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: _searchQuery.isNotEmpty
                    ? p.accent.withValues(alpha: 0.55)
                    : p.hairline,
                width: _searchQuery.isNotEmpty ? 1.5 : 1.0,
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.body,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.settingsSearchPlaceholder,
                hintStyle: TextStyle(
                  color: p.textTertiary,
                  fontSize: AppFontSize.bodySmall,
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
                          tooltip: context.l10n.clear,
                          onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding:
            EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = _selectedCategoryId == item.id;

          return Semantics(
            selected: isSelected,
            button: true,
            label: item.title,
            child: PulsrPressable(
            pressedScale: 0.94,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategoryId = item.id);
            },
            child: AnimatedContainer(
              duration: context.motionMs(180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: isSelected
                    ? p.accent.withValues(alpha: 0.16)
                    : p.surfaceContainer,
                borderRadius: AppRadii.full,
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
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected ? p.accent : p.textPrimary,
                      fontSize: AppFontSize.label,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final masterWidth = screenWidth < 1000 ? 280.0 : 320.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Master Navigation Pane
        SizedBox(
          width: masterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabletMasterHeader(context),
              const SizedBox(height: AppSpacing.s6),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s14,
                    AppSpacing.xxs,
                    AppSpacing.s14,
                    140 + MediaQuery.paddingOf(context).bottom,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xxs),
                  itemBuilder: (context, i) {
                    final cat = categories[i];
                    final isSelected = activeCatId == cat.id;

                    return PulsrPressable(
                      pressedScale: 0.985,
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
                        duration: context.motionMs(180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? p.accent.withValues(alpha: 0.14)
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
                                borderRadius: BorderRadius.circular(AppRadii.r12),
                              ),
                              child: Icon(
                                cat.icon,
                                size: 19,
                                color: cat.tintColor,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
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
                                      fontSize: AppFontSize.bodySmall,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s2),
                                  Text(
                                    cat.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.caption,
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
                                  : p.textTertiary.withValues(alpha: 0.5),
                            ),
                          ],
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
          child: RepaintBoundary(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResultsList(context, state, cubit)
                : _buildDetailPane(context, state, cubit, activeCatId),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletMasterHeader(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.settings,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.headline,
                    fontWeight: FontWeight.w900,
                    letterSpacing: AppTracking.heading,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                decoration: BoxDecoration(
                  color: p.accentContainer,
                  borderRadius: BorderRadius.circular(AppRadii.r6),
                ),
                child: Text(
                  'v${AppConfig.appVersion}',
                  style: TextStyle(
                    color: p.accent,
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            context.l10n.settingsHeaderTaglineShort(AppConfig.appVersion),
            style: TextStyle(
              color: p.textTertiary,
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Search Box
          Container(
            height: 40,
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
                fontSize: AppFontSize.bodySmall,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.settingsSearchPlaceholder,
                hintStyle: TextStyle(
                  color: p.textTertiary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _searchQuery.isNotEmpty ? p.accent : p.textTertiary,
                  size: 18,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded,
                              color: p.textSecondary, size: 16),
                          tooltip: context.l10n.clear,
                          onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
    final bottomInset = 140 + MediaQuery.paddingOf(context).bottom;

    return AnimatedSwitcher(
      duration: context.motionMs(220),
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
              padding: EdgeInsetsDirectional.fromSTEB(
                Adaptive.pagePadding(context),
                AppSpacing.md,
                Adaptive.pagePadding(context),
                bottomInset,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildCategoryHeroHeader(context, currentCat),
                const SizedBox(height: AppSpacing.md),
                if (activeCatId == 'audio') ...[
                  _experienceModeCard(context),
                ],
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
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            _buildTopHeader(context),
            if (_searchQuery.isEmpty) _buildCategoryFilterBar(context, state),
            const SizedBox(height: AppSpacing.md),
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
    final bottomInset = 140 + MediaQuery.paddingOf(context).bottom;
    final horizontalPad = Adaptive.pagePadding(context);

    if (_selectedCategoryId == 'all') {
      return ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsetsDirectional.only(
          bottom: bottomInset,
          top: AppSpacing.md,
          start: horizontalPad,
          end: horizontalPad,
        ),
        children: [
          if (AppConfig.isCloudSyncAllowed || AppConfig.ytmEnabled)
            const SettingsHeroCard(),
          _experienceModeCard(context),
          const SizedBox(height: AppSpacing.sm),
          _buildSuperSection(
            context,
            title: 'Sound & Playback',
            icon: Icons.graphic_eq_rounded,
            isExpanded: _soundPlaybackExpanded,
            onToggle: () => setState(
                () => _soundPlaybackExpanded = !_soundPlaybackExpanded),
            children: [
              ..._buildCategoryWidgets(context, 'audio', state, cubit),
              ..._buildCategoryWidgets(context, 'playback', state, cubit),
              if (state.isProfessional)
                ..._buildCategoryWidgets(context, 'profiles', state, cubit),
            ],
          ),
          _buildSuperSection(
            context,
            title: 'Appearance & Gestures',
            icon: Icons.palette_outlined,
            isExpanded: _appearanceGesturesExpanded,
            onToggle: () => setState(
                () => _appearanceGesturesExpanded = !_appearanceGesturesExpanded),
            children: [
              ..._buildCategoryWidgets(context, 'appearance', state, cubit),
              ..._buildCategoryWidgets(context, 'gestures', state, cubit),
            ],
          ),
          _buildSuperSection(
            context,
            title: 'System & Privacy',
            icon: Icons.settings_suggest_rounded,
            isExpanded: _systemPrivacyExpanded,
            onToggle: () => setState(
                () => _systemPrivacyExpanded = !_systemPrivacyExpanded),
            children: [
              ..._buildCategoryWidgets(context, 'library', state, cubit),
              ..._buildCategoryWidgets(context, 'online', state, cubit),
              ..._buildCategoryWidgets(context, 'storage', state, cubit),
              _buildPrivacyBackupSection(context),
              ..._buildCategoryWidgets(context, 'about', state, cubit),
            ],
          ),
        ],
      );
    }

    final categories = _getCategories(context, pro: state.isProfessional);
    final currentCat = categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => categories.first,
    );

    return AnimatedSwitcher(
      duration: context.motionMs(220),
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
          padding: EdgeInsetsDirectional.only(

            bottom: bottomInset,
            top: AppSpacing.md,
            start: horizontalPad,
            end: horizontalPad,
          ),
          children: [
            _buildCategoryHeroHeader(context, currentCat),
            const SizedBox(height: AppSpacing.md),
            if (_selectedCategoryId == 'audio') ...[
              _experienceModeCard(context),
            ],
            ..._buildCategoryWidgets(
                context, _selectedCategoryId, state, cubit),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: '$title, ${isExpanded ? "expanded" : "collapsed"}',
            child: PulsrPressable(
              pressedScale: 0.985,
              onTap: () {
                HapticFeedback.selectionClick();
                onToggle();
              },
              child: AnimatedContainer(
                duration: context.motionMs(200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isExpanded
                      ? p.surfaceContainer
                      : p.surfaceContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(
                    color: isExpanded
                        ? p.accent.withValues(alpha: 0.45)
                        : p.hairline,
                    width: isExpanded ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? p.accent.withValues(alpha: 0.16)
                            : p.accentContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(AppRadii.r10),
                      ),
                      child: Icon(icon, color: p.accent, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          color: isExpanded ? p.textPrimary : p.textSecondary,
                          fontSize: AppFontSize.callout,
                          fontWeight: FontWeight.w800,
                          letterSpacing: AppTracking.heading,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.0 : -0.25,
                      duration: context.motionMs(220),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? p.accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? p.accent : p.textTertiary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: context.motionMs(250),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeroHeader(
    BuildContext context,
    _SettingsCategoryItem cat,
  ) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
            child: Icon(cat.icon, color: cat.tintColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.title,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.bodyLarge,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.title,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  cat.subtitle,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.label,
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
            padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
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
                padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
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
                padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
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
                Icons.person_outline_rounded,
                'Developer',
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

  // ==========================================================================
  // Appearance Section
  // ==========================================================================


  // ==========================================================================
  // Gestures Section
  // ==========================================================================


  // ==========================================================================
  // Library & Scanning Section
  // ==========================================================================


  // ==========================================================================
  // Online / Streaming Section
  // ==========================================================================


  // ==========================================================================
  // Privacy & Backup Section
  // ==========================================================================


  // ==========================================================================
  // Live Instant Search Mode
  // ==========================================================================


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
        default:
          c.title = id;
          break;
      }
    }
  }

  @override
  _Category _catById(String id) =>
      _categories.firstWhere((c) => c.id == id, orElse: () => _categories.first);

  Widget _catSection(BuildContext context, String id, Widget child) =>
      KeyedSubtree(key: _catById(id).key, child: child);

  IconData _iconFor(String id) => switch (id) {
        'audio' => Icons.equalizer_rounded,
        'playback' => Icons.play_circle_outline_rounded,
        'appearance' => Icons.palette_outlined,
        'gestures' => Icons.swipe_rounded,
        'profiles' => Icons.phone_android_rounded,
        'automation' => Icons.bolt_rounded,
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

  @override
  Widget _section(
    BuildContext context,
    String title,
    String subtitle,
    List<Widget> children, {
    GlobalKey? key,
    IconData? icon,
  }) {
    return KeyedSubtree(
      key: key,
      child: SettingsSection(
        icon: icon,
        title: title,
        subtitle: subtitle.isNotEmpty ? subtitle : null,
        children: children,
      ),
    );
  }

  @override
  Widget _divider(PulsrPalette p) =>
      Divider(height: 1, indent: 72, color: p.hairline);

  @override
  Widget _iconBox(BuildContext context, IconData icon) {
    final p = context.palette;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: p.accentContainer,
        borderRadius: BorderRadius.circular(AppRadii.r12),
      ),
      child: Icon(icon, color: p.accent, size: 20),
    );
  }

  @override
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
    return PulsrPressable(
      pressedScale: 0.988,
      onTap: onTap,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s2),
        leading: _iconBox(context, icon),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.body,
            letterSpacing: AppTracking.none,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.s2),
            Text(
              subtitle,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                height: 1.32,
              ),
            ),
          ],
        ),
        trailing: trailing ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailingBadge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                    margin: const EdgeInsetsDirectional.only(end: AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.r6),
                    ),
                    child: Text(
                      trailingBadge,
                      style: TextStyle(
                        color: p.accent,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.label,
                      ),
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: p.textTertiary.withValues(alpha: 0.7),
                  size: 20,
                ),
              ],
            ),
      ),
    );
  }

  @override
  Widget _switchTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final p = context.palette;
    return PulsrPressable(
      pressedScale: 0.988,
      onTap: () => onChanged(!value),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s2),
        leading: _iconBox(context, icon),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.body,
            letterSpacing: AppTracking.none,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.s2),
            Text(
              subtitle,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                height: 1.32,
              ),
            ),
          ],
        ),
        trailing: PulsrSwitch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ==========================================================================
  // Dialogs
  // ==========================================================================

  @override
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
            const SizedBox(height: AppSpacing.sm),
            PulsrSlider(
              value: selected.toDouble(),
              min: 0,
              max: 120,
              divisions: 12,
              semanticLabel: context.l10n.excludeTracksUnder(selected),
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
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.accent,
            foregroundColor: context.palette.onAccent,
          ),
          onPressed: () {
            cubit.setMinDuration(selected);
            Navigator.pop(context);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }

  @override
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
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.error,
            foregroundColor: Colors.white,
          ),
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

  @override
  Future<void> _fetchMissingArtwork(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showPulsrDialog<bool>(
      context,
      title: Text(l10n.fetchMissingArtworkTitle),
      content: Text(l10n.fetchMissingArtworkBody),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.accent,
            foregroundColor: context.palette.onAccent,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.fetchArtwork),
        ),
      ],
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.fetchArtwork)),
    );
    final int count;
    try {
      if (!getIt.isRegistered<MissingArtworkService>()) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.artworkServiceUnavailable)));
        return;
      }
      count = await getIt<MissingArtworkService>()
          .fetchAndPersistMissingArtwork();
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.artworkServiceUnavailable)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? l10n.updatedArtworkForAlbums(count)
            : l10n.noMissingArtworkFound),
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
