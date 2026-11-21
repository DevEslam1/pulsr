part of '../equalizer_sheet.dart';

/// Loudness Contour and TPDF Dither cards for Pro Rack Tab 3.
extension _EqLoudnessDitherCards on _EqualizerSheetState {
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
}
