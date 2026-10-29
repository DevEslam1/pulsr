// lib/features/sheets/sort_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_radii.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class _SortOptionSpec {
  final String key;
  final String label;
  final IconData icon;

  const _SortOptionSpec({
    required this.key,
    required this.label,
    required this.icon,
  });
}

// FIX-L5: Optimize SortFilterSheet widget tree and const constructors
class SortFilterSheet extends StatelessWidget {
  final String currentSort;
  final bool ascending;
  final Function(String sortBy, bool ascending) onApply;

  const SortFilterSheet({
    super.key,
    required this.currentSort,
    required this.ascending,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentSort,
    required bool ascending,
    required Function(String sortBy, bool ascending) onApply,
  }) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => SortFilterSheet(
        currentSort: currentSort,
        ascending: ascending,
        onApply: onApply,
      ),
    );
  }

  void _handleSelect(BuildContext context, String key) {
    const descendingFirst = {
      'playCount',
      'rating',
      'dateAdded',
      'lastPlayed',
    };
    final isSelected = currentSort == key;
    final newAsc = isSelected ? !ascending : !descendingFirst.contains(key);
    HapticFeedback.selectionClick();
    onApply(key, newAsc);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = MediaQuery.sizeOf(context);
    final screenHeight = size.height;
    final sortOptions = <_SortOptionSpec>[
      _SortOptionSpec(
          key: 'title',
          label: context.l10n.title,
          icon: Icons.sort_by_alpha_rounded),
      _SortOptionSpec(
          key: 'artist',
          label: context.l10n.artist,
          icon: Icons.person_outline_rounded),
      _SortOptionSpec(
          key: 'album', label: context.l10n.albums, icon: Icons.album_outlined),
      _SortOptionSpec(
          key: 'dateAdded',
          label: context.l10n.recentlyAdded,
          icon: Icons.auto_awesome_mosaic_outlined),
      _SortOptionSpec(
          key: 'duration',
          label: context.l10n.duration,
          icon: Icons.schedule_rounded),
      _SortOptionSpec(
          key: 'playCount',
          label: context.l10n.mostPlayed,
          icon: Icons.trending_up_rounded),
      _SortOptionSpec(
          key: 'rating',
          label: context.l10n.browseTopRated,
          icon: Icons.star_outline_rounded),
      _SortOptionSpec(
          key: 'lastPlayed',
          label: context.l10n.recentlyPlayed,
          icon: Icons.history_rounded),
      _SortOptionSpec(
          key: 'fileSize',
          label: context.l10n.fileSize,
          icon: Icons.sd_storage_outlined),
      _SortOptionSpec(
          key: 'sampleRate',
          label: context.l10n.sampleRate,
          icon: Icons.graphic_eq_rounded),
      _SortOptionSpec(
          key: 'year',
          label: context.l10n.browseReleaseYear,
          icon: Icons.calendar_today_rounded),
    ];

    return PulsrBottomSheetContainer(
      title: Text(context.l10n.sortAndFilter),
      trailing: PulsrPressable(
        pressedScale: 0.95,
        onTap: () {
          HapticFeedback.selectionClick();
          onApply(currentSort, !ascending);
          Navigator.pop(context);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12, vertical: AppSpacing.s6),
          decoration: BoxDecoration(
            color: p.surfaceContainerHigh,
            borderRadius: AppRadii.full,
            border: Border.all(
              color: p.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 15,
                color: p.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                ascending ? 'A–Z' : 'Z–A',
                style: TextStyle(
                  color: p.accent,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.68),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useTwoColumns = constraints.maxWidth >= 460;
            if (useTwoColumns) {
              return GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.s16,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 48,
                  crossAxisSpacing: AppSpacing.xs,
                  mainAxisSpacing: AppSpacing.xs,
                ),
                itemCount: sortOptions.length,
                itemBuilder: (context, index) => _buildSortOptionTile(
                  context,
                  p,
                  sortOptions[index],
                  isGrid: true,
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.s16,
              ),
              itemCount: sortOptions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.s2),
              itemBuilder: (context, index) => _buildSortOptionTile(
                context,
                p,
                sortOptions[index],
                isGrid: false,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSortOptionTile(
    BuildContext context,
    PulsrPalette p,
    _SortOptionSpec option, {
    required bool isGrid,
  }) {
    final isSelected = currentSort == option.key;
    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.r12All,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _handleSelect(context, option.key),
          borderRadius: AppRadii.r12All,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? p.accentContainer
                  : (isGrid ? p.surfaceContainer : Colors.transparent),
              borderRadius: AppRadii.r12All,
              border: isSelected
                  ? Border.all(
                      color: p.accent.withValues(alpha: 0.35),
                      width: 1.0,
                    )
                  : (isGrid
                      ? Border.all(color: p.hairline, width: 1.0)
                      : null),
            ),
            child: Row(
              children: [
                Icon(
                  option.icon,
                  size: 20,
                  color: isSelected ? p.accent : p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? p.accent : p.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: AppFontSize.body,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.16),
                      borderRadius: AppRadii.full,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: p.accent,
                          size: 13,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          ascending ? 'A–Z' : 'Z–A',
                          style: TextStyle(
                            color: p.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.check_rounded,
                    color: p.accent,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
