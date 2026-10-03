part of '../settings_screen.dart';

mixin CategoryFilterBarSection
    on
        SettingsCategoryMetadata,
        SettingsScreenController,
        State<SettingsScreen> {
  // Requires: provided by the composing class (same library).
  @override
  String get _selectedCategoryId;

  // ==========================================================================
  // Category Filter Bar (Pills for Phone)
  // ==========================================================================

  Widget _buildCategoryFilterBar(BuildContext context, SettingsState state) {
    final p = context.palette;
    final categories = _getCategories(context, pro: state.isProfessional);
    final items = [
      (
        id: 'all',
        title: context.l10n.all,
        icon: Icons.tune_rounded,
        color: p.accent
      ),
      ...categories.map(
          (c) => (id: c.id, title: c.title, icon: c.icon, color: c.tintColor)),
    ];

    return SizedBox(
      height: AppSpacing.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding:
            EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = _selectedCategoryId == item.id;

          return Semantics(
            selected: isSelected,
            button: true,
            label: item.title,
            child: PulsrPressable(
              pressedScale: 0.94,
              onTap: () {
                HapticFeedback.selectionClick();
                _selectCategory(item.id);
              },
              child: AnimatedContainer(
                duration: context.motionMs(180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: isSelected
                      ? p.accent.withValues(alpha: 0.16)
                      : p.surfaceContainer,
                  borderRadius: AppRadii.full,
                  border: Border.all(
                    color: isSelected ? p.accent : p.hairline,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 15,
                      color: isSelected ? p.accent : item.color,
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    Text(
                      item.title,
                      style: TextStyle(
                        color: isSelected ? p.accent : p.textPrimary,
                        fontSize: AppFontSize.label,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
