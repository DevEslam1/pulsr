import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../core/errors/failures.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../domain/models/ytm_track.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../cubit/home_cubit.dart';

import 'package:go_router/go_router.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// Scales a fixed two-line card title box (34px at the default text size) with
/// the user's Dynamic Type setting so large text never clips. Pixel-identical
/// at the 1.0x scale.
double _scaledTitleBoxHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(34.0).clamp(34.0, 78.0);

/// Grows a fixed-height horizontal card carousel just enough to fit scaled
/// two-line titles. Pixel-identical at the 1.0x scale.
double _scaledCarouselHeight(BuildContext context, bool isTablet) {
  final delta =
      (MediaQuery.textScalerOf(context).scale(34.0) - 34.0).clamp(0.0, 44.0);
  return (isTablet ? 232.0 : 212.0) + delta;
}

class HomeScreen extends StatelessWidget {
  final YtmService? ytmService;
  final YtmAccountService? ytmAccountService;
  final GetSongsUseCase? getSongsUseCase;

  const HomeScreen({
    super.key,
    this.ytmService,
    this.ytmAccountService,
    this.getSongsUseCase,
  });

  @override
  Widget build(BuildContext context) {
    final accountService = ytmAccountService ?? getIt<YtmAccountService>();
    final ytm = ytmService ?? getIt<YtmService>();
    return BlocProvider<HomeCubit>(
      create: (context) => HomeCubit(
        ytmService: ytm,
        accountService: accountService,
      ),
      child: _HomeScreenContent(
        ytmService: ytmService,
        ytmAccountService: ytmAccountService,
        getSongsUseCase: getSongsUseCase,
      ),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  final YtmService? ytmService;
  final YtmAccountService? ytmAccountService;
  final GetSongsUseCase? getSongsUseCase;

  const _HomeScreenContent({
    this.ytmService,
    this.ytmAccountService,
    this.getSongsUseCase,
  });

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> {
  int _selectedTab = 0; // 0: Local, 1: Online
  String _selectedOnlineCategory = 'Recommended For You';

  YtmAccountService get _ytmAccountService =>
      widget.ytmAccountService ?? getIt<YtmAccountService>();
  GetSongsUseCase get _getSongsUseCase =>
      widget.getSongsUseCase ?? getIt<GetSongsUseCase>();

  late final HomeCubit _homeCubit;

  // FIX-M12: Use monotonic Stopwatch for 60-second TTL cache for 200 songs shared by Daily Drive and Focus Flow
  List<SongsTableData>? _cachedSongs200;
  Stopwatch? _cachedSongs200Stopwatch;
  StreamSubscription? _librarySub;

  Future<List<SongsTableData>> _getQuickActionSongs(GetSongsUseCase useCase) async {
    if (_cachedSongs200 != null &&
        _cachedSongs200Stopwatch != null &&
        _cachedSongs200Stopwatch!.isRunning &&
        _cachedSongs200Stopwatch!.elapsed < const Duration(seconds: 60)) {
      return _cachedSongs200!;
    }
    final res = await useCase.getAllSongs(limit: 50);
    final list = res.fold((_) => <SongsTableData>[], (r) => r);
    _cachedSongs200 = list;
    _cachedSongs200Stopwatch = Stopwatch()..start();
    return list;
  }

  List<String> get _onlineCategories => _homeCubit.onlineCategories;
  bool _notificationDenied = false;

  @override
  void initState() {
    super.initState();
    _homeCubit = context.read<HomeCubit>();
    final isLoggedIn = _ytmAccountService.isLoggedIn;
    _selectedOnlineCategory =
        isLoggedIn ? 'Recommended For You' : 'Trending Egypt';
    _ytmAccountService.loginState.addListener(_onLoginStateChanged);
    _checkNotificationDenied();
    final libraryCubit = context.read<LibraryCubit?>();
    if (libraryCubit != null) {
      _librarySub = libraryCubit.stream.listen((_) {
        // H-06: A library emission can land while this screen is being disposed.
        if (!mounted) return;
        _cachedSongs200 = null;
        _cachedSongs200Stopwatch = null;
      });
    }
  }

  Future<void> _checkNotificationDenied() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final denied = prefs.getBool('notification_permission_denied') ?? false;
      if (denied && mounted) {
        setState(() => _notificationDenied = true);
      }
    } catch (_) {}
  }

  void _onLoginStateChanged() {
    if (!mounted) return;
    setState(() {
      context.read<HomeCubit>().clearCache();
      final isLoggedIn = _ytmAccountService.isLoggedIn;
      _selectedOnlineCategory =
          isLoggedIn ? 'Recommended For You' : 'Trending Egypt';
    });
  }

  @override
  void dispose() {
    _librarySub?.cancel();
    // H-06: Stop the TTL stopwatch so it doesn't keep running after disposal.
    _cachedSongs200Stopwatch?.stop();
    _ytmAccountService.loginState.removeListener(_onLoginStateChanged);
    super.dispose();
  }

  String _getGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return context.l10n.goodMorning;
    if (hour < 17) return context.l10n.goodAfternoon;
    return context.l10n.goodEvening;
  }

