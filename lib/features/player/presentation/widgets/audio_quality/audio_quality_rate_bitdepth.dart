part of '../audio_quality_sheet.dart';

/// Sample-rate selector, bit-depth selector, Bit-Perfect switch (preserving all
/// [requestBitPerfectOutput] / `BitPerfectConflictDialog` guardrails), and
/// format label helpers for [AudioQualitySheet].
extension _AudioQualityRateBitDepth on AudioQualitySheet {
  Widget _buildSampleRateSelector(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
    AudioQualityInfo info,
    BitPerfectState state,
  ) {
    final isBitPerfectActive = state.isVerified;
    final currentTarget =
        isBitPerfectActive ? 0 : (outputDevice?.targetSampleRate ?? 0);

    final supportedRates = HiResAudioService.supportedSampleRateOptions(
      deviceSampleRates: outputDevice?.supportedSampleRates ?? const [],
      directFormats: outputDevice?.directFormats ?? const [],
    );
    final options = <(int, String, String)>[
      (
        0,
        context.l10n.audioQualityAuto,
        context.l10n.audioQualitySystemManaged
      ),
      for (final rate in supportedRates)
        (rate, _sampleRateLabel(rate), _sampleRateTag(rate)),
    ];

    const goldAccent = AppColors.dacGold;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.audioQualityFormatFollowsEngine,
            style: TextStyle(
                color: p.textSecondary, fontSize: AppFontSize.caption)),
        if (isBitPerfectActive)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.12),
              borderRadius: AppRadii.r8All,
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: goldAccent, size: 13),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    context.l10n.exclusiveMixerPrefix(
                        _outputStreamDescription(context, outputDevice)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: goldAccent,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: options.map((opt) {
                final isSelected = (currentTarget == opt.$1);
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: _OptionPill(
                    title: opt.$2,
                    subtitle: opt.$3,
                    isSelected: isSelected,
                    isEnabled: !isBitPerfectActive,
                    activeColor: activeColor,
                    palette: p,
                    onTap: () {
                      PulsrHaptics.selectionClick();
                      cubit?.setTargetOutputSampleRate(opt.$1);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBitDepthSelector(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
    AudioQualityInfo info,
    BitPerfectState state,
  ) {
    final surfacePalette = context.playerSurfacePalette;
    final animate = PulsrMotion.shouldAnimate(context);
    final isBitPerfectEnabled = cubit?.state.bitPerfectOutput == true;
    final blockedReason = AudioConflicts.bitPerfectBlockedReason(outputDevice);
    final isBitPerfectActive = state.isVerified;
    final currentTarget =
        isBitPerfectActive ? 0 : (outputDevice?.targetBitDepth ?? 0);

    final bitDepthOptions = [
      (
        0,
        context.l10n.audioQualityAuto,
        context.l10n.audioQualitySystemManaged
      ),
      (16, '16-bit', context.l10n.audioQualityStandard),
      (24, '24-bit', 'Hi-Res HD'),
      (32, '32-bit', 'PCM'),
    ];

    const goldAccent = AppColors.dacGold;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.audioQualityFormatFollowsEngine,
            style: TextStyle(
                color: p.textSecondary, fontSize: AppFontSize.caption)),
        if (isBitPerfectActive)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.12),
              borderRadius: AppRadii.r8All,
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: goldAccent, size: 13),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    context.l10n.exclusiveMixerPrefix(
                        _outputStreamDescription(context, outputDevice)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: goldAccent,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: bitDepthOptions.map((opt) {
                final isSelected = (currentTarget == opt.$1);
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: _OptionPill(
                    title: opt.$2,
                    subtitle: opt.$3,
                    isSelected: isSelected,
                    isEnabled: !isBitPerfectActive,
                    activeColor: activeColor,
                    palette: p,
                    onTap: () {
                      PulsrHaptics.selectionClick();
                      cubit?.setTargetOutputBitDepth(opt.$1);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedContainer(
          duration: animate ? context.motionMs(200) : Duration.zero,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isBitPerfectActive
                ? goldAccent.withValues(alpha: 0.12)
                : p.surfaceContainer,
            borderRadius: AppRadii.r14All,
            border: Border.all(
              color: isBitPerfectActive
                  ? goldAccent.withValues(alpha: 0.7)
                  : p.hairline,
              width: isBitPerfectActive ? 1.5 : 1.0,
            ),
            boxShadow: isBitPerfectActive
                ? [
                    BoxShadow(
                      color: goldAccent.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: isBitPerfectActive
                      ? goldAccent.withValues(alpha: 0.22)
                      : p.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: isBitPerfectActive ? goldAccent : p.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.l10n.directBpMode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: AppFontSize.bodySmall,
                              color: isBitPerfectActive
                                  ? goldAccent
                                  : p.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        if (isBitPerfectActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s6,
                              vertical: AppSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: goldAccent.withValues(alpha: 0.25),
                              borderRadius: AppRadii.r4All,
                            ),
                            child: Text(
                              context.l10n.activeLabel,
                              style: const TextStyle(
                                color: goldAccent,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w900,
                                letterSpacing: AppTracking.medium,
                              ),
                            ),
                          )
                        else if (isBitPerfectEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s6,
                              vertical: AppSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.2),
                              borderRadius: AppRadii.r4All,
                            ),
                            child: Text(
                              context.l10n.armedLabel,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w800,
                                letterSpacing: AppTracking.medium,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            blockedReason != null && !isBitPerfectEnabled
                                ? blockedReason
                                : (isBitPerfectEnabled
                                    ? (isBitPerfectActive
                                        ? context.l10n
                                            .bitPerfectSourcePreservedUnmeasured
                                        : context.l10n.bpPassThroughArmed)
                                    : context
                                        .l10n.bitPerfectRequestsExclusiveUsb),
                            style: TextStyle(
                              color:
                                  blockedReason != null && !isBitPerfectEnabled
                                      ? p.error
                                      : (isBitPerfectEnabled
                                          ? p.textPrimary.withValues(
                                              alpha: 0.85,
                                            )
                                          : p.textSecondary),
                              fontSize: AppFontSize.caption,
                              height: 1.25,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: p.textTertiary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget,
                          ),
                          tooltip: context.l10n.dspAboutBitPerfect,
                          onPressed: () {
                            PulsrDialogHelper.showCustomDialog<void>(
                              context,
                              builder: (ctx) => PulsrDialog(
                                title: context.l10n.bitPerfectMode,
                                icon: Icons.info_outline_rounded,
                                content: Text(
                                  AudioFeatureRegistry.bitPerfect
                                      .localized(context.l10n)
                                      .description,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.bodySmall,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text(context.l10n.gotIt),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch.adaptive(
                value: isBitPerfectEnabled,
                activeTrackColor: goldAccent,
                activeThumbColor: surfacePalette.highContrastInk,
                onChanged: (blockedReason != null && !isBitPerfectEnabled)
                    ? null
                    : (val) async {
                        if (blockedReason != null && val) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(blockedReason),
                              backgroundColor: p.error,
                            ),
                          );
                          return;
                        }
                        PulsrHaptics.selectionClick();
                        if (cubit == null) return;
                        String? capturedError;
                        final sub = cubit.stream.listen((s) {
                          if (s.errorMessage != null) {
                            capturedError = s.errorMessage;
                          }
                        });
                        bool attempted = false;
                        try {
                          attempted =
                              await requestBitPerfectOutput(context, val);
                        } finally {
                          await sub.cancel();
                        }
                        if (!attempted || !val || !context.mounted) return;
                        if (cubit.state.bitPerfectOutput) return;
                        PulsrToast.show(
                          context,
                          isError: true,
                          duration: const Duration(seconds: 8),
                          position: PulsrToastPosition.top,
                          maxLines: 6,
                          message: cubit.state.errorMessage ??
                              capturedError ??
                              context.l10n.bitPerfectUnsupportedDevice,
                        );
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionPill extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isEnabled;
  final Color activeColor;
  final PulsrPalette palette;
  final VoidCallback onTap;

  const _OptionPill({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    this.isEnabled = true,
    required this.activeColor,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final animate = PulsrMotion.shouldAnimate(context);
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.45,
      child: AnimatedContainer(
        duration: animate ? context.motionMs(200) : Duration.zero,
        curve: PulsrMotion.resolveCurve(context, PulsrMotion.enter),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.16)
              : palette.surfaceContainer,
          borderRadius: AppRadii.r14All,
          border: Border.all(
            color: isSelected ? activeColor : palette.hairline,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected && isEnabled
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadii.r14All,
            onTap: isEnabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? activeColor : palette.textPrimary,
                      letterSpacing: AppTracking.none,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? activeColor.withValues(alpha: 0.85)
                          : palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _outputStreamDescription(BuildContext context, AudioOutputInfo? output) {
  final l10n = context.l10n;
  if (output == null || output.sampleRate <= 0 || output.bitDepth <= 0) {
    return l10n.appStreamFormatUnverified;
  }
  final frames = output.nativeFramesPerBuffer ?? 0;
  final nativeRate = output.nativeSampleRate ?? 0;
  final bufferMs = (frames > 0 && nativeRate > 0)
      ? (frames / nativeRate * 1000).toStringAsFixed(1)
      : null;
  final spec = l10n.appStreamFormatSpec(
    _sampleRateLabel(output.sampleRate),
    output.bitDepth,
    output.pcmEncoding == 4 ? 'float' : 'PCM',
  );
  return bufferMs == null
      ? spec
      : '$spec • ${l10n.appStreamPrimaryBufferHint(bufferMs)}';
}

String _sampleRateLabel(int rate) {
  switch (rate) {
    case 44100:
      return '44.1 kHz';
    case 48000:
      return '48 kHz';
    case 88200:
      return '88.2 kHz';
    case 96000:
      return '96 kHz';
    case 176400:
      return '176.4 kHz';
    case 192000:
      return '192 kHz';
    case 352800:
      return '352.8 kHz';
    case 384000:
      return '384 kHz';
    case 705600:
      return '705.6 kHz';
    case 768000:
      return '768 kHz';
    default:
      return '${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1)} kHz';
  }
}

String _sampleRateTag(int rate) {
  switch (rate) {
    case 44100:
      return 'CD';
    case 48000:
      return 'Std';
    case 88200:
      return '2x';
    case 96000:
      return 'Studio';
    case 176400:
      return '4x';
    case 192000:
      return 'Master';
    case 352800:
      return '8x';
    case 384000:
      return 'Ultra';
    case 705600:
      return '16x';
    case 768000:
      return 'Max';
    default:
      return 'Hi-Res';
  }
}
