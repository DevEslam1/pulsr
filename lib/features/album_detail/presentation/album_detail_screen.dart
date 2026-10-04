import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_albums_usecase.dart';
import '../../../core/errors/failures.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/utils/error_logger.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  _AlbumSort _sort = _AlbumSort.track;
  final Set<int> _selectedIds = {};

  // Memoized so rebuilds (sort changes, selection, theme) do not resubscribe to
  // the DB watch stream.
  late final Stream<Result<List<SongsTableData>>> _songsStream;

  @override
  void initState() {
    super.initState();
    _useCase = widget.getAlbumsUseCase ?? getIt<GetAlbumsUseCase>();
    _songsStream = _useCase.watchAlbumSongs(widget.album.id).distinct();
    _loadSortPreference();
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
      ErrorLogger.log('Failed to load saved album sort',
          error: e, stackTrace: st, category: 'AlbumDetail');
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
      ErrorLogger.log('Failed to persist album sort',
          error: e, stackTrace: st, category: 'AlbumDetail');
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
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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
        ? (MediaQuery.sizeOf(context).height * 0.40).clamp(280.0, 380.0)
        : PulsrLayoutMetrics.heroHeight(context);
    final artworkSize = (expandedHeight * 0.55).clamp(120.0, 220.0);

    final shouldSplit = PulsrBreakpoint.isLandscape(context) ||
        (Adaptive.isTablet(context) && context.screenWidth >= 800);

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: _songsStream,
      builder: (context, snapshot) {
        Widget buildSongsView(List<SongsTableData> rawSongs) {
          final songs = _sorted(rawSongs);

          // Tablet / landscape: adopt the shared adaptive master-detail split so the
          // horizontal space shows artwork + actions beside the track list. The
          // breakpoint mirrors DetailScaffold's own split condition so it engages at
          // exactly the same point as the Genre/Year sibling screens.
          if (shouldSplit) {
            return DetailScaffold(
              titleText: album.title,
              onRefresh: () async {
                if (mounted) setState(() {});
              },
              hero: _buildSplitHero(context, album, songs),
              body: _buildTrackListBody(context, songs),
            );
          }

          // Phone / portrait: preserve the existing collapsing SliverAppBar layout
          // exactly (unchanged appearance and behavior).
          return PulsrPagePopScope(
            child: Scaffold(
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
                      slivers: [
                        SliverAppBar(
                          leading: const PulsrBackButton(),
                          expandedHeight: expandedHeight,
                          pinned: true,
                          backgroundColor: p.bg,
                          flexibleSpace: FlexibleSpaceBar(
                            background: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [p.accentContainer, p.bg],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: SafeArea(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Hero(
                                      tag:
                                          widget.heroTag ?? 'album_${album.id}',
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
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(album.title,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                        '${album.artist} • ${Formatters.formatTrackCount(songs.length)}',
                                        style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: AppFontSize.bodySmall)),
                                    const SizedBox(height: AppSpacing.md),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: Adaptive.pagePadding(context)),
                            child: _actionButtons(context, songs),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: Adaptive.pagePadding(context)),
                            child: _queueActionsHeader(context, songs),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.only(
                              top: AppSpacing.xs,
                              bottom: PulsrLayoutMetrics.scrollBottom(context)),
                          sliver: SliverList.builder(
                            addAutomaticKeepAlives: false,
                            addRepaintBoundaries: true,
                            itemCount: songs.length,
                            itemBuilder: (context, index) {
                              return _buildSongItem(context, songs, index);
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
          loadingWidget: emptyView,
          emptyWidget: emptyView,
          onError: (_) => _AlbumErrorView(onRetry: () => setState(() {})),
          onData: (result) => result.fold(
            (_) => _AlbumErrorView(onRetry: () => setState(() {})),
            buildSongsView,
          ),
        );
      },
    );
  }

  Widget _actionButtons(BuildContext context, List<SongsTableData> songs) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: songs.isEmpty
                ? null
                : () => context
                    .read<PlayerCubit>()
                    .playSong(songs.first, queue: songs),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(context.l10n.playAll),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: songs.isEmpty
                ? null
                : () {
                    final shuffled = List<SongsTableData>.from(songs)
                      ..shuffle();
                    context
                        .read<PlayerCubit>()
                        .playSong(shuffled.first, queue: shuffled);
                  },
            icon: Icon(Icons.shuffle_rounded, color: p.accent),
            label: Text(context.l10n.shuffle),
          ),
        ),
      ],
    );
  }

  Widget _queueActionsHeader(BuildContext context, List<SongsTableData> songs) {
    final p = context.palette;
    return Row(
      children: [
        Text(
          context.l10n.queue,
          style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        // In-list sort (gap 07-01, persisted per session).
        DropdownButton<_AlbumSort>(
          value: _sort,
          underline: const SizedBox.shrink(),
          icon: Icon(Icons.sort_rounded, color: p.textSecondary, size: 18),
          items: [
            DropdownMenuItem(
                value: _AlbumSort.track,
                child: Text(context.l10n.sortTrackNumber)),
            DropdownMenuItem(
                value: _AlbumSort.title, child: Text(context.l10n.sortAZ)),
            DropdownMenuItem(
                value: _AlbumSort.duration,
                child: Text(context.l10n.sortDuration)),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => _sort = v);
              _persistSort(v);
            }
          },
        ),
        // Album-level queue actions (gap 07-03).
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: p.textSecondary),
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
            PopupMenuItem(value: 'add', child: Text(context.l10n.addToQueue)),
            PopupMenuItem(value: 'next', child: Text(context.l10n.playNext)),
            if (_selectedIds.isNotEmpty)
              PopupMenuItem(
                  value: 'clear',
                  child:
                      Text('${context.l10n.clear} (${_selectedIds.length})')),
          ],
        ),
      ],
    );
  }

  Widget _buildSongItem(
      BuildContext context, List<SongsTableData> songs, int index) {
    final p = context.palette;
    // Disc grouping (gap 07-02): data is already ordered by
    // discNumber/trackNumber; render a header on change.
    final song = songs[index];
    final showDiscHeader = index == 0 ||
        (song.discNumber ?? 1) != (songs[index - 1].discNumber ?? 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDiscHeader && songs.any((s) => (s.discNumber ?? 1) > 1))
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxs),
            child: Text(
              '${context.l10n.browseDisc} ${song.discNumber ?? 1}',
              style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w800),
            ),
          ),
        SongTile(
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
              context.read<PlayerCubit>().playSong(song, queue: songs);
            }
          },
          onMorePressed: () => SongInfoSheet.show(context, song: song),
        ),
      ],
    );
  }

  // Left pane (tablet/landscape split): artwork, title, metadata and the
  // play/shuffle actions. The artwork keeps the same Hero tag used by the phone
  // SliverAppBar so list->detail and mini->player hero flights are unaffected.
  Widget _buildSplitHero(
      BuildContext context, AlbumsTableData album, List<SongsTableData> songs) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            // Scale the primary artwork to the pane while staying crisp.
            final artSize = (constraints.maxWidth * 0.7).clamp(140.0, 280.0);
            return Hero(
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
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(album.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${album.artist} • ${Formatters.formatTrackCount(songs.length)}',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: p.textSecondary, fontSize: AppFontSize.bodySmall),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
          child: _queueActionsHeader(context, songs),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (int i = 0; i < songs.length; i++)
          _buildSongItem(context, songs, i),
      ],
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
        appBar: AppBar(leading: const PulsrBackButton()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: p.error, size: 48),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.couldNotLoadAlbumSongs,
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
                      color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                ),
                const SizedBox(height: AppSpacing.s20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
