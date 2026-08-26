// lib/features/genre_detail/presentation/genre_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/genre_item.dart';
import '../../../domain/usecases/get_genres_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/errors/failures.dart';

class GenreDetailScreen extends StatefulWidget {
  final GenreItem genreItem;
  final GetGenresUseCase? getGenresUseCase;

  const GenreDetailScreen({super.key, required this.genreItem, this.getGenresUseCase});

  @override
  State<GenreDetailScreen> createState() => _GenreDetailScreenState();
}

class _GenreDetailScreenState extends State<GenreDetailScreen> {
  late GetGenresUseCase _useCase;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getGenresUseCase ?? getIt<GetGenresUseCase>();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final genreItem = widget.genreItem;

    return Scaffold(
      appBar: AppBar(
        title: Text(genreItem.name),
      ),
      body: StreamBuilder<Result<List<SongsTableData>>>(
        stream: _useCase.watchGenreSongs(genreItem.name),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, color: p.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load genre songs',
                      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Something went wrong while reading your library.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final songs = snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          return Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 160),
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: p.accentContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.hairline),
                        boxShadow: [
                          BoxShadow(color: p.glow, blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Icon(
                        Icons.style_rounded,
                        size: 48,
                        color: p.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      genreItem.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      Formatters.formatTrackCount(songs.length),
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons (Play All, Shuffle)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: songs.isNotEmpty
                                ? () => context.read<PlayerCubit>().playSong(songs.first, queue: songs)
                                : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(context.l10n.playAll),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: songs.isNotEmpty
                                ? () {
                                    final shuffled = List<SongsTableData>.from(songs)..shuffle();
                                    context.read<PlayerCubit>().playSong(shuffled.first, queue: shuffled);
                                  }
                                : null,
                            icon: Icon(Icons.shuffle_rounded, color: p.accent),
                            label: Text(context.l10n.shuffle),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Songs List
                  if (songs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: EmptyStateWidget(
                        icon: Icons.music_off_rounded,
                        title: 'No Tracks',
                        subtitle: 'No tracks found in this genre.',
                      ),
                    )
                  else
                    for (int i = 0; i < songs.length; i++)
                      SongTile(
                        song: songs[i],
                        index: i,
                        subtitleOverride: '${songs[i].artist} • ${songs[i].album}',
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
              ),
            ),
          );
        },
      ),
    );
  }
}
