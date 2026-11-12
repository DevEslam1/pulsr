import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/highlighted_text.dart';
import '../../../core/widgets/pulsr_artwork_header.dart';
import '../../../core/widgets/pulsr_chip.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_scroll_edge_fade.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/db/app_database.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/cubit/ytm_search_cubit.dart';
import '../../ytm_search/cubit/ytm_search_state.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';
import 'widgets/highlighted_song_tile.dart';

import '../../../core/utils/pulsr_haptics.dart';
const List<String> _onlineTags = [
  'Top Hits',
  'Trending',
  'Lo-Fi Beats',
  'Pop',
  'Hip-Hop',
  'Rock Classics',
  'Chillout',
  'Electronic',
];

/// Provider shell. Everything that talks to [YtmSearchCubit] lives in
/// [_SearchView], which sits *below* these providers.
class SearchScreen extends StatelessWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  Widget build(BuildContext context) {
    final view = _SearchView(initialQuery: initialQuery);
    if (!AppConfig.ytmEnabled) return view;
    if (!getIt.isRegistered<YtmSearchCubit>() ||
        !getIt.isRegistered<YtmDownloadCubit>()) {
      return view;
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<YtmSearchCubit>()),
        BlocProvider<YtmDownloadCubit>.value(value: getIt<YtmDownloadCubit>()),
      ],
      child: view,
    );
  }
}

class _SearchView extends StatefulWidget {
  final String? initialQuery;
  const _SearchView({this.initialQuery});

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// 0 = All (Local + Online), 1 = Local, 2 = Online.
  int _tab = 0;

  /// Mirrors the text field so Online-tab typing triggers immediate UI updates.
  String _text = '';
  bool _hasFocus = false;

