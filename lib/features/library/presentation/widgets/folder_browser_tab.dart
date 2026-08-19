// lib/features/library/presentation/widgets/folder_browser_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';

class FolderBrowserTab extends StatelessWidget {
  const FolderBrowserTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final folders = state.folders;
        final cubit = context.read<LibraryCubit>();

        if (folders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_off_outlined, size: 56, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                const Text(
                  'No Folders Found',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Scan storage to discover music directories.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120, top: 8),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppRadii.cardRadius,
                border: Border.all(
                  color: folder.isExcluded ? Colors.red.withValues(alpha: 0.4) : AppColors.outline,
                ),
              ),
              child: ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: folder.isExcluded
                        ? Colors.red.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    folder.isExcluded ? Icons.folder_off_rounded : Icons.folder_rounded,
                    color: folder.isExcluded ? Colors.redAccent : AppColors.primary,
                    size: 24,
                  ),
                ),
                title: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: folder.isExcluded ? AppColors.textSecondary : AppColors.textPrimary,
                    decoration: folder.isExcluded ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '${folder.songCount} audio tracks • ${folder.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                trailing: IconButton(
                  icon: Icon(
                    folder.isExcluded ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: folder.isExcluded ? Colors.redAccent : AppColors.textSecondary,
                    size: 22,
                  ),
                  tooltip: folder.isExcluded ? 'Include in Scan' : 'Exclude from Scan',
                  onPressed: () {
                    cubit.toggleFolderExclusion(folder.path);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
