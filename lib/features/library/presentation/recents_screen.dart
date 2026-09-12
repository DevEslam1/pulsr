import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_info_sheet.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  int _historyLimit = 100;
  late final GetSongsUseCase _getSongsUseCase;

  @override
  void initState() {
    super.initState();
    _getSongsUseCase = getIt<GetSongsUseCase>();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<SongsTableData> _filterSongs(List<SongsTableData> songs) {
    if (_searchQuery.isEmpty) return songs;
    final q = _searchQuery.toLowerCase();
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _showClearConfirmation(BuildContext context) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: 'Clear Listening History?',
      message:
          'This will remove all tracks from your Recently Played history. Your actual audio files and playlists will not be affected.',
      icon: Icons.history_rounded,
      confirmLabel: 'Clear History',
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      final res = await _getSongsUseCase.clearRecentlyPlayed();
      res.fold(
        (err) => PulsrToast.show(context,
            message: 'Failed to clear history: ${err.message}', isError: true),
        (_) => PulsrToast.show(context,
            message: 'Listening history cleared',
            icon: Icons.history_rounded),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: const Text(
          'Recently Played',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear History',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _showClearConfirmation(context),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _getSongsUseCase.watchRecentlyPlayed(limit: _historyLimit),
        builder: (context, snapshot) {
          final allRecents =
              snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          if (allRecents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded,
                      size: 64, color: p.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No recently played songs',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Play your favorite music and it will appear here.',
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          final filtered = _filterSongs(allRecents);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Search & Header Stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      // Search bar
                      GlassContainer(
                        blur: 16,
                        opacity: p.isDark ? 0.9 : 0.95,
                        borderRadius: AppRadii.full,
                        color: p.surfaceContainer,
                        border: Border.all(color: p.hairline, width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                color: p.textSecondary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) {
                                  _searchDebounce?.cancel();
                                  _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                                    if (mounted) setState(() => _searchQuery = val);
                                  });
                                },
                                style: TextStyle(
                                    color: p.textPrimary, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search ${allRecents.length} recent songs...',
                                  hintStyle: TextStyle(
                                      color: p.textTertiary, fontSize: 13.5),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              IconButton(
                                icon: Icon(Icons.close_rounded,
                                    color: p.textSecondary, size: 18),
                                onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Action buttons: Play All & Shuffle
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (filtered.isNotEmpty) {
                                  playerCubit.playSong(filtered.first,
                                      queue: filtered);
                                }
                              },
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 20),
                              label: Text('Play All (${filtered.length})'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: p.accent,
                                foregroundColor: p.onAccent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadii.buttonRadius,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (filtered.isNotEmpty) {
                                final shuffled = List<SongsTableData>.from(
                                    filtered)..shuffle();
                                playerCubit.playSong(shuffled.first,
                                    queue: shuffled);
                              }
                            },
                            icon: const Icon(Icons.shuffle_rounded, size: 20),
                            label: const Text('Shuffle'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.surfaceContainerHigh,
                              foregroundColor: p.textPrimary,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadii.buttonRadius,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Song List
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No results for "$_searchQuery"',
                      style: TextStyle(color: p.textSecondary, fontSize: 14),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.only(top: 8, bottom: 100, left: 16, right: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = filtered[index];
                        return StaggeredListItem(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: AppRadii.cardRadius,
                                onTap: () => playerCubit.playSong(song,
                                    queue: filtered),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadii.cardRadius,
                                    color: p.surfaceContainer.withValues(
                                        alpha: p.isDark ? 0.3 : 0.6),
                                  ),
                                  child: Row(
                                    children: [
                                      // Index number
                                      SizedBox(
                                        width: 24,
                                        child: Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: p.textTertiary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Artwork
                                      CachedArtwork(
                                        id: song.id,
                                        remoteUrl: song.remoteArtworkUrl,
                                        type: ArtworkType.AUDIO,
                                        size: 46,
                                        borderRadius: 12,
                                      ),
                                      const SizedBox(width: 12),
                                      // Title & Artist
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.textPrimary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              song.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // More menu
                                      IconButton(
                                        icon: const Icon(
                                            Icons.more_vert_rounded,
                                            size: 20),
                                        color: p.textSecondary,
                                        onPressed: () {
                                          _showSongOptions(context, song);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
              if (allRecents.length >= _historyLimit && _searchQuery.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load More History'),
                        onPressed: () {
                          setState(() {
                            _historyLimit += 100;
                          });
                        },
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      ),
    );
  }

  void _showSongOptions(BuildContext context, SongsTableData song) {
    final p = context.palette;
    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add to playlist'),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddToPlaylistSheet(song: song),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Song info'),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SongInfoSheet(song: song),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
