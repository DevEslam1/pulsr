// lib/features/library/presentation/duplicate_finder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/duplicate_finder_service.dart';
import '../../../core/services/missing_artwork_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../player/cubit/player_cubit.dart';
import 'library_quality_utils.dart';

class DuplicateFinderScreen extends StatefulWidget {
  const DuplicateFinderScreen({super.key});

  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

enum _ResolveAction { keep, delete }

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  late final DuplicateFinderService _finder;
  List<DuplicateGroup> _duplicateGroups = [];
  final Map<String, int> _keptSongByGroup = {};
  bool _isScanning = true;
  bool _isFetchingArtwork = false;

  /// A failed scan must not fall through to the "no duplicates" success view:
  /// an empty [_duplicateGroups] after a failure would falsely claim the
  /// library is clean.
  bool _scanFailed = false;
  bool _isBulkDeleting = false;

  @override
  void initState() {
    super.initState();
    _finder = getIt<DuplicateFinderService>();
    _scan();
  }

  Future<void> _scan() async {
    if (mounted) {
      setState(() {
        _isScanning = true;
        _scanFailed = false;
      });
    }
    try {
      var songs = const <SongsTableData>[];
      if (getIt.isRegistered<IMusicRepository>()) {
        var excluded = const <String>[];
        try {
          final excludedRes =
              await getIt<IMusicRepository>().getExcludedFolderPaths();
          excluded = excludedRes.fold((_) => <String>[], (list) => list);
        } catch (_) {
          // A failed exclusion lookup must not abort the duplicate scan.
        }
        final res = await getIt<IMusicRepository>()
            .getAllSongs(excludedFolders: excluded);
        songs = res.fold((_) => const <SongsTableData>[], (list) => list);
      }
      // CUE chapter rows share the container's path/duration/fileSize, so the
      // checksum pass would hash one file per chapter and report every chapter
      // as an identical copy of its siblings. Skip them: only real file rows
      // (cueStartMs == null) are duplicate candidates.
      songs = songs.where((s) => s.cueStartMs == null).toList();
      final duplicates = await _finder.findDuplicates(songs);
      if (!mounted) return;
      setState(() {
        _duplicateGroups = duplicates;
        _keptSongByGroup
            .removeWhere((key, _) => !duplicates.any((g) => g.key == key));
      });
    } catch (e, st) {
      // BUG-17: never let a scan failure leave the spinner running forever.
      ErrorLogger.log(
        'Duplicate scan failed',
        error: e,
        stackTrace: st,
        category: 'DuplicateFinder',
      );
      if (mounted) setState(() => _scanFailed = true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _fetchMissingArtwork() async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.fetchMissingArtworkTitle,
      message: l10n.fetchMissingArtworkBody,
      icon: Icons.image_search_rounded,
      confirmLabel: l10n.fetchArtwork,
    );
    if (confirmed != true || !mounted) return;
    if (!getIt.isRegistered<MissingArtworkService>()) {
      PulsrToast.show(
        context,
        message: l10n.artworkServiceUnavailable,
        isError: true,
      );
      return;
    }
    setState(() => _isFetchingArtwork = true);
    final count =
        await getIt<MissingArtworkService>().fetchAndPersistMissingArtwork();
    if (!mounted) return;
    setState(() => _isFetchingArtwork = false);
    PulsrToast.show(
      context,
      message: count == 0
          ? l10n.noMissingArtworkFound
          : l10n.updatedArtworkForAlbums(count),
      icon: Icons.image_rounded,
    );
  }

  int _compareSongQuality(SongsTableData a, SongsTableData b) {
    final aLossless = isLosslessSong(a);
    final bLossless = isLosslessSong(b);
    if (aLossless != bLossless) return aLossless ? -1 : 1;

    final aBitDepth = a.bitDepth ?? 0;
    final bBitDepth = b.bitDepth ?? 0;
    if (aBitDepth != bBitDepth) return bBitDepth.compareTo(aBitDepth);

    final aSampleRate = a.sampleRate ?? 0;
    final bSampleRate = b.sampleRate ?? 0;
    if (aSampleRate != bSampleRate) return bSampleRate.compareTo(aSampleRate);

    final aBitrate = a.bitrateKbps ?? 0;
    final bBitrate = b.bitrateKbps ?? 0;
    if (aBitrate != bBitrate) return bBitrate.compareTo(aBitrate);

    final aSize = a.fileSize ?? 0;
    final bSize = b.fileSize ?? 0;
    return bSize.compareTo(aSize);
  }

  void _autoSelectBestQuality() {
    int updatedCount = 0;
    for (final group in _duplicateGroups) {
      if (group.songs.isEmpty) continue;
      final sorted = List<SongsTableData>.from(group.songs)
        ..sort(_compareSongQuality);
      _keptSongByGroup[group.key] = sorted.first.id;
      updatedCount++;
    }
    setState(() {});
    if (!mounted) return;
    PulsrToast.show(
      context,
      message: context.l10n.selectedHighestQuality(updatedCount),
      icon: Icons.auto_awesome_rounded,
    );
  }

  /// Every copy that is not the explicitly kept row, across all groups where a
  /// keeper was chosen. Used by the bulk cleanup action.
  List<SongsTableData> _nonKeptDuplicates() {
    final targets = <SongsTableData>[];
    for (final group in _duplicateGroups) {
      final keptId = _keptSongByGroup[group.key];
      if (keptId == null) continue;
      for (final song in group.songs) {
        if (song.id != keptId) targets.add(song);
      }
    }
    return targets;
  }

  /// Estimates total reclaimable bytes across all duplicate groups if the single
  /// best copy (or user-selected keeper) is retained per group.
  int _estimateReclaimableBytes() {
    int bytes = 0;
    for (final group in _duplicateGroups) {
      if (group.songs.length < 2) continue;
      final keptId = _keptSongByGroup[group.key] ??
          (List<SongsTableData>.from(group.songs)..sort(_compareSongQuality))
              .first
              .id;
      for (final s in group.songs) {
        if (s.id != keptId) {
          bytes += s.fileSize ?? 0;
        }
      }
    }
    return bytes;
  }

  Future<void> _deleteNonKeptDuplicates() async {
    if (_isBulkDeleting) return;
    final targets = _nonKeptDuplicates();
    if (targets.isEmpty) return;

    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.delete,
      message: l10n.deleteMultipleConfirmation(targets.length),
      icon: Icons.delete_sweep_rounded,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    if (!getIt.isRegistered<IMusicRepository>()) {
      PulsrToast.show(
        context,
        message: l10n.deleteIsUnavailable,
        isError: true,
      );
      return;
    }

    setState(() => _isBulkDeleting = true);
    final ids = targets.map((s) => s.id).toSet();
    final res = await getIt<IMusicRepository>().deleteSongs(ids.toList());
    if (!mounted) return;
    setState(() => _isBulkDeleting = false);

    res.fold(
      (failure) => PulsrToast.show(
        context,
        message: l10n.failedToDelete(failure.message),
        isError: true,
      ),
      (_) {
        setState(() {
          _duplicateGroups = _duplicateGroups
              .map(
                (g) => DuplicateGroup(
                  key: g.key,
                  reason: g.reason,
                  songs: g.songs.where((s) => !ids.contains(s.id)).toList(),
                ),
              )
              .where((g) => g.songs.length > 1)
              .toList();
          final groupKeys = _duplicateGroups.map((g) => g.key).toSet();
          _keptSongByGroup.removeWhere((key, _) => !groupKeys.contains(key));
        });
        if (!mounted) return;
        PulsrToast.show(
          context,
          message: l10n.songsDeleted,
          icon: Icons.delete_outline_rounded,
        );
      },
    );
  }

  Future<void> _showResolveSheet(
    DuplicateGroup group,
    SongsTableData song,
  ) async {
    final p = context.palette;
    final l10n = context.l10n;
    final action = await PulsrSheetHelper.showPulsrSheet<_ResolveAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.check_circle_outline_rounded,
                color: p.accent,
              ),
              title: Text(
                l10n.keepThisOne,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.markAsCopyToKeep(song.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, _ResolveAction.keep),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: p.error),
              title: Text(
                l10n.deleteFile,
                style: TextStyle(
                  color: p.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.removeFromDevice(song.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, _ResolveAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _ResolveAction.keep) {
      _keepSong(group, song);
    } else {
      await _confirmDelete(group, song);
    }
  }

  void _keepSong(DuplicateGroup group, SongsTableData song) {
    setState(() => _keptSongByGroup[group.key] = song.id);
    if (!mounted) return;
    PulsrToast.show(
      context,
      message: context.l10n.keepingTitle(song.title),
      icon: Icons.check_circle_rounded,
    );
  }

  Future<void> _confirmDelete(DuplicateGroup group, SongsTableData song) async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.deleteThisFile,
      message: l10n.deleteFileConfirmBody(song.title),
      icon: Icons.delete_outline_rounded,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _deleteSong(group, song);
  }

  Future<void> _deleteSong(DuplicateGroup group, SongsTableData song) async {
    final l10n = context.l10n;
    if (!getIt.isRegistered<IMusicRepository>()) {
      PulsrToast.show(
        context,
        message: l10n.deleteIsUnavailable,
        isError: true,
      );
      return;
    }
    final res = await getIt<IMusicRepository>().deleteSongs([song.id]);
    if (!mounted) return;
    res.fold(
      (failure) => PulsrToast.show(
        context,
        message: l10n.failedToDelete(failure.message),
        isError: true,
      ),
      (_) {
        setState(() {
          _duplicateGroups = _duplicateGroups
              .map(
                (g) => DuplicateGroup(
                  key: g.key,
                  reason: g.reason,
                  songs: g.songs.where((s) => s.id != song.id).toList(),
                ),
              )
              .where((g) => g.songs.length > 1)
              .toList();
          if (_keptSongByGroup[group.key] == song.id) {
            _keptSongByGroup.remove(group.key);
          }
        });
        if (!mounted) return;
        PulsrToast.show(
          context,
          message: l10n.deletedTitle(song.title),
          icon: Icons.delete_outline_rounded,
        );
      },
    );
  }

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
          title: Text(
            context.l10n.duplicateCleaner,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.bodyLarge,
            ),
          ),
          actions: [
            if (_duplicateGroups.isNotEmpty)
              IconButton(
                icon: Icon(Icons.auto_awesome_rounded, color: p.accent),
                tooltip: context.l10n.keepBestQualityForAll,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                onPressed: _autoSelectBestQuality,
              ),
            if (_keptSongByGroup.isNotEmpty)
              IconButton(
                icon: _isBulkDeleting
                    ? SizedBox(
                        width: AppSpacing.s20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.error,
                        ),
                      )
                    : Icon(Icons.delete_sweep_rounded, color: p.error),
                tooltip: context.l10n.delete,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                onPressed: _isBulkDeleting ? null : _deleteNonKeptDuplicates,
              ),
            IconButton(
              icon: _isFetchingArtwork
                  ? SizedBox(
                      width: AppSpacing.s20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.primary,
                      ),
                    )
                  : Icon(Icons.image_search_rounded, color: p.textSecondary),
              tooltip: context.l10n.fetchMissingArtworkTooltip,
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              onPressed: _isFetchingArtwork ? null : _fetchMissingArtwork,
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: p.textSecondary),
              tooltip: context.l10n.rescanLibrary,
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              onPressed: _isScanning ? null : _scan,
            ),
          ],
        ),
        body: RefreshIndicator(
          color: p.accent,
          backgroundColor: p.surfaceContainer,
          onRefresh: _scan,
          child: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: _buildBody(p),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(PulsrPalette p) {
    if (_isScanning) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: SkeletonList(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            120,
          ),
        ),
      );
    }

    if (_scanFailed) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          PulsrEmptyState(
            icon: Icons.error_outline_rounded,
            iconColor: p.error,
            title: context.l10n.browseFailedToFetch,
            subtitle: context.l10n.libraryReadError,
            primaryActionLabel: context.l10n.retry,
            primaryActionIcon: Icons.refresh_rounded,
            onPrimaryAction: _scan,
          ),
        ],
      );
    }

    if (_duplicateGroups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          PulsrEmptyState(
            icon: Icons.check_circle_outline_rounded,
            iconColor: p.accent,
            title: context.l10n.noDuplicatesFound,
            subtitle: context.l10n.libraryCleanlyOrganized,
          ),
        ],
      );
    }

    final nonKeptTargets = _nonKeptDuplicates();
    final reclaimableMb =
        (_estimateReclaimableBytes() / (1024 * 1024)).toStringAsFixed(1);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // ---------- Summary & Batch Action Banner ----------
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: (p.isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.05),
                borderRadius: AppRadii.r18All,
                border: Border.all(
                  color: (p.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s10),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.15),
                          borderRadius: AppRadii.r12All,
                        ),
                        child: Icon(
                          Icons.library_music_rounded,
                          color: p.accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_duplicateGroups.length} • ~$reclaimableMb MB',
                              style: TextStyle(
                                fontSize: AppFontSize.callout,
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.keepBestQualityForAll,
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
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _autoSelectBestQuality,
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                          ),
                          label: Text(
                            context.l10n.keepBestQualityForAll,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent.withValues(alpha: 0.16),
                            foregroundColor: p.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All,
                            ),
                          ),
                        ),
                      ),
                      if (nonKeptTargets.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.xs),
                        FilledButton.icon(
                          onPressed: _isBulkDeleting
                              ? null
                              : _deleteNonKeptDuplicates,
                          icon: const Icon(
                            Icons.delete_sweep_rounded,
                            size: 18,
                          ),
                          label: Text(
                            '${context.l10n.delete} (${nonKeptTargets.length})',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.error,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // ---------- Duplicate Groups List ----------
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            PulsrLayoutMetrics.scrollBottom(context),
          ),
          sliver: SliverList.separated(
            itemCount: _duplicateGroups.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final group = _duplicateGroups[index];
              final keptId = _keptSongByGroup[group.key];
              return Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: AppRadii.r18All,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                        vertical: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.copy_all_rounded,
                            size: 16,
                            color: p.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              group.reason,
                              style: TextStyle(
                                fontSize: AppFontSize.bodySmall,
                                fontWeight: FontWeight.w700,
                                color: p.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: p.surfaceContainer,
                              borderRadius: AppRadii.r8All,
                            ),
                            child: Text(
                              context.l10n.tracksCount(group.songs.length),
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final song in group.songs)
                      _buildDuplicateSongRow(
                        context,
                        group: group,
                        song: song,
                        isKept: song.id == keptId,
                        p: p,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDuplicateSongRow(
    BuildContext context, {
    required DuplicateGroup group,
    required SongsTableData song,
    required bool isKept,
    required PulsrPalette p,
  }) {
    final specs = formatSongTechSpecs(song);
    final lossless = isLosslessSong(song);

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: isKept ? p.accent.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: AppRadii.r12All,
        border: isKept
            ? Border.all(color: p.accent.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SongTile(
            song: song,
            onTap: () => context.read<PlayerCubit>().playSong(song),
            onLongPress: () => _showResolveSheet(group, song),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isKept)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.18),
                      borderRadius: AppRadii.r8All,
                    ),
                    child: Text(
                      context.l10n.kept,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                        color: p.accent,
                      ),
                    ),
                  ),
                PopupMenuButton<_ResolveAction>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: p.textTertiary,
                  ),
                  tooltip: context.l10n.resolveDuplicate,
                  onSelected: (action) {
                    if (action == _ResolveAction.keep) {
                      _keepSong(group, song);
                    } else {
                      _confirmDelete(group, song);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: _ResolveAction.keep,
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                            color: p.accent,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(context.l10n.keepThisOne),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _ResolveAction.delete,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: p.error,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(context.l10n.deleteFile),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (specs.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                68,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (lossless)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: p.info.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r4All,
                      ),
                      child: Text(
                        isHiResSong(song) ? 'HI-RES' : 'LOSSLESS',
                        style: TextStyle(
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w800,
                          color: p.info,
                        ),
                      ),
                    ),
                  Text(
                    specs,
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w600,
                      color: p.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}