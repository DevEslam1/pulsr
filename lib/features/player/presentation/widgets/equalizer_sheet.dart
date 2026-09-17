// lib/features/player/presentation/widgets/equalizer_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../../../domain/models/reverb_preset.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/utils/list_content_diff.dart';
import '../../cubit/player_state.dart';
import 'dart:async';

import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../data/audio/equalizer_manager.dart';
import 'eq_curve_visualizer.dart';
import 'autoeq_search_sheet.dart';
import 'compressor_limiter_sheet.dart';
import 'dsp_inspector_sheet.dart';
import 'viper_ddc_sheet.dart';
import 'arbitrary_eq_sheet.dart';
import 'live_prog_sheet.dart';
import 'audio_quality_sheet.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/presentation/widgets/room_correction_sheet.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_dialog.dart';

// Rebuild gate for the whole DSP sheet. Every user-facing toggle/slider field
// MUST be listed here or its switch will not flip until the sheet is reopened
// (state emits, engine applies, but BlocBuilder skips the rebuild).
// Position/playback fields stay excluded on purpose (10 Hz ticks).
bool dspSheetRebuildGate(PlayerState a, PlayerState b) {
  return a.isEqEnabled != b.isEqEnabled ||
      a.eqPreset.name != b.eqPreset.name ||
      a.eqPreset.gains.length != b.eqPreset.gains.length ||
      a.eqPreset.bassBoost != b.eqPreset.bassBoost ||
      a.isVirtualizerEnabled != b.isVirtualizerEnabled ||
      a.virtualizerStrength != b.virtualizerStrength ||
      a.isVirtualizerSupported != b.isVirtualizerSupported ||
      a.isDynamicsEnabled != b.isDynamicsEnabled ||
      a.isDynamicsSupported != b.isDynamicsSupported ||
      a.dynamicsPreset != b.dynamicsPreset ||
      a.selectedHeadphoneProfile != b.selectedHeadphoneProfile ||
      a.isSpatializerEnabled != b.isSpatializerEnabled ||
      a.isSpatializerSupported != b.isSpatializerSupported ||
      a.volumeBoost != b.volumeBoost ||
      a.isVolumeBoostSupported != b.isVolumeBoostSupported ||
      a.isBassBoostSupported != b.isBassBoostSupported ||
      a.stereoBalance != b.stereoBalance ||
      a.monoMix != b.monoMix ||
      a.isCrossfeedEnabled != b.isCrossfeedEnabled ||
      a.crossfeedDelayUs != b.crossfeedDelayUs ||
      a.crossfeedFeedDb != b.crossfeedFeedDb ||
      a.isLimiterEnabled != b.isLimiterEnabled ||
      a.limiterThresholdDb != b.limiterThresholdDb ||
      a.limiterReleaseMs != b.limiterReleaseMs ||
      a.isReverbEnabled != b.isReverbEnabled ||
      a.reverbPreset != b.reverbPreset ||
      a.reverbWetDry != b.reverbWetDry ||
      a.isSincResamplerEnabled != b.isSincResamplerEnabled ||
      a.isDitherEnabled != b.isDitherEnabled ||
      a.ditherTargetBitDepth != b.ditherTargetBitDepth ||
      a.hasOemAudio != b.hasOemAudio ||
      listContentDiffers(a.detectedOemEngines, b.detectedOemEngines) ||
      a.isSaturationEnabled != b.isSaturationEnabled ||
      a.saturationDrive != b.saturationDrive ||
      a.saturationMix != b.saturationMix ||
      a.saturationTilt != b.saturationTilt ||
      a.isStereoWidthEnabled != b.isStereoWidthEnabled ||
      a.stereoWidth != b.stereoWidth ||
      a.stereoWidthMultiband != b.stereoWidthMultiband ||
      a.stereoWidthLow != b.stereoWidthLow ||
      a.stereoWidthMid != b.stereoWidthMid ||
      a.stereoWidthHigh != b.stereoWidthHigh ||
      a.isLoudnessContourEnabled != b.isLoudnessContourEnabled ||
      a.loudnessContourIntensity != b.loudnessContourIntensity ||
      a.isSubCrossoverEnabled != b.isSubCrossoverEnabled ||
      a.subCrossoverCornerHz != b.subCrossoverCornerHz ||
      a.subCrossoverSlopeDbPerOct != b.subCrossoverSlopeDbPerOct ||
      a.subCrossoverGain != b.subCrossoverGain ||
      a.isDynamicEqEnabled != b.isDynamicEqEnabled ||
      listContentDiffers(a.dynamicEqBands, b.dynamicEqBands) ||
      a.crossfeedMode != b.crossfeedMode ||
      a.saturationMultiband != b.saturationMultiband ||
      a.isViperDdcEnabled != b.isViperDdcEnabled ||
      a.viperDdcProfileName != b.viperDdcProfileName ||
      a.isArbitraryEqEnabled != b.isArbitraryEqEnabled ||
      a.arbitraryEqString != b.arbitraryEqString ||
      a.isLiveProgEnabled != b.isLiveProgEnabled ||
      a.liveProgCode != b.liveProgCode ||
      a.isDynamicBassEnabled != b.isDynamicBassEnabled ||
      a.dynamicBassStrength != b.dynamicBassStrength ||
      a.dynamicBassPreset != b.dynamicBassPreset ||
      a.errorMessage != b.errorMessage;
}

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const EqualizerSheet(),
    );
  }

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final HeadphoneProfilesRepository _headphoneRepo =
      HeadphoneProfilesRepository();

  StreamSubscription<int>? _degradedSessionSub;
  bool _degradeSnackQueued = false;

  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoadingProfiles = true;
  bool _isAbComparing = false;
  bool? _isStudioModeOverride;

  bool _isStudio(BuildContext context) {
    if (_isStudioModeOverride != null) return _isStudioModeOverride!;
    try {
      final settings = context.read<SettingsCubit>().state;
      return settings.isProfessional;
    } catch (_) {
      return false;
    }
  }

  double _getBassGain(PlayerState state) {
    final gains = state.eqPreset.gains;
    if (gains.isEmpty) return 0.0;
    if (gains.length >= 3) {
      return ((gains[0] + gains[1] + gains[2]) / 3.0).clamp(-12.0, 12.0);
    }
    return gains.first.clamp(-12.0, 12.0);
  }

  double _getMidGain(PlayerState state) {
    final gains = state.eqPreset.gains;
    if (gains.length >= 7) {
      return ((gains[4] + gains[5] + gains[6]) / 3.0).clamp(-12.0, 12.0);
    } else if (gains.length >= 3) {
      return gains[gains.length ~/ 2].clamp(-12.0, 12.0);
    }
    return 0.0;
  }

  double _getTrebleGain(PlayerState state) {
    final gains = state.eqPreset.gains;
    if (gains.length >= 10) {
      return ((gains[7] + gains[8] + gains[9]) / 3.0).clamp(-12.0, 12.0);
    } else if (gains.length >= 3) {
      return gains.last.clamp(-12.0, 12.0);
    }
    return 0.0;
  }

  void _setBassMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final count = state.eqPreset.gains.length;
    if (count >= 10) {
      cubit.setBandGain(0, val);
      cubit.setBandGain(1, (val * 0.85).clamp(-12.0, 12.0));
      cubit.setBandGain(2, (val * 0.65).clamp(-12.0, 12.0));
    } else if (count > 0) {
      cubit.setBandGain(0, val);
    }
    if (val >= 0) {
      cubit.setBassBoost((val / 12.0).clamp(0.0, 1.0));
    }
  }

  void _setMidMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final count = state.eqPreset.gains.length;
    if (count >= 10) {
      cubit.setBandGain(3, (val * 0.5).clamp(-12.0, 12.0));
      cubit.setBandGain(4, (val * 0.8).clamp(-12.0, 12.0));
      cubit.setBandGain(5, val);
      cubit.setBandGain(6, (val * 0.85).clamp(-12.0, 12.0));
    } else if (count >= 3) {
      cubit.setBandGain(count ~/ 2, val);
    }
  }

  void _setTrebleMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final count = state.eqPreset.gains.length;
    if (count >= 10) {
      cubit.setBandGain(7, (val * 0.75).clamp(-12.0, 12.0));
      cubit.setBandGain(8, val);
      cubit.setBandGain(9, (val * 0.9).clamp(-12.0, 12.0));
    } else if (count >= 3) {
      cubit.setBandGain(count - 1, val);
    }
  }

  /// F-35: per-band solo/mute are push-to-native only (the engine exposes no
  /// getter), so the sheet owns the transient UI state. Cleared on a band-count
  /// switch because the indices then refer to a different frequency plan.
  final Set<int> _mutedBands = <int>{};
  final Set<int> _soloedBands = <int>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHeadphoneProfiles();
    _listenForDspAutoDegrade();
  }

  /// Surfaces the native DSP auto-degrade safety net: when the engine bypasses
  /// stages to prevent stutter, show ONE snack per degraded session (re-arms after
  /// full recovery) so the user understands why effects stopped.
  void _listenForDspAutoDegrade() {
    try {
      _degradedSessionSub =
          AudioEffectsChannel().onAutoDegradedSessionStarted.listen(
        (mask) {
          if (!mounted) return;
          _degradeSnackQueued = true;
          setState(() {});
        },
      );
    } catch (_) {}
  }

  Future<void> _loadHeadphoneProfiles() async {
    await _headphoneRepo.loadProfiles();
    if (mounted) {
      setState(() {
        _isLoadingProfiles = false;
      });
    }
  }

  @override
  void dispose() {
    _degradedSessionSub?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String? _dspBlockedReason(BuildContext context) {
    try {
      final settings = context.watch<SettingsCubit>().state;
      return AudioConflicts.dspBlockedByBitPerfect(
        bitPerfectOutput: settings.bitPerfectOutput,
        bypassDspOnBitPerfect: settings.bypassDspOnBitPerfect,
        device: settings.currentOutputDevice,
        aaudioEnabled: settings.aaudioOutputEnabled,
        dsdDopActive: AudioQualityInfo.dsdDopActive,
      );
    } catch (_) {
      return null;
    }
  }

  /// The C++ stages (crossfeed, saturation, stereo width, sub crossover,
  /// dynamic EQ, convolution reverb, mono/balance) exist only in libpulsr_dsp,
  /// so they need the native chain spliced into ExoPlayer's audio sink.
  /// HAL-backed stages (limiter, EQ, bass, virtualizer, volume boost) ignore
  /// this and stay available.
  bool get _nativePcmEffectsAvailable => AudioEffectsChannel().hasPcmDspPath;

  /// The spatializer toggle falls back to the hardware virtualizer on devices
  /// without a Spatializer API, so it is only reachable when at least one of
  /// the two exists. Shared by both tabs so their gating stays identical.
  bool _spatializerToggleAvailable(PlayerState state) =>
      state.isSpatializerSupported || state.isVirtualizerSupported;

  /// The EqualizerManager singleton, when DI has registered it. Widget tests
  /// that do not register it must not crash the sheet, so this is defensive.
  EqualizerManager? _equalizerManagerOrNull() {
    try {
      return getIt.isRegistered<EqualizerManager>()
          ? getIt<EqualizerManager>()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// F-32: active band plan length (10, 32 or 64). The manager is the source of
  /// truth; fall back to the emitted preset length when DI is not registered.
  int _activeBandCount(PlayerState state) {
    final manager = _equalizerManagerOrNull();
    if (manager != null) return manager.activeFrequencies.length;
    final n = state.eqPreset.gains.length;
    return (n == 32 || n == 64) ? n : 10;
  }

  /// F-32: center frequencies matching [_activeBandCount].
  List<double> _activeFrequencies(PlayerState state) {
    final manager = _equalizerManagerOrNull();
    if (manager != null) return manager.activeFrequencies;
    final n = state.eqPreset.gains.length;
    if (n == 64) return EqPreset.iso64Frequencies;
    if (n == 32) return EqPreset.iso32Frequencies;
    return EqPreset.centerFrequencies;
  }

  String _formatHz(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000.0;
      final s =
          k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${s}K';
    }
    return hz == hz.roundToDouble()
        ? hz.toStringAsFixed(0)
        : hz.toStringAsFixed(1);
  }

  /// Truthful native status: shown under an effect control when the engine
  /// reported it could not be applied (unsupported / build failure / no
  /// session), so an "on" control cannot silently mean "no audible effect".
  Widget _effectNotAppliedNotice(String effectKey, PulsrPalette p) {
    final manager = _equalizerManagerOrNull();
    if (manager == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: manager.effectStatusNotifier,
      builder: (context, status, _) {
        if (!status.containsKey(effectKey)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 13, color: p.error),
              const SizedBox(width: 5),
              Expanded(
                child: Text(context.l10n.notAppliedWarn,
                  style: TextStyle(
                    color: p.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFeatureInfo(BuildContext context, AudioFeatureInfo info,
      {String? conflictReason}) {
    final p = context.palette;
    PulsrDialogHelper.showPulsrDialog<void>(
      context,
      icon: Icon(Icons.info_outline_rounded, color: p.accent, size: 26),
      title: Text(info.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.subtitle,
                style: TextStyle(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            const SizedBox(height: 10),
            Text(info.description,
                style: TextStyle(
                    color: p.textPrimary, fontSize: 13, height: 1.4)),
            if (info.conflictsWith != null) ...[
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: p.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: p.warning.withValues(alpha: 0.4))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: p.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                context.l10n.conflictsWith(
                                    info.conflictsWith ?? ''),
                                style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)))
                      ])),
            ],
            if (conflictReason != null) ...[
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: p.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: p.error.withValues(alpha: 0.4))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.block_rounded, color: p.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(conflictReason,
                                style: TextStyle(
                                    color: p.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)))
                      ])),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(),
          child: Text(context.l10n.gotIt),
        ),
      ],
    );
  }

  Widget _conflictBanner(String reason, PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.error.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.block_rounded, color: p.error, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(reason,
                style: TextStyle(
                    color: p.error, fontSize: 11, fontWeight: FontWeight.w600)))
      ]),
    );
  }

  Future<void> _resetAllDspDefaults(
      BuildContext context, PlayerCubit cubit) async {
    await cubit.resetToFlat();
    await cubit.setBassBoost(0.0);
    await cubit.setVolumeBoost(0.0);
    await cubit.setVirtualizerEnabled(false);
    await cubit.setVirtualizerStrength(0.0);
    await cubit.setDynamicsPreset(DynamicsPreset.off);
    await cubit.setCrossfeed(false, delayUs: 350.0, feedDb: -9.0);
    await cubit.setLookaheadLimiter(false, thresholdDb: -0.2, releaseMs: 50.0);
    await cubit.setStereoBalance(0.0);
    await cubit.setReverb(false, preset: 0, wetDry: 0.20);
    await cubit.setSaturation(false, drive: 0.3, mix: 0.5, tilt: 0.3);
    await cubit.setStereoWidth(false, width: 1.0);
    await cubit.setSubCrossover(false, cornerHz: 80.0, gain: 0.8);
    await cubit.setDynamicEq(false);
    await cubit.setLoudnessContour(false, intensity: 0.0);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.eqResetNotice),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showSaveCustomPresetDialog(
      PlayerCubit cubit, PlayerState state) async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.saveCustomEqPreset,
      initialText: context.l10n.dspMyCustomEq,
      hintText: context.l10n.dspPresetNameHint,
      icon: Icons.equalizer_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    if (name != null && name.trim().isNotEmpty) {
      final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      // Read from the cubit at tap time: with the F-10 gating, this build's
      // captured `state` may predate the latest band-drag gains.
      final currentEq = cubit.state.eqPreset;
      final profile = HeadphoneProfile(
        id: id,
        name: name,
        brand: 'User Custom',
        model: name,
        category: 'Custom',
        gains: List<double>.from(currentEq.gains),
        bassBoost: currentEq.bassBoost,
      );
      await _headphoneRepo.addCustomProfile(profile);
      await cubit.applyHeadphoneProfile(profile);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.eqPresetSaved(name))),
        );
      }
    }
  }

  Future<void> _exportCurrentPreset(
      BuildContext context, PlayerCubit cubit) async {
    try {
      final jsonString = cubit.exportCurrentEqPreset();
      await SharePlus.instance.share(
        ShareParams(
          text: jsonString,
          subject: 'Pulsr EQ Preset - ${cubit.state.eqPreset.name}',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.exportFailed)),
        );
      }
    }
  }

  Future<void> _importPresetDialog(
      BuildContext context, PlayerCubit cubit) async {
    final textController = TextEditingController();
    final jsonString = await PulsrDialogHelper.showCustomDialog<String>(
      context,
      builder: (ctx) => PulsrDialog(
        title: context.l10n.importEqPreset,
        icon: Icons.file_download_rounded,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.pasteJsonPreset,
              style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '{"name": "...", "gains": [...]}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: Text(context.l10n.importAction),
          ),
        ],
      ),
    );

    if (jsonString != null && jsonString.isNotEmpty) {
      final success = await cubit.importEqPreset(jsonString);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(success
                ? context.l10n.dspPresetImported
                : context.l10n.dspPresetImportInvalid),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// F-32: edit the active band plan's center frequencies. Validates strictly
  /// ascending order and a sane 10 Hz..30 kHz range before applying, then
  /// re-pushes to the engine (the center-frequency setters only persist).
  Future<void> _showCustomFrequencyEditor(
      PlayerCubit cubit, PlayerState state) async {
    final bandCount = _activeBandCount(state);
    final initial = List<double>.from(_activeFrequencies(state));
    final controllers = [
      for (final f in initial)
        TextEditingController(
            text: f == f.roundToDouble()
                ? f.toStringAsFixed(0)
                : f.toStringAsFixed(1)),
    ];
    String? error;
    final applied = await PulsrDialogHelper.showCustomDialog<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PulsrDialog(
          title: context.l10n.customBandFreqs(initial.length),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.centerFreqHelp,
                  style: const TextStyle(fontSize: 12),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(color: context.palette.error, fontSize: 12)),
                ],
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < controllers.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TextField(
                              controller: controllers[i],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: context.l10n.eqBandLabel(i + 1),
                                suffixText: 'Hz',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final parsed = <double>[];
                for (final c in controllers) {
                  final v = double.tryParse(c.text.trim());
                  if (v == null) {
                    setDialogState(
                        () => error = context.l10n.dspEveryBandValidNumber);
                    return;
                  }
                  parsed.add(v);
                }
                for (var i = 0; i < parsed.length; i++) {
                  if (parsed[i] < 10 || parsed[i] > 30000) {
                    setDialogState(() =>
                        error = context.l10n.dspFreqRange10To30k);
                    return;
                  }
                  if (i > 0 && parsed[i] <= parsed[i - 1]) {
                    setDialogState(() =>
                        error = context.l10n.dspFreqStrictlyAscending);
                    return;
                  }
                }
                Navigator.pop(ctx, true);
              },
              child: Text(context.l10n.apply),
            ),
          ],
        ),
      ),
    );

    if (applied == true) {
      final parsed = [
        for (final c in controllers) double.parse(c.text.trim()),
      ];
      final manager = _equalizerManagerOrNull();
      if (manager != null) {
        if (bandCount == 64) {
          await manager.setCustom64Frequencies(parsed);
        } else if (bandCount == 32) {
          await manager.setCustom32Frequencies(parsed);
        } else {
          await manager.setCustomFrequencies(parsed);
        }
      }
      // The center-frequency setters only persist; re-push the active plan so
      // the native parametric EQ picks up the new centers immediately.
      await cubit.setBandMode(bandCount);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(context.l10n.customFreqsApplied),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    for (final c in controllers) {
      c.dispose();
    }
  }

  /// F-37: room-correction entry surfaced from the EQ sheet. Opens the
  /// measurement wizard or exports the current curve to the convolution stage
  /// as a linear-phase FIR (see [PlayerCubit.exportCorrectionImpulseResponse]).
  Future<void> _showRoomCorrectionActions(PlayerCubit cubit) async {
    final action = await PulsrDialogHelper.showCustomDialog<String>(
      context,
      builder: (ctx) => PulsrDialog(
        title: context.l10n.roomCorrection,
        icon: Icons.mic_rounded,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.roomMeasureHelp,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mic_rounded),
              title: Text(context.l10n.measureRoom),
              subtitle: Text(context.l10n.roomWizardDesc),
              onTap: () => Navigator.pop(ctx, 'measure'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: Text(context.l10n.exportEqFir),
              subtitle:
                  Text(context.l10n.firDesc),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'measure') {
      await RoomCorrectionSheet.show(context);
    } else if (action == 'export') {
      await _exportCurrentCurveAsFir(cubit, cubit.state);
    }
  }

  Future<void> _exportCurrentCurveAsFir(
      PlayerCubit cubit, PlayerState state) async {
    final gains = List<double>.from(state.eqPreset.gains);
    final centers = _activeFrequencies(state);
    final ir = cubit.exportCorrectionImpulseResponse(
      gains,
      centers: centers.length == gains.length ? centers : null,
    );
    final loaded = await cubit.loadCustomImpulseResponse(ir);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(loaded
            ? context.l10n.dspFirLoaded
            : context.l10n.dspFirRejected),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildBandControl({
    required int index,
    required String label,
    required bool isEnabled,
    required Color accentColor,
    required Color trackColor,
    required Color surfaceColor,
    required Color textColor,
    required Color errorColor,
    required PlayerState state,
    required PlayerCubit cubit,
  }) {
    final isMuted = _mutedBands.contains(index);
    final isSoloed = _soloedBands.contains(index);
    return BlocSelector<PlayerCubit, PlayerState, double>(
      selector: (s) =>
          index < s.eqPreset.gains.length ? s.eqPreset.gains[index] : 0.0,
      builder: (context, gain) => Semantics(
        slider: true,
        label: context.l10n.eqBandLabel(index + 1),
        value:
            '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB',
        child: RepaintBoundary(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VerticalEqSlider(
              value: gain,
              label: label,
              isEnabled: isEnabled,
              accentColor: accentColor,
              trackColor: trackColor,
              surfaceColor: surfaceColor,
              textColor: textColor,
              onInteraction: () {
                if (!state.isEqEnabled) {
                  cubit.setEqualizerEnabled(true);
                }
              },
              onChanged: (val) {
                if (!state.isEqEnabled) {
                  cubit.setEqualizerEnabled(true);
                }
                cubit.setBandGain(index, val);
              },
            ),
            const SizedBox(height: 4),
            // F-35: fast solo/mute toggles. State is transient (native has no
            // getter), so it is mirrored locally for the current session only.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bandToggle(
                  label: 'M',
                  tooltip: isMuted
                      ? context.l10n.dspUnmuteBand
                      : context.l10n.dspMuteBand,
                  active: isMuted,
                  activeColor: errorColor,
                  onTap: isEnabled
                      ? () async {
                          final next = !isMuted;
                          final manager = _equalizerManagerOrNull();
                          if (manager != null) {
                            await manager.setBandMute(index, next);
                          }
                          if (!mounted) return;
                          setState(() {
                            if (next) {
                              _mutedBands.add(index);
                            } else {
                              _mutedBands.remove(index);
                            }
                          });
                        }
                      : null,
                ),
                const SizedBox(width: 2),
                _bandToggle(
                  label: 'S',
                  tooltip: isSoloed
                      ? context.l10n.dspUnsoloBand
                      : context.l10n.dspSoloBand,
                  active: isSoloed,
                  activeColor: accentColor,
                  onTap: isEnabled
                      ? () async {
                          final next = !isSoloed;
                          final manager = _equalizerManagerOrNull();
                          if (manager != null) {
                            await manager.setBandSolo(index, next);
                          }
                          if (!mounted) return;
                          setState(() {
                            if (next) {
                              _soloedBands.add(index);
                            } else {
                              _soloedBands.remove(index);
                            }
                          });
                        }
                      : null,
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _bandToggle({
    required String label,
    required String tooltip,
    required bool active,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? activeColor : Colors.grey.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: active ? activeColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (!Platform.isAndroid) {
      return Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Icon(Icons.equalizer_rounded, color: p.textTertiary, size: 48),
                const SizedBox(height: 16),
                Text(context.l10n.hwFxUnavailable,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(context.l10n.hwFxDesc,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) =>
          prev.errorMessage != curr.errorMessage && curr.errorMessage != null,
      listener: (ctx, state) {
        final msg = state.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
              content: Text(resolveUiErrorMessage(ctx, msg)),
              backgroundColor: Theme.of(ctx).colorScheme.error,
              behavior: SnackBarBehavior.floating));
          ctx.read<PlayerCubit>().clearError();
        }
      },
      child: BlocBuilder<PlayerCubit, PlayerState>(
        // DSP sheet ignores playback/position fields entirely - position ticks at
        // 10Hz were rebuilding the whole equalizer UI for nothing.
        //
        // F-10: eqPreset identity changes on EVERY band-drag delta. The gains
        // are consumed exclusively by per-band BlocSelectors and the curve
        // selector further down, so only the preset's name/bassBoost gate this
        // full-sheet rebuild - a drag rebuilds just the dragged slider + curve.
        buildWhen: dspSheetRebuildGate,
        builder: (context, state) {
          final cubit = context.read<PlayerCubit>();
          final dspBlockedGlobal = _dspBlockedReason(context);
          final isStudio = _isStudio(context);

          // One snack per DSP auto-degrade session (re-arms after recovery).
          if (_degradeSnackQueued) {
            _degradeSnackQueued = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(context.l10n.audioStageDegraded('DSP')),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            });
          }

          return Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Adaptive.sheetConstraints(context).maxWidth,
                maxHeight: MediaQuery.sizeOf(context).height *
                    (context.isLandscape ? 0.95 : 0.84),
              ),
              child: Material(
                color: p.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      // Top Handle & Inspector Bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: context.l10n.dspResetAllEqTooltip,
                              icon: Icon(Icons.restart_alt_rounded,
                                  color: dspBlockedGlobal != null
                                      ? p.textTertiary.withValues(alpha: 0.4)
                                      : p.accent,
                                  size: 20),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                              onPressed: dspBlockedGlobal != null
                                  ? null
                                  : () => _resetAllDspDefaults(context, cubit),
                            ),
                            const Spacer(),
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: p.hairline,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<String>(
                              tooltip: context.l10n.dspPresetOptions,
                              icon: Icon(Icons.more_vert_rounded,
                                  color: p.accent, size: 20),
                              color: p.surfaceContainer,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              onSelected: (value) {
                                switch (value) {
                                  case 'save':
                                    _showSaveCustomPresetDialog(cubit, state);
                                    break;
                                  case 'export':
                                    _exportCurrentPreset(context, cubit);
                                    break;
                                  case 'import':
                                    _importPresetDialog(context, cubit);
                                    break;
                                  case 'inspector':
                                    DspInspectorSheet.show(context);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'save',
                                  child: Row(
                                    children: [
                                      Icon(Icons.save_rounded,
                                          size: 18, color: p.textPrimary),
                                      const SizedBox(width: 10),
                                      Text(context.l10n.saveCustomEqPreset,
                                          style: TextStyle(
                                              color: p.textPrimary,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'export',
                                  child: Row(
                                    children: [
                                      Icon(Icons.upload_rounded,
                                          size: 18, color: p.textPrimary),
                                      const SizedBox(width: 10),
                                      Text(context.l10n.exportPresetJson,
                                          style: TextStyle(
                                              color: p.textPrimary,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'import',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download_rounded,
                                          size: 18, color: p.textPrimary),
                                      const SizedBox(width: 10),
                                      Text(context.l10n.importPresetJson,
                                          style: TextStyle(
                                              color: p.textPrimary,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'inspector',
                                  child: Row(
                                    children: [
                                      Icon(Icons.sensors_rounded,
                                          size: 18, color: p.accent),
                                      const SizedBox(width: 10),
                                      Text(context.l10n.dspInspector,
                                          style: TextStyle(
                                              color: p.accent, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Essential vs Studio Mode Switcher
                      _buildModeSwitcher(context, p, isStudio),
                      const SizedBox(height: 6),

                      if (!isStudio)
                        Expanded(
                          child: _buildEssentialView(
                            context,
                            cubit,
                            state,
                            p,
                            dspBlockedGlobal,
                          ),
                        )
                      else ...[
                        // Separated EQ and DSP Master Toggles
                        Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            // 1. Equalizer (EQ) Toggle Card
                            Material(
                              color: Colors.transparent,
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: state.isEqEnabled
                                      ? p.accent.withValues(alpha: 0.08)
                                      : p.surfaceContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: state.isEqEnabled
                                        ? p.accent.withValues(alpha: 0.35)
                                        : p.hairline,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: dspBlockedGlobal != null &&
                                          !state.isEqEnabled
                                      ? null
                                      : () {
                                          cubit.setEqualizerEnabled(!state.isEqEnabled);
                                          _tabController.animateTo(0);
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: state.isEqEnabled
                                                ? p.accent.withValues(alpha: 0.2)
                                                : p.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.graphic_eq_rounded,
                                            color: state.isEqEnabled
                                                ? p.accent
                                                : p.textSecondary,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(context.l10n.equalizerTitle,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: p.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: state.isEqEnabled
                                                          ? (dspBlockedGlobal != null
                                                              ? p.error.withValues(
                                                                  alpha: 0.15)
                                                              : p.accent.withValues(
                                                                  alpha: 0.2))
                                                          : p.surfaceContainerHigh,
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      dspBlockedGlobal != null
                                                          ? context.l10n.dspBlocked
                                                          : (state.isEqEnabled
                                                              ? context.l10n.dspStatOn
                                                              : context.l10n.dspStatOff),
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w800,
                                                        color:
                                                            dspBlockedGlobal != null
                                                                ? p.error
                                                                : (state.isEqEnabled
                                                                    ? p.accent
                                                                    : p.textTertiary),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                dspBlockedGlobal != null
                                                    ? context.l10n.dspBlockedBitPerfect
                                                    : (state.isEqEnabled
                                                        ? (state.selectedHeadphoneProfile !=
                                                                null
                                                            ? '${context.l10n.dspTunedFor} ${state.selectedHeadphoneProfile!.name}'
                                                            : '${context.l10n.dspPresetLabel} ${state.eqPreset.name}')
                                                        : context.l10n.dspEqCurvesBypassed),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: dspBlockedGlobal != null
                                                      ? p.error
                                                      : p.textTertiary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.info_outline_rounded,
                                              size: 16, color: p.textTertiary),
                                          visualDensity: VisualDensity.compact,
                                          tooltip: context.l10n.dspAboutEqualizer,
                                          onPressed: () => _showFeatureInfo(
                                            context,
                                            AudioFeatureRegistry.equalizer,
                                            conflictReason: dspBlockedGlobal,
                                          ),
                                        ),
                                        Opacity(
                                          opacity: dspBlockedGlobal != null &&
                                                  !state.isEqEnabled
                                              ? 0.45
                                              : 1.0,
                                          child: Switch.adaptive(
                                            value: dspBlockedGlobal == null &&
                                                state.isEqEnabled,
                                            activeTrackColor: p.accent,
                                            activeThumbColor: p.onAccent,
                                            onChanged: dspBlockedGlobal != null &&
                                                    !state.isEqEnabled
                                                ? null
                                                : (val) =>
                                                    cubit.setEqualizerEnabled(val),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // 2. DSP & Spatial Effects Toggle Card
                            Material(
                              color: Colors.transparent,
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: state.isDspEffectsActive
                                      ? p.accent.withValues(alpha: 0.08)
                                      : p.surfaceContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: state.isDspEffectsActive
                                        ? p.accent.withValues(alpha: 0.35)
                                        : p.hairline,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: dspBlockedGlobal != null &&
                                          !state.isDspEffectsActive
                                      ? null
                                      : () {
                                          cubit.setDspEffectsEnabled(
                                              !state.isDspEffectsActive);
                                          _tabController.animateTo(2);
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: state.isDspEffectsActive
                                                ? p.accent.withValues(alpha: 0.2)
                                                : p.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.multitrack_audio_rounded,
                                            color: state.isDspEffectsActive
                                                ? p.accent
                                                : p.textSecondary,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(context.l10n.dspSpatialTitle,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: p.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: state.isDspEffectsActive
                                                          ? (dspBlockedGlobal != null
                                                              ? p.error.withValues(
                                                                  alpha: 0.15)
                                                              : p.accent.withValues(
                                                                  alpha: 0.2))
                                                          : p.surfaceContainerHigh,
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      dspBlockedGlobal != null
                                                          ? context.l10n.dspBlocked
                                                          : (state.isDspEffectsActive
                                                              ? context.l10n.dspStatOn
                                                              : context.l10n.dspStatOff),
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w800,
                                                        color:
                                                            dspBlockedGlobal != null
                                                                ? p.error
                                                                : (state.isDspEffectsActive
                                                                    ? p.accent
                                                                    : p.textTertiary),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                dspBlockedGlobal != null
                                                    ? context.l10n.dspBlockedBitPerfect
                                                    : (state.isDspEffectsActive
                                                        ? '${state.activeDspEffectStagesCount} ${context.l10n.dspActiveEffects}'
                                                        : context.l10n.dspAllEffectsBypassed),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: dspBlockedGlobal != null
                                                      ? p.error
                                                      : p.textTertiary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.info_outline_rounded,
                                              size: 16, color: p.textTertiary),
                                          visualDensity: VisualDensity.compact,
                                          tooltip: context.l10n.dspAboutDspEngine,
                                          onPressed: () => _showFeatureInfo(
                                            context,
                                            AudioFeatureRegistry.spatializer,
                                            conflictReason: dspBlockedGlobal,
                                          ),
                                        ),
                                        Opacity(
                                          opacity: dspBlockedGlobal != null &&
                                                  !state.isDspEffectsActive
                                              ? 0.45
                                              : 1.0,
                                          child: Switch.adaptive(
                                            value: state.isDspEffectsActive,
                                            activeTrackColor: p.accent,
                                            activeThumbColor: p.onAccent,
                                            onChanged: dspBlockedGlobal != null &&
                                                    !state.isDspEffectsActive
                                                ? null
                                                : (val) =>
                                                    cubit.setDspEffectsEnabled(val),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Top Hardware Device Profile Bar (JamesDSP parity)
                      _buildHardwareDeviceProfileBar(context, cubit, state, p),
                      const SizedBox(height: 8),

                      // The AutoEq and Spatial & DSP tabs are intentionally not
                      // exposed in the Equalizer dialog. Headphone correction is
                      // applied automatically by Smart Audio and the advanced DSP
                      // stages live in Settings (Professional mode).
                      Expanded(
                        child: Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: p.surfaceContainer,
                                  borderRadius: BorderRadius.circular(19),
                                  border: Border.all(color: p.hairline),
                                ),
                                child: TabBar(
                                  controller: _tabController,
                                  tabAlignment: TabAlignment.fill,
                                  indicator: BoxDecoration(
                                    color: p.accent,
                                    borderRadius: BorderRadius.circular(19),
                                  ),
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  labelColor: p.onAccent,
                                  unselectedLabelColor: p.textSecondary,
                                  labelStyle: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12),
                                  dividerColor: Colors.transparent,
                                  tabs: [
                                    Tab(text: context.l10n.equalizer),
                                    Tab(text: 'AutoEq'),
                                    Tab(text: context.l10n.dspSpatialTab),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildEqualizerTab(
                                      context, cubit, state, p),
                                  _buildAutoEqTab(
                                      context, cubit, state, p),
                                  _buildSpatialDynamicsTab(
                                      context, cubit, state, p),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Essential / Studio Mode Switcher
  // ---------------------------------------------------------------------------
  Widget _buildModeSwitcher(BuildContext context, PulsrPalette p, bool isStudio) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isStudioModeOverride = false);
                },
                child: AnimatedContainer(
                  duration: context.motionMs(200),
                  decoration: BoxDecoration(
                    color: !isStudio ? p.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: !isStudio
                        ? [
                            BoxShadow(
                              color: p.glow.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: !isStudio ? p.onAccent : p.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.eqModeEssential,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                !isStudio ? FontWeight.w800 : FontWeight.w600,
                            color: !isStudio ? p.onAccent : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isStudioModeOverride = true);
                },
                child: AnimatedContainer(
                  duration: context.motionMs(200),
                  decoration: BoxDecoration(
                    color: isStudio ? p.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isStudio
                        ? [
                            BoxShadow(
                              color: p.glow.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: isStudio ? p.onAccent : p.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.eqModeStudioPro,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isStudio ? FontWeight.w800 : FontWeight.w600,
                            color: isStudio ? p.onAccent : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Essential (Curated / Low Cognitive Load) View
  // ---------------------------------------------------------------------------
  Widget _buildEssentialView(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final isEnabled = state.isEqEnabled && dspBlocked == null;
    final preset = state.eqPreset;

    final bassVal = _getBassGain(state);
    final midVal = _getMidGain(state);
    final trebleVal = _getTrebleGain(state);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) ...[
            _conflictBanner(dspBlocked, p),
            const SizedBox(height: 8),
          ],

          // 1. Master Equalizer Toggle Card
          Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                color: state.isEqEnabled
                    ? p.accent.withValues(alpha: 0.08)
                    : p.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: state.isEqEnabled
                      ? p.accent.withValues(alpha: 0.35)
                      : p.hairline,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: dspBlocked != null && !state.isEqEnabled
                    ? null
                    : () => cubit.setEqualizerEnabled(!state.isEqEnabled),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: state.isEqEnabled
                              ? p.accent.withValues(alpha: 0.2)
                              : p.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color:
                              state.isEqEnabled ? p.accent : p.textSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.equalizer,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: state.isEqEnabled
                                    ? p.textPrimary
                                    : p.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              state.isEqEnabled
                                  ? (state.selectedHeadphoneProfile != null
                                      ? '${context.l10n.dspTunedFor} ${state.selectedHeadphoneProfile!.name}'
                                      : preset.name)
                                  : context.l10n.dspAllEffectsBypassed,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: state.isEqEnabled
                                    ? p.accent
                                    : p.textTertiary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: dspBlocked == null && state.isEqEnabled,
                        activeTrackColor: p.accent,
                        activeThumbColor: p.onAccent,
                        onChanged: dspBlocked != null && !state.isEqEnabled
                            ? null
                            : (val) => cubit.setEqualizerEnabled(val),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 2. Sound Profiles Presets Carousel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.eqSoundProfiles,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: p.textTertiary,
                ),
              ),
              if (preset.name != 'Flat' ||
                  state.selectedHeadphoneProfile != null)
                GestureDetector(
                  onTap: dspBlocked != null ? null : () => cubit.resetToFlat(),
                  child: Text(
                    context.l10n.resetToFlat,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: EqPreset.defaultPresets.length,
              itemBuilder: (context, index) {
                final item = EqPreset.defaultPresets[index];
                final isSelected = state.selectedHeadphoneProfile == null &&
                    preset.name == item.name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item.name),
                    selected: isSelected,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surfaceContainer,
                    side: BorderSide(
                      color: isSelected
                          ? p.accent.withValues(alpha: 0.5)
                          : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? p.accent : p.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: dspBlocked != null
                        ? null
                        : (_) {
                            if (!state.isEqEnabled) {
                              cubit.setEqualizerEnabled(true);
                            }
                            cubit.applyPreset(item);
                          },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          // 3. Quick Headphone Target Profile Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: state.selectedHeadphoneProfile != null
                    ? p.accent.withValues(alpha: 0.35)
                    : p.hairline,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: state.selectedHeadphoneProfile != null
                        ? p.accent.withValues(alpha: 0.16)
                        : p.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.headphones_rounded,
                    color: state.selectedHeadphoneProfile != null
                        ? p.accent
                        : p.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.selectedHeadphoneProfile != null
                            ? 'AutoEQ: ${state.selectedHeadphoneProfile!.name}'
                            : 'Headphone Calibration',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: state.selectedHeadphoneProfile != null
                              ? p.accent
                              : p.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.selectedHeadphoneProfile != null
                            ? '${state.selectedHeadphoneProfile!.brand} • Target Curve Applied'
                            : 'Auto-calibrate frequency response for your headphones',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (state.selectedHeadphoneProfile != null)
                  IconButton(
                    tooltip: 'Clear Headphone Calibration',
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: p.textSecondary),
                    onPressed: () => cubit.resetToFlat(),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  TextButton(
                    onPressed: () {
                      setState(() => _isStudioModeOverride = true);
                      _tabController.animateTo(1);
                    },
                    child: Text(
                      context.l10n.eqCalibrate,
                      style: TextStyle(
                          color: p.accent, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Live Frequency Curve Visualizer Card
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.eqFreqResponseCurve,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: p.textTertiary,
                      ),
                    ),
                    Text(
                      isEnabled ? 'Active' : 'Bypassed',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isEnabled ? p.accent : p.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  child: EqCurveVisualizer(
                    gains: preset.gains,
                    activeColor: isEnabled
                        ? p.accent
                        : p.textTertiary.withValues(alpha: 0.4),
                    height: 86,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 5. Macro Sound Tuning Sliders (Bass, Vocals, Treble)
          Text(
            context.l10n.eqQuickToneDials,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(height: 10),

          _buildMacroSliderRow(
            context: context,
            icon: Icons.speaker_rounded,
            title: 'Bass & Punch',
            subtitle: 'Sub-bass impact & warmth (31 Hz – 125 Hz)',
            value: bassVal,
            accentColor: p.accent,
            p: p,
            onChanged: (val) => _setBassMacro(cubit, state, val),
          ),
          const SizedBox(height: 10),

          _buildMacroSliderRow(
            context: context,
            icon: Icons.mic_rounded,
            title: 'Vocal & Presence',
            subtitle: 'Lead vocals & acoustic presence (500 Hz – 2 kHz)',
            value: midVal,
            accentColor: const Color(0xFF00E5FF),
            p: p,
            onChanged: (val) => _setMidMacro(cubit, state, val),
          ),
          const SizedBox(height: 10),

          _buildMacroSliderRow(
            context: context,
            icon: Icons.auto_awesome_rounded,
            title: 'Clarity & Air',
            subtitle: 'Treble shimmer & spatial detail (4 kHz – 16 kHz)',
            value: trebleVal,
            accentColor: const Color(0xFFFFB300),
            p: p,
            onChanged: (val) => _setTrebleMacro(cubit, state, val),
          ),

          const SizedBox(height: 16),

          // 6. Pro Banner: "Switch to Studio Console"
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _isStudioModeOverride = true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.14),
                    p.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.accent.withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune_rounded, color: p.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.eqUnlockStudioConsole,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.eqUnlockStudioDesc,
                          style: TextStyle(
                            fontSize: 11,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.accent, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSliderRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required Color accentColor,
    required PulsrPalette p,
    required ValueChanged<double> onChanged,
  }) {
    final sign = value > 0 ? '+' : '';
    final gainText = '$sign${value.toStringAsFixed(1)} dB';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10.5, color: p.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  gainText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accentColor,
              thumbColor: Colors.white,
              overlayColor: accentColor.withValues(alpha: 0.18),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(-12.0, 12.0),
              min: -12.0,
              max: 12.0,
              divisions: 48,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  // 1. Equalizer Tab
  Widget _buildEqualizerTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final preset = state.eqPreset;
    final isEnabled = state.isEqEnabled;
    final dspBlocked = _dspBlockedReason(context);
    final effectiveEnabled = isEnabled && dspBlocked == null;
    final spatializerAvailable = _spatializerToggleAvailable(state);

    // Gain staging calculations for Volume Boost
    final preampDb = state.selectedHeadphoneProfile?.preampGain ?? 0.0;
    final safeMaxBoost = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
    final isOverSafe = state.volumeBoost > safeMaxBoost;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) _conflictBanner(dspBlocked, p),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconButton(
                      icon: Icon(Icons.info_outline_rounded,
                          size: 18, color: p.accent),
                      onPressed: () => _showFeatureInfo(
                          context, AudioFeatureRegistry.equalizer,
                          conflictReason: dspBlocked)),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(context.l10n.dspDisabledBp,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 11))),
                ],
              ),
            ),
          // Presets Carousel & Actions Header
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: EqPreset.defaultPresets.length,
                    itemBuilder: (context, index) {
                      final presetItem = EqPreset.defaultPresets[index];
                      final isSelected =
                          state.selectedHeadphoneProfile == null &&
                              preset.name == presetItem.name;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(presetItem.name),
                          selected: isSelected,
                          selectedColor: p.accent.withValues(alpha: 0.22),
                          backgroundColor: p.surfaceContainer,
                          side: BorderSide(
                            color: isSelected
                                ? p.accent.withValues(alpha: 0.5)
                                : p.hairline,
                          ),
                          labelStyle: TextStyle(
                            color: isSelected ? p.accent : p.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          onSelected: dspBlocked != null
                              ? null
                              : (_) {
                                  if (!state.isEqEnabled) {
                                    cubit.setEqualizerEnabled(true);
                                  }
                                  cubit.applyPreset(presetItem);
                                },
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // A/B Comparison Toggle
              IgnorePointer(
                ignoring: dspBlocked != null,
                child: Opacity(
                  opacity: dspBlocked != null ? 0.45 : 1.0,
                  child: GestureDetector(
                    onTapDown: (_) {
                      setState(() => _isAbComparing = true);
                      cubit.startAbComparison();
                    },
                    onTapUp: (_) {
                      setState(() => _isAbComparing = false);
                      cubit.endAbComparison();
                    },
                    onTapCancel: () {
                      setState(() => _isAbComparing = false);
                      cubit.endAbComparison();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _isAbComparing ? p.accent : p.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _isAbComparing ? p.accent : p.hairline),
                      ),
                      child: Text(context.l10n.abFlat,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _isAbComparing ? p.onAccent : p.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Reset to Flat button
              TextButton.icon(
                onPressed:
                    dspBlocked != null ? null : () => cubit.resetToFlat(),
                icon: Icon(Icons.restore_rounded,
                    size: 16, color: p.textSecondary),
                label: Text(context.l10n.reset,
                    style: TextStyle(
                        fontSize: 11,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              // Save Custom Preset button
              TextButton.icon(
                onPressed: dspBlocked != null
                    ? null
                    : () => _showSaveCustomPresetDialog(cubit, state),
                icon:
                    Icon(Icons.bookmark_add_rounded, size: 16, color: p.accent),
                label: Text(context.l10n.save,
                    style: TextStyle(
                        fontSize: 11,
                        color: p.accent,
                        fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // A/B/C/D 4-Slot Comparison & Studio Tools Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // A/B/C/D Slot Selector
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      for (final slot in ComparisonSlot.values) ...[
                        InkWell(
                          onTap: () => cubit.switchComparisonSlot(slot),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              slot.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // AutoEQ Online Search
                ActionChip(
                  avatar: Icon(Icons.search_rounded, size: 14, color: p.accent),
                  label: Text(context.l10n.autoEqSearch,
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => AutoEqSearchSheet(
                        equalizerManager: getIt<EqualizerManager>(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Studio Dynamics Compressor
                ActionChip(
                  avatar:
                      Icon(Icons.compress_rounded, size: 14, color: p.primary),
                  label: Text(context.l10n.dynamicsCompressor,
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    final blocked = _dspBlockedReason(context);
                    if (blocked != null) {
                      // This sheet drives EqualizerManager directly, bypassing
                      // PlayerCubit's guard; refuse it here so the compressor
                      // cannot be toggled while bit-perfect/AAudio/DoP is active.
                      PulsrToast.show(
                        context,
                        message: blocked,
                        icon: Icons.error_outline_rounded,
                        isError: true,
                      );
                      return;
                    }
                    CompressorLimiterSheet.show(
                      context,
                      equalizerManager: getIt<EqualizerManager>(),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // F-37: room-correction entry with FIR export.
                ActionChip(
                  avatar:
                      Icon(Icons.graphic_eq_rounded, size: 14, color: p.accent),
                  label: Text(context.l10n.roomCorrection,
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: dspBlocked != null
                      ? null
                      : () => _showRoomCorrectionActions(cubit),
                ),
                const SizedBox(width: 8),

                // ViPER-DDC
                ActionChip(
                  avatar: Icon(Icons.headphones_rounded,
                      size: 14,
                      color:
                          state.isViperDdcEnabled ? p.accent : p.textSecondary),
                  label: Text(
                    state.isViperDdcEnabled &&
                            state.viperDdcProfileName.isNotEmpty
                        ? 'DDC: ${state.viperDdcProfileName}'
                        : 'ViPER-DDC',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: state.isViperDdcEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isViperDdcEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isViperDdcEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const ViperDdcSheet(),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Arbitrary Response EQ
                ActionChip(
                  avatar: Icon(Icons.auto_graph_rounded,
                      size: 14,
                      color: state.isArbitraryEqEnabled
                          ? p.accent
                          : p.textSecondary),
                  label: Text(context.l10n.arbitraryEq,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color:
                          state.isArbitraryEqEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isArbitraryEqEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isArbitraryEqEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const ArbitraryEqSheet(),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Live Programmable DSP
                ActionChip(
                  avatar: Icon(Icons.terminal_rounded,
                      size: 14,
                      color:
                          state.isLiveProgEnabled ? p.accent : p.textSecondary),
                  label: Text(context.l10n.liveProgDsp,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: state.isLiveProgEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isLiveProgEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isLiveProgEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const LiveProgSheet(),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Dynamic Bass
                ActionChip(
                  avatar: Icon(Icons.speaker_group_rounded,
                      size: 14,
                      color: state.isDynamicBassEnabled
                          ? p.accent
                          : p.textSecondary),
                  label: Text(context.l10n.dynamicBass,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color:
                          state.isDynamicBassEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isDynamicBassEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isDynamicBassEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: dspBlocked != null || !_nativePcmEffectsAvailable
                      ? null
                      : () {
                          _tabController.animateTo(1);
                          cubit.setDynamicBass(!state.isDynamicBassEnabled);
                        },
                ),
                const SizedBox(width: 8),

                // DSP Inspector
                ActionChip(
                  avatar:
                      Icon(Icons.insights_rounded, size: 14, color: p.accent),
                  label: Text(context.l10n.dspChain,
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () => DspInspectorSheet.show(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Active Profile Banner if AutoEq is selected
          // OEM Audio Double-Processing Warning Banner
          if (state.hasOemAudio &&
              (state.isEqEnabled ||
                  state.isCrossfeedEnabled ||
                  state.isLimiterEnabled ||
                  state.isVirtualizerEnabled ||
                  state.isDynamicsEnabled)) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.warning.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: p.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${state.detectedOemEngines.join(", ")} ${context.l10n.activeLabel}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.warning,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(context.l10n.systemFxActive,
                          style:
                              TextStyle(fontSize: 11, color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (state.selectedHeadphoneProfile != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.headphones_rounded, color: p.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AutoEq: ${state.selectedHeadphoneProfile!.name}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                        Text(
                          '${state.selectedHeadphoneProfile!.brand} Ã¢Â€Â¢ '
                          '${context.l10n.preampLabel}: ${state.selectedHeadphoneProfile!.preampGain.toStringAsFixed(1)} dB',
                          style: TextStyle(fontSize: 10, color: p.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => cubit.resetToFlat(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                    child: Text(context.l10n.reset,
                        style: TextStyle(color: p.textSecondary, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Real-time Frequency Response Curve Visualizer.
          // F-10/F-24: the gains come from a dedicated BlocSelector (band
          // drags repaint only the curve), and the RepaintBoundary keeps the
          // curve repaint inside its own layer instead of propagating to the
          // ancestor layers during drags.
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: BlocSelector<PlayerCubit, PlayerState, List<double>>(
              selector: (s) => s.eqPreset.gains,
              builder: (context, gains) => RepaintBoundary(
                child: EqCurveVisualizer(
                  gains: gains,
                  activeColor: effectiveEnabled ? p.accent : p.textTertiary,
                  height: 52,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // F-32: 10 / 32 / 64-band mode toggle + custom frequency editor.
          Row(
            children: [
              Text(context.l10n.bandsLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  children: [
                    for (final bandCount in const [10, 32, 64])
                      InkWell(
                        borderRadius: BorderRadius.circular(7),
                        onTap: dspBlocked != null
                            ? null
                            : () async {
                                if (_activeBandCount(state) == bandCount) {
                                  return;
                                }
                                _mutedBands.clear();
                                _soloedBands.clear();
                                await cubit.setBandMode(bandCount);
                                if (mounted) setState(() {});
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _activeBandCount(state) == bandCount
                                ? p.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '$bandCount',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _activeBandCount(state) == bandCount
                                  ? p.onAccent
                                  : p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: dspBlocked != null
                    ? null
                    : () => _showCustomFrequencyEditor(cubit, state),
                icon: Icon(Icons.tune_rounded, size: 16, color: p.accent),
                label: Text(context.l10n.frequencies,
                    style: TextStyle(
                        fontSize: 11,
                        color: p.accent,
                        fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Equalizer band sliders — 10-band ISO, 32-band 1/3-octave or
          // 64-band log-spaced. Non-10 plans render in a horizontal scroll.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Builder(
              builder: (context) {
                final bandCount = _activeBandCount(state);
                final frequencies = _activeFrequencies(state);
                final compact = bandCount > 10;
                final sliders = Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(bandCount, (index) {
                    // F-10: each band subscribes to its own gain via
                    // BlocSelector, so a band-drag delta rebuilds only the
                    // dragged slider (plus the curve) instead of the whole sheet.
                    final control = _buildBandControl(
                      index: index,
                      label: index < frequencies.length
                          ? _formatHz(frequencies[index])
                          : '',
                      isEnabled: effectiveEnabled,
                      accentColor: p.accent,
                      trackColor: p.hairline,
                      surfaceColor: p.surface,
                      textColor: p.textPrimary,
                      errorColor: p.error,
                      state: state,
                      cubit: cubit,
                    );
                    return compact
                        ? SizedBox(width: 40, child: control)
                        : Expanded(child: control);
                  }),
                );
                if (!compact) return sliders;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: sliders,
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // F-33: manual preamp / gain staging with clipping warning.
          Builder(
            builder: (context) => StatefulBuilder(
              builder: (context, setCardState) {
                final manager = _equalizerManagerOrNull();
                final currentPreamp = manager?.preampDb ??
                    (state.selectedHeadphoneProfile?.preampGain ?? 0.0);
                final maxBoost = state.eqPreset.gains.isEmpty
                    ? 0.0
                    : state.eqPreset.gains.reduce((a, b) => a > b ? a : b);
                final clipRisk = currentPreamp + maxBoost > 0.0;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(
                      color: clipRisk
                          ? p.error.withValues(alpha: 0.45)
                          : p.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (clipRisk ? p.error : p.accent)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.vertical_align_center_rounded,
                              color: clipRisk ? p.error : p.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.preampLabel,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: p.textPrimary),
                                ),
                                Text(
                                  state.selectedHeadphoneProfile != null
                                      ? 'Manual override (AutoEQ suggests '
                                          '${state.selectedHeadphoneProfile!.preampGain.toStringAsFixed(1)} dB)'
                                      : 'Output gain applied before the EQ',
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (clipRisk
                                      ? p.error
                                      : (currentPreamp.abs() > 0.05
                                          ? p.accent
                                          : p.surface))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: clipRisk
                                    ? p.error.withValues(alpha: 0.4)
                                    : (currentPreamp.abs() > 0.05
                                        ? p.accent.withValues(alpha: 0.3)
                                        : p.hairline),
                              ),
                            ),
                            child: Text(
                              '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)} dB',
                              style: TextStyle(
                                color: clipRisk
                                    ? p.error
                                    : (currentPreamp.abs() > 0.05
                                        ? p.accent
                                        : p.textSecondary),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 16,
                                color: currentPreamp.abs() <= 0.05 ||
                                        dspBlocked != null
                                    ? p.textTertiary.withValues(alpha: 0.35)
                                    : p.accent),
                            tooltip: context.l10n.dspResetPreamp,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 24, minHeight: 24),
                            onPressed: currentPreamp.abs() <= 0.05 ||
                                    dspBlocked != null
                                ? null
                                : () {
                                    final target = state
                                            .selectedHeadphoneProfile
                                            ?.preampGain ??
                                        0.0;
                                    manager?.setPreamp(target);
                                    setCardState(() {});
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Semantics(
                        slider: true,
                        label: context.l10n.preampLabel,
                        value:
                            '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)} dB',
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                            activeTrackColor: clipRisk ? p.error : p.accent,
                            inactiveTrackColor: p.surface,
                            thumbColor: clipRisk ? p.error : p.accent,
                          ),
                          child: Slider(
                            value: currentPreamp.clamp(-12.0, 12.0),
                            min: -12.0,
                            max: 12.0,
                            divisions: 48,
                            onChanged: dspBlocked != null
                                ? null
                                : (val) {
                                    if (!state.isEqEnabled) {
                                      cubit.setEqualizerEnabled(true);
                                    }
                                    final rounded =
                                        (val * 10).roundToDouble() / 10.0;
                                    manager?.setPreamp(rounded);
                                    setCardState(() {});
                                  },
                          ),
                        ),
                      ),
                      if (clipRisk)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 4),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: p.error, size: 13),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  context.l10n.dspPreampClipWarning(
                                    '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)}',
                                    maxBoost.toStringAsFixed(1),
                                  ),
                                  style: TextStyle(
                                      color: p.error,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Bass Boost Slider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.speaker_group_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(context.l10n.bassEnhancer,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: p.textPrimary),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    size: 16, color: p.textTertiary),
                                visualDensity: VisualDensity.compact,
                                tooltip: context.l10n.dspAboutBassBoost,
                                onPressed: () => _showFeatureInfo(
                                    context, AudioFeatureRegistry.bassBoost,
                                    conflictReason: dspBlocked),
                              ),
                            ],
                          ),
                          Text(
                            preset.bassBoost > 0
                                ? '${(preset.bassBoost * 100).round()}% punch'
                                : 'Bass boost bypassed',
                            style:
                                TextStyle(fontSize: 11, color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (preset.bassBoost > 0 ? p.accent : p.surface)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: preset.bassBoost > 0
                                  ? p.accent.withValues(alpha: 0.3)
                                  : p.hairline,
                            ),
                          ),
                          child: Text(
                            preset.bassBoost > 0
                                ? '${(preset.bassBoost * 100).round()}%'
                                : context.l10n.dspOff,
                            style: TextStyle(
                              color: preset.bassBoost > 0
                                  ? p.accent
                                  : p.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.settings_backup_restore,
                              size: 16,
                              color: preset.bassBoost <= 0.001 ||
                                      dspBlocked != null
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                          tooltip: context.l10n.dspResetBassEnhancer,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: preset.bassBoost <= 0.001 ||
                                  dspBlocked != null ||
                                  !state.isBassBoostSupported
                              ? null
                              : () => cubit.setBassBoost(0.0),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: p.accent,
                  ),
                  child: Semantics(
                    slider: true,
                    label: context.l10n.bassEnhancer,
                    child: Slider(
                      value: preset.bassBoost.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: dspBlocked != null || !state.isBassBoostSupported
                          ? null
                          : (val) {
                              if (!state.isEqEnabled) {
                                cubit.setEqualizerEnabled(true);
                              }
                              cubit.setBassBoost(val);
                            },
                    ),
                  ),
                ),
                _effectNotAppliedNotice('bassBoost', p),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Volume Boost Slider (LoudnessEnhancer)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isOverSafe ? p.error : p.accent)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.volume_up_rounded,
                        color: isOverSafe ? p.error : p.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(context.l10n.volumeBoost,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: p.textPrimary),
                                ),
                              ),
                              IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      size: 16, color: p.textTertiary),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: context.l10n.dspAboutVolumeBoost,
                                  onPressed: () => _showFeatureInfo(
                                      context, AudioFeatureRegistry.volumeBoost,
                                      conflictReason: dspBlocked)),
                            ],
                          ),
                          Text(
                            state.volumeBoost > 0
                                ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB hardware gain'
                                : 'Hardware gain bypassed',
                            style:
                                TextStyle(fontSize: 11, color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isOverSafe
                                    ? p.error
                                    : (state.volumeBoost > 0
                                        ? p.accent
                                        : p.surface))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isOverSafe
                                  ? p.error.withValues(alpha: 0.4)
                                  : (state.volumeBoost > 0
                                      ? p.accent.withValues(alpha: 0.3)
                                      : p.hairline),
                            ),
                          ),
                          child: Text(
                            state.volumeBoost > 0
                                ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB'
                                : context.l10n.dspOff,
                            style: TextStyle(
                              color: isOverSafe
                                  ? p.error
                                  : (state.volumeBoost > 0
                                      ? p.accent
                                      : p.textSecondary),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.settings_backup_restore,
                              size: 16,
                              color: state.volumeBoost <= 0.001 ||
                                      dspBlocked != null
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                          tooltip: context.l10n.dspResetVolumeBoost,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: state.volumeBoost <= 0.001 ||
                                  dspBlocked != null ||
                                  !state.isVolumeBoostSupported
                              ? null
                              : () => cubit.setVolumeBoost(0.0),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: isOverSafe ? p.error : p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: isOverSafe ? p.error : p.accent,
                  ),
                  child: Semantics(
                    slider: true,
                    label: context.l10n.volumeBoost,
                    child: Slider(
                      value: state.volumeBoost.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged:
                          dspBlocked != null || !state.isVolumeBoostSupported
                              ? null
                              : (val) {
                                  if (!state.isEqEnabled) {
                                    cubit.setEqualizerEnabled(true);
                                  }
                                  cubit.setVolumeBoost(val);
                                },
                    ),
                  ),
                ),
                if (isOverSafe)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: p.error, size: 13),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.l10n.dspVolumeClipWarning(
                                preampDb.toStringAsFixed(1)),
                            style: TextStyle(
                                color: p.error,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (state.volumeBoost > 0.6)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: p.error, size: 13),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(context.l10n.highBoostWarn,
                            style: TextStyle(
                                color: p.error,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                _effectNotAppliedNotice('volumeBoost', p),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Honest Spatializer / Soundstage Widening Section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.spatial_tracking_rounded,
                      color: p.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              state.isSpatializerSupported
                                  ? 'Spatial Audio'
                                  : 'Soundstage Widening',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (state.isSpatializerSupported
                                      ? p.accent
                                      : p.textTertiary)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              state.isSpatializerSupported
                                  ? 'Spatial API'
                                  : 'Emulated',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: state.isSpatializerSupported
                                    ? p.accent
                                    : p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? 'Android Spatializer API with head tracking'
                            : 'Stereo field expansion via hardware virtualizer',
                        style: TextStyle(fontSize: 11, color: p.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: dspBlocked == null && state.isSpatializerEnabled,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: dspBlocked != null || !spatializerAvailable
                      ? null
                      : (val) => cubit.setSpatializerEnabled(val),
                ),
              ],
            ),
          ),
          _effectNotAppliedNotice('spatializer', p),
        ],
      ),
    );
  }

  // 2. AutoEq Headphone Presets Tab
  Widget _buildAutoEqTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    if (_isLoadingProfiles) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }

    final categories = _headphoneRepo.getCategories();
    final filteredProfiles =
        _headphoneRepo.search(_searchQuery, category: _selectedCategory);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: TextStyle(fontSize: 13, color: p.textPrimary),
              decoration: InputDecoration(
                hintText: context.l10n.dspSearchHeadphonesHint,
                hintStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                prefixIcon:
                    Icon(Icons.search_rounded, color: p.textTertiary, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: p.textTertiary, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),

        // Category Filter Chips
        SizedBox(
          height: 34,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: p.accent.withValues(alpha: 0.2),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(
                    color: isSelected
                        ? p.accent.withValues(alpha: 0.4)
                        : p.hairline,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? p.accent : p.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Active Profile Banner (if applied)
        if (state.selectedHeadphoneProfile != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: p.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.appliedTuningProfile,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: p.accent),
                        ),
                        Text(
                          state.selectedHeadphoneProfile!.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => cubit.resetToFlat(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Text(context.l10n.resetToFlat,
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Profiles List
        Expanded(
          child: filteredProfiles.isEmpty
              ? Center(
                  child: Text(context.l10n.noHpProfiles,
                    style: TextStyle(color: p.textTertiary, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filteredProfiles.length,
                  itemBuilder: (context, index) {
                    final profile = filteredProfiles[index];
                    final isApplied =
                        state.selectedHeadphoneProfile?.id == profile.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            if (isApplied) {
                              await cubit.resetToFlat();
                            } else {
                              if (!state.isEqEnabled) {
                                await cubit.setEqualizerEnabled(true);
                              }
                              await cubit.applyHeadphoneProfile(profile);
                            }
                          },
                          borderRadius: AppRadii.cardRadius,
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isApplied
                                  ? p.accent.withValues(alpha: 0.14)
                                  : p.surfaceContainer,
                              borderRadius: AppRadii.cardRadius,
                              border: Border.all(
                                color: isApplied ? p.accent : p.hairline,
                                width: isApplied ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color:
                                        (isApplied ? p.accent : p.textTertiary)
                                            .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    profile.category == 'Over-Ear'
                                        ? Icons.headset_rounded
                                        : Icons.headphones_rounded,
                                    color:
                                        isApplied ? p.accent : p.textSecondary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: isApplied
                                              ? p.accent
                                              : p.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${profile.brand} Ã¢Â€Â¢ ${profile.category}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: p.textTertiary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (profile.id.startsWith('custom_')) ...[
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded,
                                        size: 18, color: p.error),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: context.l10n.dspDeleteCustomPreset,
                                    onPressed: () async {
                                      await _headphoneRepo
                                          .removeProfile(profile.id);
                                      if (isApplied) await cubit.resetToFlat();
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                if (isApplied)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              p.accent.withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_rounded,
                                            color: p.onAccent, size: 13),
                                        const SizedBox(width: 4),
                                        Text(context.l10n.activeLabel,
                                          style: TextStyle(
                                            color: p.onAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: p.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: p.hairline),
                                    ),
                                    child: Text(context.l10n.apply,
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 3. Spatial & Dynamics Tab
  Widget _buildSpatialDynamicsTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final dspBlocked = _dspBlockedReason(context);
    final spatializerAvailable = _spatializerToggleAvailable(state);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) _conflictBanner(dspBlocked, p),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(context.l10n.allDspBypassed,
                  style: TextStyle(color: p.textSecondary, fontSize: 11)),
            ),
          // Support Detection Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: state.isSpatializerSupported
                  ? p.accent.withValues(alpha: 0.12)
                  : p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(
                color: state.isSpatializerSupported
                    ? p.accent.withValues(alpha: 0.4)
                    : p.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  state.isSpatializerSupported
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  color:
                      state.isSpatializerSupported ? p.accent : p.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isSpatializerSupported
                            ? 'Hardware Spatializer Detected'
                            : 'Emulated 3D Widening Mode',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: state.isSpatializerSupported
                              ? p.accent
                              : p.textPrimary,
                        ),
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? 'Android Spatializer API with multi-channel soundstage'
                            : 'Stereo field widening active via hardware virtualizer',
                        style: TextStyle(fontSize: 10, color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Dolby Atmos / Hardware Spatial Audio Card (when supported by device)
          if (state.isSpatializerSupported) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.spatial_tracking_rounded,
                        color: p.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(context.l10n.spatialAudio,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: p.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(context.l10n.spatialApi,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(context.l10n.spatialApiDesc,
                          style: TextStyle(fontSize: 11, color: p.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: Icon(Icons.info_outline_rounded,
                          size: 16, color: p.textTertiary),
                      visualDensity: VisualDensity.compact,
                      tooltip: context.l10n.dspAboutSpatializer,
                      onPressed: () => _showFeatureInfo(
                          context, AudioFeatureRegistry.spatializer,
                          conflictReason: dspBlocked)),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: dspBlocked == null && state.isSpatializerEnabled,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged: dspBlocked != null || !spatializerAvailable
                        ? null
                        : (val) => cubit.setSpatializerEnabled(val),
                  ),
                ],
              ),
            ),
            if (dspBlocked != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(context.l10n.blockedByBitPerfectShort,
                      style: TextStyle(
                          color: p.error,
                          fontSize: 10,
                          fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
          ],

          // Stereo Soundstage Expansion (Virtualizer)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.surround_sound_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.soundstageWidening,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(context.l10n.virtualizerDesc,
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.dspAboutVirtualizer,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.virtualizer,
                            conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: dspBlocked == null && state.isVirtualizerEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !state.isVirtualizerSupported
                              ? null
                              : (val) => cubit.setVirtualizerEnabled(val),
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 8),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))),
                const SizedBox(height: 16),

                // Soundstage visual slider
                Opacity(
                  opacity: dspBlocked != null
                      ? 0.35
                      : (state.isVirtualizerEnabled ? 1.0 : 0.35),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.width,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(state.virtualizerStrength * 100).round()}%',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: p.accent),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(Icons.settings_backup_restore,
                                    size: 15,
                                    color: !state.isVirtualizerEnabled ||
                                            state.virtualizerStrength <= 0.001
                                        ? p.textTertiary.withValues(alpha: 0.35)
                                        : p.accent),
                                tooltip: context.l10n.dspResetToDefault0,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 20, minHeight: 20),
                                onPressed: !state.isVirtualizerSupported ||
                                        !state.isVirtualizerEnabled ||
                                        state.virtualizerStrength <= 0.001
                                    ? null
                                    : () => cubit.setVirtualizerStrength(0.0),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          activeTrackColor: p.accent,
                          inactiveTrackColor: p.surface,
                          thumbColor: p.accent,
                        ),
                        child: Semantics(
                          slider: true,
                          label: context.l10n.width,
                          child: Slider(
                            value: state.virtualizerStrength.clamp(0.0, 1.0),
                            min: 0.0,
                            max: 1.0,
                            onChanged: state.isVirtualizerEnabled &&
                                    state.isVirtualizerSupported
                                ? (val) => cubit.setVirtualizerStrength(val)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _effectNotAppliedNotice('virtualizer', p),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Studio Dynamics (DynamicsProcessing)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.compress_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.studioDynamics,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(context.l10n.multibandDesc,
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.dspAboutDynamics,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.dynamics,
                            conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: dspBlocked == null && state.isDynamicsEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !state.isDynamicsSupported
                              ? null
                              : (val) {
                                  cubit.setDynamicsPreset(
                                    val
                                        ? (state.dynamicsPreset ==
                                                DynamicsPreset.off
                                            ? DynamicsPreset.studioPunch
                                            : state.dynamicsPreset)
                                        : DynamicsPreset.off,
                                    enabled: val,
                                  );
                                },
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))),
                _effectNotAppliedNotice('dynamics', p),
                const SizedBox(height: 14),

                // Dynamics Preset Cards Grid
                Opacity(
                  opacity: dspBlocked != null
                      ? 0.35
                      : (state.isDynamicsEnabled ? 1.0 : 0.35),
                  child: Column(
                    children: DynamicsPreset.values
                        .where((d) => d != DynamicsPreset.off)
                        .map((preset) {
                      final isSelected = state.isDynamicsEnabled &&
                          state.dynamicsPreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap:
                              dspBlocked != null || !state.isDynamicsSupported
                                  ? null
                                  : (state.isDynamicsEnabled
                                      ? () => cubit.setDynamicsPreset(preset,
                                          enabled: true)
                                      : null),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? p.accent.withValues(alpha: 0.15)
                                  : p.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? p.accent.withValues(alpha: 0.5)
                                    : p.hairline,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: isSelected ? p.accent : p.textTertiary,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        preset.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? p.accent
                                              : p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        preset.description,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: p.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 1. Headphone Crossfeed (Chu Moy / Linkwitz-Riley)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.headphones_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.crossfeedHp,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(context.l10n.crossfeedNatural,
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.dspAboutCrossfeed,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.crossfeed,
                            conflictReason: dspBlocked ??
                                (_nativePcmEffectsAvailable
                                    ? null
                                    : 'Requires PCM DSP path - not audible yet'))),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: dspBlocked == null &&
                          _nativePcmEffectsAvailable &&
                          state.isCrossfeedEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !_nativePcmEffectsAvailable
                              ? null
                              : (val) => cubit.setCrossfeed(val),
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))),
                if (dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isCrossfeedEnabled) ...[
                  const SizedBox(height: 14),
                  // BS2B Preset Selector Chips
                  Text(context.l10n.crossfeedAlgorithm,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text(context.l10n.dspCrossfeedDefault),
                        selected: state.crossfeedMode == 0,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 0 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 0
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) => cubit.setCrossfeedMode(0),
                      ),
                      ChoiceChip(
                        label: Text(context.l10n.dspCrossfeedChuMoy),
                        selected: state.crossfeedMode == 1,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 1 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 1
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) => cubit.setCrossfeedMode(1),
                      ),
                      ChoiceChip(
                        label: Text(context.l10n.dspCrossfeedJanMeier),
                        selected: state.crossfeedMode == 2,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 2 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 2
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) => cubit.setCrossfeedMode(2),
                      ),
                      ChoiceChip(
                        label: Text(context.l10n.customDelayLine),
                        selected: state.crossfeedMode == 3,
                        selectedColor: p.accent.withValues(alpha: 0.22),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color:
                              state.crossfeedMode == 3 ? p.accent : p.hairline,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: state.crossfeedMode == 3
                              ? p.accent
                              : p.textSecondary,
                        ),
                        onSelected: (_) => cubit.setCrossfeedMode(3),
                      ),
                    ],
                  ),
                  if (state.crossfeedMode < 3) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: p.accent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(context.l10n.bs2bActive,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (state.crossfeedMode == 3) ...[
                    const SizedBox(height: 14),
                    // Delay slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.delayTime,
                            style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${state.crossfeedDelayUs.round()} µs',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.settings_backup_restore,
                                  size: 15,
                                  color: (state.crossfeedDelayUs - 350.0)
                                              .abs() <
                                          1.0
                                      ? p.textTertiary.withValues(alpha: 0.35)
                                      : p.accent),
                              tooltip: context.l10n.dspResetToDefault350us,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 20, minHeight: 20),
                              onPressed:
                                  (state.crossfeedDelayUs - 350.0).abs() < 1.0
                                      ? null
                                      : () => cubit.setCrossfeed(true,
                                          delayUs: 350.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: p.accent,
                        inactiveTrackColor: p.surface,
                        thumbColor: p.accent,
                      ),
                      child: Semantics(
                        slider: true,
                        label: context.l10n.delayTime,
                        child: Slider(
                          value: state.crossfeedDelayUs.clamp(200.0, 700.0),
                          min: 200.0,
                          max: 700.0,
                          divisions: 50,
                          onChanged: (val) =>
                              cubit.setCrossfeed(true, delayUs: val),
                        ),
                      ),
                    ),
                    // Feed Level slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.oppositeEarBleed,
                            style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${state.crossfeedFeedDb.toStringAsFixed(1)} dB',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.settings_backup_restore,
                                  size: 15,
                                  color: (state.crossfeedFeedDb - (-9.0))
                                              .abs() <
                                          0.05
                                      ? p.textTertiary.withValues(alpha: 0.35)
                                      : p.accent),
                              tooltip: context.l10n.dspResetToDefault9db,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 20, minHeight: 20),
                              onPressed:
                                  (state.crossfeedFeedDb - (-9.0)).abs() < 0.05
                                      ? null
                                      : () => cubit.setCrossfeed(true,
                                          feedDb: -9.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: p.accent,
                        inactiveTrackColor: p.surface,
                        thumbColor: p.accent,
                      ),
                      child: Semantics(
                        slider: true,
                        label: context.l10n.oppositeEarBleed,
                        child: Slider(
                          value: state.crossfeedFeedDb.clamp(-15.0, -6.0),
                          min: -15.0,
                          max: -6.0,
                          divisions: 18,
                          onChanged: (val) =>
                              cubit.setCrossfeed(true, feedDb: val),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Lookahead Brickwall Limiter
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.security_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.lookaheadLimiter,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(context.l10n.lookaheadDesc,
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.dspAboutLimiter,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.limiter,
                            conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: dspBlocked == null && state.isLimiterEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null
                          ? null
                          : (val) => cubit.setLookaheadLimiter(val),
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))),
                if (dspBlocked == null && state.isLimiterEnabled) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.ceilingThreshold,
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.limiterThresholdDb.toStringAsFixed(1)} dBFS',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 15,
                                color:
                                    (state.limiterThresholdDb - (-0.2)).abs() <
                                            0.05
                                        ? p.textTertiary.withValues(alpha: 0.35)
                                        : p.accent),
                            tooltip: context.l10n.dspResetToDefault02dbfs,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            onPressed:
                                (state.limiterThresholdDb - (-0.2)).abs() < 0.05
                                    ? null
                                    : () => cubit.setLookaheadLimiter(true,
                                        thresholdDb: -0.2),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Semantics(
                      slider: true,
                      label: context.l10n.ceilingThreshold,
                      child: Slider(
                        value: state.limiterThresholdDb.clamp(-6.0, 0.0),
                        min: -6.0,
                        max: 0.0,
                        divisions: 60,
                        onChanged: (val) =>
                            cubit.setLookaheadLimiter(true, thresholdDb: val),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.releaseTime,
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${state.limiterReleaseMs.round()} ms',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 15,
                                color:
                                    (state.limiterReleaseMs - 50.0).abs() < 0.5
                                        ? p.textTertiary.withValues(alpha: 0.35)
                                        : p.accent),
                            tooltip: context.l10n.dspResetToDefault50ms,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            onPressed:
                                (state.limiterReleaseMs - 50.0).abs() < 0.5
                                    ? null
                                    : () => cubit.setLookaheadLimiter(true,
                                        releaseMs: 50.0),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Semantics(
                      slider: true,
                      label: context.l10n.releaseTime,
                      child: Slider(
                        value: state.limiterReleaseMs.clamp(10.0, 200.0),
                        min: 10.0,
                        max: 200.0,
                        divisions: 38,
                        onChanged: (val) =>
                            cubit.setLookaheadLimiter(true, releaseMs: val),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Stereo Balance & Mono Mix
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.compare_arrows_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(context.l10n.stereoBalanceMono,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: p.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                        icon: Icon(Icons.info_outline_rounded,
                                            size: 16, color: p.textTertiary),
                                        visualDensity: VisualDensity.compact,
                                        tooltip: context.l10n.dspAboutStereoBalance,
                                        onPressed: () => _showFeatureInfo(
                                            context,
                                            AudioFeatureRegistry.panner,
                                            conflictReason: dspBlocked ??
                                                (_nativePcmEffectsAvailable
                                                    ? null
                                                    : 'Requires PCM DSP path - not audible yet'))),
                                  ],
                                ),
                                Text(context.l10n.panDesc,
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        Text(context.l10n.monoLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: state.monoMix
                                    ? p.accent
                                    : p.textSecondary)),
                        const SizedBox(width: 4),
                        Switch.adaptive(
                          value: dspBlocked == null &&
                              _nativePcmEffectsAvailable &&
                              state.monoMix,
                          activeTrackColor: p.accent,
                          activeThumbColor: p.onAccent,
                          onChanged:
                              dspBlocked != null || !_nativePcmEffectsAvailable
                                  ? null
                                  : (val) => cubit.setMonoMix(val),
                        ),
                      ],
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)))
                else if (!_nativePcmEffectsAvailable)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.nativeDspUnavailable,
                          style: TextStyle(
                              color: p.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('L',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: dspBlocked != null
                                ? p.textTertiary
                                : (state.stereoBalance < -0.05
                                    ? p.accent
                                    : p.textSecondary))),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dspBlocked != null
                              ? 'Blocked'
                              : (state.stereoBalance.abs() < 0.05
                                  ? 'Center'
                                  : (state.stereoBalance < 0
                                      ? 'Left ${(-state.stereoBalance * 100).round()}%'
                                      : 'Right ${(state.stereoBalance * 100).round()}%')),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: dspBlocked != null ? p.error : p.accent),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.settings_backup_restore,
                              size: 15,
                              color: dspBlocked != null ||
                                      !_nativePcmEffectsAvailable ||
                                      state.stereoBalance.abs() < 0.01
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                          tooltip: context.l10n.dspResetBalanceCenter,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 20, minHeight: 20),
                          onPressed: dspBlocked != null ||
                                  !_nativePcmEffectsAvailable ||
                                  state.stereoBalance.abs() < 0.01
                              ? null
                              : () => cubit.setStereoBalance(0.0),
                        ),
                      ],
                    ),
                    Text('R',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: dspBlocked != null
                                ? p.textTertiary
                                : (state.stereoBalance > 0.05
                                    ? p.accent
                                    : p.textSecondary))),
                  ],
                ),
                Semantics(
                  slider: true,
                  label: context.l10n.stereoBalanceMono,
                  value: state.stereoBalance.abs() < 0.05
                      ? 'Center'
                      : (state.stereoBalance < 0
                          ? 'Left ${(-state.stereoBalance * 100).round()}%'
                          : 'Right ${(state.stereoBalance * 100).round()}%'),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor:
                          dspBlocked != null ? p.textTertiary : p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor:
                          dspBlocked != null ? p.textTertiary : p.accent,
                    ),
                    child: Slider(
                      value: state.stereoBalance.clamp(-1.0, 1.0),
                      min: -1.0,
                      max: 1.0,
                      divisions: 40,
                      onChanged:
                          dspBlocked != null || !_nativePcmEffectsAvailable
                              ? null
                              : (val) => cubit.setStereoBalance(val),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Convolution Reverb & Room Acoustics
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.meeting_room_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.roomConv,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(context.l10n.irDesc,
                                  style: TextStyle(
                                      fontSize: 11, color: p.textTertiary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.info_outline_rounded,
                            size: 16, color: p.textTertiary),
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.dspAboutReverb,
                        onPressed: () => _showFeatureInfo(
                            context, AudioFeatureRegistry.reverb,
                            conflictReason: dspBlocked ??
                                (_nativePcmEffectsAvailable
                                    ? null
                                    : 'Requires PCM DSP path - not audible yet'))),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: dspBlocked == null &&
                          _nativePcmEffectsAvailable &&
                          state.isReverbEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged:
                          dspBlocked != null || !_nativePcmEffectsAvailable
                              ? null
                              : (val) => cubit.setReverb(val),
                    ),
                  ],
                ),
                if (dspBlocked != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.blockedByBitPerfectShort,
                          style: TextStyle(
                              color: p.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)))
                else if (!_nativePcmEffectsAvailable)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(context.l10n.nativeDspUnavailable,
                          style: TextStyle(
                              color: p.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600))),
                if (dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isReverbEnabled) ...[
                  const SizedBox(height: 14),
                  // Room presets chips. Ordinals are the C++ ReverbPreset
                  // enum, so the synthesized IR always matches the label.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final preset in ReverbPreset.values)
                        _buildReverbChip(preset, state.reverbPreset, cubit, p),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.wetDryMix,
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(state.reverbWetDry * 100).round()}% Wet',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 15,
                                color: (state.reverbWetDry - 0.20).abs() < 0.01
                                    ? p.textTertiary.withValues(alpha: 0.35)
                                    : p.accent),
                            tooltip: context.l10n.dspResetToDefault20wet,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            onPressed: (state.reverbWetDry - 0.20).abs() < 0.01
                                ? null
                                : () => cubit.setReverb(true, wetDry: 0.20),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: p.accent,
                      inactiveTrackColor: p.surface,
                      thumbColor: p.accent,
                    ),
                    child: Semantics(
                      slider: true,
                      label: context.l10n.wetDryMix,
                      child: Slider(
                        value: state.reverbWetDry.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) => cubit.setReverb(true, wetDry: val),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Harmonic Saturation / Exciter (Phase 1 DSP expansion)
          _buildSaturationCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 4. Stereo Width — Mid/Side (Phase 1 DSP expansion)
          _buildStereoWidthCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 5. Subwoofer Crossover — bass redirection (Phase 1 DSP expansion)
          _buildSubCrossoverCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // Dynamic Bass (Dynamic System / ViPER4Android parity)
          _buildDynamicBassCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 6. Dynamic EQ (Phase 1 DSP expansion)
          _buildDynamicEqCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 7. Loudness Contour (Fletcher-Munson) — previously persisted with
          // no reachable control.
          _buildLoudnessContourCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 8. TPDF Dither — previously persisted with no reachable control.
          _buildDitherCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 9. Sinc Resampler — previously persisted with no reachable control.
          _buildSincResamplerCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 10. ViPER-DDC Headphone Correction (JamesDSP parity)
          _buildViperDdcCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 11. Arbitrary Response EQ / GraphicEq (JamesDSP parity)
          _buildArbitraryEqCard(context, state, cubit, dspBlocked, p),
          const SizedBox(height: 16),

          // 12. Live Programmable DSP / EEL VM (JamesDSP parity)
          _buildLiveProgCard(context, state, cubit, dspBlocked, p),
        ],
      ),
    );
  }

  Widget _buildReverbChip(ReverbPreset preset, int currentPreset,
      PlayerCubit cubit, PulsrPalette p) {
    final isSelected = preset.wireValue == currentPreset;
    if (preset == ReverbPreset.custom) {
      return ActionChip(
        avatar: Icon(Icons.file_upload_outlined,
            size: 14, color: isSelected ? p.accent : p.textSecondary),
        label: Text(isSelected ? 'Custom (Loaded)' : 'Load WAV IR...'),
        backgroundColor:
            isSelected ? p.accent.withValues(alpha: 0.22) : p.surface,
        side: BorderSide(color: isSelected ? p.accent : p.hairline),
        labelStyle: TextStyle(
          color: isSelected ? p.accent : p.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        onPressed: () => cubit.pickAndLoadCustomIrFile(),
      );
    }
    return ChoiceChip(
      label: Text(preset.label),
      selected: isSelected,
      selectedColor: p.accent.withValues(alpha: 0.22),
      backgroundColor: p.surface,
      side: BorderSide(
        color: isSelected ? p.accent : p.hairline,
      ),
      labelStyle: TextStyle(
        color: isSelected ? p.accent : p.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: 11,
      ),
      onSelected: (_) => cubit.setReverb(true, preset: preset.wireValue),
    );
  }

  // ---- Phase 1 DSP expansion cards ----

  /// Shared label/value header + slider row used by the expansion cards,
  /// matching the visual style of the Crossfeed/Limiter sliders above.
  Widget _buildDspSliderRow({
    required BuildContext context,
    required PulsrPalette p,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    double? defaultValue,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    final isDefault =
        defaultValue != null && (value - defaultValue).abs() < 0.001;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valueText,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.accent)),
                if (defaultValue != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.settings_backup_restore,
                        size: 15,
                        color: isDefault
                            ? p.textTertiary.withValues(alpha: 0.35)
                            : p.accent),
                    tooltip: context.l10n.dspResetToDefault,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    onPressed: isDefault ? null : () => onChanged(defaultValue),
                  ),
                ],
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: p.accent,
            inactiveTrackColor: p.surface,
            thumbColor: p.accent,
          ),
          child: Semantics(
            slider: true,
            label: label,
            value: valueText,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaturationCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.waves_rounded, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspSaturationTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspSaturationSubtitle,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.dspSaturationTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.saturation,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : 'Requires PCM DSP path - not audible yet'))),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isSaturationEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setSaturation(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isSaturationEnabled) ...[
            const SizedBox(height: 14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSaturationDrive,
              valueText: '${(state.saturationDrive * 100).round()}%',
              value: state.saturationDrive,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.3,
              divisions: 20,
              onChanged: (val) => cubit.setSaturation(true, drive: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSaturationMix,
              valueText: '${(state.saturationMix * 100).round()}% Wet',
              value: state.saturationMix,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.5,
              divisions: 20,
              onChanged: (val) => cubit.setSaturation(true, mix: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSaturationTilt,
              valueText: '${(state.saturationTilt * 100).round()}%',
              value: state.saturationTilt,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.3,
              divisions: 20,
              onChanged: (val) => cubit.setSaturation(true, tilt: val),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.multibandWarmth,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(context.l10n.saturationBandDesc,
                      style: TextStyle(fontSize: 10, color: p.textTertiary),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: state.saturationMultiband,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) => cubit.setSaturationMultiband(val),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStereoWidthCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.compare_arrows_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspStereoWidthTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspStereoWidthSubtitle,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.dspStereoWidthTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.stereoWidth,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : 'Requires PCM DSP path - not audible yet'))),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isStereoWidthEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setStereoWidth(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isStereoWidthEnabled) ...[
            const SizedBox(height: 14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspStereoWidthAmount,
              valueText: state.stereoWidth.toStringAsFixed(2),
              value: state.stereoWidth,
              min: 0.0,
              max: 2.0,
              defaultValue: 1.0,
              divisions: 40,
              onChanged: (val) => cubit.setStereoWidth(true, width: val),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.dspMultibandLabel,
                    style: TextStyle(fontSize: 12, color: p.textSecondary)),
                Switch.adaptive(
                  value: state.stereoWidthMultiband,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) =>
                      cubit.setStereoWidth(true, multiband: val),
                ),
              ],
            ),
            if (state.stereoWidthMultiband) ...[
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.dspBandLow,
                valueText: state.stereoWidthLow.toStringAsFixed(2),
                value: state.stereoWidthLow,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                divisions: 40,
                onChanged: (val) =>
                    cubit.setStereoWidth(true, lowWidth: val),
              ),
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.dspBandMid,
                valueText: state.stereoWidthMid.toStringAsFixed(2),
                value: state.stereoWidthMid,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                divisions: 40,
                onChanged: (val) =>
                    cubit.setStereoWidth(true, midWidth: val),
              ),
              _buildDspSliderRow(
                context: context,
                p: p,
                label: context.l10n.dspBandHigh,
                valueText: state.stereoWidthHigh.toStringAsFixed(2),
                value: state.stereoWidthHigh,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                divisions: 40,
                onChanged: (val) =>
                    cubit.setStereoWidth(true, highWidth: val),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubCrossoverCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.speaker_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspSubCrossoverTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspSubCrossoverSubtitle,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.dspSubCrossoverTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.subCrossover,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : 'Requires PCM DSP path - not audible yet'))),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isSubCrossoverEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setSubCrossover(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isSubCrossoverEnabled) ...[
            const SizedBox(height: 14),
            // Honest copy: this is bass redirection, not multichannel LFE.
            Text(l10n.dspSubCrossoverNote,
                style: TextStyle(fontSize: 10, color: p.textTertiary)),
            const SizedBox(height: 10),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSubCrossoverCorner,
              valueText: '${state.subCrossoverCornerHz.round()} Hz',
              value: state.subCrossoverCornerHz,
              min: 60.0,
              max: 150.0,
              defaultValue: 80.0,
              divisions: 18,
              onChanged: (val) => cubit.setSubCrossover(true, cornerHz: val),
            ),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: l10n.dspSubCrossoverSubLevel,
              valueText: '${(state.subCrossoverGain * 100).round()}%',
              value: state.subCrossoverGain,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.8,
              divisions: 20,
              onChanged: (val) => cubit.setSubCrossover(true, gain: val),
            ),
            SwitchListTile.adaptive(
              title: Text(context.l10n.bassMono, style: TextStyle(fontSize: 14)),
              subtitle: Text(context.l10n.bassMonoDesc,
                  style: TextStyle(fontSize: 11, color: p.textTertiary)),
              value: state.subCrossoverBassMono,
              activeThumbColor: p.onAccent,
              activeTrackColor: p.accent,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => cubit.setSubCrossover(
                true,
                cornerHz: state.subCrossoverCornerHz,
                slopeDbPerOct: state.subCrossoverSlopeDbPerOct,
                gain: state.subCrossoverGain,
                bassMono: v,
                antiPop: state.subCrossoverAntiPop,
              ),
            ),
            SwitchListTile.adaptive(
              title: Text(context.l10n.antiPop, style: TextStyle(fontSize: 14)),
              subtitle: Text(context.l10n.antiPopDesc,
                  style: TextStyle(fontSize: 11, color: p.textTertiary)),
              value: state.subCrossoverAntiPop,
              activeThumbColor: p.onAccent,
              activeTrackColor: p.accent,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => cubit.setSubCrossover(
                true,
                cornerHz: state.subCrossoverCornerHz,
                slopeDbPerOct: state.subCrossoverSlopeDbPerOct,
                gain: state.subCrossoverGain,
                bassMono: state.subCrossoverBassMono,
                antiPop: v,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicEqCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.graphic_eq_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.dspDynamicEqTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(l10n.dspDynamicEqSubtitle,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.dspDynamicEqTitle,
                  onPressed: () => _showFeatureInfo(
                      context, AudioFeatureRegistry.dynamicEq,
                      conflictReason: dspBlocked ??
                          (_nativePcmEffectsAvailable
                              ? null
                              : 'Requires PCM DSP path - not audible yet'))),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isDynamicEqEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setDynamicEq(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isDynamicEqEnabled) ...[
            const SizedBox(height: 14),
            for (int i = 0; i < state.dynamicEqBands.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _buildDynamicEqBandSection(context, state.dynamicEqBands[i], i, cubit, p),
            ],
            if (state.dynamicEqBands.length < 8) ...[
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => cubit.addDynamicEqBand(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.l10n.addBand),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: p.surfaceContainerHigh,
                    foregroundColor: p.textPrimary,
                  ),
                ),
              ),
            ]
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicEqBandSection(BuildContext context, DynamicEqBandConfig band,
      int index, PlayerCubit cubit, PulsrPalette p) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        collapsedBackgroundColor: p.surfaceContainerHigh,
        backgroundColor: p.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(context.l10n.eqBandLabel(index + 1),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: band.enabled ? p.textPrimary : p.textTertiary)),
        leading: Switch.adaptive(
          value: band.enabled,
          activeTrackColor: p.accent,
          onChanged: (val) =>
              cubit.setDynamicEqBand(index, band.copyWith(enabled: val)),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, size: 18, color: p.error),
          onPressed: () => cubit.removeDynamicEqBand(index),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode Toggle
                Row(
                  children: [
                    Text('${context.l10n.modeLabel}:', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 0, label: Text(context.l10n.cutAction)),
                          ButtonSegment(value: 1, label: Text(context.l10n.boostAction)),
                        ],
                        selected: {band.mode},
                        onSelectionChanged: (Set<int> newSelection) {
                          cubit.setDynamicEqBand(index, band.copyWith(mode: newSelection.first));
                        },
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: p.surfaceContainer,
                          selectedBackgroundColor: p.accent.withValues(alpha: 0.2),
                          selectedForegroundColor: p.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Filter Type Dropdown
                Row(
                  children: [
                    Text('${context.l10n.filterLabel}:', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: band.filterType,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          DropdownMenuItem(value: 0, child: Text(context.l10n.peakingFilter)),
                          DropdownMenuItem(value: 1, child: Text(context.l10n.lowShelfFilter)),
                          DropdownMenuItem(value: 2, child: Text(context.l10n.highShelfFilter)),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            cubit.setDynamicEqBand(index, band.copyWith(filterType: val));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqFrequency,
                  valueText: '${band.frequency.round()} Hz',
                  value: band.frequency,
                  min: 60.0,
                  max: 12000.0,
                  defaultValue: 1000.0,
                  divisions: 64,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(frequency: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: context.l10n.dspQBandwidth,
                  valueText: band.q.toStringAsFixed(2),
                  value: band.q,
                  min: 0.5,
                  max: 8.0,
                  defaultValue: 2.0,
                  divisions: 75,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(q: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqThreshold,
                  valueText: '${band.thresholdDb.toStringAsFixed(0)} dB',
                  value: band.thresholdDb,
                  min: -60.0,
                  max: 0.0,
                  defaultValue: -30.0,
                  divisions: 60,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(thresholdDb: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqRatio,
                  valueText: '${band.ratio.toStringAsFixed(1)} : 1',
                  value: band.ratio,
                  min: 1.0,
                  max: 8.0,
                  defaultValue: 3.0,
                  divisions: 35,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(ratio: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqAttack,
                  valueText: '${band.attackMs.toStringAsFixed(1)} ms',
                  value: band.attackMs,
                  min: 0.1,
                  max: 50.0,
                  defaultValue: 5.0,
                  divisions: 50,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(attackMs: val)),
                ),
                _buildDspSliderRow(
                  context: context,
                  p: p,
                  label: l10n.dspDynamicEqRelease,
                  valueText: '${band.releaseMs.round()} ms',
                  value: band.releaseMs,
                  min: 20.0,
                  max: 1000.0,
                  defaultValue: 120.0,
                  divisions: 49,
                  onChanged: (val) =>
                      cubit.setDynamicEqBand(index, band.copyWith(releaseMs: val)),
                ),
                if (band.mode == 0)
                  _buildDspSliderRow(
                    context: context,
                    p: p,
                    label: l10n.dspDynamicEqMaxCut,
                    valueText: '${band.maxCutDb.toStringAsFixed(0)} dB',
                    value: band.maxCutDb,
                    min: -24.0,
                    max: 0.0,
                    defaultValue: -12.0,
                    divisions: 24,
                    onChanged: (val) =>
                        cubit.setDynamicEqBand(index, band.copyWith(maxCutDb: val)),
                  ),
                if (band.mode == 1)
                  _buildDspSliderRow(
                    context: context,
                    p: p,
                    label: context.l10n.dspMaxBoost,
                    valueText: '${band.maxBoostDb.toStringAsFixed(0)} dB',
                    value: band.maxBoostDb,
                    min: 0.0,
                    max: 24.0,
                    defaultValue: 12.0,
                    divisions: 24,
                    onChanged: (val) =>
                        cubit.setDynamicEqBand(index, band.copyWith(maxBoostDb: val)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Loudness Contour (Fletcher-Munson). Previously persisted state with no
  /// reachable control; the dead AudioSoundSection was its only renderer.
  Widget _buildLoudnessContourCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final available = dspBlocked == null && _nativePcmEffectsAvailable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.volume_up_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.loudnessContour,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(context.l10n.loudnessContourDesc,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: available && state.isLoudnessContourEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged:
                    !available ? null : (val) => cubit.setLoudnessContour(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)))
          else if (!_nativePcmEffectsAvailable)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.l10n.nativeDspUnavailable,
                    style: TextStyle(
                        color: p.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          if (available && state.isLoudnessContourEnabled) ...[
            const SizedBox(height: 14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.dspLoudnessIntensity,
              valueText: '${(state.loudnessContourIntensity * 100).round()}%',
              value: state.loudnessContourIntensity,
              min: 0.0,
              max: 1.0,
              defaultValue: 0.0,
              divisions: 20,
              onChanged: (val) =>
                  cubit.setLoudnessContour(true, intensity: val),
            ),
          ],
        ],
      ),
    );
  }

  /// TPDF Dither with a 16/24/32-bit target. Previously persisted with no
  /// reachable control.
  Widget _buildDitherCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final available = dspBlocked == null && _nativePcmEffectsAvailable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.grain_rounded, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.tpdfDither,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(context.l10n.ditherDesc,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: available && state.isDitherEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: !available ? null : (val) => cubit.setDither(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)))
          else if (!_nativePcmEffectsAvailable)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.l10n.nativeDspUnavailable,
                    style: TextStyle(
                        color: p.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
          if (available && state.isDitherEnabled) ...[
            const SizedBox(height: 14),
            Text(context.l10n.targetBitDepth,
                style: TextStyle(
                    fontSize: 12,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final bits in const [16, 24, 32])
                  ChoiceChip(
                    label: Text('$bits-bit'),
                    selected: state.ditherTargetBitDepth == bits,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surface,
                    side: BorderSide(
                      color: state.ditherTargetBitDepth == bits
                          ? p.accent
                          : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      color: state.ditherTargetBitDepth == bits
                          ? p.accent
                          : p.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    onSelected: (_) =>
                        cubit.setDither(true, targetBitDepth: bits),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Sinc Resampler toggle (auto-bypasses when track and device rates match).
  Widget _buildSincResamplerCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final available = dspBlocked == null && _nativePcmEffectsAvailable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.sync_alt_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.sincResampler,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(context.l10n.sincDesc,
                              style: TextStyle(
                                  fontSize: 11, color: p.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: available && state.isSincResamplerEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged:
                    !available ? null : (val) => cubit.setSincResampler(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.l10n.blockedByBitPerfectShort,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)))
          else if (!_nativePcmEffectsAvailable)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.l10n.nativeDspUnavailable,
                    style: TextStyle(
                        color: p.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildHardwareDeviceProfileBar(BuildContext context, PlayerCubit cubit,
      PlayerState state, PulsrPalette p) {
    final output = context.watch<SettingsCubit?>()?.state.currentOutputDevice;
    final devType = output?.activeDeviceType.toLowerCase() ?? '';
    final devName = (output?.deviceName ?? '').toLowerCase();

    final isUsb =
        output?.isUsbDac == true || devType == 'usb' || devName.contains('usb');
    final isBt = output?.isBluetooth == true ||
        devType == 'bluetooth' ||
        devType == 'ble' ||
        devName.contains('bluetooth');
    final isWired = devType == 'wired' ||
        devName.contains('headphone') ||
        devName.contains('headset');
    final isSpeaker = (!isUsb && !isBt && !isWired) ||
        devType == 'builtin' ||
        devName.contains('speaker');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildDeviceTypeChip(
            label: context.l10n.dspHeadset,
            icon: Icons.headphones_rounded,
            isActive: isWired,
            p: p,
            onTap: () {
              if (state.currentSong != null) {
                AudioQualitySheet.show(context, state.currentSong!, p.accent);
              }
            },
          ),
          _buildDeviceTypeChip(
            label: context.l10n.dspSpeaker,
            icon: Icons.volume_up_rounded,
            isActive: isSpeaker,
            p: p,
            onTap: () {
              if (state.currentSong != null) {
                AudioQualitySheet.show(context, state.currentSong!, p.accent);
              }
            },
          ),
          _buildDeviceTypeChip(
            label: 'Bluetooth',
            icon: Icons.bluetooth_audio_rounded,
            isActive: isBt,
            p: p,
            onTap: () {
              if (state.currentSong != null) {
                AudioQualitySheet.show(context, state.currentSong!, p.accent);
              }
            },
          ),
          _buildDeviceTypeChip(
            label: 'USB DAC',
            icon: Icons.album_rounded,
            isActive: isUsb,
            p: p,
            onTap: () {
              if (state.currentSong != null) {
                AudioQualitySheet.show(context, state.currentSong!, p.accent);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTypeChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required PulsrPalette p,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: context.motionMs(200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              isActive ? p.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? p.accent : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? p.accent : p.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? p.accent : p.textSecondary,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViperDdcCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    final hasProfile = state.viperDdcProfileName.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.headphones_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AudioFeatureRegistry.viperDdc.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            hasProfile
                                ? state.viperDdcProfileName
                                : AudioFeatureRegistry.viperDdc.subtitle,
                            style:
                                TextStyle(fontSize: 11, color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                visualDensity: VisualDensity.compact,
                tooltip: AudioFeatureRegistry.viperDdc.title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.viperDdc,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : 'Requires PCM DSP path - not audible yet'),
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isViperDdcEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setViperDdcEnabled(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isViperDdcEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: Text(
                hasProfile
                    ? 'Change Profile: ${state.viperDdcProfileName}'
                    : 'Select / Load .vdc Profile...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () {
                PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const ViperDdcSheet(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArbitraryEqCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.auto_graph_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AudioFeatureRegistry.arbitraryEq.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            AudioFeatureRegistry.arbitraryEq.subtitle,
                            style:
                                TextStyle(fontSize: 11, color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                visualDensity: VisualDensity.compact,
                tooltip: AudioFeatureRegistry.arbitraryEq.title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.arbitraryEq,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : 'Requires PCM DSP path - not audible yet'),
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isArbitraryEqEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setArbitraryEqEnabled(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isArbitraryEqEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: Text(context.l10n.editGraphicEq,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () {
                PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const ArbitraryEqSheet(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveProgCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.code_rounded, color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AudioFeatureRegistry.liveProg.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            state.liveProgStatus.isNotEmpty
                                ? state.liveProgStatus
                                : AudioFeatureRegistry.liveProg.subtitle,
                            style:
                                TextStyle(fontSize: 11, color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                visualDensity: VisualDensity.compact,
                tooltip: AudioFeatureRegistry.liveProg.title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.liveProg,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : 'Requires PCM DSP path - not audible yet'),
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isLiveProgEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setLiveProgEnabled(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isLiveProgEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.terminal_rounded, size: 16),
              label: Text(context.l10n.openEelEditor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () {
                PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const LiveProgSheet(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicBassCard(BuildContext context, PlayerState state,
      PlayerCubit cubit, String? dspBlocked, PulsrPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.speaker_group_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AudioFeatureRegistry.dynamicBass.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                            AudioFeatureRegistry.dynamicBass.subtitle,
                            style:
                                TextStyle(fontSize: 11, color: p.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded,
                    size: 16, color: p.textTertiary),
                visualDensity: VisualDensity.compact,
                tooltip: AudioFeatureRegistry.dynamicBass.title,
                onPressed: () => _showFeatureInfo(
                  context,
                  AudioFeatureRegistry.dynamicBass,
                  conflictReason: dspBlocked ??
                      (_nativePcmEffectsAvailable
                          ? null
                          : 'Requires PCM DSP path - not audible yet'),
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: dspBlocked == null &&
                    _nativePcmEffectsAvailable &&
                    state.isDynamicBassEnabled,
                activeTrackColor: p.accent,
                activeThumbColor: p.onAccent,
                onChanged: dspBlocked != null || !_nativePcmEffectsAvailable
                    ? null
                    : (val) => cubit.setDynamicBass(val),
              ),
            ],
          ),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                style: TextStyle(
                    color: p.error, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            )
          else if (!_nativePcmEffectsAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.nativeDspUnavailable,
                style: TextStyle(
                    color: p.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (dspBlocked == null &&
              _nativePcmEffectsAvailable &&
              state.isDynamicBassEnabled) ...[
            const SizedBox(height: 14),
            _buildDspSliderRow(
              context: context,
              p: p,
              label: context.l10n.dspBassStrength,
              valueText: '${(state.dynamicBassStrength * 100).round()}%',
              value: state.dynamicBassStrength.clamp(1.0, 8.0),
              min: 1.0,
              max: 8.0,
              defaultValue: 1.0,
              divisions: 70,
              onChanged: (val) => cubit.setDynamicBass(true, strength: val),
            ),
            const SizedBox(height: 12),
            Text(context.l10n.acousticCalibModel,
              style: TextStyle(
                fontSize: 12,
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(context.l10n.neutralCustom),
                    selected: state.dynamicBassPreset == 0,
                    selectedColor: p.accent.withValues(alpha: 0.22),
                    backgroundColor: p.surface,
                    side: BorderSide(
                      color:
                          state.dynamicBassPreset == 0 ? p.accent : p.hairline,
                    ),
                    labelStyle: TextStyle(
                      color: state.dynamicBassPreset == 0
                          ? p.accent
                          : p.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    onSelected: (_) => cubit.setDynamicBass(
                      true,
                      preset: 0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final item in DynamicBassConfig.builtinPresets) ...[
                    ChoiceChip(
                      label: Text(item.name),
                      selected: state.dynamicBassPreset == item.id,
                      selectedColor: p.accent.withValues(alpha: 0.22),
                      backgroundColor: p.surface,
                      side: BorderSide(
                        color: state.dynamicBassPreset == item.id
                            ? p.accent
                            : p.hairline,
                      ),
                      labelStyle: TextStyle(
                        color: state.dynamicBassPreset == item.id
                            ? p.accent
                            : p.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      onSelected: (_) => cubit.setDynamicBass(
                        true,
                        preset: item.id,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerticalEqSlider extends StatefulWidget {
  final double value;
  final bool isEnabled;
  final String label;
  final Color accentColor;
  final Color trackColor;
  final Color surfaceColor;
  final Color textColor;
  final ValueChanged<double> onChanged;
  final VoidCallback? onInteraction;

  static const double min = -15.0;
  static const double max = 15.0;

  const _VerticalEqSlider({
    required this.value,
    required this.isEnabled,
    required this.label,
    required this.accentColor,
    required this.trackColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onChanged,
    this.onInteraction,
  });

  @override
  State<_VerticalEqSlider> createState() => _VerticalEqSliderState();
}

class _VerticalEqSliderState extends State<_VerticalEqSlider> {
  bool _isDragging = false;
  double? _dragGain;

  void _handlePointer(double localY, double totalHeight,
      {bool notifyParent = false}) {
    widget.onInteraction?.call();
    const topMargin = 12.0;
    const bottomMargin = 12.0;
    final trackHeight = totalHeight - topMargin - bottomMargin;
    if (trackHeight <= 0) return;
    final clampedY = (localY - topMargin).clamp(0.0, trackHeight);
    final fraction = 1.0 - (clampedY / trackHeight);
    final newGain = _VerticalEqSlider.min +
        fraction * (_VerticalEqSlider.max - _VerticalEqSlider.min);
    final roundedGain = double.parse(newGain.toStringAsFixed(1));
    setState(() {
      _dragGain = roundedGain;
    });
    if (notifyParent) {
      widget.onChanged(roundedGain);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gain = (_isDragging && _dragGain != null ? _dragGain! : widget.value)
        .clamp(_VerticalEqSlider.min, _VerticalEqSlider.max);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Value Pill
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (gain.abs() > 0.1 ? widget.accentColor : widget.trackColor)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 10,
                color: gain.abs() > 0.1 ? widget.accentColor : widget.textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Vertical Slider Track
        SizedBox(
          height: 140,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              const topMargin = 12.0;
              const bottomMargin = 12.0;
              final trackHeight = height - topMargin - bottomMargin;
              final fraction = (gain - _VerticalEqSlider.min) /
                  (_VerticalEqSlider.max - _VerticalEqSlider.min);
              final thumbY = topMargin + (1.0 - fraction) * trackHeight;
              final centerY = topMargin + trackHeight / 2;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (details) {
                  setState(() => _isDragging = true);
                  _handlePointer(details.localPosition.dy, height,
                      notifyParent: true);
                },
                onVerticalDragUpdate: (details) {
                  _handlePointer(details.localPosition.dy, height,
                      notifyParent: true);
                },
                onVerticalDragEnd: (_) {
                  final finalGain = _dragGain ?? widget.value;
                  widget.onChanged(finalGain);
                  setState(() {
                    _isDragging = false;
                    _dragGain = null;
                  });
                },
                onVerticalDragCancel: () {
                  setState(() {
                    _isDragging = false;
                    _dragGain = null;
                  });
                },
                onTapDown: (details) {
                  _handlePointer(details.localPosition.dy, height,
                      notifyParent: true);
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: _VerticalSliderPainter(
                    fraction: fraction,
                    thumbY: thumbY,
                    centerY: centerY,
                    topMargin: topMargin,
                    bottomMargin: bottomMargin,
                    isDragging: _isDragging,
                    isEnabled: widget.isEnabled,
                    accentColor: widget.accentColor,
                    trackColor: widget.trackColor,
                    surfaceColor: widget.surfaceColor,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Frequency Label + Modification Indicator Dot
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.textColor,
                ),
              ),
              if (gain.abs() > 0.1)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerticalSliderPainter extends CustomPainter {
  final double fraction;
  final double thumbY;
  final double centerY;
  final double topMargin;
  final double bottomMargin;
  final bool isDragging;
  final bool isEnabled;
  final Color accentColor;
  final Color trackColor;
  final Color surfaceColor;

  _VerticalSliderPainter({
    required this.fraction,
    required this.thumbY,
    required this.centerY,
    required this.topMargin,
    required this.bottomMargin,
    required this.isDragging,
    required this.isEnabled,
    required this.accentColor,
    required this.trackColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final trackTop = topMargin;
    final trackBottom = size.height - bottomMargin;

    // Background track (Pill)
    final bgPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.35)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    canvas.drawLine(
      Offset(centerX, trackTop),
      Offset(centerX, trackBottom),
      bgPaint,
    );

    // Center 0 dB notch tick
    final notchPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(centerX - 6, centerY),
      Offset(centerX + 6, centerY),
      notchPaint,
    );

    // Active fill from center (0dB) to thumbY
    final activePaint = Paint()
      ..color = isEnabled ? accentColor : trackColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX, thumbY),
      activePaint,
    );

    // Thumb Glow / Halo when dragging
    if (isDragging && isEnabled) {
      final haloPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, thumbY), 16.0, haloPaint);
    }

    // Thumb Outer Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawCircle(
        Offset(centerX, thumbY + 1), isDragging ? 9.0 : 8.0, shadowPaint);

    // Thumb Main Circle
    final thumbPaint = Paint()
      ..color = isEnabled ? accentColor : trackColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(centerX, thumbY), isDragging ? 9.0 : 8.0, thumbPaint);

    // Thumb Inner Core
    final corePaint = Paint()
      ..color = isEnabled ? Colors.white : surfaceColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(centerX, thumbY), isDragging ? 3.5 : 3.0, corePaint);
  }

  @override
  bool shouldRepaint(covariant _VerticalSliderPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.thumbY != thumbY ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.accentColor != accentColor;
  }
}
