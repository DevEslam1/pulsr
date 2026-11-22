import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/presentation/widgets/collection_sort_control.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dismissible.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_albums_usecase.dart';
import '../../library/domain/album_disc_grouping.dart';
import '../../library/presentation/library_quality_utils.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_options_sheet.dart';

class AlbumDetailScreen extends StatefulWidget {
  final AlbumsTableData album;
  final GetAlbumsUseCase? getAlbumsUseCase;
  final String? heroTag;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    this.getAlbumsUseCase,
    this.heroTag,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

enum _AlbumSort { track, title, duration }

/// One row of the album track list: a song plus the disc header drawn above
/// it. Header placement comes from [groupAlbumDiscs], never from comparing
/// neighbouring rows.
class _AlbumTrackRow {
  const _AlbumTrackRow({required this.song, this.discHeader});

  final SongsTableData song;

  /// Localized `Disc <n>` / `Unnumbered` label, or null when no header is
  /// drawn above this row.
  final String? discHeader;
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late GetAlbumsUseCase _useCase;
  late final ScrollController _scrollController;
  bool _showCollapsedTitle = false;
  double _expandedHeight = 280.0;
  _AlbumSort _sort = _AlbumSort.track;
  bool _sortAscending = true;
  final Set<int> _selectedIds = {};

  // Recreated on retry only, so rebuilds (sort changes, selection, theme) do
  // not resubscribe to the DB watch stream.
  late Stream<Result<List<SongsTableData>>> _songsStream;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getAlbumsUseCase ?? getIt<GetAlbumsUseCase>();
    _scrollController = ScrollController()..addListener(_onScroll);
    _updateStream();
    _loadSortPreference();
  }

