import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
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

const List<String> _localTags = [
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
];

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
///
/// BUG FIX: the old State owned both the providers and the handlers, so its
/// own `context` was above the YtmSearchCubit provider. Deep-link / initial
/// queries therefore read a null online cubit and never searched online.
class SearchScreen extends StatelessWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  Widget build(BuildContext context) {
    final view = _SearchView(initialQuery: initialQuery);
    if (!AppConfig.ytmEnabled) return view;
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

  /// Mirrors the text field. BUG FIX: the body used to read
  /// `_controller.text` during a SearchCubit-driven rebuild, so on the Online
  /// tab (which never touches SearchCubit) typing did not switch the body
  /// away from the start page.
  String _text = '';

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

    // Assistant / deep-link entry: `/search?q=...`
    String? q;
    try {
      q = GoRouterState.of(context).uri.queryParameters['q'];
    } catch (_) {}
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
  /// Sets the text and runs the query after the first frame (used for deep
  /// links before the tree is fully built).
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
    _suggestTimer = Timer(const Duration(milliseconds: 200), () async {
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
    if (!_focus.hasFocus && _showSuggestions) {
      setState(() => _showSuggestions = false);
    }
  }

  /// Runs [term] right now. [commit] stores it in the recent searches (not for
  /// discovery tags, which the user did not type).
  void _applySearch(String term, {bool commit = true}) {
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

  /// BUG FIX: applying a saved search used to call `setFilter` first, which
  /// searched the *old* query with the new filter, and it never reached the
  /// online cubit in the All tab.
  void _applySavedSearch(String entry) {
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
        context.push('/artist', extra: match);
        return;
      }
    } catch (_) {}
    // Not in the library: search for the name, restricted to artists.
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
        context.push('/album', extra: match);
        return;
      }
    } catch (_) {}
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(pad, 16, pad, 0),
                  child: Text(
                    context.l10n.search,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (showOnline) ...[
                  const SizedBox(height: AppSpacing.s14),
                  PulsrSegmentedControl(
                    margin: EdgeInsets.symmetric(horizontal: pad),
                    selectedIndex: _tab,
                    onChanged: _onTabChanged,
                    segments: [
                      PulsrSegment(
                          label: context.l10n.all,
                          icon: Icons.dashboard_rounded),
                      PulsrSegment(
                          label: context.l10n.localMusic,
                          icon: Icons.library_music_rounded),
                      PulsrSegment(
                          label: context.l10n.onlineStream,
                          icon: Icons.public_rounded),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: _buildSearchField(context, p, tab),
                ),
                _buildProgressBar(p, tab),
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
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    return TextField(
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onChanged: _onChanged,
      onSubmitted: _onSubmitted,
      decoration: InputDecoration(
        hintText: tab == 2
            ? context.l10n.searchOnline
            : tab == 1
                ? context.l10n.searchPlaceholder
                : context.l10n.searchLocalOnlineHint,
        filled: true,
        fillColor: p.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: border(p.hairline),
        enabledBorder: border(p.hairline),
        focusedBorder: border(p.accent, 1.5),
        prefixIcon: Icon(Icons.search_rounded, color: p.textTertiary),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, val, _) {
            if (val.text.isEmpty) {
              if (!AppConfig.voiceSearchEnabled) return const SizedBox.shrink();
              return IconButton(
                constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget),
                icon: Icon(Icons.mic_rounded, color: p.textTertiary),
                tooltip: context.l10n.voiceSearch,
                onPressed: () {
                  HapticFeedback.lightImpact();
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
                  minHeight: AppSpacing.minTouchTarget),
              icon: Icon(Icons.clear_rounded, color: p.textTertiary),
              tooltip: context.l10n.clear,
              onPressed: _clear,
            );
          },
        ),
      ),
    );
  }

  /// Thin loading line under the field: results stay visible while a new
  /// query loads, so there is no skeleton flicker per keystroke.
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
                ? LinearProgressIndicator(
                    minHeight: 2,
                    color: p.accent,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
        );
      },
    );
  }

  /// BUG FIX: filter chips were shown on the Local tab only, but the persisted
  /// filter was also applied to the local section of the All tab, silently
  /// hiding results (e.g. a leftover "FLAC") with no visible control.
  Widget _buildFilterBar(PulsrPalette p, double pad) {
    return BlocBuilder<SearchCubit, SearchState>(
      buildWhen: (a, b) =>
          a.selectedFilter != b.selectedFilter || a.query != b.query,
      builder: (context, state) {
        final cubit = context.read<SearchCubit>();
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding:
                EdgeInsets.symmetric(horizontal: pad, vertical: AppSpacing.xs),
            children: [
              for (final filter in SearchCubit.filterOptions)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: _buildChip(context, state, filter, p),
                ),
              if (state.query.trim().isNotEmpty)
                ValueListenableBuilder<List<String>>(
                  valueListenable: cubit.savedSearches,
                  builder: (context, _, __) {
                    final saved =
                        cubit.isSaved(state.query, state.selectedFilter);
                    return ActionChip(
                      avatar: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_add_outlined,
                        size: 16,
                        color: p.accent,
                      ),
                      label: Text(context.l10n.saveSearch),
                      backgroundColor: p.surfaceContainer,
                      side: BorderSide(color: p.hairline),
                      labelStyle: TextStyle(
                          color: p.accent,
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        if (saved) {
                          cubit.removeSavedSearch(SearchCubit.encodeSavedSearch(
                              state.query.trim(), state.selectedFilter));
                        } else {
                          cubit.saveCurrentSearch();
                        }
                      },
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip(
      BuildContext context, SearchState state, String filter, PulsrPalette p) {
    final selected = state.selectedFilter == filter;
    return ChoiceChip(
      label: Text(_filterLabel(context, filter)),
      selected: selected,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? p.accent : p.textSecondary,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      onSelected: (_) {
        HapticFeedback.selectionClick();
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
          onTag: (t) => _applySearch(t, commit: false),
          onSaved: _applySavedSearch,
        ),
      );
    } else if (showOnline && tab == 0) {
      content = _UnifiedSearchResults(
        query: text,
        onClear: _clear,
        onCommit: () => context.read<SearchCubit>().commitQuery(text),
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
            top: 0,
            start: Adaptive.pagePadding(context),
            end: Adaptive.pagePadding(context),
            child: _SuggestionsCard(
              suggestions: _suggestions,
              onSelect: (s) => _applySearch(s),
            ),
          ),
      ],
    );
  }
}

// ==================== SUGGESTIONS OVERLAY ====================
/// BUG FIX: suggestions used to *replace* the results list whenever any
/// prefix matched, so results were effectively unreachable while typing.
/// They are now a compact card floating above the results.
class _SuggestionsCard extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  const _SuggestionsCard({required this.suggestions, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surfaceContainer,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < suggestions.length; i++) ...[
            if (i > 0) Divider(color: p.hairline, height: 1),
            ListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              leading:
                  Icon(Icons.search_rounded, color: p.textTertiary, size: 20),
              title: Text(
                suggestions[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w500),
              ),
              trailing: Icon(Icons.north_west_rounded,
                  size: 16, color: p.textTertiary),
              onTap: () => onSelect(suggestions[i]),
            ),
          ],
        ],
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
  final ValueChanged<String> onTag;
  final ValueChanged<String> onSaved;

  const _StartPage({
    required this.history,
    required this.showOnline,
    required this.tab,
    required this.onRecent,
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
          PulsrLayoutMetrics.scrollBottom(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((tab == 0 || tab == 1) && history.isNotEmpty) ...[
            _buildRecentSectionHeader(
              context: context,
              icon: Icons.history_rounded,
              title:
                  '${context.l10n.recentSearches} • ${context.l10n.localMusic}',
              onClear: () {
                HapticFeedback.lightImpact();
                local.clearHistory();
              },
              p: p,
            ),
            for (final term in history.take(5))
              _RecentRow(
                icon: Icons.history_rounded,
                term: term,
                onTap: () => onRecent(term),
                onRemove: () => local.removeHistoryQuery(term),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (ytm != null && (tab == 0 || tab == 2))
            ValueListenableBuilder<List<String>>(
              valueListenable: ytm.historyNotifier,
              builder: (context, online, _) {
                if (online.isEmpty) return const SizedBox.shrink();
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
                        ytm.clearHistory();
                      },
                      p: p,
                    ),
                    for (final term in online.take(5))
                      _RecentRow(
                        icon: Icons.public_rounded,
                        term: term,
                        onTap: () => onRecent(term),
                        onRemove: () => ytm.removeHistoryQuery(term),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          // Saved searches are local-only, so hide them on the Online tab
          // (applying one there changed nothing visible).
          if (tab != 2)
            ValueListenableBuilder<List<String>>(
              valueListenable: local.savedSearches,
              builder: (context, saved, _) {
                if (saved.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context.l10n.savedSearches, p),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        for (final entry in saved)
                          InputChip(
                            avatar: Icon(Icons.bookmark_outline_rounded,
                                size: 14, color: p.accent),
                            label: Text(
                                SearchCubit.decodeSavedSearch(entry).query),
                            backgroundColor: p.surfaceContainer,
                            side: BorderSide(color: p.hairline),
                            deleteIcon:
                                const Icon(Icons.close_rounded, size: 14),
                            deleteIconColor: p.textTertiary,
                            labelStyle: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600),
                            onDeleted: () => local.removeSavedSearch(entry),
                            onPressed: () => onSaved(entry),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                );
              },
            ),
          _label(
              tab == 2
                  ? context.l10n.popularSearches
                  : context.l10n.quickDiscovery,
              p),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final tag in tab == 2 ? _onlineTags : _localTags)
                ActionChip(
                  label: Text(_localizedTag(context, tag)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  labelStyle: TextStyle(
                      color: p.accent,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700),
                  onPressed: () => onTag(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text, PulsrPalette p) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.w800,
          color: p.textTertiary,
          letterSpacing: AppTracking.wide,
        ),
      );
}

class _RecentRow extends StatelessWidget {
  final IconData icon;
  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentRow({
    required this.icon,
    required this.term,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
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
                    fontWeight: FontWeight.w500),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
              onPressed: onRemove,
            ),
          ],
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

    if (state.isLoading && state.results.isEmpty) {
      return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
    }
    final error = state.errorMessage;
    if (error != null && state.results.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.somethingWentWrong,
        // BUG FIX: the raw failure text was shown; the online tab already
        // resolved it to a localized message.
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
    final names = _deriveNames(state.results);
    final artists = (filter == 'All' || filter == 'Artists')
        ? names.artists.take(10).toList()
        : const <String>[];
    final albums = (filter == 'All' || filter == 'Albums')
        ? names.albums.take(10).toList()
        : const <String>[];

    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      onRefresh: cubit.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (artists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context: context,
                icon: Icons.person_rounded,
                title: context.l10n.artists,
                count: names.artists.length,
                isLoading: false,
                p: p,
              ),
            ),
            SliverToBoxAdapter(
              child: _EntityRail(
                names: artists,
                icon: Icons.person_rounded,
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
                count: names.albums.length,
                isLoading: false,
                p: p,
              ),
            ),
            SliverToBoxAdapter(
              child: _EntityRail(
                names: albums,
                icon: Icons.album_rounded,
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
                return SongTile(
                  song: song,
                  subtitleOverride: '${song.artist} • ${song.album}',
                  onTap: () {
                    cubit.commitQuery();
                    player.playSong(song, queue: state.results);
                  },
                  onMorePressed: () => SongInfoSheet.show(context, song: song),
                );
              },
              childCount: state.results.length,
            ),
          ),
          SliverToBoxAdapter(
              child:
                  SizedBox(height: PulsrLayoutMetrics.scrollBottom(context))),
        ],
      ),
    );
  }
}

