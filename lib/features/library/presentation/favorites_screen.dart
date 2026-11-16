// lib/features/library/presentation/favorites_screen.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/song_classification.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/source_scope_switcher.dart';
import '../../../data/db/app_database.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import 'widgets/favorites_slivers.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchOpen = false;
  SourceScope _scope = SourceScope.local;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isOnlineFavorite(SongsTableData s) => isOnlineFavorite(s);

  List<SongsTableData> _filterSongs(List<SongsTableData> songs) {
    if (_searchQuery.isEmpty) return songs;
    final q = _searchQuery.toLowerCase();
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.album.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _downloadFavorites(
    BuildContext context,
    List<SongsTableData> songs,
  ) async {
    if (songs.isEmpty) return;
    final downloadCubit = context.read<YtmDownloadCubit?>() ??
        (getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null);
    if (downloadCubit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.downloadErrorDisabled)),
      );
      return;
    }
    final report = await downloadCubit.downloadAllDetailed(songs);
    if (!context.mounted) return;
    final queuedCount = report.queued;
    final extras = describeBatchOutcomeExtras(
      context.l10n,
      capped: report.capped,
      failed: report.failed,
      firstError: report.firstError,
      skippedLocal: report.skippedLocal,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queuedCount > 0
              ? '${context.l10n.browseQueued} $queuedCount ${context.l10n.browseTracksForDownload}$extras'
              : '${context.l10n.browseAllTracksAlreadyDownloaded}$extras',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Pull-to-refresh mirrors the integrated Favorites tab: a rescan for the
  /// Local bucket and a Liked-Music sync for the Online bucket.
  Future<void> _refreshFavorites() async {
    if (_scope == SourceScope.online && AppConfig.ytmEnabled) {
      await _syncOnlineLikes();
      return;
    }
    final settingsCubit = context.read<SettingsCubit?>();
    if (settingsCubit != null) {
      try {
        final count = await settingsCubit.rescanLibrary();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.scanResult(count)),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (_) {
        // A failed rescan still falls through to a library re-subscribe.
      }
    }
    if (!mounted) return;
    await context.read<LibraryCubit>().init();
  }

  Future<void> _syncOnlineLikes() async {
    if (!getIt.isRegistered<YtmAccountService>()) return;
    final accountService = getIt<YtmAccountService>();
    if (!accountService.isLoggedIn) {
      final success = await YtmWebLoginSheet.show(context);
      if (success != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final libraryCubit = context.read<LibraryCubit>();
    final authCubit = context.read<AuthCubit?>();
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.syncingYtm),
        duration: const Duration(seconds: 4),
      ),
    );
    try {
      final count = await libraryCubit.syncYtmAccountLikes();
      if (!mounted) return;
      if (_scope != SourceScope.online) {
        setState(() => _scope = SourceScope.online);
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.syncedOnline(count)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      try {
        authCubit?.syncNow();
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to trigger sync after saving online favorites',
          error: e,
          stackTrace: st,
          category: 'FavoritesScreen',
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      final isAuth = (e is YtmException && e.isAuth) ||
          e.toString().toLowerCase().contains('unauthenticated') ||
          e.toString().toLowerCase().contains('session expired') ||
          e.toString().toLowerCase().contains('not signed in');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isAuth
                ? context.l10n.sessionExpired
                : context.l10n.syncFailed(e.toString()),
          ),
          behavior: SnackBarBehavior.floating,
          action: isAuth
              ? SnackBarAction(
                  label: context.l10n.signIn,
                  onPressed: () => YtmWebLoginSheet.show(context),
                )
              : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final playerCubit = context.read<PlayerCubit>();
    final libraryCubit = context.read<LibraryCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const PulsrBackButton(),
          title: _isSearchOpen
              ? PulsrSearchField(
                  controller: _searchController,
                  autofocus: true,
                  hintText: '${l10n.search}...',
                  // PulsrSearchField already debounces onChanged by 300ms, so
                  // every keystroke does not rebuild the CustomScrollView.
                  onChanged: (v) {
                    if (mounted) setState(() => _searchQuery = v.trim());
                  },
                  onClear: () {
                    if (mounted) setState(() => _searchQuery = '');
                  },
                )
              : Text(
                  l10n.favorites,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: AppFontSize.bodyLarge,
                  ),
                ),
          actions: [
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              icon: Icon(
                _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                color: p.textPrimary,
              ),
              tooltip: _isSearchOpen ? l10n.close : l10n.search,
              onPressed: () {
                setState(() {
                  if (_isSearchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                    _isSearchOpen = false;
                  } else {
                    _isSearchOpen = true;
                  }
                });
              },
            ),
          ],
        ),
        body: BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, state) {
            final allFavorites = state.favorites;
            final localFavorites =
                allFavorites.where((s) => !_isOnlineFavorite(s)).toList();
            final onlineFavorites =
                allFavorites.where((s) => _isOnlineFavorite(s)).toList();

            final currentTabFavorites = _scope == SourceScope.local
                ? localFavorites
                : onlineFavorites;
            final songs = _filterSongs(currentTabFavorites);

            return Center(
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: RefreshIndicator(
                  color: p.accent,
                  backgroundColor: p.surfaceContainer,
                  onRefresh: _refreshFavorites,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: buildFavoritesSlivers(
                      context: context,
                      songs: songs,
                      localCount: localFavorites.length,
                      onlineCount: onlineFavorites.length,
                      scope: _scope,
                      onScopeChanged: (next) => setState(() => _scope = next),
                      isLoading: state.isLoading,
                      isGrid: false,
                      isMultiSelectMode: false,
                      selectedSongIds: const <int>{},
                      playerCubit: playerCubit,
                      libraryCubit: libraryCubit,
                      dismissKeyPrefix: 'fav_screen',
                      hasAnyInScope: currentTabFavorites.isNotEmpty,
                      searchQuery: _searchQuery,
                      onClearSearch: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      onDownloadAll: () => _downloadFavorites(context, songs),
                      onSyncOnline: _syncOnlineLikes,
                    ),
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