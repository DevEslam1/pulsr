part of '../equalizer_sheet.dart';

/// Volume Boost and Spatializer quick cards for Pro Rack Tab 0.
extension _EqBoostCards on _EqualizerSheetState {
  Widget _buildVolumeBoostCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final isBoostClamped = EqSheetMath.isBoostClamped(
      requestedBoost: state.volumeBoost,
      effectiveBoost: state.effectiveVolumeBoost,
    );
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
                  color: (isBoostClamped ? p.error : p.accent)
                      .withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(
                  Icons.volume_up_rounded,
                  color: isBoostClamped ? p.error : p.accent,
                  size: 20,
                ),
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
                            context.l10n.volumeBoost,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.bodySmall,
                                color: p.textPrimary),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.info_outline_rounded,
                              size: 16, color: p.textTertiary),
                          tooltip: context.l10n.dspAboutVolumeBoost,
                          onPressed: () => _showFeatureInfo(
                              context, AudioFeatureRegistry.volumeBoost,
                              conflictReason: dspBlocked),
                        ),
                      ],
                    ),
                    Text(
                      state.volumeBoost > 0
                          ? context.l10n.hardwareGainPlusDb(
                              (state.volumeBoost * 10).toStringAsFixed(1))
                          : AudioFeatureRegistry.volumeBoost
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
                      color: (isBoostClamped
                              ? p.error
                              : (state.volumeBoost > 0 ? p.accent : p.surface))
                          .withValues(alpha: 0.15),
                      borderRadius: AppRadii.r8All,
                      border: Border.all(
                        color: isBoostClamped
                            ? p.error.withValues(alpha: 0.4)
                            : (state.volumeBoost > 0
                                ? p.accent.withValues(alpha: 0.3)
                                : p.hairline),
                      ),
                    ),
                    child: Text(
                      state.volumeBoost > 0
                          ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB'
                          : context.l10n.dspOff,
                      style: TextStyle(
                        color: isBoostClamped
                            ? p.error
                            : (state.volumeBoost > 0
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
                        color: state.volumeBoost <= 0.001 || dspBlocked != null
                            ? p.textTertiary.withValues(alpha: 0.35)
                            : p.accent),
                    tooltip: context.l10n.dspResetVolumeBoost,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    onPressed: state.volumeBoost <= 0.001 ||
                            dspBlocked != null ||
                            !state.isVolumeBoostSupported
                        ? null
                        : () => cubit.setVolumeBoost(0.0),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Builder(
            builder: (context) {
              final vVal = state.volumeBoost.clamp(0.0, 1.0);
              final nextVVal = (vVal + 0.05).clamp(0.0, 1.0);
              final prevVVal = (vVal - 0.05).clamp(0.0, 1.0);
              final vEnabled =
                  dspBlocked == null && state.isVolumeBoostSupported;
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: isBoostClamped ? p.error : p.accent,
                  inactiveTrackColor: p.surface,
                  thumbColor: isBoostClamped ? p.error : p.accent,
                ),
                child: Semantics(
                  slider: true,
                  excludeSemantics: true,
                  enabled: vEnabled,
                  label: context.l10n.volumeBoost,
                  value: '${(vVal * 100).round()}%',
                  increasedValue: '${(nextVVal * 100).round()}%',
                  decreasedValue: '${(prevVVal * 100).round()}%',
                  onIncrease: vEnabled
                      ? () {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setVolumeBoost(nextVVal);
                        }
                      : null,
                  onDecrease: vEnabled
                      ? () {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setVolumeBoost(prevVVal);
                        }
                      : null,
                  child: Slider(
                    value: vVal,
                    min: 0.0,
                    max: 1.0,
                    onChanged: !vEnabled
                        ? null
                        : (val) {
                            if (!state.isEqEnabled) {
                              cubit.setEqualizerEnabled(true);
                            }
                            cubit.setVolumeBoost(val);
                          },
                  ),
                ),
              );
            },
          ),
          if (isBoostClamped)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  top: AppSpacing.s2, start: AppSpacing.xxs),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: p.error, size: 13),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: Text(
                      context.l10n.dspLimitedForHeadroom,
                      style: TextStyle(
                          color: p.error,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else if (state.volumeBoost > 0.6)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  top: AppSpacing.s2, start: AppSpacing.xxs),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: p.error, size: 13),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: Text(
                      context.l10n.highBoostWarn,
                      style: TextStyle(
                          color: p.error,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          _effectNotAppliedNotice('volumeBoost', p),
        ],
      ),
    );
  }

  Widget _buildSpatializerQuickCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final spatializerAvailable = _spatializerToggleAvailable(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                            state.isSpatializerSupported
                                ? context.l10n.spatialAudio
                                : context.l10n.soundstageWidening,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.bodySmall,
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
                            color: (state.isSpatializerSupported
                                    ? p.accent
                                    : p.textTertiary)
                                .withValues(alpha: 0.15),
                            borderRadius: AppRadii.r6All,
                          ),
                          child: Text(
                            state.isSpatializerSupported
                                ? context.l10n.spatialApi
                                : context.l10n.spatialEmulated,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              color: state.isSpatializerSupported
                                  ? p.accent
                                  : p.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      state.isSpatializerSupported
                          ? context.l10n.spatialApiDesc
                          : context.l10n.spatialVirtualizerDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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
        _effectNotAppliedNotice('spatializer', p),
      ],
    );
  }
}
