import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
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
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_chip.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_refresh_indicator.dart';
import '../../../core/widgets/pulsr_scroll_edge_fade.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/source_scope_switcher.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/db/app_database.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_options_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/cubit/ytm_search_cubit.dart';
import '../../ytm_search/cubit/ytm_search_state.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';
import 'widgets/highlighted_song_tile.dart';

import '../../../core/utils/pulsr_haptics.dart';

export '../../../core/widgets/source_scope_switcher.dart' show SourceScope;

part 'search_online_results.dart';
part 'search_start_page.dart';

/// Canonical scope selector for [SearchScreen].
///
/// Aliases [SourceScope] (`all`, `local`, `online`) so callers can pass
/// `initialScope: SearchScope.online` directly without enum conversion.
typedef SearchScope = SourceScope;

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

/// Unified search screen covering Local, Online (YouTube Music), and All scopes.
///
/// ### Route & Constructor Contract (Wave 3 `HomeScreen` & deep links)
/// - **Shell route**: `/search` accepts optional query parameters:
///   - `q`: prefilled search query string.
///   - `scope`: `all`, `local`, or `online` (parsed via [parseScopeParam]).
///   - `autofocus`: `true` or `1` to focus the search input on arrival.
///   - Use [SearchScreen.routeLocation] to construct deep links safely, e.g.:
///     `context.go(SearchScreen.routeLocation(scope: SearchScope.online, autofocus: true))`
/// - **Legacy route**: `/ytm-search` renders `YtmSearchScreen`, a thin wrapper
///   around `SearchScreen(initialScope: SearchScope.online, autofocus: true, showBackButton: true)`
///   so existing pushed navigation keeps a back button with zero broken deep links.
///
/// Everything that talks to [YtmSearchCubit] lives in [_SearchView], which sits
/// *below* the optional online [MultiBlocProvider].
class SearchScreen extends StatelessWidget {
  final String? initialQuery;
  final SearchScope? initialScope;
  final bool autofocus;
  final bool showBackButton;

  /// Optional override for whether online (YouTube Music) search is enabled.
  /// Defaults to [AppConfig.ytmEnabled].
  final bool? enableOnlineOverride;

  const SearchScreen({
    super.key,
    this.initialQuery,
    this.initialScope,
    this.autofocus = false,
    this.showBackButton = false,
    this.enableOnlineOverride,
  });

