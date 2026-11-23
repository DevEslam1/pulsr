part of '../equalizer_sheet.dart';

/// Pro Rack Tab 1: AutoEQ Headphone Profiles, ViPER-DDC Headphone Correction,
/// Arbitrary Response EQ, and Live Programmable DSP.
extension _EqAutoEqViperTab on _EqualizerSheetState {
  Widget _buildAutoEqViperTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final dspBlocked = _dspBlockedReason(context);
    if (_isLoadingProfiles) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }

    final categories = _headphoneRepo.getCategories();
    final filteredProfiles =
        _headphoneRepo.search(_searchQuery, category: _selectedCategory);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (dspBlocked != null) _conflictBanner(dspBlocked, p),
              // Search bar
              Container(
                height: AppSpacing.minTouchTarget,
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.r12All,
                  border: Border.all(color: p.hairline),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => _setStateSafe(() => _searchQuery = val),
                  style: TextStyle(
                      fontSize: AppFontSize.bodySmall, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: context.l10n.dspSearchHeadphonesHint,
                    hintStyle: TextStyle(
                        fontSize: AppFontSize.label, color: p.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: p.textTertiary, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget),
                            icon: Icon(Icons.clear_rounded,
                                color: p.textTertiary, size: 16),
                            tooltip: context.l10n.clear,
                            onPressed: () {
                              _searchController.clear();
                              _setStateSafe(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),

              // Category Filter Chips
              SizedBox(
                height: PulsrLayoutMetrics.fieldHeight(context),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: AppSpacing.s6),
                      child: FilterChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: p.accent.withValues(alpha: 0.2),
                        backgroundColor: p.surfaceContainer,
                        side: BorderSide(
                          color: isSelected
                              ? p.accent.withValues(alpha: 0.4)
                              : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? p.accent : p.textSecondary,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) =>
                            _setStateSafe(() => _selectedCategory = cat),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),

              // Active Headphone Profile Banner
              if (state.selectedHeadphoneProfile != null) ...[
                _buildAutoEqAppliedBanner(
                    context, cubit, state, p, dspBlocked),
                const SizedBox(height: AppSpacing.xs),
              ],
            ]),
          ),
        ),

        // Headphone Profiles List
        if (filteredProfiles.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Text(
                  context.l10n.noHpProfiles,
                  style: TextStyle(
                      color: p.textTertiary, fontSize: AppFontSize.bodySmall),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: SliverList.builder(
              itemCount: filteredProfiles.length,
              itemBuilder: (context, index) => _buildHeadphoneProfileRow(
                context: context,
                cubit: cubit,
                state: state,
                profile: filteredProfiles[index],
                p: p,
                dspBlocked: dspBlocked,
              ),
            ),
          ),

        // ViPER-DDC, Arbitrary EQ, and LiveProg Correction Cards
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildViperDdcCard(context, state, cubit, dspBlocked, p),
              const SizedBox(height: AppSpacing.md),
              _buildArbitraryEqCard(context, state, cubit, dspBlocked, p),
              const SizedBox(height: AppSpacing.md),
              _buildLiveProgCard(context, state, cubit, dspBlocked, p),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoEqAppliedBanner(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, color: p.accent, size: 18),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.appliedTuningProfile,
                  style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: p.accent),
                ),
                Text(
                  state.selectedHeadphoneProfile!.name,
                  style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: dspBlocked != null ? null : () => cubit.resetToFlat(),
            child: Text(
              context.l10n.resetToFlat,
              style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadphoneProfileRow({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required HeadphoneProfile profile,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    final isApplied = state.selectedHeadphoneProfile?.id == profile.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Opacity(
        opacity: dspBlocked != null ? 0.5 : 1.0,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: dspBlocked != null
                ? null
                : () async {
                    if (isApplied) {
                      await cubit.resetToFlat();
                    } else {
                      if (!state.isEqEnabled) {
                        await cubit.setEqualizerEnabled(true);
                      }
                      await cubit.applyHeadphoneProfile(profile);
                    }
                  },
            borderRadius: AppRadii.cardRadius,
            child: Ink(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: isApplied
                  ? p.accent.withValues(alpha: 0.14)
                  : p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(
                color: isApplied ? p.accent : p.hairline,
                width: isApplied ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isApplied ? p.accent : p.textTertiary)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    profile.category == 'Over-Ear'
                        ? Icons.headset_rounded
                        : Icons.headphones_rounded,
                    color: isApplied ? p.accent : p.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: TextStyle(
                          fontSize: AppFontSize.bodySmall,
                          fontWeight: FontWeight.w700,
                          color: isApplied ? p.accent : p.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        '${profile.brand} • ${profile.category}',
                        style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: p.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (profile.id.startsWith('custom_')) ...[
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: p.error),
                    tooltip: context.l10n.dspDeleteCustomPreset,
                    onPressed: dspBlocked != null
                        ? null
                        : () async {
                            await _headphoneRepo.removeProfile(profile.id);
                            if (!mounted) return;
                            if (isApplied) await cubit.resetToFlat();
                            if (mounted) _setStateSafe(() {});
                          },
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                if (isApplied)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: AppRadii.r12All,
                      boxShadow: [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, color: p.onAccent, size: 13),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          context.l10n.activeLabel,
                          style: TextStyle(
                            color: p.onAccent,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: p.surfaceContainerHigh,
                      borderRadius: AppRadii.r12All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Text(
                      context.l10n.apply,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildViperDdcCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final hasProfile = state.viperDdcProfileName.isNotEmpty;
    final info = AudioFeatureRegistry.viperDdc.localized(context.l10n);
    return _buildCorrectionToolCard(
      context: context,
      p: p,
      icon: Icons.headphones_rounded,
      title: info.title,
      subtitle: hasProfile ? state.viperDdcProfileName : info.subtitle,
      infoTooltip: info.title,
      onInfo: () => _showFeatureInfo(context, AudioFeatureRegistry.viperDdc,
          conflictReason: dspBlocked ??
              (_nativePcmEffectsAvailable
                  ? null
                  : context.l10n.dspRequiresPcmPath)),
      value: state.isViperDdcEnabled,
      dspBlocked: dspBlocked,
      onChanged: (val) => cubit.setViperDdcEnabled(val),
      actionIcon: Icons.folder_open_rounded,
      actionLabel: hasProfile
          ? context.l10n.viperChangeProfile(state.viperDdcProfileName)
          : context.l10n.viperSelectLoadProfile,
      onAction: () => PulsrSheetHelper.showPulsrSheet<void>(
        context: context,
        wrapWithContainer: false,
        builder: (_) => const ViperDdcSheet(),
      ),
    );
  }

  Widget _buildArbitraryEqCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final info = AudioFeatureRegistry.arbitraryEq.localized(context.l10n);
    return _buildCorrectionToolCard(
      context: context,
      p: p,
      icon: Icons.auto_graph_rounded,
      title: info.title,
      subtitle: info.subtitle,
      infoTooltip: info.title,
      onInfo: () => _showFeatureInfo(context, AudioFeatureRegistry.arbitraryEq,
          conflictReason: dspBlocked ??
              (_nativePcmEffectsAvailable
                  ? null
                  : context.l10n.dspRequiresPcmPath)),
      value: state.isArbitraryEqEnabled,
      dspBlocked: dspBlocked,
      onChanged: (val) => cubit.setArbitraryEqEnabled(val),
      actionIcon: Icons.edit_note_rounded,
      actionLabel: context.l10n.editGraphicEq,
      onAction: () => PulsrSheetHelper.showPulsrSheet<void>(
        context: context,
        wrapWithContainer: false,
        builder: (_) => const ArbitraryEqSheet(),
      ),
    );
  }

  Widget _buildLiveProgCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final info = AudioFeatureRegistry.liveProg.localized(context.l10n);
    return _buildCorrectionToolCard(
      context: context,
      p: p,
      icon: Icons.code_rounded,
      title: info.title,
      subtitle:
          state.liveProgStatus.isNotEmpty ? state.liveProgStatus : info.subtitle,
      infoTooltip: info.title,
      onInfo: () => _showFeatureInfo(context, AudioFeatureRegistry.liveProg,
          conflictReason: dspBlocked ??
              (_nativePcmEffectsAvailable
                  ? null
                  : context.l10n.dspRequiresPcmPath)),
      value: state.isLiveProgEnabled,
      dspBlocked: dspBlocked,
      onChanged: (val) => cubit.setLiveProgEnabled(val),
      actionIcon: Icons.terminal_rounded,
      actionLabel: context.l10n.openEelEditor,
      onAction: () => PulsrSheetHelper.showPulsrSheet<void>(
        context: context,
        wrapWithContainer: false,
        builder: (_) => const LiveProgSheet(),
      ),
    );
  }

  Widget _buildCorrectionToolCard({
    required BuildContext context,
    required PulsrPalette p,
    required IconData icon,
    required String title,
    required String subtitle,
    required String infoTooltip,
    required VoidCallback onInfo,
    required bool value,
    required String? dspBlocked,
    required ValueChanged<bool> onChanged,
    required IconData actionIcon,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final available = dspBlocked == null && _nativePcmEffectsAvailable;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Icon(icon, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(subtitle,
                              style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip: infoTooltip,
                onPressed: onInfo,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && value,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available ? null : onChanged,
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                  style: TextStyle(
                      color: p.error,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.nativeDspUnavailable,
                  style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            ),
          if (available && value) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: Icon(actionIcon, size: 16),
              label: Text(actionLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              ),
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
