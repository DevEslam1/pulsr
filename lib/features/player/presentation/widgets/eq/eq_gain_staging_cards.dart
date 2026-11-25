part of '../equalizer_sheet.dart';

/// Gain staging and tone cards for Pro Rack Tab 0: Preamp (with live P0-8
/// clip-risk warning), Bass Boost, Volume Boost (with headroom-clamp warning),
/// and Spatializer quick toggle.
extension _EqGainStagingCards on _EqualizerSheetState {
  Widget _buildPreampCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    return BlocSelector<PlayerCubit, PlayerState, List<double>>(
      selector: (s) => s.eqPreset.gains,
      builder: (context, liveGains) => StatefulBuilder(
        builder: (context, setCardState) {
          final currentPreamp = _preampPreview ?? state.dsp.preampDb;
          final maxBoost = EqSheetMath.peakGain(liveGains);
          final autoHeadroomDb = EqSheetMath.autoHeadroomDb(
            liveGains,
            isEqEnabled: state.dsp.isEqEnabled,
          );
          final clipRisk = EqSheetMath.hasClipRisk(
            preampDb: currentPreamp,
            gains: liveGains,
            isEqEnabled: state.dsp.isEqEnabled,
          );
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(
                color: clipRisk ? p.error.withValues(alpha: 0.45) : p.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: (clipRisk ? p.error : p.accent)
                            .withValues(alpha: 0.15),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Icon(
                        Icons.vertical_align_center_rounded,
                        color: clipRisk ? p.error : p.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.preampLabel,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.bodySmall,
                                color: p.textPrimary),
                          ),
                          Text(
                            state.selectedHeadphoneProfile != null
                                ? context.l10n.autoPreampManualOverride(
                                    state.selectedHeadphoneProfile!.preampGain
                                        .toStringAsFixed(1),
                                  )
                                : context.l10n.preampOutputGainHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                          ),
                          if (autoHeadroomDb < -0.05)
                            Text(
                              context.l10n.autoHeadroomValue(
                                  autoHeadroomDb.toStringAsFixed(1)),
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600,
                                color: p.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: (clipRisk
                                ? p.error
                                : (currentPreamp.abs() > 0.05
                                    ? p.accent
                                    : p.surface))
                            .withValues(alpha: 0.15),
                        borderRadius: AppRadii.r8All,
                        border: Border.all(
                          color: clipRisk
                              ? p.error.withValues(alpha: 0.4)
                              : (currentPreamp.abs() > 0.05
                                  ? p.accent.withValues(alpha: 0.3)
                                  : p.hairline),
                        ),
                      ),
                      child: Text(
                        '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)} dB',
                        style: TextStyle(
                          color: clipRisk
                              ? p.error
                              : (currentPreamp.abs() > 0.05
                                  ? p.accent
                                  : p.textSecondary),
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    IconButton(
                      icon: Icon(Icons.settings_backup_restore,
                          size: 16,
                          color:
                              currentPreamp.abs() <= 0.05 || dspBlocked != null
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                      tooltip: context.l10n.dspResetPreamp,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget),
                      onPressed: currentPreamp.abs() <= 0.05 ||
                              dspBlocked != null
                          ? null
                          : () {
                              final target =
                                  state.selectedHeadphoneProfile?.preampGain ??
                                      0.0;
                              _setPreampImmediate(cubit, target);
                              setCardState(() {});
                            },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s6),
                Builder(
                  builder: (context) {
                    final pVal = currentPreamp.clamp(-12.0, 12.0);
                    final nextPVal = (pVal + 0.5).clamp(-12.0, 12.0);
                    final prevPVal = (pVal - 0.5).clamp(-12.0, 12.0);
                    final pEnabled = dspBlocked == null;
                    return Semantics(
                      slider: true,
                      excludeSemantics: true,
                      enabled: pEnabled,
                      label: context.l10n.preampLabel,
                      value:
                          '${pVal > 0 ? '+' : ''}${pVal.toStringAsFixed(1)} dB',
                      increasedValue:
                          '${nextPVal > 0 ? '+' : ''}${nextPVal.toStringAsFixed(1)} dB',
                      decreasedValue:
                          '${prevPVal > 0 ? '+' : ''}${prevPVal.toStringAsFixed(1)} dB',
                      onIncrease: pEnabled
                          ? () {
                              if (!state.isEqEnabled) {
                                cubit.setEqualizerEnabled(true);
                              }
                              _schedulePreamp(
                                  cubit, nextPVal, () => setCardState(() {}));
                            }
                          : null,
                      onDecrease: pEnabled
                          ? () {
                              if (!state.isEqEnabled) {
                                cubit.setEqualizerEnabled(true);
                              }
                              _schedulePreamp(
                                  cubit, prevPVal, () => setCardState(() {}));
                            }
                          : null,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: clipRisk ? p.error : p.accent,
                          inactiveTrackColor: p.surface,
                          thumbColor: clipRisk ? p.error : p.accent,
                        ),
                        child: Slider(
                          value: pVal,
                          min: -12.0,
                          max: 12.0,
                          divisions: 48,
                          onChanged: !pEnabled
                              ? null
                              : (val) {
                                  if (!state.isEqEnabled) {
                                    cubit.setEqualizerEnabled(true);
                                  }
                                  final rounded =
                                      (val * 10).roundToDouble() / 10.0;
                                  _schedulePreamp(cubit, rounded,
                                      () => setCardState(() {}));
                                },
                        ),
                      ),
                    );
                  },
                ),
                if (clipRisk)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        top: AppSpacing.s2, start: AppSpacing.xxs),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: p.error, size: 13),
                        const SizedBox(width: AppSpacing.s6),
                        Expanded(
                          child: Text(
                            context.l10n.dspPreampClipWarning(
                              '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)}',
                              maxBoost.toStringAsFixed(1),
                            ),
                            style: TextStyle(
                                color: p.error,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (currentPreamp > 6.0)
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.xs),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: p.error.withValues(alpha: 0.15),
                      borderRadius: AppRadii.r10All,
                      border: Border.all(color: p.error.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hearing_disabled_rounded,
                            color: p.error, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            '${context.l10n.volume}: ${context.l10n.highBoostWarn}',
                            style: TextStyle(
                              color: p.error,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBassBoostCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final preset = state.eqPreset;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                child: Icon(Icons.speaker_group_rounded,
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
                            context.l10n.bassEnhancer,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.bodySmall,
                                color: p.textPrimary),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.info_outline_rounded,
                              size: 16, color: p.textTertiary),
                          tooltip: context.l10n.dspAboutBassBoost,
                          onPressed: () => _showFeatureInfo(
                              context, AudioFeatureRegistry.bassBoost,
                              conflictReason: dspBlocked),
                        ),
                      ],
                    ),
                    Text(
                      preset.bassBoost > 0
                          ? context.l10n
                              .dspPunchPercent((preset.bassBoost * 100).round())
                          : AudioFeatureRegistry.bassBoost
                              .localized(context.l10n)
                              .subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: (preset.bassBoost > 0 ? p.accent : p.surface)
                          .withValues(alpha: 0.15),
                      borderRadius: AppRadii.r8All,
                      border: Border.all(
                        color: preset.bassBoost > 0
                            ? p.accent.withValues(alpha: 0.3)
                            : p.hairline,
                      ),
                    ),
                    child: Text(
                      preset.bassBoost > 0
                          ? '${(preset.bassBoost * 100).round()}%'
                          : context.l10n.dspOff,
                      style: TextStyle(
                        color:
                            preset.bassBoost > 0 ? p.accent : p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  IconButton(
                    icon: Icon(Icons.settings_backup_restore,
                        size: 16,
                        color: preset.bassBoost <= 0.001 || dspBlocked != null
                            ? p.textTertiary.withValues(alpha: 0.35)
                            : p.accent),
                    tooltip: context.l10n.dspResetBassEnhancer,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    onPressed: preset.bassBoost <= 0.001 ||
                            dspBlocked != null ||
                            !state.isBassBoostSupported
                        ? null
                        : () => cubit.setBassBoost(0.0),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Builder(
            builder: (context) {
              final bVal = preset.bassBoost.clamp(0.0, 1.0);
              final nextBVal = (bVal + 0.05).clamp(0.0, 1.0);
              final prevBVal = (bVal - 0.05).clamp(0.0, 1.0);
              final bEnabled = dspBlocked == null && state.isBassBoostSupported;
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: p.accent,
                  inactiveTrackColor: p.surface,
                  thumbColor: p.accent,
                ),
                child: Semantics(
                  slider: true,
                  excludeSemantics: true,
                  enabled: bEnabled,
                  label: context.l10n.bassEnhancer,
                  value: '${(bVal * 100).round()}%',
                  increasedValue: '${(nextBVal * 100).round()}%',
                  decreasedValue: '${(prevBVal * 100).round()}%',
                  onIncrease: bEnabled
                      ? () {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setBassBoost(nextBVal);
                        }
                      : null,
                  onDecrease: bEnabled
                      ? () {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setBassBoost(prevBVal);
                        }
                      : null,
                  child: Slider(
                    value: bVal,
                    min: 0.0,
                    max: 1.0,
                    onChanged: !bEnabled
                        ? null
                        : (val) {
                            if (!state.isEqEnabled) {
                              cubit.setEqualizerEnabled(true);
                            }
                            cubit.setBassBoost(val);
                          },
                  ),
                ),
              );
            },
          ),
          if (preset.bassBoost - state.effectiveBassBoost > 0.01)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  top: AppSpacing.s2, start: AppSpacing.xxs),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: p.textTertiary, size: 12),
                  const SizedBox(width: AppSpacing.s4),
                  Text(
                    context.l10n.dspLimitedForHeadroom,
                    style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                    ),
                  ),
                ],
              ),
            ),
          _effectNotAppliedNotice('bassBoost', p),
        ],
      ),
    );
  }
}
