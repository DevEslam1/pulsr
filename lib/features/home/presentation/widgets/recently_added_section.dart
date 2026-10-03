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
import '../../../../core/widgets/song_tile.dart';
import '../../../../core/widgets/staggered_reveal.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/get_songs_usecase.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../sheets/song_info_sheet.dart';
import 'empty_library.dart';
import 'section_error.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  int _currentLimit = _pageSize;
  bool _isLoadingMore = false;
  Timer? _loadMoreTimeoutTimer;

  void _loadMore() {
    if (_isLoadingMore) return;
    _loadMoreTimeoutTimer?.cancel();
    setState(() {
      _isLoadingMore = true;
      _currentLimit += _pageSize;
    });
    _loadMoreTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoadingMore) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  @override
  void dispose() {
    _loadMoreTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();
    final columns = PulsrAdaptiveGrid.songColumns(context);

    return StreamBuilder<Result<List<SongsTableData>>>(
      stream: widget.getSongsUseCase
          .watchRecentlyAdded(limit: _currentLimit)
          .distinct(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (_isLoadingMore) {
            _loadMoreTimeoutTimer?.cancel();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isLoadingMore) {
                setState(() => _isLoadingMore = false);
              }
            });
          }
          return SectionError(onRetry: () => setState(() {}));
        }
        final songs =
            snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

        if (songs.isEmpty) {
          if (_isLoadingMore) {
            _loadMoreTimeoutTimer?.cancel();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isLoadingMore) {
                setState(() => _isLoadingMore = false);
              }
            });
          }
          return const EmptyLibrary();
        }

        final hasMore = songs.length >= _currentLimit;
        // As soon as the active stream emits, clear the guard so "Load more"
        // does not remain stuck when reaching the end of the collection.
        if (_isLoadingMore &&
            snapshot.connectionState != ConnectionState.waiting) {
          _loadMoreTimeoutTimer?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isLoadingMore) {
              setState(() => _isLoadingMore = false);
            }
          });
        }
        final loading = _isLoadingMore;
        final totalItemCount = songs.length + (hasMore ? 1 : 0);

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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : _loadMore,
                          icon: loading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(p.accent),
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text(
                            context.l10n.browseSeeAll,
                            style: TextStyle(
                              color: p.accent,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final song = songs[index];
                  return StaggeredReveal(
                    index: index,
                    groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                    child: SongTile(
                      song: song,
                      onTap: () => playerCubit.playSong(song, queue: songs),
                      onMorePressed: () =>
                          SongInfoSheet.show(context, song: song),
                    ),
                  );
                },
              )
            else
              for (int index = 0; index < totalItemCount; index++)
                if (index >= songs.length)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context),
                      vertical: AppSpacing.sm,
                    ),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: loading ? null : _loadMore,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: p.accent.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.s10,
                          ),
                        ),
                        icon: loading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(p.accent),
                                ),
                              )
                            : Icon(Icons.expand_more_rounded,
                                size: 18, color: p.accent),
                        label: Text(
                          '${context.l10n.loadMore} (+50)',
                          style: TextStyle(
                            color: p.accent,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  StaggeredReveal(
                    index: index,
                    groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                    child: SongTile(
                      song: songs[index],
                      onTap: () =>
                          playerCubit.playSong(songs[index], queue: songs),
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
