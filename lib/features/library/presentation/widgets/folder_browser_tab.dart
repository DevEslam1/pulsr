// lib/features/library/presentation/widgets/folder_browser_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p_path;
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/responsive/adaptive_grid.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/adaptive.dart';
import 'package:pulsr/core/utils/l10n_extensions.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/core/widgets/pulsr_toast.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';

enum _FolderSort { name, count }

class FolderBrowserTab extends StatefulWidget {
  const FolderBrowserTab({super.key});

  @override
  State<FolderBrowserTab> createState() => _FolderBrowserTabState();
}

class _FolderBrowserTabState extends State<FolderBrowserTab> {
  _FolderSort _sort = _FolderSort.name;
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final folders = state.folders;
        final cubit = context.read<LibraryCubit>();
        final isGrid = state.viewMode == LibraryViewMode.grid;

        Future<void> onRefresh() async {
          final settingsCubit = context.read<SettingsCubit>();
          final count = await settingsCubit.rescanLibrary();
          if (context.mounted) {
            await cubit.init();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.scanComplete(count))),
            );
          }
        }

        if (folders.isEmpty) {
          return RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surfaceContainer,
            onRefresh: onRefresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: PulsrEmptyState(
                        icon: Icons.folder_off_rounded,
                        title: context.l10n.noFoldersFound,
                        subtitle: context.l10n.noFoldersSubtitle,
                        primaryActionLabel: context.l10n.scanStorage,
                        primaryActionIcon: Icons.center_focus_strong_rounded,
                        onPrimaryAction: onRefresh,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        final sortedFolders = List<FolderItem>.from(folders);
        if (_sort == _FolderSort.name) {
          sortedFolders.sort((a, b) => _ascending
              ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
              : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        } else {
          sortedFolders.sort((a, b) => _ascending
              ? a.songCount.compareTo(b.songCount)
              : b.songCount.compareTo(a.songCount));
        }

        // Precompute parent-directory -> representative song map for O(1) artwork lookups
        final representativeByDir = <String, SongsTableData>{};
        for (final s in state.songs) {
          final normalized = p_path.posix
              .normalize(s.path.replaceAll('\\', '/'))
              .toLowerCase();
          representativeByDir.putIfAbsent(
            p_path.posix.dirname(normalized),
            () => s,
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              onRefresh: onRefresh,
              child: isGrid
                  ? _buildGridView(
                      context: context,
                      sortedFolders: sortedFolders,
                      representativeByDir: representativeByDir,
                      p: p,
                      cubit: cubit,
                    )
                  : _buildListView(
                      context: context,
                      sortedFolders: sortedFolders,
                      representativeByDir: representativeByDir,
                      p: p,
                      cubit: cubit,
                    ),
            ),
          ),
        );
      },
    );
  }

  // ================= LIST VIEW =================
  Widget _buildListView({
    required BuildContext context,
    required List<FolderItem> sortedFolders,
    required Map<String, SongsTableData> representativeByDir,
    required PulsrPalette p,
    required LibraryCubit cubit,
  }) {
    final pagePadding = Adaptive.pagePadding(context);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      padding: EdgeInsetsDirectional.only(
        bottom: PulsrLayoutMetrics.scrollBottom(context),
        top: AppSpacing.xxs,
        start: pagePadding,
        end: pagePadding,
      ),
      // 1 item for sort toolbar + folder cards + 1 helper footer card
      itemCount: sortedFolders.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSortToolbar(context, p);
        }

        if (index == sortedFolders.length + 1) {
          return _buildStorageHelperFooter(context, p);
        }

        final folder = sortedFolders[index - 1];
        final isDownloads = _isDownloadsFolder(folder);

        return _buildFolderListTile(
          context: context,
          folder: folder,
          representativeByDir: representativeByDir,
          p: p,
          isDownloads: isDownloads,
          cubit: cubit,
        );
      },
    );
  }

  // ================= GRID VIEW =================
  Widget _buildGridView({
    required BuildContext context,
    required List<FolderItem> sortedFolders,
    required Map<String, SongsTableData> representativeByDir,
    required PulsrPalette p,
    required LibraryCubit cubit,
  }) {
    final pagePadding = Adaptive.pagePadding(context);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(
            pagePadding,
            AppSpacing.xxs,
            pagePadding,
            AppSpacing.xs,
          ),
          sliver: SliverToBoxAdapter(
            child: _buildSortToolbar(context, p),
          ),
        ),
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(
            pagePadding,
            0,
            pagePadding,
            AppSpacing.sm,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: PulsrAdaptiveGrid.columns(
                context,
                type: GridType.albums,
              ),
              crossAxisSpacing: 14,
              mainAxisSpacing: 16,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final folder = sortedFolders[index];
                final isDownloads = _isDownloadsFolder(folder);
                return _buildFolderGridCard(
                  context: context,
                  folder: folder,
                  representativeByDir: representativeByDir,
                  p: p,
                  isDownloads: isDownloads,
                  cubit: cubit,
                );
              },
              childCount: sortedFolders.length,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(
            pagePadding,
            AppSpacing.xs,
            pagePadding,
            PulsrLayoutMetrics.scrollBottom(context),
          ),
          sliver: SliverToBoxAdapter(
            child: _buildStorageHelperFooter(context, p),
          ),
        ),
      ],
    );
  }

  // ================= SORT SUB-BAR =================
  Widget _buildSortToolbar(BuildContext context, PulsrPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s6,
        horizontal: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 15,
                color: p.textTertiary,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                context.l10n.sortBy,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w600,
                  color: p.textTertiary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          Material(
            color: p.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
              side: BorderSide(
                color: p.hairline.withValues(alpha: 0.6),
              ),
            ),
            child: InkWell(
              borderRadius: AppRadii.r12All,
              onTap: () {
                HapticFeedback.lightImpact();
                _showSortOptionsSheet(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: AppSpacing.s6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _sort == _FolderSort.name
                          ? Icons.sort_by_alpha_rounded
                          : Icons.numbers_rounded,
                      size: 14,
                      color: p.accent,
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    Text(
                      _sort == _FolderSort.name
                          ? context.l10n.title
                          : context.l10n.songs,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Icon(
                      _ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 13,
                      color: p.textSecondary,
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

  // ================= LIST ITEM CARD =================
  Widget _buildFolderListTile({
    required BuildContext context,
    required FolderItem folder,
    required Map<String, SongsTableData> representativeByDir,
    required PulsrPalette p,
    required bool isDownloads,
    required LibraryCubit cubit,
  }) {
    final displayPath = _formatDisplayPath(folder.path);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: p.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.r16All,
          side: BorderSide(
            color: folder.isExcluded
                ? p.error.withValues(alpha: 0.35)
                : isDownloads
                    ? p.accent.withValues(alpha: 0.35)
                    : p.hairline.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          borderRadius: AppRadii.r16All,
          onTap: () => context.push(
            '/folder?path=${Uri.encodeComponent(folder.path)}&name=${Uri.encodeComponent(folder.name)}',
            extra: folder,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            child: Row(
              children: [
                // Artwork thumbnail (52x52) with folder badge
                _buildFolderLeading(
                  folder: folder,
                  representativeByDir: representativeByDir,
                  p: p,
                  isDownloads: isDownloads,
                ),
                const SizedBox(width: AppSpacing.s12),
                // Title and formatted path info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                                color: folder.isExcluded
                                    ? p.textTertiary
                                    : p.textPrimary,
                                decoration: folder.isExcluded
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (isDownloads) ...[
                            const SizedBox(width: AppSpacing.s6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2,
                              ),
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: 0.18),
                                borderRadius: AppRadii.r6All,
                              ),
                              child: Text(
                                context.l10n.downloadsLabel,
                                style: TextStyle(
                                  fontSize: AppFontSize.micro,
                                  fontWeight: FontWeight.w800,
                                  color: p.accent,
                                  letterSpacing: AppTracking.medium,
                                ),
                              ),
                            ),
                          ],
                          if (folder.isExcluded) ...[
                            const SizedBox(width: AppSpacing.s6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2,
                              ),
                              decoration: BoxDecoration(
                                color: p.error.withValues(alpha: 0.18),
                                borderRadius: AppRadii.r6All,
                              ),
                              child: Text(
                                context.l10n.folderPersistentExcludedBadge,
                                style: TextStyle(
                                  fontSize: AppFontSize.micro,
                                  fontWeight: FontWeight.w800,
                                  color: p.error,
                                  letterSpacing: AppTracking.medium,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Row(
                        children: [
                          Icon(
                            Icons.audiotrack_rounded,
                            size: 13,
                            color: p.accent.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Text(
                            '${folder.songCount} ${context.l10n.browseAudioTracks}',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.label,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              displayPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textTertiary,
                                fontSize: AppFontSize.label,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                // Quick play button
                Material(
                  color: p.accent.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _playFolder(context, folder, shuffle: false),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s8),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: p.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                // 3-dots more options menu
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded),
                  color: p.textSecondary,
                  tooltip: context.l10n.moreOptions,
                  onPressed: () =>
                      _showFolderOptionsSheet(context, folder, cubit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= GRID ITEM CARD =================
  Widget _buildFolderGridCard({
    required BuildContext context,
    required FolderItem folder,
    required Map<String, SongsTableData> representativeByDir,
    required PulsrPalette p,
    required bool isDownloads,
    required LibraryCubit cubit,
  }) {
    final repArtwork = _resolveArtworkInfo(folder, representativeByDir);

    return Material(
      color: p.surfaceContainer,
      borderRadius: AppRadii.r18All,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppRadii.r18All,
        onTap: () => context.push(
          '/folder?path=${Uri.encodeComponent(folder.path)}&name=${Uri.encodeComponent(folder.name)}',
          extra: folder,
        ),
        onLongPress: () => _showFolderOptionsSheet(context, folder, cubit),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s10),
          decoration: BoxDecoration(
            borderRadius: AppRadii.r18All,
            border: Border.all(
              color: folder.isExcluded
                  ? p.error.withValues(alpha: 0.35)
                  : isDownloads
                      ? p.accent.withValues(alpha: 0.35)
                      : p.hairline.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: AppRadii.r14All,
                      child: repArtwork.hasArtwork
                          ? CachedArtwork(
                              id: repArtwork.songId ?? 0,
                              albumId: repArtwork.albumId,
                              remoteUrl: repArtwork.remoteUrl,
                              type: ArtworkType.AUDIO,
                              size: double.infinity,
                              borderRadius: AppRadii.r14,
                              fallbackIcon: isDownloads
                                  ? Icons.download_done_rounded
                                  : Icons.folder_rounded,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    p.accentContainer.withValues(alpha: 0.5),
                                    p.surfaceContainerHigh,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: AppRadii.r14All,
                              ),
                              child: Icon(
                                isDownloads
                                    ? Icons.download_done_rounded
                                    : Icons.folder_rounded,
                                color: p.accent,
                                size: 36,
                              ),
                            ),
                    ),
                    // Folder badge top right
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: p.hairline.withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          isDownloads
                              ? Icons.download_rounded
                              : Icons.folder_rounded,
                          size: 13,
                          color: p.accent,
                        ),
                      ),
                    ),
                    // Quick play button bottom right
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Material(
                        color: p.accent,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () =>
                              _playFolder(context, folder, shuffle: false),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                              color: p.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.bodySmall,
                  color: folder.isExcluded ? p.textTertiary : p.textPrimary,
                  decoration:
                      folder.isExcluded ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${folder.songCount} ${context.l10n.browseAudioTracks}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= STORAGE HELPER FOOTER =================
  Widget _buildStorageHelperFooter(BuildContext context, PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.45),
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: p.hairline.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.s10),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.14),
              borderRadius: AppRadii.r12All,
            ),
            child: Icon(
              Icons.manage_search_rounded,
              color: p.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.hiddenFolders,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.bodySmall,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.hiddenFoldersSubtitle,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: p.accent.withValues(alpha: 0.16),
              foregroundColor: p.accent,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.r10All,
              ),
            ),
            onPressed: () => context.push('/hidden-folders'),
            child: const Icon(Icons.arrow_forward_rounded, size: 16),
          ),
        ],
      ),
    );
  }

  // ================= LEADING ARTWORK HELPER =================
  Widget _buildFolderLeading({
    required FolderItem folder,
    required Map<String, SongsTableData> representativeByDir,
    required PulsrPalette p,
    required bool isDownloads,
  }) {
    final rep = _resolveArtworkInfo(folder, representativeByDir);

    final fallbackIcon = folder.isExcluded
        ? Icons.folder_off_rounded
        : isDownloads
            ? Icons.download_done_rounded
            : Icons.folder_rounded;

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (rep.hasArtwork)
            CachedArtwork(
              id: rep.songId ?? 0,
              albumId: rep.albumId,
              remoteUrl: rep.remoteUrl,
              type: ArtworkType.AUDIO,
              size: 52,
              borderRadius: AppRadii.r14,
              fallbackIcon: fallbackIcon,
            )
          else
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accentContainer.withValues(alpha: 0.5),
                    p.surfaceContainerHigh,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadii.r14All,
                border: Border.all(
                  color: folder.isExcluded
                      ? p.error.withValues(alpha: 0.4)
                      : p.accent.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                fallbackIcon,
                color: folder.isExcluded ? p.error : p.accent,
                size: 26,
              ),
            ),
          // Badge on bottom corner
          PositionedDirectional(
            end: -3,
            bottom: -3,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.bg,
                  width: 1.5,
                ),
              ),
              child: Icon(
                folder.isExcluded
                    ? Icons.block_rounded
                    : isDownloads
                        ? Icons.download_done_rounded
                        : Icons.folder_rounded,
                size: 11,
                color: folder.isExcluded
                    ? p.error
                    : p.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= RESOLVE ARTWORK =================
  _ArtworkInfo _resolveArtworkInfo(
    FolderItem folder,
    Map<String, SongsTableData> representativeByDir,
  ) {
    int? songId = folder.representativeSongId;
    int? albumId = folder.representativeAlbumId;
    String? remoteUrl =
        folder.representativeRemoteUrl ?? folder.representativeArtworkUri;

    if ((songId == null || songId == 0) &&
        (remoteUrl == null || remoteUrl.isEmpty)) {
      final normFolder = p_path.posix
          .normalize(folder.path.replaceAll('\\', '/'))
          .toLowerCase();
      final representative = representativeByDir[normFolder];
      if (representative != null) {
        songId = representative.id;
        albumId = representative.albumId;
        remoteUrl =
            representative.remoteArtworkUrl ?? representative.artworkUri;
      }
    }

    final hasArtwork = (songId != null && songId > 0) ||
        (remoteUrl != null && remoteUrl.isNotEmpty);

    return _ArtworkInfo(
      songId: songId,
      albumId: albumId,
      remoteUrl: remoteUrl,
      hasArtwork: hasArtwork,
    );
  }

  // ================= PLAY FOLDER =================
  Future<void> _playFolder(
    BuildContext context,
    FolderItem folder, {
    bool shuffle = false,
  }) async {
    try {
      final playerCubit = context.read<PlayerCubit>();
      final folderUseCases = getIt<FolderUseCases>();
      final result = await folderUseCases.watchFolderSongs(folder.path).first;
      final songs = result.fold((_) => <SongsTableData>[], (s) => s);
      if (!context.mounted) return;
      if (songs.isEmpty) {
        PulsrToast.show(
          context,
          message: context.l10n.browseNoTracksInFolder,
          icon: Icons.music_off_rounded,
        );
        return;
      }
      final queue =
          shuffle ? (List<SongsTableData>.from(songs)..shuffle()) : songs;
      await playerCubit.playSong(queue.first, queue: queue);
      if (!context.mounted) return;
      PulsrToast.show(
        context,
        message: shuffle
            ? '${context.l10n.shuffle}: ${folder.name}'
            : '${context.l10n.playAll}: ${folder.name}',
        icon: shuffle ? Icons.shuffle_rounded : Icons.play_arrow_rounded,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotLoadFolderSongs)),
        );
      }
    }
  }

  // ================= FOLDER OPTIONS SHEET =================
  void _showFolderOptionsSheet(
    BuildContext context,
    FolderItem folder,
    LibraryCubit cubit,
  ) {
    final p = context.palette;
    final displayPath = _formatDisplayPath(folder.path);

    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: p.accentContainer,
                      borderRadius: AppRadii.r12All,
                    ),
                    child: Icon(
                      folder.isExcluded
                          ? Icons.folder_off_rounded
                          : Icons.folder_rounded,
                      color: folder.isExcluded ? p.error : p.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${folder.songCount} ${context.l10n.browseAudioTracks} · $displayPath',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(color: p.hairline, height: 1),
              const SizedBox(height: AppSpacing.xs),

              // Play All
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: p.accent),
                title: Text(
                  context.l10n.playAll,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _playFolder(context, folder, shuffle: false);
                },
              ),

              // Shuffle
              ListTile(
                leading: Icon(Icons.shuffle_rounded, color: p.accent),
                title: Text(
                  context.l10n.shuffle,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _playFolder(context, folder, shuffle: true);
                },
              ),

              // Open Folder Details
              ListTile(
                leading:
                    Icon(Icons.folder_open_rounded, color: p.textSecondary),
                title: Text(
                  context.l10n.browseOpenFolderDetails,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push(
                    '/folder?path=${Uri.encodeComponent(folder.path)}&name=${Uri.encodeComponent(folder.name)}',
                    extra: folder,
                  );
                },
              ),

              // Exclude / Include Toggle
              ListTile(
                leading: Icon(
                  folder.isExcluded
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: folder.isExcluded ? p.success : p.error,
                ),
                title: Text(
                  folder.isExcluded
                      ? context.l10n.browseIncludeInScan
                      : context.l10n.browseExcludeFromScan,
                  style: TextStyle(
                    color: folder.isExcluded ? p.success : p.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  folder.isExcluded
                      ? context.l10n.folderIncluded
                      : context.l10n.folderExcluded,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textTertiary,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  cubit.toggleFolderExclusion(folder.path);
                },
              ),

              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  // ================= SORT OPTIONS BOTTOM SHEET =================
  void _showSortOptionsSheet(BuildContext context) {
    final p = context.palette;

    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  context.l10n.sortBy,
                  style: TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                title: '${context.l10n.title} (A → Z)',
                icon: Icons.sort_by_alpha_rounded,
                selected: _sort == _FolderSort.name && _ascending,
                onTap: () {
                  setState(() {
                    _sort = _FolderSort.name;
                    _ascending = true;
                  });
                },
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                title: '${context.l10n.title} (Z → A)',
                icon: Icons.sort_by_alpha_rounded,
                selected: _sort == _FolderSort.name && !_ascending,
                onTap: () {
                  setState(() {
                    _sort = _FolderSort.name;
                    _ascending = false;
                  });
                },
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                title: '${context.l10n.songs} (High → Low)',
                icon: Icons.numbers_rounded,
                selected: _sort == _FolderSort.count && !_ascending,
                onTap: () {
                  setState(() {
                    _sort = _FolderSort.count;
                    _ascending = false;
                  });
                },
              ),
              _buildSortOptionTile(
                sheetContext: sheetContext,
                title: '${context.l10n.songs} (Low → High)',
                icon: Icons.numbers_rounded,
                selected: _sort == _FolderSort.count && _ascending,
                onTap: () {
                  setState(() {
                    _sort = _FolderSort.count;
                    _ascending = true;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOptionTile({
    required BuildContext sheetContext,
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final p = sheetContext.palette;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r12All),
      tileColor:
          selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
      leading: Icon(icon, color: selected ? p.accent : p.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? p.accent : p.textPrimary,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: p.accent, size: 20)
          : null,
      onTap: () {
        Navigator.of(sheetContext).pop();
        onTap();
      },
    );
  }

  bool _isDownloadsFolder(FolderItem folder) {
    final nameLower = folder.name.toLowerCase();
    final pathLower = folder.path.toLowerCase();
    return nameLower.contains('pulsr') ||
        pathLower.contains('ytdl') ||
        nameLower == 'download' ||
        nameLower == 'downloads';
  }

  String _formatDisplayPath(String rawPath) {
    var path = rawPath.replaceAll('\\', '/');
    const emulated0 = '/storage/emulated/0';
    if (path.startsWith(emulated0)) {
      path = path.substring(emulated0.length);
      if (path.isEmpty || path == '/') {
        return 'Internal Storage';
      }
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      return 'Internal › ${path.replaceAll('/', ' › ')}';
    }
    if (path.startsWith('/storage/')) {
      final segments = path.substring('/storage/'.length).split('/');
      if (segments.isNotEmpty) {
        final disk = segments.first;
        final rest = segments.skip(1).join(' › ');
        return rest.isEmpty ? 'SD Card ($disk)' : 'SD Card › $rest';
      }
    }
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path.replaceAll('/', ' › ');
  }
}

class _ArtworkInfo {
  final int? songId;
  final int? albumId;
  final String? remoteUrl;
  final bool hasArtwork;

  const _ArtworkInfo({
    required this.songId,
    required this.albumId,
    required this.remoteUrl,
    required this.hasArtwork,
  });
}
