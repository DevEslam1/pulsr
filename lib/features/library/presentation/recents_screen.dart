// lib/features/library/presentation/recents_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_dismissible.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import 'library_quality_utils.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _isSearchOpen = false;

  static const int _persistedHistoryLimit = 100;
  static const int _maxHistoryLimit = 500;
  int _historyLimit = _persistedHistoryLimit;
  bool _hasMore = true;

  late final GetSongsUseCase _getSongsUseCase;
  late Stream<dynamic> _recentStream;
  List<String> _excludedFolders = const [];

  void _updateStream() {
    _recentStream = _getSongsUseCase.watchRecentlyPlayed(
      limit: _historyLimit,
      excludedFolders: _excludedFolders,
    );
  }

  Future<void> _initHistory() async {
    if (getIt.isRegistered<FolderUseCases>()) {
      try {
        final res = await getIt<FolderUseCases>().getExcludedFolders();
        _excludedFolders = res.fold((_) => <String>[], (list) => list);
      } catch (_) {
        // Exclusion lookup failure must not block the history list.
      }
    }
    if (!mounted || _excludedFolders.isEmpty) return;
    // Only the first stream needs replacing when exclusions were loaded; an
    // unconditional resubscribe duplicated the DB query on every open.
    setState(_updateStream);
  }

  void _retryHistory() {
    setState(_updateStream);
  }

  Widget _buildLoadError(BuildContext context) => PulsrEmptyState(
        icon: Icons.error_outline_rounded,
        iconColor: context.palette.error,
        title: context.l10n.somethingWentWrong,
        subtitle: context.l10n.libraryReadError,
        primaryActionLabel: context.l10n.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: _retryHistory,
      );

  @override
  void initState() {
    super.initState();
    _getSongsUseCase = getIt<GetSongsUseCase>();
    _updateStream();
    _initHistory();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<SongsTableData> _filterSongs(List<SongsTableData> songs) {
    if (_searchQuery.isEmpty) return songs;
    final q = _searchQuery.toLowerCase();
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.album.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _showClearConfirmation(BuildContext context) async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: context.l10n.browseClearListeningHistoryTitle,
      message: context.l10n.browseClearListeningHistoryMessage,
      icon: Icons.history_rounded,
      confirmLabel: context.l10n.browseClearHistory,
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      final res = await _getSongsUseCase.clearRecentlyPlayed();
      if (!mounted) return;
      res.fold(
        (err) => PulsrToast.show(
          context,
          message: '${context.l10n.browseClearHistoryFailed}:${err.message}',
          isError: true,
        ),
        (_) => PulsrToast.show(
          context,
          message: context.l10n.browseHistoryCleared,
          icon: Icons.history_rounded,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final playerCubit = context.read<PlayerCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const PulsrBackButton(),
          title: _isSearchOpen
              ? PulsrSearchField(
                  controller: _searchController,
                  autofocus: true,
                  debounceDuration: Duration.zero,
                  hintText: '${l10n.search}${l10n.browseRecentSongs}...',
                  // BUG-09: debounce keystrokes so the list isn't rebuilt on every character.
                  onChanged: (val) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () {
                        if (mounted) {
                          setState(() => _searchQuery = val.trim());
                        }
                      },
                    );
                  },
                  onClear: () {
                    _searchDebounce?.cancel();
                    if (mounted) {
                      setState(() => _searchQuery = '');
                    }
                  },
                )
              : Text(
                  l10n.recentlyPlayed,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: AppFontSize.bodyLarge,
                  ),
                ),
          actions: [
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              icon: Icon(
                _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                color: p.textPrimary,
              ),
              tooltip: _isSearchOpen ? l10n.close : l10n.search,
              onPressed: () {
                _searchDebounce?.cancel();
                setState(() {
                  if (_isSearchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                    _isSearchOpen = false;
                  } else {
                    _isSearchOpen = true;
                  }
                });
              },
            ),
            IconButton(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              tooltip: l10n.browseClearHistory,
              icon: Icon(Icons.delete_sweep_outlined, color: p.textSecondary),
              onPressed: () => _showClearConfirmation(context),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: StreamBuilder(
              key: ValueKey(_historyLimit),
              stream: _recentStream,
              builder: (context, snapshot) {
                final emptyBody = RefreshIndicator(
                  color: p.accent,
                  backgroundColor: p.surfaceContainer,
                  onRefresh: () async {
                    if (mounted) _retryHistory();
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    children: [
                      const SizedBox(height: AppSpacing.xxl),
                      PulsrEmptyState(
                        icon: Icons.history_toggle_off_rounded,
                        title: l10n.noRecentSongs,
                        subtitle: l10n.recentEmptyHint,
                      ),
                    ],
                  ),
                );

                return AsyncStateBuilder<dynamic>(
                  snapshot: snapshot,
                  loadingWidget: const SkeletonList(),
                  emptyWidget: emptyBody,
                  onError: (_) => _buildLoadError(context),
                  isEmpty: (data) =>
                      data?.fold((l) => false, (r) => r.isEmpty) ?? true,
                  onData: (data) {
                    if (data.isLeft()) return _buildLoadError(context);
                    final allRecents =
                        data?.fold((l) => <SongsTableData>[], (r) => r) ??
                            <SongsTableData>[];
                    final filtered = _filterSongs(allRecents);
                    final totalDurationMs = filtered.fold<int>(
                      0,
                      (acc, s) => acc + s.durationMs,
                    );
                    final losslessCount =
                        filtered.where(isLosslessSong).length;

                    return RefreshIndicator(
                      color: p.accent,
                      backgroundColor: p.surfaceContainer,
                      onRefresh: () async {
                        if (mounted) _retryHistory();
                      },
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        slivers: [
                          // ---------- Tinted Summary Header Card ----------
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                Adaptive.pagePadding(context),
                                AppSpacing.xs,
                                Adaptive.pagePadding(context),
                                AppSpacing.sm,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (p.isDark ? Colors.white : Colors.black)
                                          .withValues(alpha: 0.05),
                                  borderRadius: AppRadii.r18All,
                                  border: Border.all(
                                    color:
                                        (p.isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.08),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (filtered.isNotEmpty)
                                      CachedArtwork(
                                        id: filtered.first.id,
                                        albumId: filtered.first.albumId,
                                        remoteUrl:
                                            filtered.first.remoteArtworkUrl ??
                                                filtered.first.artworkUri,
                                        type: ArtworkType.AUDIO,
                                        size: 52,
                                        borderRadius: AppRadii.r12,
                                      )
                                    else
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color:
                                              p.accent.withValues(alpha: 0.15),
                                          borderRadius: AppRadii.r12All,
                                        ),
                                        child: Icon(
                                          Icons.history_rounded,
                                          color: p.accent,
                                          size: 26,
                                        ),
                                      ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${l10n.tracksCount(filtered.length).toUpperCase()}'
                                            '${filtered.isNotEmpty ? " • ${Formatters.formatDuration(Duration(milliseconds: totalDurationMs)).toUpperCase()}" : ""}',
                                            style: TextStyle(
                                              fontSize: AppFontSize.tiny,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.8,
                                              color: p.textTertiary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.recentlyPlayed,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: AppFontSize.callout,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.2,
                                              color: p.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            losslessCount > 0
                                                ? '${l10n.browseLosslessHiRes}$losslessCount'
                                                : '${allRecents.length}${l10n.browseRecentSongs}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: AppFontSize.label,
                                              color: losslessCount > 0
                                                  ? p.info
                                                  : p.textSecondary,
                                              fontWeight: losslessCount > 0
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (filtered.isNotEmpty) ...[
                                      const SizedBox(width: AppSpacing.xs),
                                      IconButton.filledTonal(
                                        constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              p.accent.withValues(alpha: 0.15),
                                          foregroundColor: p.accent,
                                        ),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 22,
                                        ),
                                        tooltip:
                                            l10n.playAllCount(filtered.length),
                                        onPressed: () => playerCubit.playSong(
                                          filtered.first,
                                          queue: filtered,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                      IconButton.filledTonal(
                                        constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              p.surfaceContainerHigh,
                                          foregroundColor: p.textPrimary,
                                        ),
                                        icon: const Icon(
                                          Icons.shuffle_rounded,
                                          size: 18,
                                        ),
                                        tooltip: l10n.shuffle,
                                        onPressed: () {
                                          final shuffled =
                                              List<SongsTableData>.from(
                                            filtered,
                                          )..shuffle();
                                          playerCubit.playSong(
                                            shuffled.first,
                                            queue: shuffled,
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // ---------- Filtered Empty State ----------
                          if (filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: PulsrEmptyState(
                                icon: Icons.search_off_rounded,
                                title: l10n.noSongsFound,
                                subtitle: l10n.noResultsFor(_searchQuery),
                                primaryActionLabel:
                                    _searchQuery.isNotEmpty ? l10n.clear : null,
                                primaryActionIcon: _searchQuery.isNotEmpty
                                    ? Icons.clear_rounded
                                    : null,
                                onPrimaryAction: _searchQuery.isNotEmpty
                                    ? () {
                                        _searchDebounce?.cancel();
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      }
                                    : null,
                              ),
                            )
                          else
                            // ---------- Song List ----------
                            SliverList.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final song = filtered[index];
                                return StaggeredListItem(
                                  index: index,
                                  child: PulsrDismissible(
                                    key: ValueKey(
                                      'recent_${song.id}_$index',
                                    ),
                                    startToEndLabel: l10n.playNext,
                                    dismissDirection:
                                        DismissDirection.startToEnd,
                                    backgroundBuilder:
                                        (context, isConfirming) =>
                                            PulsrDismissible
                                                .buildActionBackground(
                                      context: context,
                                      icon: Icons.playlist_play_rounded,
                                      label: l10n.playNext,
                                      color: p.accent,
                                      backgroundColor: p.accentContainer,
                                      isConfirming: isConfirming,
                                    ),
                                    onConfirm: (direction) async {
                                      if (direction ==
                                          DismissDirection.startToEnd) {
                                        playerCubit.playNext(song);
                                      }
                                      return false;
                                    },
                                    child: SongTile(
                                      song: song,
                                      index: index,
                                      onTap: () => playerCubit.playSong(
                                        song,
                                        queue: filtered,
                                      ),
                                      onMorePressed: () =>
                                          SongOptionsSheet.show(
                                        context,
                                        song: song,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                          // ---------- Load More Pagination ----------
                          if (_hasMore &&
                              allRecents.length >= _historyLimit &&
                              _historyLimit < _maxHistoryLimit &&
                              _searchQuery.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md,
                                ),
                                child: Center(
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: p.surfaceContainer,
                                      foregroundColor: p.textPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.lg,
                                        vertical: AppSpacing.sm,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppRadii.r12All,
                                        side: BorderSide(color: p.hairline),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      '${l10n.loadMoreHistory} (${allRecents.length})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    onPressed: () {
                                      if (allRecents.length < _historyLimit) {
                                        setState(() => _hasMore = false);
                                        return;
                                      }
                                      setState(() {
                                        _historyLimit = (_historyLimit + 100)
                                            .clamp(
                                              _persistedHistoryLimit,
                                              _maxHistoryLimit,
                                            );
                                        _updateStream();
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),

                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: PulsrLayoutMetrics.scrollBottom(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}