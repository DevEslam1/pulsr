import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
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
import '../../library/presentation/library_quality_utils.dart';
import '../../player/cubit/player_cubit.dart';
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

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late GetAlbumsUseCase _useCase;
  late final ScrollController _scrollController;
  bool _showCollapsedTitle = false;
  double _expandedHeight = 280.0;
  _AlbumSort _sort = _AlbumSort.track;
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

  Future<void> _loadSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_sortPrefsKey(widget.album.id));
      if (stored != null) {
        final matches =
            _AlbumSort.values.where((e) => e.name == stored).toList();
        if (matches.isNotEmpty && mounted) {
          _sort = matches.first;
        }
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
          _cachedSort = null;
        });
      }
    }
  }

  Future<void> _persistSort(_AlbumSort sort) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortPrefsKey(widget.album.id), sort.name);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist album sort',
        error: e,
        stackTrace: st,
        category: 'AlbumDetail',
      );
    }
  }

  int? _cachedSongsHash;
  _AlbumSort? _cachedSort;
  List<SongsTableData> _cachedSortedSongs = const [];

  List<SongsTableData> _sorted(List<SongsTableData> songs) {
    // FIX-M1 / H7 / H-07 / C-05: Hash every song's identity AND its sort-relevant
    // fields. Only serve cached result when prefs have finished loading.
    final songsHash = Object.hashAll([
      for (final s in songs)
        Object.hash(s.id, s.title, s.durationMs, s.discNumber, s.trackNumber),
    ]);
    if (_cachedSongsHash == songsHash && _cachedSort == _sort) {
      return _cachedSortedSongs;
    }
    final out = List<SongsTableData>.of(songs);
    switch (_sort) {
      case _AlbumSort.title:
        out.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _AlbumSort.duration:
        out.sort((a, b) => a.durationMs.compareTo(b.durationMs));
      case _AlbumSort.track:
        out.sort((a, b) {
          final da = a.discNumber ?? 1, db = b.discNumber ?? 1;
          if (da != db) return da.compareTo(db);
          return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        });
    }
    _cachedSongsHash = songsHash;
    _cachedSort = _sort;
    _cachedSortedSongs = out;
    return out;
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
              onRefresh: () async {
                if (mounted) setState(() {});
              },
              hero: _buildSplitHero(
                context,
                album,
                songs,
                totalDurationMs: totalDurationMs,
                hasHiRes: hasHiRes,
                hasLossless: hasLossless,
                releaseYear: releaseYear,
              ),
              body: _buildTrackListBody(context, songs),
            );
          }

          // Phone / portrait: collapsing SliverAppBar layout.
          return PulsrPagePopScope(
            child: Scaffold(
              backgroundColor: p.bg,
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
                            child: _actionButtons(context, songs),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context),
                            ),
                            child: _queueActionsHeader(context, songs),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.only(
                            top: AppSpacing.xxs,
                            bottom: PulsrLayoutMetrics.scrollBottom(context),
                          ),
                          sliver: songs.isEmpty
                              ? SliverToBoxAdapter(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.xl),
                                    child: PulsrEmptyState(
                                      icon: Icons.music_off_rounded,
                                      title: context.l10n.browseNoTracks,
                                      subtitle:
                                          context.l10n.browseNoTracksFound,
                                    ),
                                  ),
                                )
                              : SliverList.builder(
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: true,
                                  itemCount: songs.length,
                                  itemBuilder: (context, index) {
                                    return _buildSongItem(
                                      context,
                                      songs,
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
              hasHiRes ? 'HI-RES' : 'LOSSLESS',
              style: TextStyle(
                color: p.info,
                fontSize: AppFontSize.tiny,
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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.15),
                borderRadius: AppRadii.r8All,
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
                  Text(
                    context.l10n.selectedCount(_selectedIds.length),
                    style: TextStyle(
                      color: p.accent,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              context.l10n.queue.toUpperCase(),
              style: TextStyle(
                color: p.textTertiary,
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          const Spacer(),
          // In-list sort (gap 07-01, persisted per session).
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s10,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r10All,
              border: Border.all(color: p.hairline),
            ),
            child: DropdownButton<_AlbumSort>(
              value: _sort,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: p.surfaceContainerHigh,
              borderRadius: AppRadii.r12All,
              icon: Padding(
                padding:
                    const EdgeInsetsDirectional.only(start: AppSpacing.xxs),
                child: Icon(
                  Icons.sort_rounded,
                  color: p.accent,
                  size: 16,
                ),
              ),
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
              ),
              items: [
                DropdownMenuItem(
                  value: _AlbumSort.track,
                  child: Text(context.l10n.sortTrackNumber),
                ),
                DropdownMenuItem(
                  value: _AlbumSort.title,
                  child: Text(context.l10n.sortAZ),
                ),
                DropdownMenuItem(
                  value: _AlbumSort.duration,
                  child: Text(context.l10n.sortDuration),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _sort = v);
                  _persistSort(v);
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          // Album-level queue actions (gap 07-03).
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
              if (v == 'add') {
                await cubit.addAllToQueue(target);
                if (mounted) {
                  setState(() => _selectedIds.clear());
                }
              } else if (v == 'next' && target.isNotEmpty) {
                for (final s in target.reversed) {
                  await cubit.playNext(s);
                }
                if (mounted) {
                  setState(() => _selectedIds.clear());
                }
              } else if (v == 'clear') {
                setState(() => _selectedIds.clear());
              }
            },
            itemBuilder: (c) => [
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
                        Icons.deselect_rounded,
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

  Widget _buildSongItem(
    BuildContext context,
    List<SongsTableData> songs,
    int index,
  ) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    // Disc grouping (gap 07-02): only meaningful when the list is ordered by
    // disc/track; title and duration sorts must not interleave disc headers.
    final song = songs[index];
    final showDiscHeader = _sort == _AlbumSort.track &&
        (index == 0 ||
            (song.discNumber ?? 1) != (songs[index - 1].discNumber ?? 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDiscHeader && songs.any((s) => (s.discNumber ?? 1) > 1))
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
                    '${context.l10n.browseDisc} ${song.discNumber ?? 1}',
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
            onLongPress: () => setState(() {
              if (_selectedIds.contains(song.id)) {
                _selectedIds.remove(song.id);
              } else {
                _selectedIds.add(song.id);
              }
            }),
            onTap: () {
              if (_selectedIds.isNotEmpty) {
                setState(() {
                  if (_selectedIds.contains(song.id)) {
                    _selectedIds.remove(song.id);
                  } else {
                    _selectedIds.add(song.id);
                  }
                });
              } else {
                playerCubit.playSong(song, queue: songs);
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
  Widget _buildTrackListBody(BuildContext context, List<SongsTableData> songs) {
    if (songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: PulsrEmptyState(
          icon: Icons.music_off_rounded,
          title: context.l10n.browseNoTracks,
          subtitle: context.l10n.browseNoTracksFound,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Adaptive.pagePadding(context),
          ),
          child: _queueActionsHeader(context, songs),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (int i = 0; i < songs.length; i++)
          _buildSongItem(context, songs, i),
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
        body: Center(
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
    );
  }
}
