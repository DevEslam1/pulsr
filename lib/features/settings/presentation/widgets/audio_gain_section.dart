part of 'audio_sound_section.dart';

/// B-25 Sub-widget 3: ReplayGain and gain/volume control (DVC, resampler).
class _GainSection extends StatelessWidget {
  final SettingsState state;
  final Future<void> Function(BuildContext, SettingsCubit)
      onResolveReplayGainConflict;

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
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
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
                                child: Text(
                                  context.l10n.replayGainTitle,
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
                              color:
                                  rgBlocked != null ? p.error : p.textSecondary,
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
                      resolveLabel:
                          context.l10n.settingsDisableBitPerfectBypass,
                      onResolve: () =>
                          onResolveReplayGainConflict(context, cubit),
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
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.track,
                        label: Text(context.l10n.rgTrack,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.album,
                        label: Text(context.l10n.rgAlbum,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.auto,
                        label: Text(context.l10n.rgAuto,
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700)),
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
