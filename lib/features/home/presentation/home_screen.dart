import 'dart:async';
import 'dart:math' as math;
import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/performance/gpu_budget.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dock_tracker.dart';
import '../../../core/widgets/pulsr_scroll_edge_fade.dart';
import '../../../core/widgets/source_scope_switcher.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../search/presentation/search_screen.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/home_cubit.dart';
import '../../../core/services/radio_station_store.dart';
import 'widgets/quran_radio_hero_carousel.dart';
import 'widgets/quick_tile.dart';
import 'widgets/online_category_section.dart';
import 'widgets/quick_discovery_header.dart';
import 'widgets/recently_added_section.dart';
import 'widgets/recently_played_section.dart';
import 'widgets/studio_tools_rail.dart';

import '../../../core/utils/pulsr_haptics.dart';
export 'widgets/quick_actions_row.dart';
export 'widgets/quick_card.dart';
export 'widgets/quick_discovery_header.dart';
export 'widgets/quran_radio_hero_carousel.dart';
export 'widgets/studio_tools_rail.dart';

class HomeScreen extends StatelessWidget {
  final YtmService? ytmService;
  final YtmAccountService? ytmAccountService;
  final GetSongsUseCase? getSongsUseCase;
  final bool? enableOnlineOverride;

  const HomeScreen({
    super.key,
    this.ytmService,
    this.ytmAccountService,
    this.getSongsUseCase,
    this.enableOnlineOverride,
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
        enableOnlineOverride: enableOnlineOverride,
      ),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  final YtmService? ytmService;
  final YtmAccountService? ytmAccountService;
  final GetSongsUseCase? getSongsUseCase;
  final bool? enableOnlineOverride;

  const _HomeScreenContent({
    this.ytmService,
    this.ytmAccountService,
    this.getSongsUseCase,
    this.enableOnlineOverride,
  });

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent>
    with WidgetsBindingObserver {
  SourceScope _scope = SourceScope.local;
  bool _scopeLoaded = false;
  int get _selectedTab => _scope == SourceScope.online ? 1 : 0;
  String _selectedOnlineCategory = 'Recommended For You';

  YtmAccountService get _ytmAccountService =>
      widget.ytmAccountService ?? getIt<YtmAccountService>();
  GetSongsUseCase get _getSongsUseCase =>
      widget.getSongsUseCase ?? getIt<GetSongsUseCase>();

  late final HomeCubit _homeCubit;

  // Cache for Focus Flow with a 60-second TTL.
  List<SongsTableData>? _cachedFocusFlowSongs;
  Stopwatch? _cachedFocusFlowStopwatch;
  StreamSubscription? _librarySub;

  static const Duration _quickActionCacheTtl = Duration(seconds: 60);
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

  /// Surfaces empty history when Focus Flow has no played songs.
  void _showQuickActionEmpty(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.noPlayHistory),
          behavior: SnackBarBehavior.floating,
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
  bool _openedAppSettingsForNotification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homeCubit = context.read<HomeCubit>();
    final isLoggedIn = _ytmAccountService.isLoggedIn;
    _selectedOnlineCategory =
        isLoggedIn ? 'Recommended For You' : 'Trending Egypt';
    _preloadScope();
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

  Future<void> _preloadScope() async {
    var restored = SourceScope.local;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(SourceScopeSwitcher.storageKey('home'));
      if (saved == SourceScope.online.name) {
        restored = SourceScope.online;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _scope = restored;
      _scopeLoaded = true;
    });
    if (restored == SourceScope.online) {
      unawaited(_homeCubit.loadCategory(_selectedOnlineCategory));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationDenied();
    }
  }

  Future<void> _checkNotificationDenied() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var denied = prefs.getBool('notification_permission_denied') ?? false;
      final returningFromSettings = _openedAppSettingsForNotification;
      _openedAppSettingsForNotification = false;
      if (denied && returningFromSettings) {
        try {
          final status = await Permission.notification.status;
          if (status.isGranted) {
            await prefs.setBool('notification_permission_denied', false);
            denied = false;
          }
        } catch (_) {
          // Permission plugin unavailable (desktop / unit tests): keep prefs flag.
        }
      }
      if (mounted && _notificationDenied != denied) {
        setState(() => _notificationDenied = denied);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _librarySub?.cancel();
    _cachedFocusFlowStopwatch?.stop();
    _cachedFocusFlowStopwatch = null;
    _cachedFocusFlowSongs = null;
    super.dispose();
  }

  String _getGreeting(BuildContext context) {
    final hour = clock.now().hour;
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
    final showOnlineTab =
        (widget.enableOnlineOverride ?? AppConfig.ytmEnabled) && !offlineOnly;

    // Reset to local tab if offline only is enabled
    final currentTab = showOnlineTab ? _selectedTab : 0;
    final safePadding = MediaQuery.paddingOf(context);
    final basePad = Adaptive.pagePadding(context);
    final isPureBlack = p.isDark && p.bg.computeLuminance() < 0.001;
    final isHighContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final showAmbientGlow =
        !isPureBlack && !p.isCalmDensity && !isHighContrast && !GpuBudget.isEnabled;
    // Sections already apply [basePad] horizontally, so only add the delta
    // needed to clear a physical display cutout without double-padding.
    final cutoutLeft = safePadding.left > 0
        ? math.max(0.0, safePadding.left - basePad + 4.0)
        : 0.0;
    final cutoutRight = safePadding.right > 0
        ? math.max(0.0, safePadding.right - basePad + 4.0)
        : 0.0;

    return BlocConsumer<HomeCubit, HomeState>(
      listenWhen: (prev, curr) => prev.loginEpoch != curr.loginEpoch,
      listener: (context, homeState) {
        if (!mounted) return;
        if (homeState.isLoggedIn) {
          setState(() => _selectedOnlineCategory = 'Recommended For You');
        } else if (!_onlineCategories.contains(_selectedOnlineCategory)) {
          setState(() {
            _selectedOnlineCategory =
                _onlineCategories.firstOrNull ?? 'Trending Egypt';
          });
        }
        if (showOnlineTab && _scope == SourceScope.online) {
          unawaited(_homeCubit.loadCategory(_selectedOnlineCategory));
        }
      },
      builder: (context, homeState) => Scaffold(
        body: Stack(
          children: [
            if (showAmbientGlow)
              PositionedDirectional(
                key: const ValueKey('home_ambient_top_glow'),
                top: 0,
                start: 0,
                end: 0,
                height: 280,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const AlignmentDirectional(-0.55, -1.0),
                            radius: 1.35,
                            colors: [
                              p.accent.withValues(alpha: p.isDark ? 0.14 : 0.075),
                              p.accent.withValues(alpha: p.isDark ? 0.045 : 0.025),
                              p.accent.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.48, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              top: true,
              bottom: false,
              left: false,
              right: false,
              child: Padding(
                padding: Directionality.of(context) == TextDirection.rtl
                    ? EdgeInsetsDirectional.only(
                        start: cutoutRight, end: cutoutLeft)
                    : EdgeInsetsDirectional.only(
                        start: cutoutLeft, end: cutoutRight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: Adaptive.contentConstraints(context),
                    child: RefreshIndicator(
                      color: p.accent,
                      backgroundColor: p.surfaceContainer,
                      onRefresh: () async {
                        if (currentTab == 0) {
                          final count = await context
                              .read<SettingsCubit>()
                              .rescanLibrary();
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
                          await context
                              .read<HomeCubit>()
                              .refreshCategory(_selectedOnlineCategory);
                        }
                      },
                      child: ValueListenableBuilder<double>(
                        valueListenable: PulsrDockTracker.dockHeight,
                        builder: (context, dockHeight, _) {
                          final bottomPad = dockHeight > 0
                              ? dockHeight + safePadding.bottom + AppSpacing.xl
                              : PulsrLayoutMetrics.scrollBottom(
                                  context,
                                  extra: AppSpacing.xl,
                                );
                          return ListView(
                            key: const PageStorageKey('home_screen_scroll'),
                            physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics()),
                            padding: EdgeInsetsDirectional.only(bottom: bottomPad),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            MaterialLocalizations.of(context)
                                                .formatMediumDate(clock.now())
                                                .toUpperCase(),
                                            style: TextStyle(
                                              color: p.textTertiary,
                                              fontSize: AppFontSize.caption,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.s4),
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
                                      Flexible(
                                        child: Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  end: AppSpacing.xs),
                                          child: Chip(
                                            avatar: Icon(Icons.wifi_off_rounded,
                                                size: 14, color: p.accent),
                                            label: Text(
                                              context.l10n.offlineOnlyMode,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: AppFontSize.caption,
                                                fontWeight: FontWeight.w700,
                                                color: p.accent,
                                              ),
                                            ),
                                            backgroundColor: p.accentContainer,
                                            side: BorderSide(
                                                color: p.borderSubtle),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ),
                                    const ActiveAudioOutputPill(),
                                    const SizedBox(width: AppSpacing.xs),
                                    IconButton(
                                      key: const ValueKey(
                                          'home_settings_button'),
                                      constraints: const BoxConstraints(
                                        minWidth: AppSpacing.minTouchTarget,
                                        minHeight: AppSpacing.minTouchTarget,
                                      ),
                                      icon: Icon(
                                        Icons.settings_outlined,
                                        color: p.textSecondary,
                                        size: 22,
                                      ),
                                      tooltip: context.l10n.settings,
                                      onPressed: () =>
                                          context.push('/settings'),
                                    ),
                                  ],
                                ),
                              ),

                              // ---------- Notification Permission Denied Banner (B-37) ----------
                              if (_notificationDenied &&
                                  !_notificationBannerDismissed)
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
                                          color:
                                              p.accent.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.notifications_off_outlined,
                                            color: p.accent, size: 20),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: Text(
                                            context
                                                .l10n.playbackStopsScreenOff,
                                            style: TextStyle(
                                              color: p.textSecondary,
                                              fontSize: AppFontSize.caption,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            _openedAppSettingsForNotification =
                                                true;
                                            await openAppSettings();
                                          },
                                          child:
                                              Text(context.l10n.openSettings),
                                        ),
                                        IconButton(
                                          constraints: const BoxConstraints(
                                              minWidth:
                                                  AppSpacing.minTouchTarget,
                                              minHeight:
                                                  AppSpacing.minTouchTarget),
                                          icon: Icon(Icons.close,
                                              size: 16,
                                              color: p.textSecondary),
                                          tooltip: context.l10n.close,
                                          onPressed: () {
                                            if (mounted) {
                                              setState(() =>
                                                  _notificationBannerDismissed =
                                                      true);
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
                                Padding(
                                  padding: EdgeInsetsDirectional.symmetric(
                                      horizontal:
                                          Adaptive.pagePadding(context)),
                                  child: CompactSourceScopeSwitcher(
                                    persistKey: 'home',
                                    selectedScope: _scope,
                                    onChanged: (next) {
                                      setState(() => _scope = next);
                                      if (next == SourceScope.online) {
                                        unawaited(_homeCubit
                                            .loadCategory(_selectedOnlineCategory));
                                      }
                                    },
                                  ),
                                ),
                              ] else if (offlineOnly) ...[
                                const SizedBox(height: AppSpacing.md),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal:
                                          Adaptive.pagePadding(context)),
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
                                duration: context.motion(PulsrDurations.layout),
                                switchInCurve:
                                    context.motionCurve(Curves.easeOutCubic),
                                switchOutCurve:
                                    context.motionCurve(Curves.easeInCubic),
                                child: KeyedSubtree(
                                  key: ValueKey('home_tab_$currentTab'),
                                  child: (showOnlineTab && !_scopeLoaded)
                                      ? const SizedBox.shrink()
                                      : currentTab == 0
                                      ? _buildLocalView(
                                          context,
                                          p,
                                          getSongsUseCase,
                                          playerCubit,
                                          isTablet)
                                      : (showOnlineTab
                                          ? _buildOnlineView(
                                              context,
                                              p,
                                              playerCubit,
                                              homeState,
                                              isTablet)
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
            ),
          ],
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
        color: p.goldAccent,
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
            color: AppColors.fadeStopTransparent,
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
    final showOnline =
        (widget.enableOnlineOverride ?? AppConfig.ytmEnabled) && !offlineOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- Beat 1: Immediate Resume / QuranRadioHeroCarousel ----------
        const SizedBox(height: AppSpacing.md),
        Padding(
          key: const ValueKey('home_beat_1_immediate_resume'),
          padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context),
              0, Adaptive.pagePadding(context), AppSpacing.md),
          child: Builder(
            builder: (context) {
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
                  _showQuickActionEmpty(context);
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
                color: p.isDark
                    ? AppColors.qualityBadgeCyan
                    : AppColors.catGestures,
                onTap: onFocusFlowTap,
                trailingIcon: Icons.play_arrow_rounded,
                trailingIconSize: 20,
              );

              return ValueListenableBuilder<bool>(
                valueListenable: RadioStationStore.heroCardsVisible,
                builder: (context, showRadioCards, _) {
                  if (!showRadioCards) {
                    return Row(
                      children: [
                        Expanded(child: favTile),
                        const SizedBox(width: AppSpacing.s10),
                        Expanded(child: focusTile),
                      ],
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, heroConstraints) {
                      final useSplitHero =
                          isTablet || heroConstraints.maxWidth >= 600;
                      if (useSplitHero) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 11,
                                child: QuranRadioHeroCarousel(
                                  height: 158,
                                  playerCubit: playerCubit,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s12),
                              Expanded(
                                flex: 9,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: favTile),
                                    const SizedBox(height: AppSpacing.s10),
                                    Expanded(child: focusTile),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: [
                          QuranRadioHeroCarousel(
                            height: 152,
                            playerCubit: playerCubit,
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
                  );
                },
              );
            },
          ),
        ),

        // ---------- Beat 3: Consolidated horizontal "Studio Tools" rail ----------
        KeyedSubtree(
          key: const ValueKey('home_beat_3_studio_tools'),
          child: StudioToolsRail(
            showYtm: showOnline,
            onMore: () => _showDiscoveryToolsSheet(context),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ---------- Beat 2: Personal Rails (Recently Played, Recently Added) ----------
        Column(
          key: const ValueKey('home_beat_2_personal_rails'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: RecentlyPlayedSection(
                getSongsUseCase: getSongsUseCase,
                isTablet: isTablet,
              ),
            ),
            RepaintBoundary(
              child: RecentlyAddedSection(
                getSongsUseCase: getSongsUseCase,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOnlineView(
    BuildContext context,
    PulsrPalette p,
    PlayerCubit playerCubit,
    HomeState homeState,
    bool isTablet,
  ) {
    final isHighContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final flatChrome = p.isCalmDensity || isHighContrast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        // ---------- Search YouTube Music Action Banner (Unified Online Search) ----------
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
          child: InkWell(
            key: const ValueKey('home_online_search_banner'),
            borderRadius: AppRadii.r20All,
            onTap: () => context.push(
              SearchScreen.routeLocation(
                scope: SearchScope.online,
                autofocus: true,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: flatChrome ? p.surfaceContainer : null,
                gradient: flatChrome
                    ? null
                    : LinearGradient(
                        colors: [
                          p.accent.withValues(alpha: p.isDark ? 0.18 : 0.11),
                          p.surfaceContainer,
                        ],
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                      ),
                borderRadius: AppRadii.r20All,
                border: Border.all(
                  color: isHighContrast
                      ? p.borderStrong
                      : p.accent.withValues(alpha: 0.3),
                  width: isHighContrast ? 1.25 : 1.0,
                ),
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

        // ---------- Beat 3: Consolidated horizontal "Studio Tools" rail ----------
        StudioToolsRail(
          online: true,
          onMore: () => _showDiscoveryToolsSheet(context),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ---------- Category Chips ----------
        PulsrScrollEdgeFade(
          extent: 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding:
                EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
            child: Row(
              children: [
                for (final cat in _onlineCategories)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.s10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40.0),
                      child: ChoiceChip(
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s12,
                          vertical: AppSpacing.s8,
                        ),
                        avatar: cat == 'Recommended For You'
                            ? Icon(Icons.auto_awesome_rounded,
                                size: 15,
                                color: _selectedOnlineCategory == cat
                                    ? p.onAccent
                                    : p.accent)
                            : null,
                        label: Text(_categoryLabel(context, cat)),
                        selected: _selectedOnlineCategory == cat,
                        onSelected: (selected) {
                          PulsrHaptics.selectionClick();
                          if (selected) {
                            setState(() => _selectedOnlineCategory = cat);
                            unawaited(_homeCubit.loadCategory(cat));
                          }
                        },
                        selectedColor: p.accent,
                        backgroundColor: p.surfaceContainerHigh,
                        labelStyle: TextStyle(
                          color: _selectedOnlineCategory == cat
                              ? p.onAccent
                              : p.textPrimary,
                          fontWeight: _selectedOnlineCategory == cat
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontSize: AppFontSize.label,
                        ),
                        side: _selectedOnlineCategory == cat
                            ? (isHighContrast
                                ? BorderSide(color: p.borderStrong, width: 1.25)
                                : BorderSide.none)
                            : BorderSide(
                                color: isHighContrast
                                    ? p.borderStrong
                                    : p.borderSubtle,
                                width: isHighContrast ? 1.25 : 1.0,
                              ),
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadii.full),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ---------- Online Category Content ----------
        AnimatedSwitcher(
          duration: context.motion(PulsrDurations.layout),
          switchInCurve: context.motionCurve(Curves.easeOutCubic),
          switchOutCurve: context.motionCurve(Curves.easeInCubic),
          child: OnlineCategorySection(
            key: PageStorageKey('online_cat_$_selectedOnlineCategory'),
            title: _selectedOnlineCategory == 'Recommended For You'
                ? context.l10n.browseRecommendedYtmTitle
                : (_selectedOnlineCategory == 'Trending Egypt'
                    ? context.l10n.browseTrendingInEgypt
                    : '${context.l10n.browsePopular}: ${_categoryLabel(context, _selectedOnlineCategory)}'),
            categoryState: homeState.categoryState(_selectedOnlineCategory),
            playerCubit: playerCubit,
            onRetry: () {
              _homeCubit.retryCategory(_selectedOnlineCategory);
              unawaited(_homeCubit.loadCategory(_selectedOnlineCategory));
            },
          ),
        ),
      ],
    );
  }
}