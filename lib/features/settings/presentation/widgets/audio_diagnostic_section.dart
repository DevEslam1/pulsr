part of 'audio_sound_section.dart';

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
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bluetooth_audio_rounded,
                      size: 20, color: p.accent),
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
                    ? context.l10n.bluetoothLatencySubtitle(
                        state.bluetoothLatencyOffsetMs)
                    : unsupported,
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.label),
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
