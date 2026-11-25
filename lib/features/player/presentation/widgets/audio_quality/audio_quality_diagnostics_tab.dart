part of '../audio_quality_sheet.dart';

/// Diagnostics tab content for [AudioQualitySheet]: USB Audio Class probe,
/// 4-stage [AudioSignalPathCard], and 6-node live signal chain custody view.
extension _AudioQualityDiagnosticsTab on AudioQualitySheet {
  List<Widget> _buildDiagnosticsChildren({
    required BuildContext context,
    required AudioQualityInfo info,
    required SongsTableData resolvedSong,
    required AudioOutputInfo? outputDevice,
    required SettingsState? settingsState,
    required DspSlice dspSlice,
    required BitPerfectState state,
    required UsbExclusiveStatus usbStatus,
    required PulsrPalette p,
  }) {
    return <Widget>[
      // Output Path Diagnostics / USB Probe
      _buildUsbProbeSummary(context, outputDevice, p),
      const SizedBox(height: AppSpacing.md),

      // Real-Time 4-Stage Audio Signal Path Readout
      AudioSignalPathCard(
        signalPath: AudioSignalPath.fromOutputInfo(
          sourceCodec: info.format,
          sourceSampleRate: effectiveSourceSampleRate(
            tagged: resolvedSong.sampleRate ?? 0,
            decoded: outputDevice?.decodedSampleRate ?? 0,
          ),
          sourceBitDepth: effectiveSourceBitDepth(
            tagged: resolvedSong.bitDepth ?? 0,
            decoded: outputDevice?.decodedBitDepth ?? 0,
          ),
          isDsdSource: info.format.toUpperCase().contains('DSD') ||
              info.codecName.toUpperCase().contains('DSD'),
          output: outputDevice,
          uac2DirectActive: usbStatus.streamingActive,
          aaudioEnabled: settingsState?.aaudioOutputEnabled == true,
          floatOutputEnabled: settingsState?.floatOutputEnabled == true,
          bitPerfectState: state,
          dspActive: dspSlice.isDspActive,
          dspDescription: dspSlice.isEqEnabled
              ? 'EQ Active'
              : (dspSlice.isLimiterEnabled
                  ? 'Limiter Active'
                  : (dspSlice.isDspActive ? 'DSP Active' : null)),
        ),
        activeColor: activeColor,
      ),
      const SizedBox(height: AppSpacing.md),

      // Live Signal Chain Indicator & Custody
      Text(
        context.l10n.liveSignalChain,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          letterSpacing: AppTracking.wide,
          fontWeight: FontWeight.w800,
          color: p.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.s10),
      _buildVisualSignalChain(
        context,
        info,
        outputDevice,
        settingsState,
        p,
        activeColor,
        dspSlice,
        state,
        usbStatus: usbStatus,
      ),
    ];
  }

