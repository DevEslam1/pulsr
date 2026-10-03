import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/pulsr_toast.dart';
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
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// 0 = All (unified 2-section view: Local + Online), 1 = Local Music, 2 = Online Stream
  int _selectedTab = 0;
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onQueryChanged(context, widget.initialQuery!, immediate: true);
        }
      });
    }

    // Reset to All/Local tab if offline-only mode gets enabled while on Online tab
    _settingsSub = context.read<SettingsCubit?>()?.stream.listen((settings) {
      if (settings.offlineOnlyMode && _selectedTab == 2 && mounted) {
        setState(() => _selectedTab = 0);
      }
    });
  }

  // Memoised derived headers using content hash
  int? _derivedCacheHash;
  List<String> _derivedArtistsCache = const [];
  List<String> _derivedAlbumsCache = const [];

  /// Resolves whether online (YouTube Music) search is available.
  ///
  /// [listen] must stay `true` only while building (so the screen rebuilds when
  /// offline-only mode toggles). Event handlers/`onChanged` callbacks must pass
  /// `listen: false`: calling `context.watch` outside build throws
  /// "Tried to listen to a value exposed with provider, from outside of the
  /// widget tree" and would abort the search before it starts.
  bool _isOnlineAvailable(BuildContext context, {bool listen = true}) {
    final settings = listen
        ? context.watch<SettingsCubit?>()
        : context.read<SettingsCubit?>();
    final offlineOnly = settings?.state.offlineOnlyMode ?? false;
    return AppConfig.ytmEnabled && !offlineOnly;
  }

  int _effectiveTab(BuildContext context, {bool listen = true}) {
    if (!_isOnlineAvailable(context, listen: listen)) {
      return 1; // Fallback to Local only
    }
    return _selectedTab;
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

  String? _lastAppliedQueryParam;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppConfig.ytmEnabled && _selectedTab != 1) {
      _selectedTab = 1;
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

  void _onQueryChanged(BuildContext context, String value,
      {bool immediate = false}) {
    // Event handler: read (never watch) providers here.
    final showOnline = _isOnlineAvailable(context, listen: false);
    final effTab = _effectiveTab(context, listen: false);

    if (effTab == 0) {
      // Unified view: search both Local and Online simultaneously
      context.read<SearchCubit>().onQueryChanged(value);
      if (showOnline) {
        context.read<YtmSearchCubit?>()?.onQueryChanged(value);
      }
      _scheduleSuggestions(context, value);
    } else if (effTab == 1) {
      // Local tab
      context.read<SearchCubit>().onQueryChanged(value);
      _scheduleSuggestions(context, value);
    } else if (effTab == 2 && showOnline) {
      // Online tab
      context.read<YtmSearchCubit?>()?.onQueryChanged(value);
    }
  }

  /// C-02: debounced (200 ms) autocomplete lookup for the local search.
  void _scheduleSuggestions(BuildContext context, String value) {
    _suggestTimer?.cancel();
    final trimmed = value.trim();
    // Autocomplete is a Local-tab affordance. On the unified "All" tab it would
    // otherwise *replace* the local+online result sections with a short local
    // suggestion list, leaving the All tab apparently empty until the user
    // switches tabs (which clears the suggestions).
    if (trimmed.isEmpty || _effectiveTab(context, listen: false) != 1) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 200), () async {
      final cubit = context.read<SearchCubit>();
      final results = await cubit.suggestionsFor(trimmed);
      if (!mounted) return;
      if (_searchController.text.trim() != trimmed) return;
      setState(() => _suggestions = results);
    });
  }

  void _applySearch(BuildContext context, String term) {
    _searchController.text = term;
    _searchController.selection = TextSelection.collapsed(offset: term.length);
    setState(() => _suggestions = const []);
    _onQueryChanged(context, term, immediate: true);
  }

  void _applySuggestion(BuildContext context, String suggestion) {
    _applySearch(context, suggestion);
  }

  void _clear(BuildContext context) {
    _searchController.clear();
    _suggestTimer?.cancel();
    if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
    context.read<SearchCubit>().clearQuery();
    if (_isOnlineAvailable(context, listen: false)) {
      context.read<YtmSearchCubit?>()?.clearQuery();
    }
    _searchFocus.requestFocus();
  }

  void _onTabChanged(BuildContext context, int index) {
    if (_selectedTab == index) return;
    _suggestTimer?.cancel();
    setState(() {
      _selectedTab = index;
      _suggestions = const [];
    });
    final query = _searchController.text;
    if (query.trim().isNotEmpty) {
      // Use the builder context (below SearchScreen's own YtmSearchCubit
      // provider) — the State's context sits above it, so reading the online
      // cubit there returns null and the Online tab would never search.
      _onQueryChanged(context, query, immediate: true);
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
        BlocProvider<YtmDownloadCubit>.value(value: getIt<YtmDownloadCubit>()),
      ],
      child: scaffold,
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final p = context.palette;
    final showOnline = _isOnlineAvailable(context);
    final effTab = _effectiveTab(context);

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

                    // ---------- Segmented Tab Selector (All / Local / Online) ----------
                    if (showOnline) ...[
                      const SizedBox(height: AppSpacing.s14),
                      PulsrSegmentedControl(
                        margin: EdgeInsets.symmetric(
                            horizontal: Adaptive.pagePadding(context)),
                        selectedIndex: _selectedTab.clamp(0, 2),
                        onChanged: (i) => _onTabChanged(context, i),
                        segments: [
                          PulsrSegment(
                            label: context.l10n.all,
                            icon: Icons.dashboard_rounded,
                          ),
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
                          hintText: effTab == 2
                              ? context.l10n.searchOnline
                              : effTab == 1
                                  ? context.l10n.searchPlaceholder
                                  : context.l10n.searchLocalOnlineHint,
                          prefixIcon:
                              Icon(Icons.search_rounded, color: p.textTertiary),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, val, _) {
                              if (val.text.isEmpty) {
                                // No silent dead button: the mic only exists
                                // when a speech recognizer is actually wired.
                                if (!AppConfig.voiceSearchEnabled) {
                                  return const SizedBox.shrink();
                                }
                                return IconButton(
                                  constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget),
                                  icon: Icon(Icons.mic_rounded,
                                      color: p.textTertiary),
                                  tooltip: context.l10n.voiceSearch,
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    PulsrToast.show(
                                      context,
                                      message:
                                          context.l10n.voiceSearchUnavailable,
                                      icon: Icons.mic_rounded,
                                    );
                                  },
                                );
                              }
                              return IconButton(
                                constraints: const BoxConstraints(
                                    minWidth: AppSpacing.minTouchTarget,
                                    minHeight: AppSpacing.minTouchTarget),
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
                    if (effTab == 1) ...[
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
                                      end: AppSpacing.sm),
                                  child: _buildChip(context, state, filter, p),
                                ),
                              // C-05: save the current query + filter.
                              if (state.query.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                      start: AppSpacing.sm),
                                  child: ActionChip(
                                    avatar: Icon(Icons.bookmark_add_outlined,
                                        size: 16, color: p.accent),
                                    label: Text(context.l10n.saveSearch),
                                    backgroundColor: p.surfaceContainer,
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
                      child: effTab == 1 &&
                              _suggestions.isNotEmpty &&
                              _searchController.text.trim().isNotEmpty
                          ? _buildSuggestionsList(context, p)
                          : _searchController.text.trim().isEmpty
                              ? _buildEmptySearchBody(
                                  context, state, p, showOnline, effTab)
                              : (showOnline && effTab == 0)
                                  ? _UnifiedSearchResults(
                                      query: _searchController.text.trim(),
                                      onSelectTag: (tag) =>
                                          _applySearch(context, tag),
                                      onOpenArtist: (name) =>
                                          _openDerivedArtist(context, name),
                                      onOpenAlbum: (name) =>
                                          _openDerivedAlbum(context, name),
                                    )
                                  : (showOnline && effTab == 2)
                                      ? _OnlineResults(
                                          onSelectTag: (tag) =>
                                              _applySearch(context, tag),
                                        )
                                      : _buildLocalBody(
                                          context, state, playerCubit, p),
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

  // ---------- Empty Body with Recent Searches (5 Local & 5 Online) ----------
  Widget _buildEmptySearchBody(
    BuildContext context,
    SearchState state,
    PulsrPalette p,
    bool showOnline,
    int effTab,
  ) {
    final ytmCubit = showOnline ? context.read<YtmSearchCubit?>() : null;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: Adaptive.pagePadding(context),
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Local Recent Searches (up to 5 items)
          if ((effTab == 0 || effTab == 1) && state.history.isNotEmpty) ...[
            _buildRecentSectionHeader(
              context: context,
              icon: Icons.library_music_rounded,
              title:
                  '${context.l10n.recentSearches} • ${context.l10n.localMusic}',
              onClear: () {
                HapticFeedback.lightImpact();
                context.read<SearchCubit>().clearHistory();
              },
              p: p,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: state.history.take(5).map((term) {
                return InputChip(
                  avatar: Icon(Icons.history_rounded,
                      size: 14, color: p.textTertiary),
                  label: Text(term),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  deleteIconColor: p.textTertiary,
                  labelStyle: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                  onDeleted: () =>
                      context.read<SearchCubit>().removeHistoryQuery(term),
                  onPressed: () => _applySearch(context, term),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 2. Online Recent Searches (up to 5 items)
          if (showOnline &&
              (effTab == 0 || effTab == 2) &&
              ytmCubit != null) ...[
            ValueListenableBuilder<List<String>>(
              valueListenable: ytmCubit.historyNotifier,
              builder: (context, onlineHistory, _) {
                if (onlineHistory.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecentSectionHeader(
                      context: context,
                      icon: Icons.public_rounded,
                      title:
                          '${context.l10n.recentSearches} • ${context.l10n.onlineStream}',
                      onClear: () {
                        HapticFeedback.lightImpact();
                        ytmCubit.clearHistory();
                      },
                      p: p,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: onlineHistory.take(5).map((term) {
                        return InputChip(
                          avatar: Icon(Icons.public_rounded,
                              size: 14, color: p.accent),
                          label: Text(term),
                          backgroundColor: p.surfaceContainer,
                          side: BorderSide(color: p.hairline),
                          deleteIcon: const Icon(Icons.close_rounded, size: 14),
                          deleteIconColor: p.textTertiary,
                          labelStyle: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600,
                          ),
                          onDeleted: () => ytmCubit.removeHistoryQuery(term),
                          onPressed: () => _applySearch(context, term),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          ],

          // 3. Saved Searches
          ValueListenableBuilder<List<String>>(
            valueListenable: context.read<SearchCubit>().savedSearches,
            builder: (context, saved, _) {
              if (saved.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.savedSearches.toUpperCase(),
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w800,
                      color: p.textTertiary,
                      letterSpacing: AppTracking.wide,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      for (final entry in saved)
                        InputChip(
                          avatar: Icon(Icons.bookmark_outline_rounded,
                              size: 14, color: p.accent),
                          label:
                              Text(SearchCubit.decodeSavedSearch(entry).query),
                          backgroundColor: p.surfaceContainer,
                          side: BorderSide(color: p.hairline),
                          deleteIcon: const Icon(Icons.close_rounded, size: 14),
                          deleteIconColor: p.textTertiary,
                          labelStyle: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600,
                          ),
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
                  const SizedBox(height: AppSpacing.md),
                ],
              );
            },
          ),

          // 4. Quick Discovery / Popular Tags
          Text(
            (effTab == 2
                    ? context.l10n.popularSearches
                    : context.l10n.quickDiscovery)
                .toUpperCase(),
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w800,
              color: p.textTertiary,
              letterSpacing: AppTracking.wide,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final tag in effTab == 2
                  ? [
                      'Top Hits',
                      'Trending',
                      'Lo-Fi Beats',
                      'Pop',
                      'Hip-Hop',
                      'Rock Classics',
                      'Chillout',
                      'Electronic'
                    ]
                  : [
                      'Rock',
                      'Pop',
                      'Hip-Hop',
                      'Acoustic',
                      'FLAC',
                      'Lossless',
                      'Jazz',
                      'Electronic',
                      'Top Hits',
                      'Trending',
                    ])
                ActionChip(
                  label: Text(_localizedTag(context, tag)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  labelStyle: TextStyle(
                    color: p.accent,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                  ),
                  onPressed: () => _applySearch(context, tag),
                ),
            ],
          ),
        ],
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
      onSelected: (_) {
        HapticFeedback.selectionClick();
        _selectLocalFilter(context, filter);
      },
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
    // Only show the skeleton when there is nothing to show yet; keeping the
    // previous results visible prevents flicker on every keystroke.
    if (state.isLoading && state.results.isEmpty) {
      return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
    }
    final errorMessage = state.errorMessage;
    if (errorMessage != null && state.results.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.somethingWentWrong,
        subtitle: errorMessage,
        primaryActionLabel: context.l10n.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: () =>
            context.read<SearchCubit>().onQueryChanged(state.query),
      );
    }
    if (state.results.isEmpty) {
      return PulsrEmptyState(
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
            style:
                TextStyle(color: p.textTertiary, fontSize: AppFontSize.label)),
        trailing: Icon(Icons.chevron_right_rounded, color: p.textTertiary),
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
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600)),
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
          (a) => (a?.name as String?)?.toLowerCase() == name.toLowerCase(),
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
          (a) => (a?.title as String?)?.toLowerCase() == name.toLowerCase(),
          orElse: () => null);
      if (match != null) {
        context.push('/album', extra: match);
        return;
      }
    } catch (_) {}
    context.read<SearchCubit>().setFilter('Albums');
  }
}

// ==================== UNIFIED SEARCH RESULTS (2 SECTIONS) ====================
class _UnifiedSearchResults extends StatefulWidget {
  final String query;
  final ValueChanged<String>? onSelectTag;
  final ValueChanged<String>? onOpenArtist;
  final ValueChanged<String>? onOpenAlbum;

  const _UnifiedSearchResults({
    required this.query,
    this.onSelectTag,
    this.onOpenArtist,
    this.onOpenAlbum,
  });

  @override
  State<_UnifiedSearchResults> createState() => _UnifiedSearchResultsState();
}

class _UnifiedSearchResultsState extends State<_UnifiedSearchResults> {
  bool _expandLocal = false;
  bool _expandOnline = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final isOffline =
        context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;

    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, localState) {
        return BlocBuilder<YtmSearchCubit, YtmSearchState>(
          builder: (context, ytmState) {
            final localDone = !localState.isLoading;
            final onlineDone = isOffline || !ytmState.isLoading;
            final localEmpty = localState.results.isEmpty;
            final onlineEmpty =
                isOffline || (ytmState.results.isEmpty && ytmState.hasSearched);

            if (localDone &&
                onlineDone &&
                localEmpty &&
                onlineEmpty &&
                ytmState.errorMessage == null &&
                localState.errorMessage == null) {
              return PulsrEmptyState(
                icon: Icons.search_off_rounded,
                title: context.l10n.noResultsFound,
                subtitle: '${context.l10n.noResultsSubtitle} "${widget.query}"',
                primaryActionLabel: context.l10n.clearSearchQuery,
                primaryActionIcon: Icons.backspace_rounded,
                onPrimaryAction: () {
                  context.read<SearchCubit>().clearQuery();
                  context.read<YtmSearchCubit>().clearQuery();
                },
              );
            }

            final localResults = localState.results;
            final localToDisplay =
                _expandLocal ? localResults : localResults.take(5).toList();

            final onlineTracks = ytmState.results;
            final onlineSongs = [
              for (final track in onlineTracks) track.toSongData()
            ];
            final onlineToDisplay =
                _expandOnline ? onlineSongs : onlineSongs.take(10).toList();

            return RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              onRefresh: () async {
                context.read<SearchCubit>().onQueryChanged(widget.query);
                if (!isOffline) {
                  context.read<YtmSearchCubit>().onQueryChanged(widget.query);
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.only(
                  bottom: AppSpacing.scrollBottom,
                  top: AppSpacing.xxs,
                ),
                children: [
                  // ==================== SECTION 1: LOCAL RESULTS ====================
                  _buildSectionHeader(
                    context: context,
                    icon: Icons.library_music_rounded,
                    title: context.l10n.localMusic,
                    count: localResults.length,
                    isLoading: localState.isLoading,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  if (localState.errorMessage != null && localResults.isEmpty)
                    _buildErrorSectionCard(
                      context: context,
                      errorMessage: localState.errorMessage!,
                      onRetry: () => context
                          .read<SearchCubit>()
                          .onQueryChanged(widget.query),
                      p: p,
                    )
                  else if (localState.isLoading && localResults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SkeletonList(itemCount: 3),
                    )
                  else if (localResults.isEmpty)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.library_music_outlined,
                      message: context.l10n.noLocalSongsMatch(widget.query),
                      p: p,
                    )
                  else ...[
                    for (final song in localToDisplay)
                      SongTile(
                        song: song,
                        subtitleOverride: '${song.artist} • ${song.album}',
                        onTap: () =>
                            playerCubit.playSong(song, queue: localResults),
                        onMorePressed: () =>
                            SongInfoSheet.show(context, song: song),
                      ),
                    if (localResults.length > 5)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs),
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => _expandLocal = !_expandLocal),
                            icon: Icon(
                              _expandLocal
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: p.accent,
                            ),
                            label: Text(
                              _expandLocal
                                  ? context.l10n.showLess
                                  : context.l10n.showMore,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],

                  // Divider between Section 1 and Section 2
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Divider(color: p.hairline, height: 1),
                  ),

                  // ==================== SECTION 2: ONLINE RESULTS ====================
                  _buildSectionHeader(
                    context: context,
                    icon: Icons.public_rounded,
                    title: context.l10n.onlineStream,
                    count: onlineTracks.length,
                    isLoading: ytmState.isLoading,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  if (isOffline)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.wifi_off_rounded,
                      message: context.l10n.offlineOnlyMode,
                      p: p,
                    )
                  else if (ytmState.isLoading && onlineTracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SkeletonList(itemCount: 4),
                    )
                  else if (ytmState.errorMessage != null)
                    _buildErrorSectionCard(
                      context: context,
                      errorMessage: ytmState.errorMessage!,
                      onRetry: context.read<YtmSearchCubit>().retry,
                      p: p,
                    )
                  else if (onlineTracks.isEmpty && ytmState.hasSearched)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.search_off_rounded,
                      message: context.l10n.noOnlineSongsMatch(widget.query),
                      p: p,
                    )
                  else ...[
                    for (var i = 0; i < onlineToDisplay.length; i++)
                      SongTile(
                        song: onlineToDisplay[i],
                        subtitleOverride: (i < onlineTracks.length)
                            ? onlineTracks[i].artist
                            : null,
                        onTap: () => playerCubit.playSong(onlineToDisplay[i],
                            queue: onlineSongs),
                        trailing: YtmDownloadButton(song: onlineToDisplay[i]),
                      ),
                    if (onlineSongs.length > 10)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs),
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => _expandOnline = !_expandOnline),
                            icon: Icon(
                              _expandOnline
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: p.accent,
                            ),
                            label: Text(
                              _expandOnline
                                  ? context.l10n.showLess
                                  : context.l10n.showMore,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------- Section Header Widget ----------
Widget _buildSectionHeader({
  required BuildContext context,
  required IconData icon,
  required String title,
  required int count,
  required bool isLoading,
  required PulsrPalette p,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(
      horizontal: Adaptive.pagePadding(context),
      vertical: AppSpacing.xxs,
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: p.accent),
        const SizedBox(width: AppSpacing.s8),
        Text(
          title,
          style: TextStyle(
            fontSize: AppFontSize.bodyLarge,
            fontWeight: FontWeight.w800,
            color: p.textPrimary,
          ),
        ),
        const Spacer(),
        if (isLoading)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(p.accent),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.r12),
              border: Border.all(color: p.hairline),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w700,
                color: p.textSecondary,
              ),
            ),
          ),
      ],
    ),
  );
}

// ---------- Compact Empty Card for a Section ----------
Widget _buildEmptySectionCard({
  required BuildContext context,
  required IconData icon,
  required String message,
  required PulsrPalette p,
}) {
  return Container(
    margin: EdgeInsets.symmetric(
      horizontal: Adaptive.pagePadding(context),
      vertical: AppSpacing.xs,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: p.surfaceContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadii.r12),
      border: Border.all(color: p.hairline),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: p.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: p.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------- Compact Error Card for a Section ----------
Widget _buildErrorSectionCard({
  required BuildContext context,
  required String errorMessage,
  required VoidCallback onRetry,
  required PulsrPalette p,
}) {
  return Container(
    margin: EdgeInsets.symmetric(
      horizontal: Adaptive.pagePadding(context),
      vertical: AppSpacing.xs,
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: p.surfaceContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadii.r12),
      border: Border.all(color: p.hairline),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 20, color: p.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            errorMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: p.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        TextButton(
          onPressed: onRetry,
          child: Text(
            context.l10n.tryAgain,
            style: TextStyle(
              color: p.accent,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------- Recent Searches Section Header ----------
Widget _buildRecentSectionHeader({
  required BuildContext context,
  required IconData icon,
  required String title,
  required VoidCallback onClear,
  required PulsrPalette p,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: p.textTertiary),
          const SizedBox(width: AppSpacing.s6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w700,
              letterSpacing: AppTracking.wide,
              color: p.textTertiary,
            ),
          ),
        ],
      ),
      GestureDetector(
        onTap: onClear,
        child: Text(
          context.l10n.clear,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w600,
            color: p.accent,
          ),
        ),
      ),
    ],
  );
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
          return PulsrEmptyState(
            icon: Icons.wifi_off_rounded,
            title: context.l10n.offlineOnlyMode,
            subtitle: context.l10n.browseYtmSearchScreenDesc,
          );
        }

        if (state.isLoading) {
          return const SkeletonList(
              padding: EdgeInsets.only(top: AppSpacing.xs));
        }

        if (state.errorMessage != null) {
          return PulsrEmptyState(
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
            return PulsrEmptyState(
              icon: Icons.search_off_rounded,
              title: context.l10n.browseNoResultsFound,
              subtitle:
                  '${context.l10n.browseNoYtmMatchesFor} "${state.query.trim()}".',
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore_rounded,
                      size: 48, color: p.textTertiary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.searchYtm,
                    style: TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    context.l10n.ytmSearchDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.bodySmall),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    context.l10n.popularSearches,
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
