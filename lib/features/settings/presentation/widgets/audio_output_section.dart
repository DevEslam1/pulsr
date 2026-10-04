part of 'audio_sound_section.dart';

/// Collapsible disclosure for rarely-used audiophile controls.
/// Reuses the animation pattern from [_WhatChangesExpander].
class _AdvancedDisclosure extends StatefulWidget {
  final List<Widget> children;

  const _AdvancedDisclosure({required this.children});

  @override
  State<_AdvancedDisclosure> createState() => _AdvancedDisclosureState();
}

class _AdvancedDisclosureState extends State<_AdvancedDisclosure>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PulsrMotion.standard,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: AppRadii.r12All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: AppRadii.r12All,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _expanded = !_expanded;
                  if (_expanded) {
                    _controller.forward();
                  } else {
                    _controller.reverse();
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.s10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: _expanded ? p.accent : p.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.settingsAdvancedAudioTitle,
                            style: TextStyle(
                              fontSize: AppFontSize.bodySmall,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          Text(
                            context.l10n.settingsAdvancedAudioDesc,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: context.motionMs(200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: _expanded ? p.accent : p.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              if (_controller.value == 0.0 && !_expanded) {
                return const SizedBox(width: double.infinity);
              }
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _animation.value,
                  child: child,
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: p.hairline),
                ...widget.children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Device-adaptive audio output section that branches dynamically based on
/// [state.currentOutputDevice]:
/// - USB DAC: Bit-perfect, strict bit-perfect, follow track rate, DSD/DoP,
///   hardware volume, exclusive claim.
/// - Bluetooth: Codec, latency calibration & offset, BT sample rate.
/// - Speaker / Built-in: EQ, loudness, battery optimization.
class DeviceAdaptiveOutputSection extends StatelessWidget {
  final SettingsState state;
  final void Function(BuildContext, SettingsCubit, String)? onShowDspPreference;

  const DeviceAdaptiveOutputSection({
    super.key,
    required this.state,
    this.onShowDspPreference,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;
    final dev = state.currentOutputDevice;
    final isUsbDac = dev?.isUsbDac == true || (dev == null && state.isProfessional);
    final isBluetooth = dev?.isBluetooth == true;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Prominent Output Device Summary Card
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
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
                    color: isUsbDac
                        ? p.warning.withValues(alpha: 0.5)
                        : isBluetooth
                            ? p.accent.withValues(alpha: 0.4)
                            : p.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isUsbDac
                              ? Icons.usb_rounded
                              : isBluetooth
                                  ? Icons.bluetooth_audio_rounded
                                  : Icons.speaker_rounded,
                          color: isUsbDac
                              ? p.warning
                              : p.accent,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            dev?.deviceName ??
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
                        if (dev?.isBitPerfectActive == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: AppColors.dacGold.withValues(alpha: 0.15),
                              borderRadius: AppRadii.r6All,
                              border: Border.all(
                                  color: AppColors.dacGold
                                      .withValues(alpha: 0.6)),
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
                          (dev?.sampleRate ?? 44100) ~/ 1000,
                          dev?.bitDepth ?? 16),
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

        // 2. Branching device-specific controls
        if (isUsbDac) ...[
          // ════════════ USB DAC BRANCH ════════════
          Builder(builder: (ctx) {
            final bpBlock = !isAndroid
                ? unsupported
                : AudioConflicts.bitPerfectBlockedReason(dev);
            return Column(
              children: [
                if (bpBlock != null && isAndroid)
                  SettingsConflictCard(reason: bpBlock),
                SettingsSwitchTile(
                  Icons.album_rounded,
                  context.l10n.settingsBitPerfectUsb,
                  context.l10n.settingsBitPerfectUsbDesc,
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
          Builder(builder: (ctx) {
            final strictBlock = !isAndroid
                ? unsupported
                : AudioConflicts.strictBitPerfectBlockedReason(dev);
            return Column(
              children: [
                SettingsSwitchTile(
                  Icons.verified_rounded,
                  context.l10n.strictBitPerfectTitle,
                  context.l10n.strictBitPerfectSubtitle,
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
                          device: dev,
                        ) ??
                        context.l10n.strictBitPerfectActive,
                  ),
              ],
            );
          }),
          settingsCardDivider(p),
          SettingsSwitchTile(
            Icons.sync_rounded,
            context.l10n.followTrackSampleRateTitle,
            context.l10n.followTrackSampleRateSubtitle,
            value: isAndroid && state.followTrackSampleRate,
            featureInfo: AudioFeatureRegistry.followTrackSampleRate,
            disabledReason: isAndroid ? null : unsupported,
            onChanged: isAndroid ? cubit.setFollowTrackSampleRate : (v) {},
          ),
          settingsCardDivider(p),
          // DSD / DoP output selector
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
              ],
            ),
          ),
          settingsCardDivider(p),
          // Exclusive claim
          SettingsSwitchTile(
            Icons.lock_outline_rounded,
            'Exclusive Audio Claim',
            'Claim dedicated hardware mixer endpoint for zero interference',
            value: isAndroid && state.aaudioPreferExclusive,
            disabledReason: isAndroid ? null : unsupported,
            onChanged: isAndroid ? cubit.setAaudioPreferExclusive : (v) {},
          ),
          settingsCardDivider(p),
          UsbDacSection(cubit: cubit, state: state),
          // Rarely-used controls behind Advanced disclosure
          _AdvancedDisclosure(
            children: [
              SettingsSwitchTile(
                Icons.sync_alt_rounded,
                context.l10n.settingsPerTrackFormatNegotiation,
                context.l10n.settingsPerTrackFormatDesc,
                value: isAndroid && state.outputFormatNegotiationEnabled,
                disabledReason: isAndroid ? null : unsupported,
                onChanged: !isAndroid
                    ? (v) {}
                    : cubit.setOutputFormatNegotiationEnabled,
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
              if (isAndroid &&
                  state.dsdDopSupported &&
                  state.dsdOutputMode == DsdOutputMode.dop) ...[
                settingsCardDivider(p),
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: _DopContainerSelector(),
                ),
              ],
            ],
          ),
        ] else if (isBluetooth) ...[
          // ════════════ BLUETOOTH BRANCH ════════════
          SettingsNavTile(
            Icons.bluetooth_audio_rounded,
            'Bluetooth Codec',
            dev?.btCodecName ?? 'Standard Bluetooth Audio',
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.15),
                borderRadius: AppRadii.r4All,
              ),
              child: Text(
                dev?.btCodecName ?? 'BT',
                style: TextStyle(
                  color: p.accent,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            onTap: null,
          ),
          settingsCardDivider(p),
          SettingsNavTile(
            Icons.timer_outlined,
            context.l10n.settingsCalibrateBtLatency,
            context.l10n.settingsLatencyMs(state.bluetoothLatencyOffsetMs),
            trailing: Icon(Icons.touch_app_rounded,
                size: 20, color: p.accent),
            onTap: () => BtLatencyTapSheet.show(context),
          ),
          SettingSliderRow(
            label: context.l10n.bluetoothLatencyTitle,
            value: state.bluetoothLatencyOffsetMs.toDouble(),
            min: 0,
            max: 500,
            divisions: 50,
            defaultValue: 150,
            formatValue: (v) => '${v.round()} ms',
            onChanged: (v) => cubit.setBluetoothLatencyOffsetMs(v.round()),
          ),
          settingsCardDivider(p),
          SettingsSwitchTile(
            Icons.sync_rounded,
            context.l10n.followTrackSampleRateTitle,
            context.l10n.followTrackSampleRateBluetooth,
            value: isAndroid && state.followTrackSampleRate,
            featureInfo: AudioFeatureRegistry.followTrackSampleRate,
            disabledReason: isAndroid ? null : unsupported,
            onChanged: isAndroid ? cubit.setFollowTrackSampleRate : (v) {},
          ),
          // Advanced disclosure for Bluetooth
          _AdvancedDisclosure(
            children: [
              SettingsSwitchTile(
                Icons.sync_alt_rounded,
                context.l10n.settingsPerTrackFormatNegotiation,
                context.l10n.settingsPerTrackFormatDesc,
                value: isAndroid && state.outputFormatNegotiationEnabled,
                disabledReason: isAndroid ? null : unsupported,
                onChanged: !isAndroid
                    ? (v) {}
                    : cubit.setOutputFormatNegotiationEnabled,
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
            ],
          ),
        ] else ...[
          // ════════════ SPEAKER / BUILT-IN BRANCH ════════════
          SettingsNavTile(
            Icons.equalizer_rounded,
            context.l10n.equalizerAndSoundEffects,
            PlatformCapabilities.hasEqualizer
                ? context.l10n.equalizerSubtitle
                : unsupported,
            onTap: PlatformCapabilities.hasEqualizer
                ? () => EqualizerSheet.show(context)
                : null,
          ),
          settingsCardDivider(p),
          if (onShowDspPreference != null) ...[
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
                  ? () => onShowDspPreference!(
                      context, cubit, state.dspPreference)
                  : null,
            ),
            settingsCardDivider(p),
          ],
          const BatteryOptimizationCard(),
        ],
      ],
    );
  }
}
