part of '../equalizer_sheet.dart';

/// Dynamic EQ card and expandable per-band dynamic filter editor.
extension _EqDynamicEqCard on _EqualizerSheetState {
  Widget _buildDynamicEqCard(BuildContext context, PlayerState state,
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
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isDynamicEqEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available ? null : (val) => cubit.setDynamicEq(val),
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
          if (available && state.isDynamicEqEnabled) ...[
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
                    backgroundColor: p.surfaceContainerHigh,
                    foregroundColor: p.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicEqBandSection(BuildContext context,
      DynamicEqBandConfig band, int index, PlayerCubit cubit, PulsrPalette p) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context)
          .copyWith(dividerColor: p.hairline.withValues(alpha: 0.0)),
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
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Row(
                  children: [
                    Text('${context.l10n.filterLabel}:',
                        style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: p.textSecondary)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<int>(
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
                  alignment: AlignmentDirectional.centerEnd,
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
}
