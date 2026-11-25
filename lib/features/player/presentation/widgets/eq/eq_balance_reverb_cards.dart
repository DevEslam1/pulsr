part of '../equalizer_sheet.dart';

/// Stereo Balance/Mono and Convolution Reverb cards for Pro Rack Tab 2.
extension _EqBalanceReverbCards on _EqualizerSheetState {
  Widget _buildStereoBalanceCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
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
                                tooltip: context.l10n.dspAboutStereoBalance,
                                onPressed: () => _showFeatureInfo(
                                    context, AudioFeatureRegistry.panner,
                                    conflictReason: dspBlocked ??
                                        (_nativePcmEffectsAvailable
                                            ? null
                                            : context.l10n.dspRequiresPcmPath)),
                              ),
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
                          color: state.monoMix ? p.accent : p.textSecondary)),
                  const SizedBox(width: AppSpacing.xxs),
                  Switch.adaptive(
                    value: available && state.monoMix,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged:
                        !available ? null : (val) => cubit.setMonoMix(val),
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
                                    (state.stereoBalance * 100).round()))),
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w700,
                        color: dspBlocked != null ? p.error : p.accent),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  IconButton(
                    icon: Icon(Icons.settings_backup_restore,
                        size: 15,
                        color: !available || state.stereoBalance.abs() < 0.01
                            ? p.textTertiary.withValues(alpha: 0.35)
                            : p.accent),
                    tooltip: context.l10n.dspResetBalanceCenter,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    onPressed: !available || state.stereoBalance.abs() < 0.01
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
              String formatBal(double b) => b.abs() < 0.05
                  ? context.l10n.roomPositionCenter
                  : (b < 0
                      ? context.l10n.balanceLeftPercent((-b * 100).round())
                      : context.l10n.balanceRightPercent((b * 100).round()));
              return Semantics(
                slider: true,
                excludeSemantics: true,
                enabled: available,
                label: context.l10n.stereoBalanceMono,
                value: formatBal(bal),
                increasedValue: formatBal(nextBal),
                decreasedValue: formatBal(prevBal),
                onIncrease:
                    available ? () => cubit.setStereoBalance(nextBal) : null,
                onDecrease:
                    available ? () => cubit.setStereoBalance(prevBal) : null,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor:
                        dspBlocked != null ? p.textTertiary : p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: dspBlocked != null ? p.textTertiary : p.accent,
                  ),
                  child: ThrottledSlider(
                    value: bal,
                    min: -1.0,
                    max: 1.0,
                    divisions: 40,
                    onChanged:
                        available ? (val) => cubit.setStereoBalance(val) : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReverbCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
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
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isReverbEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available ? null : (val) => cubit.setReverb(val),
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
          if (available && state.isReverbEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final preset in ReverbPreset.values)
                  _buildReverbChip(preset, state.reverbPreset, cubit, p),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.wetDryMix,
              valueText: context.l10n
                  .dspWetPercent((state.reverbWetDry * 100).round()),
              value: state.reverbWetDry.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              defaultValue: 0.20,
              divisions: 20,
              onChanged: (val) => cubit.setReverb(true, wetDry: val),
            ),
          ],
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
}
