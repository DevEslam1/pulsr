// lib/features/library/presentation/widgets/folder_browser_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p_path;
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../domain/usecases/folder_usecases.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: PulsrEmptyState(
                    icon: Icons.folder_off_rounded,
                    title: context.l10n.noFoldersFound,
                    subtitle: context.l10n.noFoldersSubtitle,
                    primaryActionLabel: context.l10n.scanStorage,
                    primaryActionIcon: Icons.center_focus_strong_rounded,
                    onPrimaryAction: onRefresh,
                  ),
                ),
              ],
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

        return Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surfaceContainer,
              onRefresh: onRefresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                padding: EdgeInsetsDirectional.only(
                  bottom: AppSpacing.scrollBottom,
                  top: 8,
                  start: Adaptive.pagePadding(context),
                  end: Adaptive.pagePadding(context),
                ),
                itemCount: sortedFolders.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs, horizontal: AppSpacing.xxs),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${sortedFolders.length} ${context.l10n.folders.toLowerCase()}',
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              color: p.textTertiary,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(
                                  _sort == _FolderSort.name
                                      ? Icons.sort_by_alpha_rounded
                                      : Icons.numbers_rounded,
                                  size: 16,
                                  color: p.accent,
                                ),
                                label: Text(
                                  _sort == _FolderSort.name
                                      ? context.l10n.title
                                      : context.l10n.songs,
                                  style: TextStyle(
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w600,
                                    color: p.textPrimary,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _sort = _sort == _FolderSort.name
                                        ? _FolderSort.count
                                        : _FolderSort.name;
                                  });
                                },
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              IconButton(
                                icon: Icon(
                                  _ascending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 18,
                                  color: p.textSecondary,
                                ),
                                tooltip:
                                    _ascending ? 'Ascending' : 'Descending',
                                constraints: const BoxConstraints(
                                    minWidth: AppSpacing.minTouchTarget,
                                    minHeight: AppSpacing.minTouchTarget),
                                onPressed: () =>
                                    setState(() => _ascending = !_ascending),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  final folder = sortedFolders[index - 1];
                  final isDownloads =
                      folder.name.toLowerCase().contains('pulsr') ||
                          folder.path.toLowerCase().contains('ytdl') ||
                          folder.name.toLowerCase() == 'download' ||
                          folder.name.toLowerCase() == 'downloads';

                  return Container(
                    margin:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Material(
                      color: p.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.r16All,
                        side: BorderSide(
                          color: folder.isExcluded
                              ? p.error.withValues(alpha: 0.4)
                              : isDownloads
                                  ? p.accent.withValues(alpha: 0.35)
                                  : p.hairline,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => context.push('/folder', extra: folder),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.r16All,
                        ),
                        leading: _buildFolderLeading(
                          folder: folder,
                          state: state,
                          p: p,
                          isDownloads: isDownloads,
                        ),
                        title: Row(
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
                                    vertical: AppSpacing.s2),
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
                          ],
                        ),
                        subtitle: Text(
                          '${folder.songCount} ${context.l10n.browseAudioTracks} • ${folder.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label),
                        ),
                        trailing: IconButton(
                          constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget),
                          icon: Icon(
                            folder.isExcluded
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color:
                                folder.isExcluded ? p.error : p.textSecondary,
                            size: 20,
                          ),
                          tooltip: folder.isExcluded
                              ? context.l10n.browseIncludeInScan
                              : context.l10n.browseExcludeFromScan,
                          onPressed: () {
                            cubit.toggleFolderExclusion(folder.path);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderLeading({
    required FolderItem folder,
    required LibraryState state,
    required PulsrPalette p,
    required bool isDownloads,
  }) {
    int? songId = folder.representativeSongId;
    int? albumId = folder.representativeAlbumId;
    String? remoteUrl =
        folder.representativeRemoteUrl ?? folder.representativeArtworkUri;

    // Fallback: match from currently loaded library songs if no direct ID on folder
    if ((songId == null || songId == 0) &&
        (remoteUrl == null || remoteUrl.isEmpty)) {
      final normFolder = p_path.posix
          .normalize(folder.path.replaceAll('\\', '/'))
          .toLowerCase();
      for (final s in state.songs) {
        final parent = p_path.posix
            .dirname(p_path.posix.normalize(s.path.replaceAll('\\', '/')))
            .toLowerCase();
        if (parent == normFolder) {
          songId = s.id;
          albumId = s.albumId;
          remoteUrl = s.remoteArtworkUrl ?? s.artworkUri;
          break;
        }
      }
    }

    final hasArtwork = (songId != null && songId > 0) ||
        (remoteUrl != null && remoteUrl.isNotEmpty);

    final fallbackIcon = folder.isExcluded
        ? Icons.folder_off_rounded
        : isDownloads
            ? Icons.download_done_rounded
            : Icons.folder_rounded;

    if (hasArtwork) {
      return SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CachedArtwork(
              id: songId ?? 0,
              albumId: albumId,
              remoteUrl: remoteUrl,
              type: ArtworkType.AUDIO,
              size: 42,
              borderRadius: AppRadii.r12,
              fallbackIcon: fallbackIcon,
            ),
            if (folder.isExcluded)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: p.error.withValues(alpha: 0.4),
                    borderRadius: AppRadii.r12All,
                  ),
                  child: Center(
                    child: Icon(Icons.block_rounded, size: 20, color: p.error),
                  ),
                ),
              )
            else if (isDownloads)
              PositionedDirectional(
                end: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.surfaceContainer, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.download_done_rounded,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: folder.isExcluded
            ? p.error.withValues(alpha: 0.15)
            : isDownloads
                ? p.accent.withValues(alpha: 0.22)
                : p.accentContainer,
        borderRadius: AppRadii.r12All,
      ),
      child: Icon(
        fallbackIcon,
        color: folder.isExcluded ? p.error : p.accent,
        size: 20,
      ),
    );
  }
}
