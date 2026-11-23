part of '../equalizer_sheet.dart';

/// Pro Rack Tab 0: Parametric / Graphic EQ â€” presets carousel, A/B/C/D slots,
/// studio tool chips, live response curve, 10/32/64-band selector, vertical
/// band slider bank (>= 48dp hit targets), and gain staging cards.
extension _EqParametricTab on _EqualizerSheetState {
  Widget _buildEqualizerTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final preset = state.eqPreset;
    final isEnabled = state.isEqEnabled;
    final dspBlocked = _dspBlockedReason(context);
    final effectiveEnabled = isEnabled && dspBlocked == null;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s20, AppSpacing.xs, AppSpacing.s20, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) _conflictBanner(dspBlocked, p),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  IconButton(
                      constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget),
                      icon: Icon(Icons.info_outline_rounded,
                          size: 18, color: p.accent),
                      tooltip: context.l10n.learnMore,
                      onPressed: () => _showFeatureInfo(
                          context, AudioFeatureRegistry.equalizer,
                          conflictReason: dspBlocked)),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                      child: Text(context.l10n.dspDisabledBp,
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption))),
                ],
              ),
            ),

          // Presets Carousel & Actions Header
          _buildPresetsActionsHeader(
            context: context,
            cubit: cubit,
            state: state,
            preset: preset,
            p: p,
            dspBlocked: dspBlocked,
          ),
          const SizedBox(height: AppSpacing.s10),

          // A/B/C/D 4-Slot Comparison & Studio Tools Row
          _buildStudioToolsRow(
            context: context,
            cubit: cubit,
            state: state,
            p: p,
            dspBlocked: dspBlocked,
          ),
          const SizedBox(height: AppSpacing.s14),

          // OEM Audio Double-Processing Warning Banner
          if (state.hasOemAudio &&
              (state.isEqEnabled ||
                  state.isCrossfeedEnabled ||
                  state.isLimiterEnabled ||
                  state.isVirtualizerEnabled ||
                  state.isDynamicsEnabled)) ...[
            _buildOemDoubleProcessingBanner(context, state, p),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Active AutoEq Profile Banner
          if (state.selectedHeadphoneProfile != null) ...[
            _buildActiveAutoEqBanner(context, cubit, state, p, dspBlocked),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Real-time Frequency Response Curve Visualizer
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: BlocSelector<PlayerCubit, PlayerState, List<double>>(
              selector: (s) => s.eqPreset.gains,
              builder: (context, gains) => RepaintBoundary(
                child: EqCurveVisualizer(
                  gains: gains,
                  activeColor: effectiveEnabled ? p.accent : p.textTertiary,
                  height: 52,
                  selectedBandIndex: _activeDraggedBandIndex,
                  onGainChanged: effectiveEnabled
                      ? (idx, gain) {
                          context.read<PlayerCubit>().setBandGain(idx, gain);
                          if (_autoPreampEnabled) {
                            final updatedGains = List<double>.from(gains);
                            if (idx >= 0 && idx < updatedGains.length) {
                              updatedGains[idx] = gain;
                            }
                            context.read<PlayerCubit>().setPreamp(
                                EqSheetMath.autoPreampFor(updatedGains));
                          }
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),

          // F-32: 10 / 32 / 64-band mode toggle + Auto-Preamp / Reset / Freq
          _buildBandPlanToolbar(
            context: context,
            cubit: cubit,
            state: state,
            p: p,
            dspBlocked: dspBlocked,
          ),
          const SizedBox(height: AppSpacing.xs),

          // Equalizer band sliders (>= 48dp per column)
          _buildBandSlidersContainer(
            context: context,
            cubit: cubit,
            state: state,
            p: p,
            effectiveEnabled: effectiveEnabled,
          ),
          const SizedBox(height: AppSpacing.md),

          // Gain Staging & Quick Tone Cards
          _buildPreampCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.sm),
          _buildBassBoostCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.sm),
          _buildVolumeBoostCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.sm),
          _buildSpatializerQuickCard(context, cubit, state, p, dspBlocked),
        ],
      ),
    );
  }

  Widget _buildPresetsActionsHeader({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required EqPreset preset,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 460;
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: math.max(
                  AppSpacing.minTouchTarget,
                  MediaQuery.textScalerOf(context).scale(38.0),
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemCount: EqPreset.defaultPresets.length,
                  itemBuilder: (context, index) {
                    final presetItem = EqPreset.defaultPresets[index];
                    final isSelected = state.selectedHeadphoneProfile == null &&
                        preset.name == presetItem.name;
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(
                          end: AppSpacing.xs),
                      child: ChoiceChip(
                        label: Text(presetItem.name),
                        selected: isSelected,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surfaceContainer,
                        side: BorderSide(
                          color: isSelected
                              ? p.accent.withValues(alpha: 0.5)
                              : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? p.accent : p.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.label,
                        ),
                        onSelected: dspBlocked != null
                            ? null
                            : (_) {
                                PulsrHaptics.selectionClick();
                                if (!state.isEqEnabled) {
                                  cubit.setEqualizerEnabled(true);
                                }
                                cubit.applyPreset(presetItem);
                              },
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _buildAbCompareToggle(
              cubit: cubit,
              p: p,
              dspBlocked: dspBlocked,
            ),
            const SizedBox(width: AppSpacing.xxs),
            if (isCompact)
              IconButton(
                tooltip: context.l10n.saveCustomEqPreset,
                onPressed: dspBlocked != null
                    ? null
                    : () => _showSaveCustomPresetDialog(cubit, state),
                icon: Icon(Icons.bookmark_add_rounded,
                    size: 18, color: p.accent),
                padding: const EdgeInsets.all(AppSpacing.xxs),
                constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget),
              )
            else
              TextButton.icon(
                onPressed: dspBlocked != null
                    ? null
                    : () => _showSaveCustomPresetDialog(cubit, state),
                icon: Icon(Icons.bookmark_add_rounded,
                    size: 16, color: p.accent),
                label: Text(context.l10n.save,
                    style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: p.accent,
                        fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs),
                ),
              ),
          ],
        );
      },
    );
  }

  static final ValueNotifier<bool> _dspToolsExpanded =
      ValueNotifier<bool>(false);

  Widget _buildStudioToolsRow({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    int activeCount = 0;
    if (state.isViperDdcEnabled) activeCount++;
    if (state.isArbitraryEqEnabled) activeCount++;
    if (state.isLiveProgEnabled) activeCount++;
    if (state.isDynamicBassEnabled) activeCount++;
    if (state.isLimiterEnabled || state.isDynamicsEnabled) activeCount++;
    if (state.selectedHeadphoneProfile != null) activeCount++;

    return ValueListenableBuilder<bool>(
      valueListenable: _dspToolsExpanded,
      builder: (context, isExpanded, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _buildAbSlotSelector(cubit: cubit, p: p),
                const SizedBox(width: AppSpacing.xs),
                ActionChip(
                  avatar: Icon(
                    isExpanded ? Icons.tune_rounded : Icons.handyman_outlined,
                    size: 14,
                    color: isExpanded || activeCount > 0
                        ? p.accent
                        : p.textSecondary,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.dspTools,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                          color: isExpanded || activeCount > 0
                              ? p.accent
                              : p.textPrimary,
                        ),
                      ),
                      if (activeCount > 0) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: AppRadii.r10All,
                          ),
                          child: Text(
                            '$activeCount',
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textOnAccent(p.accent),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.xxs),
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 14,
                        color: isExpanded ? p.accent : p.textSecondary,
                      ),
                    ],
                  ),
                  backgroundColor: isExpanded
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: isExpanded ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () =>
                      _dspToolsExpanded.value = !_dspToolsExpanded.value,
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.surfaceContainer.withValues(alpha: 0.65),
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Correction & Profiles
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildAutoEqChip(context, p),
                          const SizedBox(width: AppSpacing.xs),
                          _buildRoomCorrectionChip(
                              context, cubit, p, dspBlocked),
                          const SizedBox(width: AppSpacing.xs),
                          _buildViperDdcChip(context, state, p),
                          const SizedBox(width: AppSpacing.xs),
                          _buildArbitraryEqChip(context, state, p),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Row 2: Dynamics & Chain
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCompressorChip(context, p),
                          const SizedBox(width: AppSpacing.xs),
                          _buildLiveProgChip(context, state, p),
                          const SizedBox(width: AppSpacing.xs),
                          _buildDynamicBassChip(
                              context, cubit, state, p, dspBlocked),
                          const SizedBox(width: AppSpacing.xs),
                          _buildDspChainChip(context, p),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAutoEqChip(BuildContext context, PulsrPalette p) {
    return ActionChip(
      avatar: Icon(Icons.search_rounded, size: 14, color: p.accent),
      label: Text(context.l10n.autoEqSearch,
          style: const TextStyle(
              fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
      backgroundColor: p.surfaceContainer,
      side: BorderSide(color: p.hairline),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: () {
        PulsrSheetHelper.showPulsrSheet<void>(
          context: context,
          wrapWithContainer: false,
          builder: (_) => const AutoEqSearchSheet(),
        );
      },
    );
  }

  Widget _buildRoomCorrectionChip(BuildContext context, PlayerCubit cubit,
      PulsrPalette p, String? dspBlocked) {
    return ActionChip(
      avatar: Icon(Icons.graphic_eq_rounded, size: 14, color: p.accent),
      label: Text(context.l10n.roomCorrection,
          style: const TextStyle(
              fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
      backgroundColor: p.surfaceContainer,
      side: BorderSide(color: p.hairline),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed:
          dspBlocked != null ? null : () => _showRoomCorrectionActions(cubit),
    );
  }

  Widget _buildViperDdcChip(
      BuildContext context, PlayerState state, PulsrPalette p) {
    return ActionChip(
      avatar: Icon(Icons.headphones_rounded,
          size: 14,
          color: state.isViperDdcEnabled ? p.accent : p.textSecondary),
      label: Text(
        state.isViperDdcEnabled && state.viperDdcProfileName.isNotEmpty
            ? 'DDC: ${state.viperDdcProfileName}'
            : 'ViPER-DDC',
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          color: state.isViperDdcEnabled ? p.accent : p.textPrimary,
        ),
      ),
      backgroundColor: state.isViperDdcEnabled
          ? p.accent.withValues(alpha: 0.15)
          : p.surfaceContainer,
      side: BorderSide(
        color: state.isViperDdcEnabled ? p.accent : p.hairline,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: () {
        PulsrSheetHelper.showPulsrSheet<void>(
          context: context,
          wrapWithContainer: false,
          builder: (_) => const ViperDdcSheet(),
        );
      },
    );
  }

  Widget _buildArbitraryEqChip(
      BuildContext context, PlayerState state, PulsrPalette p) {
    return ActionChip(
      avatar: Icon(Icons.auto_graph_rounded,
          size: 14,
          color: state.isArbitraryEqEnabled ? p.accent : p.textSecondary),
      label: Text(
        context.l10n.arbitraryEq,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          color: state.isArbitraryEqEnabled ? p.accent : p.textPrimary,
        ),
      ),
      backgroundColor: state.isArbitraryEqEnabled
          ? p.accent.withValues(alpha: 0.15)
          : p.surfaceContainer,
      side: BorderSide(
        color: state.isArbitraryEqEnabled ? p.accent : p.hairline,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: () {
        PulsrSheetHelper.showPulsrSheet<void>(
          context: context,
          wrapWithContainer: false,
          builder: (_) => const ArbitraryEqSheet(),
        );
      },
    );
  }

  Widget _buildCompressorChip(BuildContext context, PulsrPalette p) {
    return ActionChip(
      avatar: Icon(Icons.compress_rounded, size: 14, color: p.primary),
      label: Text(context.l10n.dynamicsCompressor,
          style: const TextStyle(
              fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
      backgroundColor: p.surfaceContainer,
      side: BorderSide(color: p.hairline),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: () {
        final blocked = _dspBlockedReason(context);
        if (blocked != null) {
          PulsrToast.show(
            context,
            message: blocked,
            icon: Icons.error_outline_rounded,
            isError: true,
          );
          return;
        }
        if (!getIt.isRegistered<EqualizerManager>()) return;
        CompressorLimiterSheet.show(
          context,
          equalizerManager: getIt<EqualizerManager>(),
        );
      },
    );
  }

  Widget _buildLiveProgChip(
      BuildContext context, PlayerState state, PulsrPalette p) {
    return ActionChip(
      avatar: Icon(Icons.terminal_rounded,
          size: 14,
          color: state.isLiveProgEnabled ? p.accent : p.textSecondary),
      label: Text(
        context.l10n.liveProgDsp,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          color: state.isLiveProgEnabled ? p.accent : p.textPrimary,
        ),
      ),
      backgroundColor: state.isLiveProgEnabled
          ? p.accent.withValues(alpha: 0.15)
          : p.surfaceContainer,
      side: BorderSide(
        color: state.isLiveProgEnabled ? p.accent : p.hairline,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: () {
        PulsrSheetHelper.showPulsrSheet<void>(
          context: context,
          wrapWithContainer: false,
          builder: (_) => const LiveProgSheet(),
        );
      },
    );
  }

  Widget _buildDynamicBassChip(BuildContext context, PlayerCubit cubit,
      PlayerState state, PulsrPalette p, String? dspBlocked) {
    return ActionChip(
      avatar: Icon(Icons.speaker_group_rounded,
          size: 14,
          color: state.isDynamicBassEnabled ? p.accent : p.textSecondary),
      label: Text(
        context.l10n.dynamicBass,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          color: state.isDynamicBassEnabled ? p.accent : p.textPrimary,
        ),
      ),
      backgroundColor: state.isDynamicBassEnabled
          ? p.accent.withValues(alpha: 0.15)
          : p.surfaceContainer,
      side: BorderSide(
        color: state.isDynamicBassEnabled ? p.accent : p.hairline,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: dspBlocked != null || !_nativePcmEffectsAvailable
          ? null
          : () {
              _tabController.animateTo(3);
              cubit.setDynamicBass(!state.isDynamicBassEnabled);
            },
    );
  }

  Widget _buildDspChainChip(BuildContext context, PulsrPalette p) {
    return ActionChip(
      avatar: Icon(Icons.insights_rounded, size: 14, color: p.accent),
      label: Text(context.l10n.dspChain,
          style: const TextStyle(
              fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
      backgroundColor: p.surfaceContainer,
      side: BorderSide(color: p.hairline),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
      onPressed: () => DspInspectorSheet.show(context),
    );
  }

  Widget _buildOemDoubleProcessingBanner(
      BuildContext context, PlayerState state, PulsrPalette p) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.12),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: p.warning, size: 20),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${state.detectedOemEngines.join(", ")} ${context.l10n.activeLabel}',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.warning,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  context.l10n.systemFxActive,
                  style: TextStyle(
                      fontSize: AppFontSize.caption, color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveAutoEqBanner(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final profile = state.selectedHeadphoneProfile!;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.headphones_rounded, color: p.accent, size: 20),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AutoEq: ${profile.name}',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
                Text(
                  '${profile.brand} • '
                  '${context.l10n.preampLabel}: ${profile.preampGain.toStringAsFixed(1)} dB',
                  style: TextStyle(
                      fontSize: AppFontSize.caption, color: p.textTertiary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: dspBlocked != null ? null : () => cubit.resetToFlat(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
            child: Text(context.l10n.reset,
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.caption)),
          ),
        ],
      ),
    );
  }

}
