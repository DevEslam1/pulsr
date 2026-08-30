// lib/features/year_detail/presentation/year_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/year_item.dart';
import '../../../domain/usecases/get_years_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/errors/failures.dart';

class YearDetailScreen extends StatefulWidget {
  final YearItem yearItem;
  final GetYearsUseCase? getYearsUseCase;

  const YearDetailScreen(
      {super.key, required this.yearItem, this.getYearsUseCase});

  @override
  State<YearDetailScreen> createState() => _YearDetailScreenState();
}

class _YearDetailScreenState extends State<YearDetailScreen> {
  late GetYearsUseCase _useCase;

  /// Created once so StreamBuilder keeps a single drift subscription across
  /// rebuilds — a fresh Stream per build tears down and re-subscribes the
  /// watch, re-issuing the DB query on every rebuild. [yearItem] is a route
  /// argument and cannot change for this mount.
  late final Stream<Result<List<SongsTableData>>> _songsStream =
      _useCase.watchYearSongs(widget.yearItem.year);

  @override
  void initState() {
    super.initState();
    _useCase = widget.getYearsUseCase ?? getIt<GetYearsUseCase>();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final yearItem = widget.yearItem;

    return Scaffold(
      appBar: AppBar(
        title: Text('${yearItem.year}'),
      ),
      body: StreamBuilder<Result<List<SongsTableData>>>(
        stream: _songsStream,
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
                      'Could not load songs for this year',
                      style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
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
          final songs =
              snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          return Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              // Builder-based slivers (F-04): header as a box adapter, track
              // list virtualized — same order/spacing as ListView(children:).
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFF40C4FF)
                                  .withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: p.hairline),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF40C4FF)
                                        .withValues(alpha: 0.25),
                                    blurRadius: 24,
                                    spreadRadius: -4,
                                    offset: const Offset(0, 8)),
                              ],
                            ),
                            child: const Icon(
                              Icons.calendar_today_rounded,
                              size: 44,
                              color: Color(0xFF40C4FF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            '${yearItem.year}',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            Formatters.formatTrackCount(songs.length),
                            style: TextStyle(
                                color: p.textSecondary, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action Buttons (Play All, Shuffle)
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context)),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: songs.isNotEmpty
                                      ? () => context
                                          .read<PlayerCubit>()
                                          .playSong(songs.first, queue: songs)
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Play All'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: songs.isNotEmpty
                                      ? () {
                                          final shuffled =
                                              List<SongsTableData>.from(songs)
                                                ..shuffle();
                                          context.read<PlayerCubit>().playSong(
                                              shuffled.first,
                                              queue: shuffled);
                                        }
                                      : null,
                                  icon: Icon(Icons.shuffle_rounded,
                                      color: p.accent),
                                  label: const Text('Shuffle'),
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
                              subtitle: 'No tracks found for this year.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (songs.isNotEmpty)
                    SliverList.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        return SongTile(
                          song: song,
                          index: index,
                          subtitleOverride: '${song.artist} • ${song.album}',
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
                  // Bottom padding kept unconditional (matches the former
                  // ListView padding, as in artist/playlist detail).
                  const SliverPadding(padding: EdgeInsets.only(bottom: 160)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
