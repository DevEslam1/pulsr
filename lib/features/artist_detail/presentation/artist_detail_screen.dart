// lib/features/artist_detail/presentation/artist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../player/cubit/player_cubit.dart';

class ArtistDetailScreen extends StatelessWidget {
  final ArtistsTableData artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MusicRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(artist.name),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const SizedBox(height: 16),
          Center(
            child: CachedArtwork(
              id: artist.id,
              type: ArtworkType.ARTIST,
              size: 140,
              borderRadius: 70,
              fallbackIcon: Icons.person_rounded,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              artist.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: 24),

          // Discography (Albums)
          StreamBuilder<List<AlbumsTableData>>(
            stream: repository.watchArtistAlbums(artist.id),
            builder: (context, snapshot) {
              final albums = snapshot.data ?? [];
              if (albums.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('ALBUMS', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: albums.length,
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CachedArtwork(id: album.id, type: ArtworkType.ALBUM, size: 110, borderRadius: 12),
                              const SizedBox(height: 6),
                              Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // Top Songs
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('TOP TRACKS', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700, fontSize: 12)),
          ),

          StreamBuilder<List<SongsTableData>>(
            stream: repository.watchArtistSongs(artist.id),
            builder: (context, snapshot) {
              final songs = snapshot.data ?? [];

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 44, borderRadius: 10),
                    title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('${song.album} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    onTap: () {
                      context.read<PlayerCubit>().playSong(song, queue: songs);
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
