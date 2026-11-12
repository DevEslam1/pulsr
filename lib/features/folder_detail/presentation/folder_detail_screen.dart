// lib/features/folder_detail/presentation/folder_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/detail_scaffold.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import '../../sheets/song_options_sheet.dart';

import '../../../core/utils/pulsr_haptics.dart';
enum _FolderSortMode {
  natural,
  title,
  artist,
  duration,
}

class FolderDetailScreen extends StatefulWidget {
  final FolderItem folder;
  final FolderUseCases? folderUseCases;

  const FolderDetailScreen({
    super.key,
    required this.folder,
    this.folderUseCases,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  late final FolderUseCases _useCase;
  late final ScrollController _scrollController;
  late Stream<Result<List<SongsTableData>>> _songsStream;
  late bool _isExcluded;
  bool _showCollapsedTitle = false;
  bool _favoriteAllBusy = false;
  _FolderSortMode _sortMode = _FolderSortMode.natural;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _useCase = widget.folderUseCases ?? getIt<FolderUseCases>();
    _updateStream();
    _isExcluded = widget.folder.isExcluded;
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _updateStream() {
    _songsStream = _useCase.watchFolderSongs(widget.folder.path).distinct();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final show = offset > 160;
    if (show != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = show);
    }
  }

  List<SongsTableData> _sortedSongs(List<SongsTableData> raw) {
    if (_sortMode == _FolderSortMode.natural && _sortAscending) {
      return raw;
    }
    final copy = List<SongsTableData>.from(raw);
    copy.sort((a, b) {
      int cmp;
      switch (_sortMode) {
        case _FolderSortMode.natural:
          cmp = 0;
          break;
        case _FolderSortMode.title:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case _FolderSortMode.artist:
          cmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          if (cmp == 0) {
            cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          }
          break;
        case _FolderSortMode.duration:
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    if (_sortMode == _FolderSortMode.natural && !_sortAscending) {
      return copy.reversed.toList();
    }
    return copy;
  }

  void _cycleSortMode() {
    PulsrHaptics.selectionClick();
    setState(() {
      const values = _FolderSortMode.values;
      final nextIndex = (_sortMode.index + 1) % values.length;
      _sortMode = values[nextIndex];
    });
  }

  void _toggleSortDirection() {
    PulsrHaptics.selectionClick();
    setState(() => _sortAscending = !_sortAscending);
  }

  IconData _sortIcon(_FolderSortMode mode) {
    switch (mode) {
      case _FolderSortMode.natural:
        return Icons.format_list_numbered_rounded;
      case _FolderSortMode.title:
        return Icons.sort_by_alpha_rounded;
      case _FolderSortMode.artist:
        return Icons.person_outline_rounded;
      case _FolderSortMode.duration:
        return Icons.schedule_rounded;
    }
  }

  Future<void> _toggleExclusion() async {
    final prevExcluded = _isExcluded;
    final newExcluded = !prevExcluded;
    setState(() => _isExcluded = newExcluded);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    LibraryCubit? libraryCubit;
    try {
      libraryCubit = context.read<LibraryCubit>();
    } catch (_) {}

    Result<void> result;
    try {
      if (libraryCubit != null) {
        result = await libraryCubit.toggleFolderExclusion(widget.folder.path);
      } else {
        result = await _useCase.toggleExcludeFolder(widget.folder.path);
      }
    } catch (e) {
      result = Left(DatabaseFailure(e.toString()));
    }

    if (!mounted) return;
    final failureMessage = result.fold<String?>((l) => l.message, (_) => null);
    if (failureMessage != null) {
      setState(() => _isExcluded = prevExcluded);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
      return;
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          newExcluded ? l10n.folderExcluded : l10n.folderIncluded,
        ),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () async {
            if (mounted) setState(() => _isExcluded = prevExcluded);
            try {
              if (libraryCubit != null) {
                await libraryCubit.toggleFolderExclusion(widget.folder.path);
              } else {
                await _useCase.toggleExcludeFolder(widget.folder.path);
              }
            } catch (_) {
              if (mounted) setState(() => _isExcluded = newExcluded);
            }
          },
        ),
      ),
    );
  }

  String _formatTotalDuration(int totalMs) {
    final d = Duration(milliseconds: totalMs);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  String _formatTrackDuration(int ms) {
    if (ms <= 0) return '--:--';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool _isAllFavorited(List<SongsTableData> songs) =>
      songs.isNotEmpty && songs.every((s) => s.isFavorite);

  Future<void> _toggleFavoriteFolder(List<SongsTableData> songs) async {
    if (songs.isEmpty || _favoriteAllBusy) return;
    _favoriteAllBusy = true;
    PulsrHaptics.lightImpact();
    try {
      LibraryCubit? libraryCubit;
      try {
        libraryCubit = context.read<LibraryCubit>();
      } catch (_) {}
      if (libraryCubit == null) return;

      final allFavorited = _isAllFavorited(songs);

      if (allFavorited) {
        for (final s in songs) {
          if (s.isFavorite) {
            await libraryCubit.toggleFavorite(s.id);
          }
        }
        if (mounted) {
          PulsrToast.show(
            context,
            message: context.l10n.removeFromFavorites,
            icon: Icons.favorite_border_rounded,
          );
        }
      } else {
        for (final s in songs) {
          if (!s.isFavorite) {
            await libraryCubit.toggleFavorite(s.id);
          }
        }
        if (mounted) {
          PulsrToast.show(
            context,
            message: context.l10n.favorite,
            icon: Icons.favorite_rounded,
          );
        }
      }
    } finally {
      _favoriteAllBusy = false;
    }
  }

  void _copyFolderPath() {
    PulsrHaptics.selectionClick();
    Clipboard.setData(ClipboardData(text: widget.folder.path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.l10n.browseCopy}: ${widget.folder.name}'),
      ),
    );
  }

  void _showFolderOptionsMenu(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    PulsrHaptics.lightImpact();
    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (ctx) => PulsrBottomSheet(
        title: Text(
          widget.folder.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          widget.folder.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (songs.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(context.l10n.playNext),
                onTap: () async {
                  final cubit = context.read<PlayerCubit>();
                  Navigator.pop(ctx);
                  for (final s in songs.reversed) {
                    await cubit.playNext(s);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(context.l10n.addToQueue),
                onTap: () {
                  final cubit = context.read<PlayerCubit>();
                  Navigator.pop(ctx);
                  cubit.addAllToQueue(songs);
                },
              ),
            ],
            ListTile(
              leading: Icon(
                _isExcluded
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: _isExcluded ? p.accent : p.error,
              ),
              title: Text(
                _isExcluded
                    ? context.l10n.browseIncludeInScan
                    : context.l10n.browseExcludeFromScan,
              ),
              onTap: () {
                Navigator.pop(ctx);
                _toggleExclusion();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(context.l10n.browseCopy),
              subtitle: Text(
                widget.folder.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(ctx);
                _copyFolderPath();
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _actionButtons(BuildContext context, List<SongsTableData> songs) {
    final p = context.palette;
    final allFavorited = _isAllFavorited(songs);
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
                : () {
                    PulsrHaptics.mediumImpact();
                    context
                        .read<PlayerCubit>()
                        .playSong(songs.first, queue: songs);
                  },
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(
              context.l10n.playAll,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
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
                    PulsrHaptics.mediumImpact();
                    final shuffled = List<SongsTableData>.from(songs)
                      ..shuffle();
                    context
                        .read<PlayerCubit>()
                        .playSong(shuffled.first, queue: shuffled);
                  },
            icon: Icon(Icons.shuffle_rounded, color: p.accent, size: 20),
            label: Text(
              context.l10n.shuffle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.filledTonal(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          style: IconButton.styleFrom(
            backgroundColor: p.surfaceContainerHigh,
            foregroundColor: allFavorited ? p.favorite : p.textPrimary,
            side: BorderSide(color: p.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r14All,
            ),
          ),
          onPressed: songs.isEmpty ? null : () => _toggleFavoriteFolder(songs),
          icon: Icon(
            allFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: allFavorited ? p.favorite : p.textPrimary,
            size: 20,
          ),
          tooltip: allFavorited
              ? context.l10n.removeFromFavorites
              : context.l10n.favorite,
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.filledTonal(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          style: IconButton.styleFrom(
            backgroundColor: p.surfaceContainerHigh,
            foregroundColor: p.textPrimary,
            side: BorderSide(color: p.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r14All,
            ),
          ),
          onPressed: () => _showFolderOptionsMenu(context, songs, p),
          icon: const Icon(Icons.info_outline_rounded, size: 20),
          tooltip: context.l10n.browseOpenFolderDetails,
        ),
      ],
    );
  }

  List<({int id, int? albumId, String? remoteUrl})> _extractDistinctArts(
    List<SongsTableData> songs,
  ) {
    final List<({int id, int? albumId, String? remoteUrl})> distinctArts = [];
    final Set<String> seen = {};
    for (final s in songs) {
      final key = s.artworkUri ?? '${s.albumId ?? s.id}';
      if (seen.add(key)) {
        distinctArts.add((
          id: s.id,
          albumId: s.albumId,
          remoteUrl: s.remoteArtworkUrl ?? s.artworkUri,
        ));
        if (distinctArts.length == 4) break;
      }
    }
    return distinctArts;
  }

  Widget _buildImmersiveCover(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    Widget backgroundArt;

    if (songs.isNotEmpty) {
      final featuredSong = songs.firstWhere(
        (s) =>
            s.artworkUri != null ||
            s.remoteArtworkUrl != null ||
            s.albumId != null,
        orElse: () => songs.first,
      );

      backgroundArt = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: CachedArtwork(
            id: featuredSong.id,
            albumId: featuredSong.albumId,
            remoteUrl: featuredSong.remoteArtworkUrl ?? featuredSong.artworkUri,
            size: 600,
            borderRadius: 0,
            highQuality: true,
          ),
        ),
      );
    } else {
      backgroundArt = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              p.accentContainer,
              p.surfaceContainer,
              p.bg,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.folder_rounded,
            size: 100,
            color: p.accent.withValues(alpha: 0.35),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        backgroundArt,
        if (_isExcluded)
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 12,
            end: AppSpacing.md,
            child: _buildExcludedBadge(context, p),
          ),
      ],
    );
  }

  Widget _buildExcludedBadge(BuildContext context, PulsrPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.94),
        borderRadius: AppRadii.r10All,
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.visibility_off_rounded,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            context.l10n.folderPersistentExcludedBadge,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    double size,
  ) {
    final distinctArts = _extractDistinctArts(songs);

    Widget content;
    if (distinctArts.length >= 4) {
      final half = size / 2;
      content = SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: CachedArtwork(
                    id: distinctArts[0].id,
                    albumId: distinctArts[0].albumId,
                    remoteUrl: distinctArts[0].remoteUrl,
                    size: half,
                    borderRadius: 0,
                  ),
                ),
                Expanded(
                  child: CachedArtwork(
                    id: distinctArts[1].id,
                    albumId: distinctArts[1].albumId,
                    remoteUrl: distinctArts[1].remoteUrl,
                    size: half,
                    borderRadius: 0,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: CachedArtwork(
                    id: distinctArts[2].id,
                    albumId: distinctArts[2].albumId,
                    remoteUrl: distinctArts[2].remoteUrl,
                    size: half,
                    borderRadius: 0,
                  ),
                ),
                Expanded(
                  child: CachedArtwork(
                    id: distinctArts[3].id,
                    albumId: distinctArts[3].albumId,
                    remoteUrl: distinctArts[3].remoteUrl,
                    size: half,
                    borderRadius: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else if (distinctArts.isNotEmpty) {
      content = CachedArtwork(
        id: distinctArts.first.id,
        albumId: distinctArts.first.albumId,
        remoteUrl: distinctArts.first.remoteUrl,
        size: size,
        borderRadius: AppRadii.r20,
        highQuality: true,
      );
    } else {
      content = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              p.accentContainer,
              p.surfaceContainer,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            _isExcluded ? Icons.folder_off_rounded : Icons.folder_rounded,
            size: size * 0.42,
            color: _isExcluded ? p.error : p.accent,
          ),
        ),
      );
    }

    return Semantics(
      image: true,
      label: widget.folder.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: AppRadii.r20All,
          border: Border.all(
            color: p.hairline,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrimAt(0.32),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: p.accent.withValues(alpha: 0.14),
              blurRadius: 36,
              spreadRadius: -6,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadii.r20All,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (_isExcluded)
                Container(
                  color: AppColors.scrimAt(0.55),
                  child: Center(child: _buildExcludedBadge(context, p)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    int totalDurationMs, {
    bool compact = false,
  }) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final featuredSong = songs.firstWhere(
      (s) =>
          s.artworkUri != null ||
          s.remoteArtworkUrl != null ||
          s.albumId != null,
      orElse: () => songs.first,
    );

    final artSize = compact ? 44.0 : 50.0;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : Adaptive.pagePadding(context),
        vertical: compact ? AppSpacing.xxs : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.65),
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.r16All,
          onTap: () {
            PulsrHaptics.selectionClick();
            context.read<PlayerCubit>().playSong(featuredSong, queue: songs);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: compact ? AppSpacing.xs : AppSpacing.s10,
            ),
            child: Row(
              children: [
                CachedArtwork(
                  id: featuredSong.id,
                  albumId: featuredSong.albumId,
                  remoteUrl:
                      featuredSong.remoteArtworkUrl ?? featuredSong.artworkUri,
                  size: artSize,
                  borderRadius: AppRadii.r12,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_mosaic_rounded,
                            size: 12,
                            color: p.accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${context.l10n.tracksCount(songs.length).toUpperCase()} • ${_formatTotalDuration(totalDurationMs).toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: p.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        featuredSong.album.isNotEmpty
                            ? featuredSong.album
                            : featuredSong.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        featuredSong.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPathExcluded(String path) {
    try {
      final folders = context.read<LibraryCubit>().state.folders;
      final normalized = path.replaceAll('\\', '/');
      for (final folder in folders) {
        if (folder.path.replaceAll('\\', '/') == normalized) {
          return folder.isExcluded;
        }
      }
    } catch (_) {}
    return false;
  }

  Widget _buildBreadcrumbs(
    BuildContext context,
    PulsrPalette p,
    String fullPath, {
    bool compact = false,
  }) {
    final cleanPath = fullPath.replaceAll('\\', '/');
    final parts = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    final isUnixAbsolute = cleanPath.startsWith('/');
    final isWindowsDrive = RegExp(r'^[A-Za-z]:$').hasMatch(parts.first);

    return GestureDetector(
      onLongPress: _copyFolderPath,
      child: Container(
        height: compact ? 32 : 36,
        margin: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : Adaptive.pagePadding(context),
          vertical: AppSpacing.xxs,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: p.surfaceContainer.withValues(alpha: 0.45),
          borderRadius: AppRadii.r12All,
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 15,
              color: p.accent,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: parts.length,
                separatorBuilder: (_, __) => Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: p.textTertiary.withValues(alpha: 0.55),
                ),
                itemBuilder: (context, index) {
                  final isLast = index == parts.length - 1;
                  final name = parts[index];
                  final joined = parts.sublist(0, index + 1).join('/');
                  final subPath = isWindowsDrive && index == 0
                      ? '$joined/'
                      : isUnixAbsolute
                          ? '/$joined'
                          : joined;

                  return Center(
                    child: Material(
                      color: isLast
                          ? p.accent.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: AppRadii.r8All,
                      child: InkWell(
                        borderRadius: AppRadii.r8All,
                        onTap: isLast
                            ? null
                            : () {
                                PulsrHaptics.selectionClick();
                                context.push(
                                  '/folder',
                                  extra: FolderItem(
                                    path: subPath,
                                    name: name,
                                    songCount: 0,
                                    isExcluded: _isPathExcluded(subPath),
                                  ),
                                );
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s6,
                            vertical: 3,
                          ),
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight:
                                  isLast ? FontWeight.w700 : FontWeight.w500,
                              color: isLast ? p.accent : p.textSecondary,
                            ),
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
      ),
    );
  }

  Widget _buildTrackSectionHeader(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p, {
    required EdgeInsetsGeometry padding,
  }) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(
            context.l10n.browseTopTracks,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.title,
                  letterSpacing: -0.3,
                  color: p.textPrimary,
                ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r10All,
              border: Border.all(color: p.hairline),
            ),
            child: Text(
              '${songs.length}',
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          if (songs.length > 1) ...[
            Material(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r10All,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _cycleSortMode,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.r10All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Icon(
                    _sortIcon(_sortMode),
                    size: 16,
                    color: _sortMode == _FolderSortMode.natural
                        ? p.textSecondary
                        : p.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Material(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r10All,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _toggleSortDirection,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.r10All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Icon(
                    _sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: _sortAscending ? p.textSecondary : p.accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSongRow(
    BuildContext context,
    List<SongsTableData> songs,
    int index,
    PulsrPalette p,
  ) {
    final song = songs[index];
    return BlocSelector<PlayerCubit, PlayerState,
        ({bool isActive, bool isPlaying})>(
      selector: (state) {
        final isActive = state.currentSong?.id == song.id;
        return (isActive: isActive, isPlaying: isActive && state.isPlaying);
      },
      builder: (context, playback) {
        final isActive = playback.isActive;
        final isPlaying = playback.isPlaying;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Adaptive.pagePadding(context),
            vertical: 2,
          ),
          child: AnimatedContainer(
            duration: context.motion(PulsrMotion.state),
            curve: context.motionCurve(PulsrMotion.enter),
            decoration: BoxDecoration(
              color: isActive
                  ? p.accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: AppRadii.r14All,
              border: Border.all(
                color: isActive
                    ? p.accent.withValues(alpha: 0.32)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadii.r14All,
                onTap: () {
                  PulsrHaptics.selectionClick();
                  context.read<PlayerCubit>().playSong(song, queue: songs);
                },
                onLongPress: () {
                  PulsrHaptics.mediumImpact();
                  SongOptionsSheet.show(context, song: song);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.s6,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedArtwork(
                              id: song.id,
                              albumId: song.albumId,
                              remoteUrl:
                                  song.remoteArtworkUrl ?? song.artworkUri,
                              size: 48,
                              borderRadius: AppRadii.r10,
                            ),
                            if (isActive)
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.scrimAt(0.52),
                                  borderRadius: AppRadii.r10All,
                                ),
                                child: Center(
                                  child: NowPlayingIndicator(
                                    color: p.accent,
                                    isPlaying: isPlaying,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive ? p.accent : p.textPrimary,
                                fontWeight: isActive
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: AppFontSize.callout,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${song.artist} • ${song.album.isNotEmpty ? song.album : 'Single'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (song.isFavorite) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: p.favorite,
                        ),
                      ],
                      if (song.durationMs > 0) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _formatTrackDuration(song.durationMs),
                          style: TextStyle(
                            color: isActive ? p.accent : p.textTertiary,
                            fontSize: AppFontSize.tiny,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        tooltip:
                            MaterialLocalizations.of(context).moreButtonTooltip,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: isActive ? p.accent : p.textTertiary,
                        ),
                        onPressed: () {
                          PulsrHaptics.lightImpact();
                          SongOptionsSheet.show(context, song: song);
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
    );
  }

  Widget _buildSplitHero(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
    int totalDurationMs,
  ) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isShort = screenHeight < 480;
    final coverSize = isShort
        ? (screenHeight * 0.28).clamp(96.0, 130.0)
        : (screenHeight * 0.28).clamp(130.0, 230.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCoverArt(context, songs, p, coverSize),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            widget.folder.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: isShort ? 17 : 20,
                  letterSpacing: -0.3,
                  color: p.textPrimary,
                ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${context.l10n.tracksCount(songs.length)} • ${_formatTotalDuration(totalDurationMs)}',
          style: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: _actionButtons(context, songs),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildFeaturedCard(context, songs, p, totalDurationMs, compact: true),
        _buildBreadcrumbs(context, p, widget.folder.path, compact: true),
      ],
    );
  }

  Widget _buildSplitTrackList(
    BuildContext context,
    List<SongsTableData> songs,
    PulsrPalette p,
  ) {
    if (songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: PulsrEmptyState(
          icon: Icons.music_off_rounded,
          title: context.l10n.browseNoTracksFound,
          subtitle: context.l10n.browseNoTracksInFolder,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: PulsrLayoutMetrics.contentMaxWidth(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTrackSectionHeader(
              context,
              songs,
              p,
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
            ),
            for (int i = 0; i < songs.length; i++) ...[
              _buildSongRow(context, songs, i, p),
              if (i < songs.length - 1)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 68),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: p.hairline.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final folder = widget.folder;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLandscape = PulsrBreakpoint.isLandscape(context);
    final isTablet = Adaptive.isTablet(context);
    final isWide = screenWidth >= 800;

    final shouldSplit = isLandscape || (isTablet && isWide);

    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
    final headerHeight = (screenHeight * (isTablet ? 0.30 : 0.32) * textScale)
        .clamp(240.0, isTablet ? 360.0 : 300.0);

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        body: StreamBuilder<Result<List<SongsTableData>>>(
          stream: _songsStream,
          builder: (context, snapshot) {
            Widget buildContent(List<SongsTableData> rawSongs) {
              final songs = _sortedSongs(rawSongs);
              final totalDurationMs =
                  songs.fold<int>(0, (sum, s) => sum + s.durationMs);

              if (shouldSplit) {
                return DetailScaffold(
                  leading: const PulsrBackButton(),
                  leftPaneFlex: isLandscape ? 4.2 : 4.0,
                  rightPaneFlex: isLandscape ? 5.8 : 6.0,
                  hero: _buildSplitHero(context, songs, p, totalDurationMs),
                  body: _buildSplitTrackList(context, songs, p),
                );
              }

              return CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverAppBar(
                    expandedHeight: headerHeight,
                    pinned: true,
                    elevation: 0,
                    backgroundColor: p.bg,
                    surfaceTintColor: Colors.transparent,
                    leading: const PulsrBackButton(),
                    title: AnimatedOpacity(
                      duration: context.motion(PulsrMotion.state),
                      opacity: _showCollapsedTitle ? 1.0 : 0.0,
                      child: Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.subtitle,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    centerTitle: true,
                    actions: [
                      IgnorePointer(
                        ignoring: !_showCollapsedTitle,
                        child: AnimatedOpacity(
                          duration: context.motion(PulsrMotion.state),
                          opacity: _showCollapsedTitle ? 1.0 : 0.0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (songs.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: p.accent,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    PulsrHaptics.mediumImpact();
                                    context
                                        .read<PlayerCubit>()
                                        .playSong(songs.first, queue: songs);
                                  },
                                ),
                              IconButton(
                                icon: Icon(
                                  Icons.more_horiz_rounded,
                                  color: p.textPrimary,
                                ),
                                tooltip: context.l10n.browseOpenFolderDetails,
                                onPressed: () =>
                                    _showFolderOptionsMenu(context, songs, p),
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                            ],
                          ),
                        ),
                      ),
                    ],
                    flexibleSpace: LayoutBuilder(
                      builder: (context, constraints) {
                        final safeTop = MediaQuery.paddingOf(context).top;
                        final minExtent = kToolbarHeight + safeTop;
                        final maxExtent = headerHeight;
                        final delta = maxExtent - minExtent;
                        final currentExtent = constraints.maxHeight;
                        final t = delta > 0
                            ? ((maxExtent - currentExtent) / delta)
                                .clamp(0.0, 1.0)
                            : 0.0;
                        final heroContentOpacity =
                            (1.0 - (t * 2.2)).clamp(0.0, 1.0);

                        return FlexibleSpaceBar(
                          collapseMode: CollapseMode.parallax,
                          background: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildImmersiveCover(context, songs, p),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: const [
                                        0.0,
                                        0.28,
                                        0.55,
                                        0.82,
                                        1.0,
                                      ],
                                      colors: [
                                        AppColors.scrimLight,
                                        Colors.transparent,
                                        p.bg.withValues(alpha: 0.42),
                                        p.bg.withValues(alpha: 0.92),
                                        p.bg,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                start: AppSpacing.lg,
                                end: AppSpacing.lg,
                                bottom: AppSpacing.md,
                                child: Opacity(
                                  opacity: heroContentOpacity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        folder.name,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: screenWidth < 360
                                              ? 22.0
                                              : (isTablet ? 30.0 : 26.0),
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: p.textPrimary,
                                          shadows: p.isDark
                                              ? const [
                                                  Shadow(
                                                    color: Colors.black54,
                                                    blurRadius: 14,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        '${context.l10n.tracksCount(songs.length)} • ${_formatTotalDuration(totalDurationMs)}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: AppFontSize.caption,
                                          fontWeight: FontWeight.w600,
                                          shadows: p.isDark
                                              ? const [
                                                  Shadow(
                                                    color: Colors.black54,
                                                    blurRadius: 10,
                                                    offset: Offset(0, 1),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            PulsrLayoutMetrics.contentConstraints(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                Adaptive.pagePadding(context),
                                AppSpacing.sm,
                                Adaptive.pagePadding(context),
                                AppSpacing.xs,
                              ),
                              child: _actionButtons(context, songs),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _buildFeaturedCard(
                              context,
                              songs,
                              p,
                              totalDurationMs,
                            ),
                            _buildBreadcrumbs(context, p, folder.path),
                            const SizedBox(height: AppSpacing.xs),
                            _buildTrackSectionHeader(
                              context,
                              songs,
                              p,
                              padding: EdgeInsetsDirectional.fromSTEB(
                                Adaptive.pagePadding(context),
                                AppSpacing.sm,
                                Adaptive.pagePadding(context),
                                AppSpacing.xs,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (songs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: PulsrEmptyState(
                          icon: Icons.music_off_rounded,
                          title: context.l10n.browseNoTracksFound,
                          subtitle: context.l10n.browseNoTracksInFolder,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.only(
                        bottom: PulsrLayoutMetrics.scrollBottom(context),
                      ),
                      sliver: SliverList.separated(
                        itemCount: songs.length,
                        separatorBuilder: (_, __) => Center(
                          child: ConstrainedBox(
                            constraints:
                                PulsrLayoutMetrics.contentConstraints(context),
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: 68 + Adaptive.pagePadding(context),
                              ),
                              child: Divider(
                                height: 1,
                                thickness: 0.5,
                                color: p.hairline.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                        itemBuilder: (context, index) => Center(
                          child: ConstrainedBox(
                            constraints:
                                PulsrLayoutMetrics.contentConstraints(context),
                            child: _buildSongRow(context, songs, index, p),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }

            final errorView = PulsrEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: p.error,
              title: context.l10n.couldNotLoadFolderSongs,
              subtitle: context.l10n.libraryReadError,
              primaryActionLabel: context.l10n.retry,
              primaryActionIcon: Icons.refresh_rounded,
              onPrimaryAction: () => setState(_updateStream),
            );

            return AsyncStateBuilder<Result<List<SongsTableData>>>(
              snapshot: snapshot,
              loadingWidget: const SkeletonList(
                padding: EdgeInsets.only(top: AppSpacing.xl),
              ),
              emptyWidget: buildContent(const []),
              onError: (_) => errorView,
              onData: (result) => result.fold(
                (_) => errorView,
                buildContent,
              ),
            );
          },
        ),
      ),
    );
  }
}
