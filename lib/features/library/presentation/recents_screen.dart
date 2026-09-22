import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_info_sheet.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  // FIX-M3: Static default history limit
  static const int _persistedHistoryLimit = 100;
  int _historyLimit = _persistedHistoryLimit;
  late final GetSongsUseCase _getSongsUseCase;

  @override
  void initState() {
    super.initState();
    _getSongsUseCase = getIt<GetSongsUseCase>();
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
          s.artist.toLowerCase().contains(q);
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
        (err) => PulsrToast.show(context,
            message:
                '${context.l10n.browseClearHistoryFailed}: ${err.message}',
            isError: true),
        (_) => PulsrToast.show(context,
            message: context.l10n.browseHistoryCleared,
            icon: Icons.history_rounded),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(context.l10n.recentlyPlayed,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppFontSize.bodyLarge),
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.browseClearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _showClearConfirmation(context),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _getSongsUseCase.watchRecentlyPlayed(limit: _historyLimit),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const SkeletonList();
          }

          final allRecents =
              snapshot.data?.fold((l) => <SongsTableData>[], (r) => r) ?? [];

          if (allRecents.isEmpty) {
            return RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              onRefresh: () async {
                if (mounted) setState(() {});
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  EmptyStateWidget(
                    icon: Icons.history_toggle_off_rounded,
                    title: context.l10n.noRecentSongs,
                    subtitle: context.l10n.recentEmptyHint,
                  ),
                ],
              ),
            );
          }

          final filtered = _filterSongs(allRecents);

          return RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surfaceContainer,
            onRefresh: () async {
              if (mounted) setState(() {});
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
              // Search & Header Stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                  child: Column(
                    children: [
                      // Search bar
                      GlassContainer(
                        blur: 16,
                        opacity: p.isDark ? 0.9 : 0.95,
                        borderRadius: AppRadii.full,
                        color: p.surfaceContainer,
                        border: Border.all(color: p.hairline, width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                color: p.textSecondary, size: 20),
                            const SizedBox(width: AppSpacing.s10),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) {
                                  _searchDebounce?.cancel();
                                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                                    if (mounted) setState(() => _searchQuery = val);
                                  });
                                },
                                style: TextStyle(
                                    color: p.textPrimary, fontSize: AppFontSize.body),
                                decoration: InputDecoration(
                                  hintText:
                                      '${context.l10n.search} ${allRecents.length} ${context.l10n.browseRecentSongs}...',
                                  hintStyle: TextStyle(
                                      color: p.textTertiary, fontSize: AppFontSize.bodySmall),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                ),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                                IconButton(
                                  icon: Icon(Icons.close_rounded,
                                      color: p.textSecondary, size: 18),
                                  tooltip: context.l10n.clear,
                                  onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s14),
                      // Action buttons: Play All & Shuffle
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                if (filtered.isNotEmpty) {
                                  playerCubit.playSong(filtered.first,
                                      queue: filtered);
                                }
                              },
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 20),
                              label: Text(context.l10n.playAllCount(filtered.length)),
                              style: FilledButton.styleFrom(
                                backgroundColor: p.accent,
                                foregroundColor: p.onAccent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadii.buttonRadius,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: () {
                              if (filtered.isNotEmpty) {
                                final shuffled = List<SongsTableData>.from(
                                    filtered)..shuffle();
                                playerCubit.playSong(shuffled.first,
                                    queue: shuffled);
                              }
                            },
                            icon: const Icon(Icons.shuffle_rounded, size: 20),
                            label: Text(context.l10n.shuffle),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.textPrimary,
                              side: BorderSide(color: p.hairline),
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm, horizontal: AppSpacing.md),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadii.buttonRadius,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Song List
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateWidget(
                    icon: Icons.search_off_rounded,
                    title: context.l10n.noSongsFound,
                    subtitle: context.l10n.noResultsFor(_searchQuery),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsetsDirectional.only(top: AppSpacing.xs, bottom: 100, start: AppSpacing.md, end: AppSpacing.md),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      (context, index) {
                        final song = filtered[index];
                        return StaggeredListItem(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: AppRadii.cardRadius,
                                onTap: () => playerCubit.playSong(song,
                                    queue: filtered),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(

                                      horizontal: AppSpacing.s10, vertical: AppSpacing.xs),
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadii.cardRadius,
                                    color: p.surfaceContainer.withValues(
                                        alpha: p.isDark ? 0.3 : 0.6),
                                  ),
                                  child: Row(
                                    children: [
                                      // Index number
                                      SizedBox(width: AppSpacing.lg,
                                        child: Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: p.textTertiary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: AppFontSize.label,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      // Artwork
                                      CachedArtwork(
                                        id: song.id,
                                        remoteUrl: song.remoteArtworkUrl,
                                        type: ArtworkType.AUDIO,
                                        size: 46,
                                        borderRadius: 12,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      // Title & Artist
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.textPrimary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: AppFontSize.body,
                                              ),
                                            ),
                                            const SizedBox(height: AppSpacing.s2),
                                            Text(
                                              song.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: AppFontSize.label,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // More menu
                                        IconButton(
                                          icon: const Icon(
                                              Icons.more_vert_rounded,
                                              size: 20),
                                          color: p.textSecondary,
                                          tooltip: MaterialLocalizations.of(
                                                  context)
                                              .moreButtonTooltip,
                                          onPressed: () {
                                          _showSongOptions(context, song);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
              if (allRecents.length >= _historyLimit && _searchQuery.isEmpty && _historyLimit < 500)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(context.l10n.loadMoreHistory),
                        onPressed: () {
                          setState(() {
                            _historyLimit = (_historyLimit + 100).clamp(100, 500);
                          });
                        },
                      ),
                    ),
                  ),
                ),
            ],
            ),
          );
        },
      ),
    ),
  );
}

  void _showSongOptions(BuildContext context, SongsTableData song) {
    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsrPressable(
            onTap: () {
              Navigator.pop(ctx);
              AddToPlaylistSheet.show(context, song: song);
            },
            child: ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(context.l10n.addToPlaylist),
            ),
          ),
          PulsrPressable(
            onTap: () {
              Navigator.pop(ctx);
              SongInfoSheet.show(context, song: song);
            },
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(context.l10n.songInfo),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
