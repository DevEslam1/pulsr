// lib/features/genre_detail/presentation/genre_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/genre_item.dart';
import '../../../domain/usecases/get_genres_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/errors/failures.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class GenreDetailScreen extends StatefulWidget {
  final GenreItem genreItem;
  final GetGenresUseCase? getGenresUseCase;

  const GenreDetailScreen({
    super.key,
    required this.genreItem,
    this.getGenresUseCase,
  });

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

    return PulsrPagePopScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const PulsrBackButton(),
          title: Text(genreItem.name),
        ),
      body: StreamBuilder<Result<List<SongsTableData>>>(
        stream: _useCase.watchGenreSongs(genreItem.name).distinct(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(
                padding: EdgeInsets.only(top: AppSpacing.xs));
          }
          final loadFailed = snapshot.hasError ||
              (snapshot.data?.fold((l) => true, (_) => false) ?? false);
          if (loadFailed) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, color: p.error, size: 48),
                    const SizedBox(height: AppSpacing.md),
                    Text(context.l10n.couldNotLoadGenre,
                      style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.bodyLarge),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.libraryReadError,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    FilledButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.l10n.retry),
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
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.scrollBottom),
                children: [
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: p.accentContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.hairline),
                        boxShadow: [
                          BoxShadow(
                              color: p.glow,
                              blurRadius: 24,
                              spreadRadius: -4,
                              offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Icon(
                        Icons.style_rounded,
                        size: 48,
                        color: p.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      genreItem.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Center(
                    child: Text(
                      Formatters.formatTrackCount(songs.length),
                      style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s20),

                  // Action Buttons (Play All, Shuffle)
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: songs.isNotEmpty
                                ? () => context
                                    .read<PlayerCubit>()
                                    .playSong(songs.first, queue: songs)
                                : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(context.l10n.playAll),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
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
                            icon: Icon(Icons.shuffle_rounded, color: p.accent),
                            label: Text(context.l10n.shuffle),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // Songs List
                  if (songs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: EmptyStateWidget(
                        icon: Icons.music_off_rounded,
                        title: context.l10n.browseNoTracks,
                        subtitle: context.l10n.browseNoTracksInGenre,
                      ),
                    )
                  else
                    for (int i = 0; i < songs.length; i++)
                      SongTile(
                        song: songs[i],
                        index: i,
                        subtitleOverride:
                            '${songs[i].artist} • ${songs[i].album}',
                        onTap: () => context
                            .read<PlayerCubit>()
                            .playSong(songs[i], queue: songs),
                        onMorePressed: () => SongInfoSheet.show(context, song: songs[i]),
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
