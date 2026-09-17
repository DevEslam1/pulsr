// lib/features/settings/presentation/widgets/playback_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/sponsorblock_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'settings_conflict_card.dart';
import 'headset_controls_section.dart';
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
          ? context.l10n.settingsResolvedCrossfade(crossfade.toStringAsFixed(1))
          : context.l10n.settingsResolvedGapless),
    ));
  }

  /// Curated playback section for Normal mode.
  Widget _buildNormal(BuildContext context) {
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
          onTap: () => SleepTimerSheet.show(context),
        ),
        settingsCardDivider(p),
        _switchTile(
          context,
          Icons.graphic_eq_rounded,
          context.l10n.gaplessPlayback,
          context.l10n.gaplessSubtitle,
          value: state.gaplessPlayback,
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
        SettingSliderRow(
          label: context.l10n.crossfade,
          value: state.crossfadeSeconds,
          min: 0,
          max: 12,
          divisions: 24,
          defaultValue: 0.0,
          formatValue: (v) => '${v.toStringAsFixed(1)}s',
          onChanged: cubit.setCrossfade,
        ),
        if (state.gaplessPlayback)
          SettingsConflictCard(
            reason: AudioConflicts.crossfadeBlockedByGapless(true)!,
            resolveLabel: state.crossfadeSeconds > 0.01
                ? context.l10n.settingsTurnOffGaplessEnableCrossfade
                : context.l10n.settingsTurnOffGapless,
            onResolve: () => _resolveCrossfadeConflict(
                context, cubit, state.crossfadeSeconds),
          ),
        settingsCardDivider(p),
        _switchTile(
          context,
          Icons.volume_down_outlined,
          context.l10n.settingsDuckOnNavigation,
          context.l10n.settingsDuckOnNavigationSubtitle,
          value: state.duckingMode == 'duck',
          onChanged: (v) => cubit.setDuckingMode(v ? 'duck' : 'pause'),
        ),
        settingsCardDivider(p),
        settingsCardDivider(p),
        const _AudioNormalizationSettingTile(),
        settingsCardDivider(p),
        const _PlaybackPresetsTile(),
        settingsCardDivider(p),
        const HeadsetControlsSection(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Normal mode: the playback essentials only. Streaming-engine tuning,
    // SponsorBlock, multi-output and calibration stay in Professional mode.
    if (!state.isProfessional) return _buildNormal(context);
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
          onTap: () => SleepTimerSheet.show(context),
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
                ? context.l10n.settingsTurnOffGaplessEnableCrossfade
                : context.l10n.settingsTurnOffGapless,
            onResolve: () =>
                _resolveCrossfadeConflict(context, cubit, state.crossfadeSeconds),
          ),
        settingsCardDivider(p),
        // F3: hedged stream resolution (race 2 clients, take first).
        _switchTile(
          context,
          Icons.bolt_outlined,
          context.l10n.settingsHedgedStreaming,
          context.l10n.settingsHedgedStreamingSubtitle,
          value: state.hedgedResolutionEnabled,
          onChanged: cubit.setHedgedResolutionEnabled,
        ),
        settingsCardDivider(p),
        // F4: adaptive quality mid-track.
        _switchTile(
          context,
          Icons.auto_graph_outlined,
          context.l10n.settingsAdaptiveQuality,
          context.l10n.settingsAdaptiveQualitySubtitle,
          value: state.adaptiveQualityEnabled,
          onChanged: cubit.setAdaptiveQualityEnabled,
        ),
        settingsCardDivider(p),
        // F10: silence-skip sensitivity slider (0 = off).
        SettingSliderRow(
          label: context.l10n.settingsSilenceSkipSensitivity,
          value: state.silenceSkipSensitivity.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          defaultValue: 0.0,
          formatValue: (v) =>
              v < 0.5 ? context.l10n.rgOff : '${v.round()}%',
          onChanged: (v) => cubit.setSilenceSkipSensitivity(v.round()),
        ),
        settingsCardDivider(p),
        // F7: ducking control.
        _switchTile(
          context,
          Icons.volume_down_outlined,
          context.l10n.settingsDuckOnNavigation,
          context.l10n.settingsDuckOnNavigationSubtitle,
          value: state.duckingMode == 'duck',
          onChanged: (v) => cubit.setDuckingMode(v ? 'duck' : 'pause'),
        ),
        SettingSliderRow(
          label: context.l10n.settingsDuckLevel,
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
          context.l10n.settingsSpeakerBluetooth,
          context.l10n.settingsSpeakerBluetoothSubtitle,
          value: state.multiOutputMode == 'speakerAndBluetooth',
          onChanged: (v) => cubit.setMultiOutputMode(
              v ? 'speakerAndBluetooth' : 'systemDefault'),
        ),
        settingsCardDivider(p),
        // F9: per-album DSP snapshots.
        _switchTile(
          context,
          Icons.save_as_outlined,
          context.l10n.settingsPerAlbumEqMemory,
          context.l10n.settingsPerAlbumEqMemorySubtitle,
          value: state.dspSnapshotEnabled,
          onChanged: cubit.setDspSnapshotEnabled,
        ),
        settingsCardDivider(p),
        // F5: BT latency auto-calibration.
        _navTile(
          context,
          Icons.bluetooth_searching_outlined,
          context.l10n.settingsCalibrateBtLatency,
          context.l10n.settingsCalibrateBtLatencySubtitle(state.bluetoothLatencyOffsetMs),
          onTap: () async {
            final ms = await cubit.autoCalibrateBluetoothLatency();
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(context.l10n.btCalibrated(ms)),
            ));
          },
        ),
        settingsCardDivider(p),
        // F-67: SponsorBlock auto-skip controls.
        const _SponsorBlockSettingTile(),
        settingsCardDivider(p),
        // F-26: extended 0.1x–8.0x speed range.
        const _AdvancedSpeedSettingTile(),
        settingsCardDivider(p),
        // F-27: manual loudness normalization.
        settingsCardDivider(p),
        const _AudioNormalizationSettingTile(),
        settingsCardDivider(p),
        const _PlaybackPresetsTile(),
        settingsCardDivider(p),
        const HeadsetControlsSection(),
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

