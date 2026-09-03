import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/features/tag_editor/presentation/tag_editor_screen.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../data/services/ytm_account_service.dart';
import '../../../data/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_info_sheet.dart';
import '../../sheets/sort_filter_sheet.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import '../../downloads/cubit/ytm_download_cubit.dart';
import '../../downloads/presentation/widgets/ytm_download_button.dart';
import 'widgets/folder_browser_tab.dart';

import '../../../core/utils/error_logger.dart';
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _songsScrollController = ScrollController();
  int _favTabFilter = 0; // 0: Local, 1: Online

  // F-06: memoized O(n) filter passes â€” recomputed only when the source list
  // identity changes (freezed copyWith preserves references), never per build.
  List<SongsTableData>? _songsCacheKey;
  List<SongsTableData> _downloadedListCache = const [];
  int _downloadedBadgeCountCache = 0;
  List<SongsTableData>? _favoritesCacheKey;
  List<SongsTableData> _localFavoritesCache = const [];
  List<SongsTableData> _onlineFavoritesCache = const [];

  void _ensureSongsDerivedCaches(LibraryState state) {
    if (identical(_songsCacheKey, state.songs)) return;
    _songsCacheKey = state.songs;
    _downloadedListCache = state.songs.where(_isOnlineDownload).toList();
    _downloadedBadgeCountCache =
        state.songs.where((s) => s.isDownloaded == true).length;
  }

  List<SongsTableData> _downloadedOf(LibraryState state) {
    _ensureSongsDerivedCaches(state);
    return _downloadedListCache;
  }

  int _downloadedBadgeCountOf(LibraryState state) {
    _ensureSongsDerivedCaches(state);
    return _downloadedBadgeCountCache;
  }

  void _ensureFavoritesDerivedCaches(LibraryState state) {
    if (identical(_favoritesCacheKey, state.favorites)) return;
    _favoritesCacheKey = state.favorites;
    _localFavoritesCache =
        state.favorites.where((s) => !_isOnlineFavorite(s)).toList();
    _onlineFavoritesCache =
        state.favorites.where((s) => _isOnlineFavorite(s)).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _songsScrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter, List<SongsTableData> songs) {
    final index = songs.indexWhere(
      (s) => s.title.toUpperCase().startsWith(letter),
    );
    if (index != -1 && _songsScrollController.hasClients) {
      final maxScroll = _songsScrollController.position.maxScrollExtent;
      final target =
          songs.length > 1 ? (index / (songs.length - 1)) * maxScroll : 0.0;
      _songsScrollController.animateTo(
        target.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      // F-06: the shell only depends on selection/view/sort state â€” data
      // emissions (songs/albums/artists/genres/years/favorites) no longer
      // rebuild the whole 8-tab scaffold. Each tab gets its own gated builder
      // below, and the downloaded badge has a songs-identity builder of its
      // own.
      buildWhen:
          (a, b) =>
              a.isMultiSelectMode != b.isMultiSelectMode ||
              listContentDiffers(a.selectedSongIds, b.selectedSongIds) ||
              a.viewMode != b.viewMode ||
              a.sortBy != b.sortBy ||
              a.ascending != b.ascending,
      builder: (context, state) {
        final cubit = context.read<LibraryCubit>();
        final playerCubit = context.read<PlayerCubit>();
        final isMultiSelect = state.isMultiSelectMode;
        final p = context.palette;

        return Scaffold(
          appBar:
              isMultiSelect
                  ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: cubit.clearSelection,
                    ),
                    title: Text('${state.selectedSongIds.length} Selected'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.select_all_rounded),
                        tooltip: 'Select All',
                        onPressed: cubit.selectAllSongs,
                      ),
                      IconButton(
                        icon: const Icon(Icons.playlist_add_rounded),
                        tooltip: 'Add to Playlist',
                        onPressed: () {
                          final selected = cubit.getSelectedSongs();
                          if (selected.isNotEmpty) {
                            showModalBottomSheet<void>(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder:
                                  (_) => AddToPlaylistSheet(
                                    song: selected.first,
                                    songs: selected,
                                  ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_note_rounded),
                        tooltip: 'Batch Edit Tags',
                        onPressed: () {
                          final selected = cubit.getSelectedSongs();
                          if (selected.isNotEmpty) {
                            cubit.clearSelection();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => TagEditorScreen(
                                      song: selected.first,
                                      batchSongs: selected,
                                    ),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded),
                        tooltip: 'Add to Queue',
                        onPressed: () {
                          final selected = cubit.getSelectedSongs();
                          for (final s in selected) {
                            playerCubit.addToQueue(s);
                          }
                          cubit.clearSelection();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added ${selected.length} tracks to queue',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  )
                  : AppBar(
                    title: Text(context.l10n.navLibrary),
                    actions: [
                      IconButton(
                        icon: Icon(
                          state.viewMode == LibraryViewMode.list
                              ? Icons.grid_view_rounded
                              : Icons.view_list_rounded,
                        ),
                        onPressed: cubit.toggleViewMode,
                      ),
                      IconButton(
                        icon: const Icon(Icons.sort_rounded),
                        onPressed:
                            () => showModalBottomSheet<void>(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder:
                                  (_) => SortFilterSheet(
                                    currentSort: state.sortBy,
                                    ascending: state.ascending,
                                    onApply:
                                        (sort, asc) =>
                                            cubit.updateSort(sort, asc),
                                  ),
                            ),
                      ),
                    ],
                    bottom: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      physics: const BouncingScrollPhysics(),
                      tabs: [
                        Tab(text: context.l10n.songs),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(context.l10n.downloaded),
                              // F-06: songs-identity-scoped badge builder, so
                              // the O(n) count runs once per songs change, not
                              // twice per shell build.
                              BlocBuilder<LibraryCubit, LibraryState>(
                                buildWhen:
                                    (a, b) =>
                                        listContentDiffers(a.songs, b.songs),
                                builder: (context, songsState) {
                                  final count = _downloadedBadgeCountOf(
                                    songsState,
                                  );
                                  if (count == 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: p.accent.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          '$count',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: p.accent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Tab(text: context.l10n.albums),
                        Tab(text: context.l10n.artists),
                        Tab(text: context.l10n.favorites),
                        Tab(text: context.l10n.folders),
                        Tab(text: context.l10n.genres),
                        Tab(text: context.l10n.years),
                      ],
                    ),
                  ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: TabBarView(
                controller: _tabController,
                // F-06: per-tab gated builders â€” an emission touching one
                // collection no longer rebuilds all eight tab subtrees.
                children: [
                  _songsTab(cubit, playerCubit),
                  _downloadedTab(cubit, playerCubit),
                  _albumsTab(),
                  _artistsTab(),
                  _favoritesTab(playerCubit),
                  const FolderBrowserTab(),
                  _genresTab(),
                  _yearsTab(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRefresh(BuildContext context) async {
    final settingsCubit = context.read<SettingsCubit>();
    final libraryCubit = context.read<LibraryCubit>();
    final count = await settingsCubit.rescanLibrary();
    if (context.mounted) {
      // Use refresh() instead of init() to avoid re-emitting preferences state
      // which caused a double-emit / overlapping list render on pull-to-refresh.
      await libraryCubit.refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.scanResult(count)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildEmpty(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
  }) {
    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: icon,
              title: title,
              subtitle: subtitle,
              primaryActionLabel: actionLabel ?? context.l10n.scanStorage,
              primaryActionIcon:
                  actionIcon ?? Icons.center_focus_strong_rounded,
              onPrimaryAction: onAction ?? () => _handleRefresh(context),
            ),
          ),
        ],
      ),
    );
  }

  // ================= PER-TAB GATED BUILDERS (F-06) =================
  Widget _songsTab(LibraryCubit cubit, PlayerCubit playerCubit) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.songs, b.songs) ||
              a.viewMode != b.viewMode ||
              listContentDiffers(a.selectedSongIds, b.selectedSongIds) ||
              a.isMultiSelectMode != b.isMultiSelectMode ||
              a.isLoading != b.isLoading,
      builder:
          (context, state) =>
              _buildSongsTab(context, state, cubit, playerCubit),
    );
  }

  Widget _downloadedTab(LibraryCubit cubit, PlayerCubit playerCubit) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.songs, b.songs) ||
              listContentDiffers(a.selectedSongIds, b.selectedSongIds) ||
              a.isMultiSelectMode != b.isMultiSelectMode ||
              a.isLoading != b.isLoading,
      builder:
          (context, state) =>
              _buildDownloadedTab(context, state, cubit, playerCubit),
    );
  }

  Widget _albumsTab() {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.albums, b.albums) ||
              a.viewMode != b.viewMode ||
              a.isLoading != b.isLoading,
      builder: (context, state) => _buildAlbumsTab(context, state),
    );
  }

  Widget _artistsTab() {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.artists, b.artists) ||
              a.viewMode != b.viewMode ||
              a.isLoading != b.isLoading,
      builder: (context, state) => _buildArtistsTab(context, state),
    );
  }

  Widget _favoritesTab(PlayerCubit playerCubit) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.favorites, b.favorites) ||
              a.viewMode != b.viewMode ||
              listContentDiffers(a.selectedSongIds, b.selectedSongIds) ||
              a.isMultiSelectMode != b.isMultiSelectMode ||
              a.isLoading != b.isLoading,
      builder:
          (context, state) => _buildFavoritesTab(context, state, playerCubit),
    );
  }

  Widget _genresTab() {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.genres, b.genres) ||
              a.isLoading != b.isLoading,
      builder: (context, state) => _buildGenresTab(context, state),
    );
  }

  Widget _yearsTab() {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen:
          (a, b) =>
              listContentDiffers(a.years, b.years) ||
              a.isLoading != b.isLoading,
      builder: (context, state) => _buildYearsTab(context, state),
    );
  }

  // ================= SONGS =================
  Widget _buildSongsTab(
    BuildContext context,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    final p = context.palette;
    final songs = state.songs;
    if (songs.isEmpty) {
      return _buildEmpty(
        context,
        title: context.l10n.noSongsFound,
        subtitle: context.l10n.noSongsSubtitle,
        icon: Icons.music_note_rounded,
      );
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    if (isGrid) {
      return RefreshIndicator(
        onRefresh: () => _handleRefresh(context),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            Adaptive.pagePadding(context),
            16,
            Adaptive.pagePadding(context),
            160,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Adaptive.gridColumns(context, minItemWidth: 155),
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            childAspectRatio: 0.76,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final isSelected = state.selectedSongIds.contains(song.id);
            return RepaintBoundary(
              key: ValueKey('song_grid_${song.id}'),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  if (state.isMultiSelectMode) {
                    cubit.toggleSongSelection(song.id);
                  } else {
                    playerCubit.playSong(song, queue: songs);
                  }
                },
                onLongPress: () => cubit.toggleSongSelection(song.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CachedArtwork(
                              id: song.id,
                              remoteUrl: song.remoteArtworkUrl,
                              type: ArtworkType.AUDIO,
                              size: double.infinity,
                              borderRadius: 18,
                            ),
                          ),
                          if (isSelected)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap:
                                    () => showModalBottomSheet<void>(
                                      context: context,
                                      useRootNavigator: true,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => SongInfoSheet(song: song),
                                    ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6.0),
                                  child: Icon(
                                    Icons.more_vert_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    final showAlphabet = songs.length >= 15;
    final alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: Stack(
        children: [
          ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: _songsScrollController,
            padding: const EdgeInsets.only(
              bottom: 160,
              top: 8,
              left: 4,
              right: 4,
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return Dismissible(
                key: ValueKey('song_${song.id}'),
                background: Container(
                  color: p.accentContainer,
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsetsDirectional.only(start: 24),
                  child: Row(
                    children: [
                      Icon(Icons.playlist_play_rounded, color: p.accent),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.playNext,
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                secondaryBackground: Container(
                  color: p.favorite.withValues(alpha: 0.2),
                  alignment: AlignmentDirectional.centerEnd,
                  padding: const EdgeInsetsDirectional.only(end: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        context.l10n.favorite,
                        style: TextStyle(
                          color: p.favorite,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.favorite_rounded, color: p.favorite),
                    ],
                  ),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    unawaited(playerCubit.playNext(song));
                  } else {
                    unawaited(cubit.toggleFavorite(song.id));
                  }
                  return false;
                },
                child: SongTile(
                  song: song,
                  selected: state.selectedSongIds.contains(song.id),
                  onTap: () {
                    if (state.isMultiSelectMode) {
                      cubit.toggleSongSelection(song.id);
                    } else {
                      playerCubit.playSong(song, queue: songs);
                    }
                  },
                  onLongPress: () => cubit.toggleSongSelection(song.id),
                  onMorePressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => SongInfoSheet(song: song),
                      ),
                ),
              );
            },
          ),
          if (showAlphabet)
            PositionedDirectional(
              end: 4,
              top: 8,
              bottom: 150,
              child: Container(
                width: 22,
                decoration: BoxDecoration(
                  color: p.surfaceContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children:
                        alphabet
                            .map(
                              (l) => InkWell(
                                onTap: () => _scrollToLetter(l, songs),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    l,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: p.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ================= DOWNLOADED =================
  Widget _buildDownloadedTab(
    BuildContext context,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    final p = context.palette;
    // F-06: cached filter â€” recomputed only when state.songs identity changes.
    final downloaded = _downloadedOf(state);

    if (downloaded.isEmpty) {
      return _buildEmpty(
        context,
        icon: Icons.cloud_download_rounded,
        title: context.l10n.noDownloadsYet,
        subtitle: context.l10n.noDownloadsYetSubtitle,
        actionLabel: context.l10n.exploreOnlineMusic,
        actionIcon: Icons.travel_explore_rounded,
        onAction: () => context.go('/'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: Column(
        children: [
          // ---------- Header Card with Play All & Shuffle ----------
          Padding(
            padding: EdgeInsets.fromLTRB(
              Adaptive.pagePadding(context),
              12,
              Adaptive.pagePadding(context),
              8,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.15),
                    p.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.download_done_rounded,
                      color: p.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.offlineDownloads,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.tracksCount(downloaded.length),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    tooltip: context.l10n.playAll,
                    onPressed:
                        () => playerCubit.playSong(
                          downloaded.first,
                          queue: downloaded,
                        ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: p.surfaceContainerHigh,
                      foregroundColor: p.textPrimary,
                    ),
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    tooltip: context.l10n.shuffle,
                    onPressed: () {
                      final shuffled = List<SongsTableData>.from(downloaded)
                        ..shuffle();
                      playerCubit.playSong(shuffled.first, queue: shuffled);
                    },
                  ),
                ],
              ),
            ),
          ),

          // ---------- List of Downloaded Songs ----------
          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                bottom: 160,
                top: 4,
                left: 4,
                right: 4,
              ),
              itemCount: downloaded.length,
              itemBuilder: (context, index) {
                final song = downloaded[index];
                return Dismissible(
                  key: ValueKey('dl_${song.id}'),
                  background: Container(
                    color: p.accentContainer,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 24),
                    child: Row(
                      children: [
                        Icon(Icons.playlist_play_rounded, color: p.accent),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.playNext,
                          style: TextStyle(
                            color: p.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  secondaryBackground: Container(
                    color: p.favorite.withValues(alpha: 0.2),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          context.l10n.favorite,
                          style: TextStyle(
                            color: p.favorite,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.favorite_rounded, color: p.favorite),
                      ],
                    ),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      unawaited(playerCubit.playNext(song));
                    } else {
                      unawaited(cubit.toggleFavorite(song.id));
                    }
                    return false;
                  },
                  child: SongTile(
                    song: song,
                    index: index + 1,
                    selected: state.selectedSongIds.contains(song.id),
                    onTap: () {
                      if (state.isMultiSelectMode) {
                        cubit.toggleSongSelection(song.id);
                      } else {
                        playerCubit.playSong(song, queue: downloaded);
                      }
                    },
                    onLongPress: () => cubit.toggleSongSelection(song.id),
                    onMorePressed:
                        () => showModalBottomSheet<void>(
                          context: context,
                          useRootNavigator: true,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => SongInfoSheet(song: song),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isOnlineDownload(SongsTableData s) {
    if (s.path.isEmpty || s.path.startsWith('ytmusic://')) return false;
    // Primary: use the isDownloaded flag from DB
    if (s.isDownloaded == true) return true;
    // Secondary: source is local but has remoteId (reconciled download)
    if (s.source == SongSource.local &&
        s.remoteId != null &&
        s.remoteId!.isNotEmpty) {
      return true;
    }
    return false;
  }

  // ================= ALBUMS (adaptive grid / list) =================
  Widget _buildAlbumsTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final albums = state.albums;
    if (albums.isEmpty) {
      return _buildEmpty(
        context,
        title: 'No Albums Found',
        subtitle: 'Scan your media library to view your albums.',
        icon: Icons.album_rounded,
      );
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child:
          isGrid
              ? GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Adaptive.pagePadding(context),
                  16,
                  Adaptive.pagePadding(context),
                  160,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Adaptive.gridColumns(
                    context,
                    minItemWidth: 168,
                  ),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.78,
                ),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => context.push('/album', extra: album),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Hero(
                            tag: 'album_${album.id}',
                            child: CachedArtwork(
                              id: album.id,
                              type: ArtworkType.ALBUM,
                              size: double.infinity,
                              borderRadius: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${album.artist} â€¢ ${Formatters.formatTrackCount(album.songCount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
              : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 160, top: 8),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    child: Material(
                      color: p.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: p.hairline),
                      ),
                      child: ListTile(
                        leading: CachedArtwork(
                          id: album.id,
                          type: ArtworkType.ALBUM,
                          size: 48,
                          borderRadius: 12,
                        ),
                        title: Text(
                          album.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: p.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${album.artist} â€¢ ${Formatters.formatTrackCount(album.songCount)}',
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: p.textTertiary,
                        ),
                        onTap: () => context.push('/album', extra: album),
                      ),
                    ),
                  );
                },
              ),
    );
  }

  // ================= ARTISTS =================
  Widget _buildArtistsTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final artists = state.artists;
    if (artists.isEmpty) {
      return _buildEmpty(
        context,
        title: 'No Artists Found',
        subtitle: 'Scan your media library to view all artists.',
        icon: Icons.person_rounded,
      );
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child:
          isGrid
              ? GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Adaptive.pagePadding(context),
                  16,
                  Adaptive.pagePadding(context),
                  160,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Adaptive.gridColumns(
                    context,
                    minItemWidth: 150,
                    phoneColumns: 3,
                    maxColumns: 8,
                  ),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.82,
                ),
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => context.push('/artist', extra: artist),
                    child: Column(
                      children: [
                        Expanded(
                          child: CachedArtwork(
                            id: artist.id,
                            type: ArtworkType.ARTIST,
                            size: double.infinity,
                            borderRadius: 999,
                            fallbackIcon: Icons.person_rounded,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          Formatters.formatTrackCount(artist.songCount),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
              : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 160, top: 8),
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    child: Material(
                      color: p.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: p.hairline),
                      ),
                      child: ListTile(
                        leading: CachedArtwork(
                          id: artist.id,
                          type: ArtworkType.ARTIST,
                          size: 48,
                          borderRadius: 999,
                          fallbackIcon: Icons.person_rounded,
                        ),
                        title: Text(
                          artist.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: p.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          Formatters.formatTrackCount(artist.songCount),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: p.textTertiary,
                        ),
                        onTap: () => context.push('/artist', extra: artist),
                      ),
                    ),
                  );
                },
              ),
    );
  }

  // ================= GENRES / YEARS =================
  Widget _buildGenresTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final genres = state.genres;
    if (genres.isEmpty) {
      return _buildEmpty(
        context,
        title: 'No Genres Found',
        subtitle: 'Scan your media library to view all song genres.',
        icon: Icons.style_rounded,
      );
    }
    return _chipCategoryGrid(
      context,
      count: genres.length,
      builder: (context, i) {
        final g = genres[i];
        return _CategoryCard(
          icon: Icons.style_rounded,
          title: g.name,
          subtitle: Formatters.formatTrackCount(g.songCount),
          color: p.accent,
          onTap: () => context.push('/genre', extra: g),
        );
      },
    );
  }

  Widget _buildYearsTab(BuildContext context, LibraryState state) {
    final years = state.years;
    if (years.isEmpty) {
      return _buildEmpty(
        context,
        title: 'No Years Found',
        subtitle: 'Scan your media library to view release years.',
        icon: Icons.calendar_today_rounded,
      );
    }
    return _chipCategoryGrid(
      context,
      count: years.length,
      builder: (context, i) {
        final y = years[i];
        return _CategoryCard(
          icon: Icons.calendar_today_rounded,
          title: '${y.year}',
          subtitle: Formatters.formatTrackCount(y.songCount),
          color: const Color(0xFF40C4FF),
          onTap: () => context.push('/year', extra: y),
        );
      },
    );
  }

  Widget _chipCategoryGrid(
    BuildContext context, {
    required int count,
    required Widget Function(BuildContext, int) builder,
  }) {
    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          Adaptive.pagePadding(context),
          16,
          Adaptive.pagePadding(context),
          160,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Adaptive.gridColumns(
            context,
            minItemWidth: 160,
            phoneColumns: 2,
          ),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.4,
        ),
        itemCount: count,
        itemBuilder: builder,
      ),
    );
  }

  // ================= FAVORITES =================
  Widget _buildFavoritesTab(
    BuildContext context,
    LibraryState state,
    PlayerCubit playerCubit,
  ) {
    final p = context.palette;
    final cubit = context.read<LibraryCubit>();
    // F-06: cached split â€” recomputed only when state.favorites identity
    // changes, instead of two O(n) passes per build.
    _ensureFavoritesDerivedCaches(state);
    final localFavorites = _localFavoritesCache;
    final onlineFavorites = _onlineFavoritesCache;

    final currentFavorites =
        _favTabFilter == 0 ? localFavorites : onlineFavorites;
    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: Column(
        children: [
          // ---------- Sub Tabs Switcher (Local / Online) ----------
          Padding(
            padding: EdgeInsets.fromLTRB(
              Adaptive.pagePadding(context),
              12,
              Adaptive.pagePadding(context),
              8,
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _FavTabButton(
                      label: context.l10n.local,
                      count: localFavorites.length,
                      icon: Icons.folder_rounded,
                      isSelected: _favTabFilter == 0,
                      onTap: () => setState(() => _favTabFilter = 0),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _FavTabButton(
                      label: context.l10n.online,
                      count: onlineFavorites.length,
                      icon: Icons.cloud_rounded,
                      isSelected: _favTabFilter == 1,
                      onTap: () => setState(() => _favTabFilter = 1),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------- Quick Play Header (if songs exist in current tab) ----------
          if (currentFavorites.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: 4,
              ),
              child: Row(
                children: [
                  Text(
                    context.l10n.tracksCount(currentFavorites.length),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed:
                        () => playerCubit.playSong(
                          currentFavorites.first,
                          queue: currentFavorites,
                        ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(context.l10n.playAll),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: p.accent.withValues(alpha: 0.15),
                      foregroundColor: p.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      final shuffled = List<SongsTableData>.from(
                        currentFavorites,
                      )..shuffle();
                      playerCubit.playSong(shuffled.first, queue: shuffled);
                    },
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: p.surfaceContainerHigh,
                      foregroundColor: p.textPrimary,
                    ),
                    tooltip: context.l10n.shuffle,
                  ),
                  if (AppConfig.ytmEnabled) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed:
                          () => _downloadFavorites(context, currentFavorites),
                      icon: const Icon(Icons.download_rounded, size: 19),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: p.accent.withValues(alpha: 0.15),
                        foregroundColor: p.accent,
                      ),
                      tooltip: 'Download All Liked Songs',
                    ),
                  ],
                  if (_favTabFilter == 1 && AppConfig.ytmEnabled) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _syncYtmLikes(context),
                      icon: const Icon(Icons.sync_rounded, size: 19),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: p.accent.withValues(alpha: 0.15),
                        foregroundColor: p.accent,
                      ),
                      tooltip: context.l10n.syncYouTubeMusic,
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _showImportYtmFavoritesDialog(context),
                      icon: const Icon(Icons.link_rounded, size: 20),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: p.surfaceContainerHigh,
                        foregroundColor: p.textPrimary,
                      ),
                      tooltip: context.l10n.importByPlaylistLink,
                    ),
                  ],
                ],
              ),
            ),

          // ---------- Content (List / Grid or Empty State) ----------
          Expanded(
            child:
                currentFavorites.isEmpty
                    ? CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildFavoritesEmptyState(
                            context,
                            p,
                            _favTabFilter,
                          ),
                        ),
                      ],
                    )
                    : (isGrid
                        ? GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            Adaptive.pagePadding(context),
                            8,
                            Adaptive.pagePadding(context),
                            160,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: Adaptive.gridColumns(
                                  context,
                                  minItemWidth: 155,
                                ),
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 18,
                                childAspectRatio: 0.76,
                              ),
                          itemCount: currentFavorites.length,
                          itemBuilder: (context, index) {
                            final song = currentFavorites[index];
                            return _buildFavoriteGridCard(
                              context,
                              song,
                              currentFavorites,
                              p,
                              playerCubit,
                            );
                          },
                        )
                        : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(
                            bottom: 160,
                            top: 4,
                            left: 4,
                            right: 4,
                          ),
                          itemCount: currentFavorites.length,
                          itemBuilder: (context, index) {
                            final song = currentFavorites[index];
                            return Dismissible(
                              key: ValueKey('fav_${song.id}'),
                              background: Container(
                                color: p.accentContainer,
                                alignment: AlignmentDirectional.centerStart,
                                padding: const EdgeInsetsDirectional.only(
                                  start: 24,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.playlist_play_rounded,
                                      color: p.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.l10n.playNext,
                                      style: TextStyle(
                                        color: p.accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              secondaryBackground: Container(
                                color: p.error.withValues(alpha: 0.2),
                                alignment: AlignmentDirectional.centerEnd,
                                padding: const EdgeInsetsDirectional.only(
                                  end: 24,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      context.l10n.delete,
                                      style: TextStyle(
                                        color: p.error,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color: p.error,
                                    ),
                                  ],
                                ),
                              ),
                              confirmDismiss: (direction) async {
                                if (direction == DismissDirection.startToEnd) {
                                  unawaited(playerCubit.playNext(song));
                                } else {
                                  unawaited(cubit.toggleFavorite(song.id));
                                }
                                return false;
                              },
                              child: SongTile(
                                song: song,
                                index: index + 1,
                                selected: state.selectedSongIds.contains(
                                  song.id,
                                ),
                                onTap: () {
                                  if (state.isMultiSelectMode) {
                                    cubit.toggleSongSelection(song.id);
                                  } else {
                                    playerCubit.playSong(
                                      song,
                                      queue: currentFavorites,
                                    );
                                  }
                                },
                                onLongPress:
                                    () => cubit.toggleSongSelection(song.id),
                                onMorePressed:
                                    () => showModalBottomSheet<void>(
                                      context: context,
                                      useRootNavigator: true,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => SongInfoSheet(song: song),
                                    ),
                              ),
                            );
                          },
                        )),
          ),
        ],
      ),
    );
  }

  bool _isOnlineFavorite(SongsTableData s) {
    return s.source == SongSource.youtube ||
        (s.remoteId != null && s.remoteId!.isNotEmpty) ||
        s.isDownloaded == true;
  }

  Widget _buildFavoritesEmptyState(
    BuildContext context,
    PulsrPalette p,
    int tabIndex,
  ) {
    if (tabIndex == 0) {
      return EmptyStateWidget(
        icon: Icons.favorite_border_rounded,
        iconColor: p.favorite,
        title: context.l10n.noLocalFavorites,
        subtitle: context.l10n.noLocalFavoritesSubtitle,
        primaryActionLabel: context.l10n.songs,
        primaryActionIcon: Icons.library_music_rounded,
        onPrimaryAction: () => _tabController.animateTo(0),
      );
    } else {
      final ytmAccount = getIt<YtmAccountService>();
      final isYtmLoggedIn = ytmAccount.isLoggedIn;

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EmptyStateWidget(
            icon: Icons.cloud_sync_rounded,
            iconColor: p.accent,
            title:
                isYtmLoggedIn
                    ? context.l10n.ytmConnected
                    : context.l10n.noOnlineFavorites,
            subtitle:
                isYtmLoggedIn
                    ? 'Tap sync below to pull your latest YouTube Music Liked Songs library.'
                    : context.l10n.connectYtmSubtitle,
            primaryActionLabel:
                AppConfig.ytmEnabled
                    ? (isYtmLoggedIn
                        ? context.l10n.syncYouTubeMusic
                        : context.l10n.connectYtmAccount)
                    : context.l10n.navLibrary,
            primaryActionIcon:
                AppConfig.ytmEnabled
                    ? Icons.cloud_sync_rounded
                    : Icons.library_music_rounded,
            onPrimaryAction: () {
              if (AppConfig.ytmEnabled) {
                _syncYtmLikes(context);
              } else {
                _tabController.animateTo(0);
              }
            },
          ),
          if (AppConfig.ytmEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: () => _showImportYtmFavoritesDialog(context),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(context.l10n.importByPlaylistLink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: TextButton.icon(
                onPressed: () => context.push('/ytm-search'),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(context.l10n.searchYtm),
              ),
            ),
          ],
        ],
      );
    }
  }

  void _downloadFavorites(BuildContext context, List<SongsTableData> songs) {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No favorite songs to download.')),
      );
      return;
    }

    final downloadCubit =
        context.read<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();
    final queuedCount = downloadCubit.downloadAll(songs);

    if (queuedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Queued $queuedCount liked songs for download (3 active downloads)...',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final hasOnlineTracks = songs.any(
        (s) => s.remoteId != null && s.remoteId!.isNotEmpty,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasOnlineTracks
                ? 'All online liked songs are already downloaded or in progress.'
                : 'All songs in this list are already offline local tracks.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _syncYtmLikes(BuildContext context) async {
    final accountService = getIt<YtmAccountService>();
    if (!accountService.isLoggedIn) {
      final success = await YtmWebLoginSheet.show(context);
      if (success != true) return;
    }

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final authCubit = context.read<AuthCubit>();
    final libraryCubit = context.read<LibraryCubit>();

    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Syncing YouTube Music Liked Songs...'),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final count = await libraryCubit.syncYtmAccountLikes();
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Synced $count tracks from your YouTube Music Liked library!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        try {
          unawaited(authCubit.syncNow());
        } catch (e, st) {
          ErrorLogger.log('_syncYtmLikes failed', error: e, stackTrace: st, category: 'LibraryScreen');
        }
      }
    } catch (e) {
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        final isAuth =
            (e is YtmException && e.isAuth) ||
            e.toString().toLowerCase().contains('unauthenticated') ||
            e.toString().toLowerCase().contains('session expired') ||
            e.toString().toLowerCase().contains('not signed in');
        if (isAuth) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text(
                'YouTube Music session expired. Please sign in again.',
              ),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Sign In',
                onPressed: () => YtmWebLoginSheet.show(context),
              ),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Sync failed: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _showImportYtmFavoritesDialog(BuildContext context) {
    final p = context.palette;
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setSheetState) {
              final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
              return Container(
                padding: EdgeInsets.fromLTRB(24, 16, 24, bottomInset + 24),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.textTertiary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.cloud_download_rounded,
                            color: p.accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Import YouTube Music Favorites',
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Paste a playlist link or Liked playlist from YouTube Music',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: controller,
                      style: TextStyle(color: p.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'https://music.youtube.com/playlist?list=...',
                        hintStyle: TextStyle(
                          color: p.textTertiary,
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.link_rounded,
                          color: p.textTertiary,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.content_paste_rounded,
                            color: p.accent,
                            size: 18,
                          ),
                          tooltip: 'Paste from clipboard',
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              setSheetState(
                                () => controller.text = data!.text!.trim(),
                              );
                            }
                          },
                        ),
                        filled: true,
                        fillColor: p.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(color: p.error, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed:
                          isLoading
                              ? null
                              : () async {
                                final text = controller.text.trim();
                                if (text.isEmpty) {
                                  setSheetState(
                                    () =>
                                        errorText =
                                            'Please enter a playlist URL or ID',
                                  );
                                  return;
                                }
                                setSheetState(() {
                                  isLoading = true;
                                  errorText = null;
                                });

                                final libraryCubit =
                                    context.read<LibraryCubit>();
                                final authCubit = context.read<AuthCubit>();

                                try {
                                  final ytmService = getIt<YtmService>();
                                  var tracks = await ytmService
                                      .getPlaylistTracks(text);
                                  if (tracks.isEmpty &&
                                      (text.contains('list=LM') ||
                                          text.contains('list=LL') ||
                                          text == 'LM' ||
                                          text == 'LL')) {
                                    final ytmAccount =
                                        getIt<YtmAccountService>();
                                    if (ytmAccount.isLoggedIn) {
                                      tracks =
                                          await ytmAccount.fetchLikedSongs();
                                    }
                                  }

                                  if (tracks.isEmpty) {
                                    setSheetState(() {
                                      isLoading = false;
                                      errorText =
                                          'No tracks found. If this is your private Liked Music, please ensure you are signed in or tap "Sync".';
                                    });
                                    return;
                                  }

                                  final count = await libraryCubit
                                      .importYtmTracksAsFavorites(tracks);
                                  if (ctx.mounted &&
                                      Navigator.of(ctx).canPop()) {
                                    Navigator.of(ctx).pop();
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Successfully imported $count tracks to Online Favorites!',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    // Trigger cloud sync if authenticated
                                    try {
                                      unawaited(authCubit.syncNow());
                                    } catch (e, st) {
                                      ErrorLogger.log('canPop failed', error: e, stackTrace: st, category: 'LibraryScreen');
                                    }
                                  }
                                } catch (e) {
                                  setSheetState(() {
                                    isLoading = false;
                                    errorText = 'Failed to load playlist: $e';
                                  });
                                }
                              },
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child:
                          isLoading
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(
                                'Import Tracks',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _buildFavoriteGridCard(
    BuildContext context,
    SongsTableData song,
    List<SongsTableData> currentFavorites,
    PulsrPalette p,
    PlayerCubit playerCubit,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => playerCubit.playSong(song, queue: currentFavorites),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CachedArtwork(
                    id: song.id,
                    remoteUrl: song.remoteArtworkUrl,
                    type: ArtworkType.AUDIO,
                    size: double.infinity,
                    borderRadius: 18,
                  ),
                ),
                if (AppConfig.ytmEnabled &&
                    song.remoteId != null &&
                    song.remoteId!.isNotEmpty)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: YtmDownloadButton(
                        song: song,
                        activeColor: Colors.white,
                        iconColor: Colors.white,
                        iconSize: 18,
                      ),
                    ),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap:
                          () => context.read<LibraryCubit>().toggleFavorite(
                            song.id,
                          ),
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: p.favorite,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _FavTabButton extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FavTabButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.3),
                      blurRadius: 8,
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
              size: 16,
              color: isSelected ? p.onAccent : p.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? p.onAccent : p.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? p.onAccent.withValues(alpha: 0.25)
                        : p.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? p.onAccent : p.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
