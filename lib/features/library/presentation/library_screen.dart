// lib/features/library/presentation/library_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../album_detail/presentation/album_detail_screen.dart';
import '../../artist_detail/presentation/artist_detail_screen.dart';
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

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _songsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _songsScrollController.dispose();
    super.dispose();
  }

  void _scrollToLetter(String letter, List<SongsTableData> songs) {
    final index = songs.indexWhere((s) => s.title.toUpperCase().startsWith(letter));
    if (index != -1 && _songsScrollController.hasClients) {
      const itemHeight = 72.0;
      final target = (index * itemHeight).clamp(0.0, _songsScrollController.position.maxScrollExtent);
      _songsScrollController.animateTo(
        target,
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
        final repository = context.read<MusicRepository>();
        final isMultiSelect = state.isMultiSelectMode;

        return Scaffold(
          appBar: isMultiSelect
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => cubit.clearSelection(),
                  ),
                  title: Text('${state.selectedSongIds.length} Selected'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.select_all_rounded),
                      tooltip: 'Select All',
                      onPressed: () => cubit.selectAllSongs(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded),
                      tooltip: 'Add to Playlist',
                      onPressed: () {
                        final selected = cubit.getSelectedSongs();
                        if (selected.isNotEmpty) {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => AddToPlaylistSheet(
                              song: selected.first,
                              repository: repository,
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
                          SnackBar(content: Text('Added ${selected.length} tracks to queue')),
                        );
                      },
                    ),
                  ],
                )
              : AppBar(
                  title: const Text(
                    'Library',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        state.viewMode == LibraryViewMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded,
                      ),
                      tooltip: 'Toggle View',
                      onPressed: () => cubit.toggleViewMode(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.sort_rounded),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => SortFilterSheet(
                            currentSort: state.sortBy,
                            ascending: state.ascending,
                            onApply: (sort, asc) => cubit.updateSort(sort, asc),
                          ),
                        );
                      },
                    ),
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    dividerColor: AppColors.outline,
                    tabs: const [
                      Tab(text: 'Songs'),
                      Tab(text: 'Albums'),
                      Tab(text: 'Artists'),
                      Tab(text: 'Favorites'),
                      Tab(text: 'Folders'),
                    ],
                  ),
                ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildSongsTab(context, state, cubit, playerCubit),
              _buildAlbumsTab(context, state),
              _buildArtistsTab(context, state),
              _buildFavoritesTab(context, state, cubit, playerCubit),
              const FolderBrowserTab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, {required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.music_off_rounded, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Device Storage', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () async {
                final scanner = context.read<MediaScannerService>();
                final count = await scanner.scanDeviceLibrary();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Scan complete! $count tracks loaded.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongsTab(
    BuildContext context,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    final songs = state.songs;
    if (songs.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'No Songs Found',
        subtitle: 'Scan your local storage to find all offline music files.',
      );
    }

    final showAlphabet = songs.length >= 15;
    final alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

    return Stack(
      children: [
        ListView.builder(
          controller: _songsScrollController,
          padding: EdgeInsets.only(
            bottom: 120,
            top: 8,
            right: showAlphabet ? 28 : 8,
            left: 4,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final isSelected = state.selectedSongIds.contains(song.id);

            return Dismissible(
              key: ValueKey('song_${song.id}'),
              background: Container(
                color: AppColors.primary.withValues(alpha: 0.25),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                child: const Row(
                  children: [
                    Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 28),
                    SizedBox(width: 8),
                    Text('Play Next', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              secondaryBackground: Container(
                color: AppColors.favorite.withValues(alpha: 0.25),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Favorite', style: TextStyle(color: AppColors.favorite, fontWeight: FontWeight.w700)),
                    SizedBox(width: 8),
                    Icon(Icons.favorite_rounded, color: AppColors.favorite, size: 28),
                  ],
                ),
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  playerCubit.playNext(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Playing "${song.title}" next')),
                  );
                } else {
                  cubit.toggleFavorite(song.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Toggled favorite for "${song.title}"')),
                  );
                }
                return false;
              },
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                selected: isSelected,
                selectedTileColor: AppColors.primary.withValues(alpha: 0.15),
                leading: isSelected
                    ? Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.black),
                      )
                    : CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 52, borderRadius: 12),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Text(
                  '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 22),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => SongInfoSheet(song: song),
                    );
                  },
                ),
                onLongPress: () {
                  cubit.toggleSongSelection(song.id);
                },
                onTap: () {
                  if (state.isMultiSelectMode) {
                    cubit.toggleSongSelection(song.id);
                  } else {
                    playerCubit.playSong(song, queue: songs);
                  }
                },
              ),
            );
          },
        ),

        // Fast-Scroll Alphabet Sidebar
        if (showAlphabet)
          Positioned(
            right: 4,
            top: 8,
            bottom: 120,
            child: Container(
              width: 20,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: alphabet.map((letter) {
                    return InkWell(
                      onTap: () => _scrollToLetter(letter, songs),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          letter,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAlbumsTab(BuildContext context, LibraryState state) {
    final albums = state.albums;
    if (albums.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'No Albums Found',
        subtitle: 'Scan your media library to view your albums.',
      );
    }

    if (state.viewMode == LibraryViewMode.list) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 120, top: 8),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return ListTile(
            leading: CachedArtwork(id: album.id, type: ArtworkType.ALBUM, size: 48, borderRadius: 10),
            title: Text(album.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('${album.artist} • ${album.songCount} tracks', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
              );
            },
          );
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.8,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CachedArtwork(
                  id: album.id,
                  type: ArtworkType.ALBUM,
                  size: double.infinity,
                  borderRadius: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                '${album.artist} • ${album.songCount} tracks',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtistsTab(BuildContext context, LibraryState state) {
    final artists = state.artists;
    if (artists.isEmpty) {
      return _buildEmptyState(
        context,
        title: 'No Artists Found',
        subtitle: 'Scan your media library to view all artists.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120, top: 8),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          leading: CachedArtwork(
            id: artist.id,
            type: ArtworkType.ARTIST,
            size: 52,
            borderRadius: 26,
            fallbackIcon: Icons.person_rounded,
          ),
          title: Text(
            artist.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            '${artist.songCount} tracks',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist)),
            );
          },
        );
      },
    );
  }

  Widget _buildFavoritesTab(
    BuildContext context,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    final favorites = state.favorites;
    if (favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, size: 52, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'No Favorite Tracks Yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Heart songs to quickly access them here.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120, top: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final song = favorites[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 52, borderRadius: 12),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            '${song.artist} • ${song.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.favorite_rounded, color: AppColors.favorite, size: 22),
            onPressed: () {
              cubit.toggleFavorite(song.id);
            },
          ),
          onTap: () {
            playerCubit.playSong(song, queue: favorites);
          },
        );
      },
    );
  }
}
