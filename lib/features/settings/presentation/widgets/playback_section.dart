// lib/features/settings/presentation/widgets/playback_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import 'settings_conflict_card.dart';
import 'settings_section.dart';
import 'settings_slider_row.dart';
import 'settings_tiles.dart';

/// Playback behavior: sleep timer, gapless, crossfade, resume, waveform seek.
class PlaybackSection extends StatelessWidget {
  final SettingsState state;

  const PlaybackSection({super.key, required this.state});

  Future<void> _resolveCrossfadeConflict(
      BuildContext context, SettingsCubit cubit, double crossfade) async {
    await cubit.setGapless(false);
    if (crossfade > 0.01) {
      await cubit.setCrossfade(crossfade);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(crossfade > 0.01
          ? 'Resolved: Gapless off — Crossfade set to ${crossfade.toStringAsFixed(1)}s'
          : 'Resolved: Gapless disabled'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    return SettingsSection(
      icon: Icons.play_circle_outline_rounded,
      title: context.l10n.playback,
      children: [
        _navTile(
          context,
          Icons.timer_outlined,
          context.l10n.sleepTimer,
          context.l10n.sleepTimerSubtitle,
          onTap: () => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const SleepTimerSheet()),
        ),
        settingsCardDivider(p),
        _switchTile(
          context,
          Icons.graphic_eq_rounded,
          context.l10n.gaplessPlayback,
          context.l10n.gaplessSubtitle,
          value: state.gaplessPlayback,
          featureInfo: AudioFeatureRegistry.gapless,
          disabledReason: state.crossfadeSeconds > 0.01
              ? AudioConflicts.gaplessBlockedByCrossfade(state.crossfadeSeconds)
              : null,
          onChanged: cubit.setGapless,
        ),
        settingsCardDivider(p),
        _switchTile(
          context,
          Icons.play_circle_outline_rounded,
          context.l10n.resumeAfterInterruption,
          context.l10n.resumeAfterInterruptionSubtitle,
          value: state.resumeAfterInterruption,
          onChanged: cubit.setResumeAfterInterruption,
        ),
        settingsCardDivider(p),
        _switchTile(
          context,
          Icons.waves_rounded,
          context.l10n.waveformSeekBar,
          context.l10n.waveformSeekBarSubtitle,
          value: state.waveformSeekBarEnabled,
          onChanged: cubit.setWaveformSeekBar,
        ),
        settingsCardDivider(p),
        // Crossfade — default 0.0 s (SettingsState.crossfadeSeconds).
        SettingSliderRow(
          label: context.l10n.crossfade,
          value: state.crossfadeSeconds,
          min: 0,
          max: 12,
          divisions: 24,
          defaultValue: 0.0,
          formatValue: (v) => '${v.toStringAsFixed(1)}s',
          onInfo: () => showAudioFeatureInfoDialog(context,
              AudioFeatureRegistry.crossfade,
              conflictReason: state.gaplessPlayback
                  ? AudioConflicts.crossfadeBlockedByGapless(
                      state.gaplessPlayback)
                  : null),
          onChanged: cubit.setCrossfade,
        ),
        if (state.gaplessPlayback)
          SettingsConflictCard(
            reason: AudioConflicts.crossfadeBlockedByGapless(true)!,
            resolveLabel: state.crossfadeSeconds > 0.01
                ? 'Turn off Gapless & enable Crossfade'
                : 'Turn off Gapless',
            onResolve: () =>
                _resolveCrossfadeConflict(context, cubit, state.crossfadeSeconds),
          ),
        settingsCardDivider(p),
        // F3: hedged stream resolution (race 2 clients, take first).
        _switchTile(
          context,
          Icons.bolt_outlined,
          'Hedged streaming',
          'Race two resolvers, take the fastest URL',
          value: state.hedgedResolutionEnabled,
          onChanged: cubit.setHedgedResolutionEnabled,
        ),
        settingsCardDivider(p),
        // F4: adaptive quality mid-track.
        _switchTile(
          context,
          Icons.auto_graph_outlined,
          'Adaptive quality',
          'Step bitrate down/up mid-track on stalls',
          value: state.adaptiveQualityEnabled,
          onChanged: cubit.setAdaptiveQualityEnabled,
        ),
        settingsCardDivider(p),
        // F10: silence-skip sensitivity slider (0 = off).
        SettingSliderRow(
          label: 'Silence-skip sensitivity',
          value: state.silenceSkipSensitivity.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          defaultValue: 0.0,
          formatValue: (v) =>
              v < 0.5 ? 'Off' : '${v.round()}%',
          onChanged: (v) => cubit.setSilenceSkipSensitivity(v.round()),
        ),
        settingsCardDivider(p),
        // F7: ducking control.
        _switchTile(
          context,
          Icons.volume_down_outlined,
          'Duck on navigation',
          'Lower music instead of pausing for prompts',
          value: state.duckingMode == 'duck',
          onChanged: (v) => cubit.setDuckingMode(v ? 'duck' : 'pause'),
        ),
        SettingSliderRow(
          label: 'Duck level',
          value: state.duckingLevel,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          defaultValue: 0.3,
          formatValue: (v) => '${(v * 100).round()}%',
          onChanged: cubit.setDuckingLevel,
        ),
        settingsCardDivider(p),
        // F8: multi-output routing.
        _switchTile(
          context,
          Icons.speaker_group_outlined,
          'Speaker + Bluetooth',
          'Best-effort simultaneous output (falls back gracefully)',
          value: state.multiOutputMode == 'speakerAndBluetooth',
          onChanged: (v) => cubit.setMultiOutputMode(
              v ? 'speakerAndBluetooth' : 'systemDefault'),
        ),
        settingsCardDivider(p),
        // F9: per-album DSP snapshots.
        _switchTile(
          context,
          Icons.save_as_outlined,
          'Per-album EQ memory',
          'Restore EQ snapshot per album/artist',
          value: state.dspSnapshotEnabled,
          onChanged: cubit.setDspSnapshotEnabled,
        ),
        settingsCardDivider(p),
        // F5: BT latency auto-calibration.
        _navTile(
          context,
          Icons.bluetooth_searching_outlined,
          'Calibrate Bluetooth latency',
          'Auto-probe offset (currently ${state.bluetoothLatencyOffsetMs} ms)',
          onTap: () async {
            final ms = await cubit.autoCalibrateBluetoothLatency();
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Bluetooth latency calibrated: $ms ms'),
            ));
          },
        ),
      ],
    );
  }

  Widget _navTile(BuildContext context, IconData icon, String title,
          String subtitle,
          {Widget? trailing, VoidCallback? onTap}) =>
      SettingsNavTile(icon, title, subtitle,
          trailing: trailing, onTap: onTap);

  Widget _switchTile(BuildContext context, IconData icon, String title,
          String subtitle,
          {required bool value,
          required ValueChanged<bool> onChanged,
          AudioFeatureInfo? featureInfo,
          String? disabledReason}) =>
      SettingsSwitchTile(icon, title, subtitle,
          value: value,
          onChanged: onChanged,
          featureInfo: featureInfo,
          disabledReason: disabledReason);
}
