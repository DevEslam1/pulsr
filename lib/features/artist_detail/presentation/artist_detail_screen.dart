// lib/features/artist_detail/presentation/artist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/artist_bio_service.dart';

class ArtistDetailScreen extends StatefulWidget {
  final ArtistsTableData artist;
  final GetArtistsUseCase? getArtistsUseCase;

  const ArtistDetailScreen(
      {super.key, required this.artist, this.getArtistsUseCase});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  late GetArtistsUseCase _useCase;

  /// Created once so StreamBuilder keeps a single drift subscription across
  /// rebuilds — a fresh Stream per build tears down and re-subscribes the
  /// watch, re-issuing the DB query on every rebuild. [artist] is a route
  /// argument and cannot change for this mount.
  late final Stream<Result<List<AlbumsTableData>>> _albumsStream =
      _useCase.watchArtistAlbums(widget.artist.id);
  late final Stream<Result<List<SongsTableData>>> _songsStream =
      _useCase.watchArtistSongs(widget.artist.id);

  @override
  void initState() {
    super.initState();
    _useCase = widget.getArtistsUseCase ?? getIt<GetArtistsUseCase>();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final artist = widget.artist;

    return Scaffold(
      appBar: AppBar(
        title: Text(artist.name),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: Adaptive.contentConstraints(context),
          // Builder-based slivers (F-04): header/sections as box adapters and
          // the Top Tracks list virtualized via SliverList.builder.
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: p.accent.withValues(alpha: 0.3), width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: p.glow,
                                blurRadius: 28,
                                spreadRadius: -4,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: CachedArtwork(
                          id: artist.id,
                          type: ArtworkType.ARTIST,
                          size: isTablet ? 160 : 130,
                          borderRadius: 999,
                          fallbackIcon: Icons.person_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        artist.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        Formatters.formatTrackCount(artist.songCount),
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Artist Biography & HD Info
                    FutureBuilder(
                      future: ArtistBioService().getArtistInfo(artist.name),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data?.bio != null) {
                          final bio = snapshot.data!.bio!;
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: p.surfaceContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: p.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 16, color: p.accent),
                                    const SizedBox(width: 6),
                                    Text(
                                      'About Artist',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: p.accent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  bio,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Discography (Albums)
                    StreamBuilder<Result<List<AlbumsTableData>>>(
                      stream: _albumsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _ErrorSection(
                            title: 'Albums',
                            onRetry: () => setState(() {}),
                          );
                        }
                        final albums = snapshot.data
                                ?.fold((l) => <AlbumsTableData>[], (r) => r) ??
                            [];
                        if (albums.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(title: 'Albums'),
                            SizedBox(
                              height: 175,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.symmetric(
                                    horizontal: Adaptive.pagePadding(context)),
                                itemCount: albums.length,
                                itemBuilder: (context, index) {
                                  final album = albums[index];
                                  return Container(
                                    width: 120,
                                    margin: const EdgeInsets.only(right: 14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () =>
                                          context.push('/album', extra: album),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CachedArtwork(
                                              id: album.id,
                                              type: ArtworkType.ALBUM,
                                              size: 120,
                                              borderRadius: 16),
                                          const SizedBox(height: 8),
                                          Text(album.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: p.textPrimary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                          const SizedBox(height: 2),
                                          Text(
                                              Formatters.formatTrackCount(
                                                  album.songCount),
                                              style: TextStyle(
                                                  color: p.textSecondary,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Top Tracks — sliver-returning StreamBuilder so the track list
              // virtualizes instead of inflating every tile up front.
              StreamBuilder<Result<List<SongsTableData>>>(
                stream: _songsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SliverToBoxAdapter(
                      child: _ErrorSection(
                        title: 'Top Tracks',
                        onRetry: () => setState(() {}),
                      ),
                    );
                  }
                  final songs = snapshot.data
                          ?.fold((l) => <SongsTableData>[], (r) => r) ??
                      [];
                  if (songs.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  return SliverMainAxisGroup(
                    slivers: [
                      const SliverToBoxAdapter(
                        child: SectionHeader(title: 'Top Tracks'),
                      ),
                      SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return SongTile(
                            song: song,
                            index: index,
                            subtitleOverride: song.album,
                            onTap: () => context
                                .read<PlayerCubit>()
                                .playSong(song, queue: songs),
                            onMorePressed: () => showModalBottomSheet<void>(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => SongInfoSheet(song: song),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),

              // Matches the former ListView bottom padding.
              const SliverPadding(padding: EdgeInsets.only(bottom: 160)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorSection extends StatelessWidget {
  final String title;
  final VoidCallback onRetry;

  const _ErrorSection({required this.title, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: p.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Could not load ${title.toLowerCase()}.',
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
