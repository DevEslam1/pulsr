import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../library/cubit/library_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/cubit/ytm_search_cubit.dart';
import '../../ytm_search/cubit/ytm_search_state.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../../data/db/app_database.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// 0 = Local Music, 1 = Online Stream
  int _selectedTab = 0;
  StreamSubscription? _settingsSub;

  // Memoised derived headers using content hash
  int? _derivedCacheHash;
  List<String> _derivedArtistsCache = const [];
  List<String> _derivedAlbumsCache = const [];

  bool _isOnlineAvailable(BuildContext context) {
    final offlineOnly =
        context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;
    return AppConfig.ytmEnabled && !offlineOnly;
  }

  static const List<String> _localFilters = [
    'All',
    'Songs',
    'Artists',
    'Albums',
    'FLAC',
    'MP3',
    'Lossless',
  ];

  // C-02: autocomplete suggestions
  final FocusNode _searchFocus = FocusNode();
  List<String> _suggestions = const [];
  Timer? _suggestTimer;

  @override
  void initState() {
    super.initState();

    // Reset to local tab if offline-only mode gets enabled
    _settingsSub = context.read<SettingsCubit?>()?.stream.listen((settings) {
      if (settings.offlineOnlyMode && _selectedTab == 1 && mounted) {
        setState(() => _selectedTab = 0);
      }
    });
  }

  String? _lastAppliedQueryParam;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppConfig.ytmEnabled && _selectedTab != 0) {
      _selectedTab = 0;
    }
    // Assistant / deep-link entry: prefill and run the search when the route
    // carries a `?q=` query (e.g. `go('/search?q=...')` from voice search).
    final q = GoRouterState.of(context).uri.queryParameters['q'];
    if (q != null && q.trim().isNotEmpty && q != _lastAppliedQueryParam) {
      _lastAppliedQueryParam = q;
      _searchController.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onQueryChanged(context, q, immediate: true);
      });
    }
  }

  @override
  void deactivate() {
    _suggestTimer?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _suggestTimer?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(BuildContext context, String value, {bool immediate = false}) {
    if (_isOnlineTab) {
      context.read<YtmSearchCubit>().onQueryChanged(value);
    } else {
      context.read<SearchCubit>().onQueryChanged(value);
      _scheduleSuggestions(context, value);
    }
  }

  /// C-02: debounced (200 ms) autocomplete lookup for the local search tab.
  void _scheduleSuggestions(BuildContext context, String value) {
    _suggestTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty || _isOnlineTab) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 200), () async {
      final cubit = context.read<SearchCubit>();
      final results = await cubit.suggestionsFor(trimmed);
      if (!mounted) return;
      // Ignore stale responses for a query the user has since changed.
      if (_searchController.text.trim() != trimmed) return;
      setState(() => _suggestions = results);
    });
  }

  void _applySuggestion(BuildContext context, String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.collapsed(
        offset: suggestion.length);
    setState(() => _suggestions = const []);
    if (_isOnlineTab) {
      context.read<YtmSearchCubit>().onQueryChanged(suggestion);
    } else {
      context.read<SearchCubit>().useHistoryQuery(suggestion);
    }
  }

  void _clear(BuildContext context) {
    _searchController.clear();
    _suggestTimer?.cancel();
    if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
    if (_isOnlineTab) {
      context.read<YtmSearchCubit>().clearQuery();
    } else {
      context.read<SearchCubit>().clearQuery();
    }
    _searchFocus.requestFocus();
  }

  bool get _isOnlineTab => AppConfig.ytmEnabled && _selectedTab == 1;

  void _onTabChanged(int index) {
    if (_selectedTab == index) return;
    _suggestTimer?.cancel();
    setState(() {
      _selectedTab = index;
      _suggestions = const [];
    });
    final query = _searchController.text;
    if (index == 1 && AppConfig.ytmEnabled) {
      context.read<YtmSearchCubit>().onQueryChanged(query);
    } else {
      context.read<SearchCubit>().onQueryChanged(query);
      if (query.trim().isNotEmpty) {
        _scheduleSuggestions(context, query);
      }
    }
  }

  void _selectLocalFilter(BuildContext context, String filter) {
    context.read<SearchCubit>().setFilter(filter);
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = _buildScaffold(context);
    if (!AppConfig.ytmEnabled) return scaffold;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<YtmSearchCubit>()),
        BlocProvider<YtmDownloadCubit>.value(
            value: getIt<YtmDownloadCubit>()),
      ],
      child: scaffold,
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final p = context.palette;
    final showOnline = _isOnlineAvailable(context);
    final currentTab = showOnline ? _selectedTab : 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                final playerCubit = context.read<PlayerCubit>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---------- Header ----------
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                          Adaptive.pagePadding(context),
                          16,
                          Adaptive.pagePadding(context),
                          0),
                      child: Text(
                        context.l10n.search,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),

                    // ---------- Segmented Tab Selector (Local vs Online) ----------
                    if (showOnline) ...[
                      const SizedBox(height: AppSpacing.s14),
                      PulsrSegmentedControl(
                        margin: EdgeInsets.symmetric(
                            horizontal: Adaptive.pagePadding(context)),
                        selectedIndex: currentTab,
                        onChanged: _onTabChanged,
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
                    ],

                    // ---------- Search Input Field ----------
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        onChanged: (value) => _onQueryChanged(context, value),
                        decoration: InputDecoration(
                          hintText: (showOnline && currentTab == 1)
                              ? context.l10n.searchOnline
                              : context.l10n.searchPlaceholder,
                          prefixIcon:
                              Icon(Icons.search_rounded, color: p.textTertiary),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, val, _) {
                              if (val.text.isEmpty) return const SizedBox.shrink();
                              return IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: p.textTertiary),
                                tooltip: context.l10n.clear,
                                onPressed: () => _clear(context),
                              );
                            },
                          ),
                        ),
                      ),
                    ),



                    // ---------- Filter Chips (Local Tab Only) ----------
                    if (currentTab == 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: Adaptive.pagePadding(context)),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              for (final filter in _localFilters)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                      end: AppSpacing.xs),
                                  child: _buildChip(context, state, filter, p),
                                ),
                              // C-05: save the current query + filter.
                              if (state.query.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                      start: AppSpacing.xs),
                                  child: ActionChip(
                                    avatar: Icon(Icons.bookmark_add_outlined,
                                        size: 16, color: p.accent),
                                    label: Text(context.l10n.saveSearch),                                    backgroundColor: p.surfaceContainer,
                                    side: BorderSide(color: p.hairline),
                                    labelStyle: TextStyle(
                                        color: p.accent,
                                        fontSize: AppFontSize.label,
                                        fontWeight: FontWeight.w700),
                                    onPressed: () => context
                                        .read<SearchCubit>()
                                        .saveCurrentSearch(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.xs),

                    // ---------- Search Content Body ----------
                    Expanded(
                      child: (showOnline && currentTab == 1)
                          ? _OnlineResults(
                              onSelectTag: (tag) {
                                _searchController.text = tag;
                                _onQueryChanged(context, tag);
                              },
                            )
                          : _buildLocalBody(context, state, playerCubit, p),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _getFilterLabel(BuildContext context, String filter) {
    switch (filter) {
      case 'All':
        return context.l10n.all;
      case 'Songs':
        return context.l10n.songs;
      case 'Artists':
        return context.l10n.artists;
      case 'Albums':
        return context.l10n.albums;
      default:
        return filter;
    }
  }

  Widget _buildChip(
      BuildContext context, SearchState state, String filter, PulsrPalette p) {
    final selected = state.selectedFilter == filter;
    return ChoiceChip(
      label: Text(_getFilterLabel(context, filter)),
      selected: selected,
      labelStyle: TextStyle(
        color: selected ? p.accent : p.textSecondary,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      onSelected: (_) => _selectLocalFilter(context, filter),
    );
  }

  Widget _buildSuggestionsList(BuildContext context, PulsrPalette p) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: Adaptive.pagePadding(context),
        vertical: AppSpacing.xs,
      ),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => Divider(color: p.hairline, height: 1),
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          leading: Icon(Icons.search_rounded, color: p.textTertiary, size: 20),
          title: Text(
            suggestion,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: const Icon(Icons.north_west_rounded, size: 16),
          onTap: () => _applySuggestion(context, suggestion),
        );
      },
    );
  }

  Widget _buildLocalBody(BuildContext context, SearchState state,
      PlayerCubit playerCubit, PulsrPalette p) {
    if (_suggestions.isNotEmpty && _searchController.text.trim().isNotEmpty) {
      return _buildSuggestionsList(context, p);
    }
    if (state.isLoading) {
      return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
    }
    if (state.results.isEmpty) {
      if (state.query.isEmpty) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 48, color: p.textTertiary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.search,
                  style: TextStyle(
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary),
                ),
                const SizedBox(height: AppSpacing.s6),
                Text(
                  context.l10n.searchPlaceholder,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                ),
                const SizedBox(height: AppSpacing.lg),
                // C-05: saved searches (query + filter), re-executed on tap.
                ValueListenableBuilder<List<String>>(
                  valueListenable: context.read<SearchCubit>().savedSearches,
                  builder: (context, saved, _) {
                    if (saved.isEmpty) {
                      if (state.history.length > 3) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_add_outlined, size: 14, color: p.textTertiary),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(
                                '${context.l10n.search}: Tap "Save search" after searching to bookmark it',
                                style: TextStyle(fontSize: AppFontSize.caption, color: p.textTertiary),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.savedSearches,
                          style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w800,
                              color: p.textTertiary,
                              letterSpacing: AppTracking.wide),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final entry in saved)
                              InputChip(
                                avatar: Icon(Icons.bookmark_outline_rounded,
                                    size: 16, color: p.accent),
                                label: Text(
                                    SearchCubit.decodeSavedSearch(entry).query),
                                backgroundColor: p.surfaceContainer,
                                side: BorderSide(color: p.hairline),
                                deleteIcon:
                                    const Icon(Icons.close_rounded, size: 16),
                                deleteIconColor: p.textTertiary,
                                labelStyle: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w600),
                                onDeleted: () => context
                                    .read<SearchCubit>()
                                    .removeSavedSearch(entry),
                                onPressed: () {
                                  final decoded =
                                      SearchCubit.decodeSavedSearch(entry);
                                  _searchController.text = decoded.query;
                                  context
                                      .read<SearchCubit>()
                                      .setFilter(decoded.filter);
                                  _onQueryChanged(context, decoded.query,
                                      immediate: true);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    );
                  },
                ),
                if (state.history.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(context.l10n.recentSearches,
                        style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w800,
                            color: p.textTertiary,
                            letterSpacing: AppTracking.wide),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      GestureDetector(
                        onTap: () =>
                            context.read<SearchCubit>().clearHistory(),
                        child: Icon(Icons.clear_all_rounded,
                            size: 16, color: p.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final h in state.history)
                        InputChip(
                          label: Text(h),
                          backgroundColor: p.surfaceContainer,
                          side: BorderSide(color: p.hairline),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          deleteIconColor: p.textTertiary,
                          labelStyle: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600),
                          onDeleted: () => context
                              .read<SearchCubit>()
                              .removeHistoryQuery(h),
                          onPressed: () {
                            _searchController.text = h;
                            context.read<SearchCubit>().useHistoryQuery(h);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Text(context.l10n.quickDiscovery,
                  style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                      color: p.textTertiary,
                      letterSpacing: AppTracking.wide),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in [
                      'Rock',
                      'Pop',
                      'Hip-Hop',
                      'Acoustic',
                      'FLAC',
                      'Lossless',
                      'Jazz',
                      'Electronic'
                    ])
                      ActionChip(
                        label: Text(_localizedTag(context, tag)),
                        backgroundColor: p.surfaceContainer,
                        side: BorderSide(color: p.hairline),
                        labelStyle: TextStyle(
                            color: p.accent,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700),
                        onPressed: () {
                          _searchController.text = tag;
                          _onQueryChanged(context, tag);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: context.l10n.noResultsFound,
        subtitle: context.l10n.noResultsSubtitle,
        primaryActionLabel: context.l10n.clearSearchQuery,
        primaryActionIcon: Icons.backspace_rounded,
        onPrimaryAction: () => _clear(context),
      );
    }
    final filter = state.selectedFilter;
    final derivedArtists = (filter == 'All' || filter == 'Artists')
        ? _derivedArtists(state).take(3).toList()
        : const <String>[];
    final derivedAlbums = (filter == 'All' || filter == 'Albums')
        ? _derivedAlbums(state).take(3).toList()
        : const <String>[];
    final headerCount = derivedArtists.length + derivedAlbums.length;
    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      onRefresh: () async {
        context.read<SearchCubit>().onQueryChanged(state.query);
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        padding: const EdgeInsets.only(
            bottom: AppSpacing.scrollBottom, top: AppSpacing.xxs),
        itemCount: state.results.length + headerCount,
        itemBuilder: (context, index) {
          if (index < headerCount) {
            return _buildDerivedHeader(
                context, index, derivedArtists, derivedAlbums, p);
          }
          final song = state.results[index - headerCount];
          return SongTile(
            song: song,
            subtitleOverride: '${song.artist} • ${song.album}',
            onTap: () => playerCubit.playSong(song, queue: state.results),
            onMorePressed: () => SongInfoSheet.show(context, song: song),
          );
        },
      ),
    );
  }

    int _computeResultsHash(List<SongsTableData> results) {
      if (results.isEmpty) return 0;
      // Hash every id, not just the endpoints: interior changes (re-rank, edited
      // metadata) must invalidate the derived artist/album chip caches.
      return Object.hashAll(results.map((s) => s.id));
    }

    void _ensureDerivedCache(SearchState state) {
      final hash = _computeResultsHash(state.results);
      if (_derivedCacheHash == hash) return;
      _derivedCacheHash = hash;
      final artists = <String>[];
      final albums = <String>[];
      final seenA = <String>{};
      final seenB = <String>{};
      for (final s in state.results) {
        final a = s.artist.trim();
        if (a.isNotEmpty && seenA.add(a.toLowerCase())) artists.add(a);
        final b = s.album.trim();
        if (b.isNotEmpty && seenB.add(b.toLowerCase())) albums.add(b);
      }
      _derivedArtistsCache = artists;
      _derivedAlbumsCache = albums;
    }

    List<String> _derivedArtists(SearchState state) {
      _ensureDerivedCache(state);
      return _derivedArtistsCache;
    }

    List<String> _derivedAlbums(SearchState state) {
      _ensureDerivedCache(state);
      return _derivedAlbumsCache;
    }

    Widget _buildDerivedHeader(BuildContext context, int index,
        List<String> artists, List<String> albums, PulsrPalette p) {
      final total = artists.length + albums.length;
      if (index >= total) return const SizedBox.shrink();
      if (index < artists.length) {
        final name = artists[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: p.accent.withValues(alpha: 0.15),
            child: Icon(Icons.person_rounded, color: p.accent, size: 20),
          ),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600)),
          subtitle: Text(context.l10n.artist,
              style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label)),
          trailing:
              Icon(Icons.chevron_right_rounded, color: p.textTertiary),
          onTap: () => _openDerivedArtist(context, name),
        );
      }
      final album = albums[index - artists.length];
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: p.accent.withValues(alpha: 0.15),
          child: Icon(Icons.album_rounded, color: p.accent, size: 20),
        ),
        title: Text(album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(context.l10n.album,
            style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label)),
        trailing: Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        onTap: () => _openDerivedAlbum(context, album),
      );
    }

    void _openDerivedArtist(BuildContext context, String name) {
      try {
        final lib = context.read<LibraryCubit>().state.artists;
        final match = lib.cast<dynamic>().firstWhere(
            (a) =>
                (a?.name as String?)?.toLowerCase() == name.toLowerCase(),
            orElse: () => null);
        if (match != null) {
          context.push('/artist', extra: match);
          return;
        }
      } catch (_) {}
      context.read<SearchCubit>().setFilter('Artists');
    }

    void _openDerivedAlbum(BuildContext context, String name) {
      try {
        final lib = context.read<LibraryCubit>().state.albums;
        final match = lib.cast<dynamic>().firstWhere(
            (a) =>
                (a?.title as String?)?.toLowerCase() == name.toLowerCase(),
            orElse: () => null);
        if (match != null) {
          context.push('/album', extra: match);
          return;
        }
      } catch (_) {}
      context.read<SearchCubit>().setFilter('Albums');
    }
}

