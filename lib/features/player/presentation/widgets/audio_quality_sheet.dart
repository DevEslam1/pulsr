import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/presentation/audio_quality_presentation.dart';
import '../../../../core/services/coach_mark_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../core/widgets/pulsr_segmented_control.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/bit_perfect_chain.dart';
import '../../../../data/audio/dsd_decoder_helper.dart';
import '../../../../data/audio/live_output_verdict.dart';
import '../../../../data/audio/mqa_decoder_helper.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../data/services/hires_audio_service.dart';
import '../../../../data/services/usb_exclusive_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../../domain/models/audio_signal_path.dart';
import '../../../../domain/models/bit_perfect_state.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../settings/presentation/widgets/bit_perfect_conflict_dialog.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_quality_live_chain.dart';
import 'audio_signal_path_card.dart';
import 'pulsr_cast_sheet.dart';

part 'audio_quality/audio_quality_signal_path_header.dart';
part 'audio_quality/audio_quality_route_drawers.dart';
part 'audio_quality/audio_quality_scaffold.dart';
part 'audio_quality/audio_quality_now_playing_tab.dart';
part 'audio_quality/audio_quality_output_tab.dart';
part 'audio_quality/audio_quality_rate_bitdepth.dart';
part 'audio_quality/audio_quality_bluetooth_drawer.dart';
part 'audio_quality/audio_quality_bluetooth_banners.dart';
part 'audio_quality/audio_quality_diagnostics_tab.dart';

class AudioQualitySheet extends StatelessWidget {
  final SongsTableData song;
  final Color activeColor;

  const AudioQualitySheet({
    super.key,
    required this.song,
    required this.activeColor,
  });

  static void show(
    BuildContext context,
    SongsTableData song,
    Color activeColor,
  ) {
    PulsrHaptics.mediumImpact();
    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => AudioQualitySheet(song: song, activeColor: activeColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsCubit = context.read<SettingsCubit?>();
    final settingsState = settingsCubit?.state;
    // `bitPerfectOutput` is part of the selection so toggling it rebuilds the
    // sheet immediately.
    final (streamingQuality, outputDevice, _, experienceMode) = context.select<
        SettingsCubit,
        (YtmAudioQuality?, AudioOutputInfo?, bool, ExperienceMode)>(
      (c) => (
        c.state.streamingQuality,
        c.state.currentOutputDevice,
        c.state.bitPerfectOutput,
        c.state.experienceMode,
      ),
    );
    final isProfessional = experienceMode == ExperienceMode.professional;
    SongsTableData? currentSong;
    DspSlice dspSlice = const DspSlice();
    try {
      currentSong = context
          .select<PlayerCubit, SongsTableData?>((c) => c.state.currentSong);
      dspSlice = context.select<PlayerCubit, DspSlice>((c) => c.state.dsp);
    } catch (_) {
      dspSlice = const DspSlice();
    }
    final resolvedSong = currentSong ?? song;
    final info = AudioQualityInfo.fromSong(
      resolvedSong,
      streamingQuality: streamingQuality,
      isConfirmedMqa: MqaDecoderHelper.isConfirmedMqaPath(resolvedSong.path),
      dsdDopActive: DsdDecoderHelper.dsdDopActive,
      dsdNativeActive: DsdDecoderHelper.dsdNativeActive,
    );

    return _buildLiveChainContent(
      outputDevice,
      settingsState,
      dspSlice,
      resolvedSong,
      (state, usbStatus) {
        if (outputDevice?.isUsbDac == true || usbStatus.attached) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              CoachMarkService.maybeShowUsbDacExplainer(context);
            }
          });
        }

        final signalPathHeader = AudioQualitySignalPathHeader(
          info: info,
          outputDevice: outputDevice,
          settingsState: settingsState,
          dsp: dspSlice,
          bitPerfectState: state,
          usbStatus: usbStatus,
          activeColor: activeColor,
        );

