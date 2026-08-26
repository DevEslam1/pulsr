import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../core/utils/formatters.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_info_sheet.dart';
import '../../sheets/sort_filter_sheet.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
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
  int _favTabFilter = 0; // 0: Local, 1: Online

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
                    tabs: [
                      Tab(text: context.l10n.songs),
                      const Tab(text: 'Downloaded'),
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
              child: RefreshIndicator(
                onRefresh: () async {
                  final count = await context.read<SettingsCubit>().rescanLibrary();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.scanResult(count)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSongsTab(context, state, cubit, playerCubit),
                    _buildDownloadedTab(context, state, cubit, playerCubit),
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

  // ================= DOWNLOADED =================
  Widget _buildDownloadedTab(
    BuildContext context,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    final p = context.palette;
    final downloaded = state.songs.where((s) => _isOnlineDownload(s)).toList();

    if (downloaded.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.cloud_download_rounded,
        title: 'No Downloads Yet',
        subtitle: 'Download your favorite songs from YouTube Music to listen offline anywhere.',
        primaryActionLabel: 'Explore Online Music',
        primaryActionIcon: Icons.travel_explore_rounded,
        onPrimaryAction: () => context.go('/'),
      );
    }

    return Column(
      children: [
        // ---------- Header Card with Play All & Shuffle ----------
        Padding(
          padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 12, Adaptive.pagePadding(context), 8),
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
                  child: Icon(Icons.download_done_rounded, color: p.accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline Downloads',
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${downloaded.length} tracks • Available offline',
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
                  tooltip: 'Play All',
                  onPressed: () => playerCubit.playSong(downloaded.first, queue: downloaded),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: p.surfaceContainerHigh,
                    foregroundColor: p.textPrimary,
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 20),
                  tooltip: 'Shuffle',
                  onPressed: () {
                    final shuffled = List<SongsTableData>.from(downloaded)..shuffle();
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
            padding: const EdgeInsets.only(bottom: 160, top: 4, left: 4, right: 4),
            itemCount: downloaded.length,
            itemBuilder: (context, index) {
              final song = downloaded[index];
              return Dismissible(
                key: ValueKey('dl_${song.id}'),
                background: Container(
                  color: p.accentContainer,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 24),
                  child: Row(children: [
                    Icon(Icons.playlist_play_rounded, color: p.accent),
                    const SizedBox(width: 8),
                    Text('Play Next', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
                  ]),
                ),
                secondaryBackground: Container(
                  color: p.favorite.withValues(alpha: 0.2),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('Favorite', style: TextStyle(color: p.favorite, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_rounded, color: p.favorite),
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
      ],
    );
  }

  bool _isOnlineDownload(SongsTableData s) {
    return (s.isDownloaded ?? false) ||
           s.source == SongSource.youtube ||
           (s.remoteId != null && s.remoteId!.isNotEmpty) ||
           (s.remoteArtworkUrl != null && s.remoteArtworkUrl!.isNotEmpty) ||
           s.path.contains('ytdl_') ||
           s.path.toLowerCase().contains('pulsr');
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
    final allFavorites = state.favorites;
    final localFavorites = allFavorites.where((s) => !_isOnlineFavorite(s)).toList();
    final onlineFavorites = allFavorites.where((s) => _isOnlineFavorite(s)).toList();

    final currentFavorites = _favTabFilter == 0 ? localFavorites : onlineFavorites;
    final isGrid = state.viewMode == LibraryViewMode.grid;

    return Column(
      children: [
        // ---------- Sub Tabs Switcher (Local / Online) ----------
        Padding(
          padding: EdgeInsets.fromLTRB(
              Adaptive.pagePadding(context), 12, Adaptive.pagePadding(context), 8),
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
                    label: 'Local',
                    count: localFavorites.length,
                    icon: Icons.folder_rounded,
                    isSelected: _favTabFilter == 0,
                    onTap: () => setState(() => _favTabFilter = 0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _FavTabButton(
                    label: 'Online',
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
                  '${currentFavorites.length} ${currentFavorites.length == 1 ? 'Track' : 'Tracks'}',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => playerCubit.playSong(currentFavorites.first,
                      queue: currentFavorites),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play All'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: p.accent.withValues(alpha: 0.15),
                    foregroundColor: p.accent,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () {
                    final shuffled =
                        List<SongsTableData>.from(currentFavorites)..shuffle();
                    playerCubit.playSong(shuffled.first, queue: shuffled);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: p.surfaceContainerHigh,
                    foregroundColor: p.textPrimary,
                  ),
                  tooltip: 'Shuffle',
                ),
                if (AppConfig.ytmEnabled) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _downloadFavorites(context, currentFavorites),
                    icon: const Icon(Icons.download_rounded, size: 19),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: p.accent.withValues(alpha: 0.15),
                      foregroundColor: p.accent,
                    ),
                    tooltip: 'Download All Liked Songs (3 active downloads)',
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
                    tooltip: 'Sync YouTube Music Account',
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
                    tooltip: 'Import YTM Playlist Link',
                  ),
                ],
              ],
            ),
          ),

        // ---------- Content (List / Grid or Empty State) ----------
        Expanded(
          child: currentFavorites.isEmpty
              ? _buildFavoritesEmptyState(context, p, _favTabFilter)
              : (isGrid
                  ? GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        Adaptive.pagePadding(context),
                        8,
                        Adaptive.pagePadding(context),
                        160,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            Adaptive.gridColumns(context, minItemWidth: 155),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 18,
                        childAspectRatio: 0.76,
                      ),
                      itemCount: currentFavorites.length,
                      itemBuilder: (context, index) {
                        final song = currentFavorites[index];
                        return _buildFavoriteGridCard(
                            context, song, currentFavorites, p, playerCubit);
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                          bottom: 160, top: 4, left: 4, right: 4),
                      itemCount: currentFavorites.length,
                      itemBuilder: (context, index) {
                        final song = currentFavorites[index];
                        return SongTile(
                          song: song,
                          subtitleOverride: '${song.artist} • ${song.album}',
                          onTap: () => playerCubit.playSong(song,
                              queue: currentFavorites),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (AppConfig.ytmEnabled &&
                                  song.remoteId != null &&
                                  song.remoteId!.isNotEmpty)
                                YtmDownloadButton(song: song),
                              IconButton(
                                icon: Icon(Icons.favorite_rounded,
                                    color: p.favorite, size: 21),
                                onPressed: () => context
                                    .read<LibraryCubit>()
                                    .toggleFavorite(song.id),
                              ),
                            ],
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  bool _isOnlineFavorite(SongsTableData s) {
    return s.source == SongSource.youtube ||
        (s.remoteId != null && s.remoteId!.isNotEmpty) ||
        (s.remoteArtworkUrl != null && s.remoteArtworkUrl!.isNotEmpty) ||
        s.path.contains('ytdl_') ||
        s.path.toLowerCase().contains('pulsr');
  }

  Widget _buildFavoritesEmptyState(
      BuildContext context, PulsrPalette p, int tabIndex) {
    if (tabIndex == 0) {
      return EmptyStateWidget(
        icon: Icons.favorite_border_rounded,
        iconColor: p.favorite,
        title: 'No Local Favorites',
        subtitle:
            'Tap the heart icon on any of your local tracks to add them here.',
        primaryActionLabel: 'Explore Songs',
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
            title: isYtmLoggedIn ? 'YouTube Music Connected' : 'No Online Favorites',
            subtitle: isYtmLoggedIn
                ? 'Tap sync below to pull your latest YouTube Music Liked Songs library.'
                : 'Sign in to YouTube Music to automatically sync your Liked Music library.',
            primaryActionLabel: AppConfig.ytmEnabled
                ? (isYtmLoggedIn
                    ? 'Sync Liked Songs Now'
                    : 'Connect YouTube Music')
                : 'Explore Library',
            primaryActionIcon: AppConfig.ytmEnabled
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
                label: const Text('Import by Playlist Link'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: TextButton.icon(
                onPressed: () => context.push('/ytm-search'),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Search YouTube Music Directly'),
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
              'Queued $queuedCount liked songs for download (3 active downloads)...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final hasOnlineTracks =
          songs.any((s) => s.remoteId != null && s.remoteId!.isNotEmpty);
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
                  strokeWidth: 2, color: Colors.white),
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
                'Synced $count tracks from your YouTube Music Liked library!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        try {
          authCubit.syncNow();
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showImportYtmFavoritesDialog(BuildContext context) {
    final p = context.palette;
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, bottomInset + 24),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
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
                      child: Icon(Icons.cloud_download_rounded,
                          color: p.accent, size: 22),
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
                    hintStyle: TextStyle(color: p.textTertiary, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.link_rounded, color: p.textTertiary, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.content_paste_rounded,
                          color: p.accent, size: 18),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setSheetState(
                              () => controller.text = data!.text!.trim());
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
                  onPressed: isLoading
                      ? null
                      : () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) {
                            setSheetState(() =>
                                errorText = 'Please enter a playlist URL or ID');
                            return;
                          }
                          setSheetState(() {
                            isLoading = true;
                            errorText = null;
                          });

                          final libraryCubit = context.read<LibraryCubit>();
                          final authCubit = context.read<AuthCubit>();

                          try {
                            final ytmService = getIt<YtmService>();
                            var tracks =
                                await ytmService.getPlaylistTracks(text);
                            if (tracks.isEmpty &&
                                (text.contains('list=LM') ||
                                    text.contains('list=LL') ||
                                    text == 'LM' ||
                                    text == 'LL')) {
                              final ytmAccount = getIt<YtmAccountService>();
                              if (ytmAccount.isLoggedIn) {
                                tracks = await ytmAccount.fetchLikedSongs();
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

                            final count =
                                await libraryCubit.importYtmTracksAsFavorites(tracks);
                            if (ctx.mounted && Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).pop();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Successfully imported $count tracks to Online Favorites!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              // Trigger cloud sync if authenticated
                              try {
                                authCubit.syncNow();
                              } catch (_) {}
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
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Import Tracks',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
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