  String _categoryLabel(BuildContext context, String category) {
    switch (category) {
      case 'Recommended For You':
        return context.l10n.browseRecommendedForYou;
      case 'Trending Egypt':
        return context.l10n.browseTrendingEgypt;
      case 'Mahraganat':
        return context.l10n.browseMahraganat;
      case 'Arabic Pop':
        return context.l10n.browseArabicPop;
      case 'Global Top Hits':
        return context.l10n.browseGlobalTopHits;
      case 'New Releases':
        return context.l10n.newReleases;
      case 'Chill & Lo-Fi':
        return context.l10n.browseChillLofi;
      case 'Pop Mix':
        return context.l10n.browsePopMix;
      case 'Hip-Hop':
        return context.l10n.browseHipHop;
      case 'Workout Energy':
        return context.l10n.browseWorkoutEnergy;
      case 'Rock & Metal':
        return context.l10n.browseRockMetal;
      case 'Acoustic':
        return context.l10n.browseAcoustic;
      default:
        return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = context.isTablet;
    final getSongsUseCase = _getSongsUseCase;
    final playerCubit = context.read<PlayerCubit>();
    final offlineOnly = context.select<SettingsCubit, bool>(
        (c) => c.state.offlineOnlyMode);
    final showOnlineTab = AppConfig.ytmEnabled && !offlineOnly;

    // Reset to local tab if offline only is enabled
    final currentTab = showOnlineTab ? _selectedTab : 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              onRefresh: () async {
                if (currentTab == 0) {
                  final count =
                      await context.read<SettingsCubit>().rescanLibrary();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.scanResult(count)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  setState(() {
                    context.read<HomeCubit>().clearCache();
                  });
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
                children: [
                  // ---------- Header ----------
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context),
                        16, Adaptive.pagePadding(context), 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(DateTime.now()),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: p.textTertiary),
                              ),
                              const SizedBox(height: AppSpacing.s6),
                              Text(
                                _getGreeting(context),
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.s10),
                          decoration: BoxDecoration(
                            color: p.accentContainer,
                            borderRadius: BorderRadius.circular(AppRadii.r16),
                            border: Border.all(color: p.hairline),
                            boxShadow: [
                              BoxShadow(
                                  color: p.glow,
                                  blurRadius: 24,
                                  spreadRadius: -4,
                                  offset: const Offset(0, 8)),
                            ],
                          ),
                          child: PulsrLogo(
                              size: 26,
                              color: p.accent,
                              glowColor: p.glow,
                              animate: false),
                        ),
                      ],
                    ),
                  ),

                  // ---------- Notification Permission Denied Banner (B-37) ----------
                  if (_notificationDenied)
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        Adaptive.pagePadding(context),
                        AppSpacing.sm,
                        Adaptive.pagePadding(context),
                        0,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.notifications_off_outlined,
                                color: p.accent, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                context.l10n.playbackStopsScreenOff,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await openAppSettings();
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('notification_permission_denied', false);
                                if (mounted) setState(() => _notificationDenied = false);
                              },
                              child: Text(context.l10n.openSettings),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('notification_permission_denied', false);
                                if (mounted) setState(() => _notificationDenied = false);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ---------- Segmented Tab Selector (Local vs Online) ----------
                  if (showOnlineTab) ...[
                    const SizedBox(height: AppSpacing.md),
                    PulsrSegmentedControl(
                      margin: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      selectedIndex: currentTab,
                      onChanged: (i) => setState(() => _selectedTab = i),
                      segments: [
                        PulsrSegment(
                          label: context.l10n.localMusic,
                          icon: Icons.library_music_rounded,
                        ),
                        PulsrSegment(
                          label: context.l10n.onlineStream,
                          icon: Icons.public_rounded,
                        ),
                      ],
                    ),
                  ] else if (offlineOnly) ...[
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 14, color: p.textTertiary),
                          const SizedBox(width: AppSpacing.s6),
                          Expanded(
                            child: Text(
                              context.l10n.homeOfflineNotice,
                              style: TextStyle(
                                  color: p.textTertiary,
                                  fontSize: AppFontSize.label),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ---------- Quick Discovery Tools Row ----------
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      children: [
                        if (AppConfig.ytmEnabled && !offlineOnly) ...[
                          _DiscoveryChip(
                            icon: Icons.explore_rounded,
                            label: context.l10n.ytmExplore,
                            iconColor: p.primary,
                            onTap: () => context.push('/ytm-explore'),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        _DiscoveryChip(
                          icon: Icons.radio_rounded,
                          label: context.l10n.radioTitle,
                          iconColor: p.warning,
                          onTap: () => context.push('/radio'),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _DiscoveryChip(
                          icon: Icons.queue_music_rounded,
                          label: context.l10n.queue,
                          iconColor: p.info,
                          onTap: () => context.push('/queue'),
                        ),
                        if (AppConfig.ytmEnabled && !offlineOnly) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _DiscoveryChip(
                            icon: Icons.downloading_rounded,
                            label: context.l10n.downloadsTitle,
                            iconColor: p.success,
                            onTap: () => context.push('/downloads'),
                          ),
                        ],
                        const SizedBox(width: AppSpacing.xs),
                        _DiscoveryChip(
                          icon: Icons.apps_rounded,
                          label: context.l10n.browseMoreTools,
                          iconColor: p.textSecondary,
                          onTap: () => _showDiscoveryToolsSheet(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ---------- Content (Local vs Online) ----------
                  if (currentTab == 0)
                    _buildLocalView(
                        context, p, getSongsUseCase, playerCubit, isTablet)
                  else if (showOnlineTab)
                    _buildOnlineView(context, p, playerCubit, isTablet),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps Home focused on playback while still exposing the library "power
  /// tools" one tap away. Restraint borrowed from Apple Music: a short primary
  /// row plus a single overflow entry instead of a dozen equal-weight chips.
  void _showDiscoveryToolsSheet(BuildContext context) {
    final p = context.palette;
    final tools = <({
      IconData icon,
      String label,
      Color color,
      VoidCallback onTap
    })>[
      (
        icon: Icons.grid_view_rounded,
        label: context.l10n.artworkWall,
        color: p.accent,
        onTap: () => context.push('/artwork-grid'),
      ),
      (
        icon: Icons.insights_rounded,
        label: context.l10n.browseLibraryStats,
        color: p.warning,
        onTap: () => context.push('/library-stats'),
      ),
      (
        icon: Icons.cleaning_services_rounded,
        label: context.l10n.duplicateCleaner,
        color: p.success,
        onTap: () => context.push('/duplicate-finder'),
      ),
      (
        icon: Icons.palette_rounded,
        label: context.l10n.themeStudio,
        color: p.favorite,
        onTap: () => context.push('/theme-studio'),
      ),
    ];
    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) {
        final sp = sheetContext.palette;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.sm),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: sp.surface,
              borderRadius: BorderRadius.circular(AppRadii.r24),
              border: Border.all(color: sp.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: sp.hairline,
                    borderRadius: BorderRadius.circular(AppRadii.r2),
                  ),
                ),
                for (final tool in tools)
                  ListTile(
                    leading: Icon(tool.icon, color: tool.color),
                    title: Text(
                      tool.label,
                      style: TextStyle(
                        color: sp.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      tool.onTap();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalView(
    BuildContext context,
    PulsrPalette p,
    GetSongsUseCase getSongsUseCase,
    PlayerCubit playerCubit,
    bool isTablet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- Quick actions ----------
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context), 0,
              Adaptive.pagePadding(context), AppSpacing.md),
          child: Row(
            children: [
              _QuickCard(
                title: context.l10n.favorites,
                subtitle: context.l10n.likedTracks,
                icon: Icons.favorite_rounded,
                color: p.favorite,
                onTap: () => context.push('/favorites'),
              ),
              const SizedBox(width: AppSpacing.s10),
              _QuickCard(
                title: context.l10n.dailyDrive,
                subtitle: context.l10n.autoMix,
                icon: Icons.directions_car_rounded,
                color: p.accent,
                onTap: () async {
                  final list = await _getQuickActionSongs(getSongsUseCase);
                  if (list.isNotEmpty) {
                    final shuffled = List<SongsTableData>.from(list)..shuffle();
                    playerCubit.playSong(shuffled.first, queue: shuffled);
                  }
                },
              ),
              const SizedBox(width: AppSpacing.s10),
              _QuickCard(
                title: context.l10n.focusFlow,
                subtitle: context.l10n.topPlayedTracks,
                icon: Icons.headphones_rounded,
                color: AppColors.mint,
                onTap: () async {
                  final list = await _getQuickActionSongs(getSongsUseCase);
                  final top = list.where((s) => s.playCount > 0).toList()
                    ..sort((a, b) => b.playCount.compareTo(a.playCount));
                  if (top.isNotEmpty) {
                    playerCubit.playSong(top.first, queue: top);
                  }
                },
              ),
            ],
          ),
        ),

        // ---------- Recently played (50 by 50 smooth lazy load) ----------
        // Section isolation (gap 04-02): each stream section is wrapped in a
        // RepaintBoundary so one emission never repaints unrelated sections.
        // Note: this screen has no whole-dashboard BlocBuilder; the 57KB
        // rebuild claim (04-01) was overstated — emissions are already scoped
        // to the StreamBuilders below.
        RepaintBoundary(
          child: _RecentlyPlayedSection(
            getSongsUseCase: getSongsUseCase,
            isTablet: isTablet,
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ---------- Recently added (lazy loaded in 50-song batches) ----------
        RepaintBoundary(
          child: _RecentlyAddedSection(
            getSongsUseCase: getSongsUseCase,
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineView(
    BuildContext context,
    PulsrPalette p,
    PlayerCubit playerCubit,
    bool isTablet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- Search YouTube Music Action Banner ----------
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Adaptive.pagePadding(context)),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.r20),
            onTap: () => context.push('/ytm-search'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.18),
                    p.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadii.r20),
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.travel_explore_rounded,
                        color: p.accent, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.s14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.searchYtm,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: AppFontSize.body,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(context.l10n.ytmPromo,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: p.accent),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ---------- Quick Moods & Vibe Cards ----------
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Adaptive.pagePadding(context)),
          child: Row(
            children: [
              _QuickCard(
                title: _ytmAccountService.isLoggedIn
                    ? context.l10n.browseForYou
                    : context.l10n.browseTopHits,
                subtitle: _ytmAccountService.isLoggedIn
                    ? context.l10n.browsePersonalized
                    : context.l10n.browseTrending,
                icon: _ytmAccountService.isLoggedIn
                    ? Icons.auto_awesome_rounded
                    : Icons.local_fire_department_rounded,
                color: _ytmAccountService.isLoggedIn
                    ? p.accent
                    : AppColors.error,
                onTap: () => setState(() => _selectedOnlineCategory =
                    _ytmAccountService.isLoggedIn
                        ? 'Recommended For You'
                        : 'Global Top Hits'),
              ),
              const SizedBox(width: AppSpacing.s10),
              _QuickCard(
                title: context.l10n.newReleases,
                subtitle: context.l10n.browseTrending,
                icon: Icons.fiber_new_rounded,
                color: AppColors.azure,
                onTap: () =>
                    setState(() => _selectedOnlineCategory = 'New Releases'),
              ),
              const SizedBox(width: AppSpacing.s10),
              _QuickCard(
                title: context.l10n.browseChillLofi,
                subtitle: context.l10n.browseRelaxing,
                icon: Icons.spa_rounded,
                color: AppColors.ldacViolet,
                onTap: () =>
                    setState(() => _selectedOnlineCategory = 'Chill & Lo-Fi'),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ---------- Category Chips ----------
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding:
              EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
          child: Row(
            children: [
              for (final cat in _onlineCategories)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: ChoiceChip(
                    avatar: cat == 'Recommended For You'
                        ? Icon(Icons.auto_awesome_rounded,
                            size: 14,
                            color: _selectedOnlineCategory == cat
                                ? p.onAccent
                                : p.accent)
                        : null,
                    label: Text(_categoryLabel(context, cat)),
                    selected: _selectedOnlineCategory == cat,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedOnlineCategory = cat);
                      }
                    },
                    selectedColor: p.accent,
                    backgroundColor: p.surfaceContainer,
                    labelStyle: TextStyle(
                      color: _selectedOnlineCategory == cat
                          ? p.onAccent
                          : p.textSecondary,
                      fontWeight: _selectedOnlineCategory == cat
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: AppFontSize.label,
                    ),
                    side: BorderSide(
                        color: _selectedOnlineCategory == cat
                            ? p.accent
                            : p.hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r14)),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ---------- Online Category Content (Carousel + Top Charts) ----------
        _OnlineCategorySection(
          key: ValueKey(_selectedOnlineCategory),
          title: _selectedOnlineCategory == 'Recommended For You'
              ? context.l10n.browseRecommendedYtmTitle
              : (_selectedOnlineCategory == 'Trending Egypt'
                  ? context.l10n.browseTrendingInEgypt
                  : '${context.l10n.browsePopular}: ${_categoryLabel(context, _selectedOnlineCategory)}'),
          future: context.read<HomeCubit>().categoryFuture(_selectedOnlineCategory),
          playerCubit: playerCubit,
          onRetry: () {
            context.read<HomeCubit>().retryCategory(_selectedOnlineCategory);
            setState(() {});
          },
        ),
      ],
    );
  }
}

class _OnlineCategorySection extends StatelessWidget {
  final String title;
  final Future<List<YtmTrack>> future;
  final PlayerCubit playerCubit;
  final VoidCallback onRetry;

  const _OnlineCategorySection({
    super.key,
    required this.title,
    required this.future,
    required this.playerCubit,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final size = isTablet ? 158.0 : 138.0;

    return FutureBuilder<List<YtmTrack>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title),
              SizedBox(
                height: _scaledCarouselHeight(context, isTablet),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  itemCount: 4,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
                    child: SizedBox(
                      width: size,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: size, height: size, radius: AppRadii.r18),
                          const SizedBox(height: AppSpacing.xs),
                          SkeletonLine(width: size * 0.75, height: 12),
                          const SizedBox(height: AppSpacing.s6),
                          SkeletonLine(width: size * 0.45, height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError || (snapshot.data ?? const []).isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.wifi_tethering_error_rounded,
                      color: p.textTertiary, size: 38),
                  const SizedBox(height: AppSpacing.s10),
                  Text(
                    context.l10n.loadSongsFailed(title),
                    style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(context.l10n.retry),
                  ),
                ],
              ),
            ),
          );
        }

        final tracks = snapshot.data!;
        final songs = [for (final track in tracks) track.toSongData()];
        final ytmCubit = getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: title),
              SizedBox(
                height: _scaledCarouselHeight(context, isTablet),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return StaggeredReveal(
                      index: index,
                      horizontal: true,
                      groupKey: songs.isEmpty
                          ? ''
                          : '${songs.first.id}-${songs.length}',
                      child: _TrendingCard(
                        song: song,
                        onTap: () => playerCubit.playSong(song, queue: songs),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SectionHeader(
                  title:
                      '${context.l10n.browseTopChartsSongs} (${songs.length})'),
              if (context.trackGridColumns > 1)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: context.trackGridColumns,
                    mainAxisExtent: 72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: songs.length,
                  itemBuilder: (context, i) => StaggeredReveal(
                    index: i,
                    groupKey: songs.isEmpty
                        ? ''
                        : '${songs.first.id}-${songs.length}',
                    child: SongTile(
                      song: songs[i],
                      index: i,
                      onTap: () => playerCubit.playSong(songs[i], queue: songs),
                      trailing: YtmDownloadButton(song: songs[i]),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: songs[i]),
                    ),
                  ),
                )
              else
                for (int i = 0; i < songs.length; i++)
                  StaggeredReveal(
                    index: i,
                    groupKey: songs.isEmpty
                        ? ''
                        : '${songs.first.id}-${songs.length}',
                    child: SongTile(
                      song: songs[i],
                      index: i,
                      onTap: () => playerCubit.playSong(songs[i], queue: songs),
                      trailing: YtmDownloadButton(song: songs[i]),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: songs[i]),
                    ),
                  ),
            ],
          );
        if (ytmCubit != null) {
          return BlocProvider<YtmDownloadCubit>.value(
            value: ytmCubit,
            child: content,
          );
        }
        return content;
      },
    );
  }
}