        final nowPlayingChildren = _buildNowPlayingChildren(
          context: context,
          info: info,
          resolvedSong: resolvedSong,
          settingsCubit: settingsCubit,
          streamingQuality: streamingQuality,
          p: p,
        );

        final outputChildren = _buildOutputChildren(
          context: context,
          outputDevice: outputDevice,
          settingsCubit: settingsCubit,
          info: info,
          state: state,
          usbStatus: usbStatus,
          p: p,
        );

        final diagnosticsChildren = _buildDiagnosticsChildren(
          context: context,
          info: info,
          resolvedSong: resolvedSong,
          outputDevice: outputDevice,
          settingsState: settingsState,
          dspSlice: dspSlice,
          state: state,
          usbStatus: usbStatus,
          p: p,
        );

        return _AudioQualityTabbedScaffold(
          isProfessional: isProfessional,
          activeColor: activeColor,
          signalPathHeader: signalPathHeader,
          nowPlayingChildren: nowPlayingChildren,
          outputChildren: outputChildren,
          diagnosticsChildren: diagnosticsChildren,
        );
      },
    );
  }

  Widget _buildLiveChainContent(
    AudioOutputInfo? outputDevice,
    SettingsState? settingsState,
    DspSlice dsp,
    SongsTableData source,
    Widget Function(BitPerfectState, UsbExclusiveStatus) builder,
  ) {
    PulsrAudioHandler? handler;
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      handler = getIt<PulsrAudioHandler>();
    }
    final usb = UsbExclusiveService();
    return StreamBuilder<UsbExclusiveStatus>(
      stream: usb.statusStream,
      initialData: usb.lastStatus,
      builder: (context, snapshot) => StreamBuilder<PlaybackState>(
        stream: handler?.playbackState,
        initialData: handler?.playbackState.value,
        builder: (context, _) {
          final status = snapshot.data ?? usb.lastStatus;
          return builder(
              _assessLiveChain(
                  outputDevice, settingsState, dsp, source, status, handler),
              status);
        },
      ),
    );
  }

  BitPerfectState _assessLiveChain(
    AudioOutputInfo? outputDevice,
    SettingsState? settings,
    DspSlice dsp,
    SongsTableData source,
    UsbExclusiveStatus usb,
    PulsrAudioHandler? handler,
  ) {
    final verdict = resolveLiveOutputVerdict(LiveOutputObservation(
      output: outputDevice,
      directStreamingActive: usb.streamingActive,
      streamingSampleRate: usb.streamingSampleRate,
      streamingBitDepth: usb.streamingBitDepth,
      rawPcmBitDepth: usb.rawPcmBitDepth,
      channelMismatchFrames: usb.channelMismatchFrames,
      rateVerified: usb.rateVerified,
      taggedSampleRate: source.sampleRate ?? 0,
      taggedBitDepth: source.bitDepth ?? 0,
      codec: source.codec,
      path: source.path,
      isRadioSource: source.source == SongSource.radio,
      bitPerfectOutput: settings?.bitPerfectOutput == true,
      strictBitPerfect: settings?.strictBitPerfect == true,
      bypassDspOnBitPerfect: settings?.bypassDspOnBitPerfect ?? true,
      dspEffectsActive: dsp.isDspActive,
      channelBalanceActive: dsp.stereoBalance != 0.0 || dsp.monoMix,
      ditherActive: dsp.isDitherEnabled,
      replayGainActive:
          settings != null && settings.replayGainMode != ReplayGainMode.off,
      dvcActive: settings?.dvcEnabled == true,
      transportSamplesModified: handler?.transportSamplesModified ?? true,
      softwareGain: handler?.effectiveSoftwareGain,
      isDsdDop: DsdDecoderHelper.dsdDopActive,
      isDsdNative: DsdDecoderHelper.dsdNativeActive ||
          (usb.streamingActive && usb.dsdActive),
      oversamplingActive: AudioEffectsChannel().activeOversampleMultiplier > 1,
      pcmToDsdActive: AudioEffectsChannel().isPcmToDsdActive,
    ));
    return verdict.state;
  }
}
