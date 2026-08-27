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

class AudioQualitySheet extends StatelessWidget {
  final SongsTableData song;
  final Color activeColor;

  const AudioQualitySheet({
    super.key,
    required this.song,
    required this.activeColor,
  });

  static void show(BuildContext context, SongsTableData song, Color activeColor) {
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
    final info = AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);
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
                              child: Icon(info.icon, color: info.badgeColor, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    info.tierLabel,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.18),
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

                  _buildOutputDevicesSelector(context, outputDevice, settingsCubit, p),

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

                  _buildSampleRateSelector(context, outputDevice, settingsCubit, p),

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

                  _buildBitDepthSelector(context, outputDevice, settingsCubit, p),

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
                          value: info.bitrateKbps != null ? '${info.bitrateKbps} kbps' : 'Variable Bitrate',
                          subValue: info.tier == AudioQualityTier.hiResLossless || info.tier == AudioQualityTier.lossless
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
                          subValue: 'Duration: ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
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

                  // Signal Flow Summary Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: activeColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.route_rounded, color: activeColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Audio Signal Chain',
                                style: TextStyle(
                                  color: activeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${info.format} (${info.sampleRate}) ➔ DSP Resampler (${outputDevice != null && outputDevice.targetSampleRate > 0 ? "${outputDevice.targetSampleRate ~/ 1000} kHz" : (outputDevice != null ? "${outputDevice.sampleRate ~/ 1000} kHz" : "Native")}) ➔ ${outputDevice?.deviceName ?? "Default DAC"}',
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeColor,
                        foregroundColor: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Apply & Done',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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
  ) {
    final devices = outputDevice?.availableDevices ?? [];

    if (devices.isEmpty) {
      // Fallback display
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Icon(
              outputDevice?.isUsbDac == true ? Icons.usb_rounded : Icons.headphones_rounded,
              color: activeColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outputDevice?.deviceName ?? 'Default Audio Output',
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    'Active system output device',
                    style: TextStyle(color: p.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
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
          child: Material(
            color: isSelected ? activeColor.withValues(alpha: 0.12) : p.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.selectionClick();
                cubit?.selectOutputDevice(dev.id);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? activeColor : p.hairline,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? activeColor.withValues(alpha: 0.2) : p.surface,
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
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${dev.typeName} • Up to ${dev.sampleRates.isEmpty ? "48" : (dev.sampleRates.reduce((a, b) => a > b ? a : b) ~/ 1000)} kHz / ${dev.maxBitDepth}-bit',
                            style: TextStyle(color: p.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: activeColor, size: 20)
                    else
                      Icon(Icons.radio_button_unchecked_rounded, color: p.textSecondary, size: 20),
                  ],
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
  ) {
    final currentTarget = outputDevice?.targetSampleRate ?? 0;

    final options = [
      (0, 'Auto', 'Native'),
      (44100, '44.1 kHz', 'CD'),
      (48000, '48 kHz', 'Std'),
      (88200, '88.2 kHz', '2x'),
      (96000, '96 kHz', 'Studio'),
      (192000, '192 kHz', 'Master'),
      (384000, '384 kHz', 'Ultra'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final isSelected = (currentTarget == opt.$1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    opt.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? (activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                          : p.textPrimary,
                    ),
                  ),
                  Text(
                    opt.$3,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? (activeColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white70)
                          : p.textSecondary,
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              selectedColor: activeColor,
              backgroundColor: p.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? activeColor : p.hairline,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  HapticFeedback.selectionClick();
                  cubit?.setTargetOutputSampleRate(opt.$1);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBitDepthSelector(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    final currentTarget = outputDevice?.targetBitDepth ?? 0;
    final isBitPerfectActive = outputDevice?.isBitPerfectActive == true;

    final bitDepthOptions = [
      (0, 'Auto', 'Source'),
      (16, '16-bit', 'Standard'),
      (24, '24-bit', 'Hi-Res HD'),
      (32, '32-bit Float', 'Audiophile'),
    ];

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: bitDepthOptions.map((opt) {
              final isSelected = (currentTarget == opt.$1);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        opt.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? (activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                              : p.textPrimary,
                        ),
                      ),
                      Text(
                        opt.$3,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? (activeColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white70)
                              : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: activeColor,
                  backgroundColor: p.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? activeColor : p.hairline,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      HapticFeedback.selectionClick();
                      cubit?.setTargetOutputBitDepth(opt.$1);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        if (outputDevice?.isBitPerfectSupported == true || outputDevice?.isUsbDac == true) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isBitPerfectActive
                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                  : p.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isBitPerfectActive ? const Color(0xFFFFD700) : p.hairline,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Direct Bit-Perfect Mode',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      Text(
                        'Bypasses OS audio mixer for pure hardware bit-matching',
                        style: TextStyle(color: p.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isBitPerfectActive,
                  activeTrackColor: const Color(0xFFFFD700),
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
}
