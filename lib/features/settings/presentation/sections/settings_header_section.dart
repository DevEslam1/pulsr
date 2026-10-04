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
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPad, vertical: AppSpacing.xs),
        child: PulsrSearchField(
            controller: _searchController,
            hintText: context.l10n.settingsSearchPlaceholder,
            onClear: () {
              if (mounted) setState(() => _searchQuery = '');
            }),
      );
    }
    final compact =
        MediaQuery.sizeOf(context).height < 500 && context.isLandscape;

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
            Expanded(
                child: PulsrSearchField(
              controller: _searchController,
              hintText: context.l10n.settingsSearchPlaceholder,
              onClear: () {
                if (mounted) setState(() => _searchQuery = '');
              },
            )),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
          horizontalPad, AppSpacing.md, horizontalPad, AppSpacing.xs),
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
                      context.l10n.settingsHeaderTagline(AppConfig.appVersion),
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
