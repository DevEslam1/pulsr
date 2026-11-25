import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/responsive/responsive_values.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/track_display_info.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_scroll_edge_fade.dart';
import '../../../../core/widgets/pulsr_section_header.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/staggered_reveal.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/get_songs_usecase.dart';
import '../../../library/cubit/library_cubit.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import 'home_card_metrics.dart';
import 'section_error.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class RecentlyPlayedSection extends StatefulWidget {
  final GetSongsUseCase getSongsUseCase;
  final bool isTablet;

  const RecentlyPlayedSection({
    super.key,
    required this.getSongsUseCase,
    required this.isTablet,
  });

  @override
  State<RecentlyPlayedSection> createState() => _RecentlyPlayedSectionState();
}

class _RecentlyPlayedSectionState extends State<RecentlyPlayedSection> {
  static const int _pageSize = 50;

  /// Upper bound for the queue built on tap. Matches the player's max queue
  /// size, so playback continues through the section instead of falling off
  /// into radio autoplay after the visible window.
  static const int _queueLimit = 500;
  int _currentLimit = _pageSize;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _loadMoreTimeoutTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger next batch when scrolling within 250px of the horizontal end
    if (maxScroll - currentScroll <= 250) {
      _loadMore();
    }
  }

  bool _isLoadingMore = false;
  // Set from the latest emission: only when the window was filled may more
  // rows exist, so scroll notifications cannot grow the limit forever.
  bool _hasMore = false;
  Timer? _loadMoreTimeoutTimer;
  Stream<Result<List<SongsTableData>>>? _songsStream;
  int? _streamLimit;
  List<String> _streamExcluded = const [];

  List<String> _readExcludedFolders(BuildContext context) {
    final folders = context.watch<LibraryCubit?>()?.state.folders;
    if (folders == null || folders.isEmpty) return const [];
    return [
      for (final f in folders)
        if (f.isExcluded) f.path,
    ];
  }

  @override
  void didUpdateWidget(covariant RecentlyPlayedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.getSongsUseCase, widget.getSongsUseCase)) {
      _songsStream = null;
      _streamLimit = null;
      _streamExcluded = const [];
    }
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

  /// Clears the in-flight guard once an emission for the new limit (or a
  /// terminal error/empty state) arrives. Clearing in a post-frame callback
  /// right after setState left a window where scroll notifications re-entered
  /// and grew the limit repeatedly.
  void _clearLoadingMore() {
    _loadMoreTimeoutTimer?.cancel();
    if (!_isLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isLoadingMore) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  /// The carousel is windowed (50 by 50), but playback should continue
  /// through the whole recents list in the same order. Fetch the full list
  /// for the queue and fall back to the visible window if that fails.
  Future<void> _playFromSection(
    PlayerCubit playerCubit,
    SongsTableData song,
    List<SongsTableData> visibleSongs,
  ) async {
    var queue = visibleSongs;
    final excluded = _streamExcluded;
    try {
      final result = excluded.isEmpty
          ? await widget.getSongsUseCase.getRecentlyPlayed(limit: _queueLimit)
          : await widget.getSongsUseCase.getRecentlyPlayed(
              limit: _queueLimit,
              excludedFolders: excluded,
            );
      final full = result.fold<List<SongsTableData>?>((_) => null, (r) => r);
      if (full != null && full.isNotEmpty) {
        queue = full;
      }
    } catch (_) {
      // Keep the already-loaded window as the queue.
    }
    await playerCubit.playSong(song, queue: queue);
  }

  Widget _buildSkeleton(BuildContext context) {
    final size = context.responsive
        .value(compact: 138.0, medium: 150.0, expanded: 158.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PulsrSectionHeader(title: context.l10n.recentlyPlayed),
          SizedBox(
            height: scaledCarouselHeight(context, widget.isTablet),
            child: PulsrScrollEdgeFade(
              extent: 40,
              child: SkeletonShimmer(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsetsDirectional.fromSTEB(
                    Adaptive.pagePadding(context),
                    AppSpacing.s2,
                    Adaptive.pagePadding(context),
                    0,
                  ),
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: AppSpacing.s14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(
                              width: size,
                              height: size,
                              radius: AppRadii.r18,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            SkeletonLine(width: size * 0.78, height: 13),
                            const SizedBox(height: AppSpacing.s4),
                            SkeletonLine(width: size * 0.50, height: 11),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final excluded = _readExcludedFolders(context);

    if (_songsStream == null ||
        _streamLimit != _currentLimit ||
        !listEquals(_streamExcluded, excluded)) {
      _streamLimit = _currentLimit;
      _streamExcluded = excluded;
      _songsStream = (excluded.isEmpty
              ? widget.getSongsUseCase.watchRecentlyPlayed(limit: _currentLimit)
              : widget.getSongsUseCase.watchRecentlyPlayed(
                  limit: _currentLimit,
                  excludedFolders: excluded,
                ))
          .distinct();
    }

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: _songsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _clearLoadingMore();
          return SectionError(onRetry: () => setState(() {}));
        }
        final result = snapshot.data;
        if (result != null && result.isLeft()) {
          _clearLoadingMore();
          return SectionError(onRetry: () => setState(() {}));
        }
        final songs =
            result?.getRight().toNullable() ?? const <SongsTableData>[];

        // First frame: the drift stream has not emitted yet. Render a skeleton
        // instead of collapsing (which caused a visible empty-library flash).
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildSkeleton(context);
        }

        if (songs.isEmpty) {
          _clearLoadingMore();
          return const SizedBox.shrink();
        }

        _hasMore = songs.length >= _currentLimit;
        if (_isLoadingMore &&
            snapshot.connectionState != ConnectionState.waiting) {
          _clearLoadingMore();
        }

        final hasMore = _hasMore;
        final size = context.responsive
            .value(compact: 138.0, medium: 150.0, expanded: 158.0);
        final totalItemCount = songs.length + (hasMore ? 1 : 0);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PulsrSectionHeader(
                title: context.l10n.recentlyPlayed,
                actionLabel: context.l10n.browseSeeAll,
                onAction: () => context.push('/recents'),
              ),
              BlocSelector<PlayerCubit, PlayerState,
                  ({int? songId, bool isPlaying})>(
                selector: (state) => (
                  songId: state.currentSong?.id,
                  isPlaying: state.isPlaying,
                ),
                builder: (context, playback) {
                  return SizedBox(
                    height: scaledCarouselHeight(context, widget.isTablet),
                    child: PulsrScrollEdgeFade(
                      extent: 40,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        padding: EdgeInsetsDirectional.fromSTEB(
                          Adaptive.pagePadding(context),
                          AppSpacing.s2,
                          Adaptive.pagePadding(context),
                          0,
                        ),
                        itemCount: totalItemCount,
                        itemBuilder: (context, index) {
                          if (index >= songs.length) {
                            return Padding(
                              padding: const EdgeInsetsDirectional.only(
                                  end: AppSpacing.s14),
                              child: SkeletonShimmer(
                                child: SizedBox(
                                  width: size,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(
                                        width: size,
                                        height: size,
                                        radius: AppRadii.r18,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      SkeletonLine(
                                          width: size * 0.78, height: 13),
                                      const SizedBox(height: AppSpacing.s4),
                                      SkeletonLine(
                                          width: size * 0.50, height: 11),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          final song = songs[index];
                          final displayInfo = TrackDisplayInfo.resolve(
                            rawTitle: song.title,
                            rawArtist: song.artist,
                          );
                          final isCurrent = playback.songId == song.id;
                          return StaggeredReveal(
                            index: index,
                            horizontal: true,
                            groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                  end: AppSpacing.s14),
                              child: Semantics(
                                button: true,
                                label:
                                    '${displayInfo.title}, ${displayInfo.artist}',
                                hint: context.l10n.play,
                                child: InkWell(
                                  borderRadius: AppRadii.r20All,
                                  onTap: () => _playFromSection(
                                    playerCubit,
                                    song,
                                    songs,
                                  ),
                                  child: SizedBox(
                                    width: size,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Stack(
                                          children: [
                                            HomeCardArtworkFrame(
                                              radius: AppRadii.r18,
                                              child: CachedArtwork(
                                                id: song.id,
                                                remoteUrl:
                                                    song.remoteArtworkUrl ??
                                                        song.artworkUri,
                                                albumId: song.albumId,
                                                type: ArtworkType.AUDIO,
                                                size: size,
                                                borderRadius: AppRadii.r18,
                                                title: displayInfo.title,
                                                artist: displayInfo.artist,
                                              ),
                                            ),
                                            PositionedDirectional(
                                              end: AppSpacing.xs,
                                              bottom: AppSpacing.xs,
                                              child: HomeCardPlayBadge(
                                                isCurrent: isCurrent,
                                                isPlaying: playback.isPlaying,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        SizedBox(
                                          height: scaledTitleBoxHeight(context),
                                          child: Align(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            child: Text(
                                              displayInfo.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isCurrent
                                                    ? p.accent
                                                    : p.textPrimary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: AppFontSize.bodySmall,
                                                letterSpacing:
                                                    AppTracking.title,
                                                height: 1.25,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.s2),
                                        Text(
                                          displayInfo.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: AppFontSize.caption,
                                            fontWeight: FontWeight.w500,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
