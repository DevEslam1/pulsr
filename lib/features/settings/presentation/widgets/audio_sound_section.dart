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
part 'audio_sound_dop_selector.dart';

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
    final codec = state.currentOutputDevice?.btCodecName;
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
    final device = state.currentOutputDevice;
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
        state.isProfessional
            ? _buildProfessional(context)
            : _buildNormal(context),
        const CastSection(),
      ],
    );
  }

  Widget _buildProfessional(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    // Native DSP / HAL / Hi-Res output are Android-only. On other platforms the
    // channel truthfully reports "not applied"; disable the controls here instead
    // of letting them silently no-op and leave the UI looking enabled.
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;
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
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: state.currentOutputDevice?.isUsbDac == true
                        ? p.warning.withValues(alpha: 0.5)
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
                              ? p.warning
                              : p.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.currentOutputDevice?.deviceName ??
                                context.l10n.settingsAudioOutputDevice,
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
                            child: Text(context.l10n.bitPerfectLabel,
                              style: TextStyle(
                                color: p.warning,
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
                      context.l10n.settingsOutputDeviceConfigHint((state.currentOutputDevice?.sampleRate ?? 44100) ~/ 1000, state.currentOutputDevice?.bitDepth ?? 16),
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
                context.l10n.settingsBitPerfectUsb,
                !isAndroid
                    ? unsupported
                    : state.currentOutputDevice?.isBluetooth == true
                        ? context.l10n.settingsBitPerfectBtUnavailable
                        : context.l10n.settingsBitPerfectUsbDesc,
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
          context.l10n.settingsBypassDspBitPerfect,
          context.l10n.settingsBypassDspBitPerfectDesc,
          value:
              isAndroid && state.bitPerfectOutput && state.bypassDspOnBitPerfect,
          featureInfo: AudioFeatureRegistry.bypassDsp,
          disabledReason: !isAndroid
              ? unsupported
              : !state.bitPerfectOutput
                  ? context.l10n.settingsEnableBitPerfectFirst
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
                    tooltip: context.l10n.settingsAboutTitle(context.l10n.dsdOutputModeTitle),
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
              if (isAndroid &&
                  state.dsdDopSupported &&
                  state.dsdOutputMode == DsdOutputMode.dop) ...[
                const SizedBox(height: 8),
                const _DopContainerSelector(),
              ],
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
                                child: Text(context.l10n.replayGainTitle,
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
                                context.l10n.settingsReplayGainDesc,
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
                      resolveLabel: context.l10n.settingsDisableBitPerfectBypass,
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
                    segments: [
                      ButtonSegment(
                        value: ReplayGainMode.off,
                        label: Text(context.l10n.rgOff,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.track,
                        label: Text(context.l10n.rgTrack,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.album,
                        label: Text(context.l10n.rgAlbum,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      ButtonSegment(
                        value: ReplayGainMode.auto,
                        label: Text(context.l10n.rgAuto,
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
                    label: context.l10n.settingsPreampWithRg,
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
                    label: context.l10n.settingsPreampWithoutRg,
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
                        Text(context.l10n.dspInspectorDebug,
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
                              ? context.l10n.settingsDspInspectorDesc
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
                        _ => context.l10n.settingsStatusLabel(state.systemEffectsStatus),
                      },
                style: TextStyle(
                  color: state.systemEffectsStatus == 'bypassed'
                      ? p.success
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
                label: context.l10n.settingsSyncOffset,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => BtLatencyTapSheet.show(context),
                      icon: const Icon(Icons.fingerprint_rounded, size: 16),
                      label: Text(context.l10n.settingsSyncOffset),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          _autoCalibrateBluetoothLatency(context, cubit),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: Text(context.l10n.autoCalibrate),
                    ),
                  ],
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
          context.l10n.settingsPerTrackFormatNegotiation,
          context.l10n.settingsPerTrackFormatDesc,
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
          context.l10n.settingsFloatDspPath,
          context.l10n.settingsFloatDspDesc,
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
          context.l10n.settingsAaudioDirect,
          context.l10n.settingsAaudioDirectDesc,
          value: isAndroid && state.aaudioOutputEnabled,
          disabledReason: isAndroid ? null : unsupported,
          onChanged:
              !isAndroid ? (v) {} : cubit.setAaudioOutputEnabled,
        ),
        // AAudio stream buffer capacity (Direct output only).
        SettingSliderRow(
          label: context.l10n.settingsAaudioBufferSize,
          subtitle: context.l10n.settingsAaudioBufferSizeDesc,
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
        // Opt-in Direct Volume Control (DVC). Pins Android's media stream to
        // maximum and applies the composed gain in the native float DSP path,
        // keeping attenuation out of Android's digital volume stage for higher
        // dynamic range at low hardware volumes.
        SettingsSwitchTile(
          Icons.volume_up_rounded,
          context.l10n.settingsDvcTitle,
          context.l10n.settingsDvcDesc,
          value: isAndroid &&
              state.dvcEnabled &&
              !state.aaudioOutputEnabled &&
              AudioConflicts.dspBlockedByBitPerfect(
                    bitPerfectOutput: state.bitPerfectOutput,
                    bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                    device: state.currentOutputDevice,
                  ) ==
                  null,
          disabledReason: !isAndroid
              ? unsupported
              : (state.aaudioOutputEnabled
                  ? context.l10n.settingsUnavailableAaudio
                  : AudioConflicts.dspBlockedByBitPerfect(
                      bitPerfectOutput: state.bitPerfectOutput,
                      bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                      device: state.currentOutputDevice,
                    )),
          onChanged: !isAndroid ||
                  state.aaudioOutputEnabled ||
                  AudioConflicts.dspBlockedByBitPerfect(
                        bitPerfectOutput: state.bitPerfectOutput,
                        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
                        device: state.currentOutputDevice,
                      ) !=
                      null
              ? (v) {}
              : cubit.setDvcEnabled,
        ),
        settingsCardDivider(p),
        // USB DAC hardware volume + optional exclusive interface claim.
        UsbDacSection(cubit: cubit, state: state),
        settingsCardDivider(p),
        // Resampler quality: Fast (linear) .. Ultra (full 64-tap polyphase).
        SettingSliderRow(
          label: context.l10n.settingsResamplerQuality,
          subtitle: context.l10n.settingsResamplerQualityDesc,
          value: state.sincResamplerQuality.toDouble(),
          min: 0,
          max: 3,
          divisions: 3,
          defaultValue: 3,
          formatValue: (v) {
            switch (v.round()) {
              case 0:
                return context.l10n.settingsResamplerFast;
              case 1:
                return context.l10n.settingsResamplerStandard;
              case 2:
                return context.l10n.settingsResamplerHigh;
              default:
                return context.l10n.settingsResamplerUltra;
            }
          },
          onChanged: (v) => cubit.setSincResamplerQuality(v.round()),
        ),
        settingsCardDivider(p),
        // BPM-synced crossfade: aligns the fade to the nearest beats of the
        // incoming track when a BPM value is known for it.
        SettingsSwitchTile(
          Icons.music_note_rounded,
          context.l10n.settingsBpmSyncCrossfade,
          context.l10n.settingsBpmSyncCrossfadeDesc,
          value: state.bpmSyncCrossfadeEnabled,
          onChanged: cubit.setBpmSyncCrossfadeEnabled,
        ),
        settingsCardDivider(p),
        // Per-session audio diagnostics (pure Dart; works on every platform).
        SettingsSwitchTile(
          Icons.monitor_heart_rounded,
          context.l10n.settingsSessionDiagnostics,
          context.l10n.settingsSessionDiagnosticsDesc,
          value: state.sessionLogEnabled,
          onChanged: cubit.setSessionLogEnabled,
        ),
        SettingsNavTile(
          Icons.ios_share_rounded,
          context.l10n.settingsExportSessionLogs,
          context.l10n.settingsExportSessionLogsDesc,
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

