import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../core/errors/failures.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../domain/models/ytm_track.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';

import 'package:go_router/go_router.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0; // 0: Local, 1: Online
  String _selectedOnlineCategory = 'Recommended For You';

  /// Resolved once and reused across rebuilds so scrolling/retry never refetches.
  /// Only populated in an ENABLE_YTM build; null (and unused) otherwise.
  final Map<String, Future<List<YtmTrack>>> _categoryFutures = {};

  List<String> get _onlineCategories {
    final isLoggedIn = getIt<YtmAccountService>().isLoggedIn;
    if (isLoggedIn) {
      return const [
        'Recommended For You',
        'Trending Egypt',
        'Mahraganat',
        'Arabic Pop',
        'Global Top Hits',
        'New Releases',
        'Chill & Lo-Fi',
        'Pop Mix',
        'Hip-Hop',
        'Workout Energy',
        'Rock & Metal',
        'Acoustic',
      ];
    }
    return const [
      'Trending Egypt',
      'Mahraganat',
      'Arabic Pop',
      'Global Top Hits',
      'New Releases',
      'Chill & Lo-Fi',
      'Pop Mix',
      'Hip-Hop',
      'Workout Energy',
      'Rock & Metal',
      'Acoustic',
    ];
  }

  static const Map<String, String> _categoryQueries = {
    'Recommended For You': 'recommended music',
    'Trending Egypt': 'أغاني مصرية جديدة تريند',
    'Mahraganat': 'مهرجانات مصرية جديدة',
    'Arabic Pop': 'أغاني عربي عمرو دياب تامر حسني حماقي',
    'Global Top Hits': 'global top hits songs',
    'New Releases': 'new music releases',
    'Chill & Lo-Fi': 'chill lofi beats',
    'Pop Mix': 'pop hits playlist',
    'Hip-Hop': 'arabic hip hop rap ويجز',
    'Workout Energy': 'workout gym motivation music',
    'Rock & Metal': 'rock metal playlist',
    'Acoustic': 'acoustic guitar relax',
  };

  @override
  void initState() {
    super.initState();
    final isLoggedIn = getIt<YtmAccountService>().isLoggedIn;
    _selectedOnlineCategory = isLoggedIn ? 'Recommended For You' : 'Trending Egypt';
    getIt<YtmAccountService>().loginState.addListener(_onLoginStateChanged);
  }

  void _onLoginStateChanged() {
    if (!mounted) return;
    setState(() {
      _categoryFutures.clear();
      final isLoggedIn = getIt<YtmAccountService>().isLoggedIn;
      _selectedOnlineCategory = isLoggedIn ? 'Recommended For You' : 'Trending Egypt';
    });
  }

  @override
  void dispose() {
    getIt<YtmAccountService>().loginState.removeListener(_onLoginStateChanged);
    super.dispose();
  }

  Future<List<YtmTrack>> _getCategoryFuture(String category) {
    return _categoryFutures.putIfAbsent(
      category,
      () async {
        if (category == 'Recommended For You') {
          final account = getIt<YtmAccountService>();
          if (account.isLoggedIn) {
            try {
              final recs = await account.fetchHomeRecommendations(maxTracks: 50);
              if (recs.isNotEmpty) return recs;
            } catch (_) {}
          }
          try {
            final trending = await getIt<YtmService>().trending(limit: 25);
            if (trending.isNotEmpty) return trending;
          } catch (_) {}
          return getIt<YtmService>().searchWithFallback(_categoryQueries['Recommended For You'] ?? 'top hits music', limit: 25);
        }
        if (category == 'Trending Egypt') {
          try {
            final trending = await getIt<YtmService>().trending(limit: 25);
            if (trending.isNotEmpty) return trending;
          } catch (_) {}
          return getIt<YtmService>().searchWithFallback(_categoryQueries['Trending Egypt'] ?? 'أغاني مصرية جديدة تريند', limit: 25);
        }
        final query = _categoryQueries[category] ?? '$category songs';
        return getIt<YtmService>().searchWithFallback(query, limit: 25);
      },
    );
  }

  void _retryCategory(String category) {
    setState(() {
      _categoryFutures.remove(category);
    });
  }

  String _getGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return context.l10n.goodMorning;
    if (hour < 17) return context.l10n.goodAfternoon;
    return context.l10n.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final getSongsUseCase = getIt<GetSongsUseCase>();
    final playerCubit = context.read<PlayerCubit>();
    final isTablet = Adaptive.isTablet(context);
    final offlineOnly = context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;
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
              onRefresh: () async {
                if (currentTab == 0) {
                  final count = await context.read<SettingsCubit>().rescanLibrary();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.scanResult(count)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  setState(() {
                    _categoryFutures.clear();
                  });
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  // ---------- Header ----------
                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16, Adaptive.pagePadding(context), 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                MaterialLocalizations.of(context).formatMediumDate(DateTime.now()),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _getGreeting(context),
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: p.accentContainer,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: p.hairline),
                            boxShadow: [
                              BoxShadow(color: p.glow, blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
                            ],
                          ),
                          child: PulsrLogo(size: 26, color: p.accent, glowColor: p.glow, animate: false),
                        ),
                      ],
                    ),
                  ),

                  // ---------- Segmented Tab Selector (Local vs Online) ----------
                  if (showOnlineTab) ...[
                    const SizedBox(height: 12),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabButton(
                              title: context.l10n.localMusic,
                              icon: Icons.library_music_rounded,
                              isSelected: currentTab == 0,
                              p: p,
                              onTap: () => setState(() => _selectedTab = 0),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildTabButton(
                              title: context.l10n.onlineStream,
                              icon: Icons.public_rounded,
                              isSelected: currentTab == 1,
                              p: p,
                              onTap: () => setState(() => _selectedTab = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // ---------- Content (Local vs Online) ----------
                  if (currentTab == 0)
                    _buildLocalView(context, p, getSongsUseCase, playerCubit, isTablet)
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

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required PulsrPalette p,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: p.glow.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? p.onAccent : p.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? p.onAccent : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
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
          padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 14),
          child: Row(
            children: [
              _QuickCard(
                title: context.l10n.favorites,
                subtitle: context.l10n.likedTracks,
                icon: Icons.favorite_rounded,
                color: p.favorite,
                onTap: () async {
                  final songs = await getSongsUseCase.getAllSongs();
                  songs.fold((l) => null, (list) {
                    final favs = list.where((s) => s.isFavorite).toList();
                    if (favs.isNotEmpty) playerCubit.playSong(favs.first, queue: favs);
                  });
                },
              ),
              const SizedBox(width: 12),
              _QuickCard(
                title: context.l10n.dailyDrive,
                subtitle: context.l10n.autoMix,
                icon: Icons.directions_car_rounded,
                color: p.accent,
                onTap: () async {
                  final songs = await getSongsUseCase.getAllSongs();
                  songs.fold((l) => null, (list) {
                    if (list.isNotEmpty) {
                      final shuffled = List<SongsTableData>.from(list)..shuffle();
                      playerCubit.playSong(shuffled.first, queue: shuffled);
                    }
                  });
                },
              ),
              const SizedBox(width: 12),
              _QuickCard(
                title: context.l10n.focusFlow,
                subtitle: context.l10n.topPlayedTracks,
                icon: Icons.headphones_rounded,
                color: const Color(0xFF1DE9B6),
                onTap: () async {
                  final songs = await getSongsUseCase.getAllSongs();
                  songs.fold((l) => null, (list) {
                    final top = list.where((s) => s.playCount > 0).toList();
                    if (top.isNotEmpty) playerCubit.playSong(top.first, queue: top);
                  });
                },
              ),
            ],
          ),
        ),

        // ---------- Recently played ----------
        StreamBuilder<Result<List<SongsTableData>>>(
          stream: getSongsUseCase.watchRecentlyPlayed(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _SectionError(onRetry: () => setState(() {}));
            }
            final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
            if (songs.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: context.l10n.recentlyPlayed),
                SizedBox(
                  height: isTablet ? 214 : 196,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final size = isTablet ? 158.0 : 138.0;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
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
                                      borderRadius: 18,
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
                                            BoxShadow(color: p.glow, blurRadius: 14, spreadRadius: 1),
                                          ],
                                        ),
                                        child: Icon(Icons.play_arrow_rounded, color: p.onAccent, size: 22),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
                              ],
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
        ),

        const SizedBox(height: 12),

        // ---------- Recently added ----------
        StreamBuilder<Result<List<SongsTableData>>>(
          stream: getSongsUseCase.watchRecentlyAdded(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _SectionError(onRetry: () => setState(() {}));
            }
            final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
            if (songs.isEmpty) return const _EmptyLibrary();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: context.l10n.recentlyAdded),
                for (final song in songs.take(10))
                  SongTile(
                    song: song,
                    onTap: () => playerCubit.playSong(song, queue: songs),
                    onMorePressed: () => showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => SongInfoSheet(song: song),
                    ),
                  ),
              ],
            );
          },
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
          padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/ytm-search'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.18),
                    p.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.travel_explore_rounded, color: p.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search YouTube Music',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Find millions of songs, artists & stream online',
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: p.accent),
                ],
              ),
            ),
          ),
        ),

        // ---------- Quick Moods & Vibe Cards ----------
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 6),
          child: Row(
            children: [
              _QuickCard(
                title: getIt<YtmAccountService>().isLoggedIn ? 'For You' : 'Top Hits',
                subtitle: getIt<YtmAccountService>().isLoggedIn ? 'Personalized' : 'Trending',
                icon: getIt<YtmAccountService>().isLoggedIn ? Icons.auto_awesome_rounded : Icons.local_fire_department_rounded,
                color: getIt<YtmAccountService>().isLoggedIn ? p.accent : const Color(0xFFFF5252),
                onTap: () => setState(() => _selectedOnlineCategory = getIt<YtmAccountService>().isLoggedIn ? 'Recommended For You' : 'Global Top Hits'),
              ),
              const SizedBox(width: 10),
              _QuickCard(
                title: 'Top Hits',
                subtitle: 'Trending',
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF5252),
                onTap: () => setState(() => _selectedOnlineCategory = 'Global Top Hits'),
              ),
              const SizedBox(width: 10),
              _QuickCard(
                title: 'Chill & Lo-Fi',
                subtitle: 'Relaxing',
                icon: Icons.spa_rounded,
                color: const Color(0xFF7C4DFF),
                onTap: () => setState(() => _selectedOnlineCategory = 'Chill & Lo-Fi'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ---------- Category Chips ----------
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
          child: Row(
            children: [
              for (final cat in _onlineCategories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: cat == 'Recommended For You'
                        ? Icon(Icons.auto_awesome_rounded, size: 14, color: _selectedOnlineCategory == cat ? p.onAccent : p.accent)
                        : null,
                    label: Text(cat),
                    selected: _selectedOnlineCategory == cat,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedOnlineCategory = cat);
                      }
                    },
                    selectedColor: p.accent,
                    backgroundColor: p.surfaceContainer,
                    labelStyle: TextStyle(
                      color: _selectedOnlineCategory == cat ? p.onAccent : p.textSecondary,
                      fontWeight: _selectedOnlineCategory == cat ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12.5,
                    ),
                    side: BorderSide(color: _selectedOnlineCategory == cat ? p.accent : p.hairline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ---------- Online Category Content (Carousel + Top Charts) ----------
        _OnlineCategorySection(
          key: ValueKey(_selectedOnlineCategory),
          title: _selectedOnlineCategory == 'Recommended For You'
              ? '✨ Recommended For You (YouTube Music)'
              : (_selectedOnlineCategory == 'Trending Egypt'
                  ? 'Trending in Egypt 🇪🇬'
                  : 'Popular: $_selectedOnlineCategory'),
          future: _getCategoryFuture(_selectedOnlineCategory),
          playerCubit: playerCubit,
          onRetry: () => _retryCategory(_selectedOnlineCategory),
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
                height: isTablet ? 214 : 196,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                  itemCount: 4,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: size,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: p.surfaceContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: p.hairline),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 36,
                                color: p.textTertiary.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Container(
                            width: size * 0.75,
                            height: 12,
                            decoration: BoxDecoration(
                              color: p.surfaceContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            width: size * 0.45,
                            height: 10,
                            decoration: BoxDecoration(
                              color: p.surfaceContainer.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.wifi_tethering_error_rounded, color: p.textTertiary, size: 38),
                  const SizedBox(height: 10),
                  Text(
                    'Could not load songs for $title',
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final tracks = snapshot.data!;
        final songs = [for (final track in tracks) track.toSongData()];
        return BlocProvider<YtmDownloadCubit>(
          create: (_) => getIt<YtmDownloadCubit>(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title),
              SizedBox(
                height: isTablet ? 214 : 196,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return _TrendingCard(
                      song: song,
                      onTap: () => playerCubit.playSong(song, queue: songs),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SectionHeader(title: 'Top Charts & Songs (${songs.length})'),
              for (int i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  index: i + 1,
                  onTap: () => playerCubit.playSong(songs[i], queue: songs),
                  trailing: YtmDownloadButton(song: songs[i]),
                  onMorePressed: () => showModalBottomSheet(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => SongInfoSheet(song: songs[i]),
                  ),
                ),
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
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
                    borderRadius: 18,
                  ),
                  // Scrim keeps the download icon legible over arbitrary artwork.
                  Positioned(
                    right: 6,
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
              const SizedBox(height: 9),
              Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
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
    final isCompact = MediaQuery.sizeOf(context).width < 360;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 10 : 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            color: p.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 6 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: isCompact ? 18 : 20),
              ),
              SizedBox(height: isCompact ? 10 : 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: isCompact ? 12 : 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: isCompact ? 10 : 11,
                ),
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Could not load your library.',
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
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

  Future<void> _scan() async {
    setState(() => _isScanning = true);
    try {
      final scanner = context.read<MediaScannerService>();
      final count = await scanner.scanDeviceLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Scan complete! $count tracks loaded.')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: p.accentContainer,
                shape: BoxShape.circle,
                border: Border.all(color: p.hairline),
              ),
              child: _isScanning
                  ? Padding(
                      padding: const EdgeInsets.all(22),
                      child: CircularProgressIndicator(strokeWidth: 3, color: p.accent),
                    )
                  : Icon(Icons.music_off_rounded, size: 38, color: p.accent),
            ),
            const SizedBox(height: 18),
            Text('No Music Loaded Yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Scan your device storage to load your audio tracks.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              icon: Icon(_isScanning ? Icons.hourglass_top_rounded : Icons.refresh_rounded),
              label: Text(_isScanning ? 'Scanning...' : 'Scan Device Storage'),
              onPressed: _isScanning ? null : _scan,
            ),
          ],
        ),
      ),
    );
  }
}