  Widget _buildUsbProbeSummary(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    PulsrPalette p,
  ) {
    final uac = outputDevice?.usbAudioClass ?? 0;
    final uacLabel = uac == 0 ? 'unknown' : 'UAC$uac';
    final direct = outputDevice?.directFormats ?? const [];
    final advertised = UsbExclusiveService().lastStatus.advertisedFormats;
    final supported = direct.where((f) => f.supported).toList();
    final int? maxRateAdvertised = advertised.isNotEmpty
        ? advertised
            .map((f) =>
                (f['supportedRates'] as List<dynamic>?)?.cast<int>() ?? <int>[])
            .expand((r) => r)
            .fold<int?>(null, (max, r) => max == null || r > max ? r : max)
        : null;
    final int? maxRateStatus = UsbExclusiveService()
        .lastStatus
        .supportedRates
        .fold<int?>(null, (max, r) => max == null || r > max ? r : max);
    final int? maxRateSupported = supported.isEmpty
        ? null
        : supported.map((f) => f.sampleRate).reduce((a, b) => a > b ? a : b);
    final int? maxRate = maxRateAdvertised ?? maxRateStatus ?? maxRateSupported;
    final bits = advertised.isNotEmpty
        ? advertised
            .map((f) => f['bitResolution']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
        : supported.map((f) => f.encoding).toSet();
    final bitsLabel = bits.isEmpty
        ? '-'
        : bits.contains('24')
            ? (bits.contains('float') || bits.contains('32') ? '32/24' : '24')
            : (bits.contains('float') || bits.contains('32') ? '32' : '-');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.outputPathDiag,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            letterSpacing: AppTracking.wide,
            fontWeight: FontWeight.w800,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text(
          outputDevice?.isUsbDac == true
              ? context.l10n.usbDacConnectedSummary(
                  outputDevice?.usbDacLabel ?? '-', uacLabel)
              : context.l10n.usbDacNoneAttached,
          style: TextStyle(
            fontSize: AppFontSize.label,
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          maxRate == null
              ? context.l10n.directPlaybackNotReported
              : context.l10n.directPlaybackUpTo(maxRate.toString(), bitsLabel),
          style: TextStyle(
            fontSize: AppFontSize.label,
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          context.l10n.audioQualityCapabilityProbe,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: p.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildVisualSignalChain(
    BuildContext context,
    AudioQualityInfo info,
    AudioOutputInfo? outputDevice,
    SettingsState? settingsState,
    PulsrPalette p,
    Color activeColor,
    DspSlice dsp,
    BitPerfectState state, {
    UsbExclusiveStatus? usbStatus,
  }) {
    final assessment = state.assessment;
    final requested = settingsState?.bitPerfectOutput == true;
    final bool dspBypassed = settingsState?.strictBitPerfect == true ||
        AudioConflicts.dspBypassActive(
          bitPerfectOutput: requested,
          bypassDspOnBitPerfect: settingsState?.bypassDspOnBitPerfect ?? true,
          device: outputDevice,
        );
    final bool isDsd = info.format.toUpperCase().contains('DSD') ||
        info.codecName.toUpperCase().contains('DSD');

    final String sourceLabel = isDsd
        ? 'DSD Stream (${info.format})'
        : (info.bitDepth.isNotEmpty && info.bitDepth != 'Unknown'
            ? '${info.format} (${info.sampleRate} / ${info.bitDepth})'
            : (info.sampleRate != 'Unknown' && info.sampleRate.isNotEmpty
                ? '${info.format} (${info.sampleRate})'
                : info.format));
    final decRate = outputDevice?.decodedSampleRate ?? 0;
    final decDepth = outputDevice?.decodedBitDepth ?? 0;
    final decEnc = outputDevice?.decodedPcmEncoding ?? 0;
    final sourceDepth = assessment.sourceBitDepth > 0
        ? assessment.sourceBitDepth
        : (int.tryParse(info.bitDepth.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);
    final effectiveDepth = decDepth > 0 ? decDepth : sourceDepth;
    final decoderLabel = decRate > 0 && effectiveDepth > 0
        ? '${AudioSignalPath.pcmEncodingName(decEnc, effectiveDepth)} • '
            '${_sampleRateLabel(decRate)} / $effectiveDepth-bit'
        : AudioSignalPath.pcmEncodingName(decEnc, effectiveDepth);

    final List<String> namedStages = [
      if (dsp.isEqEnabled) context.l10n.stageEq,
      if (dsp.isLimiterEnabled) context.l10n.stageLimiter,
      if (dsp.isCrossfeedEnabled) context.l10n.stageCrossfeed,
      if (dsp.isReverbEnabled) context.l10n.stageReverb,
    ];
    final int unnamedStages = dsp.activeDspStagesCount -
        (dsp.isEqEnabled ? 1 : 0) -
        (dsp.isLimiterEnabled ? 1 : 0) -
        (dsp.isCrossfeedEnabled ? 1 : 0) -
        (dsp.isReverbEnabled ? 1 : 0);
    final List<String> activeStages = [
      ...namedStages,
      if (unnamedStages > 0) context.l10n.bpMoreEffects(unnamedStages),
    ];
    final effectiveUsbStatus = usbStatus ?? UsbExclusiveService().lastStatus;
    final String dspLabel = dspBypassed
        ? context.l10n.bpDspBypassed
        : (activeStages.isEmpty
            ? context.l10n.bpDspCleanPath
            : activeStages.join(' + '));
    final isBitPerfect = state.isVerified;
    final resamplerLabel = state.isVerified
        ? '${_sampleRateLabel(assessment.outputSampleRate)} / '
            '${assessment.outputBitDepth}-bit • ${context.l10n.bpChainVerified}'
        : switch (assessment.verdict) {
            BitPerfectChainVerdict.resampled =>
              '${_sampleRateLabel(assessment.sourceSampleRate)} → '
                  '${_sampleRateLabel(assessment.outputSampleRate)} • '
                  '${context.l10n.bpChainResampled}',
            BitPerfectChainVerdict.depthReduced =>
              '${assessment.sourceBitDepth}-bit → '
                  '${assessment.outputBitDepth}-bit • '
                  '${context.l10n.bpChainDepthReduced}',
            BitPerfectChainVerdict.inactive => context.l10n.bpChainInactive,
            BitPerfectChainVerdict.notRequested =>
              context.l10n.bpChainNotRequested,
            BitPerfectChainVerdict.verified ||
            BitPerfectChainVerdict.unverified =>
              liveChainReasonLabel(context, state.reasonCode),
          };
    final resamplerColor = assessment.isProblem
        ? p.warning
        : (state.isVerified ? p.success : p.textSecondary);
    final driverLabel = effectiveUsbStatus.streamingActive
        ? 'Pulsr UAC2 Isochronous Sink • ${_outputStreamDescription(context, outputDevice)}'
        : (settingsState?.aaudioOutputEnabled == true
            ? 'AAudio • ${_outputStreamDescription(context, outputDevice)}'
            : 'Media3 AudioTrack • ${_outputStreamDescription(context, outputDevice)}');
    final dacLabel = outputDevice?.deviceName ??
        (outputDevice?.isUsbDac == true
            ? context.l10n.outputDeviceUsbHiResDac
            : context.l10n.outputDeviceInternalDac);
    final bool floatCarrierActive =
        outputDevice?.floatCarrierDecodesSource == true;
    final int hardwareRate = assessment.outputSampleRate > 0
        ? assessment.outputSampleRate
        : (outputDevice?.sampleRate ?? 0);
    final int hardwareDepth = assessment.outputBitDepth > 0
        ? assessment.outputBitDepth
        : (floatCarrierActive ? 0 : (outputDevice?.bitDepth ?? 0));
    final bool hardwareFormatKnown = hardwareRate > 0 && hardwareDepth > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: isBitPerfect
              ? AppColors.dacGold.withValues(alpha: 0.4)
              : p.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBitPerfect) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.dacGold.withValues(alpha: 0.12),
                borderRadius: AppRadii.r8All,
                border: Border.all(
                  color: AppColors.dacGold.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.dacGold,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.bpGuardrails,
                      style: const TextStyle(
                        color: AppColors.dacGold,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (assessment.isProblem)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.warning.withValues(alpha: 0.12),
                borderRadius: AppRadii.r8All,
                border: Border.all(color: p.warning.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: p.warning, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _chainWarningText(context, assessment),
                      style: TextStyle(
                        color: p.warning,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _SignalChainNode(
            step: 1,
            title: context.l10n.dspSourceFile,
            detail: sourceLabel,
            icon: Icons.music_note_rounded,
            color: info.badgeColor,
            p: p,
          ),
          _SignalChainConnector(p: p),
          _SignalChainNode(
            step: 2,
            title: context.l10n.dspDecoderOutput,
            detail: decoderLabel,
            icon: Icons.memory_rounded,
            color: activeColor,
            p: p,
          ),
          _SignalChainConnector(p: p),
          _SignalChainNode(
            step: 3,
            title: context.l10n.dspDspProcessing,
            detail: dspLabel,
            icon: isBitPerfect
                ? Icons.do_not_disturb_on_rounded
                : Icons.tune_rounded,
            color: isBitPerfect ? p.textTertiary : activeColor,
            p: p,
            isDimmed: isBitPerfect,
          ),
          _SignalChainConnector(p: p),
          _SignalChainNode(
            step: 4,
            title: context.l10n.dspResamplingEngine,
            detail: resamplerLabel,
            icon: Icons.transform_rounded,
            color: resamplerColor,
            p: p,
            isDimmed: isBitPerfect && !assessment.isProblem,
          ),
          _SignalChainConnector(p: p),
          _SignalChainNode(
            step: 5,
            title: context.l10n.dspOutputDriver,
            detail: driverLabel,
            icon: Icons.cable_rounded,
            color: isBitPerfect
                ? AppColors.dacGold
                : (assessment.isProblem ? p.warning : activeColor),
            p: p,
          ),
          _SignalChainConnector(p: p),
          _SignalChainNode(
            step: 6,
            title: context.l10n.dspHardwareEndpoint,
            detail: hardwareFormatKnown
                ? context.l10n.hardwareFormatReportedByPlatform(
                    dacLabel,
                    _sampleRateLabel(hardwareRate),
                    hardwareDepth,
                  )
                : context.l10n.hardwareFormatNotVerified(dacLabel),
            icon: outputDevice?.isUsb == true
                ? Icons.usb_rounded
                : (outputDevice?.isBt == true
                    ? Icons.bluetooth_audio_rounded
                    : (outputDevice?.isHeadphones == true
                        ? Icons.headphones_rounded
                        : Icons.speaker_rounded)),
            color: isBitPerfect
                ? AppColors.dacGold
                : (assessment.isProblem ? p.warning : activeColor),
            p: p,
            isLast: true,
          ),
        ],
      ),
    );
  }

  String _chainWarningText(
      BuildContext context, BitPerfectChainAssessment assessment) {
    switch (assessment.verdict) {
      case BitPerfectChainVerdict.resampled:
        return '${context.l10n.bpChainResampled}: '
            '${_sampleRateLabel(assessment.sourceSampleRate)} → '
            '${_sampleRateLabel(assessment.outputSampleRate)}';
      case BitPerfectChainVerdict.depthReduced:
        return '${context.l10n.bpChainDepthReduced}: '
            '${assessment.sourceBitDepth}-bit → '
            '${assessment.outputBitDepth}-bit';
      case BitPerfectChainVerdict.inactive:
        final explained =
            AudioConflicts.bitPerfectReasonMessage(assessment.reasonCode);
        return explained == null
            ? context.l10n.bpChainInactive
            : '${context.l10n.bpChainInactive}: $explained';
      case BitPerfectChainVerdict.verified:
      case BitPerfectChainVerdict.notRequested:
      case BitPerfectChainVerdict.unverified:
        return '';
    }
  }
}

class _SignalChainNode extends StatelessWidget {
  final int step;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final PulsrPalette p;
  final bool isDimmed;
  final bool isLast;

  const _SignalChainNode({
    required this.step,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.p,
    this.isDimmed = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDimmed ? 0.08 : 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: isDimmed ? 0.2 : 0.6),
            ),
          ),
          child: Icon(
            icon,
            color: color.withValues(alpha: isDimmed ? 0.5 : 1.0),
            size: 14,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  letterSpacing: AppTracking.wide,
                  fontWeight: FontWeight.w800,
                  color: isDimmed
                      ? p.textSecondary.withValues(alpha: 0.5)
                      : p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w700,
                  color: isDimmed
                      ? p.textPrimary.withValues(alpha: 0.5)
                      : p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignalChainConnector extends StatelessWidget {
  final PulsrPalette p;

  const _SignalChainConnector({required this.p});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 13,
        top: AppSpacing.s2,
        bottom: AppSpacing.s2,
      ),
      child: Container(width: 2, height: 12, color: p.hairline),
    );
  }
}
