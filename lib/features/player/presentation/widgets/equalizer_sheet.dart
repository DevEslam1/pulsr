// lib/features/player/presentation/widgets/equalizer_sheet.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/responsive/pulsr_layout_metrics.dart';
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
import '../../../../domain/models/audio_output_info.dart';
import '../../cubit/player_cubit.dart';
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
import '../../../settings/cubit/settings_state.dart';
import '../../../settings/presentation/widgets/room_correction_sheet.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

part 'eq_sheet_shell.dart';
part 'eq_band_slider_column.dart';
part 'eq_preset_carousel.dart';
part 'eq_advanced_controls.dart';
part 'eq_ab_compare_bar.dart';

// Rebuild gate for the whole DSP sheet (F-01 / C-01 / H2).
//
// B4/F-10: `a.dsp != b.dsp` is *not* safe here. EqPreset does not implement
// value equality, so any gains-only tick (which constructs a fresh 'Custom'
// EqPreset) would rebuild the entire 3-tab sheet on every drag frame. Gains are
// consumed exclusively by the per-band BlocSelectors and the curve selector, so
// this gate compares every other DspSlice field explicitly and ignores gains.
bool dspSheetRebuildGate(PlayerState a, PlayerState b) {
  if (identical(a, b)) return false;
  if (a.errorMessage != b.errorMessage) return true;
  if (a.currentSong?.id != b.currentSong?.id) return true;
  final x = a.dsp;
  final y = b.dsp;
  if (identical(x, y)) return false;
  return !_eqPresetRebuildEquals(x.eqPreset, y.eqPreset) ||
      x.isEqEnabled != y.isEqEnabled ||
      x.isVirtualizerEnabled != y.isVirtualizerEnabled ||
      x.virtualizerStrength != y.virtualizerStrength ||
      x.isVirtualizerSupported != y.isVirtualizerSupported ||
      x.isDynamicsEnabled != y.isDynamicsEnabled ||
      x.isDynamicsSupported != y.isDynamicsSupported ||
      x.dynamicsPreset != y.dynamicsPreset ||
      x.selectedHeadphoneProfile != y.selectedHeadphoneProfile ||
      x.isSpatializerSupported != y.isSpatializerSupported ||
      x.isSpatializerEnabled != y.isSpatializerEnabled ||
      x.volumeBoost != y.volumeBoost ||
      x.isVolumeBoostSupported != y.isVolumeBoostSupported ||
      x.isBassBoostSupported != y.isBassBoostSupported ||
      x.isCrossfeedEnabled != y.isCrossfeedEnabled ||
      x.crossfeedDelayUs != y.crossfeedDelayUs ||
      x.crossfeedFeedDb != y.crossfeedFeedDb ||
      x.crossfeedMode != y.crossfeedMode ||
      x.isLimiterEnabled != y.isLimiterEnabled ||
      x.limiterThresholdDb != y.limiterThresholdDb ||
      x.limiterReleaseMs != y.limiterReleaseMs ||
      x.isReverbEnabled != y.isReverbEnabled ||
      x.reverbPreset != y.reverbPreset ||
      x.reverbWetDry != y.reverbWetDry ||
      x.stereoBalance != y.stereoBalance ||
      x.monoMix != y.monoMix ||
      x.isSincResamplerEnabled != y.isSincResamplerEnabled ||
      x.isDitherEnabled != y.isDitherEnabled ||
      x.ditherTargetBitDepth != y.ditherTargetBitDepth ||
      x.isSaturationEnabled != y.isSaturationEnabled ||
      x.saturationDrive != y.saturationDrive ||
      x.saturationMix != y.saturationMix ||
      x.saturationTilt != y.saturationTilt ||
      x.saturationMultiband != y.saturationMultiband ||
      x.isStereoWidthEnabled != y.isStereoWidthEnabled ||
      x.stereoWidth != y.stereoWidth ||
      x.isLoudnessContourEnabled != y.isLoudnessContourEnabled ||
      x.loudnessContourIntensity != y.loudnessContourIntensity ||
      x.isSubCrossoverEnabled != y.isSubCrossoverEnabled ||
      x.subCrossoverCornerHz != y.subCrossoverCornerHz ||
      x.subCrossoverSlopeDbPerOct != y.subCrossoverSlopeDbPerOct ||
      x.subCrossoverGain != y.subCrossoverGain ||
      x.subCrossoverBassMono != y.subCrossoverBassMono ||
      x.subCrossoverAntiPop != y.subCrossoverAntiPop ||
      x.stereoWidthMultiband != y.stereoWidthMultiband ||
      x.stereoWidthLow != y.stereoWidthLow ||
      x.stereoWidthMid != y.stereoWidthMid ||
      x.stereoWidthHigh != y.stereoWidthHigh ||
      x.stereoWidthLowCrossoverHz != y.stereoWidthLowCrossoverHz ||
      x.stereoWidthHighCrossoverHz != y.stereoWidthHighCrossoverHz ||
      x.multibandCompressorF0 != y.multibandCompressorF0 ||
      x.multibandCompressorF1 != y.multibandCompressorF1 ||
      x.multibandCompressorF2 != y.multibandCompressorF2 ||
      x.isDynamicEqEnabled != y.isDynamicEqEnabled ||
      !listEquals(x.dynamicEqBands, y.dynamicEqBands) ||
      x.isViperDdcEnabled != y.isViperDdcEnabled ||
      x.viperDdcProfileName != y.viperDdcProfileName ||
      x.isArbitraryEqEnabled != y.isArbitraryEqEnabled ||
      x.arbitraryEqString != y.arbitraryEqString ||
      x.isLiveProgEnabled != y.isLiveProgEnabled ||
      x.liveProgCode != y.liveProgCode ||
      x.liveProgStatus != y.liveProgStatus ||
      x.isDynamicBassEnabled != y.isDynamicBassEnabled ||
      x.dynamicBassStrength != y.dynamicBassStrength ||
      x.dynamicBassPreset != y.dynamicBassPreset ||
      x.hasOemAudio != y.hasOemAudio ||
      !listEquals(x.detectedOemEngines, y.detectedOemEngines) ||
      x.isQuranModeEnabled != y.isQuranModeEnabled ||
      x.quranReciterStyle != y.quranReciterStyle;
}

