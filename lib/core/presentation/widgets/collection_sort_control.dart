import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/pulsr_haptics.dart';

/// Representation of a single sort option within [CollectionSortControl].
class CollectionSortOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const CollectionSortOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// A unified, compact collection sort control displaying the current sort mode
/// and an ascending/descending direction toggle within a single pill container.
class CollectionSortControl<T> extends StatelessWidget {
  final T currentSort;
  final List<CollectionSortOption<T>> options;
  final bool ascending;
  final ValueChanged<T> onSortChanged;
  final ValueChanged<bool>? onDirectionChanged;
  final String? tooltip;
  final String? ascendingTooltip;
  final String? descendingTooltip;

  const CollectionSortControl({
    super.key,
    required this.currentSort,
    required this.options,
    required this.ascending,
    required this.onSortChanged,
    this.onDirectionChanged,
    this.tooltip,
    this.ascendingTooltip,
    this.descendingTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.s10,
        end: 2,
      ),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r12All,
        border: Border.all(color: p.hairline),
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sort mode selector (inline dropdown within pill)
            DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: currentSort,
                isDense: true,
                dropdownColor: p.surfaceContainerHigh,
                borderRadius: AppRadii.r12All,
                icon: Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppSpacing.xxs),
                  child: Icon(
                    Icons.arrow_drop_down_rounded,
                    color: p.textTertiary,
                    size: 16,
                  ),
                ),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                ),
                items: [
                  for (final opt in options)
                    DropdownMenuItem<T>(
                      value: opt.value,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (opt.icon != null) ...[
                            Icon(
                              opt.icon,
                              size: 15,
                              color: opt.value == currentSort
                                  ? p.accent
                                  : p.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.s6),
                          ],
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              opt.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: opt.value == currentSort
                                    ? p.accent
                                    : p.textPrimary,
                                fontWeight: opt.value == currentSort
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: AppFontSize.caption,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    PulsrHaptics.lightImpact();
                    onSortChanged(v);
                  }
                },
              ),
            ),

            if (onDirectionChanged != null) ...[
              const SizedBox(width: AppSpacing.xxs),
              Container(
                width: 1,
                height: 18,
                color: p.hairline,
              ),
              InkWell(
                borderRadius: const BorderRadiusDirectional.horizontal(
                  end: Radius.circular(AppRadii.r12),
                ).resolve(Directionality.of(context)),
                onTap: () {
                  PulsrHaptics.lightImpact();
                  onDirectionChanged!(!ascending);
                },
                child: Tooltip(
                  message: ascending
                      ? (ascendingTooltip ?? context.l10n.sortAscending)
                      : (descendingTooltip ?? context.l10n.sortDescending),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                      vertical: AppSpacing.s6,
                    ),
                    child: AnimatedRotation(
                      turns: ascending ? 0.0 : 0.5,
                      duration: context.motionMs(200),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 15,
                        color: ascending ? p.textSecondary : p.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