class _DiscoveryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _DiscoveryChip({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadii.r14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.r14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.r14),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: AppSpacing.s6),
              Text(
                label,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final SongsTableData song;
  final VoidCallback onTap;

  const _TrendingCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final size = isTablet ? 158.0 : 138.0;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.r20),
        onTap: onTap,
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CachedArtwork(
                    id: song.id,
                    remoteUrl: song.remoteArtworkUrl,
                    type: ArtworkType.AUDIO,
                    size: size,
                    borderRadius: AppRadii.r18,
                  ),
                  // Scrim keeps the download icon legible over arbitrary artwork.
                  PositionedDirectional(
                    end: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: YtmDownloadButton(song: song),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: _scaledTitleBoxHeight(context),
                child: Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.label,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCompact = MediaQuery.sizeOf(context).width < 380;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.r18),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 12,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.16),
                  color.withValues(alpha: 0.03)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.r18),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(isCompact ? 6 : 7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: isCompact ? 17 : 19),
                ),
                SizedBox(height: isCompact ? 8 : 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: isCompact ? AppFontSize.label : AppFontSize.bodySmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: isCompact ? AppFontSize.tiny : AppFontSize.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentlyPlayedSection extends StatefulWidget {
  final GetSongsUseCase getSongsUseCase;
  final bool isTablet;

  const _RecentlyPlayedSection({
    required this.getSongsUseCase,
    required this.isTablet,
  });

  @override
  State<_RecentlyPlayedSection> createState() => _RecentlyPlayedSectionState();
}

class _RecentlyPlayedSectionState extends State<_RecentlyPlayedSection> {
  static const int _pageSize = 50;
  int _currentLimit = _pageSize;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger next batch when scrolling within 250px of the horizontal end
    if (maxScroll - currentScroll <= 250) {
      _loadMore();
    }
  }

  bool _isLoadingMore = false;

  void _loadMore() {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    setState(() {
      _currentLimit += _pageSize;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: widget.getSongsUseCase.watchRecentlyPlayed(limit: _currentLimit).distinct(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SectionError(onRetry: () => setState(() {}));
        }
        final songs =
            snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

        if (songs.isEmpty) return const SizedBox.shrink();

        final hasMore = songs.length >= _currentLimit;
        final size = widget.isTablet ? 158.0 : 138.0;
        final totalItemCount = songs.length + (hasMore ? 1 : 0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: context.l10n.recentlyPlayed,
              actionLabel: context.l10n.browseSeeAll,
              onAction: () => context.push('/recents'),
            ),
            SizedBox(
              height: _scaledCarouselHeight(context, widget.isTablet),
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                padding: EdgeInsets.symmetric(
                    horizontal: Adaptive.pagePadding(context)),
                itemCount: totalItemCount,
                itemBuilder: (context, index) {
                  if (index >= songs.length) {
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: p.surfaceCard.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadii.r18),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Center(
                          child: SizedBox(width: AppSpacing.lg,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(p.accent),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final song = songs[index];
                  return StaggeredReveal(
                    index: index,
                    horizontal: true,
                    groupKey: songs.isEmpty
                        ? ''
                        : '${songs.first.id}-${songs.length}',
                    child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.r20),
                      onTap: () => playerCubit.playSong(song, queue: songs),
                      child: SizedBox(
                        width: size,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                CachedArtwork(
                                  id: song.id,
                                  remoteUrl: song.remoteArtworkUrl,
                                  type: ArtworkType.AUDIO,
                                  size: size,
                                  borderRadius: AppRadii.r18,
                                ),
                                PositionedDirectional(
                                  end: 8,
                                  bottom: 8,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                            color: p.glow,
                                            blurRadius: 14,
                                            spreadRadius: 1),
                                      ],
                                    ),
                                    child: Icon(Icons.play_arrow_rounded,
                                        color: p.onAccent, size: 22),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            SizedBox(
                              height: _scaledTitleBoxHeight(context),
                              child: Text(
                                song.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.label,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.label),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentlyAddedSection extends StatefulWidget {
  final GetSongsUseCase getSongsUseCase;

  const _RecentlyAddedSection({
    required this.getSongsUseCase,
  });

  @override
  State<_RecentlyAddedSection> createState() => _RecentlyAddedSectionState();
}

class _RecentlyAddedSectionState extends State<_RecentlyAddedSection> {
  static const int _pageSize = 50;
  int _currentLimit = _pageSize;
  bool _isLoadingMore = false;

  void _loadMore() {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _currentLimit += _pageSize;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoadingMore) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final columns = context.trackGridColumns;

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: widget.getSongsUseCase.watchRecentlyAdded(limit: _currentLimit).distinct(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (_isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isLoadingMore) {
                setState(() => _isLoadingMore = false);
              }
            });
          }
          return _SectionError(onRetry: () => setState(() {}));
        }
        final songs =
            snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

        if (songs.isEmpty) {
          if (_isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isLoadingMore) {
                setState(() => _isLoadingMore = false);
              }
            });
          }
          return const _EmptyLibrary();
        }

        final hasMore = songs.length >= _currentLimit;
        // As soon as the active stream emits, clear the guard so "Load more"
        // does not remain stuck when reaching the end of the collection.
        if (_isLoadingMore && snapshot.connectionState != ConnectionState.waiting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isLoadingMore) {
              setState(() => _isLoadingMore = false);
            }
          });
        }
        final loading = _isLoadingMore;
        final totalItemCount = songs.length + (hasMore ? 1 : 0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: context.l10n.recentlyAdded,
              actionLabel: context.l10n.browseSeeAll,
              onAction: () => context.push('/library'),
            ),
            if (columns > 1)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                padding: EdgeInsets.symmetric(
                    horizontal: Adaptive.pagePadding(context)),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 72,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 4,
                ),
                itemCount: totalItemCount,
                itemBuilder: (context, index) {
                  if (index >= songs.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : _loadMore,
                          icon: loading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(p.accent),
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text(
                            context.l10n.browseSeeAll,
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final song = songs[index];
                  return StaggeredReveal(
                    index: index,
                    groupKey: songs.isEmpty
                        ? ''
                        : '${songs.first.id}-${songs.length}',
                    child: SongTile(
                      song: song,
                      onTap: () =>
                          playerCubit.playSong(song, queue: songs),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: song),
                    ),
                  );
                },
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                itemCount: totalItemCount,
                itemBuilder: (context, index) {
                  if (index >= songs.length) {
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context),
                        vertical: AppSpacing.sm,
                      ),
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : _loadMore,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.accent.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.r20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.s10,
                            ),
                          ),
                          icon: loading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(p.accent),
                                  ),
                                )
                              : Icon(Icons.expand_more_rounded,
                                  size: 18, color: p.accent),
                          label: Text(
                            '${context.l10n.loadMore} (+50)',
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final song = songs[index];
                  return StaggeredReveal(
                    index: index,
                    groupKey: songs.isEmpty
                        ? ''
                        : '${songs.first.id}-${songs.length}',
                    child: SongTile(
                      song: song,
                      onTap: () =>
                          playerCubit.playSong(song, queue: songs),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: song),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _SectionError extends StatelessWidget {
  final VoidCallback onRetry;

  const _SectionError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s14),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.r14),
          border: Border.all(color: p.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(context.l10n.libLoadFailed,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatefulWidget {
  const _EmptyLibrary();

  @override
  State<_EmptyLibrary> createState() => _EmptyLibraryState();
}

class _EmptyLibraryState extends State<_EmptyLibrary> {
  bool _isScanning = false;
  bool _hasPermission = true;
  double _scanProgress = 0.0;
  StreamSubscription<double>? _progressSub;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  MediaScannerService? _getScanner() {
    try {
      return context.read<MediaScannerService>();
    } catch (_) {
      try {
        if (getIt.isRegistered<MediaScannerService>()) {
          return getIt<MediaScannerService>();
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> _checkPermission() async {
    try {
      final scanner = _getScanner();
      if (scanner == null) return;
      final granted = await scanner.checkPermission();
      if (mounted) setState(() => _hasPermission = granted);
    } catch (_) {}
  }

  Future<void> _requestPermission() async {
    try {
      final scanner = _getScanner();
      if (scanner == null) return;
      final granted = await scanner.requestPermission();
      if (mounted) {
        setState(() => _hasPermission = granted);
        if (granted) {
          _scan();
        }
      }
    } catch (_) {}
  }

  Future<void> _scan() async {
    final scanner = _getScanner();
    if (scanner == null) return;

    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
    });

    _progressSub?.cancel();
    _progressSub = scanner.scanProgress.listen((p) {
      if (mounted) setState(() => _scanProgress = p);
    });

    try {
      final count = await scanner.scanDeviceLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.scanComplete(count)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (!_hasPermission) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
        child: EmptyStateWidget(
          icon: Icons.folder_special_rounded,
          title: context.l10n.homePermissionNeeded,
          subtitle: context.l10n.homePermissionSubtitle,
          primaryActionLabel: context.l10n.homeGrantPermission,
          primaryActionIcon: Icons.lock_open_rounded,
          onPrimaryAction: _requestPermission,
          secondaryActionLabel: context.l10n.hiddenFolders,
          secondaryActionIcon: Icons.folder_off_rounded,
          onSecondaryAction: () => context.push('/hidden-folders'),
        ),
      );
    }

    if (_isScanning) {
      final percent = (_scanProgress * 100).toInt();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyStateWidget(
              icon: Icons.hourglass_top_rounded,
              title: context.l10n.scanningStorage,
              subtitle: _scanProgress > 0
                  ? context.l10n.homeScanProgress(percent)
                  : context.l10n.homeScanningStorageSubtitle,
              isPrimaryLoading: true,
              primaryActionLabel: context.l10n.homeScanningLabel,
            ),
            if (_scanProgress > 0) ...[
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.r8),
                  child: LinearProgressIndicator(
                    value: _scanProgress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: p.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      child: EmptyStateWidget(
        icon: Icons.music_off_rounded,
        title: context.l10n.noMusicYet,
        subtitle: context.l10n.scanPrompt,
        primaryActionLabel: context.l10n.scanStorage,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: _scan,
        secondaryActionLabel: context.l10n.hiddenFolders,
        secondaryActionIcon: Icons.folder_off_rounded,
        onSecondaryAction: () => context.push('/hidden-folders'),
      ),
    );
  }
}
