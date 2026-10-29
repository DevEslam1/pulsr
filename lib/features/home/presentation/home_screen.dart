import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../cubit/home_cubit.dart';
import 'widgets/hero_mix_card.dart';
import 'widgets/quick_tile.dart';
import 'widgets/online_category_section.dart';
import 'widgets/quick_discovery_header.dart';
import 'widgets/recently_added_section.dart';
import 'widgets/recently_played_section.dart';

export 'widgets/quick_actions_row.dart';
export 'widgets/quick_card.dart';

import 'package:go_router/go_router.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/pulsr_dock_tracker.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';

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

  // Separate caches for the two quick actions (Daily Drive & Focus Flow) with
  // a 60-second TTL. They read different sources, so they cannot share one.
  List<SongsTableData>? _cachedDailyDriveSongs;
  Stopwatch? _cachedDailyDriveStopwatch;
  List<SongsTableData>? _cachedFocusFlowSongs;
  Stopwatch? _cachedFocusFlowStopwatch;
  StreamSubscription? _librarySub;

  static const Duration _quickActionCacheTtl = Duration(seconds: 60);
  static const int _dailyDriveLimit = 200;

  /// Focus Flow: a broad top-played window (200 rows) so playback is not
  /// confined to the first 50 titles, same rationale as Daily Drive.
  static const int _focusFlowLimit = 200;

  bool _cacheFresh(Stopwatch? stopwatch) =>
      stopwatch != null &&
      stopwatch.isRunning &&
      stopwatch.elapsed < _quickActionCacheTtl;

  /// Current hidden-folder exclusions, shared by the quick-action queries so
  /// excluded songs never re-enter discovery through Daily Drive/Focus Flow.
  List<String> _currentExcludedFolders() {
    final cubit = context.read<LibraryCubit?>();
    if (cubit == null) return const [];
    return [
      for (final folder in cubit.state.folders)
        if (folder.isExcluded) folder.path,
    ];
  }

  /// Daily Drive: a broad, recently-played-first window (200 rows) so the
  /// shuffle is not confined to the first 50 titles.
  Future<List<SongsTableData>?> _fetchDailyDriveSongs(
      GetSongsUseCase useCase) async {
    if (_cachedDailyDriveSongs != null &&
        _cacheFresh(_cachedDailyDriveStopwatch)) {
      return _cachedDailyDriveSongs;
    }
    final res = await useCase.getAllSongs(
      sortBy: 'lastPlayed',
      ascending: false,
      limit: _dailyDriveLimit,
      excludedFolders: _currentExcludedFolders(),
    );
    return res.fold(
      // Null means failure (distinct from a genuinely empty library) so the
      // caller can surface an error instead of silently playing nothing.
      (_) => null,
      (songs) {
        _cachedDailyDriveSongs = songs;
        _cachedDailyDriveStopwatch = Stopwatch()..start();
        return songs;
      },
    );
  }

  /// Focus Flow: the top-played source, not a title-ordered page.
  Future<List<SongsTableData>?> _fetchTopPlayedSongs(
      GetSongsUseCase useCase) async {
    if (_cachedFocusFlowSongs != null &&
        _cacheFresh(_cachedFocusFlowStopwatch)) {
      return _cachedFocusFlowSongs;
    }
    List<SongsTableData>? songs;
    try {
      final res = await useCase
          .watchTopPlayed(
            limit: _focusFlowLimit,
            excludedFolders: _currentExcludedFolders(),
          )
          .first
          .timeout(const Duration(seconds: 5));
      songs = res.fold<List<SongsTableData>?>(
        (_) => null,
        (list) {
          _cachedFocusFlowSongs = list;
          _cachedFocusFlowStopwatch = Stopwatch()..start();
          return list;
        },
      );
    } catch (_) {
      songs = null;
    }
    return songs;
  }

  void _invalidateQuickActionCaches() {
    _cachedDailyDriveSongs = null;
    _cachedDailyDriveStopwatch?.stop();
    _cachedDailyDriveStopwatch = null;
    _cachedFocusFlowSongs = null;
    _cachedFocusFlowStopwatch?.stop();
    _cachedFocusFlowStopwatch = null;
  }

  void _showQuickActionLoadError(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.browseFailedToFetch),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Daily Drive/Focus Flow used to no-op when their queue came back empty.
  /// Surface why (empty library vs no play history) and offer a scan CTA for
  /// the empty-library case.
  void _showQuickActionEmpty(BuildContext context, {required bool dailyDrive}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(dailyDrive
              ? context.l10n.browseNoSongsInLibrary
              : context.l10n.noPlayHistory),
          behavior: SnackBarBehavior.floating,
          action: dailyDrive
              ? SnackBarAction(
                  label: context.l10n.scanStorage,
                  onPressed: () async {
                    final count =
                        await context.read<SettingsCubit>().rescanLibrary();
                    if (!context.mounted) return;
                    messenger
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(content: Text(context.l10n.scanResult(count))),
                      );
                  },
                )
              : null,
        ),
      );
  }

  List<String> get _onlineCategories => _homeCubit.onlineCategories;
  bool _notificationDenied = false;

  /// Session-only dismissal of the notification banner. Deliberately not
  /// persisted: dismissing the banner must not clear the underlying
  /// `notification_permission_denied` flag, otherwise a real denial would stay
  /// hidden on every subsequent launch.
  bool _notificationBannerDismissed = false;

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
      List<SongsTableData> lastSongs = libraryCubit.state.songs;
      _librarySub = libraryCubit.stream.listen((state) {
        if (!mounted) return;
        final firstId = state.songs.firstOrNull?.id;
        final lastFirstId = lastSongs.firstOrNull?.id;
        if (!identical(state.songs, lastSongs) ||
            state.songs.length != lastSongs.length ||
            firstId != lastFirstId) {
          lastSongs = state.songs;
          _invalidateQuickActionCaches();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkNotificationDenied();
  }

  Future<void> _checkNotificationDenied() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final denied = prefs.getBool('notification_permission_denied') ?? false;
      if (mounted && _notificationDenied != denied) {
        setState(() => _notificationDenied = denied);
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
    _cachedDailyDriveStopwatch?.stop();
    _cachedDailyDriveStopwatch = null;
    _cachedDailyDriveSongs = null;
    _cachedFocusFlowStopwatch?.stop();
    _cachedFocusFlowStopwatch = null;
    _cachedFocusFlowSongs = null;
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
    final offlineOnly =
        context.select<SettingsCubit, bool>((c) => c.state.offlineOnlyMode);
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
              child: ValueListenableBuilder<double>(
                valueListenable: PulsrDockTracker.dockHeight,
                builder: (context, dockHeight, _) {
                  final bottomPad = dockHeight > 0
                      ? dockHeight + AppSpacing.md
                      : PulsrLayoutMetrics.scrollBottom(context, extra: 24.0);
                  return ListView(
                    key: const PageStorageKey('home_screen_scroll'),
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.only(bottom: bottomPad),
                    children: [
                      // ---------- Header ----------
                      Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                            Adaptive.pagePadding(context),
                            AppSpacing.md,
                            Adaptive.pagePadding(context),
                            0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    MaterialLocalizations.of(context)
                                        .formatMediumDate(DateTime.now())
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: p.textTertiary,
                                      fontSize: AppFontSize.tiny,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  Text(
                                    _getGreeting(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5),
                                  ),
                                ],
                              ),
                            ),
                            if (offlineOnly)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    end: AppSpacing.sm),
                                child: Chip(
                                  avatar: Icon(Icons.wifi_off_rounded,
                                      size: 14, color: p.accent),
                                  label: Text(
                                    context.l10n.offlineOnlyMode,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      fontWeight: FontWeight.w700,
                                      color: p.accent,
                                    ),
                                  ),
                                  backgroundColor: p.accentContainer,
                                  side: BorderSide(color: p.hairline),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            // Logo in a soft badge so the header has a visual anchor.
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: p.accentContainer,
                                borderRadius: AppRadii.r14All,
                                border: Border.all(
                                    color: p.accent.withValues(alpha: 0.25)),
                              ),
                              child: Center(
                                child: PulsrLogo(
                                    size: 24,
                                    color: p.accent,
                                    glowColor: p.glow,
                                    animate: false),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ---------- Notification Permission Denied Banner (B-37) ----------
                      if (_notificationDenied && !_notificationBannerDismissed)
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
                              borderRadius: AppRadii.cardRadius,
                              border: Border.all(
                                  color: p.accent.withValues(alpha: 0.3)),
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
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                        'notification_permission_denied',
                                        false);
                                    if (mounted) {
                                      setState(
                                          () => _notificationDenied = false);
                                    }
                                  },
                                  child: Text(context.l10n.openSettings),
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget),
                                  icon: const Icon(Icons.close, size: 16),
                                  tooltip: context.l10n.close,
                                  // Hide for this session only. Clearing the
                                  // persisted denial flag here made a genuine
                                  // denial disappear permanently.
                                  onPressed: () {
                                    if (mounted) {
                                      setState(() =>
                                          _notificationBannerDismissed = true);
                                    }
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

                      // ---------- Content (Local vs Online) ----------
                      AnimatedSwitcher(
                        duration: context.motion(PulsrMotion.standard),
                        switchInCurve:
                            context.motionCurve(Curves.easeOutCubic),
                        switchOutCurve:
                            context.motionCurve(Curves.easeInCubic),
                        child: KeyedSubtree(
                          key: ValueKey('home_tab_$currentTab'),
                          child: currentTab == 0
                              ? _buildLocalView(context, p, getSongsUseCase,
                                  playerCubit, isTablet)
                              : (showOnlineTab
                                  ? _buildOnlineView(
                                      context, p, playerCubit, isTablet)
                                  : const SizedBox.shrink()),
                        ),
                      ),
                    ],
                  );
                },
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
    final tools =
        <({IconData icon, String label, Color color, VoidCallback onTap})>[
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
        return PulsrBottomSheet(
          title: Text(
            sheetContext.l10n.browseMoreTools,
            style: TextStyle(
              color: sp.textPrimary,
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in tools)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      borderRadius: AppRadii.r16All,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        tool.onTap();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.s10,
                        ),
                        decoration: BoxDecoration(
                          color: sp.surfaceContainer,
                          borderRadius: AppRadii.r16All,
                          border: Border.all(color: sp.hairline),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: tool.color.withValues(alpha: 0.16),
                                borderRadius: AppRadii.r12All,
                              ),
                              child:
                                  Icon(tool.icon, color: tool.color, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.s12),
                            Expanded(
                              child: Text(
                                tool.label,
                                style: TextStyle(
                                  color: sp.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: sp.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
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
    final offlineOnly =
        context.select<SettingsCubit, bool>((c) => c.state.offlineOnlyMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- Hero action + secondary tiles ----------
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context),
              0, Adaptive.pagePadding(context), AppSpacing.md),
          child: Builder(
            builder: (context) {
              Future<void> onDailyDriveTap() async {
                final list = await _fetchDailyDriveSongs(getSongsUseCase);
                if (!context.mounted) return;
                if (list == null) {
                  _showQuickActionLoadError(context);
                  return;
                }
                if (list.isNotEmpty) {
                  final shuffled = List<SongsTableData>.from(list)..shuffle();
                  playerCubit.playSong(shuffled.first, queue: shuffled);
                } else {
                  _showQuickActionEmpty(context, dailyDrive: true);
                }
              }

              Future<void> onFocusFlowTap() async {
                final list = await _fetchTopPlayedSongs(getSongsUseCase);
                if (!context.mounted) return;
                if (list == null) {
                  _showQuickActionLoadError(context);
                  return;
                }
                if (list.isNotEmpty) {
                  final top = List<SongsTableData>.from(list)
                    ..sort((a, b) => b.playCount.compareTo(a.playCount));
                  playerCubit.playSong(top.first, queue: top);
                } else {
                  _showQuickActionEmpty(context, dailyDrive: false);
                }
              }

              final favTile = QuickTile(
                title: context.l10n.favorites,
                subtitle: context.l10n.likedTracks,
                icon: Icons.favorite_rounded,
                color: p.favorite,
                onTap: () => context.push('/favorites'),
              );

              final focusTile = QuickTile(
                title: context.l10n.focusFlow,
                subtitle: context.l10n.topPlayedTracks,
                icon: Icons.headphones_rounded,
                color: AppColors.mint,
                onTap: onFocusFlowTap,
                // Focus Flow starts playback immediately; a play glyph sets
                // the right expectation next to Favorites' navigation chevron.
                trailingIcon: Icons.play_arrow_rounded,
                trailingIconSize: 20,
              );

              if (isTablet) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 11,
                      child: HeroMixCard(
                        height: 132,
                        overline: context.l10n.localMusic,
                        title: context.l10n.dailyDrive,
                        subtitle: context.l10n.autoMix,
                        onTap: onDailyDriveTap,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      flex: 9,
                      child: Column(
                        children: [
                          favTile,
                          const SizedBox(height: AppSpacing.s10),
                          focusTile,
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  HeroMixCard(
                    overline: context.l10n.localMusic,
                    title: context.l10n.dailyDrive,
                    subtitle: context.l10n.autoMix,
                    onTap: onDailyDriveTap,
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  Row(
                    children: [
                      Expanded(child: favTile),
                      const SizedBox(width: AppSpacing.s10),
                      Expanded(child: focusTile),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        // ---------- Single shortcut strip ----------
        QuickDiscoveryHeader(
          showYtm: AppConfig.ytmEnabled && !offlineOnly,
          onMore: () => _showDiscoveryToolsSheet(context),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ---------- Recently played (50 by 50 smooth lazy load) ----------
        // Section isolation (gap 04-02): each stream section is wrapped in a
        // RepaintBoundary so one emission never repaints unrelated sections.
        // Note: this screen has no whole-dashboard BlocBuilder; the 57KB
        // rebuild claim (04-01) was overstated â€” emissions are already scoped
        // to the StreamBuilders below.
        RepaintBoundary(
          child: RecentlyPlayedSection(
            getSongsUseCase: getSongsUseCase,
            isTablet: isTablet,
          ),
        ),

        // ---------- Recently added (lazy loaded in 50-song batches) ----------
        RepaintBoundary(
          child: RecentlyAddedSection(
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
        const SizedBox(height: AppSpacing.md),
        // ---------- Search YouTube Music Action Banner ----------
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
          child: InkWell(
            borderRadius: AppRadii.r20All,
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
                borderRadius: AppRadii.r20All,
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
                        Text(
                          context.l10n.searchYtm,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: AppFontSize.body,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          context.l10n.ytmPromo,
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

        // ---------- Single shortcut strip ----------
        QuickDiscoveryHeader(
          online: true,
          onMore: () => _showDiscoveryToolsSheet(context),
        ),
        const SizedBox(height: AppSpacing.sm),

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
                      HapticFeedback.selectionClick();
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
                    shape:
                        RoundedRectangleBorder(borderRadius: AppRadii.r14All),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ---------- Online Category Content (Carousel + Top Charts) ----------
        AnimatedSwitcher(
          duration: context.motion(PulsrMotion.standard),
          switchInCurve: context.motionCurve(Curves.easeOutCubic),
          switchOutCurve: context.motionCurve(Curves.easeInCubic),
          child: OnlineCategorySection(
            key: PageStorageKey('online_cat_$_selectedOnlineCategory'),
            title: _selectedOnlineCategory == 'Recommended For You'
                ? context.l10n.browseRecommendedYtmTitle
                : (_selectedOnlineCategory == 'Trending Egypt'
                    ? context.l10n.browseTrendingInEgypt
                    : '${context.l10n.browsePopular}: ${_categoryLabel(context, _selectedOnlineCategory)}'),
            future: context
                .read<HomeCubit>()
                .categoryFuture(_selectedOnlineCategory),
            playerCubit: playerCubit,
            onRetry: () {
              context.read<HomeCubit>().retryCategory(_selectedOnlineCategory);
              setState(() {});
            },
          ),
        ),
      ],
    );
  }
}
