part of '../equalizer_sheet.dart';

/// Pro Rack Tab 2: Spatial & HRTF — Hardware Spatializer, Virtualizer
/// Soundstage Widening, Headphone Crossfeed, HRTF 3D Binaural Spatializer,
/// Stereo Balance & Mono, Convolution Reverb, and Mid/Side Stereo Width.
extension _EqSpatialHrtfTab on _EqualizerSheetState {
  Widget _buildSpatialHrtfTab(
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
          _buildSpatialSupportBanner(context, state, p),
          const SizedBox(height: AppSpacing.s14),

          // Hardware Spatial Audio Card
          if (state.isSpatializerSupported) ...[
            _buildHardwareSpatializerCard(
                context, cubit, state, p, dspBlocked, spatializerAvailable),
            const SizedBox(height: AppSpacing.md),
          ],

          // Stereo Soundstage Expansion (Virtualizer)
          _buildVirtualizerCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.md),

          // Headphone Crossfeed (Chu Moy / Linkwitz-Riley / BS2B)
          _buildCrossfeedCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.md),

          // HRTF 3D Binaural Spatializer
          HrtfBinauralCard(
            blockedReason: dspBlocked,
            nativeAvailable: _nativePcmEffectsAvailable,
          ),
          const SizedBox(height: AppSpacing.md),

          // Stereo Width (Mid/Side & Multiband)
          _buildStereoWidthCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: AppSpacing.md),

          // Stereo Balance & Mono Mix
          _buildStereoBalanceCard(context, cubit, state, p, dspBlocked),
          const SizedBox(height: AppSpacing.md),

          // Convolution Reverb & Room Acoustics
          _buildReverbCard(context, cubit, state, p, dspBlocked),
        ],
      ),
    );
  }

  Widget _buildSpatialSupportBanner(
      BuildContext context, PlayerState state, PulsrPalette p) {
    return Container(
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
            color: state.isSpatializerSupported ? p.accent : p.textSecondary,
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
                    color:
                        state.isSpatializerSupported ? p.accent : p.textPrimary,
                  ),
                ),
                Text(
                  state.isSpatializerSupported
                      ? context.l10n.spatialMultiChannelDesc
                      : context.l10n.spatialVirtualizerActiveDesc,
                  style: TextStyle(
                      fontSize: AppFontSize.caption, color: p.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareSpatializerCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
    bool spatializerAvailable,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppFontSize.caption, color: p.textTertiary),
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
                    conflictReason: dspBlocked),
              ),
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
                    fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildVirtualizerCard(
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
                    conflictReason: dspBlocked),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Switch.adaptive(
                value: dspBlocked == null && state.isVirtualizerEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !state.isVirtualizerSupported
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
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: AppSpacing.md),
          Opacity(
            opacity: dspBlocked != null
                ? 0.35
                : (state.isVirtualizerEnabled ? 1.0 : 0.35),
            child: _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.width,
              valueText: '${(state.virtualizerStrength * 100).round()}%',
              value: state.virtualizerStrength.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              defaultValue: 0.0,
              divisions: 20,
              enabled: dspBlocked == null &&
                  state.isVirtualizerEnabled &&
                  state.isVirtualizerSupported,
              onChanged: (val) => cubit.setVirtualizerStrength(val),
            ),
          ),
          _effectNotAppliedNotice('virtualizer', p),
        ],
      ),
    );
  }
}