/// Compares every [EqPreset] field except `gains` (the high-frequency field
/// consumed by per-band selectors).
bool _eqPresetRebuildEquals(EqPreset x, EqPreset y) {
  if (identical(x, y)) return true;
  return x.name == y.name &&
      x.bassBoost == y.bassBoost &&
      listEquals(x.customFrequencies, y.customFrequencies) &&
      listEquals(x.qFactors, y.qFactors) &&
      mapEquals(x.bandsMap, y.bandsMap);
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
  Timer? _abCompareTimer;
  bool? _isStudioModeOverride;

  /// F-35: per-band solo/mute are push-to-native only (the engine exposes no
  /// getter), so the sheet owns the transient UI state. Cleared on a band-count
  /// switch because the indices then refer to a different frequency plan.
  final Set<int> _mutedBands = <int>{};
  final Set<int> _soloedBands = <int>{};

  EqualizerManager? _cachedEqualizerManager;

  @override
  void initState() {
    super.initState();
    try {
      _cachedEqualizerManager = getIt.isRegistered<EqualizerManager>()
          ? getIt<EqualizerManager>()
          : null;
    } catch (_) {
      _cachedEqualizerManager = null;
    }
    _tabController = TabController(length: 3, vsync: this);
    _loadHeadphoneProfiles();
    _listenForDspAutoDegrade();
  }

  @override
  void dispose() {
    _abCompareTimer?.cancel();
    _abCompareTimer = null;
    _degradedSessionSub?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _setStateSafe(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (!Platform.isAndroid) {
      return Material(
        color: p.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadii.r24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s20, AppSpacing.md, AppSpacing.s20, AppSpacing.xl),
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
                      borderRadius: AppRadii.r2All,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Icon(Icons.equalizer_rounded, color: p.textTertiary, size: 48),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.hwFxUnavailable,
                  style: TextStyle(
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.hwFxDesc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.bodySmall),
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
                maxWidth: context.isLandscape
                    ? math.min(MediaQuery.sizeOf(context).width * 0.94, 760.0)
                    : Adaptive.sheetConstraints(context).maxWidth,
                maxHeight: MediaQuery.sizeOf(context).height *
                    (context.isLandscape ? 0.95 : 0.84),
              ),
              child: Material(
                color: p.surface,
                borderRadius: context.isLandscape
                    ? AppRadii.r24All
                    : const BorderRadius.vertical(
                        top: Radius.circular(AppRadii.r28)),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: context.isLandscape
                      ? _buildLandscapeLayout(
                          context,
                          cubit,
                          state,
                          p,
                          dspBlockedGlobal,
                          isStudio,
                        )
                      : _buildPortraitLayout(
                          context,
                          cubit,
                          state,
                          p,
                          dspBlockedGlobal,
                          isStudio,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