  List<String> _suggestions = const [];
  bool _showSuggestions = false;
  Timer? _suggestTimer;
  StreamSubscription? _settingsSub;
  String? _lastAppliedQueryParam;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);

    final initial = widget.initialQuery;
    if (initial != null && initial.trim().isNotEmpty) {
      _lastAppliedQueryParam = initial;
      _prefill(initial);
    }

    _settingsSub = context.read<SettingsCubit?>()?.stream.listen((settings) {
      if (settings.offlineOnlyMode && _tab == 2 && mounted) {
        setState(() => _tab = 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppConfig.ytmEnabled && _tab != 1) _tab = 1;

    String? q;
    try {
      q = GoRouterState.of(context).uri.queryParameters['q'];
    } catch (_) {
      q = null;
    }
    if (q != null && q.trim().isNotEmpty && q != _lastAppliedQueryParam) {
      _lastAppliedQueryParam = q;
      _prefill(q);
    }
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _suggestTimer?.cancel();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── Provider helpers ────────────────────────────────────────────────
  bool _isOnlineAvailable({bool listen = true}) {
    final settings = listen
        ? context.watch<SettingsCubit?>()
        : context.read<SettingsCubit?>();
    return AppConfig.ytmEnabled && !(settings?.state.offlineOnlyMode ?? false);
  }

  int _effectiveTab({bool listen = true}) =>
      _isOnlineAvailable(listen: listen) ? _tab : 1;

  // ── Query handling ──────────────────────────────────────────────────
  void _prefill(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _text = q;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dispatchQuery(q, immediate: true);
    });
  }

  void _dispatchQuery(String value, {bool immediate = false}) {
    final online = _isOnlineAvailable(listen: false);
    final tab = _effectiveTab(listen: false);

    if (tab == 0 || tab == 1) {
      context.read<SearchCubit>().onQueryChanged(value, immediate: immediate);
    }
    if ((tab == 0 || tab == 2) && online) {
      context.read<YtmSearchCubit?>()?.onQueryChanged(value);
    }

    if (!immediate && (tab == 0 || tab == 1)) {
      _scheduleSuggestions(value);
    } else {
      _hideSuggestions();
    }
  }

  void _onChanged(String value) {
    setState(() => _text = value);
    _dispatchQuery(value);
  }

  void _onSubmitted(String value) {
    _focus.unfocus();
    _hideSuggestions();
    if (value.trim().isEmpty) return;
    _dispatchQuery(value, immediate: true);
    if (_effectiveTab(listen: false) != 2) {
      context.read<SearchCubit>().commitQuery(value);
    }
  }

  void _scheduleSuggestions(String value) {
    _suggestTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _hideSuggestions();
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      final results = await context.read<SearchCubit>().suggestionsFor(trimmed);
      if (!mounted || _controller.text.trim() != trimmed) return;
      setState(() {
        _suggestions = results;
        _showSuggestions = _focus.hasFocus && results.isNotEmpty;
      });
    });
  }

  void _hideSuggestions() {
    _suggestTimer?.cancel();
    if (_showSuggestions || _suggestions.isNotEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions = const [];
      });
    }
  }

  void _onFocusChanged() {
    final focused = _focus.hasFocus;
    if (_hasFocus != focused || (!focused && _showSuggestions)) {
      setState(() {
        _hasFocus = focused;
        if (!focused) _showSuggestions = false;
      });
    }
  }

  /// Populates the search box with [term] without unfocusing so the user can
  /// keep refining their query.
  void _fillQueryOnly(String term) {
    PulsrHaptics.selectionClick();
    final next = '$term ';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _text = next);
    _focus.requestFocus();
    _dispatchQuery(next);
  }

  /// Runs [term] immediately. [commit] stores it in recent searches.
  void _applySearch(String term, {bool commit = true}) {
    PulsrHaptics.selectionClick();
    _controller.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    setState(() => _text = term);
    _hideSuggestions();
    _focus.unfocus();
    _dispatchQuery(term, immediate: true);
    if (commit && _effectiveTab(listen: false) != 2) {
      context.read<SearchCubit>().commitQuery(term);
    }
  }

  void _applySavedSearch(String entry) {
    PulsrHaptics.selectionClick();
    final d = SearchCubit.decodeSavedSearch(entry);
    _controller.value = TextEditingValue(
      text: d.query,
      selection: TextSelection.collapsed(offset: d.query.length),
    );
    setState(() => _text = d.query);
    _hideSuggestions();
    _focus.unfocus();
    context.read<SearchCubit>().applySavedSearch(d.query, d.filter);
    if (_effectiveTab(listen: false) == 0) {
      context.read<YtmSearchCubit?>()?.onQueryChanged(d.query);
    }
  }

  void _clear() {
    PulsrHaptics.lightImpact();
    _controller.clear();
    _lastAppliedQueryParam = null;
    _hideSuggestions();
    setState(() => _text = '');
    context.read<SearchCubit>().clearQuery();
    if (_isOnlineAvailable(listen: false)) {
      context.read<YtmSearchCubit?>()?.clearQuery();
    }
    _focus.requestFocus();
  }

  void _onTabChanged(int index) {
    if (_tab == index) return;
    PulsrHaptics.selectionClick();
    setState(() => _tab = index);
    _hideSuggestions();
    if (_text.trim().isNotEmpty) _dispatchQuery(_text, immediate: true);
  }

  void _openArtist(String name) {
    try {
      final lib = context.read<LibraryCubit>().state.artists;
      final match = lib.cast<dynamic>().firstWhere(
          (a) => (a?.name as String?)?.toLowerCase() == name.toLowerCase(),
          orElse: () => null);
      if (match != null) {
        context.push('/artist?id=${match.id}', extra: match);
        return;
      }
    } catch (_) {
      // Fallback to search query when LibraryCubit or GoRouter is unavailable.
    }
    context.read<SearchCubit>().applySavedSearch(name, 'Artists');
    _controller.text = name;
    setState(() => _text = name);
  }

  void _openAlbum(String name) {
    try {
      final lib = context.read<LibraryCubit>().state.albums;
      final match = lib.cast<dynamic>().firstWhere(
          (a) => (a?.title as String?)?.toLowerCase() == name.toLowerCase(),
          orElse: () => null);
      if (match != null) {
        context.push('/album?id=${match.id}', extra: match);
        return;
      }
    } catch (_) {
      // Fallback to search query when LibraryCubit or GoRouter is unavailable.
    }
    context.read<SearchCubit>().applySavedSearch(name, 'Albums');
    _controller.text = name;
    setState(() => _text = name);
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final showOnline = _isOnlineAvailable();
    final tab = _effectiveTab();
    final pad = Adaptive.pagePadding(context);
    final compactHeader = _hasFocus || _text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!context.motionEnabled)
                  (compactHeader
                      ? const SizedBox(height: AppSpacing.xs)
                      : PulsrArtworkHeader(
                          height: 92,
                          title: context.l10n.search,
                          albumIds: context.select<PlayerCubit, List<int>>(
                            (c) => [
                              for (final song in c.state.queueHistory.take(4))
                                if (song.albumId != null) song.albumId!,
                            ],
                          ),
                        ))
                else
                  AnimatedSize(
                    duration: context.motion(PulsrMotion.state),
                    curve: context.motionCurve(PulsrMotion.enter),
                    alignment: Alignment.topCenter,
                    child: compactHeader
                        ? const SizedBox(height: AppSpacing.xs)
                        : PulsrArtworkHeader(
                            height: 92,
                            title: context.l10n.search,
                            albumIds: context.select<PlayerCubit, List<int>>(
                              (c) => [
                                for (final song in c.state.queueHistory.take(4))
                                  if (song.albumId != null) song.albumId!,
                              ],
                            ),
                          ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: _buildSearchField(context, p, tab),
                ),
                _buildProgressBar(p, tab),
                if (showOnline) ...[
                  const SizedBox(height: AppSpacing.xs),
                  PulsrSegmentedControl(
                    margin: EdgeInsets.symmetric(horizontal: pad),
                    selectedIndex: _tab,
                    onChanged: _onTabChanged,
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
                if (tab != 2) _buildFilterBar(p, pad),
                Expanded(child: _buildBody(context, p, showOnline, tab)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, PulsrPalette p, int tab) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadii.r16All,
          borderSide: BorderSide(color: c, width: w),
        );

    return AnimatedContainer(
      duration: context.motion(PulsrMotion.state),
      decoration: BoxDecoration(
        borderRadius: AppRadii.r16All,
        boxShadow: _hasFocus
            ? [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.12),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: AppFontSize.body,
          fontWeight: FontWeight.w600,
        ),
        onChanged: _onChanged,
        onSubmitted: _onSubmitted,
        decoration: InputDecoration(
          hintText: tab == 2
              ? context.l10n.searchOnline
              : tab == 1
                  ? context.l10n.searchPlaceholder
                  : context.l10n.searchLocalOnlineHint,
          hintStyle: TextStyle(
            color: p.textTertiary,
            fontSize: AppFontSize.body,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: p.surfaceContainer,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: border(p.hairline),
          enabledBorder: border(p.hairline),
          focusedBorder: border(p.accent, 1.5),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _hasFocus ? p.accent : p.textTertiary,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, val, _) {
              if (val.text.isEmpty) {
                if (!AppConfig.voiceSearchEnabled) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: Icon(Icons.mic_rounded, color: p.textTertiary),
                  tooltip: context.l10n.voiceSearch,
                  onPressed: () {
                    PulsrHaptics.lightImpact();
                    PulsrToast.show(
                      context,
                      message: context.l10n.voiceSearchUnavailable,
                      icon: Icons.mic_rounded,
                    );
                  },
                );
              }
              return IconButton(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                icon: Icon(Icons.cancel_rounded, color: p.textSecondary),
                tooltip: context.l10n.clear,
                onPressed: _clear,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(PulsrPalette p, int tab) {
    return BlocBuilder<SearchCubit, SearchState>(
      buildWhen: (a, b) => a.isLoading != b.isLoading,
      builder: (context, state) {
        final active = tab != 2 && state.isLoading && _text.trim().isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: SizedBox(
            height: 2,
            child: active
                ? PulsrProgressBar.indeterminate(
                    height: 2,
                    color: p.accent,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(PulsrPalette p, double pad) {
    return BlocBuilder<SearchCubit, SearchState>(
      buildWhen: (a, b) =>
          a.selectedFilter != b.selectedFilter || a.query != b.query,
      builder: (context, state) {
        final cubit = context.read<SearchCubit>();
        return SizedBox(
          height: AppSpacing.minTouchTarget + (AppSpacing.xs * 2),
          child: PulsrScrollEdgeFade(
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: pad,
                vertical: AppSpacing.xs,
              ),
              children: [
                for (final filter in SearchCubit.filterOptions)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                    child: _buildChip(context, state, filter, p),
                  ),
                if (state.query.trim().isNotEmpty)
                  ValueListenableBuilder<List<String>>(
                    valueListenable: cubit.savedSearches,
                    builder: (context, _, __) {
                      final saved =
                          cubit.isSaved(state.query, state.selectedFilter);
                      return PulsrChip(
                        icon: saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_add_outlined,
                        label: context.l10n.saveSearch,
                        variant: PulsrChipVariant.action,
                        onTap: () {
                          PulsrHaptics.selectionClick();
                          if (saved) {
                            cubit.removeSavedSearch(
                              SearchCubit.encodeSavedSearch(
                                state.query.trim(),
                                state.selectedFilter,
                              ),
                            );
                          } else {
                            cubit.saveCurrentSearch();
                          }
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChip(
      BuildContext context, SearchState state, String filter, PulsrPalette p) {
    final selected = state.selectedFilter == filter;
    return PulsrChip(
      label: _filterLabel(context, filter),
      selected: selected,
      variant: PulsrChipVariant.filter,
      onTap: () {
        PulsrHaptics.selectionClick();
        context.read<SearchCubit>().setFilter(filter);
      },
    );
  }

  String _filterLabel(BuildContext context, String filter) {
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

  Widget _buildBody(
      BuildContext context, PulsrPalette p, bool showOnline, int tab) {
    final text = _text.trim();
    final Widget content;

    if (text.isEmpty) {
      content = BlocBuilder<SearchCubit, SearchState>(
        buildWhen: (a, b) => a.history != b.history,
        builder: (context, state) => _StartPage(
          history: state.history,
          showOnline: showOnline,
          tab: tab,
          onRecent: _applySearch,
          onFillQuery: _fillQueryOnly,
          onTag: (t) => _applySearch(t, commit: false),
          onSaved: _applySavedSearch,
        ),
      );
    } else if (showOnline && tab == 0) {
      content = _UnifiedSearchResults(
        query: text,
        onClear: _clear,
        onCommit: () => context.read<SearchCubit>().commitQuery(text),
        onOpenArtist: _openArtist,
        onOpenAlbum: _openAlbum,
      );
    } else if (showOnline && tab == 2) {
      content = _OnlineResults(onSelectTag: (t) => _applySearch(t));
    } else {
      content = BlocBuilder<SearchCubit, SearchState>(
        builder: (context, state) => _LocalResults(
          state: state,
          onClear: _clear,
          onOpenArtist: _openArtist,
          onOpenAlbum: _openAlbum,
        ),
      );
    }

    final showCard =
        _showSuggestions && _suggestions.isNotEmpty && text.isNotEmpty;
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (showCard)
          PositionedDirectional(
            top: AppSpacing.xxs,
            start: Adaptive.pagePadding(context),
            end: Adaptive.pagePadding(context),
            child: _SuggestionsCard(
              query: text,
              suggestions: _suggestions,
              onSelect: (s) => _applySearch(s),
              onFill: _fillQueryOnly,
            ),
          ),
      ],
    );
  }
}

// ==================== SUGGESTIONS OVERLAY ====================
class _SuggestionsCard extends StatelessWidget {
  final String query;
  final List<String> suggestions;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onFill;

  const _SuggestionsCard({
    required this.query,
    required this.suggestions,
    required this.onSelect,
    required this.onFill,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final baseStyle = TextStyle(
      color: p.textPrimary,
      fontSize: AppFontSize.body,
      fontWeight: FontWeight.w500,
    );
    final matchStyle = TextStyle(
      color: p.accent,
      fontSize: AppFontSize.body,
      fontWeight: FontWeight.w800,
    );

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.accent.withValues(alpha: 0.28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < suggestions.length; i++) ...[
              if (i > 0) Divider(color: p.hairline, height: 1),
              InkWell(
                onTap: () => onSelect(suggestions[i]),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.sm,
                    end: AppSpacing.xxs,
                    top: AppSpacing.xxs,
                    bottom: AppSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: p.textTertiary,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: PulsrHighlightedText(
                          text: suggestions[i],
                          query: query,
                          baseStyle: baseStyle,
                          matchStyle: matchStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.north_west_rounded,
                          size: 17,
                          color: p.textTertiary,
                        ),
                        onPressed: () => onFill(suggestions[i]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== START PAGE (empty query) ====================
class _StartPage extends StatelessWidget {
  final List<String> history;
  final bool showOnline;
  final int tab;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onFillQuery;
  final ValueChanged<String> onTag;
  final ValueChanged<String> onSaved;

  const _StartPage({
    required this.history,
    required this.showOnline,
    required this.tab,
    required this.onRecent,
    required this.onFillQuery,
    required this.onTag,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ytm = showOnline ? context.read<YtmSearchCubit?>() : null;
    final local = context.read<SearchCubit>();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsetsDirectional.fromSTEB(
        Adaptive.pagePadding(context),
        AppSpacing.sm,
        Adaptive.pagePadding(context),
        PulsrLayoutMetrics.scrollBottom(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRecentSearchesSection(context, p, local, ytm),
          if (tab != 2)
            ValueListenableBuilder<List<String>>(
              valueListenable: local.savedSearches,
              builder: (context, saved, _) {
                if (saved.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitleRow(
                      icon: Icons.bookmarks_rounded,
                      title: context.l10n.savedSearches,
                      p: p,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final entry in saved)
                          _SavedSearchChip(
                            entry: entry,
                            palette: p,
                            onTap: () => onSaved(entry),
                            onDelete: () {
                              PulsrHaptics.lightImpact();
                              local.removeSavedSearch(entry);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          if (tab != 2)
            ValueListenableBuilder<List<SongsTableData>>(
              valueListenable: local.searchPlayedSongs,
              builder: (context, playedSongs, _) {
                if (playedSongs.isEmpty) return const SizedBox.shrink();
                final currentSongId = context
                    .select<PlayerCubit, int?>((c) => c.state.currentSong?.id);
                final player = context.read<PlayerCubit>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecentSectionHeader(
                      context: context,
                      icon: Icons.history_toggle_off_rounded,
                      title: context.l10n.recentlyPlayed,
                      onClear: () {
                        PulsrHaptics.lightImpact();
                        local.clearSearchPlayedSongs();
                      },
                      p: p,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.45),
                        borderRadius: AppRadii.r16All,
                        border: Border.all(color: p.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < playedSongs.take(6).length;
                              i++) ...[
                            if (i > 0)
                              Divider(
                                color: p.hairline,
                                height: 1,
                                indent: 68,
                              ),
                            _SearchPlayedSongTile(
                              song: playedSongs[i],
                              isCurrent: currentSongId == playedSongs[i].id,
                              onTap: () {
                                PulsrHaptics.selectionClick();
                                local.recordPlayedSong(playedSongs[i]);
                                player.playSong(
                                  playedSongs[i],
                                  queue: playedSongs,
                                );
                              },
                              onRemove: () => local
                                  .removeSearchPlayedSong(playedSongs[i].id),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          if (showOnline && (tab == 0 || tab == 2)) ...[
            _sectionTitleRow(
              icon: Icons.local_fire_department_rounded,
              title: context.l10n.popularSearches,
              p: p,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in _onlineTags)
                  PulsrChip(
                    icon: Icons.trending_up_rounded,
                    label: _localizedTag(context, tag),
                    variant: PulsrChipVariant.action,
                    onTap: () => onTag(tag),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentSearchesSection(
    BuildContext context,
    PulsrPalette p,
    SearchCubit local,
    YtmSearchCubit? ytm,
  ) {
    if (ytm == null) {
      if (tab == 2 || history.isEmpty) return const SizedBox.shrink();
      return _buildHistoryCard(
        context: context,
        p: p,
        terms: history.take(6).toList(),
        onClear: () {
          PulsrHaptics.lightImpact();
          local.clearHistory();
        },
        onRemove: (term) => local.removeHistoryQuery(term),
      );
    }

    return ValueListenableBuilder<List<String>>(
      valueListenable: ytm.historyNotifier,
      builder: (context, onlineHistory, _) {
        if (tab == 0) {
          final combined = <String>[];
          final seen = <String>{};
          final maxLen = history.length > onlineHistory.length
              ? history.length
              : onlineHistory.length;
          for (var i = 0; i < maxLen; i++) {
            if (i < history.length) {
              final term = history[i].trim();
              if (term.isNotEmpty && seen.add(term.toLowerCase())) {
                combined.add(history[i]);
              }
            }
            if (i < onlineHistory.length) {
              final term = onlineHistory[i].trim();
              if (term.isNotEmpty && seen.add(term.toLowerCase())) {
                combined.add(onlineHistory[i]);
              }
            }
          }
          if (combined.isEmpty) return const SizedBox.shrink();

          return _buildHistoryCard(
            context: context,
            p: p,
            terms: combined.take(6).toList(),
            onClear: () {
              PulsrHaptics.lightImpact();
              local.clearHistory();
              ytm.clearHistory();
            },
            onRemove: (term) {
              local.removeHistoryQuery(term);
              ytm.removeHistoryQuery(term);
            },
          );
        } else if (tab == 1) {
          if (history.isEmpty) return const SizedBox.shrink();
          return _buildHistoryCard(
            context: context,
            p: p,
            terms: history.take(6).toList(),
            onClear: () {
              PulsrHaptics.lightImpact();
              local.clearHistory();
            },
            onRemove: (term) => local.removeHistoryQuery(term),
          );
        } else {
          if (onlineHistory.isEmpty) return const SizedBox.shrink();
          return _buildHistoryCard(
            context: context,
            p: p,
            terms: onlineHistory.take(6).toList(),
            onClear: () {
              PulsrHaptics.lightImpact();
              ytm.clearHistory();
            },
            onRemove: (term) => ytm.removeHistoryQuery(term),
          );
        }
      },
    );
  }

  Widget _buildHistoryCard({
    required BuildContext context,
    required PulsrPalette p,
    required List<String> terms,
    required VoidCallback onClear,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRecentSectionHeader(
          context: context,
          icon: Icons.history_rounded,
          title: context.l10n.recentSearches,
          onClear: onClear,
          p: p,
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.45),
            borderRadius: AppRadii.r16All,
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < terms.length; i++) ...[
                if (i > 0) Divider(color: p.hairline, height: 1, indent: 42),
                _RecentRow(
                  icon: Icons.history_rounded,
                  term: terms[i],
                  onTap: () => onRecent(terms[i]),
                  onFill: () => onFillQuery(terms[i]),
                  onRemove: () => onRemove(terms[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _sectionTitleRow({
    required IconData icon,
    required String title,
    required PulsrPalette p,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: p.textTertiary),
        const SizedBox(width: AppSpacing.s6),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w800,
            color: p.textTertiary,
            letterSpacing: AppTracking.wide,
          ),
        ),
      ],
    );
  }
}

class _SavedSearchChip extends StatelessWidget {
  final String entry;
  final PulsrPalette palette;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedSearchChip({
    required this.entry,
    required this.palette,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final decoded = SearchCubit.decodeSavedSearch(entry);
    final hasCustomFilter =
        decoded.filter.isNotEmpty && decoded.filter != 'All';

    return Material(
      color: palette.surfaceContainer,
      borderRadius: AppRadii.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.circular(12),
        child: Container(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.s10,
            end: AppSpacing.s6,
            top: AppSpacing.s6,
            bottom: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.circular(12),
            border: Border.all(color: palette.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_rounded,
                size: 14,
                color: palette.accent,
              ),
              const SizedBox(width: AppSpacing.s6),
              Flexible(
                child: Text(
                  decoded.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasCustomFilter) ...[
                const SizedBox(width: AppSpacing.s6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: AppRadii.circular(6),
                  ),
                  child: Text(
                    decoded.filter,
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.s6),
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPlayedSongTile extends StatelessWidget {
  final SongsTableData song;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SearchPlayedSongTile({
    required this.song,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: isCurrent ? p.accent.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => SongOptionsSheet.show(context, song: song),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s6,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CachedArtwork(
                  id: song.id,
                  remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                  albumId: song.albumId,
                  type: ArtworkType.AUDIO,
                  size: 44,
                  borderRadius: 10,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? p.accent : p.textPrimary,
                        fontSize: AppFontSize.body,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 18,
                    color: p.accent,
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: p.textTertiary,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.remove,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final IconData icon;
  final String term;
  final VoidCallback onTap;
  final VoidCallback onFill;
  final VoidCallback onRemove;

  const _RecentRow({
    required this.icon,
    required this.term,
    required this.onTap,
    required this.onFill,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.sm,
            end: AppSpacing.xxs,
            top: AppSpacing.xxs,
            bottom: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: p.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.north_west_rounded,
                  size: 16,
                  color: p.textTertiary,
                ),
                onPressed: onFill,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.remove,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: p.textTertiary,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== LOCAL RESULTS ====================
class _LocalResults extends StatelessWidget {
  final SearchState state;
  final VoidCallback onClear;
  final ValueChanged<String> onOpenArtist;
  final ValueChanged<String> onOpenAlbum;

  const _LocalResults({
    required this.state,
    required this.onClear,
    required this.onOpenArtist,
    required this.onOpenAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SearchCubit>();
    final player = context.read<PlayerCubit>();
    final pending = cubit.isDebouncing;

    if ((state.isLoading || pending) && state.results.isEmpty) {
      return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
    }
    final error = state.errorMessage;
    if (error != null && state.results.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.somethingWentWrong,
        subtitle: resolveUiErrorMessage(context, error),
        primaryActionLabel: context.l10n.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: cubit.retry,
      );
    }
    if (state.results.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.search_off_rounded,
        title: context.l10n.noResultsFound,
        subtitle: '${context.l10n.noResultsSubtitle} "${state.query.trim()}"',
        primaryActionLabel: context.l10n.clearSearchQuery,
        primaryActionIcon: Icons.backspace_rounded,
        onPrimaryAction: onClear,
      );
    }

    final filter = state.selectedFilter;
    final entities = _deriveEntities(state.results);
    final artists = (filter == 'All' || filter == 'Artists')
        ? entities.artists.take(10).toList()
        : const <_DerivedEntity>[];
    final albums = (filter == 'All' || filter == 'Albums')
        ? entities.albums.take(10).toList()
        : const <_DerivedEntity>[];

    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      onRefresh: cubit.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (artists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context: context,
                icon: Icons.person_rounded,
                title: context.l10n.artists,
                count: entities.artists.length,
                isLoading: false,
                p: p,
              ),
            ),
            SliverToBoxAdapter(
              child: _EntityRail(
                entities: artists,
                query: state.query,
                round: true,
                onTap: onOpenArtist,
              ),
            ),
          ],
          if (albums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context: context,
                icon: Icons.album_rounded,
                title: context.l10n.albums,
                count: entities.albums.length,
                isLoading: false,
                p: p,
              ),
            ),
            SliverToBoxAdapter(
              child: _EntityRail(
                entities: albums,
                query: state.query,
                round: false,
                onTap: onOpenAlbum,
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              context: context,
              icon: Icons.music_note_rounded,
              title: context.l10n.songs,
              count: state.results.length,
              isLoading: state.isLoading,
              p: p,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = state.results[index];
                return HighlightedSongTile(
                  song: song,
                  query: state.query,
                  subtitleOverride: '${song.artist} • ${song.album}',
                  onTap: () {
                    cubit.commitQuery();
                    cubit.recordPlayedSong(song);
                    player.playSong(song, queue: state.results);
                  },
                  onMorePressed: () =>
                      SongOptionsSheet.show(context, song: song),
                );
              },
              childCount: state.results.length,
            ),
          ),
          SliverToBoxAdapter(
            child: ValueListenableBuilder<bool>(
              valueListenable: cubit.hasMoreResults,
              builder: (context, hasMore, _) => hasMore
                  ? _ShowMoreButton(
                      expanded: false,
                      onPressed: cubit.showMoreResults,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: PulsrLayoutMetrics.scrollBottom(context)),
          ),
        ],
      ),
    );
  }
}

class _DerivedEntity {
  final String name;
  final int songId;
  final int? albumId;
  final String? artworkUrl;

  const _DerivedEntity({
    required this.name,
    required this.songId,
    this.albumId,
    this.artworkUrl,
  });
}

({List<_DerivedEntity> artists, List<_DerivedEntity> albums}) _deriveEntities(
  List<SongsTableData> results,
) {
  final artists = <_DerivedEntity>[];
  final albums = <_DerivedEntity>[];
  final seenA = <String>{};
  final seenB = <String>{};
  for (final s in results) {
    final a = s.artist.trim();
    if (a.isNotEmpty && seenA.add(a.toLowerCase())) {
      artists.add(
        _DerivedEntity(
          name: a,
          songId: s.id,
          albumId: s.albumId,
          artworkUrl: s.remoteArtworkUrl ?? s.artworkUri,
        ),
      );
    }
    final b = s.album.trim();
    if (b.isNotEmpty && seenB.add(b.toLowerCase())) {
      albums.add(
        _DerivedEntity(
          name: b,
          songId: s.id,
          albumId: s.albumId,
          artworkUrl: s.remoteArtworkUrl ?? s.artworkUri,
        ),
      );
    }
  }
  return (artists: artists, albums: albums);
}

/// Horizontal rail of artist / album cards with representative artwork.
class _EntityRail extends StatelessWidget {
  final List<_DerivedEntity> entities;
  final String query;
  final bool round;
  final ValueChanged<String> onTap;

  const _EntityRail({
    required this.entities,
    required this.query,
    required this.round,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    return SizedBox(
      height: 124 + (scale - 1.0) * 30,
      child: PulsrScrollEdgeFade(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: Adaptive.pagePadding(context),
            vertical: AppSpacing.xxs,
          ),
          itemCount: entities.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, i) {
            final item = entities[i];
            return InkWell(
              borderRadius: AppRadii.r16All,
              onTap: () {
                PulsrHaptics.selectionClick();
                onTap(item.name);
              },
              child: Container(
                width: 88,
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.surfaceContainer.withValues(alpha: 0.55),
                  borderRadius: AppRadii.r16All,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CachedArtwork(
                        id: item.songId,
                        remoteUrl: item.artworkUrl,
                        albumId: item.albumId,
                        type: ArtworkType.AUDIO,
                        size: 56,
                        borderRadius: round ? 28 : 14,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    PulsrHighlightedText(
                      text: item.name,
                      query: query,
                      baseStyle: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                      ),
                      matchStyle: TextStyle(
                        color: p.accent,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== UNIFIED SEARCH RESULTS ====================
class _UnifiedSearchResults extends StatefulWidget {
  final String query;
  final VoidCallback onClear;
  final VoidCallback onCommit;
  final ValueChanged<String> onOpenArtist;
  final ValueChanged<String> onOpenAlbum;

  const _UnifiedSearchResults({
    required this.query,
    required this.onClear,
    required this.onCommit,
    required this.onOpenArtist,
    required this.onOpenAlbum,
  });

  @override
  State<_UnifiedSearchResults> createState() => _UnifiedSearchResultsState();
}

class _UnifiedSearchResultsState extends State<_UnifiedSearchResults> {
  static const int _localPreview = 5;
  static const int _onlinePreview = 10;
  bool _expandLocal = false;
  bool _expandOnline = false;

  @override
  void didUpdateWidget(covariant _UnifiedSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _expandLocal = false;
      _expandOnline = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final player = context.read<PlayerCubit>();
    final isOffline =
        context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;

    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, local) {
        return BlocBuilder<YtmSearchCubit, YtmSearchState>(
          builder: (context, ytm) {
            final localPending = context.read<SearchCubit>().isDebouncing;
            final onlinePending = context.read<YtmSearchCubit>().isDebouncing;
            final localDone = !local.isLoading && !localPending;
            final onlineDone = isOffline || (!ytm.isLoading && !onlinePending);
            final onlineEmpty = isOffline ||
                (ytm.results.isEmpty && ytm.hasSearched && !onlinePending);

            if (localDone &&
                onlineDone &&
                local.results.isEmpty &&
                onlineEmpty &&
                ytm.errorMessage == null &&
                local.errorMessage == null) {
              return PulsrEmptyState(
                icon: Icons.search_off_rounded,
                title: context.l10n.noResultsFound,
                subtitle: '${context.l10n.noResultsSubtitle} "${widget.query}"',
                primaryActionLabel: context.l10n.clearSearchQuery,
                primaryActionIcon: Icons.backspace_rounded,
                onPrimaryAction: widget.onClear,
              );
            }

            final localSongs = local.results;
            final localShown = _expandLocal
                ? localSongs
                : localSongs.take(_localPreview).toList();
            final onlineTracks = ytm.results;
            final onlineSongs = [for (final t in onlineTracks) t.toSongData()];
            final onlineShown = _expandOnline
                ? onlineSongs.length
                : onlineSongs.length.clamp(0, _onlinePreview);

            final filter = local.selectedFilter;
            final entities = _deriveEntities(localSongs);
            final artists = (filter == 'All' || filter == 'Artists')
                ? entities.artists.take(8).toList()
                : const <_DerivedEntity>[];
            final albums = (filter == 'All' || filter == 'Albums')
                ? entities.albums.take(8).toList()
                : const <_DerivedEntity>[];

            return RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              onRefresh: () async {
                if (!isOffline) {
                  context.read<YtmSearchCubit>().onQueryChanged(widget.query);
                }
                await context.read<SearchCubit>().refresh();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  bottom: PulsrLayoutMetrics.scrollBottom(context),
                  top: AppSpacing.xxs,
                ),
                children: [
                  if (artists.isNotEmpty) ...[
                    _buildSectionHeader(
                      context: context,
                      icon: Icons.person_rounded,
                      title: context.l10n.artists,
                      count: entities.artists.length,
                      isLoading: false,
                      p: p,
                    ),
                    _EntityRail(
                      entities: artists,
                      query: widget.query,
                      round: true,
                      onTap: widget.onOpenArtist,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (albums.isNotEmpty) ...[
                    _buildSectionHeader(
                      context: context,
                      icon: Icons.album_rounded,
                      title: context.l10n.albums,
                      count: entities.albums.length,
                      isLoading: false,
                      p: p,
                    ),
                    _EntityRail(
                      entities: albums,
                      query: widget.query,
                      round: false,
                      onTap: widget.onOpenAlbum,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  _buildSectionHeader(
                    context: context,
                    icon: Icons.library_music_rounded,
                    title: context.l10n.localMusic,
                    count: localSongs.length,
                    isLoading: local.isLoading,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  if (local.errorMessage != null && localSongs.isEmpty)
                    _buildErrorSectionCard(
                      context: context,
                      errorMessage:
                          resolveUiErrorMessage(context, local.errorMessage!),
                      onRetry: context.read<SearchCubit>().retry,
                      p: p,
                    )
                  else if ((local.isLoading || localPending) &&
                      localSongs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SkeletonList(itemCount: 3),
                    )
                  else if (localSongs.isEmpty && !localPending)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.library_music_outlined,
                      message: context.l10n.noLocalSongsMatch(widget.query),
                      p: p,
                    )
                  else ...[
                    for (final song in localShown)
                      HighlightedSongTile(
                        song: song,
                        query: widget.query,
                        subtitleOverride: '${song.artist} • ${song.album}',
                        onTap: () {
                          widget.onCommit();
                          context.read<SearchCubit>().recordPlayedSong(song);
                          player.playSong(song, queue: localSongs);
                        },
                        onMorePressed: () =>
                            SongOptionsSheet.show(context, song: song),
                      ),
                    if (localSongs.length > _localPreview)
                      _ShowMoreButton(
                        expanded: _expandLocal,
                        onPressed: () =>
                            setState(() => _expandLocal = !_expandLocal),
                      ),
                    if (_expandLocal)
                      ValueListenableBuilder<bool>(
                        valueListenable:
                            context.read<SearchCubit>().hasMoreResults,
                        builder: (context, hasMore, _) => hasMore
                            ? _ShowMoreButton(
                                expanded: false,
                                onPressed: () => context
                                    .read<SearchCubit>()
                                    .showMoreResults(),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Divider(color: p.hairline, height: 1),
                  ),
                  _buildSectionHeader(
                    context: context,
                    icon: Icons.public_rounded,
                    title: context.l10n.onlineStream,
                    count: onlineTracks.length,
                    isLoading: ytm.isLoading,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  if (isOffline)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.wifi_off_rounded,
                      message: context.l10n.offlineOnlyMode,
                      p: p,
                    )
                  else if ((ytm.isLoading || onlinePending) &&
                      onlineTracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SkeletonList(itemCount: 4),
                    )
                  else if (ytm.errorMessage != null)
                    _buildErrorSectionCard(
                      context: context,
                      errorMessage:
                          resolveUiErrorMessage(context, ytm.errorMessage!),
                      onRetry: context.read<YtmSearchCubit>().retry,
                      p: p,
                    )
                  else if (onlineTracks.isEmpty &&
                      ytm.hasSearched &&
                      !onlinePending)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.search_off_rounded,
                      message: context.l10n.noOnlineSongsMatch(widget.query),
                      p: p,
                    )
                  else ...[
                    for (var i = 0; i < onlineShown; i++)
                      HighlightedSongTile(
                        song: onlineSongs[i],
                        query: widget.query,
                        subtitleOverride: onlineTracks[i].artist,
                        onTap: () {
                          context
                              .read<SearchCubit>()
                              .recordPlayedSong(onlineSongs[i]);
                          player.playSong(onlineSongs[i], queue: onlineSongs);
                        },
                        onLongPress: () => SongOptionsSheet.show(
                          context,
                          song: onlineSongs[i],
                        ),
                        trailing: YtmDownloadButton(song: onlineSongs[i]),
                      ),
                    if (onlineSongs.length > _onlinePreview)
                      _ShowMoreButton(
                        expanded: _expandOnline,
                        onPressed: () =>
                            setState(() => _expandOnline = !_expandOnline),
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

class _ShowMoreButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onPressed;

  const _ShowMoreButton({required this.expanded, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Material(
          color: p.surfaceContainer,
          borderRadius: AppRadii.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              PulsrHaptics.selectionClick();
              onPressed();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.s6,
              ),
              decoration: BoxDecoration(
                borderRadius: AppRadii.circular(20),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: p.accent,
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    expanded ? context.l10n.showLess : context.l10n.showMore,
                    style: TextStyle(
                      color: p.accent,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== SHARED SECTION WIDGETS ====================
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
      vertical: AppSpacing.xs,
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.14),
            borderRadius: AppRadii.circular(8),
          ),
          child: Icon(icon, size: 16, color: p.accent),
        ),
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
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s2,
            ),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r12All,
              border: Border.all(color: p.hairline),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w700,
                color: p.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    ),
  );
}

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
      borderRadius: AppRadii.r12All,
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
      borderRadius: AppRadii.r12All,
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

Widget _buildRecentSectionHeader({
  required BuildContext context,
  required IconData icon,
  required String title,
  required VoidCallback onClear,
  required PulsrPalette p,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            children: [
              Icon(icon, size: 14, color: p.textTertiary),
              const SizedBox(width: AppSpacing.s6),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.wide,
                    color: p.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onClear,
          child: Text(
            context.l10n.clear,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w700,
              color: p.accent,
            ),
          ),
        ),
      ],
    ),
  );
}

// ==================== ONLINE TAB ====================
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

        final pending = context.read<YtmSearchCubit>().isDebouncing;

        if ((state.isLoading || pending) && state.results.isEmpty) {
          return const SkeletonList(
            padding: EdgeInsets.only(top: AppSpacing.xs),
          );
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
          if (state.hasSearched && !pending) {
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
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.travel_explore_rounded,
                      size: 32,
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.searchYtm,
                    style: TextStyle(
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    context.l10n.ytmSearchDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.bodySmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final tag in _onlineTags)
                        PulsrChip(
                          icon: Icons.trending_up_rounded,
                          label: _localizedTag(context, tag),
                          variant: PulsrChipVariant.action,
                          onTap: () => onSelectTag?.call(tag),
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
              parent: BouncingScrollPhysics(),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            padding: EdgeInsets.only(
              bottom: PulsrLayoutMetrics.scrollBottom(context),
              top: AppSpacing.xxs,
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return HighlightedSongTile(
                song: song,
                query: state.query,
                subtitleOverride: state.results[index].artist,
                onTap: () {
                  context.read<SearchCubit>().recordPlayedSong(song);
                  playerCubit.playSong(song, queue: songs);
                },
                onLongPress: () => SongOptionsSheet.show(context, song: song),
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