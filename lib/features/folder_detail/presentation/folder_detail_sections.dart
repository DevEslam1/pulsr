part of 'folder_detail_screen.dart';

extension _FolderDetailSections on _FolderDetailScreenState {
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
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);

    return GestureDetector(
      onLongPress: _copyFolderPath,
      child: Container(
        height: ((compact ? 32.0 : 36.0) * textScale).roundToDouble(),
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
                          : AppColors.fadeStopTransparent,
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
}
