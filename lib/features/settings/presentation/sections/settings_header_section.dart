part of '../settings_screen.dart';

mixin SettingsHeaderSection on State<SettingsScreen> {
  // Requires: provided by the composing class (same library).
  TextEditingController get _searchController;

  // Requires: provided by the composing class (same library).
  set _searchQuery(String value);

  // ==========================================================================
  // Header & Search Bar
  // ==========================================================================

  Widget _buildTopHeader(BuildContext context) {
    final p = context.palette;
    final horizontalPad = Adaptive.pagePadding(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact =
        MediaQuery.sizeOf(context).height < 500 && context.isLandscape;

    // The search field must keep a stable position in the element tree across
    // keyboard-inset changes. A structural swap when the keyboard opens
    // recreates the field's TextField element, which drops focus and closes
    // its text-input connection (the keyboard closes instantly and search
    // cannot be typed into on phones). The title block is therefore collapsed
    // with [Visibility] instead of a branch swap.
    final searchField = PulsrSearchField(
      controller: _searchController,
      hintText: context.l10n.settingsSearchPlaceholder,
      onClear: () {
        if (mounted) setState(() => _searchQuery = '');
      },
    );

    if (compact) {
      return Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
            horizontalPad, AppSpacing.xs, horizontalPad, AppSpacing.xs),
        child: Row(
          children: [
            Text(context.l10n.settings,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.titleLarge,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: searchField),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
          horizontalPad,
          keyboardOpen ? AppSpacing.xs : AppSpacing.md,
          horizontalPad,
          AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Visibility(
            visible: !keyboardOpen,
            maintainState: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.settings,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.display,
                              fontWeight: FontWeight.w900,
                              letterSpacing: AppTracking.heading,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            context.l10n
                                .settingsHeaderTagline(AppConfig.appVersion),
                            style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
          searchField,
        ],
      ),
    );
  }

  Widget _buildTabletMasterHeader(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.settings,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.headline,
                    fontWeight: FontWeight.w900,
                    letterSpacing: AppTracking.heading,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                decoration: BoxDecoration(
                  color: p.accentContainer,
                  borderRadius: AppRadii.r6All,
                ),
                child: Text(
                  'v${AppConfig.appVersion}',
                  style: TextStyle(
                    color: p.accent,
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            context.l10n.settingsHeaderTaglineShort(AppConfig.appVersion),
            style: TextStyle(
              color: p.textTertiary,
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Search Box
          PulsrSearchField(
            controller: _searchController,
            hintText: context.l10n.settingsSearchPlaceholder,
            onClear: () {
              if (mounted) setState(() => _searchQuery = '');
            },
          ),
        ],
      ),
    );
  }
}
