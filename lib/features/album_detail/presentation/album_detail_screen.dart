import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_albums_usecase.dart';
import '../../../core/errors/failures.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';

class AlbumDetailScreen extends StatefulWidget {
  final AlbumsTableData album;
  final GetAlbumsUseCase? getAlbumsUseCase;

  const AlbumDetailScreen(
      {super.key, required this.album, this.getAlbumsUseCase});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

enum _AlbumSort { track, title, duration }

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late GetAlbumsUseCase _useCase;
  _AlbumSort _sort = _AlbumSort.track;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _useCase = widget.getAlbumsUseCase ?? getIt<GetAlbumsUseCase>();
  }

  List<SongsTableData> _sorted(List<SongsTableData> songs) {
    final out = List<SongsTableData>.of(songs);
    switch (_sort) {
      case _AlbumSort.title:
        out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _AlbumSort.duration:
        out.sort((a, b) => a.durationMs.compareTo(b.durationMs));
      case _AlbumSort.track:
        out.sort((a, b) {
          final da = a.discNumber ?? 1, db = b.discNumber ?? 1;
          if (da != db) return da.compareTo(db);
          return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final album = widget.album;

    final isLandscape = context.isLandscape;
    final expandedHeight = isTablet ? 340.0 : (isLandscape ? 230.0 : 300.0);
    final artworkSize = isTablet ? 220.0 : (isLandscape ? 120.0 : 180.0);

    return PulsrPagePopScope(
      child: Scaffold(
        body: StreamBuilder<Result<List<SongsTableData>>>(
          stream: _useCase.watchAlbumSongs(album.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _AlbumErrorView(onRetry: () => setState(() {}));
            }
            final rawSongs =
                snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
            final songs = _sorted(rawSongs);

            return Center(
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      leading: const PulsrBackButton(),
                      expandedHeight: expandedHeight,
                      pinned: true,
                    backgroundColor: p.bg,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [p.accentContainer, p.bg],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Hero(
                                tag: 'album_${album.id}',
                                child: CachedArtwork(
                                  id: album.id,
                                  type: ArtworkType.ALBUM,
                                  size: artworkSize,
                                  borderRadius: 24,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(album.title,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 4),
                              Text(
                                  '${album.artist} • ${Formatters.formatTrackCount(songs.length)}',
                                  style: TextStyle(
                                      color: p.textSecondary, fontSize: 13)),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: songs.isEmpty
                                  ? null
                                  : () => context
                                      .read<PlayerCubit>()
                                      .playSong(songs.first, queue: songs),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(context.l10n.playAll),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: songs.isEmpty
                                  ? null
                                  : () {
                                      final shuffled =
                                          List<SongsTableData>.from(songs)
                                            ..shuffle();
                                      context.read<PlayerCubit>().playSong(
                                          shuffled.first,
                                          queue: shuffled);
                                    },
                              icon:
                                  Icon(Icons.shuffle_rounded, color: p.accent),
                              label: Text(context.l10n.shuffle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: Adaptive.pagePadding(context)),
                      child: Row(
                        children: [
                          Text(
                            context.l10n.queue,
                            style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          // In-list sort (gap 07-01, persisted per session).
                          DropdownButton<_AlbumSort>(
                            value: _sort,
                            underline: const SizedBox.shrink(),
                            icon: Icon(Icons.sort_rounded,
                                color: p.textSecondary, size: 18),
                            items: [
                              DropdownMenuItem(
                                  value: _AlbumSort.track,
                                  child: Text(context.l10n.sortTrackNumber)),
                              DropdownMenuItem(
                                  value: _AlbumSort.title,
                                  child: Text(context.l10n.sortAZ)),
                              DropdownMenuItem(
                                  value: _AlbumSort.duration,
                                  child: Text(context.l10n.sortDuration)),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _sort = v);
                            },
                          ),
                          // Album-level queue actions (gap 07-03).
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_horiz_rounded,
                                color: p.textSecondary),
                            onSelected: (v) async {
                              final cubit = context.read<PlayerCubit>();
                              final target = _selectedIds.isEmpty
                                  ? songs
                                  : songs
                                      .where((s) => _selectedIds.contains(s.id))
                                      .toList();
                              if (v == 'add') {
                                await cubit.addAllToQueue(target);
                                if (mounted) {
                                  setState(() => _selectedIds.clear());
                                }
                              } else if (v == 'next' && target.isNotEmpty) {
                                for (final s in target.reversed) {
                                  await cubit.playNext(s);
                                }
                                if (mounted) {
                                  setState(() => _selectedIds.clear());
                                }
                              } else if (v == 'clear') {
                                setState(() => _selectedIds.clear());
                              }
                            },
                            itemBuilder: (c) => [
                              PopupMenuItem(
                                  value: 'add',
                                  child: Text(context.l10n.addToQueue)),
                              PopupMenuItem(
                                  value: 'next',
                                  child: Text(context.l10n.playNext)),
                              if (_selectedIds.isNotEmpty)
                                PopupMenuItem(
                                    value: 'clear',
                                    child: Text(
                                        '${context.l10n.clear} (${_selectedIds.length})')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8, bottom: 160),
                    sliver: SliverList.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        // Disc grouping (gap 07-02): data is already ordered by
                        // discNumber/trackNumber; render a header on change.
                        final song = songs[index];
                        final showDiscHeader = index == 0 ||
                            (song.discNumber ?? 1) !=
                                (songs[index - 1].discNumber ?? 1);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showDiscHeader &&
                                songs.any((s) => (s.discNumber ?? 1) > 1))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  'Disc ${song.discNumber ?? 1}',
                                  style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            SongTile(
                              song: song,
                              index: index,
                              showArtwork: false,
                              // Batch multi-select (gap 07-04): long-press toggles,
                              // tap plays (or toggles when selection active).
                              selected: _selectedIds.contains(song.id),
                              onLongPress: () => setState(() {
                                if (_selectedIds.contains(song.id)) {
                                  _selectedIds.remove(song.id);
                                } else {
                                  _selectedIds.add(song.id);
                                }
                              }),
                              onTap: () {
                                if (_selectedIds.isNotEmpty) {
                                  setState(() {
                                    if (_selectedIds.contains(song.id)) {
                                      _selectedIds.remove(song.id);
                                    } else {
                                      _selectedIds.add(song.id);
                                    }
                                  });
                                } else {
                                  context
                                      .read<PlayerCubit>()
                                      .playSong(song, queue: songs);
                                }
                              },
                              onMorePressed: () => showModalBottomSheet(
                                context: context,
                                useRootNavigator: true,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => SongInfoSheet(song: song),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
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

class _AlbumErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _AlbumErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(leading: const PulsrBackButton()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: p.error, size: 48),
              const SizedBox(height: 16),
              Text(
                context.l10n.couldNotLoadAlbumSongs,
                style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.libraryReadError,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
