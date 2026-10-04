import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
// lib/features/library/presentation/favorites_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/song_classification.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dismissible.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _isSearchOpen = false;
  int _favTabFilter = 0; // 0: Local, 1: Online

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

  void _downloadFavorites(BuildContext context, List<SongsTableData> songs) {
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
    final queuedCount = downloadCubit.downloadAll(songs);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queuedCount > 0
              ? '${context.l10n.browseQueued} $queuedCount ${context.l10n.browseTracksForDownload}'
              : context.l10n.browseAllTracksAlreadyDownloaded,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final playerCubit = context.read<PlayerCubit>();
    final libraryCubit = context.read<LibraryCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const PulsrBackButton(),
          title: _isSearchOpen
              ? PulsrSearchField(
                  controller: _searchController,
                  autofocus: true,
                  hintText: '${l10n.search}...',
                  onChanged: (v) {
                    if (mounted) setState(() => _searchQuery = v.trim());
                  },
                  onClear: () {
                    if (mounted) setState(() => _searchQuery = '');
                  },
                )
              : Text(
                  l10n.favorites,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
          actions: [
            IconButton(
              constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget),
              icon: Icon(
                _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                color: p.textPrimary,
              ),
              tooltip: _isSearchOpen ? context.l10n.close : context.l10n.search,
              onPressed: () {
                _searchDebounce?.cancel();
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

            final currentTabFavorites =
                _favTabFilter == 0 ? localFavorites : onlineFavorites;
            final songs = _filterSongs(currentTabFavorites);

            final totalDurationMs = songs.fold<int>(
              0,
              (acc, s) => acc + s.durationMs,
            );

            return Center(
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: RefreshIndicator(
                  color: p.accent,
                  backgroundColor: p.surfaceContainer,
                  onRefresh: () => context.read<LibraryCubit>().init(),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // ---------- Local / Online Tabs Switcher ----------
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            Adaptive.pagePadding(context),
                            8,
                            Adaptive.pagePadding(context),
                            12,
                          ),
                          child: PulsrSegmentedControl(
                            selectedIndex: _favTabFilter,
                            onChanged: (i) => setState(() => _favTabFilter = i),
                            segments: [
                              PulsrSegment(
                                label: l10n.local,
                                icon: Icons.folder_rounded,
                                count: localFavorites.length,
                              ),
                              PulsrSegment(
                                label: l10n.online,
                                icon: Icons.cloud_rounded,
                                count: onlineFavorites.length,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ---------- Compact Tinted Header Card ----------
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            Adaptive.pagePadding(context),
                            0,
                            Adaptive.pagePadding(context),
                            14,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: (p.isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.05),
                              borderRadius: AppRadii.r18All,
                              border: Border.all(
                                color: (p.isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                if (songs.isNotEmpty)
                                  CachedArtwork(
                                    id: songs.first.id,
                                    albumId: songs.first.albumId,
                                    remoteUrl: songs.first.remoteArtworkUrl ??
                                        songs.first.artworkUri,
                                    size: 52,
                                    borderRadius: AppRadii.r12,
                                  )
                                else
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: (_favTabFilter == 0
                                              ? p.favorite
                                              : AppColors.catAudio)
                                          .withValues(alpha: 0.15),
                                      borderRadius: AppRadii.r12All,
                                    ),
                                    child: Icon(
                                      _favTabFilter == 0
                                          ? Icons.favorite_rounded
                                          : Icons.cloud_rounded,
                                      color: _favTabFilter == 0
                                          ? p.favorite
                                          : p.accent,
                                      size: 26,
                                    ),
                                  ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${Formatters.formatTrackCount(songs.length).toUpperCase()}${songs.isNotEmpty ? " • ${Formatters.formatDuration(Duration(milliseconds: totalDurationMs)).toUpperCase()}" : ""}',
                                        style: TextStyle(
                                          fontSize: AppFontSize.tiny,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                          color: p.textTertiary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _favTabFilter == 0
                                            ? l10n.favorites
                                            : '${l10n.online} ${l10n.favorites}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: AppFontSize.callout,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l10n.tracksCount(songs.length),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: AppFontSize.label,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (songs.isNotEmpty) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  IconButton.filledTonal(
                                    constraints: const BoxConstraints(
                                        minWidth: AppSpacing.minTouchTarget,
                                        minHeight: AppSpacing.minTouchTarget),
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          p.accent.withValues(alpha: 0.15),
                                      foregroundColor: p.accent,
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded,
                                        size: 22),
                                    tooltip: l10n.playAll,
                                    onPressed: () => playerCubit.playSong(
                                      songs.first,
                                      queue: songs,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  IconButton.filledTonal(
                                    constraints: const BoxConstraints(
                                        minWidth: AppSpacing.minTouchTarget,
                                        minHeight: AppSpacing.minTouchTarget),
                                    style: IconButton.styleFrom(
                                      backgroundColor: p.surfaceContainerHigh,
                                      foregroundColor: p.textPrimary,
                                    ),
                                    icon: const Icon(Icons.shuffle_rounded,
                                        size: 18),
                                    tooltip: l10n.shuffle,
                                    onPressed: () {
                                      final shuffled =
                                          List<SongsTableData>.from(songs)
                                            ..shuffle();
                                      playerCubit.playSong(
                                        shuffled.first,
                                        queue: shuffled,
                                      );
                                    },
                                  ),
                                  if (_favTabFilter == 1 &&
                                      AppConfig.ytmEnabled &&
                                      songs.any((s) =>
                                          s.remoteId != null &&
                                          s.remoteId!.isNotEmpty)) ...[
                                    const SizedBox(width: AppSpacing.xxs),
                                    IconButton.filledTonal(
                                      constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget),
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            p.accent.withValues(alpha: 0.15),
                                        foregroundColor: p.accent,
                                      ),
                                      icon: const Icon(Icons.download_rounded,
                                          size: 18),
                                      tooltip: context.l10n
                                          .browseDownloadAllOnlineFavorites,
                                      onPressed: () =>
                                          _downloadFavorites(context, songs),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ---------- Song List or Empty State ----------
                      if (currentTabFavorites.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s40),
                            child: Center(
                              child: PulsrEmptyState(
                                icon: _favTabFilter == 0
                                    ? Icons.favorite_border_rounded
                                    : Icons.cloud_off_rounded,
                                iconColor:
                                    _favTabFilter == 0 ? p.favorite : p.accent,
                                title: _favTabFilter == 0
                                    ? l10n.noLocalFavorites
                                    : l10n.noOnlineFavorites,
                                subtitle: _favTabFilter == 0
                                    ? l10n.noLocalFavoritesSubtitle
                                    : l10n.connectYtmSubtitle,
                              ),
                            ),
                          ),
                        )
                      else if (songs.isEmpty && _searchQuery.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s40),
                            child: Center(
                              child: PulsrEmptyState(
                                icon: Icons.search_off_rounded,
                                title: context.l10n.browseNoSongsMatch,
                                subtitle: '"$_searchQuery"',
                                primaryActionLabel: context.l10n.clear,
                                primaryActionIcon: Icons.clear_rounded,
                                onPrimaryAction: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                            ),
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            return PulsrDismissible(
                              key: ValueKey('fav_screen_${song.id}'),
                              startToEndLabel: context.l10n.playNext,
                              endToStartLabel: context.l10n.removeFromFavorites,
                              backgroundBuilder: (context, isConfirming) =>
                                  PulsrDismissible.buildActionBackground(
                                context: context,
                                icon: Icons.playlist_play_rounded,
                                label: context.l10n.playNext,
                                color: p.accent,
                                backgroundColor: p.accentContainer,
                                isConfirming: isConfirming,
                              ),
                              secondaryBackgroundBuilder:
                                  (context, isConfirming) =>
                                      PulsrDismissible.buildActionBackground(
                                context: context,
                                icon: Icons.favorite_border_rounded,
                                label: context.l10n.removeFromFavorites,
                                color: p.favorite,
                                backgroundColor:
                                    p.favorite.withValues(alpha: 0.2),
                                isConfirming: isConfirming,
                                isEnd: true,
                              ),
                              onConfirm: (direction) async {
                                if (direction == DismissDirection.startToEnd) {
                                  playerCubit.playNext(song);
                                } else {
                                  libraryCubit.toggleFavorite(song.id);
                                  ScaffoldMessenger.of(context)
                                      .clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(song.title),
                                      action: SnackBarAction(
                                        label: context.l10n.undo,
                                        onPressed: () => libraryCubit
                                            .toggleFavorite(song.id),
                                      ),
                                    ),
                                  );
                                }
                                return false;
                              },
                              child: SongTile(
                                song: song,
                                index: index,
                                onTap: () =>
                                    playerCubit.playSong(song, queue: songs),
                                onMorePressed: () =>
                                    SongInfoSheet.show(context, song: song),
                                trailing: IconButton(
                                  constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget),
                                  tooltip: context.l10n.favorite,
                                  icon: Icon(
                                    song.isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: song.isFavorite
                                        ? p.favorite
                                        : p.textTertiary,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      libraryCubit.toggleFavorite(song.id),
                                ),
                              ),
                            );
                          },
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                            height: PulsrLayoutMetrics.scrollBottom(context)),
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
