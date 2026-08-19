// lib/features/year_detail/presentation/year_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../domain/models/year_item.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import 'package:on_audio_query/on_audio_query.dart';

class YearDetailScreen extends StatelessWidget {
  final YearItem yearItem;

  const YearDetailScreen({super.key, required this.yearItem});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MusicRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text('${yearItem.year}'),
      ),
      body: StreamBuilder<Result<List<SongsTableData>>>(
        stream: repository.watchYearSongs(yearItem.year),
        builder: (context, snapshot) {
          final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_today_rounded,
                    size: 54,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${yearItem.year}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  Formatters.formatTrackCount(songs.length),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons (Play All, Shuffle)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: songs.isNotEmpty
                            ? () {
                                context.read<PlayerCubit>().playSong(songs.first, queue: songs);
                              }
                            : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.outline),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: songs.isNotEmpty
                            ? () {
                                final shuffled = List<SongsTableData>.from(songs)..shuffle();
                                context.read<PlayerCubit>().playSong(shuffled.first, queue: shuffled);
                              }
                            : null,
                        icon: const Icon(Icons.shuffle_rounded, color: AppColors.primary),
                        label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Songs List
              if (songs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No tracks for this year',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...songs.map((song) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 48, borderRadius: 10),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => SongInfoSheet(song: song),
                        );
                      },
                    ),
                    onTap: () {
                      context.read<PlayerCubit>().playSong(song, queue: songs);
                    },
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
