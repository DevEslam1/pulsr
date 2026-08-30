// lib/features/library/presentation/widgets/folder_browser_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';

class FolderBrowserTab extends StatelessWidget {
  const FolderBrowserTab({super.key});

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
            // refresh() re-subscribes the data streams + reloads folders;
            // init() would additionally re-read prefs and double-emit.
            await cubit.refresh();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Scan complete! $count tracks loaded.')),
            );
          }
        }

        if (folders.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateWidget(
                    icon: Icons.folder_off_rounded,
                    title: 'No Folders Found',
                    subtitle:
                        'Scan device storage to discover music directories and organize by path.',
                    primaryActionLabel: 'Scan Storage',
                    primaryActionIcon: Icons.center_focus_strong_rounded,
                    onPrimaryAction: onRefresh,
                  ),
                ),
              ],
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: 160,
                  top: 8,
                  left: Adaptive.pagePadding(context),
                  right: Adaptive.pagePadding(context),
                ),
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  final isDownloads =
                      folder.name.toLowerCase().contains('pulsr') ||
                          folder.path.toLowerCase().contains('ytdl') ||
                          folder.name.toLowerCase() == 'download' ||
                          folder.name.toLowerCase() == 'downloads';

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                      color: p.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                          borderRadius: BorderRadius.circular(16),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            folder.isExcluded
                                ? Icons.folder_off_rounded
                                : isDownloads
                                    ? Icons.download_done_rounded
                                    : Icons.folder_rounded,
                            color: folder.isExcluded ? p.error : p.accent,
                            size: 22,
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
                                  fontSize: 14,
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
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'DOWNLOADS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: p.accent,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${folder.songCount} audio tracks • ${folder.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 11.5),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            folder.isExcluded
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color:
                                folder.isExcluded ? p.error : p.textSecondary,
                            size: 22,
                          ),
                          tooltip: folder.isExcluded
                              ? 'Include in Scan'
                              : 'Exclude from Scan',
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
