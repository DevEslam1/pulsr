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
import 'package:flutter/services.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
          child: Text(
            state.crossfadeSeconds > 0.01
                ? 'Songs will blend over ${state.crossfadeSeconds.toStringAsFixed(1)} seconds'
                : 'Crossfade disabled (songs end naturally)',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: p.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
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
        const _AudioNormalizationSettingTile(),
        settingsCardDivider(p),
        const _PlaybackPresetsTile(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        state.isProfessional ? _buildProfessional(context) : _buildNormal(context),
        const HeadsetControlsSection(),
      ],
    );
  }

  /// Full playback control surface for Professional mode.
  Widget _buildProfessional(BuildContext context) {
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
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
          child: Text(
            state.crossfadeSeconds > 0.01
                ? 'Songs will blend over ${state.crossfadeSeconds.toStringAsFixed(1)} seconds'
                : 'Crossfade disabled (songs end naturally)',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: p.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
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
        const _AudioNormalizationSettingTile(),
        settingsCardDivider(p),
        const _PlaybackPresetsTile(),
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
  Set<String> _categories = {};
  bool _loadingCategories = true;

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
      _loadingCategories = false;
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
        final selected = Set<String>.from(_categories);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: AppSpacing.s14),
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(AppRadii.r2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Text(context.l10n.sponsorBlockCategoriesLabel,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.bodyLarge,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  ...SponsorBlockService.supportedCategories.map(
                    (category) => CheckboxListTile(
                      dense: true,
                      activeColor: p.accent,
                      value: selected.contains(category),
                      title: Text(
                        _labels(context)[category] ?? category,
                        style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
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
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
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
    final categorySummary = _loadingCategories
        ? '…'
        : SponsorBlockService.supportedCategories
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
/// (balanced), Poor Network (data saver).
class _PlaybackPresetsTile extends StatelessWidget {
  const _PlaybackPresetsTile();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final state = context.watch<SettingsCubit>().state;

    final isMaxQuality = state.bitPerfectOutput && state.gaplessPlayback;
    final isSmooth = !state.bitPerfectOutput &&
        (state.crossfadeSeconds - 4.0).abs() < 0.2;
    final isDataSaver = !state.gaplessPlayback &&
        state.crossfadeSeconds < 0.1 &&
        state.streamingQuality == YtmAudioQuality.low;

    Future<void> apply(Future<void> Function() fn, String label) async {
      try {
        await fn();
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('$label applied'),
            duration: const Duration(seconds: 2),
          ));
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to apply preset $label',
            error: e, stackTrace: st, category: 'PlaybackPresets');
        if (context.mounted) {
          PulsrToast.show(
            context,
            message: 'Failed to apply $label',
            isError: true,
          );
        }
      }
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SettingsIconBox(Icons.tune_rounded),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.playbackPresetsTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: AppFontSize.body,
                        letterSpacing: AppTracking.none,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      context.l10n.playbackPresetsSubtitle,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                        height: 1.32,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 310;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(
                      child: _PresetPill(
                        icon: Icons.high_quality_rounded,
                        label: context.l10n.playbackPresetMaxQuality,
                        isSelected: isMaxQuality,
                        onTap: () => apply(
                          cubit.applyMaximumQualityPreset,
                          context.l10n.playbackPresetMaxQuality,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _PresetPill(
                        icon: Icons.spa_rounded,
                        label: context.l10n.playbackPresetSmooth,
                        isSelected: isSmooth,
                        onTap: () => apply(
                          cubit.applySmoothPlaybackPreset,
                          context.l10n.playbackPresetSmooth,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _PresetPill(
                        icon: Icons.data_saver_on_rounded,
                        label: context.l10n.playbackPresetDataSaver,
                        isSelected: isDataSaver,
                        onTap: () => apply(
                          cubit.applyPoorNetworkPreset,
                          context.l10n.playbackPresetDataSaver,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _PresetPill(
                    icon: Icons.high_quality_rounded,
                    label: context.l10n.playbackPresetMaxQuality,
                    isSelected: isMaxQuality,
                    onTap: () => apply(
                      cubit.applyMaximumQualityPreset,
                      context.l10n.playbackPresetMaxQuality,
                    ),
                  ),
                  _PresetPill(
                    icon: Icons.spa_rounded,
                    label: context.l10n.playbackPresetSmooth,
                    isSelected: isSmooth,
                    onTap: () => apply(
                      cubit.applySmoothPlaybackPreset,
                      context.l10n.playbackPresetSmooth,
                    ),
                  ),
                  _PresetPill(
                    icon: Icons.data_saver_on_rounded,
                    label: context.l10n.playbackPresetDataSaver,
                    isSelected: isDataSaver,
                    onTap: () => apply(
                      cubit.applyPoorNetworkPreset,
                      context.l10n.playbackPresetDataSaver,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetPill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrPressable(
      pressedScale: 0.95,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: context.motionMs(180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.s10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? p.accent.withValues(alpha: 0.16)
              : p.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadii.r12),
          border: Border.all(
            color: isSelected ? p.accent : p.hairline,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? p.accent : p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? p.accent : p.textPrimary,
                  fontSize: AppFontSize.label,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: AppTracking.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
