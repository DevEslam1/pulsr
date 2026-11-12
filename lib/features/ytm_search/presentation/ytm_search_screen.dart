// lib/features/ytm_search/presentation/ytm_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';

import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_refresh_indicator.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';
import '../../search/presentation/widgets/highlighted_song_tile.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../cubit/ytm_download_cubit.dart';
import '../cubit/ytm_search_cubit.dart';
import '../cubit/ytm_search_state.dart';
import 'widgets/ytm_download_button.dart';

import '../../../core/utils/pulsr_haptics.dart';
class YtmSearchScreen extends StatelessWidget {
  const YtmSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<YtmSearchCubit>()),
        BlocProvider<YtmDownloadCubit>.value(value: getIt<YtmDownloadCubit>()),
      ],
      child: const _YtmSearchView(),
    );
  }
}

class _YtmSearchView extends StatefulWidget {
  const _YtmSearchView();

  @override
  State<_YtmSearchView> createState() => _YtmSearchViewState();
}

class _YtmSearchViewState extends State<_YtmSearchView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<String> _history = const [];
  bool _historyLoaded = false;
  bool _historyLoading = false;
  bool _historyLoadFailed = false;
  bool _historyRefreshPending = false;
  int _historyRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    // M-09: Guard against overlapping loads and replay pending requests.
    if (_historyLoading) {
      _historyRefreshPending = true;
      return;
    }
    _historyLoading = true;
    try {
      final items = await context.read<YtmSearchCubit>().getSearchHistory();
      if (mounted) {
        _historyRetryCount = 0;
        setState(() {
          _history = items;
          _historyLoaded = true;
          _historyLoadFailed = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to refresh YTM search history',
        error: e,
        stackTrace: st,
        category: 'YtmSearch',
      );
      if (mounted) {
        setState(() {
          _history = _history.isNotEmpty ? _history : const [];
          _historyLoaded = true;
          _historyLoadFailed = _history.isEmpty;
        });
      }
    } finally {
      _historyLoading = false;
      if (_historyRefreshPending && mounted) {
        _historyRefreshPending = false;
        if (_historyRetryCount < 3) {
          _historyRetryCount++;
          _refreshHistory();
        }
      }
    }
  }

  void _applyHistoryQuery(String query, {bool keepFocus = false}) {
    PulsrHaptics.selectionClick();
    final text = keepFocus ? '$query ' : query;
    _searchController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (keepFocus) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
    }
    context.read<YtmSearchCubit>().onQueryChanged(text);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<YtmSearchCubit>();
    final playerCubit = context.read<PlayerCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(
            context.l10n.browseYouTubeMusic,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.titleLarge,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: BlocListener<YtmSearchCubit, YtmSearchState>(
                listenWhen: (prev, curr) =>
                    prev.results != curr.results && curr.results.isNotEmpty,
                listener: (_, __) => _refreshHistory(),
                child: BlocBuilder<YtmSearchCubit, YtmSearchState>(
                  builder: (context, state) {
                    final showProgress =
                        (state.isLoading || cubit.isDebouncing) &&
                            state.query.trim().isNotEmpty;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PulsrSearchField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          autofocus: true,
                          debounceDuration: Duration.zero,
                          hintText: context.l10n.browseSongsOnYtm,
                          margin: EdgeInsetsDirectional.fromSTEB(
                            Adaptive.pagePadding(context),
                            AppSpacing.xs,
                            Adaptive.pagePadding(context),
                            AppSpacing.xxs,
                          ),
                          onChanged: (value) {
                            if (value.isEmpty) {
                              cubit.clearQuery();
                            } else {
                              cubit.onQueryChanged(value);
                            }
                          },
                          onSubmitted: (value) => cubit.commitQuery(value),
                          onClear: cubit.clearQuery,
                        ),
                        SizedBox(
                          height: 2,
                          child: showProgress
                              ? PulsrProgressBar.indeterminate(
                                  height: 2,
                                  color: p.accent,
                                  backgroundColor: Colors.transparent,
                                )
                              : null,
                        ),
                        Expanded(
                          child: _buildBody(
                            context,
                            state,
                            cubit,
                            playerCubit,
                            p,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context, PulsrPalette p) {
    final cubit = context.read<YtmSearchCubit>();
    if (!_historyLoaded) {
      return const SizedBox.shrink();
    }
    if (_history.isEmpty) {
      return PulsrEmptyState(
        icon: _historyLoadFailed
            ? Icons.sync_problem_rounded
            : Icons.travel_explore_rounded,
        title: _historyLoadFailed
            ? context.l10n.browseSearchFailed
            : context.l10n.searchYtm,
        subtitle: context.l10n.browseYtmSearchScreenDesc,
        primaryActionLabel: _historyLoadFailed ? context.l10n.tryAgain : null,
        primaryActionIcon: _historyLoadFailed ? Icons.refresh_rounded : null,
        onPrimaryAction: _historyLoadFailed ? _refreshHistory : null,
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsetsDirectional.fromSTEB(
        Adaptive.pagePadding(context),
        AppSpacing.xs,
        Adaptive.pagePadding(context),
        PulsrLayoutMetrics.scrollBottom(context),
      ),
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 15, color: p.textTertiary),
            const SizedBox(width: AppSpacing.s6),
            Expanded(
              child: Text(
                context.l10n.history.toUpperCase(),
                style: TextStyle(
                  color: p.textTertiary,
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w800,
                  letterSpacing: AppTracking.wide,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                PulsrHaptics.lightImpact();
                await cubit.clearHistory();
                if (mounted) _refreshHistory();
              },
              child: Text(
                context.l10n.browseClearHistory,
                style: TextStyle(
                  color: p.accent,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.5),
            borderRadius: AppRadii.r16All,
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < _history.length; i++) ...[
                if (i > 0) Divider(color: p.hairline, height: 1, indent: 42),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => _applyHistoryQuery(_history[i]),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.sm,
                        end: AppSpacing.xxs,
                        top: 2,
                        bottom: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 18,
                            color: p.textTertiary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _history[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.body,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.north_west_rounded,
                              size: 16,
                              color: p.textTertiary,
                            ),
                            onPressed: () => _applyHistoryQuery(
                              _history[i],
                              keepFocus: true,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: context.l10n.remove,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: p.textTertiary,
                            ),
                            onPressed: () {
                              PulsrHaptics.lightImpact();
                              cubit.removeHistoryQuery(_history[i]);
                              _refreshHistory();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: p.textTertiary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                context.l10n.browseYtmSearchScreenDesc,
                style: TextStyle(
                  color: p.textTertiary,
                  fontSize: AppFontSize.label,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    YtmSearchState state,
    YtmSearchCubit cubit,
    PlayerCubit playerCubit,
    PulsrPalette p,
  ) {
    if ((state.isLoading || cubit.isDebouncing) && state.results.isEmpty) {
      return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
    }

    if (state.errorMessage != null) {
      return PulsrEmptyState(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.browseSearchFailed,
        subtitle: resolveUiErrorMessage(context, state.errorMessage!),
        primaryActionLabel: context.l10n.tryAgain,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: cubit.retryAfterCooldown,
      );
    }

    if (state.results.isEmpty) {
      return state.hasSearched
          ? PulsrEmptyState(
              icon: Icons.search_off_rounded,
              title: context.l10n.browseNoResultsFound,
              subtitle:
                  '${context.l10n.browseNoYtmMatchesFor} "${state.query.trim()}".',
            )
          : _buildHistory(context, p);
    }

    final songs = [for (final track in state.results) track.toSongData()];
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: cubit.botCooldown,
          builder: (context, coolingDown, _) {
            final status = cubit.statusMessageFor(coolingDown);
            if (status == null) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              margin: EdgeInsetsDirectional.fromSTEB(
                Adaptive.pagePadding(context),
                AppSpacing.xxs,
                Adaptive.pagePadding(context),
                AppSpacing.xxs,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.r12All,
                border: Border.all(color: p.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (cubit.showingCachedResults)
          Container(
            width: double.infinity,
            margin: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              AppSpacing.xxs,
              Adaptive.pagePadding(context),
              AppSpacing.xxs,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r12All,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 16, color: p.accent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.l10n.ytmCachedResults,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: PulsrRefreshIndicator(
            onRefresh: () async {
              cubit.retry();
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 400 &&
                    cubit.hasMore &&
                    !state.isLoading &&
                    !state.loadMoreFailed) {
                  unawaited(cubit.loadMore());
                }
                return false;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                padding: EdgeInsets.only(
                  bottom: PulsrLayoutMetrics.scrollBottom(context),
                  top: AppSpacing.xxs,
                ),
                itemCount: songs.length +
                    (state.isLoading || state.loadMoreFailed ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= songs.length) {
                    if (state.loadMoreFailed) {
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => cubit.loadMore(),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(context.l10n.retry),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Center(
                        child: PulsrProgressBar.circular(
                          size: 22,
                          strokeWidth: 2.4,
                          color: p.accent,
                        ),
                      ),
                    );
                  }
                  final song = songs[index];
                  return HighlightedSongTile(
                    song: song,
                    query: state.query,
                    subtitleOverride: state.results[index].artist,
                    onTap: () {
                      cubit.commitQuery();
                      playerCubit.playSong(song, queue: songs);
                    },
                    onLongPress: () => _showTrackActions(context, song, p),
                    onMorePressed: () => _showTrackActions(context, song, p),
                    trailing: YtmDownloadButton(song: song),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTrackActions(
    BuildContext context,
    SongsTableData song,
    PulsrPalette p,
  ) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) => PulsrBottomSheet(
        leading: SizedBox(
          width: 44,
          height: 44,
          child: CachedArtwork(
            id: song.id,
            remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
            albumId: song.albumId,
            type: ArtworkType.AUDIO,
            size: 44,
            borderRadius: 10,
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.playlist_play_rounded, color: p.accent),
              title: Text(context.l10n.playNext),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<PlayerCubit>().playNext(song);
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music_rounded, color: p.accent),
              title: Text(context.l10n.addToQueue),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<PlayerCubit>().addAllToQueue([song]);
              },
            ),
            ListTile(
              leading: Icon(Icons.download_rounded, color: p.accent),
              title: Text(context.l10n.browseDownloadOffline),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<YtmDownloadCubit>().download(song);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: p.accent),
              title: Text(context.l10n.addToPlaylist),
              onTap: () {
                Navigator.of(sheetContext).pop();
                AddToPlaylistSheet.show(context, song: song);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}
