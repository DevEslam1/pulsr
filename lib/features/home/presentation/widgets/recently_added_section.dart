import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/responsive/adaptive_grid.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_static_grid.dart';
import '../../../../core/widgets/pulsr_section_header.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../../../core/widgets/staggered_reveal.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/get_songs_usecase.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../sheets/song_info_sheet.dart';
import 'empty_library.dart';
import 'section_error.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

class RecentlyAddedSection extends StatefulWidget {
  final GetSongsUseCase getSongsUseCase;

  const RecentlyAddedSection({
    super.key,
    required this.getSongsUseCase,
  });

  @override
  State<RecentlyAddedSection> createState() => _RecentlyAddedSectionState();
}

class _RecentlyAddedSectionState extends State<RecentlyAddedSection> {
  static const int _pageSize = 50;

  /// Upper bound for the queue built on tap. Matches the player's max queue
  /// size, so playback continues through the section instead of falling off
  /// into radio autoplay after the visible window.
  static const int _queueLimit = 500;

  /// How close (in logical pixels) the end of the loaded list must get to the
  /// viewport bottom before the next page is fetched automatically.
  static const double _autoLoadExtent = 400;

  int _currentLimit = _pageSize;
  bool _isLoadingMore = false;

  /// Set from the latest emission: only when the window was filled may more
  /// rows exist, so scroll events cannot grow the limit forever.
  bool _hasMore = false;
  Timer? _loadMoreTimeoutTimer;
  ScrollPosition? _outerPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The section is rendered inside the home page's outer scroll view (it is
    // not itself scrollable), so listen to that position to auto-load the
    // next page as the user reaches the end of the list.
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _outerPosition)) {
      _outerPosition?.removeListener(_maybeAutoLoad);
      _outerPosition = position;
      _outerPosition?.addListener(_maybeAutoLoad);
    }
  }

  @override
  void dispose() {
    _outerPosition?.removeListener(_maybeAutoLoad);
    _loadMoreTimeoutTimer?.cancel();
    super.dispose();
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    _loadMoreTimeoutTimer?.cancel();
    setState(() {
      _isLoadingMore = true;
      _currentLimit += _pageSize;
    });
    // Safety net in case the stream never emits for the new limit.
    _loadMoreTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoadingMore) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  /// Replaces the old manual load-more button: once the end of the loaded
  /// list gets within [_autoLoadExtent] of the viewport bottom, fetch the
  /// next page.
  void _maybeAutoLoad() {
    if (!mounted || _isLoadingMore || !_hasMore) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final viewportBottom = MediaQuery.sizeOf(context).height;
    if (bottom <= viewportBottom + _autoLoadExtent) {
      _loadMore();
    }
  }

  /// The section is windowed (50 rows at a time), but playback should
  /// continue through the whole list in the same order. Fetch the full list
  /// for the queue and fall back to the visible window if that fails.
  Future<void> _playFromSection(
    PlayerCubit playerCubit,
    SongsTableData song,
    List<SongsTableData> visibleSongs,
  ) async {
    var queue = visibleSongs;
    try {
      final result =
          await widget.getSongsUseCase.getRecentlyAdded(limit: _queueLimit);
      final full = result.fold<List<SongsTableData>?>((_) => null, (r) => r);
      if (full != null && full.isNotEmpty) {
        queue = full;
      }
    } catch (_) {
      // Keep the already-loaded window as the queue.
    }
    await playerCubit.playSong(song, queue: queue);
  }

  void _clearLoadingMore() {
    _loadMoreTimeoutTimer?.cancel();
    if (!_isLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isLoadingMore) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  Widget _buildAutoLoadIndicator(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(p.accent),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerCubit = context.read<PlayerCubit>();
    final columns = PulsrAdaptiveGrid.songColumns(context);

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: widget.getSongsUseCase
          .watchRecentlyAdded(limit: _currentLimit)
          .distinct(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _hasMore = false;
          _clearLoadingMore();
          return SectionError(onRetry: () => setState(() {}));
        }
        final songs =
            snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

        // First frame before drift emits: show a lightweight skeleton instead
        // of flashing the "No music yet / Scan Storage" empty state.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return SkeletonList(
            padding: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              AppSpacing.xs,
              Adaptive.pagePadding(context),
              AppSpacing.xs,
            ),
          );
        }

        if (songs.isEmpty) {
          _hasMore = false;
          _clearLoadingMore();
          return const EmptyLibrary();
        }

        final hasMore = songs.length >= _currentLimit;
        _hasMore = hasMore;
        // As soon as the active stream emits, clear the guard so a pending
        // auto-load does not remain stuck when reaching the end of the
        // collection.
        if (_isLoadingMore &&
            snapshot.connectionState != ConnectionState.waiting) {
          _clearLoadingMore();
        }
        // Content shorter than the viewport (e.g. a tablet in landscape)
        // keeps filling itself until the viewport is covered or the
        // collection ends.
        if (hasMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoLoad());
        }
        final loading = _isLoadingMore;
        final totalItemCount = songs.length + (loading ? 1 : 0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PulsrSectionHeader(
              title: context.l10n.recentlyAdded,
              actionLabel: context.l10n.browseSeeAll,
              onAction: () => context.push('/library'),
              padding: EdgeInsetsDirectional.fromSTEB(
                Adaptive.pagePadding(context),
                AppSpacing.xs,
                Adaptive.pagePadding(context),
                AppSpacing.xs,
              ),
            ),
            if (columns > 1)
              PulsrStaticGrid(
                crossAxisCount: columns,
                mainAxisExtent: 72,
                crossAxisSpacing: 10,
                mainAxisSpacing: 4,
                padding: EdgeInsets.symmetric(
                    horizontal: Adaptive.pagePadding(context)),
                itemCount: totalItemCount,
                itemBuilder: (context, index) {
                  if (index >= songs.length) {
                    return _buildAutoLoadIndicator(context);
                  }

                  final song = songs[index];
                  return StaggeredReveal(
                    index: index,
                    groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                    child: SongTile(
                      song: song,
                      onTap: () => _playFromSection(
                        playerCubit,
                        song,
                        songs,
                      ),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: song),
                    ),
                  );
                },
              )
            else
              for (int index = 0; index < totalItemCount; index++)
                if (index >= songs.length)
                  _buildAutoLoadIndicator(context)
                else
                  StaggeredReveal(
                    index: index,
                    groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                    child: SongTile(
                      song: songs[index],
                      onTap: () => _playFromSection(
                        playerCubit,
                        songs[index],
                        songs,
                      ),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: songs[index]),
                    ),
                  ),
          ],
        );
      },
    );
  }
}
