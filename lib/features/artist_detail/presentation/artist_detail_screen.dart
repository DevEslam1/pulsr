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

class ArtistDetailScreen extends StatefulWidget {
  final ArtistsTableData artist;
  final GetArtistsUseCase? getArtistsUseCase;

  const ArtistDetailScreen({super.key, required this.artist, this.getArtistsUseCase});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  late GetArtistsUseCase _useCase;

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
          child: ListView(
            padding: const EdgeInsets.only(bottom: 160),
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.accent.withValues(alpha: 0.3), width: 2),
                    boxShadow: [
                      BoxShadow(color: p.glow, blurRadius: 28, spreadRadius: -4, offset: const Offset(0, 8)),
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
              const SizedBox(height: 24),

              // Discography (Albums)
              StreamBuilder<Result<List<AlbumsTableData>>>(
                stream: _useCase.watchArtistAlbums(artist.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorSection(
                      title: 'Albums',
                      onRetry: () => setState(() {}),
                    );
                  }
                  final albums = snapshot.data?.fold((l) => <AlbumsTableData>[], (r) => r) ?? [];
                  if (albums.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Albums'),
                      SizedBox(
                        height: 175,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                          itemCount: albums.length,
                          itemBuilder: (context, index) {
                            final album = albums[index];
                            return Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => context.push('/album', extra: album),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CachedArtwork(id: album.id, type: ArtworkType.ALBUM, size: 120, borderRadius: 16),
                                    const SizedBox(height: 8),
                                    Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(Formatters.formatTrackCount(album.songCount),
                                        style: TextStyle(color: p.textSecondary, fontSize: 11)),
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

              // Top Tracks
              StreamBuilder<Result<List<SongsTableData>>>(
                stream: _useCase.watchArtistSongs(artist.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorSection(
                      title: 'Top Tracks',
                      onRetry: () => setState(() {}),
                    );
                  }
                  final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];
                  if (songs.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Top Tracks'),
                      for (int i = 0; i < songs.length; i++)
                        SongTile(
                          song: songs[i],
                          index: i,
                          subtitleOverride: songs[i].album,
                          onTap: () => context.read<PlayerCubit>().playSong(songs[i], queue: songs),
                          onMorePressed: () => showModalBottomSheet(
                            context: context,
                            useRootNavigator: true,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => SongInfoSheet(song: songs[i]),
                          ),
                        ),
                    ],
                  );
                },
              ),
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
