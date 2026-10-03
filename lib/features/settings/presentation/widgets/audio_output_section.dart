part of 'audio_sound_section.dart';

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
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.s6),
          child: Material(
            color: p.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: AppRadii.r14All,
            child: InkWell(
              borderRadius: AppRadii.r14All,
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
                  borderRadius: AppRadii.r14All,
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
                        if (state.currentOutputDevice?.isBitPerfectActive ==
                            true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: AppColors.dacGold.withValues(alpha: 0.15),
                              borderRadius: AppRadii.r6All,
                              border: Border.all(
                                  color:
                                      AppColors.dacGold.withValues(alpha: 0.6)),
                            ),
                            child: Text(
                              context.l10n.bitPerfectLabel,
                              style: TextStyle(
                                color: p.warning,
                                fontWeight: FontWeight.w900,
                                fontSize: AppFontSize.micro,
                                letterSpacing: AppTracking.medium,
                              ),
                            ),
                          ),
                        const SizedBox(width: AppSpacing.s6),
                        Icon(Icons.tune_rounded,
                            size: 16, color: p.textSecondary),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.settingsOutputDeviceConfigHint(
                          (state.currentOutputDevice?.sampleRate ?? 44100) ~/
                              1000,
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
              : AudioConflicts.bitPerfectBlockedReason(
                  state.currentOutputDevice);
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
                onChanged: bpBlock != null
                    ? (v) {}
                    : (v) => requestBitPerfectOutput(ctx, v),
              ),
            ],
          );
        }),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.tune_rounded,
          context.l10n.settingsBypassDspBitPerfect,
          context.l10n.settingsBypassDspBitPerfectDesc,
          value: isAndroid &&
              state.bitPerfectOutput &&
              state.bypassDspOnBitPerfect,
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
              : AudioConflicts.strictBitPerfectBlockedReason(
                  state.currentOutputDevice);
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
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
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
                    icon: Icon(Icons.info_outline_rounded,
                        size: 18, color: p.textTertiary),
                    tooltip: context.l10n
                        .settingsAboutTitle(context.l10n.dsdOutputModeTitle),
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
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.label),
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
          onChanged:
              !isAndroid ? (v) {} : cubit.setOutputFormatNegotiationEnabled,
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
