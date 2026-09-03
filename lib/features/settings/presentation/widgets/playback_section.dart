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
    if (crossfade > 0.0) {
      await cubit.setCrossfade(crossfade);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(crossfade > 0.0
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
          disabledReason: null,
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
            resolveLabel: state.crossfadeSeconds > 0.0
                ? 'Turn off Gapless & enable Crossfade'
                : 'Turn off Gapless',
            onResolve: () =>
                _resolveCrossfadeConflict(context, cubit, state.crossfadeSeconds),
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
