part of '../equalizer_sheet.dart';

/// Spatial processing cards used by Pro Rack Tab 2: Crossfeed, Stereo Width,
/// Stereo Balance & Mono Mix, and Convolution Reverb.
extension _EqSpatialCards on _EqualizerSheetState {
  Widget _buildCrossfeedCard(
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
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isCrossfeedEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available
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
                      fontWeight: FontWeight.w600)),
            ),
          if (available && !state.isCrossfeedEnabled) ...[
            const SizedBox(height: AppSpacing.s10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.headphones_rounded, size: 14),
                label: Text(context.l10n.eqAuditionFiveSeconds),
                onPressed: () =>
                    _triggerCrossfeedAudition(context, cubit, state),
              ),
            ),
          ],
          if (available && state.isCrossfeedEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
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
                for (final entry in <(int, String)>[
                  (0, context.l10n.dspCrossfeedDefault),
                  (1, context.l10n.dspCrossfeedChuMoy),
                  (2, context.l10n.dspCrossfeedJanMeier),
                  (3, context.l10n.customDelayLine),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: state.crossfeedMode == entry.$1,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surface,
                    side: BorderSide(
                      color: state.crossfeedMode == entry.$1
                          ? p.accent
                          : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600,
                      color: state.crossfeedMode == entry.$1
                          ? p.accent
                          : p.textSecondary,
                    ),
                    onSelected: (_) {
                      PulsrHaptics.selectionClick();
                      cubit.setCrossfeedMode(entry.$1);
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
                    Icon(Icons.auto_awesome_rounded, color: p.accent, size: 16),
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
                      icon: const Icon(Icons.headphones_rounded, size: 14),
                      label: Text(context.l10n.eqAuditionFiveSeconds),
                      onPressed: () =>
                          _triggerCrossfeedAudition(context, cubit, state),
                    ),
                  ],
                ),
              ),
            ],
            if (state.crossfeedMode == 3) ...[
              const SizedBox(height: AppSpacing.s14),
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.delayTime,
                valueText: '${state.crossfeedDelayUs.round()} Âµs',
                value: state.crossfeedDelayUs.clamp(200.0, 700.0),
                min: 200.0,
                max: 700.0,
                defaultValue: 350.0,
                divisions: 50,
                onChanged: (val) => cubit.setCrossfeed(true, delayUs: val),
              ),
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.oppositeEarBleed,
                valueText: '${state.crossfeedFeedDb.toStringAsFixed(1)} dB',
                value: state.crossfeedFeedDb.clamp(-15.0, -6.0),
                min: -15.0,
                max: -6.0,
                defaultValue: -9.0,
                divisions: 18,
                onChanged: (val) => cubit.setCrossfeed(true, feedDb: val),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStereoWidthCard(BuildContext context, PlayerState state,
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
                            : context.l10n.dspRequiresPcmPath)),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: available && state.isStereoWidthEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged:
                    !available ? null : (val) => cubit.setStereoWidth(val),
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
          if (available && state.isStereoWidthEnabled) ...[
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
}
