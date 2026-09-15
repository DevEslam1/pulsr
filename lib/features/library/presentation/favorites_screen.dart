// lib/features/library/presentation/favorites_screen.dart
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
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchOpen = false;
  int _favTabFilter = 0; // 0: Local, 1: Online

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
                  style: TextStyle(color: p.textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '${l10n.search}...',
                    hintStyle: TextStyle(color: p.textTertiary),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
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
                  padding: const EdgeInsets.only(bottom: 140),
                  children: [
                    // ---------- Local / Online Tabs Switcher ----------
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        Adaptive.pagePadding(context),
                        8,
                        Adaptive.pagePadding(context),
                        12,
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
                                label: l10n.local,
                                count: localFavorites.length,
                                icon: Icons.folder_rounded,
                                isSelected: _favTabFilter == 0,
                                onTap: () => setState(() => _favTabFilter = 0),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _FavTabButton(
                                label: l10n.online,
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

                    // ---------- Hero Banner Card ----------
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        Adaptive.pagePadding(context),
                        0,
                        Adaptive.pagePadding(context),
                        16,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _favTabFilter == 0
                                ? [
                                    p.favorite.withValues(alpha: 0.88),
                                    const Color(0xFFB0316B),
                                  ]
                                : [
                                    const Color(0xFFE50914),
                                    const Color(0xFF8B0000),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: (_favTabFilter == 0
                                      ? p.favorite
                                      : const Color(0xFFE50914))
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
                                    borderRadius: BorderRadius.circular(14),
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
                            const SizedBox(height: 16),
                            Text(
                              _favTabFilter == 0
                                  ? l10n.favorites
                                  : '${l10n.online} ${l10n.favorites}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${l10n.tracksCount(songs.length)}${songs.isNotEmpty ? ' • ${Formatters.formatDuration(Duration(milliseconds: totalDurationMs))}' : ''}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (songs.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black87,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
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
                                  const SizedBox(width: 12),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white
                                          .withValues(alpha: 0.2),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.all(12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                          BorderRadius.circular(14),
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
                        padding: const EdgeInsets.symmetric(vertical: 40),
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
                        padding: const EdgeInsets.all(32),
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
                        return SongTile(
                          song: song,
                          index: index + 1,
                          onTap: () => playerCubit.playSong(song, queue: songs),
                          onMorePressed: () {
                            showModalBottomSheet<void>(
                              context: context,
                              builder: (_) => SongInfoSheet(song: song),
                            );
                          },
                          trailing: IconButton(
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
          boxShadow: isSelected
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
                color: isSelected
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