  @override
  void didUpdateWidget(AlbumDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id ||
        oldWidget.getAlbumsUseCase != widget.getAlbumsUseCase) {
      _useCase = widget.getAlbumsUseCase ?? getIt<GetAlbumsUseCase>();
      setState(() {
        _selectedIds.clear();
        _cachedRawSongs = null;
        _sort = _AlbumSort.track;
        _sortAscending = true;
        _updateStream();
      });
      _loadSortPreference();
    }
  }

  void _updateStream() {
    _songsStream = _useCase.watchAlbumSongs(widget.album.id).distinct();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _expandedHeight - kToolbarHeight - 48;
    final show = _scrollController.offset > threshold;
    if (show != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = show);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String _sortPrefsKey(int albumId) => 'album_sort_$albumId';
  String _sortAscendingPrefsKey(int albumId) => 'album_sort_asc_$albumId';

  Future<void> _loadSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_sortPrefsKey(widget.album.id));
      final storedAsc = prefs.getBool(_sortAscendingPrefsKey(widget.album.id));
      if (mounted) {
        setState(() {
          if (stored != null) {
            final matches =
                _AlbumSort.values.where((e) => e.name == stored).toList();
            if (matches.isNotEmpty) {
              _sort = matches.first;
            }
          }
          if (storedAsc != null) {
            _sortAscending = storedAsc;
          }
        });
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load saved album sort',
        error: e,
        stackTrace: st,
        category: 'AlbumDetail',
      );
    } finally {
      if (mounted) {
        setState(() {
          _cachedRawSongs = null;
          _cachedSort = null;
          _cachedSortAscending = null;
        });
      }
    }
  }

  Future<void> _persistSort(_AlbumSort sort, bool ascending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortPrefsKey(widget.album.id), sort.name);
      await prefs.setBool(_sortAscendingPrefsKey(widget.album.id), ascending);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist album sort',
        error: e,
        stackTrace: st,
        category: 'AlbumDetail',
      );
    }
  }

  List<SongsTableData>? _cachedRawSongs;
  _AlbumSort? _cachedSort;
  bool? _cachedSortAscending;
  List<SongsTableData> _cachedSortedSongs = const [];

  List<SongsTableData> _sorted(List<SongsTableData> songs) {
    if (identical(_cachedRawSongs, songs) &&
        _cachedSort == _sort &&
        _cachedSortAscending == _sortAscending) {
      return _cachedSortedSongs;
    }
    final out = List<SongsTableData>.of(songs);
    switch (_sort) {
      case _AlbumSort.title:
        out.sort(
          (a, b) => _sortAscending
              ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
              : b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case _AlbumSort.duration:
        out.sort(
          (a, b) => _sortAscending
              ? a.durationMs.compareTo(b.durationMs)
              : b.durationMs.compareTo(a.durationMs),
        );
      case _AlbumSort.track:
        if (!_sortAscending) {
          out.sort((a, b) {
            final discA = a.discNumber ?? 1;
            final discB = b.discNumber ?? 1;
            if (discA != discB) return discB.compareTo(discA);
            return (b.trackNumber ?? 0).compareTo(a.trackNumber ?? 0);
          });
        }
        break;
    }
    _cachedRawSongs = songs;
    _cachedSort = _sort;
    _cachedSortAscending = _sortAscending;
    _cachedSortedSongs = out;
    return out;
  }

  /// Display rows for the track list.
  ///
  /// Disc/track order comes from [groupAlbumDiscs], the single grouping
  /// implementation; title and duration sorts keep the plain sorted list and
  /// never interleave disc headers. Headers are drawn only for multi-disc
  /// albums, so a single-disc album renders exactly as before.
  List<_AlbumTrackRow> _trackRows(
    BuildContext context,
    List<SongsTableData> songs,
  ) {
    if (_sort != _AlbumSort.track || !_sortAscending) {
      return [for (final song in songs) _AlbumTrackRow(song: song)];
    }
    final groups = groupAlbumDiscs<SongsTableData>([
      for (final song in songs)
        AlbumDiscTrack<SongsTableData>(
          track: song,
          id: song.id.toString(),
          title: song.title,
          discNumber: song.discNumber,
          trackNumber: song.trackNumber,
        ),
    ]);
    return [
      for (final group in groups)
        for (var i = 0; i < group.tracks.length; i++)
          _AlbumTrackRow(
            song: group.tracks[i],
            discHeader: groups.isMultiDisc && i == 0
                ? _discHeader(context, group)
                : null,
          ),
    ];
  }

  /// Localized header for [group].
  String _discHeader(
    BuildContext context,
    AlbumDiscGroup<SongsTableData> group,
  ) {
    final disc = group.discNumber;
    return disc == null
        ? context.l10n.browseDiscUnnumbered
        : '${context.l10n.browseDisc} $disc';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final album = widget.album;

    final expandedHeight = isTablet
        ? (MediaQuery.sizeOf(context).height * 0.42).clamp(290.0, 390.0)
        : PulsrLayoutMetrics.heroHeight(context);
    _expandedHeight = expandedHeight;
    final artworkSize = (expandedHeight * 0.52).clamp(120.0, 210.0);

    final shouldSplit = PulsrBreakpoint.isLandscape(context) ||
        (Adaptive.isTablet(context) && context.screenWidth >= 800);

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: _songsStream,
      builder: (context, snapshot) {
        Widget buildSongsView(List<SongsTableData> rawSongs) {
          final songs = _sorted(rawSongs);
          // `rows` is the rendered order; the queue follows it so a tap plays
          // in the order the user sees.
          final rows = _trackRows(context, songs);
          final orderedSongs = [for (final row in rows) row.song];
          final totalDurationMs = songs.fold<int>(
            0,
            (acc, s) => acc + s.durationMs,
          );
          final hasHiRes = songs.any(isHiResSong);
          final hasLossless = hasHiRes || songs.any(isLosslessSong);
          final releaseYear = songs
              .map((s) => s.year)
              .whereType<int>()
              .cast<int?>()
              .firstWhere((y) => y != null && y > 0, orElse: () => null);

          // Tablet / landscape: adopt the shared adaptive master-detail split so the
          // horizontal space shows artwork + actions beside the track list.
          if (shouldSplit) {
            return DetailScaffold(
              titleText: album.title,
              bottomNavigationBar:
                  _buildBulkActionsBar(context, orderedSongs),
              onRefresh: () async {
                if (mounted) setState(() {});
              },
              hero: _buildSplitHero(
                context,
                album,
                orderedSongs,
                totalDurationMs: totalDurationMs,
                hasHiRes: hasHiRes,
                hasLossless: hasLossless,
                releaseYear: releaseYear,
              ),
              body: _buildTrackListBody(context, rows),
            );
          }

          // Phone / portrait: collapsing SliverAppBar layout.
          return PulsrPagePopScope(
            onPop: _selectedIds.isNotEmpty
                ? () {
                    setState(() => _selectedIds.clear());
                  }
                : null,
            child: Scaffold(
              backgroundColor: p.bg,
              bottomNavigationBar:
                  _buildBulkActionsBar(context, orderedSongs),
              body: Center(
                child: ConstrainedBox(
                  constraints: PulsrLayoutMetrics.contentConstraints(context),
                  child: RefreshIndicator(
                    color: p.accent,
                    backgroundColor: p.surfaceContainer,
                    onRefresh: () async {
                      if (mounted) setState(() {});
                    },
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverAppBar(
                          leading: const PulsrBackButton(),
                          expandedHeight: expandedHeight,
                          pinned: true,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          backgroundColor: p.bg,
                          surfaceTintColor: Colors.transparent,
                          centerTitle: true,
                          title: ExcludeSemantics(
                            excluding: !_showCollapsedTitle,
                            child: AnimatedOpacity(
                              key: const Key('album_detail_collapsed_title'),
                              duration: context.motion(PulsrMotion.state),
                              opacity: _showCollapsedTitle ? 1.0 : 0.0,
                              child: Text(
                                widget.album.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: AppFontSize.subtitle,
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          actions: [
                            IgnorePointer(
                              ignoring: !_showCollapsedTitle,
                              child: ExcludeSemantics(
                                excluding: !_showCollapsedTitle,
                                child: AnimatedOpacity(
                                  duration: context.motion(PulsrMotion.state),
                                  opacity: _showCollapsedTitle ? 1.0 : 0.0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (songs.isNotEmpty)
                                        IconButton(
                                          constraints: const BoxConstraints(
                                            minWidth: AppSpacing.minTouchTarget,
                                            minHeight:
                                                AppSpacing.minTouchTarget,
                                          ),
                                          icon: Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: p.accent,
                                            size: 28,
                                          ),
                                          tooltip: context.l10n.playAll,
                                          onPressed: () {
                                            PulsrHaptics.mediumImpact();
                                            context.read<PlayerCubit>().playSong(
                                                  orderedSongs.first,
                                                  queue: orderedSongs,
                                                );
                                          },
                                        ),
                                      const SizedBox(width: AppSpacing.xxs),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          flexibleSpace: FlexibleSpaceBar(
                            background: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    p.accentContainer.withValues(
                                      alpha: p.isDark ? 0.55 : 0.75,
                                    ),
                                    p.bg,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: AppRadii.r24All,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: p.isDark ? 0.45 : 0.18,
                                              ),
                                              blurRadius: 28,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: Hero(
                                          tag: widget.heroTag ??
                                              'album_${album.id}',
                                          child: Semantics(
                                            image: true,
                                            label: album.title,
                                            child: CachedArtwork(
                                              id: album.id,
                                              type: ArtworkType.ALBUM,
                                              remoteUrl: album.artworkUri,
                                              size: artworkSize,
                                              borderRadius: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(
                                        album.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3,
                                              color: p.textPrimary,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(
                                        album.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: p.accent,
                                          fontWeight: FontWeight.w700,
                                          fontSize: AppFontSize.bodySmall,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      _buildAlbumMetaRow(
                                        context,
                                        trackCount: songs.length,
                                        totalDurationMs: totalDurationMs,
                                        releaseYear: releaseYear,
                                        hasHiRes: hasHiRes,
                                        hasLossless: hasLossless,
                                        p: p,
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(
                              Adaptive.pagePadding(context),
                              AppSpacing.xs,
                              Adaptive.pagePadding(context),
                              AppSpacing.xs,
                            ),
                            child: _actionButtons(context, orderedSongs),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context),
                            ),
                            child: _queueActionsHeader(context, orderedSongs),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.only(
                            top: AppSpacing.xxs,
                            bottom: PulsrLayoutMetrics.scrollBottom(context),
                          ),
                          sliver: rows.isEmpty
                              ? SliverToBoxAdapter(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.xl),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: PulsrEmptyState(
                                        icon: Icons.music_off_rounded,
                                        title: context.l10n.browseNoTracks,
                                        subtitle:
                                            context.l10n.browseNoTracksFound,
                                      ),
                                    ),
                                  ),
                                )
                              : SliverList.builder(
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: true,
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    return _buildSongItem(
                                      context,
                                      orderedSongs,
                                      rows[index],
                                      index,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final emptyView = buildSongsView(const []);

        return AsyncStateBuilder<Result<List<SongsTableData>>>(
          snapshot: snapshot,
          loadingWidget: _AlbumLoadingView(
            album: album,
            expandedHeight: expandedHeight,
            artworkSize: artworkSize,
          ),
          emptyWidget: emptyView,
          onError: (_) =>
              _AlbumErrorView(onRetry: () => setState(_updateStream)),
          onData: (result) => result.fold(
            (_) => _AlbumErrorView(onRetry: () => setState(_updateStream)),
            buildSongsView,
          ),
        );
      },
    );
  }

  Widget _buildAlbumMetaRow(
    BuildContext context, {
    required int trackCount,
    required int totalDurationMs,
    required int? releaseYear,
    required bool hasHiRes,
    required bool hasLossless,
    required PulsrPalette p,
  }) {
    final durationLabel = totalDurationMs > 0
        ? Formatters.formatDuration(Duration(milliseconds: totalDurationMs))
        : null;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (releaseYear != null)
          Text(
            '$releaseYear •',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          '${context.l10n.tracksCount(trackCount)}'
          '${durationLabel != null ? " • $durationLabel" : ""}',
          style: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hasLossless)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: p.info.withValues(alpha: 0.16),
              borderRadius: AppRadii.r6All,
              border: Border.all(
                color: p.info.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              hasHiRes
                  ? context.l10n.badgeHiRes.toUpperCase()
                  : context.l10n.badgeLossless.toUpperCase(),
              style: TextStyle(
                color: p.info,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionButtons(BuildContext context, List<SongsTableData> songs) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r14All,
              ),
            ),
            onPressed: songs.isEmpty
                ? null
                : () => context
                    .read<PlayerCubit>()
                    .playSong(songs.first, queue: songs),
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(
              context.l10n.playAll,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: p.surfaceContainerHigh,
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r14All,
              ),
            ),
            onPressed: songs.isEmpty
                ? null
                : () {
                    final shuffled = List<SongsTableData>.from(songs)
                      ..shuffle();
                    context
                        .read<PlayerCubit>()
                        .playSong(shuffled.first, queue: shuffled);
                  },
            icon: Icon(Icons.shuffle_rounded, color: p.accent, size: 20),
            label: Text(
              context.l10n.shuffle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _queueActionsHeader(BuildContext context, List<SongsTableData> songs) {
    final p = context.palette;
    final hasSelection = _selectedIds.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          if (hasSelection)
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      borderRadius: AppRadii.r10All,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: p.accent,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Flexible(
                          child: Text(
                            context.l10n.selectedCount(_selectedIds.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                context.l10n.queue.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textTertiary,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          CollectionSortControl<_AlbumSort>(
            currentSort: _sort,
            ascending: _sortAscending,
            options: [
              CollectionSortOption(
                value: _AlbumSort.track,
                label: context.l10n.sortTrackNumber,
                icon: Icons.format_list_numbered_rounded,
              ),
              CollectionSortOption(
                value: _AlbumSort.title,
                label: context.l10n.sortAZ,
                icon: Icons.sort_by_alpha_rounded,
              ),
              CollectionSortOption(
                value: _AlbumSort.duration,
                label: context.l10n.sortDuration,
                icon: Icons.schedule_rounded,
              ),
            ],
            onSortChanged: (v) {
              setState(() {
                _sort = v;
                _cachedSort = null;
              });
              _persistSort(v, _sortAscending);
            },
            onDirectionChanged: (asc) {
              setState(() {
                _sortAscending = asc;
                _cachedSortAscending = null;
              });
              _persistSort(_sort, asc);
            },
          ),
          const SizedBox(width: AppSpacing.xxs),
          // Album-level queue & multi-select actions.
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: p.textSecondary),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r14All,
              side: BorderSide(color: p.hairline),
            ),
            color: p.surfaceContainerHigh,
            onSelected: (v) async {
              final cubit = context.read<PlayerCubit>();
              final target = _selectedIds.isEmpty
                  ? songs
                  : songs.where((s) => _selectedIds.contains(s.id)).toList();
              if (v == 'select') {
                PulsrHaptics.lightImpact();
                if (songs.isNotEmpty) {
                  setState(() => _selectedIds.add(songs.first.id));
                }
              } else if (v == 'select_all') {
                PulsrHaptics.lightImpact();
                setState(() => _selectedIds.addAll(songs.map((s) => s.id)));
              } else if (v == 'add') {
                PulsrHaptics.mediumImpact();
                await cubit.addAllToQueue(target);
                if (mounted) {
                  setState(() => _selectedIds.clear());
                }
              } else if (v == 'next' && target.isNotEmpty) {
                PulsrHaptics.mediumImpact();
                for (final s in target.reversed) {
                  await cubit.playNext(s);
                }
                if (mounted) {
                  setState(() => _selectedIds.clear());
                }
              } else if (v == 'clear') {
                PulsrHaptics.lightImpact();
                setState(() => _selectedIds.clear());
              }
            },
            itemBuilder: (c) => [
              if (_selectedIds.isEmpty)
                PopupMenuItem(
                  value: 'select',
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        size: 18,
                        color: p.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(context.l10n.selectTracks),
                    ],
                  ),
                )
              else
                PopupMenuItem(
                  value: _selectedIds.length == songs.length
                      ? 'clear'
                      : 'select_all',
                  child: Row(
                    children: [
                      Icon(
                        _selectedIds.length == songs.length
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        size: 18,
                        color: p.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _selectedIds.length == songs.length
                            ? context.l10n.deselectAllAction
                            : context.l10n.selectAllAction,
                      ),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      size: 18,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(context.l10n.addToQueue),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'next',
                child: Row(
                  children: [
                    Icon(
                      Icons.playlist_play_rounded,
                      size: 18,
                      color: p.accent,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(context.l10n.playNext),
                  ],
                ),
              ),
              if (_selectedIds.isNotEmpty)
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: p.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('${context.l10n.clear} (${_selectedIds.length})'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionsBar(
    BuildContext context,
    List<SongsTableData> allSongs,
  ) {
    final p = context.palette;
    final l10n = context.l10n;
    final isVisible = _selectedIds.isNotEmpty;
    final selectedSongs = isVisible
        ? allSongs.where((s) => _selectedIds.contains(s.id)).toList()
        : const <SongsTableData>[];

    final shouldAnimate = PulsrMotion.shouldAnimate(context);

    return AnimatedSwitcher(
      duration: shouldAnimate
          ? context.motion(PulsrDurations.layout)
          : Duration.zero,
      reverseDuration: shouldAnimate
          ? context.motion(PulsrDurations.layout)
          : Duration.zero,
      switchInCurve: context.motionCurve(PulsrMotion.enter),
      switchOutCurve: context.motionCurve(PulsrMotion.exit),
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: isVisible
          ? SafeArea(
              key: const ValueKey('album_bulk_actions_bar'),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            border: Border(top: BorderSide(color: p.hairline)),
            boxShadow: [
              BoxShadow(
                color: AppColors.scrimAt(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.accent),
                icon: const Icon(Icons.playlist_play_rounded, size: 20),
                label: Text(l10n.playNext),
                onPressed: selectedSongs.isEmpty
                    ? null
                    : () async {
                        PulsrHaptics.mediumImpact();
                        final cubit = context.read<PlayerCubit>();
                        for (final s in selectedSongs.reversed) {
                          await cubit.playNext(s);
                        }
                        if (mounted) {
                          setState(() => _selectedIds.clear());
                        }
                      },
              ),
              TextButton.icon(
                style:
                    TextButton.styleFrom(foregroundColor: p.textPrimary),
                icon: const Icon(Icons.queue_music_rounded, size: 20),
                label: Text(l10n.addToQueue),
                onPressed: selectedSongs.isEmpty
                    ? null
                    : () async {
                        PulsrHaptics.mediumImpact();
                        final cubit = context.read<PlayerCubit>();
                        await cubit.addAllToQueue(selectedSongs);
                        if (mounted) {
                          setState(() => _selectedIds.clear());
                        }
                      },
              ),
              TextButton.icon(
                style:
                    TextButton.styleFrom(foregroundColor: p.textPrimary),
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                label: Text(l10n.addToPlaylist),
                onPressed: selectedSongs.isEmpty
                    ? null
                    : () async {
                        PulsrHaptics.lightImpact();
                        await AddToPlaylistSheet.show(
                          context,
                          song: selectedSongs.first,
                          songs: selectedSongs,
                        );
                        if (mounted) {
                          setState(() => _selectedIds.clear());
                        }
                      },
              ),
              IconButton(
                tooltip: l10n.cancel,
                icon: Icon(Icons.close_rounded,
                    size: 20, color: p.textSecondary),
                onPressed: () {
                  PulsrHaptics.lightImpact();
                  setState(() => _selectedIds.clear());
                },
              ),
            ],
          ),
        ),
      )
    : const SizedBox.shrink(
        key: ValueKey('album_bulk_actions_bar_empty'),
      ),
  );
  }

  Widget _buildSongItem(
    BuildContext context,
    List<SongsTableData> queue,
    _AlbumTrackRow row,
    int index,
  ) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final song = row.song;
    final discHeader = row.discHeader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (discHeader != null)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              AppSpacing.sm,
              Adaptive.pagePadding(context),
              AppSpacing.xxs,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius: AppRadii.r8All,
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.album_rounded,
                    size: 14,
                    color: p.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    discHeader,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        PulsrDismissible(
          key: ValueKey('album_song_${song.id}'),
          startToEndLabel: context.l10n.playNext,
          dismissDirection: DismissDirection.startToEnd,
          backgroundBuilder: (context, isConfirming) =>
              PulsrDismissible.buildActionBackground(
            context: context,
            icon: Icons.playlist_play_rounded,
            label: context.l10n.playNext,
            color: p.accent,
            backgroundColor: p.accentContainer,
            isConfirming: isConfirming,
          ),
          onConfirm: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await playerCubit.playNext(song);
            }
            return false;
          },
          child: SongTile(
            song: song,
            index: index,
            showArtwork: false,
            // Batch multi-select (gap 07-04): long-press toggles,
            // tap plays (or toggles when selection active).
            selected: _selectedIds.contains(song.id),
            onLongPress: () {
              PulsrHaptics.lightImpact();
              setState(() {
                if (_selectedIds.contains(song.id)) {
                  _selectedIds.remove(song.id);
                } else {
                  _selectedIds.add(song.id);
                }
              });
            },
            onTap: () {
              if (_selectedIds.isNotEmpty) {
                PulsrHaptics.lightImpact();
                setState(() {
                  if (_selectedIds.contains(song.id)) {
                    _selectedIds.remove(song.id);
                  } else {
                    _selectedIds.add(song.id);
                  }
                });
              } else {
                playerCubit.playSong(song, queue: queue);
              }
            },
            onMorePressed: () => SongOptionsSheet.show(context, song: song),
          ),
        ),
      ],
    );
  }

  // Left pane (tablet/landscape split): artwork, title, metadata and the
  // play/shuffle actions. The artwork keeps the same Hero tag used by the phone
  // SliverAppBar so list->detail and mini->player hero flights are unaffected.
  Widget _buildSplitHero(
    BuildContext context,
    AlbumsTableData album,
    List<SongsTableData> songs, {
    required int totalDurationMs,
    required bool hasHiRes,
    required bool hasLossless,
    required int? releaseYear,
  }) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            // Scale the primary artwork to the pane while staying crisp.
            final artSize = (constraints.maxWidth * 0.7).clamp(140.0, 280.0);
            return Container(
              decoration: BoxDecoration(
                borderRadius: AppRadii.r24All,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: p.isDark ? 0.45 : 0.18,
                    ),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Hero(
                tag: widget.heroTag ?? 'album_${album.id}',
                child: Semantics(
                  image: true,
                  label: album.title,
                  child: CachedArtwork(
                    id: album.id,
                    type: ArtworkType.ALBUM,
                    remoteUrl: album.artworkUri,
                    size: artSize,
                    borderRadius: 24,
                    highQuality: true,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          album.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          album.artist,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: p.accent,
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.bodySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildAlbumMetaRow(
          context,
          trackCount: songs.length,
          totalDurationMs: totalDurationMs,
          releaseYear: releaseYear,
          hasHiRes: hasHiRes,
          hasLossless: hasLossless,
          p: p,
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _actionButtons(context, songs),
        ),
      ],
    );
  }

  // Right pane (tablet/landscape split): queue header + track list, reusing the
  // same item builder as the phone sliver list.
  Widget _buildTrackListBody(BuildContext context, List<_AlbumTrackRow> rows) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Semantics(
          liveRegion: true,
          child: PulsrEmptyState(
            icon: Icons.music_off_rounded,
            title: context.l10n.browseNoTracks,
            subtitle: context.l10n.browseNoTracksFound,
          ),
        ),
      );
    }
    final queue = [for (final row in rows) row.song];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Adaptive.pagePadding(context),
          ),
          child: _queueActionsHeader(context, queue),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (int i = 0; i < rows.length; i++)
          _buildSongItem(context, queue, rows[i], i),
      ],
    );
  }
}

class _AlbumLoadingView extends StatelessWidget {
  final AlbumsTableData album;
  final double expandedHeight;
  final double artworkSize;

  const _AlbumLoadingView({
    required this.album,
    required this.expandedHeight,
    required this.artworkSize,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        body: Semantics(
          liveRegion: true,
          child: Center(
            child: ConstrainedBox(
              constraints: PulsrLayoutMetrics.contentConstraints(context),
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    leading: const PulsrBackButton(),
                    expandedHeight: expandedHeight,
                    pinned: true,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    backgroundColor: p.bg,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              p.accentContainer.withValues(
                                alpha: p.isDark ? 0.55 : 0.75,
                              ),
                              p.bg,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SkeletonBox(
                                width: artworkSize,
                                height: artworkSize,
                                radius: 24,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const SkeletonBox(width: 180, height: 22),
                              const SizedBox(height: AppSpacing.xxs),
                              const SkeletonBox(width: 120, height: 14),
                              const SizedBox(height: AppSpacing.md),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: AppSpacing.md),
                      child: SkeletonList(itemCount: 6),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const PulsrBackButton(),
        ),
        body: Center(
          child: Semantics(
            liveRegion: true,
            child: PulsrEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: p.error,
              title: context.l10n.couldNotLoadAlbumSongs,
              subtitle: context.l10n.libraryReadError,
              primaryActionLabel: context.l10n.retry,
              primaryActionIcon: Icons.refresh_rounded,
              onPrimaryAction: onRetry,
            ),
          ),
        ),
      ),
    );
  }
}
