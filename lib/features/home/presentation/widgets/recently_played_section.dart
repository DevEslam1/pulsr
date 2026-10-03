import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_section_header.dart';
import '../../../../core/widgets/staggered_reveal.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/get_songs_usecase.dart';
import '../../../player/cubit/player_cubit.dart';
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
  int _currentLimit = _pageSize;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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

  void _loadMore() {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    setState(() {
      _currentLimit += _pageSize;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: widget.getSongsUseCase
          .watchRecentlyPlayed(limit: _currentLimit)
          .distinct(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SectionError(onRetry: () => setState(() {}));
        }
        final songs =
            snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

        if (songs.isEmpty) return const SizedBox.shrink();

        final hasMore = songs.length >= _currentLimit;
        final size = widget.isTablet ? 158.0 : 138.0;
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
              SizedBox(
                height: scaledCarouselHeight(context, widget.isTablet),
                child: ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  itemCount: totalItemCount,
                  itemBuilder: (context, index) {
                    if (index >= songs.length) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: AppSpacing.s14),
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: p.surfaceCard.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppRadii.r18),
                            border: Border.all(color: p.hairline),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: AppSpacing.lg,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(p.accent),
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    final song = songs[index];
                    return StaggeredReveal(
                      index: index,
                      horizontal: true,
                      groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: AppSpacing.s14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadii.r20),
                          onTap: () => playerCubit.playSong(song, queue: songs),
                          child: SizedBox(
                            width: size,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    CachedArtwork(
                                      id: song.id,
                                      remoteUrl: song.remoteArtworkUrl ??
                                          song.artworkUri,
                                      albumId: song.albumId,
                                      type: ArtworkType.AUDIO,
                                      size: size,
                                      borderRadius: AppRadii.r18,
                                    ),
                                    PositionedDirectional(
                                      end: 8,
                                      bottom: 8,
                                      child: ExcludeSemantics(
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: p.accent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                  color: p.glow,
                                                  blurRadius: 14,
                                                  spreadRadius: 1),
                                            ],
                                          ),
                                          child: Icon(Icons.play_arrow_rounded,
                                              color: p.onAccent, size: 22),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                SizedBox(
                                  height: scaledTitleBoxHeight(context),
                                  child: Text(
                                    song.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.label,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.label),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
