part of 'audio_sound_section.dart';

/// B-25 Sub-widget 1: Audio hardware output, DAC, sample rate, bit-perfect, AAudio.
class _OutputSection extends StatelessWidget {
  final SettingsState state;
  final void Function(BuildContext, SettingsCubit, String) onShowDspPreference;

  const _OutputSection({
    required this.state,
    required this.onShowDspPreference,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsNavTile(
          Icons.equalizer_rounded,
          context.l10n.equalizerAndSoundEffects,
          PlatformCapabilities.hasEqualizer
              ? context.l10n.equalizerSubtitle
              : context.l10n.settingsNotAvailablePlatform,
          onTap: PlatformCapabilities.hasEqualizer
              ? () => EqualizerSheet.show(context)
              : null,
        ),
        settingsCardDivider(p),
        SettingsNavTile(
          Icons.settings_input_composite_rounded,
          context.l10n.dspEnginePreference,
          isAndroid
              ? switch (state.dspPreference) {
                  'oem' => context.l10n.dspEngineOem,
                  'auto' => context.l10n.dspEngineAuto,
                  _ => context.l10n.dspEngineNative,
                }
              : unsupported,
          disabledReason: isAndroid ? null : unsupported,
          onTap: isAndroid
              ? () => onShowDspPreference(context, cubit, state.dspPreference)
              : null,
        ),
        settingsCardDivider(p),
        // Audiophile & Hi-Res Output Card & Controls
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.s6),
          child: Material(
            color: p.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadii.r14),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.r14),
              onTap: () {
                final playerState = context.read<PlayerCubit>().state;
                final currentSong = playerState.currentSong ??
                    SongsTableData(
                      id: 0,
                      title: context.l10n.settingsHardwareAudioOutput,
                      artist: context.l10n.settingsMasterAudioEngine,
                      album: context.l10n.settingsInternalUsbDac,
                      durationMs: 0,
                      path: '',
                      source: SongSource.local,
                      isFavorite: false,
                      isMissing: false,
                      isDownloaded: false,
                      playCount: 0,
                      lastPositionMs: 0,
                    );
                AudioQualitySheet.show(context, currentSong, p.accent);
              },
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.r14),
                  border: Border.all(
                    color: state.currentOutputDevice?.isUsbDac == true
                        ? p.warning.withValues(alpha: 0.5)
                        : p.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.currentOutputDevice?.isUsbDac == true
                              ? Icons.usb_rounded
                              : Icons.headphones_rounded,
                          color: state.currentOutputDevice?.isUsbDac == true
                              ? p.warning
                              : p.accent,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            state.currentOutputDevice?.deviceName ??
                                context.l10n.settingsAudioOutputDevice,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: AppFontSize.bodySmall,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (state.currentOutputDevice?.isBitPerfectActive == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: AppColors.dacGold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppRadii.r6),
                              border: Border.all(
                                  color: AppColors.dacGold.withValues(alpha: 0.6)),
                            ),
                            child: Text(context.l10n.bitPerfectLabel,
                              style: TextStyle(
                                color: p.warning,
                                fontWeight: FontWeight.w900,
                                fontSize: AppFontSize.micro,
                                letterSpacing: AppTracking.medium,
                              ),
                            ),
                          ),
                        const SizedBox(width: AppSpacing.s6),
                        Icon(Icons.tune_rounded, size: 16, color: p.textSecondary),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.settingsOutputDeviceConfigHint(
                          (state.currentOutputDevice?.sampleRate ?? 44100) ~/ 1000,
                          state.currentOutputDevice?.bitDepth ?? 16),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Builder(builder: (ctx) {
          final bpBlock = !isAndroid
              ? unsupported
              : AudioConflicts.bitPerfectBlockedReason(state.currentOutputDevice);
          return Column(
            children: [
              if (bpBlock != null && isAndroid)
                SettingsConflictCard(reason: bpBlock),
              SettingsSwitchTile(
                Icons.album_rounded,
                context.l10n.settingsBitPerfectUsb,
                !isAndroid
                    ? unsupported
                    : state.currentOutputDevice?.isBluetooth == true
                        ? context.l10n.settingsBitPerfectBtUnavailable
                        : context.l10n.settingsBitPerfectUsbDesc,
                value: isAndroid && state.bitPerfectOutput,
                featureInfo: AudioFeatureRegistry.bitPerfect,
                disabledReason: bpBlock,
                onChanged: bpBlock != null ? (v) {} : cubit.setBitPerfectOutput,
              ),
            ],
          );
        }),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.tune_rounded,
          context.l10n.settingsBypassDspBitPerfect,
          context.l10n.settingsBypassDspBitPerfectDesc,
          value: isAndroid && state.bitPerfectOutput && state.bypassDspOnBitPerfect,
          featureInfo: AudioFeatureRegistry.bypassDsp,
          disabledReason: !isAndroid
              ? unsupported
              : !state.bitPerfectOutput
                  ? context.l10n.settingsEnableBitPerfectFirst
                  : null,
          onChanged: !isAndroid || !state.bitPerfectOutput
              ? (v) {}
              : cubit.setBypassDspOnBitPerfect,
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.sync_rounded,
          context.l10n.followTrackSampleRateTitle,
          !isAndroid
              ? unsupported
              : state.currentOutputDevice?.isBluetooth == true
                  ? context.l10n.followTrackSampleRateBluetooth
                  : context.l10n.followTrackSampleRateSubtitle,
          value: isAndroid && state.followTrackSampleRate,
          featureInfo: AudioFeatureRegistry.followTrackSampleRate,
          disabledReason: isAndroid ? null : unsupported,
          onChanged: isAndroid ? cubit.setFollowTrackSampleRate : (v) {},
        ),
        settingsCardDivider(p),
        Builder(builder: (ctx) {
          final strictBlock = !isAndroid
              ? unsupported
              : AudioConflicts.strictBitPerfectBlockedReason(state.currentOutputDevice);
          return Column(
            children: [
              SettingsSwitchTile(
                Icons.verified_rounded,
                context.l10n.strictBitPerfectTitle,
                !isAndroid
                    ? unsupported
                    : state.currentOutputDevice?.isBluetooth == true
                        ? context.l10n.strictBitPerfectBluetooth
                        : context.l10n.strictBitPerfectSubtitle,
                value: isAndroid && state.strictBitPerfect,
                featureInfo: AudioFeatureRegistry.strictBitPerfect,
                disabledReason: state.strictBitPerfect ? null : strictBlock,
                onChanged: cubit.setStrictBitPerfect,
              ),
              if (state.strictBitPerfect)
                SettingsConflictCard(
                  reason: AudioConflicts.strictBitPerfectActiveReason(
                        bitPerfectOutput: state.bitPerfectOutput,
                        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                        device: state.currentOutputDevice,
                      ) ??
                      context.l10n.strictBitPerfectActive,
                ),
            ],
          );
        }),
        settingsCardDivider(p),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.album_rounded,
                    size: 20,
                    color: (!isAndroid || !state.dsdDopSupported)
                        ? p.textTertiary
                        : p.accent,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Text(
                      context.l10n.dsdOutputModeTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline_rounded, size: 18, color: p.textTertiary),
                    tooltip: context.l10n.settingsAboutTitle(context.l10n.dsdOutputModeTitle),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showAudioFeatureInfoDialog(
                      context,
                      AudioFeatureRegistry.dsdNative,
                      conflictReason: !isAndroid
                          ? unsupported
                          : state.dsdDopSupported
                              ? null
                              : context.l10n.dsdDopRequiresUsbDac,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                !isAndroid
                    ? unsupported
                    : state.dsdDopSupported
                        ? context.l10n.dsdOutputModeSubtitle
                        : context.l10n.dsdDopRequiresUsbDac,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<DsdOutputMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: DsdOutputMode.pcm,
                      label: Text(
                        context.l10n.dsdOutputPcm,
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: DsdOutputMode.dop,
                      label: Text(
                        context.l10n.dsdOutputDop,
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  selected: {state.dsdOutputMode},
                  onSelectionChanged: (!isAndroid || !state.dsdDopSupported)
                      ? null
                      : (selected) {
                          if (selected.isNotEmpty) {
                            cubit.setDsdOutputMode(selected.first);
                          }
                        },
                ),
              ),
              if (isAndroid &&
                  state.dsdDopSupported &&
                  state.dsdOutputMode == DsdOutputMode.dop) ...[
                const SizedBox(height: AppSpacing.xs),
                const _DopContainerSelector(),
              ],
            ],
          ),
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.sync_alt_rounded,
          context.l10n.settingsPerTrackFormatNegotiation,
          context.l10n.settingsPerTrackFormatDesc,
          value: isAndroid && state.outputFormatNegotiationEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged: !isAndroid ? (v) {} : cubit.setOutputFormatNegotiationEnabled,
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.graphic_eq_rounded,
          context.l10n.settingsFloatDspPath,
          context.l10n.settingsFloatDspDesc,
          value: isAndroid && state.floatOutputEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged: !isAndroid ? (v) {} : cubit.setFloatOutputEnabled,
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.surround_sound_rounded,
          context.l10n.settingsAaudioDirect,
          context.l10n.settingsAaudioDirectDesc,
          value: isAndroid && state.aaudioOutputEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged: !isAndroid ? (v) {} : cubit.setAaudioOutputEnabled,
        ),
        SettingSliderRow(
          label: context.l10n.settingsAaudioBufferSize,
          subtitle: context.l10n.settingsAaudioBufferSizeDesc,
          value: state.aaudioTargetBufferMs.toDouble(),
          min: 20,
          max: 500,
          divisions: 24,
          defaultValue: 150,
          formatValue: (v) => '${v.round()} ms',
          enabled: isAndroid && state.aaudioOutputEnabled,
          onChanged: (v) => cubit.setAaudioTargetBufferMs(v.round()),
        ),
        settingsCardDivider(p),
        UsbDacSection(cubit: cubit, state: state),
      ],
    );
  }
}

