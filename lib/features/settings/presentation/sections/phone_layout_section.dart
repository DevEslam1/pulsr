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
            SizedBox(
                height: context.isLandscape ? AppSpacing.xxs : AppSpacing.md),
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
      return ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsetsDirectional.only(
          bottom: bottomInset,
          top: context.isLandscape ? AppSpacing.xxs : AppSpacing.md,
          start: horizontalPad,
          end: horizontalPad,
        ),
        children: [
          if (!context.isLandscape &&
              (AppConfig.isCloudSyncAllowed || AppConfig.ytmEnabled)) ...[
            const SettingsHeroCard(),
            const SizedBox(height: AppSpacing.md),
          ],
          ..._buildDashboardCards(context, state, cubit),
        ],
      );
    }

    final categories =
        _getCategories(context, pro: state.isProfessional, state: state);
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
            ..._buildCategoryWidgets(context, selectedId, state, cubit),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDashboardCards(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;
    final categories =
        _getCategories(context, pro: state.isProfessional, state: state);

    return categories.map((cat) {
      Widget statusLine;
      Widget? topAction;

      switch (cat.id) {
        case 'sound':
          final dev = state.currentOutputDevice;
          final devName =
              dev?.deviceName ?? context.l10n.settingsAudioOutputDevice;
          final rate = dev != null
              ? '${(dev.sampleRate / 1000).toStringAsFixed(dev.sampleRate % 1000 == 0 ? 0 : 1)} kHz / ${dev.bitDepth}-bit'
              : '44.1 kHz / 16-bit';
          final isBitPerfect =
              dev?.isBitPerfectActive == true || state.bitPerfectOutput;

          topAction = Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: PulsrPressable(
              pressedScale: 0.985,
              onTap: () {
                HapticFeedback.selectionClick();
                AudioSetupWizardSheet.show(context, cubit: cubit);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.s10),
                decoration: BoxDecoration(
                  color: p.accentContainer.withValues(alpha: 0.45),
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: p.accent, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.settingsSetUpSound,
                            style: TextStyle(
                              color: p.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: AppFontSize.label,
                            ),
                          ),
                          Text(
                            context.l10n.settingsSetUpSoundDesc,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.tiny,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded,
                        color: p.accent, size: 18),
                  ],
                ),
              ),
            ),
          );

          statusLine = Row(
            children: [
              Flexible(
                child: Text(
                  '$devName • $rate',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isBitPerfect) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.dacGold.withValues(alpha: 0.16),
                    borderRadius: AppRadii.full,
                    border: Border.all(
                        color: AppColors.dacGold.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    context.l10n.bitPerfectLabel,
                    style: TextStyle(
                      color: p.warning,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          );
          break;

        case 'look':
          final themeName = switch (state.themeMode) {
            AppThemeMode.system => context.l10n.systemDefault,
            AppThemeMode.light => context.l10n.themeLight,
            AppThemeMode.dark => context.l10n.themeDark,
            AppThemeMode.amoled => context.l10n.amoledLabel,
          };
          final langName = getLanguageTitle(state.languageCode, context.l10n);
          statusLine = Text(
            '$themeName • $langName (${state.languageCode.toUpperCase()})',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
          break;

        case 'library':
          statusLine = Text(
            state.scanResultCount != null
                ? context.l10n.lastScanTracks(state.scanResultCount!)
                : 'Min ${state.minDurationSec}s filter',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
          break;

        case 'network':
          statusLine = Text(
            '${state.proxyEnabled ? "Proxy ON" : "Proxy OFF"} • ${getQualityTitle(state.streamingQuality, context.l10n)}',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
          break;

        case 'privacy':
          statusLine = Text(
            context.l10n.settingsCategoryPrivacySubtitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
          break;

        case 'about':
        default:
          statusLine = Text(
            'Pulsr v${AppConfig.appVersion} • Audiophile Engine',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
          break;
      }

      return _DashboardCategoryCard(
        cat: cat,
        statusLine: statusLine,
        topAction: topAction,
        onTap: () => _selectCategory(cat.id),
      );
    }).toList();
  }
}

class _DashboardCategoryCard extends StatelessWidget {
  final _SettingsCategoryItem cat;
  final Widget statusLine;
  final Widget? topAction;
  final VoidCallback onTap;

  const _DashboardCategoryCard({
    required this.cat,
    required this.statusLine,
    this.topAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topAction != null) topAction!,
          Semantics(
            button: true,
            label: cat.title,
            child: PulsrPressable(
              pressedScale: 0.985,
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cat.tintColor.withValues(alpha: 0.16),
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
                              fontWeight: FontWeight.w800,
                              fontSize: AppFontSize.body,
                              letterSpacing: AppTracking.heading,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          statusLine,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: p.textTertiary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
