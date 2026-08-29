// lib/features/settings/presentation/widgets/audio_sound_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/presentation/widgets/audio_quality_sheet.dart';
import '../../../player/presentation/widgets/equalizer_sheet.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'battery_optimization_card.dart';
import 'settings_conflict_card.dart';
import 'settings_section.dart';
import 'settings_slider_row.dart';
import 'settings_tiles.dart';

/// Sound engine: equalizer, DSP engine, output device / bit-perfect,
/// ReplayGain and battery optimization for background audio.
class AudioSoundSection extends StatelessWidget {
  final SettingsState state;

  const AudioSoundSection({super.key, required this.state});

  /// Resolves the ReplayGain ↔ Bit-Perfect-bypass conflict by disabling the
  /// bypass (keeps Bit-Perfect output ON, unlocks the ReplayGain controls).
  Future<void> _resolveReplayGainConflict(
      BuildContext context, SettingsCubit cubit) async {
    await cubit.setBypassDspOnBitPerfect(false);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content:
          Text('Resolved: Bit-Perfect bypass disabled — ReplayGain is adjustable again'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    return SettingsSection(
      icon: Icons.graphic_eq_rounded,
      title: context.l10n.audioAndSound,
      children: [
        SettingsNavTile(
          Icons.equalizer_rounded,
          context.l10n.equalizerAndSoundEffects,
          PlatformCapabilities.hasEqualizer
              ? context.l10n.equalizerSubtitle
              : 'Not available on this platform',
          onTap: PlatformCapabilities.hasEqualizer
              ? () => showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const EqualizerSheet())
              : null,
        ),
        settingsCardDivider(p),
        SettingsNavTile(
          Icons.settings_input_composite_rounded,
          context.l10n.dspEnginePreference,
          switch (state.dspPreference) {
            'oem' => context.l10n.dspEngineOem,
            'auto' => context.l10n.dspEngineAuto,
            _ => context.l10n.dspEngineNative,
          },
          onTap: () => _showDspPreferencePickerSheet(
              context, cubit, state.dspPreference),
        ),
        settingsCardDivider(p),
        // Audiophile & Hi-Res Output Card & Controls
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Material(
            color: p.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                final playerState = context.read<PlayerCubit>().state;
                final currentSong = playerState.currentSong ??
                    const SongsTableData(
                      id: 0,
                      title: 'Hardware Audio Output',
                      artist: 'Master Audio Engine',
                      album: 'Internal / USB DAC',
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
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: state.currentOutputDevice?.isUsbDac == true
                        ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                        : p.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.currentOutputDevice?.isUsbDac == true
                              ? Icons.usb_rounded
                              : Icons.headphones_rounded,
                          color: state.currentOutputDevice?.isUsbDac == true
                              ? const Color(0xFFFFD700)
                              : p.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.currentOutputDevice?.deviceName ??
                                'Audio Output Device',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (state.currentOutputDevice?.isBitPerfectActive ==
                            true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.6)),
                            ),
                            child: const Text(
                              'BIT-PERFECT',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Icon(Icons.tune_rounded,
                            size: 16, color: p.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to configure Output Device • Sample Rate (${(state.currentOutputDevice?.sampleRate ?? 44100) ~/ 1000} kHz) • Bit Depth (${state.currentOutputDevice?.bitDepth ?? 16}-bit)',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Builder(builder: (ctx) {
          final bpBlock =
              AudioConflicts.bitPerfectBlockedReason(state.currentOutputDevice);
          return Column(
            children: [
              // Hardware/OS-level blockers (Bluetooth, Android version) cannot
              // be resolved in-app → explanatory card without a resolve action.
              if (bpBlock != null)
                SettingsConflictCard(reason: bpBlock),
              SettingsSwitchTile(
                Icons.album_rounded,
                'Bit-Perfect USB Pass-Through',
                state.currentOutputDevice?.isBluetooth == true
                    ? 'Unavailable: Bluetooth transcodes — use USB / wired DAC'
                    : 'Direct hardware streaming to USB / wired DACs (bypasses Android resampler)',
                value: state.bitPerfectOutput,
                featureInfo: AudioFeatureRegistry.bitPerfect,
                disabledReason: bpBlock,
                onChanged:
                    bpBlock != null ? (v) {} : cubit.setBitPerfectOutput,
              ),
            ],
          );
        }),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.tune_rounded,
          'Bypass DSP in Bit-Perfect Mode',
          'Bypasses Equalizer and virtualizer for an uncolored, pure audio bitstream to the DAC',
          value: state.bypassDspOnBitPerfect,
          featureInfo: AudioFeatureRegistry.bypassDsp,
          onChanged: cubit.setBypassDspOnBitPerfect,
        ),
        settingsCardDivider(p),
        // ReplayGain / Loudness Normalization Suite
        Builder(builder: (cntx) {
          final rgBlocked = AudioConflicts.replayGainBlockedByBitPerfect(
            bitPerfectOutput: state.bitPerfectOutput,
            bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
            device: state.currentOutputDevice,
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.volume_up_rounded,
                        color:
                            rgBlocked != null ? p.textTertiary : p.accent,
                        size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ReplayGain Loudness Normalization',
                                  style: TextStyle(
                                    color: rgBlocked != null
                                        ? p.textTertiary
                                        : p.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    size: 18, color: p.textTertiary),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => showAudioFeatureInfoDialog(
                                    context, AudioFeatureRegistry.replayGain,
                                    conflictReason: rgBlocked),
                              ),
                            ],
                          ),
                          Text(
                            rgBlocked ??
                                'EBU R128 automatic volume leveling across diverse track masters',
                            style: TextStyle(
                              color: rgBlocked != null ? p.error : p.textSecondary,
                              fontSize: 12,
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
                    padding: const EdgeInsets.only(top: 8),
                    child: SettingsConflictCard(
                      reason: rgBlocked,
                      resolveLabel: 'Disable Bit-Perfect bypass',
                      onResolve: () =>
                          _resolveReplayGainConflict(context, cubit),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReplayGainMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: ReplayGainMode.off,
                        label: Text('Off',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.track,
                        label: Text('Track',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.album,
                        label: Text('Album',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.auto,
                        label: Text('Auto',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
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
                  // Defaults: with-RG preamp 0.0 dB, without-RG preamp -3.0 dB
                  // (SettingsState.replayGainPreampWithRg / …WithoutRg).
                  SettingSliderRow(
                    label: 'Preamp (With RG tag)',
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
                    label: 'Preamp (Without RG tag fallback)',
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
        const BatteryOptimizationCard(),
      ],
    );
  }

  void _showDspPreferencePickerSheet(
      BuildContext context, SettingsCubit cubit, String currentPref) {
    final p = context.palette;
    final options = [
      ('native', context.l10n.dspEngineNative, '64-bit float, zero-latency real-time native DSP'),
      ('oem', context.l10n.dspEngineOem, 'System / vendor-level sound effects (Dolby, Dirac, etc.)'),
      ('auto', context.l10n.dspEngineAuto, 'Automatically bypass OEM sound effects when DSP active'),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.bottomSheetRadius,
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.dspEnginePreference,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...options.map((opt) {
                final isSelected = currentPref == opt.$1;
                return ListTile(
                  title: Text(opt.$2,
                      style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(opt.$3,
                      style: TextStyle(color: p.textSecondary, fontSize: 12)),
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