/// B-25 Sub-widget 2: DSP features, Room Correction, Inspector, Loudness Contour, System effects.
class _DspSection extends StatelessWidget {
  final SettingsState state;
  final bool hasPcmDspPath;

  const _DspSection({
    required this.state,
    required this.hasPcmDspPath,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAndroid ? () => RoomCorrectionSheet.show(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s10),
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 20,
                    color: isAndroid ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.rcTitle,
                                style: TextStyle(
                                  color: isAndroid ? p.textPrimary : p.textTertiary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.info_outline_rounded, size: 18, color: p.textTertiary),
                              tooltip: context.l10n.learnMore,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => showAudioFeatureInfoDialog(
                                context,
                                AudioFeatureRegistry.roomCorrection,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          isAndroid ? context.l10n.rcSubtitle : unsupported,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        ),
        settingsCardDivider(p),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAndroid ? () => DspInspectorSheet.show(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s10),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors_rounded,
                    size: 20,
                    color: isAndroid ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.dspInspectorDebug,
                          style: TextStyle(
                            color: isAndroid ? p.textPrimary : p.textTertiary,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.body,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          isAndroid ? context.l10n.settingsDspInspectorDesc : unsupported,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        ),
        settingsCardDivider(p),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.surround_sound_rounded, size: 20, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.systemEffectsTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                !isAndroid
                    ? unsupported
                    : switch (state.systemEffectsStatus) {
                        'bypassed' => context.l10n.systemEffectsSubtitleBypassed,
                        'active' => context.l10n.systemEffectsSubtitleActive,
                        'unsupportedDevice' => context.l10n.systemEffectsSubtitleUnsupported,
                        _ => context.l10n.settingsStatusLabel(state.systemEffectsStatus),
                      },
                style: TextStyle(
                  color: state.systemEffectsStatus == 'bypassed'
                      ? p.success
                      : p.textSecondary,
                  fontSize: AppFontSize.label,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: 'auto',
                      label: Text(context.l10n.systemEffectsAuto, style: const TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: 'tryDisable',
                      label: Text(context.l10n.systemEffectsTryDisable, style: const TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: 'leaveOn',
                      label: Text(context.l10n.systemEffectsLeaveOn, style: const TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  selected: {state.systemEffectsPolicy},
                  onSelectionChanged: isAndroid
                      ? (selected) {
                          if (selected.isNotEmpty) {
                            cubit.setSystemEffectsPolicy(selected.first);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        settingsCardDivider(p),
        // Loudness Contour (Fletcher–Munson) — B-24: uses cached hasPcmDspPath
        BlocBuilder<PlayerCubit, PlayerState>(
          buildWhen: (prev, curr) =>
              prev.isLoudnessContourEnabled != curr.isLoudnessContourEnabled ||
              prev.loudnessContourIntensity != curr.loudnessContourIntensity,
          builder: (context, playerState) {
            final l10n = context.l10n;
            final playerCubit = context.read<PlayerCubit>();
            final isLoudnessContourEnabled = playerState.isLoudnessContourEnabled;
            final loudnessContourIntensity = playerState.loudnessContourIntensity;
            final lcBlocked = AudioConflicts.dspBlockedByBitPerfect(
              bitPerfectOutput: state.bitPerfectOutput,
              bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
              device: state.currentOutputDevice,
            );
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          color: lcBlocked != null ? p.textTertiary : p.accent,
                          size: 20),
                      const SizedBox(width: AppSpacing.s10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.dspLoudnessTitle,
                                    style: TextStyle(
                                      color: lcBlocked != null
                                          ? p.textTertiary
                                          : p.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      size: 18, color: p.textTertiary),
                                  tooltip: context.l10n.learnMore,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => showAudioFeatureInfoDialog(
                                      context, AudioFeatureRegistry.loudnessContour,
                                      conflictReason: lcBlocked),
                                ),
                              ],
                            ),
                            Text(
                              lcBlocked ?? l10n.dspLoudnessSubtitle,
                              style: TextStyle(
                                color: lcBlocked != null ? p.error : p.textSecondary,
                                fontSize: AppFontSize.label,
                                fontWeight: lcBlocked != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: isLoudnessContourEnabled,
                        activeTrackColor: p.accent,
                        activeThumbColor: p.onAccent,
                        onChanged: lcBlocked != null || !hasPcmDspPath
                            ? null
                            : (val) => playerCubit.setLoudnessContour(val),
                      ),
                    ],
                  ),
                  if (lcBlocked == null &&
                      hasPcmDspPath &&
                      isLoudnessContourEnabled) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    SettingSliderRow(
                      label: l10n.dspLoudnessIntensity,
                      value: loudnessContourIntensity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      defaultValue: 0.0,
                      formatValue: (v) => '${(v * 100).round()}%',
                      onChanged: (v) =>
                          playerCubit.setLoudnessContour(true, intensity: v),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      l10n.dspLoudnessReplayGainNote,
                      style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// B-25 Sub-widget 3: ReplayGain and gain/volume control (DVC, resampler).
class _GainSection extends StatelessWidget {
  final SettingsState state;
  final Future<void> Function(BuildContext, SettingsCubit) onResolveReplayGainConflict;

  const _GainSection({
    required this.state,
    required this.onResolveReplayGainConflict,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(builder: (cntx) {
          final rgBlocked = AudioConflicts.replayGainBlockedByBitPerfect(
            bitPerfectOutput: state.bitPerfectOutput,
            bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
            device: state.currentOutputDevice,
          );
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.volume_up_rounded,
                        color: rgBlocked != null ? p.textTertiary : p.accent,
                        size: 20),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(context.l10n.replayGainTitle,
                                  style: TextStyle(
                                    color: rgBlocked != null
                                        ? p.textTertiary
                                        : p.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.body,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    size: 18, color: p.textTertiary),
                                tooltip: context.l10n.learnMore,
                                visualDensity: VisualDensity.compact,
                                onPressed: () => showAudioFeatureInfoDialog(
                                    context, AudioFeatureRegistry.replayGain,
                                    conflictReason: rgBlocked),
                              ),
                            ],
                          ),
                          Text(
                            rgBlocked ?? context.l10n.settingsReplayGainDesc,
                            style: TextStyle(
                              color: rgBlocked != null ? p.error : p.textSecondary,
                              fontSize: AppFontSize.label,
                              fontWeight: rgBlocked != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (rgBlocked != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: SettingsConflictCard(
                      reason: rgBlocked,
                      resolveLabel: context.l10n.settingsDisableBitPerfectBypass,
                      onResolve: () => onResolveReplayGainConflict(context, cubit),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReplayGainMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                      ),
                    ),
                    segments: [
                      ButtonSegment(
                        value: ReplayGainMode.off,
                        label: Text(context.l10n.rgOff,
                            style: TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.track,
                        label: Text(context.l10n.rgTrack,
                            style: TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.album,
                        label: Text(context.l10n.rgAlbum,
                            style: TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.auto,
                        label: Text(context.l10n.rgAuto,
                            style: TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    selected: {state.replayGainMode},
                    onSelectionChanged: rgBlocked != null
                        ? null
                        : (selected) {
                            if (selected.isNotEmpty) {
                              cubit.setReplayGainMode(selected.first);
                            }
                          },
                  ),
                ),
                if (rgBlocked == null &&
                    state.replayGainMode != ReplayGainMode.off) ...[
                  SettingSliderRow(
                    label: context.l10n.settingsPreampWithRg,
                    value: state.replayGainPreampWithRg,
                    min: -12.0,
                    max: 12.0,
                    divisions: 48,
                    defaultValue: 0.0,
                    formatValue: (v) =>
                        '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
                    onChanged: cubit.setReplayGainPreampWithRg,
                  ),
                  SettingSliderRow(
                    label: context.l10n.settingsPreampWithoutRg,
                    value: state.replayGainPreampWithoutRg,
                    min: -12.0,
                    max: 12.0,
                    divisions: 48,
                    defaultValue: -3.0,
                    formatValue: (v) =>
                        '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
                    onChanged: cubit.setReplayGainPreampWithoutRg,
                  ),
                ],
              ],
            ),
          );
        }),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.volume_up_rounded,
          context.l10n.settingsDvcTitle,
          context.l10n.settingsDvcDesc,
          value: isAndroid &&
              state.dvcEnabled &&
              !state.aaudioOutputEnabled &&
              AudioConflicts.dspBlockedByBitPerfect(
                    bitPerfectOutput: state.bitPerfectOutput,
                    bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                    device: state.currentOutputDevice,
                  ) ==
                  null,
          disabledReason: !isAndroid
              ? unsupported
              : (state.aaudioOutputEnabled
                  ? context.l10n.settingsUnavailableAaudio
                  : AudioConflicts.dspBlockedByBitPerfect(
                      bitPerfectOutput: state.bitPerfectOutput,
                      bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                      device: state.currentOutputDevice,
                    )),
          onChanged: !isAndroid ||
                  state.aaudioOutputEnabled ||
                  AudioConflicts.dspBlockedByBitPerfect(
                        bitPerfectOutput: state.bitPerfectOutput,
                        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                        device: state.currentOutputDevice,
                      ) !=
                      null
              ? (v) {}
              : cubit.setDvcEnabled,
        ),
        settingsCardDivider(p),
        SettingSliderRow(
          label: context.l10n.settingsResamplerQuality,
          subtitle: context.l10n.settingsResamplerQualityDesc,
          value: state.sincResamplerQuality.toDouble(),
          min: 0,
          max: 3,
          divisions: 3,
          defaultValue: 3,
          formatValue: (v) {
            switch (v.round()) {
              case 0:
                return context.l10n.settingsResamplerFast;
              case 1:
                return context.l10n.settingsResamplerStandard;
              case 2:
                return context.l10n.settingsResamplerHigh;
              default:
                return context.l10n.settingsResamplerUltra;
            }
          },
          onChanged: (v) => cubit.setSincResamplerQuality(v.round()),
        ),
      ],
    );
  }
}

/// B-25 Sub-widget 4: Diagnostics, Bluetooth latency sync, session logging, battery.
class _DiagnosticSection extends StatelessWidget {
  final SettingsState state;
  final Future<void> Function(BuildContext, SettingsCubit) onCalibrateBt;
  final Future<void> Function(BuildContext) onExportLogs;

  const _DiagnosticSection({
    required this.state,
    required this.onCalibrateBt,
    required this.onExportLogs,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bluetooth_audio_rounded, size: 20, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.bluetoothLatencyTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                isAndroid
                    ? context.l10n.bluetoothLatencySubtitle(state.bluetoothLatencyOffsetMs)
                    : unsupported,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              const SizedBox(height: AppSpacing.s6),
              SettingSliderRow(
                label: context.l10n.settingsSyncOffset,
                value: state.bluetoothLatencyOffsetMs.toDouble(),
                enabled: isAndroid,
                min: 0.0,
                max: 400.0,
                divisions: 20,
                defaultValue: 150.0,
                formatValue: (v) => '${v.round()} ms',
                onChanged: (v) => cubit.setBluetoothLatencyOffsetMs(v.round()),
              ),
              if (isAndroid && state.currentOutputDevice?.isBluetooth == true)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => BtLatencyTapSheet.show(context),
                      icon: const Icon(Icons.fingerprint_rounded, size: 16),
                      label: Text(context.l10n.settingsSyncOffset),
                    ),
                    TextButton.icon(
                      onPressed: () => onCalibrateBt(context, cubit),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: Text(context.l10n.autoCalibrate),
                    ),
                  ],
                ),
            ],
          ),
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.music_note_rounded,
          context.l10n.settingsBpmSyncCrossfade,
          context.l10n.settingsBpmSyncCrossfadeDesc,
          value: state.bpmSyncCrossfadeEnabled,
          onChanged: cubit.setBpmSyncCrossfadeEnabled,
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.monitor_heart_rounded,
          context.l10n.settingsSessionDiagnostics,
          context.l10n.settingsSessionDiagnosticsDesc,
          value: state.sessionLogEnabled,
          onChanged: cubit.setSessionLogEnabled,
        ),
        SettingsNavTile(
          Icons.ios_share_rounded,
          context.l10n.settingsExportSessionLogs,
          context.l10n.settingsExportSessionLogsDesc,
          trailing: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
          onTap: () => onExportLogs(context),
        ),
        settingsCardDivider(p),
        SettingsNavTile(
          Icons.health_and_safety_rounded,
          'Headphone Safety & Sound Dose',
          'WHO-ITU H.870 acoustic exposure monitoring & safety limiter',
          trailing: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
          onTap: () => HeadphoneSafetySheet.show(context),
        ),
        const BatteryOptimizationCard(),
      ],
    );
  }
}
