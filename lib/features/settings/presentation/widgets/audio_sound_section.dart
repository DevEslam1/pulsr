// lib/features/settings/presentation/widgets/audio_sound_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/services/bluetooth_latency_calibrator.dart';
import '../../../../core/telemetry/audio_session_log.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/widgets/audio_quality_sheet.dart';
import '../../../player/presentation/widgets/equalizer_sheet.dart';
import '../../../player/presentation/widgets/dsp_inspector_sheet.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'battery_optimization_card.dart';
import 'bt_latency_tap_sheet.dart';
import 'cast_section.dart';
import 'room_correction_sheet.dart';
import 'settings_conflict_card.dart';
import 'settings_section.dart';
import 'settings_slider_row.dart';
import 'settings_tiles.dart';
import 'usb_dac_section.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';
part 'audio_sound_dop_selector.dart';
part 'audio_sound_subsections.dart';

/// Sound engine: equalizer, DSP engine, output device / bit-perfect,
/// ReplayGain and battery optimization for background audio.
class AudioSoundSection extends StatefulWidget {
  final SettingsState state;

  const AudioSoundSection({super.key, required this.state});

  @override
  State<AudioSoundSection> createState() => _AudioSoundSectionState();
}

class _AudioSoundSectionState extends State<AudioSoundSection> {
  // B-24: Read hasPcmDspPath in initState and re-read on didChangeDependencies
  bool _hasPcmDspPath = false;

  @override
  void initState() {
    super.initState();
    _hasPcmDspPath = AudioEffectsChannel().hasPcmDspPath;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasPcmDspPath = AudioEffectsChannel().hasPcmDspPath;
  }

  /// Resolves the ReplayGain ↔ Bit-Perfect-bypass conflict by disabling the
  /// bypass (keeps Bit-Perfect output ON, unlocks the ReplayGain controls).
  Future<void> _resolveReplayGainConflict(
      BuildContext context, SettingsCubit cubit) async {
    await cubit.setBypassDspOnBitPerfect(false);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content:
          Text(context.l10n.bpResolved),
    ));
  }

  Future<void> _autoCalibrateBluetoothLatency(
      BuildContext context, SettingsCubit cubit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final codec = widget.state.currentOutputDevice?.btCodecName;
    final result =
        await BluetoothLatencyCalibrator().calibrate(codecName: codec);
    await cubit.setBluetoothLatencyOffsetMs(result.offsetMs);
    messenger?.showSnackBar(SnackBar(
      content: Text(
        '${l10n.btCalibrated(result.offsetMs)}'
        '${codec != null && codec.isNotEmpty ? ' ($codec)' : ''}',
      ),
    ));
  }

  /// Curated sound section for Normal mode: what a non-technical listener needs
  /// and nothing else. Smart Audio (in Settings → Sound) runs the advanced
  /// pipeline automatically.
  Widget _buildNormal(BuildContext context) {
    final p = context.palette;
    final device = widget.state.currentOutputDevice;
    final deviceLabel = device == null
        ? context.l10n.settingsConnectedDeviceQuality
        : '${device.deviceName}  •  '
            '${(device.sampleRate ~/ 1000)} kHz / ${device.bitDepth}-bit'
            '${device.isBluetooth ? '  •  Bluetooth' : ''}';
    return SettingsSection(
      icon: Icons.graphic_eq_rounded,
      title: context.l10n.audioAndSound,
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
          Icons.speaker_rounded,
          context.l10n.settingsOutputAudioQuality,
          deviceLabel,
          onTap: () {
            final currentSong = context.read<PlayerCubit>().state.currentSong ??
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
        ),
        settingsCardDivider(p),
        const BatteryOptimizationCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.state.isProfessional
            ? _buildProfessional(context)
            : _buildNormal(context),
        const CastSection(),
      ],
    );
  }

  // B-25: Split _buildProfessional into 4 sub-widgets: _OutputSection, _DspSection, _GainSection, _DiagnosticSection wrapped in RepaintBoundary
  Widget _buildProfessional(BuildContext context) {
    final p = context.palette;
    return SettingsSection(
      icon: Icons.graphic_eq_rounded,
      title: context.l10n.audioAndSound,
      children: [
        RepaintBoundary(
          child: _OutputSection(
            state: widget.state,
            onShowDspPreference: _showDspPreferencePickerSheet,
          ),
        ),
        settingsCardDivider(p),
        RepaintBoundary(
          child: _DspSection(
            state: widget.state,
            hasPcmDspPath: _hasPcmDspPath,
          ),
        ),
        settingsCardDivider(p),
        RepaintBoundary(
          child: _GainSection(
            state: widget.state,
            onResolveReplayGainConflict: _resolveReplayGainConflict,
          ),
        ),
        settingsCardDivider(p),
        RepaintBoundary(
          child: _DiagnosticSection(
            state: widget.state,
            onCalibrateBt: _autoCalibrateBluetoothLatency,
            onExportLogs: _exportSessionLogs,
          ),
        ),
      ],
    );
  }

  /// Exports the per-session audio telemetry JSONL and hands it to the OS share
  /// sheet. Best-effort: a missing/failed export surfaces a message, never a throw.
  Future<void> _exportSessionLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Captured before async gaps (no context-across-gap).
    final noLogsText = context.l10n.noSessionLogs;
    final exportFailedText = context.l10n.exportFailed;
    final shareText = context.l10n.settingsSessionLogsShareText;
    try {
      final file = await AudioSessionLog.instance.exportToFile();
      if (file == null || await file.length() == 0) {
        messenger?.showSnackBar(SnackBar(content: Text(noLogsText),
        ));
        return;
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/x-ndjson')],
        text: shareText,
      ));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(exportFailedText)),
      );
    }
  }

  void _showDspPreferencePickerSheet(
      BuildContext context, SettingsCubit cubit, String currentPref) {
    final p = context.palette;
    final options = [
      ('native', context.l10n.dspEngineNative, context.l10n.settingsDspNativeDesc),
      ('oem', context.l10n.dspEngineOem, context.l10n.settingsDspOemDesc),
      ('auto', context.l10n.dspEngineAuto, context.l10n.settingsDspAutoDesc),
    ];

    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.dspEnginePreference,
                style: const TextStyle(fontSize: AppFontSize.title, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              ...options.map((opt) {
                final isSelected = currentPref == opt.$1;
                return ListTile(
                  title: Text(opt.$2,
                      style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.normal)),
                  subtitle: Text(opt.$3,
                      style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: p.accent)
                      : null,
                  onTap: () {
                    cubit.setDspPreference(opt.$1);
                    Navigator.pop(sheetContext);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

