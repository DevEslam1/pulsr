part of '../settings_screen.dart';

mixin TabletLayoutSection
    on
        SettingsCategoryMetadata,
        SettingsHeaderSection,
        SettingsScreenController,
        SettingsSearchResults,
        SettingsCategoryWidgetsSection,
        State<SettingsScreen> {
  // Requires: provided by the composing class (same library).
  @override
  TextEditingController get _searchController;

  // Requires: provided by the composing class (same library).
  @override
  String get _searchQuery;
  @override
  set _searchQuery(String value);

  // ==========================================================================
  // Layouts: Tablet Master-Detail & Phone Category Views
  // ==========================================================================

  Widget _buildTabletLayout(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
    String activeCatId,
  ) {
    final p = context.palette;
    final categories = _getCategories(context, pro: state.isProfessional);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final masterWidth = screenWidth < 1000 ? 280.0 : 320.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Master Navigation Pane
        SizedBox(
          width: masterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabletMasterHeader(context),
              const SizedBox(height: AppSpacing.s6),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s14,
                    AppSpacing.xxs,
                    AppSpacing.s14,
                    PulsrLayoutMetrics.scrollBottom(context),
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xxs),
                  itemBuilder: (context, i) {
                    final cat = categories[i];
                    final isSelected = activeCatId == cat.id;

                    return PulsrPressable(
                      pressedScale: 0.985,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _selectCategory(cat.id);
                        if (_searchQuery.isNotEmpty) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      },
                      child: AnimatedContainer(
                        duration: context.motionMs(180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? p.accent.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: AppRadii.cardRadius,
                          border: Border.all(
                            color: isSelected
                                ? p.accent.withValues(alpha: 0.45)
                                : Colors.transparent,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: AppSpacing.s38,
                              height: AppSpacing.s38,
                              decoration: BoxDecoration(
                                color: cat.tintColor.withValues(
                                    alpha: isSelected ? 0.22 : 0.12),
                                borderRadius: AppRadii.r12All,
                              ),
                              child: Icon(
                                cat.icon,
                                size: 19,
                                color: cat.tintColor,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          isSelected ? p.accent : p.textPrimary,
                                      fontSize: AppFontSize.bodySmall,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s2),
                                  Text(
                                    cat.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.caption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: isSelected
                                  ? p.accent
                                  : p.textTertiary.withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Vertical hairline divider and foldable hinge
        Container(
          width: 1,
          color: p.hairline,
        ),
        if (context.hasFoldableHinge &&
            (context.foldableHinge?.bounds.width ?? 0) > 0)
          SizedBox(width: context.foldableHinge!.bounds.width),

        // Right Detail Pane
        Expanded(
          child: RepaintBoundary(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResultsList(context, state, cubit)
                : _buildDetailPane(context, state, cubit, activeCatId),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPane(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
    String activeCatId,
  ) {
    final categories = _getCategories(context, pro: state.isProfessional);
    final currentCat = categories.firstWhere(
      (c) => c.id == activeCatId,
      orElse: () => categories.first,
    );
    final bottomInset = PulsrLayoutMetrics.scrollBottom(context);

    return AnimatedSwitcher(
      duration: context.motionMs(220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(activeCatId),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                Adaptive.pagePadding(context),
                AppSpacing.md,
                Adaptive.pagePadding(context),
                bottomInset,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildCategoryHeroHeader(context, currentCat),
                const SizedBox(height: AppSpacing.md),
                if (activeCatId == 'audio') ...[
                  _experienceModeCard(context),
                ],
                ..._buildCategoryWidgets(context, activeCatId, state, cubit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHeroHeader(
    BuildContext context,
    _SettingsCategoryItem cat,
  ) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cat.tintColor.withValues(alpha: 0.18),
              borderRadius: AppRadii.r12All,
            ),
            child: Icon(cat.icon, color: cat.tintColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.title,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.bodyLarge,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.title,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  cat.subtitle,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.label,
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
