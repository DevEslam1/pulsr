// lib/features/genre_detail/presentation/genre_detail_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/genre_item.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../../domain/usecases/get_genres_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import '../../../core/errors/failures.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class GenreDetailScreen extends StatefulWidget {
  final GenreItem genreItem;
  final GetGenresUseCase? getGenresUseCase;
  final List<String> excludedFolders;

  const GenreDetailScreen({
    super.key,
    required this.genreItem,
    this.getGenresUseCase,
    this.excludedFolders = const [],
  });

  @override
  State<GenreDetailScreen> createState() => _GenreDetailScreenState();
}

class _GenreDetailScreenState extends State<GenreDetailScreen> {
  late GetGenresUseCase _useCase;
  late List<String> _excludedFolders;
  late Stream<Result<List<SongsTableData>>> _songsStream;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getGenresUseCase ?? getIt<GetGenresUseCase>();
    _excludedFolders = List<String>.unmodifiable(widget.excludedFolders);
    // Recreated only on retry or exclusion change so rebuilds (scroll/theme)
    // do not resubscribe to the DB watch stream.
    _updateStream();
    if (_excludedFolders.isEmpty) {
      unawaited(_loadExcludedFolders());
    }
  }

  Future<void> _loadExcludedFolders() async {
    try {
      List<String> fetched = const [];
      if (getIt.isRegistered<FolderUseCases>()) {
        final res = await getIt<FolderUseCases>().getExcludedFolders();
        fetched = res.fold((_) => const <String>[], (r) => r);
      } else if (getIt.isRegistered<IMusicRepository>()) {
        final res = await getIt<IMusicRepository>().getExcludedFolderPaths();
        fetched = res.fold((_) => const <String>[], (r) => r);
      }
      if (!mounted || listEquals(fetched, _excludedFolders)) return;
      setState(() {
        _excludedFolders = List<String>.unmodifiable(fetched);
        _updateStream();
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load excluded folders for GenreDetailScreen',
          error: e, stackTrace: st, category: 'GenreDetail');
    }
  }

  @override
  void didUpdateWidget(GenreDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final excludedChanged =
        !listEquals(oldWidget.excludedFolders, widget.excludedFolders);
    if (oldWidget.genreItem.name != widget.genreItem.name ||
        oldWidget.getGenresUseCase != widget.getGenresUseCase ||
        excludedChanged) {
      _useCase = widget.getGenresUseCase ?? getIt<GetGenresUseCase>();
      if (excludedChanged) {
        _excludedFolders = List<String>.unmodifiable(widget.excludedFolders);
      }
      setState(_updateStream);
      if (excludedChanged && _excludedFolders.isEmpty) {
        unawaited(_loadExcludedFolders());
      }
    }
  }

  static bool _isExcludedPath(String path, List<String> excludedFolders) {
    if (excludedFolders.isEmpty || path.isEmpty) return false;
    final normPath = path.replaceAll('\\', '/').toLowerCase();
    for (final raw in excludedFolders) {
      var folder = raw.replaceAll('\\', '/').toLowerCase().trim();
      while (folder.endsWith('/')) {
        folder = folder.substring(0, folder.length - 1);
      }
      if (folder.isEmpty) continue;
      if (normPath == folder || normPath.startsWith('$folder/')) return true;
    }
    return false;
  }

  void _updateStream() {
    final base = _useCase.watchGenreSongs(widget.genreItem.name).distinct();
    final excluded = _excludedFolders;
    if (excluded.isEmpty) {
      _songsStream = base;
    } else {
      _songsStream = base.map(
        (result) => result.map(
          (songs) => songs
              .where((s) => !_isExcludedPath(s.path, excluded))
              .toList(growable: false),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final genreItem = widget.genreItem;

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: _songsStream,
      builder: (context, snapshot) {
        Widget buildContent(List<SongsTableData> songs) {
          return DetailScaffold(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${context.l10n.genres} > ${genreItem.name}',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  genreItem.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            onRefresh: () async {
              if (mounted) setState(() {});
            },
            hero: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Semantics(
                    image: true,
                    label: genreItem.name,
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
                    context.l10n.tracksCount(songs.length),
                    style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.bodySmall),
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
                const SizedBox(height: AppSpacing.md),
              ],
            ),
            body: songs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: PulsrEmptyState(
                      icon: Icons.music_off_rounded,
                      title: context.l10n.browseNoTracks,
                      subtitle: context.l10n.browseNoTracksInGenre,
                    ),
                  )
                : null,
            sliverBody: songs.isEmpty
                ? null
                : SliverList.builder(
                    addAutomaticKeepAlives: false,
                    itemCount: songs.length,
                    itemBuilder: (context, i) => SongTile(
                      song: songs[i],
                      index: i,
                      subtitleOverride:
                          '${songs[i].artist} • ${songs[i].album}',
                      onTap: () => context
                          .read<PlayerCubit>()
                          .playSong(songs[i], queue: songs),
                      onMorePressed: () =>
                          SongOptionsSheet.show(context, song: songs[i]),
                    ),
                  ),
          );
        }

        final emptyContent = buildContent(const []);
        final errorView = PulsrPagePopScope(
          child: Scaffold(
            appBar: AppBar(
              leading: const PulsrBackButton(),
              title: Text(genreItem.name),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, color: p.error, size: 48),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.couldNotLoadGenre,
                      style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.bodyLarge),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.libraryReadError,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.bodySmall),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    FilledButton.icon(
                      onPressed: () => setState(_updateStream),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return AsyncStateBuilder<Result<List<SongsTableData>>>(
          snapshot: snapshot,
          loadingWidget: PulsrPagePopScope(
            child: Scaffold(
              appBar: AppBar(
                leading: const PulsrBackButton(),
                title: Text(genreItem.name),
              ),
              body: const SkeletonList(
                  padding: EdgeInsets.only(top: AppSpacing.xs)),
            ),
          ),
          emptyWidget: emptyContent,
          onError: (_) => errorView,
          onData: (result) => result.fold(
            (_) => errorView,
            buildContent,
          ),
        );
      },
    );
  }
}
