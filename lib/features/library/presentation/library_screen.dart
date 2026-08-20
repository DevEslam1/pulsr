import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../core/utils/formatters.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_info_sheet.dart';
import '../../sheets/sort_filter_sheet.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import 'widgets/folder_browser_tab.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _songsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _songsScrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter, List<SongsTableData> songs) {
    final index =
        songs.indexWhere((s) => s.title.toUpperCase().startsWith(letter));
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
      builder: (context, state) {
        final cubit = context.read<LibraryCubit>();
        final playerCubit = context.read<PlayerCubit>();
        final isMultiSelect = state.isMultiSelectMode;

        return Scaffold(
          appBar: isMultiSelect
              ? AppBar(
                  leading: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: cubit.clearSelection),
                  title: Text('${state.selectedSongIds.length} Selected'),
                  actions: [
                    IconButton(
                        icon: const Icon(Icons.select_all_rounded),
                        tooltip: 'Select All',
                        onPressed: cubit.selectAllSongs),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded),
                      tooltip: 'Add to Playlist',
                      onPressed: () {
                        final selected = cubit.getSelectedSongs();
                        if (selected.isNotEmpty) {
                          showModalBottomSheet(
                            context: context,
                            useRootNavigator: true,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) =>
                                AddToPlaylistSheet(song: selected.first),
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
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Added ${selected.length} tracks to queue')));
                      },
                    ),
                  ],
                )
              : AppBar(
                  title: const Text('Library'),
                  actions: [
                    IconButton(
                      icon: Icon(state.viewMode == LibraryViewMode.list
                          ? Icons.grid_view_rounded
                          : Icons.view_list_rounded),
                      onPressed: cubit.toggleViewMode,
                    ),
                    IconButton(
                      icon: const Icon(Icons.sort_rounded),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => SortFilterSheet(
                          currentSort: state.sortBy,
                          ascending: state.ascending,
                          onApply: (sort, asc) => cubit.updateSort(sort, asc),
                        ),
                      ),
                    ),
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    physics: const BouncingScrollPhysics(),
                    tabs: const [
                      Tab(text: 'Songs'),
                      Tab(text: 'Albums'),
                      Tab(text: 'Artists'),
                      Tab(text: 'Favorites'),
                      Tab(text: 'Folders'),
                      Tab(text: 'Genres'),
                      Tab(text: 'Years'),
                    ],
                  ),
                ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSongsTab(context, state, cubit, playerCubit),
                  _buildAlbumsTab(context, state),
                  _buildArtistsTab(context, state),
                  _buildFavoritesTab(context, state, playerCubit),
                  const FolderBrowserTab(),
                  _buildGenresTab(context, state),
                  _buildYearsTab(context, state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon}) {
    return EmptyStateWidget(
      icon: icon,
      title: title,
      subtitle: subtitle,
      primaryActionLabel: 'Scan Device Storage',
      primaryActionIcon: Icons.center_focus_strong_rounded,
      onPrimaryAction: () async {
        final scanner = context.read<MediaScannerService>();
        final count = await scanner.scanDeviceLibrary();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Scan complete! $count tracks loaded.')));
        }
      },
    );
  }

  // ================= SONGS =================
  Widget _buildSongsTab(BuildContext context, LibraryState state,
      LibraryCubit cubit, PlayerCubit playerCubit) {
    final p = context.palette;
    final songs = state.songs;
    if (songs.isEmpty) {
      return _buildEmpty(context,
          title: 'No Songs Found',
          subtitle: 'Scan your local storage to find all offline music files.',
          icon: Icons.music_note_rounded);
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    if (isGrid) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
            Adaptive.pagePadding(context), 160),
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
          return InkWell(
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
                              child: Icon(Icons.check_circle_rounded,
                                  color: Colors.white, size: 36),
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
                            onTap: () => showModalBottomSheet(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => SongInfoSheet(song: song),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(6.0),
                              child: Icon(Icons.more_vert_rounded,
                                  color: Colors.white, size: 18),
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
                      fontSize: 13.5),
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
        },
      );
    }

    final showAlphabet = songs.length >= 15;
    final alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            final scanner = context.read<MediaScannerService>();
            await scanner.scanDeviceLibrary();
          },
          child: ListView.builder(
            controller: _songsScrollController,
            padding:
                const EdgeInsets.only(bottom: 160, top: 8, left: 4, right: 4),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return Dismissible(
                key: ValueKey('song_${song.id}'),
                background: Container(
                  color: p.accentContainer,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 24),
                  child: Row(children: [
                    Icon(Icons.playlist_play_rounded, color: p.accent),
                    const SizedBox(width: 8),
                    Text('Play Next',
                        style: TextStyle(
                            color: p.accent, fontWeight: FontWeight.w700))
                  ]),
                ),
                secondaryBackground: Container(
                  color: p.favorite.withValues(alpha: 0.2),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('Favorite',
                        style: TextStyle(
                            color: p.favorite, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_rounded, color: p.favorite)
                  ]),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    playerCubit.playNext(song);
                  } else {
                    cubit.toggleFavorite(song.id);
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
                  onMorePressed: () => showModalBottomSheet(
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
        if (showAlphabet)
          Positioned(
            right: 4,
            top: 8,
            bottom: 150,
            child: Container(
              width: 22,
              decoration: BoxDecoration(
                  color: p.surfaceContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: alphabet
                      .map((l) => InkWell(
                            onTap: () => _scrollToLetter(l, songs),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(l,
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: p.textTertiary)),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ================= ALBUMS (adaptive grid / list) =================
  Widget _buildAlbumsTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final albums = state.albums;
    if (albums.isEmpty) {
      return _buildEmpty(context,
          title: 'No Albums Found',
          subtitle: 'Scan your media library to view your albums.',
          icon: Icons.album_rounded);
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    if (!isGrid) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 160, top: 8),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
                    borderRadius: 12),
                title: Text(album.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: p.textPrimary)),
                subtitle: Text(
                    '${album.artist} • ${Formatters.formatTrackCount(album.songCount)}',
                    style: TextStyle(color: p.textSecondary, fontSize: 12)),
                trailing:
                    Icon(Icons.chevron_right_rounded, color: p.textTertiary),
                onTap: () => context.push('/album', extra: album),
              ),
            ),
          );
        },
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
          Adaptive.pagePadding(context), 160),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Adaptive.gridColumns(context, minItemWidth: 168),
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
                      borderRadius: 18),
                ),
              ),
              const SizedBox(height: 9),
              Text(album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(
                  '${album.artist} • ${Formatters.formatTrackCount(album.songCount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
            ],
          ),
        );
      },
    );
  }

  // ================= ARTISTS =================
  Widget _buildArtistsTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final artists = state.artists;
    if (artists.isEmpty) {
      return _buildEmpty(context,
          title: 'No Artists Found',
          subtitle: 'Scan your media library to view all artists.',
          icon: Icons.person_rounded);
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    if (!isGrid) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 160, top: 8),
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
                    fallbackIcon: Icons.person_rounded),
                title: Text(artist.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: p.textPrimary)),
                subtitle: Text(Formatters.formatTrackCount(artist.songCount),
                    style: TextStyle(color: p.textSecondary, fontSize: 12)),
                trailing:
                    Icon(Icons.chevron_right_rounded, color: p.textTertiary),
                onTap: () => context.push('/artist', extra: artist),
              ),
            ),
          );
        },
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
          Adaptive.pagePadding(context), 160),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Adaptive.gridColumns(context,
            minItemWidth: 150, phoneColumns: 3, maxColumns: 8),
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
                    fallbackIcon: Icons.person_rounded),
              ),
              const SizedBox(height: 9),
              Text(artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              Text(Formatters.formatTrackCount(artist.songCount),
                  style: TextStyle(color: p.textSecondary, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  // ================= GENRES / YEARS =================
  Widget _buildGenresTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final genres = state.genres;
    if (genres.isEmpty) {
      return _buildEmpty(context,
          title: 'No Genres Found',
          subtitle: 'Scan your media library to view all song genres.',
          icon: Icons.style_rounded);
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
      return _buildEmpty(context,
          title: 'No Years Found',
          subtitle: 'Scan your media library to view release years.',
          icon: Icons.calendar_today_rounded);
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

  Widget _chipCategoryGrid(BuildContext context,
      {required int count,
      required Widget Function(BuildContext, int) builder}) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
          Adaptive.pagePadding(context), 160),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            Adaptive.gridColumns(context, minItemWidth: 160, phoneColumns: 2),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3.4,
      ),
      itemCount: count,
      itemBuilder: builder,
    );
  }

  // ================= FAVORITES =================
  Widget _buildFavoritesTab(
      BuildContext context, LibraryState state, PlayerCubit playerCubit) {
    final p = context.palette;
    final favorites = state.favorites;
    if (favorites.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.favorite_border_rounded,
        iconColor: p.favorite,
        title: 'No Favorite Tracks Yet',
        subtitle: 'Heart songs from your library to quickly access them here.',
        primaryActionLabel: 'Explore Songs',
        primaryActionIcon: Icons.library_music_rounded,
        onPrimaryAction: () => _tabController.animateTo(0),
      );
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    if (isGrid) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
            Adaptive.pagePadding(context), 160),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Adaptive.gridColumns(context, minItemWidth: 155),
          crossAxisSpacing: 14,
          mainAxisSpacing: 18,
          childAspectRatio: 0.76,
        ),
        itemCount: favorites.length,
        itemBuilder: (context, index) {
          final song = favorites[index];
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => playerCubit.playSong(song, queue: favorites),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedArtwork(
                          id: song.id,
                          type: ArtworkType.AUDIO,
                          size: double.infinity,
                          borderRadius: 18,
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
                            onTap: () => context
                                .read<LibraryCubit>()
                                .toggleFavorite(song.id),
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Icon(Icons.favorite_rounded,
                                  color: p.favorite, size: 18),
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
                      fontSize: 13.5),
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
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 160, top: 8),
      children: [
        for (final song in favorites)
          SongTile(
            song: song,
            subtitleOverride: '${song.artist} • ${song.album}',
            onTap: () => playerCubit.playSong(song, queue: favorites),
            trailing: IconButton(
              icon: Icon(Icons.favorite_rounded, color: p.favorite, size: 21),
              onPressed: () =>
                  context.read<LibraryCubit>().toggleFavorite(song.id),
            ),
          ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap});

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
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
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
