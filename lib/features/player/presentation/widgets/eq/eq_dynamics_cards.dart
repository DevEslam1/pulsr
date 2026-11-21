part of '../equalizer_sheet.dart';

/// Dynamics & Saturation stage cards used by Pro Rack Tab 3:
/// Harmonic Saturation, Sub Crossover, Dynamic Bass, Loudness Contour, Dither.
extension _EqDynamicsCards on _EqualizerSheetState {
  Widget _buildSaturationCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
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
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isSaturationEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available ? null : (val) => cubit.setSaturation(val),
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
                      fontWeight: FontWeight.w600)),
            ),
          if (available && state.isSaturationEnabled) ...[
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
                Expanded(
                  child: Column(
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
                            fontSize: AppFontSize.caption,
                            color: p.textTertiary),
                      ),
                    ],
                  ),
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

  Widget _buildSubCrossoverCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
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
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isSubCrossoverEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged:
                    !available ? null : (val) => cubit.setSubCrossover(val),
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
                      fontWeight: FontWeight.w600)),
            ),
          if (available && state.isSubCrossoverEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
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
                  style: const TextStyle(fontSize: AppFontSize.body)),
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
                  style: const TextStyle(fontSize: AppFontSize.body)),
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

  Widget _buildDynamicBassCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final available = dspBlocked == null && _nativePcmEffectsAvailable;
    final info = AudioFeatureRegistry.dynamicBass.localized(context.l10n);
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
                          Text(info.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(info.subtitle,
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
                tooltip: info.title,
                onPressed: () => _showFeatureInfo(
                    context, AudioFeatureRegistry.dynamicBass,
                    conflictReason: dspBlocked ??
                        (_nativePcmEffectsAvailable
                            ? null
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isDynamicBassEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged:
                    !available ? null : (val) => cubit.setDynamicBass(val),
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
          if (available && state.isDynamicBassEnabled) ...[
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
                      cubit.setDynamicBass(true, preset: 0);
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
                        cubit.setDynamicBass(true, preset: item.id);
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
