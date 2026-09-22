import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../../domain/services/hires_audio_service.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../domain/services/cast_service.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import 'pulsr_cast_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class AudioQualitySheet extends StatelessWidget {  final SongsTableData song;
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
    HapticFeedback.mediumImpact();
    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => AudioQualitySheet(song: song, activeColor: activeColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsCubit = context.watch<SettingsCubit?>();
    final settingsState = settingsCubit?.state;
    final streamingQuality = settingsState?.streamingQuality;
    final info = AudioQualityInfo.fromSong(
      song,
      streamingQuality: streamingQuality,
    );
    final outputDevice = settingsState?.currentOutputDevice;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.s14, AppSpacing.s20, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(AppRadii.r2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Hero Quality Tier Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.s18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          info.badgeColor.withValues(alpha: 0.22),
                          info.badgeColor.withValues(alpha: 0.05),
                          p.surfaceContainer.withValues(alpha: 0.4),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.r20),
                      border: Border.all(
                        color: info.badgeColor.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: info.badgeColor.withValues(alpha: 0.15),
                          blurRadius: 16,
                          spreadRadius: -2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: info.badgeColor.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                info.icon,
                                color: info.badgeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    info.tierLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: p.textPrimary,
                                          letterSpacing: AppTracking.label,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.s2),
                                  Text(
                                    info.shortBadgeLabel,
                                    style: TextStyle(
                                      color: info.badgeColor,
                                      fontSize: AppFontSize.label,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: AppTracking.overline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s10),
                        Text(
                          info.description,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // --- SECTION 1: HARDWARE OUTPUT ROUTING ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.hwOutputRouting,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          letterSpacing: AppTracking.wide,
                          fontWeight: FontWeight.w800,
                          color: p.textSecondary,
                        ),
                      ),
                      if (outputDevice?.isUsbDac == true)
                        Container(
                          padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s6,
                            vertical: AppSpacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(AppRadii.r6),
                          ),
                          child: Text(context.l10n.usbDacAttached,
                            style: TextStyle(
                              color: AppColors.dacGold,
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s10),

                  _buildOutputDevicesSelector(
                    context,
                    outputDevice,
                    settingsCubit,
                    p,
                    activeColor,
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  _buildCastOutputTile(context, p, activeColor),

                  // --- BLUETOOTH AUDIO CODEC CONTROL ---
                  if ((outputDevice?.isBluetooth == true) ||
                      (outputDevice?.btA2dpPresent == true)) ...[
                    const SizedBox(height: AppSpacing.s20),
                    _buildBluetoothCodecSection(
                      context,
                      outputDevice,
                      settingsCubit,
                      p,
                      activeColor,
                    ),
                  ],

                  // --- PHASE 4: OUTPUT PATH DIAGNOSTICS ---
                  const SizedBox(height: AppSpacing.s10),
                  Builder(
                    builder: (context) {
                      final uac = outputDevice?.usbAudioClass ?? 0;
                      final uacLabel = uac == 0 ? 'unknown' : 'UAC$uac';
                      final direct = outputDevice?.directFormats ?? const [];
                      final supported =
                          direct.where((f) => f.supported).toList();
                      final maxRate = supported.isEmpty
                          ? null
                          : supported
                              .map((f) => f.sampleRate)
                              .reduce((a, b) => a > b ? a : b);
                      final bits = supported.map((f) => f.encoding).toSet();
                      final bitsLabel = bits.isEmpty
                          ? '-'
                          : bits.contains('24')
                              ? (bits.contains('float') || bits.contains('32')
                                  ? '32f/24'
                                  : '24')
                              : (bits.contains('float') || bits.contains('32')
                                  ? '32f'
                                  : '-');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.outputPathDiag,
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
                                ? 'USB DAC: ${outputDevice?.usbDacLabel ?? "-"} ($uacLabel)'
                                : 'USB DAC: none attached',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            maxRate == null
                                ? 'DIRECT PLAYBACK: not reported'
                                : 'DIRECT PLAYBACK: up to $maxRate Hz / $bitsLabel',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(context.l10n.dsdPcmNote,
                            style: TextStyle(
                              fontSize: AppFontSize.tiny,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // --- SECTION 2: OUTPUT SAMPLE RATE CONTROL ---
                  Text(context.l10n.targetSampleRate,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      letterSpacing: AppTracking.wide,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  _buildSampleRateSelector(
                    context,
                    outputDevice,
                    settingsCubit,
                    p,
                    activeColor,
                    info,
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // --- SECTION 3: BIT DEPTH & BIT-PERFECT ---
                  Text(context.l10n.targetBitPerfect,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      letterSpacing: AppTracking.wide,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  _buildBitDepthSelector(
                    context,
                    outputDevice,
                    settingsCubit,
                    p,
                    activeColor,
                    info,
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // --- SECTION 4: AUDIO SPECIFICATIONS ---
                  Text(context.l10n.trackSourceSpecs,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      letterSpacing: AppTracking.wide,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s10),

                  // Specs Grid / List
                  Container(
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadii.r16),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      children: [
                        _buildSpecItem(
                          context,
                            icon: Icons.audio_file_rounded,
                            label: context.l10n.dspAudioFormatCodec,
                          value: info.format,
                          subValue: info.codecName,
                          p: p,
                          isFirst: true,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.speed_rounded,
                          label: context.l10n.dspSourceBitrate,
                          value: info.bitrateKbps != null
                              ? '${info.bitrateKbps} kbps'
                              : context.l10n.dspVariableBitrate,
                          subValue:
                              info.tier == AudioQualityTier.hiResLossless ||
                                      info.tier == AudioQualityTier.lossless
                                  ? context.l10n.dspBitPerfectLosslessStream
                                  : context.l10n.dspCompressedStream,
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.tune_rounded,
                          label: context.l10n.dspSourceSampleRateDepth,
                          value: '${info.bitDepth} / ${info.sampleRate}',
                          subValue: info.channels,
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.folder_zip_rounded,
                          label: context.l10n.dspFileSizeDuration,
                          value: song.fileSize != null
                              ? '${(song.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'
                              : context.l10n.dspUnknown,
                          subValue:
                              '${context.l10n.duration}: ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.graphic_eq_rounded,
                          label: context.l10n.dspDynamicRangeLra,
                          value: song.loudnessRange != null
                              ? '${song.loudnessRange!.toStringAsFixed(1)} LU (${song.loudnessRange! >= 12 ? context.l10n.dspDr12Audiophile : (song.loudnessRange! >= 7 ? context.l10n.dspDrHighDynamic : context.l10n.dspDrStandard)})'
                              : context.l10n.dspStandardDynamicRange,
                          subValue: context.l10n.dspEbuR128,
                          p: p,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // --- SECTION 5: LIVE SIGNAL CHAIN INDICATOR ---
                  Text(context.l10n.liveSignalChain,
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
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: activeColor,
                        foregroundColor: activeColor.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.applyDone,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.body,
                        ),
                      ),
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

  Widget _buildOutputDevicesSelector(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
  ) {
    final devices = outputDevice?.availableDevices ?? [];

    if (devices.isEmpty) {
      // Fallback display
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.r14),
          border: Border.all(color: activeColor, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                outputDevice?.isUsbDac == true
                    ? Icons.usb_rounded
                    : Icons.volume_up_rounded,
                color: activeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outputDevice?.deviceName ?? 'Phone Speaker',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: AppFontSize.bodySmall,
                    ),
                  ),
                  Text(
                    'Active system output device • Up to ${outputDevice != null ? (outputDevice.sampleRate ~/ 1000) : 48} kHz / ${outputDevice?.bitDepth ?? 16}-bit',
                    style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.caption),
                  ),
                ],
              ),
            ),
            Icon(Icons.check_circle_rounded, color: activeColor, size: 20),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...devices.map((dev) {
          final isSelected = dev.isCurrent;
          final devIcon = _getDeviceIcon(dev.type);

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AnimatedContainer(
              duration: context.motionMs(180),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.12)
                    : p.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadii.r14),
                border: Border.all(
                  color: isSelected ? activeColor : p.hairline,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.r14),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    cubit?.selectOutputDevice(dev.id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(

                      horizontal: AppSpacing.s14,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor.withValues(alpha: 0.2)
                                : p.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            devIcon,
                            size: 18,
                            color: isSelected ? activeColor : p.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dev.name,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${dev.typeName} • Up to ${dev.sampleRates.isEmpty ? "48" : (dev.sampleRates.reduce((a, b) => a > b ? a : b) ~/ 1000)} kHz / ${dev.maxBitDepth}-bit',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: context.motionMs(150),
                          child: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  key: const ValueKey('checked'),
                                  color: activeColor,
                                  size: 20,
                                )
                              : Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  key: const ValueKey('unchecked'),
                                  color: p.textTertiary,
                                  size: 20,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              cubit?.openOutputSwitcher();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: Text(context.l10n.switchOutputPanel,
              style: TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: p.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCastOutputTile(
    BuildContext context,
    PulsrPalette p,
    Color activeColor,
  ) {
    final session = CastService().sessionStatus;
    final isConnected = session.connected;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.r14),
      onTap: () => PulsrCastSheet.show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
        decoration: BoxDecoration(
          color: isConnected
              ? activeColor.withValues(alpha: 0.14)
              : p.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.r14),
          border: Border.all(
            color: isConnected ? activeColor : p.hairline,
            width: isConnected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: isConnected
                    ? activeColor.withValues(alpha: 0.20)
                    : p.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded,
                size: 18,
                color: isConnected ? activeColor : p.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected
                        ? 'Casting to ${session.deviceName ?? "Cast Device"}'
                        : 'Cast to Speaker / Display',
                    style: TextStyle(
                      color: isConnected ? activeColor : p.textPrimary,
                      fontSize: AppFontSize.bodySmall,
                      fontWeight:
                          isConnected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  Text(
                    isConnected
                        ? 'Tap to manage Cast volume or disconnect'
                        : 'Stream lossless/lossy audio over Wi-Fi',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.caption,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isConnected ? activeColor : p.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSampleRateSelector(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
    AudioQualityInfo info,
  ) {
    final isBitPerfectEnabled = cubit?.state.bitPerfectOutput == true;
    final isBitPerfectActive =
        isBitPerfectEnabled && outputDevice?.isBitPerfectActive == true;
    final currentTarget =
        isBitPerfectActive ? 0 : (outputDevice?.targetSampleRate ?? 0);

    // T5: only surface rates the current output actually reports. Both the
    // AudioOutputInfo rate list and Android's direct-playback probe feed the
    // filter, so a hi-res tier the device cannot honour is never advertised.
    final supportedRates = HiResAudioService.supportedSampleRateOptions(
      deviceSampleRates: outputDevice?.supportedSampleRates ?? const [],
      directFormats: outputDevice?.directFormats ?? const [],
    );
    final options = <(int, String, String)>[
      (0, 'Auto', 'Native'),
      for (final rate in supportedRates)
        (rate, _sampleRateLabel(rate), _sampleRateTag(rate)),
    ];

    const goldAccent = AppColors.dacGold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBitPerfectActive)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.r8),
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: goldAccent, size: 13),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  'Bit-Perfect Active • Locked to source track (${info.sampleRate})',
                  style: const TextStyle(
                    color: goldAccent,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
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
                      HapticFeedback.selectionClick();
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
  ) {
    final isUsbDac = outputDevice?.isUsbDac == true;
    final isBitPerfectEnabled = cubit?.state.bitPerfectOutput == true;
    final blockedReason = AudioConflicts.bitPerfectBlockedReason(outputDevice);
    final isBitPerfectActive =
        isBitPerfectEnabled && (outputDevice?.isBitPerfectActive == true);
    final currentTarget =
        isBitPerfectActive ? 0 : (outputDevice?.targetBitDepth ?? 0);

    final bitDepthOptions = [
      (0, 'Auto', 'Source'),
      (16, '16-bit', 'Standard'),
      (24, '24-bit', 'Hi-Res HD'),
      (32, '32-bit Float', 'Audiophile'),
    ];

    const goldAccent = AppColors.dacGold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBitPerfectActive)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.r8),
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: goldAccent, size: 13),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  'Bit-Perfect Active • Locked to source track (${info.bitDepth})',
                  style: const TextStyle(
                    color: goldAccent,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
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
                      HapticFeedback.selectionClick();
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
          duration: context.motionMs(200),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isBitPerfectEnabled
                ? goldAccent.withValues(alpha: 0.12)
                : p.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.r14),
            border: Border.all(
              color: isBitPerfectEnabled
                  ? goldAccent.withValues(alpha: 0.7)
                  : p.hairline,
              width: isBitPerfectEnabled ? 1.5 : 1.0,
            ),
            boxShadow: isBitPerfectEnabled
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
                  color: isBitPerfectEnabled
                      ? goldAccent.withValues(alpha: 0.22)
                      : p.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: isBitPerfectEnabled ? goldAccent : p.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(context.l10n.directBpMode,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.bodySmall,
                            color: isBitPerfectEnabled
                                ? goldAccent
                                : p.textPrimary,
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
                              borderRadius: BorderRadius.circular(AppRadii.r4),
                            ),
                            child: Text(context.l10n.activeLabel,
                              style: TextStyle(
                                color: goldAccent,
                                fontSize: AppFontSize.micro,
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
                              borderRadius: BorderRadius.circular(AppRadii.r4),
                            ),
                            child: Text(context.l10n.armedLabel,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.micro,
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
                                        ? 'Hardware direct pass-through active${isUsbDac ? " on USB DAC" : " (wired direct)"}'
                                        : 'Pass-through armed • Engages automatically when capable DAC is connected')
                                    : 'Bypasses Android mixer & DSP for bit-matched output (USB needs Android 14+, wired needs direct)'),
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
                          visualDensity: VisualDensity.compact,
                          tooltip: context.l10n.dspAboutBitPerfect,
                          onPressed: () {
                            PulsrDialogHelper.showCustomDialog<void>(
                              context,
                              builder: (ctx) => PulsrDialog(
                                title: context.l10n.bitPerfectMode,
                                icon: Icons.info_outline_rounded,
                                content: Text(
                                  AudioFeatureRegistry.bitPerfect.description,
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
              Switch.adaptive(
                value: isBitPerfectEnabled,
                activeTrackColor: goldAccent,
                activeThumbColor: Colors.white,
                onChanged: (blockedReason != null && !isBitPerfectEnabled)
                    ? null
                    : (val) {
                        if (blockedReason != null && val) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(blockedReason),
                              backgroundColor: p.error,
                            ),
                          );
                          return;
                        }
                        HapticFeedback.selectionClick();
                        cubit?.setBitPerfectOutput(val);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getDeviceIcon(int type) {
    // Android AudioDeviceInfo types
    switch (type) {
      case 2: // TYPE_BUILTIN_SPEAKER
        return Icons.volume_up_rounded;
      case 3: // TYPE_WIRED_HEADSET
      case 4: // TYPE_WIRED_HEADPHONES
        return Icons.headphones_rounded;
      case 7: // TYPE_BLUETOOTH_SCO
      case 8: // TYPE_BLUETOOTH_A2DP
      case 26: // TYPE_BLE_HEADSET
      case 27: // TYPE_BLE_SPEAKER
      case 30: // TYPE_BLE_BROADCAST
        return Icons.bluetooth_audio_rounded;
      case 23: // TYPE_HEARING_AID
        return Icons.hearing_rounded;
      case 9: // TYPE_HDMI
      case 10: // TYPE_HDMI_ARC
      case 29: // TYPE_HDMI_EARC
        return Icons.tv_rounded;
      case 11: // TYPE_USB_DEVICE
      case 22: // TYPE_USB_HEADSET
      case 12: // TYPE_USB_ACCESSORY
        return Icons.usb_rounded;
      case 13: // TYPE_DOCK
        return Icons.dock_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }

  Widget _buildSpecItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String subValue,
    required PulsrPalette p,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: !isLast ? Border(bottom: BorderSide(color: p.hairline)) : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadii.r10),
            ),
            child: Icon(icon, size: 18, color: p.textPrimary),
          ),
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: AppFontSize.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  subValue,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualSignalChain(
    BuildContext context,
    AudioQualityInfo info,
    AudioOutputInfo? outputDevice,
    SettingsState? settingsState,
    PulsrPalette p,
    Color activeColor,
  ) {
    final bool isBitPerfect = settingsState?.bitPerfectOutput == true &&
        outputDevice?.isUsbDac == true;
    final bool isDsd = info.format.toUpperCase().contains('DSD') ||
        info.codecName.toUpperCase().contains('DSD');

    final String sourceLabel = isDsd
        ? 'DSD Stream (${info.format})'
        : '${info.format} (${info.sampleRate} / ${info.bitDepth})';
    final String dspLabel = isBitPerfect
        ? 'Bypassed (Bit-Perfect Guardrail)'
        : 'EQ (8 RBJ) + True-Peak Limiter + BS2B';
    final String resamplerLabel = isBitPerfect
        ? 'Direct 1:1 Stream'
        : (outputDevice != null && outputDevice.targetSampleRate > 0
            ? 'Polyphase Sinc FIR (${info.sampleRate} → ${outputDevice.targetSampleRate ~/ 1000} kHz)'
            : 'Polyphase FIR Streaming Resampler');
    final String driverLabel = isBitPerfect
        ? 'AAudio Direct / Bit-Perfect Track'
        : 'Shared System AudioTrack';
    final String dacLabel = outputDevice?.deviceName ??
        (outputDevice?.isUsbDac == true ? 'USB Hi-Res DAC' : 'Internal DAC');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r16),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.dacGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.r8),
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
                    child: Text(context.l10n.bpGuardrails,
                      style: TextStyle(
                        color: AppColors.dacGold,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _buildSignalChainNode(
            step: 1,
            title: context.l10n.dspSourceFile,
            detail: sourceLabel,
            icon: Icons.music_note_rounded,
            color: info.badgeColor,
            p: p,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 2,
            title: context.l10n.dspDspProcessing,
            detail: dspLabel,
            icon: isBitPerfect
                ? Icons.do_not_disturb_on_rounded
                : Icons.tune_rounded,
            color: isBitPerfect ? p.textTertiary : activeColor,
            p: p,
            isDimmed: isBitPerfect,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 3,
            title: context.l10n.dspResamplingEngine,
            detail: resamplerLabel,
            icon: Icons.transform_rounded,
            color: isBitPerfect ? Colors.grey : p.success,
            p: p,
            isDimmed: isBitPerfect,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 4,
            title: context.l10n.dspOutputDriver,
            detail: driverLabel,
            icon: Icons.cable_rounded,
            color: isBitPerfect ? AppColors.dacGold : p.warning,
            p: p,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 5,
            title: context.l10n.dspHardwareEndpoint,
            detail:
                '$dacLabel (${outputDevice != null && outputDevice.targetSampleRate > 0 ? "${outputDevice.targetSampleRate ~/ 1000} kHz" : (outputDevice != null ? "${outputDevice.sampleRate ~/ 1000} kHz" : "48 kHz")} / ${outputDevice?.bitDepth ?? 24}-bit)',
            icon: outputDevice?.isUsbDac == true
                ? Icons.usb_rounded
                : Icons.speaker_rounded,
            color: outputDevice?.isUsbDac == true
                ? AppColors.dacGold
                : activeColor,
            p: p,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSignalChainNode({
    required int step,
    required String title,
    required String detail,
    required IconData icon,
    required Color color,
    required PulsrPalette p,
    bool isDimmed = false,
    bool isLast = false,
  }) {
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
                  fontSize: AppFontSize.tiny,
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

  Widget _buildSignalChainConnector(PulsrPalette p) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 13, top: AppSpacing.s2, bottom: AppSpacing.s2),
      child: Container(width: 2, height: 12, color: p.hairline),
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
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.45,
      child: AnimatedContainer(
        duration: context.motionMs(180),
        curve: context.motionCurve(Curves.easeOutCubic),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.16)
              : palette.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.r14),
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
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.r14),
            onTap: isEnabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
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
                      fontSize: AppFontSize.tiny,
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

// ── Bluetooth Codec Section ──────────────────────────────────────────────────

/// LE Audio-only codecs (LC3/Opus) are hidden on classic A2DP routes so users
/// never tap a chip the platform can never grant.
List<String> visibleBtCodecsForRoute(
    {required List<String> repoCodecs, required bool isLeAudio}) {
  if (isLeAudio) return List.of(repoCodecs);
  return repoCodecs.where((c) => c != 'LC3' && c != 'Opus').toList();
}

extension _BluetoothCodecSection on AudioQualitySheet {
  static const _btAccent = Color(0xFF00D4FF);
  static const _ldacAccent = AppColors.ldacViolet;
  static const _warnAccent = AppColors.warning;

  Widget _buildBluetoothCodecSection(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
  ) {
    final connected = outputDevice?.btCodecConnected ?? false;
    final reason = outputDevice?.btReason;
    final codecName = outputDevice?.btCodecName ?? 'AAC';
    final sampleRateHz = outputDevice?.btSampleRateHz ?? 44100;
    final bitDepth = outputDevice?.btBitDepth ?? 16;
    final ldacMode = outputDevice?.btLdacQualityMode;
    final selectableCodecs = outputDevice?.btSelectableCodecs ?? const [];
    final selectableRates = outputDevice?.btSelectableSampleRates ?? const [];
    final selectableDepths = outputDevice?.btSelectableBitDepths ?? const [];
    final isLdac = codecName == 'LDAC';

    const allCodecs = ['SBC', 'AAC', 'aptX', 'aptX HD', 'LDAC', 'LC3', 'Opus'];
    // LC3/Opus are LE Audio-only: hide them on classic A2DP so users never
    // tap a chip the platform can never grant.
    final isLeRoute = outputDevice?.isLeAudio ?? false;
    final repoCodecs =
        selectableCodecs.isNotEmpty ? selectableCodecs : allCodecs;
    final visibleCodecs = visibleBtCodecsForRoute(
        repoCodecs: repoCodecs, isLeAudio: isLeRoute);

    const ldacModes = [
      (0, 'Best Effort', 'Auto kbps'),
      (1, 'Mobile', '330 kbps'),
      (2, 'Standard', '660 kbps'),
      (3, 'Maximum', '990 kbps'),
    ];

    // ── State: permission required ───────────────────────────────────────
    if (reason == 'permission_required') {
      return _buildPermissionBanner(context, cubit, p);
    }

    // ── State: proxy initializing (BT stack not ready yet) ───────────────
    if (reason == 'proxy_initializing') {
      return _buildProxyLoadingBanner(context, cubit, p);
    }

    // ── State: LE Audio — LC3 is negotiated per-stream by the platform and
    // exposes no app-facing codec/rate/depth surface, so the A2DP controls
    // below would all be inert.
    if (reason == 'le_audio_not_configurable') {
      return _buildLeAudioBanner(context, cubit, p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Row(
          children: [
            const Icon(
              Icons.bluetooth_audio_rounded,
              size: 14,
              color: _btAccent,
            ),
            const SizedBox(width: AppSpacing.s6),
            Text(context.l10n.btAudioCodec,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                letterSpacing: AppTracking.wide,
                fontWeight: FontWeight.w800,
                color: p.textSecondary,
              ),
            ),
            const Spacer(),
            // Refresh button
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
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

        // ── Status card ─────────────────────────────────────────────────
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
            borderRadius: BorderRadius.circular(AppRadii.r16),
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
                            '${(sampleRateHz / 1000).toStringAsFixed(sampleRateHz % 1000 == 0 ? 0 : 1)} kHz'
                            ' · $bitDepth-bit'
                            '${isLdac && ldacMode != null ? ' · ${ldacModes[ldacMode.clamp(0, 3)].$3}' : ''}',
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
                      child: Text(context.l10n.earbudsConnected,
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

          // ── Codec chips: tap a supported codec to request it natively ──
          Text(context.l10n.supportedCodecs,
            style: TextStyle(
              fontSize: AppFontSize.tiny,
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
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                    child: GestureDetector(
                      onTap: isActive
                          ? null
                          : () async {
                              HapticFeedback.selectionClick();
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
                        borderRadius: BorderRadius.circular(AppRadii.r10),
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
                              fontWeight:
                                  isActive ? FontWeight.w800 : FontWeight.w500,
                              color: isActive ? accent : p.textSecondary,
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

          const SizedBox(height: AppSpacing.s14),

          // ── Sample rate + bit depth (tappable when the device reports ──
          // selectable options; read-only otherwise so users never tap a
          // control the platform can never grant) ─────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.sampleRateLabel,
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        letterSpacing: AppTracking.wide,
                        fontWeight: FontWeight.w700,
                        color: p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    GestureDetector(
                      onTap: selectableRates.isEmpty || cubit == null
                          ? null
                          : () => _showBtOptionPicker(
                                context: context,
                                cubit: cubit,
                                title: context.l10n.btSelectSampleRate,
                                options: selectableRates,
                                current: sampleRateHz,
                                label: (hz) =>
                                    '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz',
                                onPick: (v) =>
                                    cubit.setBluetoothSampleRate(v),
                              ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(

                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: _btAccent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppRadii.r10),
                          border: Border.all(
                            color: _btAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${(sampleRateHz / 1000).toStringAsFixed(sampleRateHz % 1000 == 0 ? 0 : 1)} kHz',
                                style: const TextStyle(
                                  color: _btAccent,
                                  fontSize: AppFontSize.body,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (selectableRates.isNotEmpty && cubit != null)
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
                    Text(context.l10n.bitDepthLabel,
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        letterSpacing: AppTracking.wide,
                        fontWeight: FontWeight.w700,
                        color: p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    GestureDetector(
                      onTap: selectableDepths.isEmpty || cubit == null
                          ? null
                          : () => _showBtOptionPicker(
                                context: context,
                                cubit: cubit,
                                title: context.l10n.btSelectBitDepth,
                                options: selectableDepths,
                                current: bitDepth,
                                label: (b) => '$b-bit',
                                onPick: (v) =>
                                    cubit.setBluetoothBitDepth(v),
                              ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(

                          horizontal: AppSpacing.s14,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: _btAccent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppRadii.r10),
                          border: Border.all(
                            color: _btAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$bitDepth-bit',
                                style: const TextStyle(
                                  color: _btAccent,
                                  fontSize: AppFontSize.body,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (selectableDepths.isNotEmpty && cubit != null)
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

          // ── LDAC quality indicator ────────────────────────────────────
          if (isLdac && ldacMode != null) ...[
            const SizedBox(height: AppSpacing.s14),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _ldacAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.s6),
                Text(context.l10n.ldacQuality,
                  style: TextStyle(
                    fontSize: AppFontSize.tiny,
                    letterSpacing: AppTracking.wide,
                    fontWeight: FontWeight.w700,
                    color: _ldacAccent.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: _ldacAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.r10),
                border: Border.all(color: _ldacAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Text(
                    ldacModes[ldacMode.clamp(0, 3)].$1 == 0
                        ? 'Best Effort'
                        : ldacModes[ldacMode.clamp(0, 3)].$1 == 1
                            ? 'Mobile'
                            : ldacModes[ldacMode.clamp(0, 3)].$1 == 2
                                ? 'Standard'
                                : 'Maximum',
                    style: const TextStyle(
                      color: _ldacAccent,
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    ldacModes[ldacMode.clamp(0, 3)].$3,
                    style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label),
                  ),
                  const Spacer(),
                  Row(
                    children: List.generate(
                      4,
                      (i) => Padding(
                        padding: const EdgeInsetsDirectional.only(start: 3),
                        child: GestureDetector(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final ok = await cubit?.setBluetoothLdacQuality(i) ??
                                false;
                            if (!ok && context.mounted) {
                              _showBtRefused(context, cubit);
                            }
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    i <= ldacMode ? _ldacAccent : p.hairline,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Open Developer Options shortcut ────────────────────────────
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () async {
              unawaited(HapticFeedback.mediumImpact());
              await cubit?.openBluetoothDevOptions();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _btAccent.withValues(alpha: 0.12),
                    _ldacAccent.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(AppRadii.r14),
                border: Border.all(color: _btAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _btAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.developer_mode_rounded,
                      color: _btAccent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.changeBtCodec,
                          style: TextStyle(
                            color: _btAccent,
                            fontSize: AppFontSize.bodySmall,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(context.l10n.devOptionsBtCodec,
                          style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.caption),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    color: _btAccent.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Stock ROMs refuse in-app codec switches (SystemApi): tell the user the
  /// platform refused and offer the Developer Options shortcut. Uses only
  /// existing l10n keys so the literal ratchet stays green.
  void _showBtRefused(BuildContext context, SettingsCubit? cubit) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(context.l10n.switchPrefFailed),
        action: SnackBarAction(
          label: context.l10n.devOptionsBtCodec,
          onPressed: () => cubit?.openBluetoothDevOptions(),
        ),
      ),
    );
  }

  /// Option picker for BT sample-rate / bit-depth, built from the
  /// device-reported selectable lists. Read-only callers must not invoke this
  /// (no options ⇒ nothing the platform can grant).
  Future<void> _showBtOptionPicker({
    required BuildContext context,
    required SettingsCubit? cubit,
    required String title,
    required List<int> options,
    required int current,
    required String Function(int value) label,
    required Future<bool> Function(int value) onPick,
  }) async {
    final sorted = List<int>.of(options)..sort();
    final selected = await PulsrSheetHelper.showPulsrSheet<int>(
      context: context,
      builder: (sheetCtx) {
        final sp = sheetCtx.palette;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.xxs),
                child: Text(
                  title,
                  style: TextStyle(
                    color: sp.textPrimary,
                    fontSize: AppFontSize.callout,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final opt in sorted)
                ListTile(
                  title: Text(
                    label(opt),
                    style: TextStyle(
                      color: opt == current ? _btAccent : sp.textPrimary,
                      fontWeight: opt == current
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: opt == current
                      ? const Icon(Icons.check_rounded,
                          color: _btAccent, size: 20)
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(opt),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == current || !context.mounted) return;
    HapticFeedback.selectionClick();
    final ok = await onPick(selected);
    if (!ok && context.mounted) _showBtRefused(context, cubit);
  }

  Widget _buildPermissionBanner(
    BuildContext context,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _warnAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: _warnAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bluetooth_audio_rounded,
                size: 14,
                color: _btAccent,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(context.l10n.btAudioCodec,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  letterSpacing: AppTracking.wide,
                  fontWeight: FontWeight.w800,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: _warnAccent,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(context.l10n.nearbyPermDesc,
                  style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () async {
              unawaited(HapticFeedback.mediumImpact());
              await _requestBluetoothPermission(context, cubit);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: _warnAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadii.r10),
                border: Border.all(color: _warnAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.settings_bluetooth_rounded,
                    color: _warnAccent,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(context.l10n.grantBtPerm,
                    style: TextStyle(
                      color: _warnAccent,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeAudioBanner(
    BuildContext context,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bluetooth_audio_rounded,
                size: 14, color: _btAccent),
            const SizedBox(width: AppSpacing.s6),
            Text(context.l10n.leAudio,
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
                HapticFeedback.selectionClick();
                cubit?.refreshOutputDevice();
              },
              child: Icon(Icons.refresh_rounded, size: 16, color: p.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            color: _btAccent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadii.r16),
            border: Border.all(color: _btAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: _btAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hearing_rounded,
                    color: _btAccent, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LC3',
                      style: TextStyle(
                        fontSize: AppFontSize.bodyLarge,
                        fontWeight: FontWeight.w900,
                        color: _btAccent,
                        letterSpacing: AppTracking.medium,
                      ),
                    ),
                    Text(context.l10n.lc3Negotiation,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProxyLoadingBanner(
    BuildContext context,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: _btAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: _btAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_audio_rounded, size: 14, color: _btAccent),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(context.l10n.connectingBt,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              cubit?.refreshOutputDevice();
            },
            child: Text(context.l10n.retry,
              style: TextStyle(
                color: _btAccent,
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestBluetoothPermission(
    BuildContext context,
    SettingsCubit? cubit,
  ) async {
    try {
      await cubit?.requestBluetoothPermission();
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 2));
    await cubit?.refreshOutputDevice();
  }
}