/// F-67: SponsorBlock auto-skip enable switch plus category picker.
class _SponsorBlockSettingTile extends StatefulWidget {
  const _SponsorBlockSettingTile();

  @override
  State<_SponsorBlockSettingTile> createState() =>
      _SponsorBlockSettingTileState();
}

class _SponsorBlockSettingTileState extends State<_SponsorBlockSettingTile> {
  Map<String, String> _labels(BuildContext context) => {
    'sponsor': context.l10n.settingsSponsorLabel,
    'selfpromo': context.l10n.settingsSelfPromoLabel,
    'interaction': context.l10n.settingsInteractionLabel,
    'intro': context.l10n.settingsIntroLabel,
    'outro': context.l10n.settingsOutroLabel,
    'music_offtopic': context.l10n.settingsNonMusicLabel,
  };

  bool _enabled = true;
  Set<String> _categories = Set.of(SponsorBlockService.supportedCategories);

  SponsorBlockService get _service =>
      getIt.isRegistered<SponsorBlockService>()
          ? getIt<SponsorBlockService>()
          : SponsorBlockService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = _service;
    await service.loadPreferences();
    if (!mounted) return;
    setState(() {
      _enabled = service.isEnabled;
      _categories = service.enabledCategories.toSet();
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _service.setSkipEnabled(value);
  }

  Future<void> _openCategoryPicker() async {
    final p = context.palette;
    final result = await PulsrSheetHelper.showPulsrSheet<Set<String>>(
      context: context,
      builder: (sheetContext) {
        var selected = Set<String>.from(_categories);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(context.l10n.sponsorBlockCategoriesLabel,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...SponsorBlockService.supportedCategories.map(
                    (category) => CheckboxListTile(
                      dense: true,
                      activeColor: p.accent,
                      value: selected.contains(category),
                      title: Text(
                        _labels(context)[category] ?? category,
                        style: TextStyle(color: p.textPrimary, fontSize: 14),
                      ),
                      onChanged: (checked) {
                        setSheetState(() {
                          if (checked == true) {
                            selected.add(category);
                          } else {
                            selected.remove(category);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: p.accent),
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(selected),
                      child: Text(context.l10n.doneAction),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (result == null) return;
    await _service.setEnabledCategories(result);
    if (!mounted) return;
    setState(() => _categories = result);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categorySummary = SponsorBlockService.supportedCategories
        .where(_categories.contains)
        .map((c) => _labels(context)[c] ?? c)
        .join(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSwitchTile(
          Icons.fast_forward_rounded,
          context.l10n.settingsSponsorBlock,
          context.l10n.settingsSponsorBlockSubtitle,
          value: _enabled,
          onChanged: _setEnabled,
        ),
        settingsCardDivider(p),
        SettingsNavTile(
          Icons.category_outlined,
          context.l10n.settingsSkipCategories,
          categorySummary.isEmpty
              ? context.l10n.settingsNoneSelectedAutoSkip
              : categorySummary,
          onTap: _openCategoryPicker,
        ),
      ],
    );
  }
}

/// F-26: toggles the handler's advanced 0.1x–8.0x speed range.
class _AdvancedSpeedSettingTile extends StatefulWidget {
  const _AdvancedSpeedSettingTile();

  @override
  State<_AdvancedSpeedSettingTile> createState() =>
      _AdvancedSpeedSettingTileState();
}

class _AdvancedSpeedSettingTileState extends State<_AdvancedSpeedSettingTile> {
  bool _value = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(PrefsKeys.advancedPlaybackSpeed) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _value = value);
  }

  Future<void> _onChanged(bool value) async {
    setState(() => _value = value);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAdvancedSpeedEnabled(value);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PrefsKeys.advancedPlaybackSpeed, value);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSwitchTile(
      Icons.speed_rounded,
      context.l10n.settingsExtendedSpeedRange,
      context.l10n.settingsExtendedSpeedRangeSubtitle,
      value: _value,
      onChanged: _onChanged,
    );
  }
}

/// F-27: manual loudness normalization, bridged to PulsrAudioHandler.
class _AudioNormalizationSettingTile extends StatefulWidget {
  const _AudioNormalizationSettingTile();

  @override
  State<_AudioNormalizationSettingTile> createState() =>
      _AudioNormalizationSettingTileState();
}

class _AudioNormalizationSettingTileState
    extends State<_AudioNormalizationSettingTile> {
  bool _value = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool value = false;
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        value = getIt<PulsrAudioHandler>().isAudioNormalizationEnabled;
      }
      if (!value) {
        final prefs = await SharedPreferences.getInstance();
        value =
            prefs.getBool(PrefsKeys.audioNormalizationEnabled) ?? false;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _value = value);
  }

  Future<void> _onChanged(bool value) async {
    setState(() => _value = value);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>()
            .setAudioNormalizationEnabled(value);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PrefsKeys.audioNormalizationEnabled, value);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSwitchTile(
      Icons.volume_up_outlined,
      context.l10n.settingsAudioNormalization,
      context.l10n.settingsAudioNormalizationSubtitle,
      value: _value,
      onChanged: _onChanged,
    );
  }
}

/// One-tap playback presets: Maximum Quality (audiophile), Smooth Playback
/// (balanced), Poor Network (data saver). Previously defined on the cubit
/// with zero UI callers.
class _PlaybackPresetsTile extends StatelessWidget {
  const _PlaybackPresetsTile();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    Future<void> apply(
        Future<void> Function() fn, String label) async {
      try {
        await fn();
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('$label applied'),
            duration: const Duration(seconds: 2),
          ));
        }
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, color: p.textTertiary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Playback presets',
                      style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5)),
                  Text('One-tap tuning for quality, balance or data saving',
                      style: TextStyle(
                          color: p.textTertiary, fontSize: 12.5, height: 1.32)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => apply(
                  cubit.applyMaximumQualityPreset, 'Maximum Quality'),
              icon: const Icon(Icons.high_quality_rounded, size: 18),
              label: const Text('Max Quality'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  apply(cubit.applySmoothPlaybackPreset, 'Smooth Playback'),
              icon: const Icon(Icons.spa_rounded, size: 18),
              label: const Text('Smooth'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  apply(cubit.applyPoorNetworkPreset, 'Data Saver'),
              icon: const Icon(Icons.data_saver_on_rounded, size: 18),
              label: const Text('Data Saver'),
            ),
          ],
        ),
      ],
    );
  }
}
