import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';

class AudioQualitySheet extends StatelessWidget {
  final SongsTableData song;
  final Color activeColor;

  const AudioQualitySheet({
    super.key,
    required this.song,
    required this.activeColor,
  });

  static void show(
      BuildContext context, SongsTableData song, Color activeColor) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      builder: (sheetContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(sheetContext).pop(),
        child: GestureDetector(
          onTap: () {}, // Prevent taps on the sheet card itself from closing
          child: AudioQualitySheet(song: song, activeColor: activeColor),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsCubit = context.watch<SettingsCubit?>();
    final settingsState = settingsCubit?.state;
    final streamingQuality = settingsState?.streamingQuality;
    final info =
        AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Hero Quality Tier Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
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
                      borderRadius: BorderRadius.circular(20),
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
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: info.badgeColor.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(info.icon,
                                  color: info.badgeColor, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    info.tierLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: p.textPrimary,
                                          letterSpacing: 0.2,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    info.shortBadgeLabel,
                                    style: TextStyle(
                                      color: info.badgeColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          info.description,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- SECTION 1: HARDWARE OUTPUT ROUTING ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'HARDWARE OUTPUT ROUTING',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                          color: p.textSecondary,
                        ),
                      ),
                      if (outputDevice?.isUsbDac == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFFD700).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'USB DAC ATTACHED',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  _buildOutputDevicesSelector(
                      context, outputDevice, settingsCubit, p, activeColor),

                  const SizedBox(height: 20),

                  // --- SECTION 2: OUTPUT SAMPLE RATE CONTROL ---
                  Text(
                    'TARGET OUTPUT SAMPLE RATE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildSampleRateSelector(context, outputDevice, settingsCubit,
                      p, activeColor, info),

                  const SizedBox(height: 20),

                  // --- SECTION 3: BIT DEPTH & BIT-PERFECT ---
                  Text(
                    'TARGET BIT DEPTH & BIT-PERFECT',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildBitDepthSelector(context, outputDevice, settingsCubit,
                      p, activeColor, info),

                  const SizedBox(height: 20),

                  // --- SECTION 4: AUDIO SPECIFICATIONS ---
                  Text(
                    'TRACK SOURCE SPECIFICATIONS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Specs Grid / List
                  Container(
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Column(
                      children: [
                        _buildSpecItem(
                          context,
                          icon: Icons.audio_file_rounded,
                          label: 'Audio Format & Codec',
                          value: info.format,
                          subValue: info.codecName,
                          p: p,
                          isFirst: true,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.speed_rounded,
                          label: 'Source Bitrate',
                          value: info.bitrateKbps != null
                              ? '${info.bitrateKbps} kbps'
                              : 'Variable Bitrate',
                          subValue:
                              info.tier == AudioQualityTier.hiResLossless ||
                                      info.tier == AudioQualityTier.lossless
                                  ? 'Bit-perfect Lossless Stream'
                                  : 'Compressed Audio Stream',
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.tune_rounded,
                          label: 'Source Sample Rate & Depth',
                          value: '${info.bitDepth} / ${info.sampleRate}',
                          subValue: info.channels,
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.folder_zip_rounded,
                          label: 'File Size & Duration',
                          value: song.fileSize != null
                              ? '${(song.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'
                              : 'Unknown',
                          subValue:
                              'Duration: ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.graphic_eq_rounded,
                          label: 'Dynamic Range (LRA)',
                          value: song.loudnessRange != null
                              ? '${song.loudnessRange!.toStringAsFixed(1)} LU (${song.loudnessRange! >= 12 ? "DR 12+ Audiophile" : (song.loudnessRange! >= 7 ? "DR High Dynamic" : "DR Standard")})'
                              : 'Standard Dynamic Range',
                          subValue: 'EBU R128 Loudness Range Analysis',
                          p: p,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- SECTION 5: LIVE SIGNAL CHAIN INDICATOR ---
                  Text(
                    'LIVE AUDIO SIGNAL CHAIN',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildVisualSignalChain(
                    context,
                    info,
                    outputDevice,
                    settingsState,
                    p,
                    activeColor,
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeColor,
                        foregroundColor: activeColor.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Apply & Done',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: activeColor, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outputDevice?.deviceName ?? 'Phone Speaker',
                    style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                  Text(
                    'Active system output device • Up to ${outputDevice != null ? (outputDevice.sampleRate ~/ 1000) : 48} kHz / ${outputDevice?.bitDepth ?? 16}-bit',
                    style: TextStyle(color: p.textSecondary, fontSize: 11),
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
      children: devices.map((dev) {
        final isSelected = dev.isCurrent;
        final devIcon = _getDeviceIcon(dev.type);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.12)
                  : p.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  cubit?.selectOutputDevice(dev.id);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dev.name,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${dev.typeName} • Up to ${dev.sampleRates.isEmpty ? "48" : (dev.sampleRates.reduce((a, b) => a > b ? a : b) ~/ 1000)} kHz / ${dev.maxBitDepth}-bit',
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: isSelected
                            ? Icon(Icons.check_circle_rounded,
                                key: const ValueKey('checked'),
                                color: activeColor,
                                size: 20)
                            : Icon(Icons.radio_button_unchecked_rounded,
                                key: const ValueKey('unchecked'),
                                color: p.textTertiary,
                                size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
    final isUsbDac = outputDevice?.isUsbDac == true;
    final isBitPerfectEnabled = cubit?.state.bitPerfectOutput == true;
    final isBitPerfectActive = isBitPerfectEnabled && isUsbDac;
    final currentTarget =
        isBitPerfectActive ? 0 : (outputDevice?.targetSampleRate ?? 0);

    final options = [
      (0, 'Auto', 'Native'),
      (44100, '44.1 kHz', 'CD'),
      (48000, '48 kHz', 'Std'),
      (88200, '88.2 kHz', '2x'),
      (96000, '96 kHz', 'Studio'),
      (192000, '192 kHz', 'Master'),
      (384000, '384 kHz', 'Ultra'),
    ];

    const goldAccent = Color(0xFFFFD700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBitPerfectActive)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: goldAccent, size: 13),
                const SizedBox(width: 6),
                Text(
                  'Bit-Perfect Active • Locked to source track (${info.sampleRate})',
                  style: const TextStyle(
                    color: goldAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: options.map((opt) {
                final isSelected = (currentTarget == opt.$1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
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
    final isBitPerfectActive = isBitPerfectEnabled && isUsbDac;
    final currentTarget =
        isBitPerfectActive ? 0 : (outputDevice?.targetBitDepth ?? 0);

    final bitDepthOptions = [
      (0, 'Auto', 'Source'),
      (16, '16-bit', 'Standard'),
      (24, '24-bit', 'Hi-Res HD'),
      (32, '32-bit Float', 'Audiophile'),
    ];

    const goldAccent = Color(0xFFFFD700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBitPerfectActive)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: goldAccent, size: 13),
                const SizedBox(width: 6),
                Text(
                  'Bit-Perfect Active • Locked to source track (${info.bitDepth})',
                  style: const TextStyle(
                    color: goldAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: bitDepthOptions.map((opt) {
                final isSelected = (currentTarget == opt.$1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
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
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isBitPerfectEnabled
                ? goldAccent.withValues(alpha: 0.12)
                : p.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
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
                padding: const EdgeInsets.all(8),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Direct Bit-Perfect Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isBitPerfectEnabled
                                ? goldAccent
                                : p.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isBitPerfectActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: goldAccent.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: goldAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          )
                        else if (isBitPerfectEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ARMED',
                              style: TextStyle(
                                color: p.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBitPerfectEnabled
                          ? (isUsbDac
                              ? 'Hardware direct pass-through active on USB DAC'
                              : 'Pass-through armed • Engages automatically when USB DAC is connected')
                          : 'Bypasses Android mixer & DSP for bit-matched output (Requires USB DAC & Android 14+)',
                      style: TextStyle(
                        color: isBitPerfectEnabled
                            ? p.textPrimary.withValues(alpha: 0.85)
                            : p.textSecondary,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isBitPerfectEnabled,
                activeTrackColor: goldAccent,
                activeThumbColor: Colors.white,
                onChanged: (val) {
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
        return Icons.bluetooth_audio_rounded;
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: !isLast ? Border(bottom: BorderSide(color: p.hairline)) : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: p.textPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                Text(
                  subValue,
                  style: TextStyle(
                    fontSize: 11,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isBitPerfect
                ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                : p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBitPerfect) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded,
                      color: Color(0xFFFFD700), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bit-Perfect Guardrails Active: DSP processing & software volume bypassed. Adjust volume via hardware DAC.',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10.5,
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
            title: 'SOURCE FILE',
            detail: sourceLabel,
            icon: Icons.music_note_rounded,
            color: info.badgeColor,
            p: p,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 2,
            title: 'DSP PROCESSING',
            detail: dspLabel,
            icon: isBitPerfect
                ? Icons.do_not_disturb_on_rounded
                : Icons.tune_rounded,
            color: isBitPerfect ? Colors.grey : activeColor,
            p: p,
            isDimmed: isBitPerfect,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 3,
            title: 'RESAMPLING ENGINE',
            detail: resamplerLabel,
            icon: Icons.transform_rounded,
            color: isBitPerfect ? Colors.grey : Colors.cyanAccent,
            p: p,
            isDimmed: isBitPerfect,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 4,
            title: 'OUTPUT DRIVER',
            detail: driverLabel,
            icon: Icons.cable_rounded,
            color: isBitPerfect ? const Color(0xFFFFD700) : Colors.orangeAccent,
            p: p,
          ),
          _buildSignalChainConnector(p),
          _buildSignalChainNode(
            step: 5,
            title: 'HARDWARE ENDPOINT',
            detail:
                '$dacLabel (${outputDevice != null && outputDevice.targetSampleRate > 0 ? "${outputDevice.targetSampleRate ~/ 1000} kHz" : (outputDevice != null ? "${outputDevice.sampleRate ~/ 1000} kHz" : "48 kHz")} / ${outputDevice?.bitDepth ?? 24}-bit)',
            icon: outputDevice?.isUsbDac == true
                ? Icons.usb_rounded
                : Icons.speaker_rounded,
            color: outputDevice?.isUsbDac == true
                ? const Color(0xFFFFD700)
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
                color: color.withValues(alpha: isDimmed ? 0.2 : 0.6)),
          ),
          child: Icon(icon,
              color: color.withValues(alpha: isDimmed ? 0.5 : 1.0), size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w800,
                  color: isDimmed
                      ? p.textSecondary.withValues(alpha: 0.5)
                      : p.textSecondary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 11.5,
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
      padding: const EdgeInsets.only(left: 13, top: 2, bottom: 2),
      child: Container(
        width: 2,
        height: 12,
        color: p.hairline,
      ),
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.16)
              : palette.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
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
            borderRadius: BorderRadius.circular(14),
            onTap: isEnabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? activeColor : palette.textPrimary,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
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