({List<String> artists, List<String> albums}) _deriveNames(
    List<SongsTableData> results) {
  final artists = <String>[];
  final albums = <String>[];
  final seenA = <String>{};
  final seenB = <String>{};
  for (final s in results) {
    final a = s.artist.trim();
    if (a.isNotEmpty && seenA.add(a.toLowerCase())) artists.add(a);
    final b = s.album.trim();
    if (b.isNotEmpty && seenB.add(b.toLowerCase())) albums.add(b);
  }
  return (artists: artists, albums: albums);
}

/// Horizontal rail of artist / album cards.
class _EntityRail extends StatelessWidget {
  final List<String> names;
  final IconData icon;
  final bool round;
  final ValueChanged<String> onTap;

  const _EntityRail({
    required this.names,
    required this.icon,
    required this.round,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
            horizontal: Adaptive.pagePadding(context),
            vertical: AppSpacing.xxs),
        itemCount: names.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final name = names[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(name),
            child: SizedBox(
              width: 76,
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      shape: round ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: round ? null : BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: p.accent, size: 26),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==================== UNIFIED SEARCH RESULTS ====================
class _UnifiedSearchResults extends StatefulWidget {
  final String query;
  final VoidCallback onClear;
  final VoidCallback onCommit;

  const _UnifiedSearchResults({
    required this.query,
    required this.onClear,
    required this.onCommit,
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
    // A new query starts collapsed again.
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
            final localDone = !local.isLoading;
            final onlineDone = isOffline || !ytm.isLoading;
            final onlineEmpty =
                isOffline || (ytm.results.isEmpty && ytm.hasSearched);

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
                // BUG FIX: this used to clear only the cubits and left the
                // text in the field, so the button looked dead.
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
                    parent: BouncingScrollPhysics()),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                    bottom: PulsrLayoutMetrics.scrollBottom(context),
                    top: AppSpacing.xxs),
                children: [
                  _buildSectionHeader(
                    context: context,
                    icon: Icons.library_music_rounded,
                    title: context.l10n.localMusic,
                    count: localSongs.length,
                    isLoading: local.isLoading,
                    p: p,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (local.errorMessage != null && localSongs.isEmpty)
                    _buildErrorSectionCard(
                      context: context,
                      errorMessage:
                          resolveUiErrorMessage(context, local.errorMessage!),
                      onRetry: context.read<SearchCubit>().retry,
                      p: p,
                    )
                  else if (local.isLoading && localSongs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SkeletonList(itemCount: 3),
                    )
                  else if (localSongs.isEmpty)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.library_music_outlined,
                      message: context.l10n.noLocalSongsMatch(widget.query),
                      p: p,
                    )
                  else ...[
                    for (final song in localShown)
                      SongTile(
                        song: song,
                        subtitleOverride: '${song.artist} • ${song.album}',
                        onTap: () {
                          widget.onCommit();
                          player.playSong(song, queue: localSongs);
                        },
                        onMorePressed: () =>
                            SongInfoSheet.show(context, song: song),
                      ),
                    if (localSongs.length > _localPreview)
                      _ShowMoreButton(
                        expanded: _expandLocal,
                        onPressed: () =>
                            setState(() => _expandLocal = !_expandLocal),
                      ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                  const SizedBox(height: AppSpacing.xs),
                  if (isOffline)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.wifi_off_rounded,
                      message: context.l10n.offlineOnlyMode,
                      p: p,
                    )
                  else if (ytm.isLoading && onlineTracks.isEmpty)
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
                  else if (onlineTracks.isEmpty && ytm.hasSearched)
                    _buildEmptySectionCard(
                      context: context,
                      icon: Icons.search_off_rounded,
                      message: context.l10n.noOnlineSongsMatch(widget.query),
                      p: p,
                    )
                  else ...[
                    for (var i = 0; i < onlineShown; i++)
                      SongTile(
                        song: onlineSongs[i],
                        subtitleOverride: onlineTracks[i].artist,
                        onTap: () =>
                            player.playSong(onlineSongs[i], queue: onlineSongs),
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
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: p.accent,
          ),
          label: Text(
            expanded ? context.l10n.showLess : context.l10n.showMore,
            style: TextStyle(
                color: p.accent,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700),
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
              borderRadius: AppRadii.r12All,
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
        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                fontWeight: FontWeight.w500),
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
                fontSize: AppFontSize.caption, color: p.textSecondary),
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
                fontWeight: FontWeight.w700),
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
                    fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w600,
                color: p.accent),
          ),
        ),
      ],
    ),
  );
}

// ==================== ONLINE TAB ====================
/// Live YouTube Music results with per-row download controls. Only mounted in
/// an ENABLE_YTM build, under the providers created by [SearchScreen].
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final tag in _onlineTags)
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            padding: EdgeInsets.only(
                bottom: PulsrLayoutMetrics.scrollBottom(context),
                top: AppSpacing.xxs),
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
