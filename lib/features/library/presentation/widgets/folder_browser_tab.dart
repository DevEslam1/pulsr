// lib/features/library/presentation/widgets/folder_browser_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/empty_state_widget.dart';
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
                  child: EmptyStateWidget(
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
                        borderRadius: BorderRadius.circular(AppRadii.r16),
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
                          borderRadius: BorderRadius.circular(AppRadii.r16),
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: folder.isExcluded
                                ? p.error.withValues(alpha: 0.15)
                                : isDownloads
                                    ? p.accent.withValues(alpha: 0.22)
                                    : p.accentContainer,
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                          child: Icon(
                            folder.isExcluded
                                ? Icons.folder_off_rounded
                                : isDownloads
                                    ? Icons.download_done_rounded
                                    : Icons.folder_rounded,
                            color: folder.isExcluded ? p.error : p.accent,
                            size: 20,
                          ),
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
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.r6),
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
}
