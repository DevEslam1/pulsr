// lib/features/player/presentation/widgets/equalizer_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'dart:async';

import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../data/audio/equalizer_manager.dart';
import 'eq_curve_visualizer.dart';
import 'autoeq_search_sheet.dart';
import 'compressor_limiter_sheet.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../settings/cubit/settings_cubit.dart';

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

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

  static const List<String> _bandLabels = [
    '32',
    '64',
    '125',
    '250',
    '500',
    '1K',
    '2K',
    '4K',
    '8K',
    '16K'
  ];

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
      _degradedSessionSub = AudioEffectsChannel().onAutoDegradedSessionStarted.listen(
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
      );
    } catch (_) {
      return null;
    }
  }

  void _showFeatureInfo(BuildContext context, AudioFeatureInfo info, {String? conflictReason}) {
    final p = context.palette;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: p.accentContainer, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.info_outline_rounded, color: p.accent, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(info.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(info.subtitle, style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 10),
              Text(info.description, style: TextStyle(color: p.textPrimary, fontSize: 13, height: 1.4)),
              if (info.conflictsWith != null) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withValues(alpha: 0.4))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18), const SizedBox(width: 8), Expanded(child: Text('Conflicts with: ${info.conflictsWith}', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)))])),
              ],
              if (conflictReason != null) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: p.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.error.withValues(alpha: 0.4))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.block_rounded, color: p.error, size: 18), const SizedBox(width: 8), Expanded(child: Text(conflictReason, style: TextStyle(color: p.error, fontSize: 11, fontWeight: FontWeight.w600)))])),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
      ),
    );
  }

  Widget _conflictBanner(String reason, PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: p.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.error.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.block_rounded, color: p.error, size: 16), const SizedBox(width: 8), Expanded(child: Text(reason, style: TextStyle(color: p.error, fontSize: 11, fontWeight: FontWeight.w600)))]),
    );
  }

  Future<void> _showSaveCustomPresetDialog(
      PlayerCubit cubit, PlayerState state) async {
    final textController = TextEditingController(text: 'My Custom EQ');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Custom EQ Preset'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Preset Name',
            hintText: 'e.g. Warm Bass, Vocal Punch',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      final profile = HeadphoneProfile(
        id: id,
        name: name,
        brand: 'User Custom',
        model: name,
        category: 'Custom',
        gains: List<double>.from(state.eqPreset.gains),
        bassBoost: state.eqPreset.bassBoost,
      );
      await _headphoneRepo.addCustomProfile(profile);
      await cubit.applyHeadphoneProfile(profile);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Preset "$name" saved!')),
        );
      }
    }
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
                Text(
                  'Hardware Effects Unavailable',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hardware AudioFX, Equalizer, Virtualizer and DynamicsProcessing are supported on Android devices.',
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
      listenWhen: (prev, curr) => prev.errorMessage != curr.errorMessage && curr.errorMessage != null,
      listener: (ctx, state) {
        final msg = state.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(ctx).colorScheme.error, behavior: SnackBarBehavior.floating));
          ctx.read<PlayerCubit>().clearError();
        }
      },
      child: BlocBuilder<PlayerCubit, PlayerState>(
        // DSP sheet ignores playback/position fields entirely - position ticks at
        // 10Hz were rebuilding the whole equalizer UI for nothing.
        buildWhen: (a, b) =>
            a.isEqEnabled != b.isEqEnabled ||
            a.eqPreset != b.eqPreset ||
            a.isVirtualizerEnabled != b.isVirtualizerEnabled ||
            a.virtualizerStrength != b.virtualizerStrength ||
            a.isDynamicsEnabled != b.isDynamicsEnabled ||
            a.dynamicsPreset != b.dynamicsPreset ||
            a.selectedHeadphoneProfile != b.selectedHeadphoneProfile ||
            a.isSpatializerEnabled != b.isSpatializerEnabled ||
            a.isSpatializerSupported != b.isSpatializerSupported ||
            a.volumeBoost != b.volumeBoost ||
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
            a.hasOemAudio != b.hasOemAudio ||
            !identical(a.detectedOemEngines, b.detectedOemEngines) ||
            a.errorMessage != b.errorMessage,
        builder: (context, state) {
          final cubit = context.read<PlayerCubit>();
          final dspBlockedGlobal = _dspBlockedReason(context);

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
                      // Top Handle
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),

                      // Separated EQ and DSP Master Toggles
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            // 1. Equalizer (EQ) Toggle Card
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
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
                                            Text(
                                              'Equalizer (EQ)',
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
                                                    ? 'BLOCKED'
                                                    : (state.isEqEnabled
                                                        ? 'ON'
                                                        : 'OFF'),
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: dspBlockedGlobal != null
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
                                              ? 'Blocked: Bit-Perfect bypass active'
                                              : (state.isEqEnabled
                                                  ? (state.selectedHeadphoneProfile !=
                                                          null
                                                      ? 'Tuned for ${state.selectedHeadphoneProfile!.name}'
                                                      : 'Preset: ${state.eqPreset.name}')
                                                  : 'Equalizer curves bypassed'),
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
                                    tooltip: 'About Equalizer',
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
                                      value: state.isEqEnabled,
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
                            const SizedBox(height: 6),

                            // 2. DSP & Spatial Effects Toggle Card
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: state.isDspActive
                                    ? p.accent.withValues(alpha: 0.08)
                                    : p.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: state.isDspActive
                                      ? p.accent.withValues(alpha: 0.35)
                                      : p.hairline,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: state.isDspActive
                                          ? p.accent.withValues(alpha: 0.2)
                                          : p.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.multitrack_audio_rounded,
                                      color: state.isDspActive
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
                                            Text(
                                              'DSP & Spatial Effects',
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
                                                color: state.isDspActive
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
                                                    ? 'BLOCKED'
                                                    : (state.isDspActive
                                                        ? 'ON'
                                                        : 'OFF'),
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: dspBlockedGlobal != null
                                                      ? p.error
                                                      : (state.isDspActive
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
                                              ? 'Blocked: Bit-Perfect bypass active'
                                              : (state.isDspActive
                                                  ? '${state.activeDspStagesCount} active effects (Reverb, Limiter...)'
                                                  : 'All DSP effects bypassed'),
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
                                    tooltip: 'About DSP Engine',
                                    onPressed: () => _showFeatureInfo(
                                      context,
                                      AudioFeatureRegistry.spatializer,
                                      conflictReason: dspBlockedGlobal,
                                    ),
                                  ),
                                  Opacity(
                                    opacity: dspBlockedGlobal != null &&
                                            !state.isDspActive
                                        ? 0.45
                                        : 1.0,
                                    child: Switch.adaptive(
                                      value: state.isDspActive,
                                      activeTrackColor: p.accent,
                                      activeThumbColor: p.onAccent,
                                      onChanged: dspBlockedGlobal != null &&
                                              !state.isDspActive
                                          ? null
                                          : (val) =>
                                              cubit.setDspEffectsEnabled(val),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Tabs Navigation
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                fontWeight: FontWeight.w700, fontSize: 12),
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'Equalizer'),
                              Tab(text: 'AutoEq'),
                              Tab(text: 'Spatial & DSP'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Tab Content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildEqualizerTab(context, cubit, state, p),
                            _buildAutoEqTab(context, cubit, state, p),
                            _buildSpatialDynamicsTab(context, cubit, state, p),
                          ],
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
                  IconButton(icon: Icon(Icons.info_outline_rounded, size: 18, color: p.accent), onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.equalizer, conflictReason: dspBlocked)),
                  const SizedBox(width: 4),
                  Expanded(child: Text('DSP disabled by Bit-Perfect bypass. Disable Bit-Perfect or âBypass DSPâ in Settings to re-enable.', style: TextStyle(color: p.textSecondary, fontSize: 11))),
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
                          onSelected: dspBlocked != null ? null : (_) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _isAbComparing ? p.accent : p.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _isAbComparing ? p.accent : p.hairline),
                      ),
                      child: Text(
                        'A/B Flat',
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
                onPressed: dspBlocked != null ? null : () => cubit.resetToFlat(),
                icon: Icon(Icons.restore_rounded,
                    size: 16, color: p.textSecondary),
                label: Text('Reset',
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
                onPressed: dspBlocked != null ? null : () => _showSaveCustomPresetDialog(cubit, state),
                icon:
                    Icon(Icons.bookmark_add_rounded, size: 16, color: p.accent),
                label: Text('Save',
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
                  label: const Text('AutoEQ 2.0 Search',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
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
                  label: const Text('Dynamics Compressor',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => CompressorLimiterSheet(
                        equalizerManager: getIt<EqualizerManager>(),
                      ),
                    );
                  },
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
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${state.detectedOemEngines.join(", ")} Active',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber[300] ?? Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'System-level audio enhancement is active on your device. '
                          'Running Pulsr DSP on top may cause double-processing (over-compression or clipping). '
                          'Consider disabling system Dolby/OEM sound effects or using Bit-Perfect output for cleanest sound.',
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
                          '${state.selectedHeadphoneProfile!.brand} â¢ '
                          'Preamp: ${state.selectedHeadphoneProfile!.preampGain.toStringAsFixed(1)} dB',
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
                    child: Text('Reset',
                        style: TextStyle(color: p.textSecondary, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Real-time Frequency Response Curve Visualizer
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: EqCurveVisualizer(
              gains: preset.gains,
              activeColor: effectiveEnabled ? p.accent : p.textTertiary,
              height: 52,
            ),
          ),
          const SizedBox(height: 14),

          // 10-Band Equalizer Vertical Sliders
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_bandLabels.length, (index) {
                final gain =
                    index < preset.gains.length ? preset.gains[index] : 0.0;
                return Expanded(
                  child: RepaintBoundary(
                    child: _VerticalEqSlider(
                      value: gain,
                      label: _bandLabels[index],
                      isEnabled: effectiveEnabled,
                      accentColor: p.accent,
                      trackColor: p.hairline,
                      surfaceColor: p.surface,
                      textColor: p.textPrimary,
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
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          // Bass Boost Slider
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
                            child: Text(
                              'Bass Enhancer',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: p.textPrimary),
                            ),
                          ),
                          IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Bass Boost', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.bassBoost, conflictReason: dspBlocked)),
                        ],
                      ),
                      Text(
                        '${(preset.bassBoost * 100).round()}% punch',
                        style: TextStyle(fontSize: 11, color: p.textTertiary),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: p.accent,
                        inactiveTrackColor: p.surface,
                        thumbColor: p.accent,
                      ),
                      child: Slider(
                        value: preset.bassBoost.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        onChanged: dspBlocked != null ? null : (val) {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setBassBoost(val);
                        },
                      ),
                    ),
                  ),
                ),
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
                                child: Text(
                                  'Volume Boost',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: p.textPrimary),
                                ),
                              ),
                              IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Volume Boost', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.volumeBoost, conflictReason: dspBlocked)),
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
                            : 'Off',
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
                  ],
                ),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: isOverSafe ? p.error : p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: isOverSafe ? p.error : p.accent,
                  ),
                  child: Slider(
                    value: state.volumeBoost.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    onChanged: dspBlocked != null ? null : (val) {
                      if (!state.isEqEnabled) cubit.setEqualizerEnabled(true);
                      cubit.setVolumeBoost(val);
                    },
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
                            'Combined with EQ preamp (+${preampDb.toStringAsFixed(1)} dB), total gain may clip. Consider reducing boost.',
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
                          child: Text(
                            'High boost may cause audio distortion or hearing fatigue.',
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
                  value: state.isSpatializerEnabled,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: (val) => cubit.setSpatializerEnabled(val),
                ),
              ],
            ),
          ),
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
                hintText: 'Search headphones (e.g. AirPods, Sony, Moondrop)...',
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
                        Text(
                          'Applied Tuning Profile',
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
                      child: Text(
                        'Reset to Flat',
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
                  child: Text(
                    'No headphone profiles found.',
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
                                        '${profile.brand} â¢ ${profile.category}',
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
                                    tooltip: 'Delete custom preset',
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
                                        Text(
                                          'Active',
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
                                    child: Text(
                                      'Apply',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) _conflictBanner(dspBlocked, p),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('All DSP is bypassed by Bit-Perfect. Disable it in Settings to re-enable.', style: TextStyle(color: p.textSecondary, fontSize: 11)),
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
                              child: Text(
                                'Spatial Audio',
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
                              child: Text(
                                'Spatial API',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Android Spatializer API with head tracking',
                          style: TextStyle(fontSize: 11, color: p.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Spatializer', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.spatializer, conflictReason: dspBlocked)),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: state.isSpatializerEnabled,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged: dspBlocked != null ? null : (val) => cubit.setSpatializerEnabled(val),
                  ),
                ],
              ),
            ),
            if (dspBlocked != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
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
                                Text(
                                  'Soundstage Widening',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Virtualizer stereo field expansion',
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
                    IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Virtualizer', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.virtualizer, conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: state.isVirtualizerEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null ? null : (val) => cubit.setVirtualizerEnabled(val),
                    ),
                  ],
                ),
                if (dspBlocked != null) Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
                const SizedBox(height: 16),

                // Soundstage visual slider
                Opacity(
                  opacity: dspBlocked != null ? 0.35 : (state.isVirtualizerEnabled ? 1.0 : 0.35),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Width',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600)),
                          Text(
                            '${(state.virtualizerStrength * 100).round()}%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: p.accent),
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
                        child: Slider(
                          value: state.virtualizerStrength.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          onChanged: state.isVirtualizerEnabled
                              ? (val) => cubit.setVirtualizerStrength(val)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
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
                                Text(
                                  'Studio Dynamics & Limiter',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Multiband compression engine',
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
                    IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Dynamics', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.dynamics, conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: state.isDynamicsEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null ? null : (val) {
                        cubit.setDynamicsPreset(
                          val
                              ? (state.dynamicsPreset == DynamicsPreset.off
                                  ? DynamicsPreset.studioPunch
                                  : state.dynamicsPreset)
                              : DynamicsPreset.off,
                          enabled: val,
                        );
                      },
                    ),
                  ],
                ),
                if (dspBlocked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
                const SizedBox(height: 14),

                // Dynamics Preset Cards Grid
                Opacity(
                  opacity: dspBlocked != null ? 0.35 : (state.isDynamicsEnabled ? 1.0 : 0.35),
                  child: Column(
                    children: DynamicsPreset.values
                        .where((d) => d != DynamicsPreset.off)
                        .map((preset) {
                      final isSelected = state.isDynamicsEnabled &&
                          state.dynamicsPreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: dspBlocked != null ? null : (state.isDynamicsEnabled
                              ? () =>
                                  cubit.setDynamicsPreset(preset, enabled: true)
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
                                Text(
                                  'Crossfeed (Headphones)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Natural acoustic room speaker simulation',
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
                    IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Crossfeed', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.crossfeed, conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: state.isCrossfeedEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null ? null : (val) => cubit.setCrossfeed(val),
                    ),
                  ],
                ),
                if (dspBlocked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
                if (dspBlocked == null && state.isCrossfeedEnabled) ...[
                  const SizedBox(height: 14),
                  // Delay slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Delay Time',
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${state.crossfeedDelayUs.round()} Âµs',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent),
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
                    child: Slider(
                      value: state.crossfeedDelayUs.clamp(200.0, 700.0),
                      min: 200.0,
                      max: 700.0,
                      divisions: 50,
                      onChanged: (val) =>
                          cubit.setCrossfeed(true, delayUs: val),
                    ),
                  ),
                  // Feed Level slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Opposite Ear Bleed',
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${state.crossfeedFeedDb.toStringAsFixed(1)} dB',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent),
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
                    child: Slider(
                      value: state.crossfeedFeedDb.clamp(-15.0, -6.0),
                      min: -15.0,
                      max: -6.0,
                      divisions: 18,
                      onChanged: (val) => cubit.setCrossfeed(true, feedDb: val),
                    ),
                  ),
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
                                Text(
                                  'Lookahead Brickwall Limiter',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Zero-overshoot anti-clipping protection',
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
                    IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Limiter', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.limiter, conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: state.isLimiterEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null ? null : (val) => cubit.setLookaheadLimiter(val),
                    ),
                  ],
                ),
                if (dspBlocked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
                if (dspBlocked == null && state.isLimiterEnabled) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ceiling Threshold',
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${state.limiterThresholdDb.toStringAsFixed(1)} dBFS',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent),
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
                    child: Slider(
                      value: state.limiterThresholdDb.clamp(-6.0, 0.0),
                      min: -6.0,
                      max: 0.0,
                      divisions: 60,
                      onChanged: (val) =>
                          cubit.setLookaheadLimiter(true, thresholdDb: val),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Release Time',
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${state.limiterReleaseMs.round()} ms',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent),
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
                    child: Slider(
                      value: state.limiterReleaseMs.clamp(10.0, 200.0),
                      min: 10.0,
                      max: 200.0,
                      divisions: 38,
                      onChanged: (val) =>
                          cubit.setLookaheadLimiter(true, releaseMs: val),
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
                                      child: Text(
                                        'Stereo Balance & Mono Mix',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: p.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Stereo Balance', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.panner, conflictReason: dspBlocked)),
                                  ],
                                ),
                                Text(
                                  'Left / Right acoustic panning balance',
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
                        Text('Mono',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: state.monoMix
                                    ? p.accent
                                    : p.textSecondary)),
                        const SizedBox(width: 4),
                        Switch.adaptive(
                          value: state.monoMix,
                          activeTrackColor: p.accent,
                          activeThumbColor: p.onAccent,
                          onChanged: dspBlocked != null ? null : (val) => cubit.setMonoMix(val),
                        ),
                      ],
                    ),
                  ],
                ),
                if (dspBlocked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('L',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: dspBlocked != null ? p.textTertiary : (state.stereoBalance < -0.05 ? p.accent : p.textSecondary))),
                    Text(
                      dspBlocked != null ? 'Blocked' : (state.stereoBalance.abs() < 0.05
                          ? 'Center'
                          : (state.stereoBalance < 0
                              ? 'Left ${(-state.stereoBalance * 100).round()}%'
                              : 'Right ${(state.stereoBalance * 100).round()}%')),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: dspBlocked != null ? p.error : p.accent),
                    ),
                    Text('R',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: dspBlocked != null ? p.textTertiary : (state.stereoBalance > 0.05 ? p.accent : p.textSecondary))),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: dspBlocked != null ? p.textTertiary : p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: dspBlocked != null ? p.textTertiary : p.accent,
                  ),
                  child: Slider(
                    value: state.stereoBalance.clamp(-1.0, 1.0),
                    min: -1.0,
                    max: 1.0,
                    divisions: 40,
                    onChanged: dspBlocked != null ? null : (val) => cubit.setStereoBalance(val),
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
                                Text(
                                  'Acoustic Room Convolution',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: p.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Impulse Response spatial acoustic simulation',
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
                    IconButton(icon: Icon(Icons.info_outline_rounded, size: 16, color: p.textTertiary), visualDensity: VisualDensity.compact, tooltip: 'About Reverb', onPressed: () => _showFeatureInfo(context, AudioFeatureRegistry.reverb, conflictReason: dspBlocked)),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: state.isReverbEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: dspBlocked != null ? null : (val) => cubit.setReverb(val),
                    ),
                  ],
                ),
                if (dspBlocked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Blocked by Bit-Perfect', style: TextStyle(color: p.error, fontSize: 10, fontWeight: FontWeight.w600))),
                if (dspBlocked == null && state.isReverbEnabled) ...[
                  const SizedBox(height: 14),
                  // Room presets chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildReverbChip(
                          'Studio Room', 0, state.reverbPreset, cubit, p),
                      _buildReverbChip(
                          'Concert Hall', 1, state.reverbPreset, cubit, p),
                      _buildReverbChip(
                          'Warm Tube', 2, state.reverbPreset, cubit, p),
                      _buildReverbChip(
                          'Plate Reverb', 3, state.reverbPreset, cubit, p),
                      _buildReverbChip(
                          'Custom', 4, state.reverbPreset, cubit, p),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Wet / Dry Mix',
                          style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${(state.reverbWetDry * 100).round()}% Wet',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent),
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
                    child: Slider(
                      value: state.reverbWetDry.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) => cubit.setReverb(true, wetDry: val),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReverbChip(String label, int presetIdx, int currentPreset,
      PlayerCubit cubit, PulsrPalette p) {
    final isSelected = presetIdx == currentPreset;
    return ChoiceChip(
      label: Text(label),
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
      onSelected: (_) => cubit.setReverb(true, preset: presetIdx),
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
