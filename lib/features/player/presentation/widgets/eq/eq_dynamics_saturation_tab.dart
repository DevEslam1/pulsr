part of '../equalizer_sheet.dart';

/// Pro Rack Tab 3: Dynamics & Saturation — Studio Dynamics, Lookahead Limiter,
/// Harmonic Saturation, Sub Crossover, Multichannel Bass, Dynamic Bass,
/// Dynamic EQ, Loudness Contour, TPDF Dither, Conversion Quality, and Remaster.
extension _EqDynamicsSaturationTab on _EqualizerSheetState {
  Widget _buildDynamicsSaturationTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final dspBlocked = _dspBlockedReason(context);
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

          // Studio Dynamics (DynamicsProcessing)
          _buildStudioDynamicsCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.md),

          // Lookahead Brickwall Limiter
          _buildLimiterCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.md),

          // Harmonic Saturation / Exciter
          _buildSaturationCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // Subwoofer Crossover — bass redirection
          _buildSubCrossoverCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // Multichannel Speaker Alignment & LFE Bass Management
          MultichannelBassCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
          const SizedBox(height: AppSpacing.md),

          // Dynamic Bass
          _buildDynamicBassCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // Dynamic EQ
          _buildDynamicEqCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // Loudness Contour (Fletcher-Munson)
          _buildLoudnessContourCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // TPDF Dither
          _buildDitherCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // Conversion Quality (tap-side SRC kernel)
          ConversionQualityCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
          const SizedBox(height: AppSpacing.md),

          // Remaster Suite
          RemasterControlCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
        ],
      ),
    );
  }

  Widget _buildStudioDynamicsCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
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
                    conflictReason: dspBlocked),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null && state.isDynamicsEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !state.isDynamicsSupported
                    ? null
                    : (val) {
                        cubit.setDynamicsPreset(
                          val
                              ? (state.dynamicsPreset == DynamicsPreset.off
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
                      fontWeight: FontWeight.w600)),
            ),
          _effectNotAppliedNotice('dynamics', p),
          const SizedBox(height: AppSpacing.s14),
          Opacity(
            opacity: dspBlocked != null
                ? 0.35
                : (state.isDynamicsEnabled ? 1.0 : 0.35),
            child: Column(
              children: DynamicsPreset.values
                  .where((d) => d != DynamicsPreset.off)
                  .map((preset) {
                final isSelected =
                    state.isDynamicsEnabled && state.dynamicsPreset == preset;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: InkWell(
                    onTap: dspBlocked != null || !state.isDynamicsSupported
                        ? null
                        : (state.isDynamicsEnabled
                            ? () =>
                                cubit.setDynamicsPreset(preset, enabled: true)
                            : null),
                    borderRadius: AppRadii.r10All,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.s10),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preset.label,
                                  style: TextStyle(
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        isSelected ? p.accent : p.textPrimary,
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
    );
  }

  Widget _buildLimiterCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
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
                    conflictReason: dspBlocked),
              ),
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
                      fontWeight: FontWeight.w600)),
            ),
          if (dspBlocked == null && state.isLimiterEnabled) ...[
            const SizedBox(height: AppSpacing.s14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.ceilingThreshold,
              valueText: '${state.limiterThresholdDb.toStringAsFixed(1)} dBFS',
              value: state.limiterThresholdDb.clamp(-6.0, 0.0),
              min: -6.0,
              max: 0.0,
              defaultValue: -0.2,
              divisions: 60,
              onChanged: (val) =>
                  cubit.setLookaheadLimiter(true, thresholdDb: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.releaseTime,
              valueText: '${state.limiterReleaseMs.round()} ms',
              value: state.limiterReleaseMs.clamp(10.0, 200.0),
              min: 10.0,
              max: 200.0,
              defaultValue: 50.0,
              divisions: 38,
              onChanged: (val) =>
                  cubit.setLookaheadLimiter(true, releaseMs: val),
            ),
          ],
        ],
      ),
    );
  }
}
