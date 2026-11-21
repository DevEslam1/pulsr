part of '../audio_quality_sheet.dart';

/// Compact live visual Signal Path header (`Source -> DSP -> Resampler -> Output`)
/// rendered at the top of [AudioQualitySheet] with status pills for every stage.
class AudioQualitySignalPathHeader extends StatelessWidget {
  final AudioQualityInfo info;
  final AudioOutputInfo? outputDevice;
  final SettingsState? settingsState;
  final DspSlice dsp;
  final BitPerfectState bitPerfectState;
  final UsbExclusiveStatus usbStatus;
  final Color activeColor;

  const AudioQualitySignalPathHeader({
    super.key,
    required this.info,
    required this.outputDevice,
    required this.settingsState,
    required this.dsp,
    required this.bitPerfectState,
    required this.usbStatus,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final assessment = bitPerfectState.assessment;
    final isBitPerfect = bitPerfectState.isVerified;
    final requested = settingsState?.bitPerfectOutput == true;
    final bool dspBypassed = settingsState?.strictBitPerfect == true ||
        AudioConflicts.dspBypassActive(
          bitPerfectOutput: requested,
          bypassDspOnBitPerfect: settingsState?.bypassDspOnBitPerfect ?? true,
          device: outputDevice,
        );

    // Stage 1: Source
    final sourceValue = info.format;

    // Stage 2: DSP
    final String dspValue;
    final Color dspColor;
    if (dspBypassed) {
      dspValue = context.l10n.dspStatusBypassed;
      dspColor = AppColors.dacGold;
    } else if (dsp.activeDspStagesCount > 0) {
      dspValue = '${dsp.activeDspStagesCount} ${context.l10n.dspStageStatusActive}';
      dspColor = activeColor;
    } else {
      dspValue = context.l10n.dspStageStatusOff;
      dspColor = p.textSecondary;
    }

    // Stage 3: Resampler
    final String resamplerValue;
    final Color resamplerColor;
    if (isBitPerfect) {
      resamplerValue = context.l10n.bpChainVerified;
      resamplerColor = p.success;
    } else if (assessment.verdict == BitPerfectChainVerdict.resampled) {
      resamplerValue = context.l10n.bpChainResampled;
      resamplerColor = p.warning;
    } else if (assessment.verdict == BitPerfectChainVerdict.depthReduced) {
      resamplerValue = context.l10n.bpChainDepthReduced;
      resamplerColor = p.warning;
    } else {
      final rate = assessment.outputSampleRate > 0
          ? assessment.outputSampleRate
          : (outputDevice?.sampleRate ?? 0);
      resamplerValue =
          rate > 0 ? _sampleRateLabel(rate) : context.l10n.audioQualityAuto;
      resamplerColor = p.textSecondary;
    }

    // Stage 4: Output / USB DAC
    final bool isUsb = outputDevice?.isUsbDac == true || usbStatus.attached;
    final bool isBt = outputDevice?.isBluetooth == true ||
        outputDevice?.btA2dpPresent == true;
    final String outputTitle = isUsb
        ? context.l10n.outputUsbDac
        : (isBt
            ? context.l10n.outputBluetooth
            : context.l10n.outputDeviceInternalDac);
    final String outputValue = isUsb
        ? (usbStatus.streamingActive
            ? 'UAC2'
            : (outputDevice?.usbAudioClass != null &&
                    outputDevice!.usbAudioClass > 0
                ? 'UAC${outputDevice!.usbAudioClass}'
                : context.l10n.outputUsbDac))
        : (isBt
            ? (outputDevice?.btCodecName ?? context.l10n.outputBluetooth)
            : (outputDevice?.sampleRate != null && outputDevice!.sampleRate > 0
                ? _sampleRateLabel(outputDevice!.sampleRate)
                : context.l10n.audioQualityAuto));
    final IconData outputIcon = isUsb
        ? Icons.usb_rounded
        : (isBt ? Icons.bluetooth_audio_rounded : Icons.speaker_rounded);
    final Color outputColor = isBitPerfect
        ? AppColors.dacGold
        : (isBt
            ? AppColors.accentCyan
            : (isUsb ? AppColors.dacGold : activeColor));

    final summaryText =
        '${context.l10n.dspSourceFile}: $sourceValue → '
        '${context.l10n.dspLabel}: $dspValue → '
        '${context.l10n.stageResampler}: $resamplerValue → '
        '$outputTitle: $outputValue';

    return Semantics(
      container: true,
      label: context.l10n.liveSignalChain,
      value: summaryText,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('audio_quality_signal_path_header'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.s10,
          ),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r16All,
            border: Border.all(
              color: isBitPerfect
                  ? AppColors.dacGold.withValues(alpha: 0.45)
                  : p.hairline,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderStagePill(
                  key: const ValueKey('signal_path_pill_source'),
                  icon: Icons.music_note_rounded,
                  stageLabel: context.l10n.dspSourceFile,
                  statusText: sourceValue,
                  accentColor: info.badgeColor,
                  p: p,
                ),
                _HeaderStageArrow(p: p),
                _HeaderStagePill(
                  key: const ValueKey('signal_path_pill_dsp'),
                  icon: dspBypassed
                      ? Icons.do_not_disturb_on_rounded
                      : Icons.tune_rounded,
                  stageLabel: context.l10n.dspLabel,
                  statusText: dspValue,
                  accentColor: dspColor,
                  p: p,
                ),
                _HeaderStageArrow(p: p),
                _HeaderStagePill(
                  key: const ValueKey('signal_path_pill_resampler'),
                  icon: Icons.transform_rounded,
                  stageLabel: context.l10n.stageResampler,
                  statusText: resamplerValue,
                  accentColor: resamplerColor,
                  p: p,
                ),
                _HeaderStageArrow(p: p),
                _HeaderStagePill(
                  key: const ValueKey('signal_path_pill_output'),
                  icon: outputIcon,
                  stageLabel: outputTitle,
                  statusText: outputValue,
                  accentColor: outputColor,
                  p: p,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderStagePill extends StatelessWidget {
  final IconData icon;
  final String stageLabel;
  final String statusText;
  final Color accentColor;
  final PulsrPalette p;

  const _HeaderStagePill({
    super.key,
    required this.icon,
    required this.stageLabel,
    required this.statusText,
    required this.accentColor,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: AppRadii.r10All,
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: AppSpacing.s4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stageLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                  height: 1.1,
                ),
              ),
              Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStageArrow extends StatelessWidget {
  final PulsrPalette p;

  const _HeaderStageArrow({required this.p});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 11,
        color: p.textTertiary,
      ),
    );
  }
}
