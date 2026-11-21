part of 'equalizer_sheet.dart';

extension _EqAdvancedControls on _EqualizerSheetState {
  void _triggerCrossfeedAudition(
      BuildContext context, PlayerCubit cubit, PlayerState state) {
    _crossfeedPreAuditionEnabled ??= state.isCrossfeedEnabled;
    _crossfeedAuditionTimer?.cancel();
    final targetEnabled = !state.isCrossfeedEnabled;
    cubit.setCrossfeed(targetEnabled);
    PulsrToast.show(
      context,
      message: context.l10n.eqAuditioningCrossfeed,
      icon: Icons.headphones_rounded,
    );
    _crossfeedAuditionTimer = Timer(const Duration(seconds: 5), () {
      final restore = _crossfeedPreAuditionEnabled;
      _crossfeedPreAuditionEnabled = null;
      _crossfeedAuditionTimer = null;
      if (mounted && restore != null) {
        cubit.setCrossfeed(restore);
      }
    });
  }

  // 3. Spatial & Dynamics Tab
  Widget _buildSpatialDynamicsTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final dspBlocked = _dspBlockedReason(context);
    final spatializerAvailable = _spatializerToggleAvailable(state);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s20, AppSpacing.xs, AppSpacing.s20, AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) _conflictBanner(dspBlocked, p),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(context.l10n.allDspBypassed,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.caption)),
            ),
          // Support Detection Banner
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
            decoration: BoxDecoration(
              color: state.isSpatializerSupported
                  ? p.accent.withValues(alpha: 0.12)
                  : p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(
                color: state.isSpatializerSupported
                    ? p.accent.withValues(alpha: 0.4)
                    : p.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  state.isSpatializerSupported
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  color:
                      state.isSpatializerSupported ? p.accent : p.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isSpatializerSupported
                            ? context.l10n.spatialHardwareDetected
                            : context.l10n.spatialEmulatedMode,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                          color: state.isSpatializerSupported
                              ? p.accent
                              : p.textPrimary,
                        ),
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? context.l10n.spatialMultiChannelDesc
                            : context.l10n.spatialVirtualizerActiveDesc,
                        style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s14),

          // Dolby Atmos / Hardware Spatial Audio Card (when supported by device)
          if (state.isSpatializerSupported) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      borderRadius: AppRadii.r8All,
                    ),
                    child: Icon(Icons.spatial_tracking_rounded,
                        color: p.accent, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                context.l10n.spatialAudio,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.body,
                                    color: p.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s6,
                                  vertical: AppSpacing.s2),
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: 0.15),
                                borderRadius: AppRadii.r6All,
                              ),
                              child: Text(
                                context.l10n.spatialApi,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          context.l10n.spatialApiDesc,
                          style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: p.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: Icon(Icons.info_outline_rounded,
                          size: 16, color: p.textTertiary),
                      tooltip: context.l10n.dspAboutSpatializer,
                      onPressed: () => _showFeatureInfo(
                          context, AudioFeatureRegistry.spatializer,
                          conflictReason: dspBlocked)),
                  const SizedBox(width: AppSpacing.xxs),
                  Switch.adaptive(
                    value: dspBlocked == null && state.isSpatializerEnabled,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged: dspBlocked != null || !spatializerAvailable
                        ? null
                        : (val) => cubit.setSpatializerEnabled(val),
                  ),
                ],
              ),
            ),
            if (dspBlocked != null)
              Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(context.l10n.blockedByBitPerfectShort,
                      style: TextStyle(
                          color: p.error,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600))),
            const SizedBox(height: AppSpacing.md),
          ],

          // Stereo Soundstage Expansion (Virtualizer)
          Container(
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
                            child: Icon(Icons.surround_sound_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.soundstageWidening,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  context.l10n.virtualizerDesc,
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        tooltip: context.l10n.dspAboutVirtualizer,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.virtualizer,
                            conflictReason: dspBlocked)),
                    const SizedBox(width: AppSpacing.xxs),
                    Switch.adaptive(
                      value: dspBlocked == null && state.isVirtualizerEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !state.isVirtualizerSupported
                              ? null
                              : (val) => cubit.setVirtualizerEnabled(val),
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(
                          top: AppSpacing.s6, bottom: AppSpacing.xs),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w600))),
                const SizedBox(height: AppSpacing.md),

                // Soundstage visual slider
                Opacity(
                  opacity: dspBlocked != null
                      ? 0.35
                      : (state.isVirtualizerEnabled ? 1.0 : 0.35),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.width,
                              style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(state.virtualizerStrength * 100).round()}%',
                                style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w700,
                                    color: p.accent),
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              IconButton(
                                icon: Icon(Icons.settings_backup_restore,
                                    size: 15,
                                    color: !state.isVirtualizerEnabled ||
                                            state.virtualizerStrength <= 0.001
                                        ? p.textTertiary.withValues(alpha: 0.35)
                                        : p.accent),
                                tooltip: context.l10n.dspResetToDefault0,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: !state.isVirtualizerSupported ||
                                        !state.isVirtualizerEnabled ||
                                        state.virtualizerStrength <= 0.001
                                    ? null
                                    : () => cubit.setVirtualizerStrength(0.0),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          activeTrackColor: p.accent,
                          inactiveTrackColor: p.surface,
                          thumbColor: p.accent,
                        ),
                        child: Semantics(
                          slider: true,
                          excludeSemantics: true,
                          label: context.l10n.width,
                          value:
                              '${(state.virtualizerStrength * 100).round()}%',
                          increasedValue:
                              '${((state.virtualizerStrength + 0.1).clamp(0.0, 1.0) * 100).round()}%',
                          decreasedValue:
                              '${((state.virtualizerStrength - 0.1).clamp(0.0, 1.0) * 100).round()}%',
                          onIncrease: state.isVirtualizerEnabled &&
                                  state.isVirtualizerSupported
                              ? () => cubit.setVirtualizerStrength(
                                  (state.virtualizerStrength + 0.1)
                                      .clamp(0.0, 1.0))
                              : null,
                          onDecrease: state.isVirtualizerEnabled &&
                                  state.isVirtualizerSupported
                              ? () => cubit.setVirtualizerStrength(
                                  (state.virtualizerStrength - 0.1)
                                      .clamp(0.0, 1.0))
                              : null,
                          child: ThrottledSlider(
                            value: state.virtualizerStrength.clamp(0.0, 1.0),
                            min: 0.0,
                            max: 1.0,
                            onChanged: state.isVirtualizerEnabled &&
                                    state.isVirtualizerSupported
                                ? (val) => cubit.setVirtualizerStrength(val)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _effectNotAppliedNotice('virtualizer', p),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Studio Dynamics (DynamicsProcessing)
          Container(
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
                            child: Icon(Icons.compress_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.studioDynamics,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  context.l10n.multibandDesc,
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        tooltip: context.l10n.dspAboutDynamics,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.dynamics,
                            conflictReason: dspBlocked)),
                    const SizedBox(width: AppSpacing.xxs),
                    Switch.adaptive(
                      value: dspBlocked == null && state.isDynamicsEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !state.isDynamicsSupported
                              ? null
                              : (val) {
                                  cubit.setDynamicsPreset(
                                    val
                                        ? (state.dynamicsPreset ==
                                                DynamicsPreset.off
                                            ? DynamicsPreset.studioPunch
                                            : state.dynamicsPreset)
                                        : DynamicsPreset.off,
                                    enabled: val,
                                  );
                                },
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
                              fontWeight: FontWeight.w600))),
                _effectNotAppliedNotice('dynamics', p),
                const SizedBox(height: AppSpacing.s14),

                // Dynamics Preset Cards Grid
                Opacity(
                  opacity: dspBlocked != null
                      ? 0.35
                      : (state.isDynamicsEnabled ? 1.0 : 0.35),
                  child: Column(
                    children: DynamicsPreset.values
                        .where((d) => d != DynamicsPreset.off)
                        .map((preset) {
                      final isSelected = state.isDynamicsEnabled &&
                          state.dynamicsPreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: InkWell(
                          onTap:
                              dspBlocked != null || !state.isDynamicsSupported
                                  ? null
                                  : (state.isDynamicsEnabled
                                      ? () => cubit.setDynamicsPreset(preset,
                                          enabled: true)
                                      : null),
                          borderRadius: AppRadii.r10All,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.s10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? p.accent.withValues(alpha: 0.15)
                                  : p.surface,
                              borderRadius: AppRadii.r10All,
                              border: Border.all(
                                color: isSelected
                                    ? p.accent.withValues(alpha: 0.5)
                                    : p.hairline,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: isSelected ? p.accent : p.textTertiary,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.s10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        preset.label,
                                        style: TextStyle(
                                          fontSize: AppFontSize.label,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? p.accent
                                              : p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.s2),
                                      Text(
                                        preset.description,
                                        style: TextStyle(
                                            fontSize: AppFontSize.caption,
                                            color: p.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 1. Headphone Crossfeed (Chu Moy / Linkwitz-Riley)
          Container(
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
                            child: Icon(Icons.headphones_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.crossfeedHp,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  context.l10n.crossfeedNatural,
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        tooltip: context.l10n.dspAboutCrossfeed,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.crossfeed,
                            conflictReason: dspBlocked ??
                                (_nativePcmEffectsAvailable
                                    ? null
                                    : context.l10n.dspRequiresPcmPath))),
                    const SizedBox(width: AppSpacing.xxs),
                    Switch.adaptive(
                      value: dspBlocked == null &&
                          _nativePcmEffectsAvailable &&
                          state.isCrossfeedEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !_nativePcmEffectsAvailable
                              ? null
                              : (val) {
                                  _crossfeedAuditionTimer?.cancel();
                                  _crossfeedAuditionTimer = null;
                                  _crossfeedPreAuditionEnabled = null;
                                  cubit.setCrossfeed(val);
                                },
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
                              fontWeight: FontWeight.w600))),
                if (dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    !state.isCrossfeedEnabled) ...[
                  const SizedBox(height: AppSpacing.s10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.headphones_rounded, size: 14),
                      label: Text(context.l10n.eqAuditionFiveSeconds),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs),
                      ),
                      onPressed: () =>
                          _triggerCrossfeedAudition(context, cubit, state),
                    ),
                  ),
                ],
                if (dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isCrossfeedEnabled) ...[
                  const SizedBox(height: AppSpacing.s14),
                  // BS2B Preset Selector Chips
                  Text(
                    context.l10n.crossfeedAlgorithm,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text(context.l10n.dspCrossfeedDefault),
                        selected: state.crossfeedMode == 0,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 0 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 0
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) {
                          PulsrHaptics.selectionClick();
                          cubit.setCrossfeedMode(0);
                        },
                      ),
                      ChoiceChip(
                        label: Text(context.l10n.dspCrossfeedChuMoy),
                        selected: state.crossfeedMode == 1,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 1 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 1
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) {
                          PulsrHaptics.selectionClick();
                          cubit.setCrossfeedMode(1);
                        },
                      ),
                      ChoiceChip(
                        label: Text(context.l10n.dspCrossfeedJanMeier),
                        selected: state.crossfeedMode == 2,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 2 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 2
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) {
                          PulsrHaptics.selectionClick();
                          cubit.setCrossfeedMode(2);
                        },
                      ),
                      ChoiceChip(
                        label: Text(context.l10n.customDelayLine),
                        selected: state.crossfeedMode == 3,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 3 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 3
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) {
                          PulsrHaptics.selectionClick();
                          cubit.setCrossfeedMode(3);
                        },
                      ),
                    ],
                  ),
                  if (state.crossfeedMode < 3) ...[
                    const SizedBox(height: AppSpacing.s10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s10, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.08),
                        borderRadius: AppRadii.r10All,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: p.accent, size: 16),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              context.l10n.bs2bActive,
                              style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption),
                            ),
                          ),
                          TextButton.icon(
                            icon:
                                const Icon(Icons.headphones_rounded, size: 14),
                            label: Text(context.l10n.eqAuditionFiveSeconds),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs),
                            ),
                            onPressed: () => _triggerCrossfeedAudition(
                                context, cubit, state),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (state.crossfeedMode == 3) ...[
                    const SizedBox(height: AppSpacing.s14),
                    // Delay slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.delayTime,
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${state.crossfeedDelayUs.round()} µs',
                              style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            IconButton(
                              icon: Icon(Icons.settings_backup_restore,
                                  size: 15,
                                  color: (state.crossfeedDelayUs - 350.0)
                                              .abs() <
                                          1.0
                                      ? p.textTertiary.withValues(alpha: 0.35)
                                      : p.accent),
                              tooltip: context.l10n.dspResetToDefault350us,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              onPressed:
                                  (state.crossfeedDelayUs - 350.0).abs() < 1.0
                                      ? null
                                      : () => cubit.setCrossfeed(true,
                                          delayUs: 350.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: p.accent,
                        inactiveTrackColor: p.surface,
                        thumbColor: p.accent,
                      ),
                      child: Semantics(
                        slider: true,
                        excludeSemantics: true,
                        label: context.l10n.delayTime,
                        value: '${state.crossfeedDelayUs.round()} µs',
                        increasedValue:
                            '${(state.crossfeedDelayUs + 50.0).clamp(200.0, 700.0).round()} µs',
                        decreasedValue:
                            '${(state.crossfeedDelayUs - 50.0).clamp(200.0, 700.0).round()} µs',
                        onIncrease: () => cubit.setCrossfeed(true,
                            delayUs: (state.crossfeedDelayUs + 50.0)
                                .clamp(200.0, 700.0)),
                        onDecrease: () => cubit.setCrossfeed(true,
                            delayUs: (state.crossfeedDelayUs - 50.0)
                                .clamp(200.0, 700.0)),
                        child: ThrottledSlider(
                          value: state.crossfeedDelayUs.clamp(200.0, 700.0),
                          min: 200.0,
                          max: 700.0,
                          divisions: 50,
                          onChanged: (val) =>
                              cubit.setCrossfeed(true, delayUs: val),
                        ),
                      ),
                    ),
                    // Feed Level slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.oppositeEarBleed,
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${state.crossfeedFeedDb.toStringAsFixed(1)} dB',
                              style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            IconButton(
                              icon: Icon(Icons.settings_backup_restore,
                                  size: 15,
                                  color: (state.crossfeedFeedDb - (-9.0))
                                              .abs() <
                                          0.05
                                      ? p.textTertiary.withValues(alpha: 0.35)
                                      : p.accent),
                              tooltip: context.l10n.dspResetToDefault9db,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              onPressed:
                                  (state.crossfeedFeedDb - (-9.0)).abs() < 0.05
                                      ? null
                                      : () => cubit.setCrossfeed(true,
                                          feedDb: -9.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: p.accent,
                        inactiveTrackColor: p.surface,
                        thumbColor: p.accent,
                      ),
                      child: Semantics(
                        slider: true,
                        excludeSemantics: true,
                        label: context.l10n.oppositeEarBleed,
                        value: '${state.crossfeedFeedDb.toStringAsFixed(1)} dB',
                        increasedValue:
                            '${(state.crossfeedFeedDb + 0.5).clamp(-15.0, -6.0).toStringAsFixed(1)} dB',
                        decreasedValue:
                            '${(state.crossfeedFeedDb - 0.5).clamp(-15.0, -6.0).toStringAsFixed(1)} dB',
                        onIncrease: () => cubit.setCrossfeed(true,
                            feedDb: (state.crossfeedFeedDb + 0.5)
                                .clamp(-15.0, -6.0)),
                        onDecrease: () => cubit.setCrossfeed(true,
                            feedDb: (state.crossfeedFeedDb - 0.5)
                                .clamp(-15.0, -6.0)),
                        child: ThrottledSlider(
                          value: state.crossfeedFeedDb.clamp(-15.0, -6.0),
                          min: -15.0,
                          max: -6.0,
                          divisions: 18,
                          onChanged: (val) =>
                              cubit.setCrossfeed(true, feedDb: val),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 1b. HRTF 3D Binaural Spatializer (§8.9 & §9)
          HrtfBinauralCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),

          const SizedBox(height: AppSpacing.md),

          // 2. Lookahead Brickwall Limiter
          Container(
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
                            child: Icon(Icons.security_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.lookaheadLimiter,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  context.l10n.lookaheadDesc,
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        tooltip: context.l10n.dspAboutLimiter,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.limiter,
                            conflictReason: dspBlocked)),
                    const SizedBox(width: AppSpacing.xxs),
                    Switch.adaptive(
                      value: dspBlocked == null && state.isLimiterEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null
                          ? null
                          : (val) => cubit.setLookaheadLimiter(val),
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
                              fontWeight: FontWeight.w600))),
                if (dspBlocked == null && state.isLimiterEnabled) ...[
                  const SizedBox(height: AppSpacing.s14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.ceilingThreshold,
                          style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.limiterThresholdDb.toStringAsFixed(1)} dBFS',
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 15,
                                color:
                                    (state.limiterThresholdDb - (-0.2)).abs() <
                                            0.05
                                        ? p.textTertiary.withValues(alpha: 0.35)
                                        : p.accent),
                            tooltip: context.l10n.dspResetToDefault02dbfs,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            onPressed:
                                (state.limiterThresholdDb - (-0.2)).abs() < 0.05
                                    ? null
                                    : () => cubit.setLookaheadLimiter(true,
                                        thresholdDb: -0.2),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Builder(
                      builder: (context) {
                        final limitThresh =
                            state.limiterThresholdDb.clamp(-6.0, 0.0);
                        final nextThresh = (limitThresh + 0.1).clamp(-6.0, 0.0);
                        final prevThresh = (limitThresh - 0.1).clamp(-6.0, 0.0);
                        return Semantics(
                          slider: true,
                          excludeSemantics: true,
                          label: context.l10n.ceilingThreshold,
                          value: '${limitThresh.toStringAsFixed(1)} dBFS',
                          increasedValue:
                              '${nextThresh.toStringAsFixed(1)} dBFS',
                          decreasedValue:
                              '${prevThresh.toStringAsFixed(1)} dBFS',
                          onIncrease: () => cubit.setLookaheadLimiter(true,
                              thresholdDb: nextThresh),
                          onDecrease: () => cubit.setLookaheadLimiter(true,
                              thresholdDb: prevThresh),
                          child: ThrottledSlider(
                            value: limitThresh,
                            min: -6.0,
                            max: 0.0,
                            divisions: 60,
                            onChanged: (val) => cubit.setLookaheadLimiter(true,
                                thresholdDb: val),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.releaseTime,
                          style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.limiterReleaseMs.round()} ms',
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 15,
                                color:
                                    (state.limiterReleaseMs - 50.0).abs() < 0.5
                                        ? p.textTertiary.withValues(alpha: 0.35)
                                        : p.accent),
                            tooltip: context.l10n.dspResetToDefault50ms,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            onPressed:
                                (state.limiterReleaseMs - 50.0).abs() < 0.5
                                    ? null
                                    : () => cubit.setLookaheadLimiter(true,
                                        releaseMs: 50.0),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Builder(
                      builder: (context) {
                        final limitRel =
                            state.limiterReleaseMs.clamp(10.0, 200.0);
                        final nextRel = (limitRel + 5.0).clamp(10.0, 200.0);
                        final prevRel = (limitRel - 5.0).clamp(10.0, 200.0);
                        return Semantics(
                          slider: true,
                          excludeSemantics: true,
                          label: context.l10n.releaseTime,
                          value: '${limitRel.round()} ms',
                          increasedValue: '${nextRel.round()} ms',
                          decreasedValue: '${prevRel.round()} ms',
                          onIncrease: () => cubit.setLookaheadLimiter(true,
                              releaseMs: nextRel),
                          onDecrease: () => cubit.setLookaheadLimiter(true,
                              releaseMs: prevRel),
                          child: ThrottledSlider(
                            value: limitRel,
                            min: 10.0,
                            max: 200.0,
                            divisions: 38,
                            onChanged: (val) =>
                                cubit.setLookaheadLimiter(true, releaseMs: val),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Stereo Balance & Mono Mix
          Container(
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
                            child: Icon(Icons.compare_arrows_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        context.l10n.stereoBalanceMono,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: AppFontSize.body,
                                            color: p.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                        icon: Icon(Icons.info_outline_rounded,
                                            size: 16, color: p.textTertiary),
                                        tooltip:
                                            context.l10n.dspAboutStereoBalance,
                                        onPressed: () => _showFeatureInfo(
                                            context,
                                            AudioFeatureRegistry.panner,
                                            conflictReason: dspBlocked ??
                                                (_nativePcmEffectsAvailable
                                                    ? null
                                                    : context.l10n
                                                        .dspRequiresPcmPath))),
                                  ],
                                ),
                                Text(
                                  context.l10n.panDesc,
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Row(
                      children: [
                        Text(context.l10n.monoLabel,
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                                color: state.monoMix
                                    ? p.accent
                                    : p.textSecondary)),
                        const SizedBox(width: AppSpacing.xxs),
                        Switch.adaptive(
                          value: dspBlocked == null &&
                              _nativePcmEffectsAvailable &&
                              state.monoMix,
                          activeTrackColor: p.accent,
                          activeThumbColor: p.onAccent,
                          onChanged:
                              dspBlocked != null || !_nativePcmEffectsAvailable
                                  ? null
                                  : (val) => cubit.setMonoMix(val),
                        ),
                      ],
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
                              fontWeight: FontWeight.w600)))
                else if (!_nativePcmEffectsAvailable)
                  Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s6),
                      child: Text(context.l10n.nativeDspUnavailable,
                          style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w600))),
                const SizedBox(height: AppSpacing.s14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('L',
                        style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w800,
                            color: dspBlocked != null
                                ? p.textTertiary
                                : (state.stereoBalance < -0.05
                                    ? p.accent
                                    : p.textSecondary))),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dspBlocked != null
                              ? context.l10n.dspBlockedBadge
                              : (state.stereoBalance.abs() < 0.05
                                  ? context.l10n.roomPositionCenter
                                  : (state.stereoBalance < 0
                                      ? context.l10n.balanceLeftPercent(
                                          (-state.stereoBalance * 100).round())
                                      : context.l10n.balanceRightPercent(
                                          (state.stereoBalance * 100)
                                              .round()))),
                          style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                              color: dspBlocked != null ? p.error : p.accent),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        IconButton(
                          icon: Icon(Icons.settings_backup_restore,
                              size: 15,
                              color: dspBlocked != null ||
                                      !_nativePcmEffectsAvailable ||
                                      state.stereoBalance.abs() < 0.01
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                          tooltip: context.l10n.dspResetBalanceCenter,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: dspBlocked != null ||
                                  !_nativePcmEffectsAvailable ||
                                  state.stereoBalance.abs() < 0.01
                              ? null
                              : () => cubit.setStereoBalance(0.0),
                        ),
                      ],
                    ),
                    Text('R',
                        style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w800,
                            color: dspBlocked != null
                                ? p.textTertiary
                                : (state.stereoBalance > 0.05
                                    ? p.accent
                                    : p.textSecondary))),
                  ],
                ),
                Builder(
                  builder: (context) {
                    final bal = state.stereoBalance.clamp(-1.0, 1.0);
                    final nextBal = (bal + 0.05).clamp(-1.0, 1.0);
                    final prevBal = (bal - 0.05).clamp(-1.0, 1.0);
                    final balEnabled =
                        dspBlocked == null && _nativePcmEffectsAvailable;
                    String formatBal(double b) => b.abs() < 0.05
                        ? context.l10n.roomPositionCenter
                        : (b < 0
                            ? context.l10n
                                .balanceLeftPercent((-b * 100).round())
                            : context.l10n
                                .balanceRightPercent((b * 100).round()));
                    return Semantics(
                      slider: true,
                      excludeSemantics: true,
                      enabled: balEnabled,
                      label: context.l10n.stereoBalanceMono,
                      value: formatBal(bal),
                      increasedValue: formatBal(nextBal),
                      decreasedValue: formatBal(prevBal),
                      onIncrease: balEnabled
                          ? () => cubit.setStereoBalance(nextBal)
                          : null,
                      onDecrease: balEnabled
                          ? () => cubit.setStereoBalance(prevBal)
                          : null,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          activeTrackColor:
                              dspBlocked != null ? p.textTertiary : p.accent,
                          inactiveTrackColor: p.surface,
                          thumbColor:
                              dspBlocked != null ? p.textTertiary : p.accent,
                        ),
                        child: ThrottledSlider(
                          value: bal,
                          min: -1.0,
                          max: 1.0,
                          divisions: 40,
                          onChanged: balEnabled
                              ? (val) => cubit.setStereoBalance(val)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 4. Convolution Reverb & Room Acoustics
          Container(
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
                            child: Icon(Icons.meeting_room_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.roomConv,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  context.l10n.irDesc,
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        tooltip: context.l10n.dspAboutReverb,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.reverb,
                            conflictReason: dspBlocked ??
                                (_nativePcmEffectsAvailable
                                    ? null
                                    : context.l10n.dspRequiresPcmPath))),
                    const SizedBox(width: AppSpacing.xxs),
                    Switch.adaptive(
                      value: dspBlocked == null &&
                          _nativePcmEffectsAvailable &&
                          state.isReverbEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !_nativePcmEffectsAvailable
                              ? null
                              : (val) => cubit.setReverb(val),
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
                              fontWeight: FontWeight.w600)))
                else if (!_nativePcmEffectsAvailable)
                  Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s6),
                      child: Text(context.l10n.nativeDspUnavailable,
                          style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w600))),
                if (dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isReverbEnabled) ...[
                  const SizedBox(height: AppSpacing.s14),
                  // Room presets chips. Ordinals are the C++ ReverbPreset
                  // enum, so the synthesized IR always matches the label.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final preset in ReverbPreset.values)
                        _buildReverbChip(preset, state.reverbPreset, cubit, p),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.wetDryMix,
                          style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.dspWetPercent(
                                (state.reverbWetDry * 100).round()),
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 15,
                                color: (state.reverbWetDry - 0.20).abs() < 0.01
                                    ? p.textTertiary.withValues(alpha: 0.35)
                                    : p.accent),
                            tooltip: context.l10n.dspResetToDefault20wet,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            onPressed: (state.reverbWetDry - 0.20).abs() < 0.01
                                ? null
                                : () => cubit.setReverb(true, wetDry: 0.20),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Builder(
                      builder: (context) {
                        final wetDry = state.reverbWetDry.clamp(0.0, 1.0);
                        final nextWetDry = (wetDry + 0.05).clamp(0.0, 1.0);
                        final prevWetDry = (wetDry - 0.05).clamp(0.0, 1.0);
                        return Semantics(
                          slider: true,
                          excludeSemantics: true,
                          label: context.l10n.wetDryMix,
                          value: context.l10n
                              .dspWetPercent((wetDry * 100).round()),
                          increasedValue: context.l10n
                              .dspWetPercent((nextWetDry * 100).round()),
                          decreasedValue: context.l10n
                              .dspWetPercent((prevWetDry * 100).round()),
                          onIncrease: () =>
                              cubit.setReverb(true, wetDry: nextWetDry),
                          onDecrease: () =>
                              cubit.setReverb(true, wetDry: prevWetDry),
                          child: ThrottledSlider(
                            value: wetDry,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) =>
                                cubit.setReverb(true, wetDry: val),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Harmonic Saturation / Exciter (Phase 1 DSP expansion)
          _buildSaturationCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 4. Stereo Width — Mid/Side (Phase 1 DSP expansion)
          _buildStereoWidthCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 5. Subwoofer Crossover — bass redirection (Phase 1 DSP expansion)
          _buildSubCrossoverCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 5b. Multichannel Speaker Alignment & LFE Bass Management (P2-11)
          MultichannelBassCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
          const SizedBox(height: AppSpacing.md),

          // Dynamic Bass (Dynamic System / ViPER4Android parity)
          _buildDynamicBassCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 6. Dynamic EQ (Phase 1 DSP expansion)
          _buildDynamicEqCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 7. Loudness Contour (Fletcher-Munson) — previously persisted with
          // no reachable control.
          _buildLoudnessContourCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 8. TPDF Dither — previously persisted with no reachable control.
          _buildDitherCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 9. Conversion quality — tap-side SRC kernel, or the platform's.
          ConversionQualityCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
          const SizedBox(height: AppSpacing.md),

          // 9b. Remaster Suite — Output oversampling, reconstruction filters & PCM->DSD
          RemasterControlCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
          const SizedBox(height: AppSpacing.md),

          // 10. ViPER-DDC Headphone Correction (JamesDSP parity)
          _buildViperDdcCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 11. Arbitrary Response EQ / GraphicEq (JamesDSP parity)
          _buildArbitraryEqCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // 12. Live Programmable DSP / EEL VM (JamesDSP parity)
          _buildLiveProgCard(context, state, cubit, dspBlocked, p),
        ],
      ),
    );
  }

  Widget _buildReverbChip(ReverbPreset preset, int currentPreset,
      PlayerCubit cubit, PulsrPalette p) {
    final isSelected = preset.wireValue == currentPreset;
    if (preset == ReverbPreset.custom) {
      return ActionChip(
        avatar: Icon(Icons.file_upload_outlined,
            size: 14, color: isSelected ? p.accent : p.textSecondary),
        label: Text(isSelected
            ? context.l10n.eqIrCustomLoaded
            : context.l10n.eqIrLoadWav),
        backgroundColor:
            isSelected ? p.accent.withValues(alpha: 0.22) : p.surface,
        side: BorderSide(color: isSelected ? p.accent : p.hairline),
        labelStyle: TextStyle(
          color: isSelected ? p.accent : p.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: AppFontSize.caption,
        ),
        onPressed: () => cubit.pickAndLoadCustomIrFile(),
      );
    }
    return ChoiceChip(
      label: Text(preset.label),
      selected: isSelected,
      selectedColor: p.accent.withValues(alpha: 0.22),
      backgroundColor: p.surface,
      side: BorderSide(
        color: isSelected ? p.accent : p.hairline,
      ),
      labelStyle: TextStyle(
        color: isSelected ? p.accent : p.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: AppFontSize.caption,
      ),
      onSelected: (_) {
        PulsrHaptics.selectionClick();
        cubit.setReverb(true, preset: preset.wireValue);
      },
    );
  }

  // ---- Phase 1 DSP expansion cards ----

  /// Shared label/value header + slider row used by the expansion cards,
  /// matching the visual style of the Crossfeed/Limiter sliders above.
  Widget _buildDspSliderRow({
    required BuildContext context,
    required PulsrPalette p,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    double? defaultValue,
    int? divisions,
    bool enabled = true,
    required ValueChanged<double> onChanged,
  }) {
    final isDefault =
        defaultValue != null && (value - defaultValue).abs() < 0.001;
    final step = (max - min) / (divisions ?? 20);
    final nextVal = (value + step).clamp(min, max);
    final prevVal = (value - step).clamp(min, max);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: enabled ? p.textSecondary : p.textTertiary,
                    fontWeight: FontWeight.w600)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valueText,
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w700,
                        color: enabled ? p.accent : p.textTertiary)),
                if (defaultValue != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  IconButton(
                    icon: Icon(Icons.settings_backup_restore,
                        size: 15,
                        color: !enabled || isDefault
                            ? p.textTertiary.withValues(alpha: 0.35)
                            : p.accent),
                    tooltip: context.l10n.dspResetToDefault,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: !enabled || isDefault
                        ? null
                        : () => onChanged(defaultValue),
                  ),
                ],
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor:
                enabled ? p.accent : p.textTertiary.withValues(alpha: 0.3),
            inactiveTrackColor: p.surface,
            thumbColor: enabled ? p.accent : p.textTertiary,
          ),
          child: Semantics(
            slider: true,
            excludeSemantics: true,
            enabled: enabled,
            label: label,
            value: valueText,
            increasedValue: nextVal.toStringAsFixed(1),
            decreasedValue: prevVal.toStringAsFixed(1),
            onIncrease: enabled ? () => onChanged(nextVal) : null,
            onDecrease: enabled ? () => onChanged(prevVal) : null,
            child: ThrottledSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaturationCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
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
                      child:
                          Icon(Icons.waves_rounded, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspSaturationTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspSaturationSubtitle,
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
                  tooltip: l10n.dspSaturationTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.saturation,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : context.l10n.dspRequiresPcmPath))),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isSaturationEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setSaturation(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isSaturationEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSaturationDrive,
              valueText: '${(state.saturationDrive * 100).round()}%',
              value: state.saturationDrive,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.3,
              divisions: 20,
              onChanged: (val) => cubit.setSaturation(true, drive: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSaturationMix,
              valueText: context.l10n
                  .dspWetPercent((state.saturationMix * 100).round()),
              value: state.saturationMix,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.5,
              divisions: 20,
              onChanged: (val) => cubit.setSaturation(true, mix: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSaturationTilt,
              valueText: '${(state.saturationTilt * 100).round()}%',
              value: state.saturationTilt,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.3,
              divisions: 20,
              onChanged: (val) => cubit.setSaturation(true, tilt: val),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.multibandWarmth,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      context.l10n.saturationBandDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: state.saturationMultiband,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) => cubit.setSaturationMultiband(val),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStereoWidthCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
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
                      child: Icon(Icons.compare_arrows_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspStereoWidthTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspStereoWidthSubtitle,
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
                  tooltip: l10n.dspStereoWidthTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.stereoWidth,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : context.l10n.dspRequiresPcmPath))),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isStereoWidthEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setStereoWidth(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isStereoWidthEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspStereoWidthAmount,
              valueText: state.stereoWidth.toStringAsFixed(2),
              value: state.stereoWidth,
              min: 0.0,
              max: 2.0,
              defaultValue: 1.0,
              divisions: 40,
              onChanged: (val) => cubit.setStereoWidth(true, width: val),
            ),
            const SizedBox(height: AppSpacing.s6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.dspMultibandLabel,
                    style: TextStyle(
                        fontSize: AppFontSize.label, color: p.textSecondary)),
                Switch.adaptive(
                  value: state.stereoWidthMultiband,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) =>
                      cubit.setStereoWidth(true, multiband: val),
                ),
              ],
            ),
            if (state.stereoWidthMultiband) ...[
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.dspBandLow,
                valueText: state.stereoWidthLow.toStringAsFixed(2),
                value: state.stereoWidthLow,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                divisions: 40,
                onChanged: (val) => cubit.setStereoWidth(true, lowWidth: val),
              ),
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.dspBandMid,
                valueText: state.stereoWidthMid.toStringAsFixed(2),
                value: state.stereoWidthMid,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                divisions: 40,
                onChanged: (val) => cubit.setStereoWidth(true, midWidth: val),
              ),
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.dspBandHigh,
                valueText: state.stereoWidthHigh.toStringAsFixed(2),
                value: state.stereoWidthHigh,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                divisions: 40,
                onChanged: (val) => cubit.setStereoWidth(true, highWidth: val),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubCrossoverCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
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
                      child: Icon(Icons.speaker_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspSubCrossoverTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspSubCrossoverSubtitle,
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
                  tooltip: l10n.dspSubCrossoverTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.subCrossover,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : context.l10n.dspRequiresPcmPath))),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isSubCrossoverEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setSubCrossover(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isSubCrossoverEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            // Honest copy: this is bass redirection, not multichannel LFE.
            Text(l10n.dspSubCrossoverNote,
                style: TextStyle(
                    fontSize: AppFontSize.caption, color: p.textTertiary)),
            const SizedBox(height: AppSpacing.s10),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSubCrossoverCorner,
              valueText: '${state.subCrossoverCornerHz.round()} Hz',
              value: state.subCrossoverCornerHz,
              min: 60.0,
              max: 150.0,
              defaultValue: 80.0,
              divisions: 18,
              onChanged: (val) => cubit.setSubCrossover(true, cornerHz: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSubCrossoverSubLevel,
              valueText: '${(state.subCrossoverGain * 100).round()}%',
              value: state.subCrossoverGain,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.8,
              divisions: 20,
              onChanged: (val) => cubit.setSubCrossover(true, gain: val),
            ),
            SwitchListTile.adaptive(
              title: Text(context.l10n.bassMono,
                  style: TextStyle(fontSize: AppFontSize.body)),
              subtitle: Text(context.l10n.bassMonoDesc,
                  style: TextStyle(
                      fontSize: AppFontSize.caption, color: p.textTertiary)),
              value: state.subCrossoverBassMono,
              activeThumbColor: p.onAccent,
              activeTrackColor: p.accent,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => cubit.setSubCrossover(
                true,
                cornerHz: state.subCrossoverCornerHz,
                slopeDbPerOct: state.subCrossoverSlopeDbPerOct,
                gain: state.subCrossoverGain,
                bassMono: v,
                antiPop: state.subCrossoverAntiPop,
              ),
            ),
            SwitchListTile.adaptive(
              title: Text(context.l10n.antiPop,
                  style: TextStyle(fontSize: AppFontSize.body)),
              subtitle: Text(context.l10n.antiPopDesc,
                  style: TextStyle(
                      fontSize: AppFontSize.caption, color: p.textTertiary)),
              value: state.subCrossoverAntiPop,
              activeThumbColor: p.onAccent,
              activeTrackColor: p.accent,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => cubit.setSubCrossover(
                true,
                cornerHz: state.subCrossoverCornerHz,
                slopeDbPerOct: state.subCrossoverSlopeDbPerOct,
                gain: state.subCrossoverGain,
                bassMono: state.subCrossoverBassMono,
                antiPop: v,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicEqCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
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
                      child: Icon(Icons.graphic_eq_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspDynamicEqTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspDynamicEqSubtitle,
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
                  tooltip: l10n.dspDynamicEqTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.dynamicEq,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : context.l10n.dspRequiresPcmPath))),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isDynamicEqEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setDynamicEq(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isDynamicEqEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            for (int i = 0; i < state.dynamicEqBands.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              _buildDynamicEqBandSection(
                  context, state.dynamicEqBands[i], i, cubit, p),
            ],
            if (state.dynamicEqBands.length < 8) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => cubit.addDynamicEqBand(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.l10n.addBand),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: p.surfaceContainerHigh,
                    foregroundColor: p.textPrimary,
                  ),
                ),
              ),
            ]
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicEqBandSection(BuildContext context,
      DynamicEqBandConfig band, int index, PlayerCubit cubit, PulsrPalette p) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        collapsedBackgroundColor: p.surfaceContainerHigh,
        backgroundColor: p.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.r8All),
        collapsedShape: RoundedRectangleBorder(borderRadius: AppRadii.r8All),
        title: Text(context.l10n.eqBandLabel(index + 1),
            style: TextStyle(
                fontSize: AppFontSize.body,
                fontWeight: FontWeight.w600,
                color: band.enabled ? p.textPrimary : p.textTertiary)),
        leading: Switch.adaptive(
          value: band.enabled,
          activeTrackColor: p.accent,
          onChanged: (val) =>
              cubit.setDynamicEqBand(index, band.copyWith(enabled: val)),
        ),
        // NOTE: No `trailing` override here — that would hide the default
        // expand/collapse chevron. The delete action lives inside the expanded
        // children instead.
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode Toggle
                Row(
                  children: [
                    Text('${context.l10n.modeLabel}:',
                        style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: p.textSecondary)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                              value: 0, label: Text(context.l10n.cutAction)),
                          ButtonSegment(
                              value: 1, label: Text(context.l10n.boostAction)),
                        ],
                        selected: {band.mode},
                        onSelectionChanged: (Set<int> newSelection) {
                          cubit.setDynamicEqBand(
                              index, band.copyWith(mode: newSelection.first));
                        },
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: p.surfaceContainer,
                          selectedBackgroundColor:
                              p.accent.withValues(alpha: 0.2),
                          selectedForegroundColor: p.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Filter Type Dropdown
                Row(
                  children: [
                    Text('${context.l10n.filterLabel}:',
                        style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: p.textSecondary)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // Flutter 3.33+ deprecated `value:` in favor of `initialValue:` on DropdownButtonFormField
                        initialValue: band.filterType,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs),
                          border:
                              OutlineInputBorder(borderRadius: AppRadii.r8All),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: 0,
                              child: Text(context.l10n.peakingFilter)),
                          DropdownMenuItem(
                              value: 1,
                              child: Text(context.l10n.lowShelfFilter)),
                          DropdownMenuItem(
                              value: 2,
                              child: Text(context.l10n.highShelfFilter)),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            cubit.setDynamicEqBand(
                                index, band.copyWith(filterType: val));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqFrequency,
                  valueText: '${band.frequency.round()} Hz',
                  value: band.frequency,
                  min: 60.0,
                  max: 12000.0,
                  defaultValue: 1000.0,
                  divisions: 64,
                  onChanged: (val) => cubit.setDynamicEqBand(
                      index, band.copyWith(frequency: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: context.l10n.dspQBandwidth,
                  valueText: band.q.toStringAsFixed(2),
                  value: band.q,
                  min: 0.5,
                  max: 8.0,
                  defaultValue: 2.0,
                  divisions: 75,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(q: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqThreshold,
                  valueText: '${band.thresholdDb.toStringAsFixed(0)} dB',
                  value: band.thresholdDb,
                  min: -60.0,
                  max: 0.0,
                  defaultValue: -30.0,
                  divisions: 60,
                  onChanged: (val) => cubit.setDynamicEqBand(
                      index, band.copyWith(thresholdDb: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqRatio,
                  valueText: '${band.ratio.toStringAsFixed(1)} : 1',
                  value: band.ratio,
                  min: 1.0,
                  max: 8.0,
                  defaultValue: 3.0,
                  divisions: 35,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(ratio: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqAttack,
                  valueText: '${band.attackMs.toStringAsFixed(1)} ms',
                  value: band.attackMs,
                  min: 0.1,
                  max: 50.0,
                  defaultValue: 5.0,
                  divisions: 50,
                  onChanged: (val) => cubit.setDynamicEqBand(
                      index, band.copyWith(attackMs: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqRelease,
                  valueText: '${band.releaseMs.round()} ms',
                  value: band.releaseMs,
                  min: 20.0,
                  max: 1000.0,
                  defaultValue: 120.0,
                  divisions: 49,
                  onChanged: (val) => cubit.setDynamicEqBand(
                      index, band.copyWith(releaseMs: val)),
                ),
                if (band.mode == 0)
                  _buildDspSliderRow(
                    context: context,
                    p: p,
                    label: l10n.dspDynamicEqMaxCut,
                    valueText: '${band.maxCutDb.toStringAsFixed(0)} dB',
                    value: band.maxCutDb,
                    min: -24.0,
                    max: 0.0,
                    defaultValue: -12.0,
                    divisions: 24,
                    onChanged: (val) => cubit.setDynamicEqBand(
                        index, band.copyWith(maxCutDb: val)),
                  ),
                if (band.mode == 1)
                  _buildDspSliderRow(
                    context: context,
                    p: p,
                    label: context.l10n.dspMaxBoost,
                    valueText: '${band.maxBoostDb.toStringAsFixed(0)} dB',
                    value: band.maxBoostDb,
                    min: 0.0,
                    max: 24.0,
                    defaultValue: 12.0,
                    divisions: 24,
                    onChanged: (val) => cubit.setDynamicEqBand(
                        index, band.copyWith(maxBoostDb: val)),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: Icon(Icons.delete_outline, size: 18, color: p.error),
                    label: Text(context.l10n.delete,
                        style: TextStyle(color: p.error)),
                    onPressed: () => cubit.removeDynamicEqBand(index),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Loudness Contour (Fletcher-Munson). Previously persisted state with no
  /// reachable control; the dead AudioSoundSection was its only renderer.
  Widget _buildLoudnessContourCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
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
                      child: Icon(Icons.volume_up_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.loudnessContour,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(context.l10n.loudnessContourDesc,
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
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isLoudnessContourEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged:
                    !available ? null : (val) => cubit.setLoudnessContour(val),
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
                        fontWeight: FontWeight.w600)))
          else if (!_nativePcmEffectsAvailable)
            Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Text(context.l10n.nativeDspUnavailable,
                    style: TextStyle(
                        color: p.textTertiary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600))),
          if (available && state.isLoudnessContourEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.dspLoudnessIntensity,
              valueText: '${(state.loudnessContourIntensity * 100).round()}%',
              value: state.loudnessContourIntensity,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.0,
              divisions: 20,
              onChanged: (val) =>
                  cubit.setLoudnessContour(true, intensity: val),
            ),
          ],
        ],
      ),
    );
  }

  /// TPDF Dither with a 16/24/32-bit target. Previously persisted with no
  /// reachable control.
  Widget _buildDitherCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
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
                      child:
                          Icon(Icons.grain_rounded, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.tpdfDither,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(context.l10n.ditherDesc,
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
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isDitherEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available ? null : (val) => cubit.setDither(val),
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
                        fontWeight: FontWeight.w600)))
          else if (!_nativePcmEffectsAvailable)
            Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Text(context.l10n.nativeDspUnavailable,
                    style: TextStyle(
                        color: p.textTertiary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600))),
          if (available && state.isDitherEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            Text(context.l10n.targetBitDepth,
                style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final bits in const [16, 24, 32])
                  ChoiceChip(
                    label: Text('$bits-bit'),
                    selected: state.ditherTargetBitDepth == bits,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surface,
                    side: BorderSide(
                      color: state.ditherTargetBitDepth == bits
                          ? p.accent
                          : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      color: state.ditherTargetBitDepth == bits
                          ? p.accent
                          : p.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.caption,
                    ),
                    onSelected: (_) {
                      PulsrHaptics.selectionClick();
                      cubit.setDither(true, targetBitDepth: bits);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViperDdcCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final hasProfile = state.viperDdcProfileName.isNotEmpty;
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
                      child: Icon(Icons.headphones_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              AudioFeatureRegistry.viperDdc
                                  .localized(context.l10n)
                                  .title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            hasProfile
                                ? state.viperDdcProfileName
                                : AudioFeatureRegistry.viperDdc
                                    .localized(context.l10n)
                                    .subtitle,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip:
                    AudioFeatureRegistry.viperDdc.localized(context.l10n).title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.viperDdc,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : context.l10n.dspRequiresPcmPath),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isViperDdcEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setViperDdcEnabled(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isViperDdcEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: Text(
                hasProfile
                    ? context.l10n.viperChangeProfile(state.viperDdcProfileName)
                    : context.l10n.viperSelectLoadProfile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.r10All,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              ),
              onPressed: () {
                PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const ViperDdcSheet(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArbitraryEqCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
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
                      child: Icon(Icons.auto_graph_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              AudioFeatureRegistry.arbitraryEq
                                  .localized(context.l10n)
                                  .title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            AudioFeatureRegistry.arbitraryEq
                                .localized(context.l10n)
                                .subtitle,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip: AudioFeatureRegistry.arbitraryEq
                    .localized(context.l10n)
                    .title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.arbitraryEq,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : context.l10n.dspRequiresPcmPath),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isArbitraryEqEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setArbitraryEqEnabled(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isArbitraryEqEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: Text(
                context.l10n.editGraphicEq,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.r10All,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              ),
              onPressed: () {
                PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const ArbitraryEqSheet(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveProgCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
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
                      child:
                          Icon(Icons.code_rounded, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              AudioFeatureRegistry.liveProg
                                  .localized(context.l10n)
                                  .title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            state.liveProgStatus.isNotEmpty
                                ? state.liveProgStatus
                                : AudioFeatureRegistry.liveProg
                                    .localized(context.l10n)
                                    .subtitle,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip:
                    AudioFeatureRegistry.liveProg.localized(context.l10n).title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.liveProg,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : context.l10n.dspRequiresPcmPath),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isLiveProgEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setLiveProgEnabled(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isLiveProgEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.terminal_rounded, size: 16),
              label: Text(
                context.l10n.openEelEditor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.r10All,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              ),
              onPressed: () {
                PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const LiveProgSheet(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicBassCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
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
                      child: Icon(Icons.speaker_group_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              AudioFeatureRegistry.dynamicBass
                                  .localized(context.l10n)
                                  .title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            AudioFeatureRegistry.dynamicBass
                                .localized(context.l10n)
                                .subtitle,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                tooltip: AudioFeatureRegistry.dynamicBass
                    .localized(context.l10n)
                    .title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.dynamicBass,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : context.l10n.dspRequiresPcmPath),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isDynamicBassEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setDynamicBass(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isDynamicBassEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.dspBassStrength,
              valueText: '${(state.dynamicBassStrength * 100).round()}%',
              value: state.dynamicBassStrength.clamp(1.0, 8.0),
              min: 1.0,
              max: 8.0,
              defaultValue: 1.0,
              divisions: 70,
              onChanged: (val) => cubit.setDynamicBass(true, strength: val),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.acousticCalibModel,
              style: TextStyle(
                fontSize: AppFontSize.label,
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(context.l10n.neutralCustom),
                    selected: state.dynamicBassPreset == 0,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surface,
                    side: BorderSide(
                      color:
                          state.dynamicBassPreset == 0 ? p.accent : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      color: state.dynamicBassPreset == 0
                          ? p.accent
                          : p.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.caption,
                    ),
                    onSelected: (_) {
                      PulsrHaptics.selectionClick();
                      cubit.setDynamicBass(
                        true,
                        preset: 0,
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  for (final item in DynamicBassConfig.builtinPresets) ...[
                    ChoiceChip(
                      label: Text(item.name),
                      selected: state.dynamicBassPreset == item.id,
                      selectedColor: p.accent.withValues(alpha: 0.22),
                      backgroundColor: p.surface,
                      side: BorderSide(
                        color: state.dynamicBassPreset == item.id
                            ? p.accent
                            : p.hairline,
                      ),
                      labelStyle: TextStyle(
                        color: state.dynamicBassPreset == item.id
                            ? p.accent
                            : p.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.caption,
                      ),
                      onSelected: (_) {
                        PulsrHaptics.selectionClick();
                        cubit.setDynamicBass(
                          true,
                          preset: item.id,
                        );
                      },
                    ),
                    const SizedBox(width: AppSpacing.s6),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Conversion-quality control for the tap-side sample-rate converter.
///
/// The choice is a preference rather than [SettingsState]: it mirrors a native
/// kernel size, so it is read on mount and written straight back to prefs.
/// 64/128/256/512 taps select the tap kernel; 256 is the default. Conversion
/// only runs when the sink rate differs from the track rate, so a bit-perfect
/// path is never altered. There is no "off": the tap is the only converter in
/// the playback path (the in-chain sinc stage cannot convert a fixed-size
/// block), and refusing to convert would hand the track to the platform's
/// resampler silently.
class ConversionQualityCard extends StatefulWidget {
  /// Non-null when bit-perfect playback currently bypasses the DSP chain.
  final String? blockedReason;

  /// False when no native PCM effect chain is loaded on this platform.
  final bool nativeAvailable;

  const ConversionQualityCard({
    super.key,
    this.blockedReason,
    this.nativeAvailable = true,
  });

  @override
  State<ConversionQualityCard> createState() => _ConversionQualityCardState();
}

class _ConversionQualityCardState extends State<ConversionQualityCard> {
  /// Segment index == native quality index (0..3 = 64/128/256/512 taps), so
  /// the stored preference is the value the engine consumes verbatim. The
  /// labels come from l10n; the tap counts are named there once.
  static const int _defaultQuality = 2; // 256 taps, the documented baseline.
  static const TextStyle _labelStyle = TextStyle(
    fontSize: AppFontSize.caption,
    fontWeight: FontWeight.w700,
  );

  int _segment = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final stored = (prefs.getInt(PrefsKeys.tapSrcQuality) ?? _defaultQuality)
        .clamp(0, 3);
    setState(() {
      _segment = stored;
      _loaded = true;
    });
    // Reconcile the engine with the stored value. Without this the pref only
    // reaches native when the user touches this card, so a chosen kernel would
    // silently revert to the default on the next launch.
    if (widget.blockedReason == null && widget.nativeAvailable) {
      try {
        await AudioEffectsChannel().setTapSrcQuality(stored);
      } catch (_) {
        // Off Android (or without the DSP bridge) there is nothing to apply;
        // the card stays usable as a stored preference.
      }
    }
  }

  Future<void> _select(int quality) async {
    if (quality == _segment) return;
    PulsrHaptics.selectionClick();
    final previous = _segment;
    setState(() => _segment = quality);
    try {
      final applied = await AudioEffectsChannel().setTapSrcQuality(quality);
      if (!applied) throw StateError('tap SRC refused');
    } catch (_) {
      // A refused kernel must not be persisted as if it were in force: put the
      // control back where the engine still is.
      if (mounted) setState(() => _segment = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(PrefsKeys.tapSrcQuality, quality);
  }

  static String _tapLabel(BuildContext context, int quality) {
    switch (quality.clamp(0, 3)) {
      case 0:
        return context.l10n.conversionTaps64;
      case 1:
        return context.l10n.conversionTaps128;
      case 2:
        return context.l10n.conversionTaps256;
      default:
        return context.l10n.conversionTaps512;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled =
        widget.blockedReason == null && widget.nativeAvailable && _loaded;
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
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(Icons.sync_alt_rounded, color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.conversionQuality,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.body,
                          color: p.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      context.l10n.conversionQualityDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                ),
              ),
              segments: [
                for (var i = 0; i < 4; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(_tapLabel(context, i), style: _labelStyle),
                  ),
              ],
              selected: {_segment},
              onSelectionChanged: enabled
                  ? (values) {
                      if (values.isNotEmpty) _select(values.first);
                    }
                  : null,
            ),
          ),
          if (widget.blockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                  style: TextStyle(
                      color: p.error,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            )
          else if (!widget.nativeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.nativeDspUnavailable,
                  style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// Remaster Suite (P1-5): Output oversampling (PCM), reconstruction filter suite,
/// and real-time PCM->DSD Sigma-Delta Modulation.
