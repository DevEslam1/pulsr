part of '../audio_quality_sheet.dart';

/// LE Audio-only codecs (LC3/Opus) are hidden on classic A2DP routes so users
/// never tap a chip the platform can never grant.
List<String> visibleBtCodecsForRoute(
    {required List<String> repoCodecs, required bool isLeAudio}) {
  if (isLeAudio) return List.of(repoCodecs);
  return repoCodecs.where((c) => c != 'LC3' && c != 'Opus').toList();
}

extension _BluetoothCodecSection on AudioQualitySheet {
  static const _btAccent = AppColors.accentCyan;
  static const _ldacAccent = AppColors.ldacViolet;

  Widget _buildBluetoothCodecSection(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
  ) {
    final connected = outputDevice?.btCodecConnected ?? false;
    final canConfigure = outputDevice?.canConfigureBluetooth == true &&
        outputDevice?.isBluetooth == true;
    final reason = outputDevice?.btReason;
    final codecName = outputDevice?.btCodecName ?? 'Unknown';
    final sampleRateHz = outputDevice?.btSampleRateHz ?? 0;
    final bitDepth = outputDevice?.btBitDepth ?? 0;
    final ldacMode = outputDevice?.btLdacQualityMode;
    final selectableCodecs = outputDevice?.btSelectableCodecs ?? const [];
    final selectableRates = outputDevice?.btSelectableSampleRates ?? const [];
    final selectableDepths = outputDevice?.btSelectableBitDepths ?? const [];
    final isLdac = codecName == 'LDAC';

    const allCodecs = ['SBC', 'AAC', 'aptX', 'aptX HD', 'LDAC', 'LC3', 'Opus'];
    final isLeRoute = outputDevice?.isLeAudio ?? false;
    final repoCodecs =
        selectableCodecs.isNotEmpty ? selectableCodecs : allCodecs;
    final visibleCodecs =
        visibleBtCodecsForRoute(repoCodecs: repoCodecs, isLeAudio: isLeRoute);

    final ldacModes = [
      (
        0,
        context.l10n.audioQualityBestEffort,
        context.l10n.audioQualityAutoKbps
      ),
      (1, context.l10n.audioQualityMobile, '330 kbps'),
      (2, context.l10n.audioQualityStandard, '660 kbps'),
      (3, context.l10n.audioQualityMaximum, '990 kbps'),
    ];

    if (reason == 'permission_required') {
      return _buildPermissionBanner(context, cubit, p);
    }
    if (reason == 'proxy_initializing') {
      return _buildProxyLoadingBanner(context, cubit, p);
    }
    if (reason == 'le_audio_not_configurable') {
      return _buildLeAudioBanner(context, cubit, p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(
              Icons.bluetooth_audio_rounded,
              size: 14,
              color: _btAccent,
            ),
            const SizedBox(width: AppSpacing.s6),
            Text(
              context.l10n.btAudioCodec,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                letterSpacing: AppTracking.wide,
                fontWeight: FontWeight.w800,
                color: p.textSecondary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                PulsrHaptics.selectionClick();
                cubit?.refreshOutputDevice();
              },
              child: Icon(
                Icons.refresh_rounded,
                size: 16,
                color: p.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        // Status card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _btAccent.withValues(alpha: connected ? 0.15 : 0.07),
                p.surfaceContainer.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadii.r16All,
            border: Border.all(
              color: _btAccent.withValues(alpha: connected ? 0.45 : 0.2),
            ),
          ),
          child: connected
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: isLdac
                            ? _ldacAccent.withValues(alpha: 0.2)
                            : _btAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.high_quality_rounded,
                        color: isLdac ? _ldacAccent : _btAccent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            codecName,
                            style: TextStyle(
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.w900,
                              color: isLdac ? _ldacAccent : _btAccent,
                              letterSpacing: AppTracking.medium,
                            ),
                          ),
                          Text(
                            '${sampleRateHz > 0 ? _sampleRateLabel(sampleRateHz) : context.l10n.outputRateUnknown}'
                            '${bitDepth > 0 ? " / ${context.l10n.bitDepthValue('$bitDepth')}" : " / ${context.l10n.depthUnknown}"}'
                            '${outputDevice?.btEstimatedBitrateKbps != null ? " · ~${outputDevice!.btEstimatedBitrateKbps} kbps" : ""}',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isLdac && ldacMode != null)
                      Row(
                        children: List.generate(
                          4,
                          (i) => Padding(
                            padding: const EdgeInsetsDirectional.only(start: 3),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i <= ldacMode ? _ldacAccent : p.hairline,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      Icons.bluetooth_connected_rounded,
                      color: _btAccent.withValues(alpha: 0.5),
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Text(
                        context.l10n.earbudsConnected,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.label,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
        ),

        if (connected) ...[
          const SizedBox(height: AppSpacing.s14),

          // Codec chips
          Text(
            context.l10n.supportedCodecs,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              letterSpacing: AppTracking.wide,
              fontWeight: FontWeight.w700,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: visibleCodecs.map((c) {
                  final isActive = c == codecName;
                  final isLdacOpt = c == 'LDAC';
                  final accent = isLdacOpt ? _ldacAccent : _btAccent;
                  return Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                    child: GestureDetector(
                      onTap: isActive ||
                              !canConfigure ||
                              !selectableCodecs.contains(c)
                          ? null
                          : () async {
                              PulsrHaptics.selectionClick();
                              final ok =
                                  await cubit?.setBluetoothCodec(c) ?? false;
                              if (!ok && context.mounted) {
                                _showBtRefused(context, cubit);
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? accent.withValues(alpha: 0.18)
                              : p.surfaceContainer,
                          borderRadius: AppRadii.r10All,
                          border: Border.all(
                            color: isActive ? accent : p.hairline,
                            width: isActive ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isActive) ...[
                              Icon(
                                Icons.check_rounded,
                                color: accent,
                                size: 11,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                            ],
                            Text(
                              c,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: isActive
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isActive
                                    ? accent
                                    : canConfigure
                                        ? p.textSecondary
                                        : p.textTertiary,
                                letterSpacing: AppTracking.label,
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
          ),
          if (!isLeRoute)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpacing.s6),
              child: Text(
                context.l10n.leAudioRequiresBle,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: p.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.s14),

          // Sample rate + bit depth pickers
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sampleRateLabel,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        letterSpacing: AppTracking.wide,
                        fontWeight: FontWeight.w700,
                        color: p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    GestureDetector(
                      onTap: !canConfigure ||
                              selectableRates.isEmpty ||
                              cubit == null
                          ? null
                          : () => _showBtOptionPicker(
                                context: context,
                                cubit: cubit,
                                title: context.l10n.btSelectSampleRate,
                                options: selectableRates,
                                current: sampleRateHz,
                                label: (hz) =>
                                    '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz',
                                onPick: (v) => cubit.setBluetoothSampleRate(v),
                              ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: _btAccent.withValues(alpha: 0.10),
                          borderRadius: AppRadii.r10All,
                          border: Border.all(
                            color: _btAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                sampleRateHz > 0
                                    ? _sampleRateLabel(sampleRateHz)
                                    : context.l10n.outputRateUnknown,
                                style: const TextStyle(
                                  color: _btAccent,
                                  fontSize: AppFontSize.body,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (canConfigure &&
                                selectableRates.isNotEmpty &&
                                cubit != null)
                              const Icon(
                                Icons.arrow_drop_down_rounded,
                                color: _btAccent,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.bitDepthLabel,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        letterSpacing: AppTracking.wide,
                        fontWeight: FontWeight.w700,
                        color: p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    GestureDetector(
                      onTap: !canConfigure ||
                              selectableDepths.isEmpty ||
                              cubit == null
                          ? null
                          : () => _showBtOptionPicker(
                                context: context,
                                cubit: cubit,
                                title: context.l10n.btSelectBitDepth,
                                options: selectableDepths,
                                current: bitDepth,
                                label: (b) => '$b-bit',
                                onPick: (v) => cubit.setBluetoothBitDepth(v),
                              ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: _btAccent.withValues(alpha: 0.10),
                          borderRadius: AppRadii.r10All,
                          border: Border.all(
                            color: _btAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                bitDepth > 0
                                    ? context.l10n.bitDepthValue('$bitDepth')
                                    : context.l10n.dspUnknown,
                                style: const TextStyle(
                                  color: _btAccent,
                                  fontSize: AppFontSize.body,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (canConfigure &&
                                selectableDepths.isNotEmpty &&
                                cubit != null)
                              const Icon(
                                Icons.arrow_drop_down_rounded,
                                color: _btAccent,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // LDAC quality indicator
          if (isLdac && ldacMode != null) ...[
            const SizedBox(height: AppSpacing.s14),
            _buildLdacQualityCard(
              context: context,
              cubit: cubit,
              p: p,
              ldacMode: ldacMode,
              ldacModes: ldacModes,
              canConfigure: canConfigure,
            ),
          ],

          // Open Developer Options shortcut
          const SizedBox(height: AppSpacing.md),
          _buildBtDevOptionsTile(context, cubit, p),
        ],
      ],
    );
  }
}