  /// Canonical GoRouter location builder for `/search` deep links.
  static String routeLocation({
    String? query,
    SearchScope? scope,
    bool autofocus = false,
  }) {
    final params = <String, String>{};
    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    if (scope != null) {
      params['scope'] = scope.name;
    }
    if (autofocus) {
      params['autofocus'] = 'true';
    }
    return Uri(
      path: '/search',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  /// Parses a `?scope=` route parameter (`all`, `local`, `online`).
  static SearchScope? parseScopeParam(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final scope in SearchScope.values) {
      if (scope.name == normalized) return scope;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final allowOnline = enableOnlineOverride ?? AppConfig.ytmEnabled;
    final view = _SearchView(
      initialQuery: initialQuery,
      initialScope: initialScope,
      autofocus: autofocus,
      showBackButton: showBackButton,
      allowOnline: allowOnline,
    );
    if (!allowOnline) return view;

    final hasYtmSearch = context.read<YtmSearchCubit?>() != null;
    final hasYtmDownload = context.read<YtmDownloadCubit?>() != null;
    final providers = <BlocProvider>[
      if (!hasYtmSearch && getIt.isRegistered<YtmSearchCubit>())
        BlocProvider<YtmSearchCubit>(create: (_) => getIt<YtmSearchCubit>()),
      if (!hasYtmDownload && getIt.isRegistered<YtmDownloadCubit>())
        BlocProvider<YtmDownloadCubit>.value(value: getIt<YtmDownloadCubit>()),
    ];
    if (providers.isEmpty) return view;

    return MultiBlocProvider(
      providers: providers,
      child: view,
    );
  }
}

class _SearchView extends StatefulWidget {
  final String? initialQuery;
  final SearchScope? initialScope;
  final bool autofocus;
  final bool showBackButton;
  final bool allowOnline;

  const _SearchView({
    this.initialQuery,
    this.initialScope,
    this.autofocus = false,
    this.showBackButton = false,
    required this.allowOnline,
  });

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Current scope: All / Local / Online.
  late SourceScope _scope;
  int get _tab => _scope.index;
  set _tab(int value) => _scope = SourceScope.values[value.clamp(0, 2)];

  /// Mirrors the text field so Online-tab typing triggers immediate UI updates.
  String _text = '';
  bool _hasFocus = false;

  List<String> _suggestions = const [];
  bool _showSuggestions = false;
  Timer? _suggestTimer;
  StreamSubscription? _settingsSub;
  String? _lastAppliedQueryParam;
  String? _lastAppliedRouteUri;
  bool _scopeExplicitlySet = false;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope ?? SourceScope.all;
    _scopeExplicitlySet = widget.initialScope != null;
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
    final hasLocal = context.read<SearchCubit?>() != null;
    if (!widget.allowOnline && _tab != 1) {
      _tab = 1;
    } else if (!hasLocal && widget.allowOnline && _tab != 2) {
      _tab = 2;
    }

    Uri? uri;
    try {
      uri = GoRouterState.of(context).uri;
    } catch (_) {
      uri = null;
    }
    if (uri == null) return;

    final uriString = uri.toString();
    final routeChanged = uriString != _lastAppliedRouteUri;
    if (routeChanged) {
      _lastAppliedRouteUri = uriString;

      final requestedScope =
          SearchScreen.parseScopeParam(uri.queryParameters['scope']);
      if (requestedScope != null) {
        _scopeExplicitlySet = true;
        if (requestedScope == SearchScope.online && !widget.allowOnline) {
          _scope = SearchScope.local;
        } else if (requestedScope != SearchScope.online && !hasLocal) {
          _scope = SearchScope.online;
        } else {
          _scope = requestedScope;
        }
      }

      final rawAutofocus =
          uri.queryParameters['autofocus']?.trim().toLowerCase();
      if (rawAutofocus == 'true' || rawAutofocus == '1') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    }

    final q = uri.queryParameters['q'];
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
  bool _hasLocalSearch() => context.read<SearchCubit?>() != null;

  bool _isOnlineAvailable({bool listen = true}) {
    if (!widget.allowOnline) return false;
    final hasYtm = context.read<YtmSearchCubit?>() != null;
    if (!hasYtm) return false;
    final settings = listen
        ? context.watch<SettingsCubit?>()
        : context.read<SettingsCubit?>();
    return !(settings?.state.offlineOnlyMode ?? false);
  }

  int _effectiveTab({bool listen = true}) {
    final online = _isOnlineAvailable(listen: listen);
    final local = _hasLocalSearch();
    if (!online) return 1;
    if (!local) return 2;
    return _tab;
  }

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
      context.read<SearchCubit?>()?.onQueryChanged(value, immediate: immediate);
    }
    if ((tab == 0 || tab == 2) && online) {
      if (value.isEmpty) {
        context.read<YtmSearchCubit?>()?.clearQuery();
      } else {
        context.read<YtmSearchCubit?>()?.onQueryChanged(value);
      }
    }

    if (!immediate && (tab == 0 || tab == 1) && _hasLocalSearch()) {
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
    final tab = _effectiveTab(listen: false);
    if (tab != 2) {
      context.read<SearchCubit?>()?.commitQuery(value);
    } else {
      context.read<YtmSearchCubit?>()?.commitQuery(value);
    }
  }

  void _scheduleSuggestions(String value) {
    _suggestTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _hideSuggestions();
      return;
    }
    final localCubit = context.read<SearchCubit?>();
    if (localCubit == null) return;
    _suggestTimer = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      final results = await localCubit.suggestionsFor(trimmed);
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
    if (commit) {
      if (_effectiveTab(listen: false) != 2) {
        context.read<SearchCubit?>()?.commitQuery(term);
      } else {
        context.read<YtmSearchCubit?>()?.commitQuery(term);
      }
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
    context.read<SearchCubit?>()?.applySavedSearch(d.query, d.filter);
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
    context.read<SearchCubit?>()?.clearQuery();
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
      final cubitArtists = context.read<SearchCubit?>()?.artistResults.value;
      final cubitMatch = cubitArtists
          ?.where((a) => a.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (cubitMatch != null) {
        context.push('/artist?id=${cubitMatch.id}', extra: cubitMatch);
        return;
      }
    } catch (_) {}
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
    context.read<SearchCubit?>()?.applySavedSearch(name, 'Artists');
    _controller.text = name;
    setState(() => _text = name);
  }

  void _openAlbum(String name) {
    try {
      final cubitAlbums = context.read<SearchCubit?>()?.albumResults.value;
      final cubitMatch = cubitAlbums
          ?.where((a) => a.title.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (cubitMatch != null) {
        context.push('/album?id=${cubitMatch.id}', extra: cubitMatch);
        return;
      }
    } catch (_) {}
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
    context.read<SearchCubit?>()?.applySavedSearch(name, 'Albums');
    _controller.text = name;
    setState(() => _text = name);
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final showOnline = _isOnlineAvailable();
    final hasLocal = _hasLocalSearch();
    final tab = _effectiveTab();
    final pad = Adaptive.pagePadding(context);
    final compactHeader = _hasFocus || _text.trim().isNotEmpty;
    final shouldAnimate = PulsrMotion.shouldAnimate(context);

    return Scaffold(
      appBar: widget.showBackButton
          ? AppBar(
              backgroundColor: p.bg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: const PulsrBackButton(),
              title: Semantics(
                header: true,
                child: Text(
                  tab == 2
                      ? context.l10n.browseYouTubeMusic
                      : context.l10n.search,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.titleLarge,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        top: !widget.showBackButton,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.showBackButton) ...[
                  if (!shouldAnimate || !context.motionEnabled)
                    (compactHeader
                        ? const SizedBox(height: AppSpacing.xs)
                        : Semantics(
                            header: true,
                            child: PulsrArtworkHeader(
                              height: 92,
                              title: context.l10n.search,
                              albumIds: context.select<PlayerCubit, List<int>>(
                                (c) => [
                                  for (final song
                                      in c.state.queueHistory.take(4))
                                    if (song.albumId != null) song.albumId!,
                                ],
                              ),
                            ),
                          ))
                  else
                    AnimatedSize(
                      duration: context.motion(PulsrMotion.state),
                      curve: context.motionCurve(PulsrMotion.enter),
                      alignment: Alignment.topCenter,
                      child: compactHeader
                          ? const SizedBox(height: AppSpacing.xs)
                          : Semantics(
                              header: true,
                              child: PulsrArtworkHeader(
                                height: 92,
                                title: context.l10n.search,
                                albumIds:
                                    context.select<PlayerCubit, List<int>>(
                                  (c) => [
                                    for (final song
                                        in c.state.queueHistory.take(4))
                                      if (song.albumId != null) song.albumId!,
                                  ],
                                ),
                              ),
                            ),
                    ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: _buildSearchField(context, p, tab),
                ),
                _buildProgressBar(p, tab),
                if (showOnline && hasLocal) ...[
                  const SizedBox(height: AppSpacing.xs),
                  if (_scopeExplicitlySet)
                    PulsrSegmentedControl(
                      margin: EdgeInsets.symmetric(horizontal: pad),
                      selectedIndex: _scope.index,
                      onChanged: _onTabChanged,
                      segments: [
                        PulsrSegment(
                          label: context.l10n.all,
                          icon: Icons.dashboard_rounded,
                        ),
                        PulsrSegment(
                          label: context.l10n.local,
                          icon: Icons.folder_rounded,
                        ),
                        PulsrSegment(
                          label: context.l10n.online,
                          icon: Icons.cloud_rounded,
                        ),
                      ],
                    )
                  else
                    SourceScopeSwitcher(
                      persistKey: 'search',
                      includeAll: true,
                      margin: EdgeInsets.symmetric(horizontal: pad),
                      selectedScope: _scope,
                      onChanged: (next) => _onTabChanged(next.index),
                    ),
                ],
                if (tab != 2 && hasLocal) _buildFilterBar(p, pad),
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

    final hint = tab == 2
        ? context.l10n.searchOnline
        : tab == 1
            ? context.l10n.searchPlaceholder
            : context.l10n.searchLocalOnlineHint;
    final focusGlowDuration = PulsrMotion.shouldAnimate(context)
        ? context.motion(PulsrMotion.state)
        : Duration.zero;

    return Semantics(
      textField: true,
      label: hint,
      child: AnimatedContainer(
        duration: focusGlowDuration,
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
          autofocus: widget.autofocus,
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
            hintText: hint,
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
                  return const SizedBox.shrink();
                }
                return IconButton(
                  key: const ValueKey('clear_btn'),
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
      ),
    );
  }

  Widget _buildProgressBar(PulsrPalette p, int tab) {
    if (tab == 2) {
      final ytmCubit = context.read<YtmSearchCubit?>();
      if (ytmCubit == null) {
        return const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xxs),
          child: SizedBox(height: 2),
        );
      }
      return BlocBuilder<YtmSearchCubit, YtmSearchState>(
        buildWhen: (a, b) => a.isLoading != b.isLoading || a.query != b.query,
        builder: (context, state) {
          final active = (state.isLoading || ytmCubit.isDebouncing) &&
              (state.query.trim().isNotEmpty || _text.trim().isNotEmpty);
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: SizedBox(
              height: 2,
              child: active
                  ? Semantics(
                      liveRegion: true,
                      label: context.l10n.search,
                      child: PulsrProgressBar.indeterminate(
                        height: 2,
                        color: p.accent,
                        backgroundColor: Colors.transparent,
                      ),
                    )
                  : null,
            ),
          );
        },
      );
    }

    final localCubit = context.read<SearchCubit?>();
    if (localCubit == null) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxs),
        child: SizedBox(height: 2),
      );
    }

    return BlocBuilder<SearchCubit, SearchState>(
      buildWhen: (a, b) => a.isLoading != b.isLoading,
      builder: (context, state) {
        final active = tab != 2 && state.isLoading && _text.trim().isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: SizedBox(
            height: 2,
            child: active
                ? Semantics(
                    liveRegion: true,
                    label: context.l10n.search,
                    child: PulsrProgressBar.indeterminate(
                      height: 2,
                      color: p.accent,
                      backgroundColor: Colors.transparent,
                    ),
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

  String _filterLabel(BuildContext context, String filter) =>
      _localizedFilterLabel(context, filter);

  Widget _buildBody(
      BuildContext context, PulsrPalette p, bool showOnline, int tab) {
    final text = _text.trim();
    final hasLocal = _hasLocalSearch();
    final Widget content;

    if (showOnline && tab == 2) {
      content = BlocBuilder<YtmSearchCubit, YtmSearchState>(
        builder: (context, ytmState) {
          final ytm = context.read<YtmSearchCubit>();
          final hasActiveOnline = text.isNotEmpty ||
              ytmState.query.trim().isNotEmpty ||
              ytmState.isLoading ||
              ytm.isDebouncing ||
              ytmState.results.isNotEmpty ||
              ytmState.errorMessage != null ||
              ytmState.hasSearched;
          if (hasActiveOnline) {
            return _OnlineResults(
              onSelectTag: (t) => _applySearch(t, commit: false),
            );
          }
          return ValueListenableBuilder<List<String>>(
            valueListenable: ytm.historyNotifier,
            builder: (context, onlineHistory, _) {
              if (onlineHistory.isEmpty) {
                return _OnlineResults(
                  onSelectTag: (t) => _applySearch(t, commit: false),
                );
              }
              return _StartPage(
                history: const [],
                showOnline: showOnline,
                tab: tab,
                onRecent: _applySearch,
                onFillQuery: _fillQueryOnly,
                onTag: (t) => _applySearch(t, commit: false),
                onSaved: _applySavedSearch,
              );
            },
          );
        },
      );
    } else if (text.isEmpty) {
      content = hasLocal
          ? BlocBuilder<SearchCubit, SearchState>(
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
            )
          : _StartPage(
              history: const [],
              showOnline: showOnline,
              tab: tab,
              onRecent: _applySearch,
              onFillQuery: _fillQueryOnly,
              onTag: (t) => _applySearch(t, commit: false),
              onSaved: _applySavedSearch,
            );
    } else if (showOnline && tab == 0 && hasLocal) {
      content = _UnifiedSearchResults(
        query: text,
        onClear: _clear,
        onCommit: () => context.read<SearchCubit?>()?.commitQuery(text),
        onOpenArtist: _openArtist,
        onOpenAlbum: _openAlbum,
      );
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
    final artistNotifier = _safeArtistResults(cubit);
    final albumNotifier = _safeAlbumResults(cubit);
    return ListenableBuilder(
      listenable: Listenable.merge([
        if (artistNotifier != null) artistNotifier,
        if (albumNotifier != null) albumNotifier,
      ]),
      builder: (context, _) {
        final directArtists =
            artistNotifier?.value ?? const <ArtistsTableData>[];
        final directAlbums = albumNotifier?.value ?? const <AlbumsTableData>[];
        final filter = state.selectedFilter;
        final derived = _deriveEntities(state.results);
        final allArtists = (filter == 'All' || filter == 'Artists')
            ? _mergeArtistEntities(directArtists, derived.artists)
            : const <_DerivedEntity>[];
        final allAlbums = (filter == 'All' || filter == 'Albums')
            ? _mergeAlbumEntities(directAlbums, derived.albums)
            : const <_DerivedEntity>[];
        final artists = allArtists.take(10).toList();
        final albums = allAlbums.take(10).toList();
        final hasAnyEntityMatch = artists.isNotEmpty || albums.isNotEmpty;

        if ((state.isLoading || pending) &&
            state.results.isEmpty &&
            !hasAnyEntityMatch) {
          return const SkeletonList(
              padding: EdgeInsets.only(top: AppSpacing.xs));
        }
        final error = state.errorMessage;
        if (error != null && state.results.isEmpty && !hasAnyEntityMatch) {
          return PulsrEmptyState(
            icon: Icons.error_outline_rounded,
            title: context.l10n.somethingWentWrong,
            subtitle: resolveUiErrorMessage(context, error),
            primaryActionLabel: context.l10n.retry,
            primaryActionIcon: Icons.refresh_rounded,
            onPrimaryAction: cubit.retry,
          );
        }
        if (state.results.isEmpty && !hasAnyEntityMatch) {
          return PulsrEmptyState(
            icon: Icons.search_off_rounded,
            title: context.l10n.noResultsFound,
            subtitle:
                '${context.l10n.noResultsSubtitle} "${state.query.trim()}"',
            primaryActionLabel: context.l10n.clearSearchQuery,
            primaryActionIcon: Icons.backspace_rounded,
            onPrimaryAction: onClear,
          );
        }

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
                    count: allArtists.length,
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
                    count: allAlbums.length,
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
              if (state.results.isNotEmpty || !hasAnyEntityMatch) ...[
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
              ],
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
                child:
                    SizedBox(height: PulsrLayoutMetrics.scrollBottom(context)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DerivedEntity {
  final String name;
  final int songId;
  final int? artistId;
  final int? albumId;
  final String? artworkUrl;
  final ArtworkType artworkType;

  const _DerivedEntity({
    required this.name,
    required this.songId,
    this.artistId,
    this.albumId,
    this.artworkUrl,
    this.artworkType = ArtworkType.AUDIO,
  });
}

ValueNotifier<List<ArtistsTableData>>? _safeArtistResults(SearchCubit cubit) {
  try {
    return cubit.artistResults;
  } catch (_) {
    return null;
  }
}

ValueNotifier<List<AlbumsTableData>>? _safeAlbumResults(SearchCubit cubit) {
  try {
    return cubit.albumResults;
  } catch (_) {
    return null;
  }
}

List<_DerivedEntity> _mergeArtistEntities(
  List<ArtistsTableData> direct,
  List<_DerivedEntity> derived,
) {
  if (direct.isEmpty) return derived;
  final derivedByName = {
    for (final e in derived) e.name.toLowerCase(): e,
  };
  final merged = <_DerivedEntity>[];
  final seen = <String>{};
  for (final a in direct) {
    final name = a.name.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    final fromSongs = derivedByName[name.toLowerCase()];
    merged.add(_DerivedEntity(
      name: name,
      songId: fromSongs?.songId ?? a.id,
      artistId: a.id,
      albumId: fromSongs?.albumId,
      artworkUrl: a.artworkUri ?? fromSongs?.artworkUrl,
      artworkType: fromSongs != null ? ArtworkType.AUDIO : ArtworkType.ARTIST,
    ));
  }
  for (final e in derived) {
    if (seen.add(e.name.toLowerCase())) {
      merged.add(e);
    }
  }
  return merged;
}

List<_DerivedEntity> _mergeAlbumEntities(
  List<AlbumsTableData> direct,
  List<_DerivedEntity> derived,
) {
  if (direct.isEmpty) return derived;
  final derivedByName = {
    for (final e in derived) e.name.toLowerCase(): e,
  };
  final merged = <_DerivedEntity>[];
  final seen = <String>{};
  for (final al in direct) {
    final name = al.title.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    final fromSongs = derivedByName[name.toLowerCase()];
    merged.add(_DerivedEntity(
      name: name,
      songId: fromSongs?.songId ?? al.id,
      albumId: al.id,
      artworkUrl: al.artworkUri ?? fromSongs?.artworkUrl,
      artworkType: fromSongs != null ? ArtworkType.AUDIO : ArtworkType.ALBUM,
    ));
  }
  for (final e in derived) {
    if (seen.add(e.name.toLowerCase())) {
      merged.add(e);
    }
  }
  return merged;
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
            return Semantics(
              button: true,
              label: item.name,
              child: InkWell(
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
                          type: item.artworkType,
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
            final localCubit = context.read<SearchCubit>();
            final ytmCubit = context.read<YtmSearchCubit>();
            final artistNotifier = _safeArtistResults(localCubit);
            final albumNotifier = _safeAlbumResults(localCubit);
            return ListenableBuilder(
              listenable: Listenable.merge([
                if (artistNotifier != null) artistNotifier,
                if (albumNotifier != null) albumNotifier,
              ]),
              builder: (context, _) {
                final localPending = localCubit.isDebouncing;
                final onlinePending = ytmCubit.isDebouncing;
                final localDone = !local.isLoading && !localPending;
                final onlineDone =
                    isOffline || (!ytm.isLoading && !onlinePending);
                final onlineEmpty = isOffline ||
                    (ytm.results.isEmpty && ytm.hasSearched && !onlinePending);

                final localSongs = local.results;
                final localShown = _expandLocal
                    ? localSongs
                    : localSongs.take(_localPreview).toList();
                final onlineTracks = ytm.results;
                final onlineSongs = [
                  for (final t in onlineTracks) t.toSongData()
                ];
                final onlineShown = _expandOnline
                    ? onlineSongs.length
                    : onlineSongs.length.clamp(0, _onlinePreview);

                final filter = local.selectedFilter;
                final directArtists = artistNotifier?.value ?? const [];
                final directAlbums = albumNotifier?.value ?? const [];
                final entities = _deriveEntities(localSongs);
                final allArtists = (filter == 'All' || filter == 'Artists')
                    ? _mergeArtistEntities(directArtists, entities.artists)
                    : const <_DerivedEntity>[];
                final allAlbums = (filter == 'All' || filter == 'Albums')
                    ? _mergeAlbumEntities(directAlbums, entities.albums)
                    : const <_DerivedEntity>[];
                final artists = allArtists.take(8).toList();
                final albums = allAlbums.take(8).toList();
                final hasAnyLocalEntity =
                    artists.isNotEmpty || albums.isNotEmpty;

                if (localDone &&
                    onlineDone &&
                    local.results.isEmpty &&
                    !hasAnyLocalEntity &&
                    onlineEmpty &&
                    ytm.errorMessage == null &&
                    local.errorMessage == null) {
                  return PulsrEmptyState(
                    icon: Icons.search_off_rounded,
                    title: context.l10n.noResultsFound,
                    subtitle:
                        '${context.l10n.noResultsSubtitle} "${widget.query}"',
                    primaryActionLabel: context.l10n.clearSearchQuery,
                    primaryActionIcon: Icons.backspace_rounded,
                    onPrimaryAction: widget.onClear,
                  );
                }

                final localPaneChildren = <Widget>[
                  if (artists.isNotEmpty) ...[
                    _buildSectionHeader(
                      context: context,
                      icon: Icons.person_rounded,
                      title: context.l10n.artists,
                      count: allArtists.length,
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
                      count: allAlbums.length,
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
                ];

                final onlinePaneChildren = <Widget>[
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
                      onRetry:
                          context.read<YtmSearchCubit>().retryAfterCooldown,
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
                          context.read<YtmSearchCubit>().commitQuery();
                          context
                              .read<SearchCubit>()
                              .recordPlayedSong(onlineSongs[i]);
                          player.playSong(onlineSongs[i], queue: onlineSongs);
                        },
                        onLongPress: () =>
                            _showOnlineTrackActions(context, onlineSongs[i], p),
                        onMorePressed: () =>
                            _showOnlineTrackActions(context, onlineSongs[i], p),
                        trailing: YtmDownloadButton(song: onlineSongs[i]),
                      ),
                    if (onlineSongs.length > _onlinePreview)
                      _ShowMoreButton(
                        expanded: _expandOnline,
                        onPressed: () =>
                            setState(() => _expandOnline = !_expandOnline),
                      ),
                    if (ytm.loadMoreFailed)
                      Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              context.read<YtmSearchCubit>().loadMore(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(context.l10n.retry),
                        ),
                      )
                    else if (ytm.isLoading && onlineTracks.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Center(
                          child: PulsrProgressBar.circular(
                            size: 20,
                            strokeWidth: 2.2,
                            color: p.accent,
                          ),
                        ),
                      ),
                  ],
                ];

                bool handleOnlineScroll(ScrollNotification notification) {
                  final ytmCubit = context.read<YtmSearchCubit>();
                  if (notification.metrics.extentAfter < 400 &&
                      ytmCubit.hasMore &&
                      !ytm.isLoading &&
                      !ytm.loadMoreFailed &&
                      (_expandOnline ||
                          onlineTracks.length <= _onlinePreview)) {
                    unawaited(ytmCubit.loadMore());
                  }
                  return false;
                }

                Future<void> handleRefresh() async {
                  if (!isOffline) {
                    context.read<YtmSearchCubit>().onQueryChanged(widget.query);
                  }
                  await context.read<SearchCubit>().refresh();
                }

                final isSplit = PulsrLayoutMetrics.isSplitView(context) ||
                    Adaptive.isTabletLandscape(context);

                if (isSplit) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          color: p.accent,
                          backgroundColor: p.surfaceContainer,
                          onRefresh: () =>
                              context.read<SearchCubit>().refresh(),
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
                            children: localPaneChildren,
                          ),
                        ),
                      ),
                      VerticalDivider(
                        color: p.hairline,
                        width: 1,
                        thickness: 1,
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          color: p.accent,
                          backgroundColor: p.surfaceContainer,
                          onRefresh: () => isOffline
                              ? Future<void>.value()
                              : context.read<YtmSearchCubit>().retry(),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: handleOnlineScroll,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.only(
                                bottom:
                                    PulsrLayoutMetrics.scrollBottom(context),
                                top: AppSpacing.xxs,
                              ),
                              children: onlinePaneChildren,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return RefreshIndicator(
                  color: p.accent,
                  backgroundColor: p.surfaceContainer,
                  onRefresh: handleRefresh,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: handleOnlineScroll,
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
                        ...localPaneChildren,
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Divider(color: p.hairline, height: 1),
                        ),
                        ...onlinePaneChildren,
                      ],
                    ),
                  ),
                );
              },
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
    final label = expanded ? context.l10n.showLess : context.l10n.showMore;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Semantics(
          button: true,
          expanded: expanded,
          label: label,
          excludeSemantics: true,
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
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
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
                      label,
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
  return Semantics(
    header: true,
    label: '$title ($count)',
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Adaptive.pagePadding(context),
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.14),
                borderRadius: AppRadii.circular(8),
              ),
              child: Icon(icon, size: 16, color: p.accent),
            ),
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
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _buildEmptySectionCard({
  required BuildContext context,
  required IconData icon,
  required String message,
  required PulsrPalette p,
}) {
  return Semantics(
    liveRegion: true,
    child: Container(
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
          ExcludeSemantics(child: Icon(icon, size: 20, color: p.textTertiary)),
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
    ),
  );
}

Widget _buildErrorSectionCard({
  required BuildContext context,
  required String errorMessage,
  required VoidCallback onRetry,
  required PulsrPalette p,
}) {
  return Semantics(
    liveRegion: true,
    child: Container(
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
          ExcludeSemantics(
            child: Icon(Icons.cloud_off_rounded, size: 20, color: p.accent),
          ),
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
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AppSpacing.minTouchTarget,
                AppSpacing.minTouchTarget,
              ),
            ),
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
          child: Semantics(
            header: true,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 14, color: p.textTertiary),
                ),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.wide,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(
              AppSpacing.minTouchTarget,
              AppSpacing.minTouchTarget,
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
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

String _localizedFilterLabel(BuildContext context, String filter) {
  switch (filter) {
    case 'All':
      return context.l10n.all;
    case 'Songs':
      return context.l10n.songs;
    case 'Artists':
      return context.l10n.artists;
    case 'Albums':
      return context.l10n.albums;
    case 'FLAC':
      return context.l10n.browseFlac;
    case 'Lossless':
      return context.l10n.browseLossless;
    default:
      return filter;
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
