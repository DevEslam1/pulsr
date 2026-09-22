// lib/features/library/presentation/favorites_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/song_classification.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dismissible.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
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
  void deactivate() {
    // FIX-M2: Cancel debounce timer in deactivate to prevent setState while inactive
    _searchDebounce?.cancel();
    super.deactivate();
  }

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

  void _downloadFavorites(
      BuildContext context, List<SongsTableData> songs) {
    if (songs.isEmpty) return;
    final downloadCubit = context.read<YtmDownloadCubit>();
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
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodyLarge),
                  decoration: InputDecoration(
                    hintText: '${l10n.search}...',
                    hintStyle: TextStyle(color: p.textTertiary),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() => _searchQuery = v.trim());
                    });
                  },
                )
              : Text(
                  l10n.favorites,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
          actions: [
              IconButton(
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
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
                  children: [
                    // ---------- Local / Online Tabs Switcher ----------
                    Padding(
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

                    // ---------- Hero Banner Card ----------
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        Adaptive.pagePadding(context),
                        0,
                        Adaptive.pagePadding(context),
                        16,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.s20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _favTabFilter == 0
                                ? [
                                    p.favorite.withValues(alpha: 0.88),
                                    AppColors.roseDeep,
                                  ]
                                : [
                                    AppColors.netflixRed,
                                    AppColors.ytRedDeep,
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.r24),
                          boxShadow: [
                            BoxShadow(
                              color: (_favTabFilter == 0
                                      ? p.favorite
                                      : AppColors.netflixRed)
                                  .withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(AppRadii.r14),
                                  ),
                                  child: Icon(
                                    _favTabFilter == 0
                                        ? Icons.favorite_rounded
                                        : Icons.cloud_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const Spacer(),
                                if (_favTabFilter == 1 &&
                                    AppConfig.ytmEnabled &&
                                    songs.any((s) =>
                                        s.remoteId != null &&
                                        s.remoteId!.isNotEmpty))
                                  IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white
                                          .withValues(alpha: 0.2),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.download_rounded,
                                        size: 20),
                                    tooltip:
                                        context.l10n.browseDownloadAllOnlineFavorites,
                                    onPressed: () =>
                                        _downloadFavorites(context, songs),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              _favTabFilter == 0
                                  ? l10n.favorites
                                  : '${l10n.online} ${l10n.favorites}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppFontSize.headline,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              '${l10n.tracksCount(songs.length)}${songs.isNotEmpty ? ' • ${Formatters.formatDuration(Duration(milliseconds: totalDurationMs))}' : ''}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: AppFontSize.bodySmall,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (songs.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.md),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black87,
                                        padding: const EdgeInsets.symmetric(

                                            vertical: AppSpacing.sm),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(AppRadii.r14),
                                        ),
                                      ),
                                      icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 24),
                                      label: Text(
                                        l10n.playAll,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800),
                                      ),
                                      onPressed: () => playerCubit.playSong(
                                        songs.first,
                                        queue: songs,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white
                                          .withValues(alpha: 0.2),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.all(AppSpacing.sm),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                          BorderRadius.circular(AppRadii.r14),
                                      ),
                                    ),
                                    icon: const Icon(Icons.shuffle_rounded,
                                        size: 22),
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
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // ---------- Song List or Empty State ----------
                    if (currentTabFavorites.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s40),
                        child: Center(
                          child: EmptyStateWidget(
                            icon: _favTabFilter == 0
                                ? Icons.favorite_border_rounded
                                : Icons.cloud_off_rounded,
                            iconColor: _favTabFilter == 0
                                ? p.favorite
                                : p.accent,
                            title: _favTabFilter == 0
                                ? l10n.noLocalFavorites
                                : l10n.noOnlineFavorites,
                            subtitle: _favTabFilter == 0
                                ? l10n.noLocalFavoritesSubtitle
                                : l10n.connectYtmSubtitle,
                          ),
                        ),
                      )
                    else if (songs.isEmpty && _searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: Text(
                            '${context.l10n.browseNoSongsMatch} "$_searchQuery"',
                            style: TextStyle(color: p.textSecondary),
                          ),
                        ),
                      )
                    else
                      ...List.generate(songs.length, (index) {
                        final song = songs[index];
                        return PulsrDismissible(
                          key: ValueKey('fav_screen_${song.id}'),
                          startToEndLabel: context.l10n.playNext,
                          endToStartLabel: context.l10n.delete,
                          backgroundBuilder: (context, isConfirming) =>
                              PulsrDismissible.buildActionBackground(
                            context: context,
                            icon: Icons.playlist_play_rounded,
                            label: context.l10n.playNext,
                            color: p.accent,
                            backgroundColor: p.accentContainer,
                            isConfirming: isConfirming,
                          ),
                          secondaryBackgroundBuilder: (context, isConfirming) =>
                              PulsrDismissible.buildActionBackground(
                            context: context,
                            icon: Icons.delete_outline_rounded,
                            label: context.l10n.delete,
                            color: p.error,
                            backgroundColor: p.error.withValues(alpha: 0.2),
                            isConfirming: isConfirming,
                            isEnd: true,
                          ),
                          onConfirm: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              playerCubit.playNext(song);
                            } else {
                              libraryCubit.toggleFavorite(song.id);
                            }
                            return false;
                          },
                          child: SongTile(
                            song: song,
                            index: index + 1,
                            onTap: () => playerCubit.playSong(song, queue: songs),
                            onMorePressed: () => SongInfoSheet.show(context, song: song),
                              trailing: IconButton(
                                tooltip: context.l10n.favorite,
                                icon: Icon(
                                  song.isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                color: song.isFavorite ? p.favorite : p.textTertiary,
                                size: 20,
                              ),
                              onPressed: () =>
                                  libraryCubit.toggleFavorite(song.id),
                            ),
                          ),
                        );
                      }),
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

