part of '../settings_screen.dart';

mixin PhoneLayoutSection
    on
        CategoryFilterBarSection,
        SettingsHeaderSection,
        SettingsSearchResults,
        SettingsCategoryMetadata,
        SettingsCategoryWidgetsSection,
        SettingsPrivacyBackupSection,
        TabletLayoutSection,
        State<SettingsScreen> {
  bool _soundPlaybackExpanded = true;
  bool _appearanceGesturesExpanded = true;
  bool _systemPrivacyExpanded = true;

  // Requires: provided by the composing class (same library).
  @override
  ScrollController get _scrollController;

  // Requires: provided by the composing class (same library).
  @override
  String get _selectedCategoryId;

  // Requires: provided by the composing class (same library).
  @override
  String get _searchQuery;

  Widget _buildPhoneLayout(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: PulsrLayoutMetrics.contentConstraints(context),
        child: Column(
          children: [
            _buildTopHeader(context),
            if (_searchQuery.isEmpty) _buildCategoryFilterBar(context, state),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResultsList(context, state, cubit)
                  : _buildPhoneCategoryView(context, state, cubit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneCategoryView(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final bottomInset = PulsrLayoutMetrics.scrollBottom(context);
    final horizontalPad = Adaptive.pagePadding(context);

    if (_selectedCategoryId == 'all') {
      if (context.isLandscape && !Adaptive.isTablet(context)) {
        return ListView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsetsDirectional.only(
            bottom: bottomInset,
            top: AppSpacing.md,
            start: horizontalPad,
            end: horizontalPad,
          ),
          children: [
            if (AppConfig.isCloudSyncAllowed || AppConfig.ytmEnabled)
              const SettingsHeroCard(),
            _experienceModeCard(context),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSuperSection(
                    context,
                    title: context.l10n.settingsSectionSoundPlayback,
                    icon: Icons.graphic_eq_rounded,
                    isExpanded: _soundPlaybackExpanded,
                    onToggle: () => setState(
                        () => _soundPlaybackExpanded = !_soundPlaybackExpanded),
                    children: [
                      ..._buildCategoryWidgets(context, 'audio', state, cubit),
                      ..._buildCategoryWidgets(
                          context, 'playback', state, cubit),
                      if (state.isProfessional)
                        ..._buildCategoryWidgets(
                            context, 'profiles', state, cubit),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    children: [
                      _buildSuperSection(
                        context,
                        title: context.l10n.settingsSectionAppearanceGestures,
                        icon: Icons.palette_outlined,
                        isExpanded: _appearanceGesturesExpanded,
                        onToggle: () => setState(() =>
                            _appearanceGesturesExpanded =
                                !_appearanceGesturesExpanded),
                        children: [
                          ..._buildCategoryWidgets(
                              context, 'appearance', state, cubit),
                          ..._buildCategoryWidgets(
                              context, 'gestures', state, cubit),
                        ],
                      ),
                      _buildSuperSection(
                        context,
                        title: context.l10n.settingsSectionSystemPrivacy,
                        icon: Icons.settings_suggest_rounded,
                        isExpanded: _systemPrivacyExpanded,
                        onToggle: () => setState(() =>
                            _systemPrivacyExpanded = !_systemPrivacyExpanded),
                        children: [
                          ..._buildCategoryWidgets(
                              context, 'library', state, cubit),
                          ..._buildCategoryWidgets(
                              context, 'online', state, cubit),
                          ..._buildCategoryWidgets(
                              context, 'storage', state, cubit),
                          _buildPrivacyBackupSection(context),
                          ..._buildCategoryWidgets(
                              context, 'about', state, cubit),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      }
      return ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsetsDirectional.only(
          bottom: bottomInset,
          top: AppSpacing.md,
          start: horizontalPad,
          end: horizontalPad,
        ),
        children: [
          if (AppConfig.isCloudSyncAllowed || AppConfig.ytmEnabled)
            const SettingsHeroCard(),
          _experienceModeCard(context),
          const SizedBox(height: AppSpacing.sm),
          _buildSuperSection(
            context,
            title: context.l10n.settingsSectionSoundPlayback,
            icon: Icons.graphic_eq_rounded,
            isExpanded: _soundPlaybackExpanded,
            onToggle: () => setState(
                () => _soundPlaybackExpanded = !_soundPlaybackExpanded),
            children: [
              ..._buildCategoryWidgets(context, 'audio', state, cubit),
              ..._buildCategoryWidgets(context, 'playback', state, cubit),
              if (state.isProfessional)
                ..._buildCategoryWidgets(context, 'profiles', state, cubit),
            ],
          ),
          _buildSuperSection(
            context,
            title: context.l10n.settingsSectionAppearanceGestures,
            icon: Icons.palette_outlined,
            isExpanded: _appearanceGesturesExpanded,
            onToggle: () => setState(() =>
                _appearanceGesturesExpanded = !_appearanceGesturesExpanded),
            children: [
              ..._buildCategoryWidgets(context, 'appearance', state, cubit),
              ..._buildCategoryWidgets(context, 'gestures', state, cubit),
            ],
          ),
          _buildSuperSection(
            context,
            title: context.l10n.settingsSectionSystemPrivacy,
            icon: Icons.settings_suggest_rounded,
            isExpanded: _systemPrivacyExpanded,
            onToggle: () => setState(
                () => _systemPrivacyExpanded = !_systemPrivacyExpanded),
            children: [
              ..._buildCategoryWidgets(context, 'library', state, cubit),
              ..._buildCategoryWidgets(context, 'online', state, cubit),
              ..._buildCategoryWidgets(context, 'storage', state, cubit),
              _buildPrivacyBackupSection(context),
              ..._buildCategoryWidgets(context, 'about', state, cubit),
            ],
          ),
        ],
      );
    }

    final categories = _getCategories(context, pro: state.isProfessional);
    // A category can disappear when Professional mode is turned off (e.g.
    // `profiles`). Fall back to the first available category so the hero
    // header and body can never disagree or leave an empty titled screen.
    final selectedId = categories.any((c) => c.id == _selectedCategoryId)
        ? _selectedCategoryId
        : categories.first.id;
    final currentCat = categories.firstWhere((c) => c.id == selectedId);

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
        key: ValueKey(selectedId),
        child: ListView(
          key: PageStorageKey('settings_category_$selectedId'),
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsetsDirectional.only(
            bottom: bottomInset,
            top: AppSpacing.md,
            start: horizontalPad,
            end: horizontalPad,
          ),
          children: [
            _buildCategoryHeroHeader(context, currentCat),
            const SizedBox(height: AppSpacing.md),
            if (selectedId == 'audio') ...[
              _experienceModeCard(context),
            ],
            ..._buildCategoryWidgets(context, selectedId, state, cubit),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return _SuperSectionCard(
      title: title,
      icon: icon,
      isExpanded: isExpanded,
      onToggle: onToggle,
      children: children,
    );
  }
}
