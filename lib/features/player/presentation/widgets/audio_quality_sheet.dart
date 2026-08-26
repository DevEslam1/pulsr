import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/db/app_database.dart';
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
    final streamingQuality = context.watch<SettingsCubit?>()?.state.streamingQuality;
    final info = AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
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
                        const SizedBox(height: 12),
                        Text(
                          info.description,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'AUDIO SPECIFICATIONS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
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
                          label: 'Audio Format',
                          value: info.format,
                          subValue: info.codecName,
                          p: p,
                          isFirst: true,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.speed_rounded,
                          label: 'Bitrate',
                          value: info.bitrateKbps != null ? '${info.bitrateKbps} kbps' : 'Variable Bitrate',
                          subValue: info.tier == AudioQualityTier.hiResLossless || info.tier == AudioQualityTier.lossless
                              ? 'Bit-perfect Lossless Stream'
                              : 'Compressed Audio Stream',
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.tune_rounded,
                          label: 'Sample Rate & Depth',
                          value: '${info.bitDepth} / ${info.sampleRate}',
                          subValue: info.channels,
                          p: p,
                        ),
                        _buildSpecItem(
                          context,
                          icon: Icons.folder_zip_rounded,
                          label: 'File Size',
                          value: song.fileSize != null
                              ? '${(song.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'
                              : 'Unknown',
                          subValue: 'Duration: ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                          p: p,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Hardware Route & USB DAC Card
                  Builder(
                    builder: (context) {
                      final outputDevice = context.watch<SettingsCubit?>()?.state.currentOutputDevice;
                      final isUsb = outputDevice?.isUsbDac == true;
                      final isBitPerfect = outputDevice?.isBitPerfectActive == true;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isUsb
                              ? const Color(0xFFFFD700).withValues(alpha: 0.08)
                              : p.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isUsb
                                ? const Color(0xFFFFD700).withValues(alpha: 0.35)
                                : p.hairline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isUsb ? Icons.usb_rounded : Icons.headphones_rounded,
                              color: isUsb ? const Color(0xFFFFD700) : activeColor,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Hardware Output: ${outputDevice?.deviceName ?? "Default Audio"}${isBitPerfect ? " • Direct Bit-Perfect" : ""}',
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  // Playback Engine Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: activeColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.memory_rounded, color: activeColor, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Render Engine: ${info.renderEngineDescription}',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: p.hairline),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Done',
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
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