/// The "Online" tab body: live YouTube Music results with per-row download
/// controls. Only ever mounted in an ENABLE_YTM build, under the
/// [YtmSearchCubit] / [YtmDownloadCubit] providers created by [SearchScreen].
class _OnlineResults extends StatelessWidget {
  final ValueChanged<String>? onSelectTag;

  const _OnlineResults({this.onSelectTag});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return BlocBuilder<YtmSearchCubit, YtmSearchState>(
      builder: (context, state) {
        final isOffline =
            context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;
        if (isOffline) {
          return EmptyStateWidget(
            icon: Icons.wifi_off_rounded,
            title: context.l10n.offlineOnlyMode,
            subtitle: context.l10n.browseYtmSearchScreenDesc,
          );
        }

        if (state.isLoading) {
          return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
        }

        if (state.errorMessage != null) {
          return EmptyStateWidget(
            icon: Icons.cloud_off_rounded,
            title: context.l10n.browseSearchFailed,
            subtitle: resolveUiErrorMessage(context, state.errorMessage!),
            primaryActionLabel: context.l10n.tryAgain,
            primaryActionIcon: Icons.refresh_rounded,
            onPrimaryAction: context.read<YtmSearchCubit>().retry,
          );
        }

        if (state.results.isEmpty) {
          if (state.hasSearched) {
            return EmptyStateWidget(
              icon: Icons.search_off_rounded,
              title: context.l10n.browseNoResultsFound,
              subtitle:
                  '${context.l10n.browseNoYtmMatchesFor} "${state.query.trim()}".',
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore_rounded,
                      size: 48, color: p.textTertiary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(context.l10n.searchYtm,
                    style: TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(context.l10n.ytmSearchDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(context.l10n.popularSearches,
                    style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                        color: p.textTertiary,
                        letterSpacing: AppTracking.wide),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final tag in [
                        'Top Hits',
                        'Trending',
                        'Lo-Fi Beats',
                        'Pop',
                        'Hip-Hop',
                        'Rock Classics',
                        'Chillout',
                        'Electronic'
                      ])
                        ActionChip(
                          label: Text(_localizedTag(context, tag)),
                          backgroundColor: p.surfaceContainer,
                          side: BorderSide(color: p.hairline),
                          labelStyle: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700),
                          onPressed: () => onSelectTag?.call(tag),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        final songs = [for (final track in state.results) track.toSongData()];
        return RefreshIndicator(
          color: p.accent,
          backgroundColor: p.surfaceContainer,
          onRefresh: () async {
            if (state.query.isNotEmpty) {
              context.read<YtmSearchCubit>().onQueryChanged(state.query);
            }
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            padding: const EdgeInsets.only(
                bottom: AppSpacing.scrollBottom, top: AppSpacing.xxs),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return SongTile(
                song: song,
                subtitleOverride: state.results[index].artist,
                onTap: () => playerCubit.playSong(song, queue: songs),
                trailing: YtmDownloadButton(song: song),
              );
            },
          ),
        );
      },
    );
  }
}

String _localizedTag(BuildContext context, String tag) {
  switch (tag) {
    case 'Rock':
      return context.l10n.browseRock;
    case 'Pop':
      return context.l10n.browsePop;
    case 'Hip-Hop':
      return context.l10n.browseHipHop;
    case 'Acoustic':
      return context.l10n.browseAcoustic;
    case 'FLAC':
      return context.l10n.browseFlac;
    case 'Lossless':
      return context.l10n.browseLossless;
    case 'Jazz':
      return context.l10n.browseJazz;
    case 'Electronic':
      return context.l10n.browseElectronic;
    case 'Top Hits':
      return context.l10n.browseTopHits;
    case 'Trending':
      return context.l10n.browseTrending;
    case 'Lo-Fi Beats':
      return context.l10n.browseLofiBeats;
    case 'Rock Classics':
      return context.l10n.browseRockClassics;
    case 'Chillout':
      return context.l10n.browseChillout;
    default:
      return tag;
  }
}
