// lib/features/settings/presentation/widgets/audio_sound_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/app_radii.dart';
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
import 'room_correction_sheet.dart';
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

  Future<void> _autoCalibrateBluetoothLatency(
      BuildContext context, SettingsCubit cubit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final codec = state.currentOutputDevice?.btCodecName;
    final result =
        await BluetoothLatencyCalibrator().calibrate(codecName: codec);
    await cubit.setBluetoothLatencyOffsetMs(result.offsetMs);
    messenger?.showSnackBar(SnackBar(
      content: Text(
        'Bluetooth latency calibrated to ${result.offsetMs} ms'
        '${codec != null && codec.isNotEmpty ? ' ($codec)' : ''}',
      ),
    ));
  }

  /// Curated sound section for Normal mode: what a non-technical listener needs
  /// and nothing else. Smart Audio (in Settings → Sound) runs the advanced
  /// pipeline automatically.
  Widget _buildNormal(BuildContext context) {
    final p = context.palette;
    final device = state.currentOutputDevice;
    final deviceLabel = device == null
        ? 'Connected device & audio quality'
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
          Icons.speaker_rounded,
          'Output & Audio Quality',
          deviceLabel,
          onTap: () {
            final currentSong = context.read<PlayerCubit>().state.currentSong ??
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
        ),
        settingsCardDivider(p),
        const BatteryOptimizationCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Normal mode: a curated, smart sound section. The full audiophile control
    // surface (bit-perfect, DSD, AAudio, resampler, DSP engine, diagnostics)
    // stays available in Professional mode.
    if (!state.isProfessional) return _buildNormal(context);
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    // Native DSP / HAL / Hi-Res output are Android-only. On other platforms the
    // channel truthfully reports "not applied"; disable the controls here instead
    // of letting them silently no-op and leave the UI looking enabled.
    final isAndroid = PlatformCapabilities.isAndroid;
    const unsupported = 'Not available on this platform';
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
          isAndroid
              ? switch (state.dspPreference) {
                  'oem' => context.l10n.dspEngineOem,
                  'auto' => context.l10n.dspEngineAuto,
                  _ => context.l10n.dspEngineNative,
                }
              : unsupported,
          disabledReason: isAndroid ? null : unsupported,
          onTap: isAndroid
              ? () => _showDspPreferencePickerSheet(
                  context, cubit, state.dspPreference)
              : null,
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
          final bpBlock = !isAndroid
              ? unsupported
              : AudioConflicts.bitPerfectBlockedReason(
                  state.currentOutputDevice);
          return Column(
            children: [
              // Hardware/OS-level blockers (Bluetooth, Android version) cannot
              // be resolved in-app → explanatory card without a resolve action.
              if (bpBlock != null && isAndroid)
                SettingsConflictCard(reason: bpBlock),
              SettingsSwitchTile(
                Icons.album_rounded,
                'Bit-Perfect USB Pass-Through',
                !isAndroid
                    ? unsupported
                    : state.currentOutputDevice?.isBluetooth == true
                        ? 'Unavailable: Bluetooth transcodes — use USB / wired DAC'
                        : 'Direct hardware streaming to USB / wired DACs (bypasses Android resampler)',
                value: isAndroid && state.bitPerfectOutput,
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
          value:
              isAndroid && state.bitPerfectOutput && state.bypassDspOnBitPerfect,
          featureInfo: AudioFeatureRegistry.bypassDsp,
          disabledReason: !isAndroid
              ? unsupported
              : !state.bitPerfectOutput
                  ? 'Enable Bit-Perfect USB Pass-Through first'
                  : null,
          onChanged: !isAndroid || !state.bitPerfectOutput
              ? (v) {}
              : cubit.setBypassDspOnBitPerfect,
        ),
        settingsCardDivider(p),
        // T2: follow the current track's native sample rate. De-duplicated in
        // PlayerCubit and skipped on Bluetooth, where AVRCP owns the rate.
        SettingsSwitchTile(
          Icons.sync_rounded,
          context.l10n.followTrackSampleRateTitle,
          !isAndroid
              ? unsupported
              : state.currentOutputDevice?.isBluetooth == true
                  ? context.l10n.followTrackSampleRateBluetooth
                  : context.l10n.followTrackSampleRateSubtitle,
          value: isAndroid && state.followTrackSampleRate,
          featureInfo: AudioFeatureRegistry.followTrackSampleRate,
          disabledReason: isAndroid ? null : unsupported,
          onChanged: isAndroid ? cubit.setFollowTrackSampleRate : (v) {},
        ),
        settingsCardDivider(p),
        // T3: strict bit-perfect. Enabled only on a path that reports exclusive
        // bit-perfect support; otherwise the platform reason is shown instead
        // of pretending the toggle works.
        Builder(builder: (ctx) {
          final strictBlock = !isAndroid
              ? unsupported
              : AudioConflicts.strictBitPerfectBlockedReason(
                  state.currentOutputDevice);
          return Column(
            children: [
              SettingsSwitchTile(
                Icons.verified_rounded,
                context.l10n.strictBitPerfectTitle,
                !isAndroid
                    ? unsupported
                    : state.currentOutputDevice?.isBluetooth == true
                        ? context.l10n.strictBitPerfectBluetooth
                        : context.l10n.strictBitPerfectSubtitle,
                value: isAndroid && state.strictBitPerfect,
                featureInfo: AudioFeatureRegistry.strictBitPerfect,
                // Once enabled the switch stays operable so the user can always
                // turn strict mode back off, even if the device later stops
                // reporting bit-perfect support.
                disabledReason: state.strictBitPerfect ? null : strictBlock,
                onChanged: cubit.setStrictBitPerfect,
              ),
              if (state.strictBitPerfect)
                SettingsConflictCard(
                  reason: AudioConflicts.strictBitPerfectActiveReason(
                        bitPerfectOutput: state.bitPerfectOutput,
                        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                        device: state.currentOutputDevice,
                      ) ??
                      context.l10n.strictBitPerfectActive,
                ),
            ],
          );
        }),
        settingsCardDivider(p),
        // T4: DSD (DSF/DFF) output mode. Disabled with a truthful reason
        // whenever the native probe has not confirmed a DoP-capable USB DAC.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.album_rounded,
                    size: 20,
                    color: (!isAndroid || !state.dsdDopSupported)
                        ? p.textTertiary
                        : p.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.dsdOutputModeTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline_rounded,
                        size: 18, color: p.textTertiary),
                    tooltip: 'About ${context.l10n.dsdOutputModeTitle}',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showAudioFeatureInfoDialog(
                      context,
                      AudioFeatureRegistry.dsdNative,
                      conflictReason: !isAndroid
                          ? unsupported
                          : state.dsdDopSupported
                              ? null
                              : context.l10n.dsdDopRequiresUsbDac,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                !isAndroid
                    ? unsupported
                    : state.dsdDopSupported
                        ? context.l10n.dsdOutputModeSubtitle
                        : context.l10n.dsdDopRequiresUsbDac,
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<DsdOutputMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: DsdOutputMode.pcm,
                      label: Text(
                        context.l10n.dsdOutputPcm,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: DsdOutputMode.dop,
                      label: Text(
                        context.l10n.dsdOutputDop,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  selected: {state.dsdOutputMode},
                  onSelectionChanged: (!isAndroid || !state.dsdDopSupported)
                      ? null
                      : (selected) {
                          if (selected.isNotEmpty) {
                            cubit.setDsdOutputMode(selected.first);
                          }
                        },
                ),
              ),
            ],
          ),
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
                                'Track / album gain from tags, applied during playback',
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
        // Loudness Contour (Fletcher–Munson) — volume-linked tone compensation.
        // Complementary to ReplayGain (gain-domain): RG levels tracks, the
        // contour adapts tone to the listening level. See conflict copy.
        BlocBuilder<PlayerCubit, PlayerState>(
          buildWhen: (prev, curr) =>
              prev.isLoudnessContourEnabled != curr.isLoudnessContourEnabled ||
              prev.loudnessContourIntensity != curr.loudnessContourIntensity,
          builder: (context, playerState) {
            final l10n = context.l10n;
            final playerCubit = context.read<PlayerCubit>();
            final isLoudnessContourEnabled = playerState.isLoudnessContourEnabled;
            final loudnessContourIntensity = playerState.loudnessContourIntensity;
          final lcBlocked = AudioConflicts.dspBlockedByBitPerfect(
            bitPerfectOutput: state.bitPerfectOutput,
            bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
            device: state.currentOutputDevice,
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.hearing_rounded,
                        color: lcBlocked != null ? p.textTertiary : p.accent,
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
                                  l10n.dspLoudnessTitle,
                                  style: TextStyle(
                                    color: lcBlocked != null
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
                                    context, AudioFeatureRegistry.loudnessContour,
                                    conflictReason: lcBlocked),
                              ),
                            ],
                          ),
                          Text(
                            lcBlocked ?? l10n.dspLoudnessSubtitle,
                            style: TextStyle(
                              color:
                                  lcBlocked != null ? p.error : p.textSecondary,
                              fontSize: 12,
                              fontWeight: lcBlocked != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: isLoudnessContourEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: lcBlocked != null || !AudioEffectsChannel().hasPcmDspPath
                          ? null
                          : (val) => playerCubit.setLoudnessContour(val),
                    ),
                  ],
                ),
                if (lcBlocked == null &&
                    AudioEffectsChannel().hasPcmDspPath &&
                    isLoudnessContourEnabled) ...[
                  const SizedBox(height: 4),
                  SettingSliderRow(
                    label: l10n.dspLoudnessIntensity,
                    value: loudnessContourIntensity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    defaultValue: 0.0,
                    formatValue: (v) => '${(v * 100).round()}%',
                    onChanged: (v) =>
                        playerCubit.setLoudnessContour(true, intensity: v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.dspLoudnessReplayGainNote,
                    style: TextStyle(color: p.textTertiary, fontSize: 10),
                  ),
                ],
              ],
            ),
          );
        }),
        settingsCardDivider(p),
        // Room Correction Wizard
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAndroid ? () => RoomCorrectionSheet.show(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 20,
                    color: isAndroid ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.rcTitle,
                                style: TextStyle(
                                  color: isAndroid
                                      ? p.textPrimary
                                      : p.textTertiary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.info_outline_rounded,
                                  size: 18, color: p.textTertiary),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => showAudioFeatureInfoDialog(
                                context,
                                AudioFeatureRegistry.roomCorrection,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAndroid ? context.l10n.rcSubtitle : unsupported,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: p.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        settingsCardDivider(p),
        // DSP Signal Inspector & Debug
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAndroid ? () => DspInspectorSheet.show(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors_rounded,
                    size: 20,
                    color: isAndroid ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DSP Signal Inspector & Debug',
                          style: TextStyle(
                            color:
                                isAndroid ? p.textPrimary : p.textTertiary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAndroid
                              ? 'Inspect live active DSP stages, HAL effects & engine state'
                              : unsupported,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: p.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        settingsCardDivider(p),
        // System Audio Effects (Dolby Atmos / OEM DAP Controller)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.surround_sound_rounded, size: 20, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.systemEffectsTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                !isAndroid
                    ? unsupported
                    : switch (state.systemEffectsStatus) {
                        'bypassed' =>
                          context.l10n.systemEffectsSubtitleBypassed,
                        'active' => context.l10n.systemEffectsSubtitleActive,
                        'unsupportedDevice' =>
                          context.l10n.systemEffectsSubtitleUnsupported,
                        _ => 'Status: ${state.systemEffectsStatus}',
                      },
                style: TextStyle(
                  color: state.systemEffectsStatus == 'bypassed'
                      ? Colors.greenAccent
                      : p.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: 'auto',
                      label: Text(context.l10n.systemEffectsAuto, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: 'tryDisable',
                      label: Text(context.l10n.systemEffectsTryDisable, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: 'leaveOn',
                      label: Text(context.l10n.systemEffectsLeaveOn, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  selected: {state.systemEffectsPolicy},
                  onSelectionChanged: isAndroid
                      ? (selected) {
                          if (selected.isNotEmpty) {
                            cubit.setSystemEffectsPolicy(selected.first);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        settingsCardDivider(p),
        // Bluetooth Wireless Quality & Latency Sync
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bluetooth_audio_rounded, size: 20, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.bluetoothLatencyTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isAndroid
                    ? context.l10n
                        .bluetoothLatencySubtitle(state.bluetoothLatencyOffsetMs)
                    : unsupported,
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              SettingSliderRow(
                label: 'Sync Offset',
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
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        _autoCalibrateBluetoothLatency(context, cubit),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Auto-calibrate'),
                  ),
                ),
            ],
          ),
        ),
        settingsCardDivider(p),
        // Opt-in per-track output-format negotiation. Off by default: the output
        // format stays the manual, device-global setting. When on, each track
        // requests its native rate/depth, capped by the active route's device.
        SettingsSwitchTile(
          Icons.sync_alt_rounded,
          'Per-Track Output Format Negotiation',
          'Hi-res first: requests each track\'s native sample rate / bit depth '
              'from the output device (device-capped). Bit-Perfect keeps its '
              'exclusive format. Turn off to use one manual output format',
          value: isAndroid && state.outputFormatNegotiationEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged: !isAndroid
              ? (v) {}
              : cubit.setOutputFormatNegotiationEnabled,
        ),
        settingsCardDivider(p),
        // 24/32-bit float DSP path. ON by default so hi-res sources are never
        // truncated to 16-bit; 16-bit content is unaffected.
        SettingsSwitchTile(
          Icons.graphic_eq_rounded,
          '24/32-bit Float DSP Path',
          'Hi-res first: feeds the native DSP chain float32 samples so 24/32-bit '
              'sources keep their depth (16-bit content is unaffected). '
              'Unsupported devices safely fall back to 16-bit',
          value: isAndroid && state.floatOutputEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged:
              !isAndroid ? (v) {} : cubit.setFloatOutputEnabled,
        ),
        settingsCardDivider(p),
        // Opt-in AAudio Direct output. Off by default: the sink stays the
        // historical DefaultAudioSink + native DSP chain. When on, playback
        // goes through a native AAudio stream (EXCLUSIVE attempt, SHARED
        // fallback) and the DSP chain is bypassed for bit-perfect output.
        SettingsSwitchTile(
          Icons.surround_sound_rounded,
          'AAudio Direct Output (Bit-Perfect)',
          'Bypasses the system mixer with a native AAudio stream opened at '
              'each track rate (EXCLUSIVE attempt, SHARED fallback). The DSP '
              'chain and speed/pitch controls are inactive in this mode; '
              'applies to newly built players',
          value: isAndroid && state.aaudioOutputEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged:
              !isAndroid ? (v) {} : cubit.setAaudioOutputEnabled,
        ),
        // AAudio stream buffer capacity (Direct output only).
        SettingSliderRow(
          label: 'AAudio Buffer Size',
          subtitle: 'Stream buffer capacity hint in milliseconds. Lower = '
              'lower latency (wired), higher = more stall resistance',
          value: state.aaudioTargetBufferMs.toDouble(),
          min: 20,
          max: 500,
          divisions: 24,
          defaultValue: 150,
          formatValue: (v) => '${v.round()} ms',
          enabled: isAndroid && state.aaudioOutputEnabled,
          onChanged: (v) => cubit.setAaudioTargetBufferMs(v.round()),
        ),
        settingsCardDivider(p),
        // Resampler quality: Fast (linear) .. Ultra (full 64-tap polyphase).
        SettingSliderRow(
          label: 'Resampler Quality',
          subtitle: 'Sample-rate conversion quality. Ultra is the full '
              '64-tap polyphase sinc (historical default); Fast is linear '
              'interpolation for minimal CPU on battery',
          value: state.sincResamplerQuality.toDouble(),
          min: 0,
          max: 3,
          divisions: 3,
          defaultValue: 3,
          formatValue: (v) {
            switch (v.round()) {
              case 0:
                return 'Fast (Linear)';
              case 1:
                return 'Standard (16-tap)';
              case 2:
                return 'High (32-tap)';
              default:
                return 'Ultra (64-tap)';
            }
          },
          onChanged: (v) => cubit.setSincResamplerQuality(v.round()),
        ),
        settingsCardDivider(p),
        // BPM-synced crossfade: aligns the fade to the nearest beats of the
        // incoming track when a BPM value is known for it.
        SettingsSwitchTile(
          Icons.music_note_rounded,
          'BPM-Synced Crossfade',
          'Aligns the crossfade duration to the nearest 2/4/8/16/32 beats of '
              'the incoming track when its BPM is known (set per track in '
              'Song Info); otherwise the configured duration is used',
          value: state.bpmSyncCrossfadeEnabled,
          onChanged: cubit.setBpmSyncCrossfadeEnabled,
        ),
        settingsCardDivider(p),
        // Per-session audio diagnostics (pure Dart; works on every platform).
        SettingsSwitchTile(
          Icons.monitor_heart_rounded,
          'Session Audio Diagnostics',
          'Records one log per track: route type, Bluetooth codec, negotiated '
              'sample rate / bit depth, interruptions and dropout counts',
          value: state.sessionLogEnabled,
          onChanged: cubit.setSessionLogEnabled,
        ),
        SettingsNavTile(
          Icons.ios_share_rounded,
          'Export audio session logs',
          'Share the on-device JSONL log of your recent playback sessions',
          trailing: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
          onTap: () => _exportSessionLogs(context),
        ),
        const BatteryOptimizationCard(),
      ],
    );
  }

  /// Exports the per-session audio telemetry JSONL and hands it to the OS share
  /// sheet. Best-effort: a missing/failed export surfaces a message, never a throw.
  Future<void> _exportSessionLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await AudioSessionLog.instance.exportToFile();
      if (file == null || await file.length() == 0) {
        messenger?.showSnackBar(const SnackBar(
          content: Text('No audio session logs recorded yet'),
        ));
        return;
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/x-ndjson')],
        text: 'Pulsr audio session logs',
      ));
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Export failed: ${e.toString()}')),
      );
    }
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
