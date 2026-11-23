// lib/features/year_detail/presentation/year_detail_screen.dart
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/year_item.dart';
import '../../../domain/usecases/get_years_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import '../../../core/errors/failures.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class YearDetailScreen extends StatefulWidget {
  final YearItem yearItem;
  final GetYearsUseCase? getYearsUseCase;
  final List<String> excludedFolders;

  const YearDetailScreen({
    super.key,
    required this.yearItem,
    this.getYearsUseCase,
    this.excludedFolders = const [],
  });

  @override
  State<YearDetailScreen> createState() => _YearDetailScreenState();
}

class _YearDetailScreenState extends State<YearDetailScreen> {
  late GetYearsUseCase _useCase;
  late Stream<Result<List<SongsTableData>>> _songsStream;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getYearsUseCase ?? getIt<GetYearsUseCase>();
    // Wave 1 watchYearSongs already reacts to excludedFoldersTable in SQL.
    _updateStream();
  }

  @override
  void didUpdateWidget(YearDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final excludedChanged =
        !listEquals(oldWidget.excludedFolders, widget.excludedFolders);
    if (oldWidget.yearItem.year != widget.yearItem.year ||
        oldWidget.getYearsUseCase != widget.getYearsUseCase ||
        excludedChanged) {
      _useCase = widget.getYearsUseCase ?? getIt<GetYearsUseCase>();
      setState(_updateStream);
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
    final base = _useCase.watchYearSongs(widget.yearItem.year).distinct();
    final excluded = widget.excludedFolders;
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
    final yearItem = widget.yearItem;

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: _songsStream,
      builder: (context, snapshot) {
        Widget buildContent(List<SongsTableData> songs) {
          return DetailScaffold(
            titleText: '${yearItem.year}',
            onRefresh: () async {
              if (mounted) setState(_updateStream);
            },
            hero: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Semantics(
                    image: true,
                    label: '${yearItem.year}',
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: p.info.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: p.hairline),
                        boxShadow: [
                          BoxShadow(
                              color: p.info.withValues(alpha: 0.25),
                              blurRadius: 24,
                              spreadRadius: -4,
                              offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        size: 44,
                        color: p.info,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(
                    '${yearItem.year}',
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
                      subtitle: context.l10n.browseNoTracksInYear,
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
              title: Text('${yearItem.year}'),
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
                      context.l10n.couldNotLoadYear,
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
                title: Text('${yearItem.year}'),
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
