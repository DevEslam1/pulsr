import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import 'audio_quality_sheet.dart';

class AudioQualityBadge extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final bool compact;

  const AudioQualityBadge({
    super.key,
    required this.song,
    required this.activeColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (song == null) return const SizedBox.shrink();

    final settingsState = context.watch<SettingsCubit?>()?.state;
    final streamingQuality = settingsState?.streamingQuality;
    final info =
        AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);
    final output = settingsState?.currentOutputDevice;
    final isUsb = output?.isUsbDac == true;
    final isBitPerfect = output?.isBitPerfectActive == true;

    final outputRate = (output != null && output.targetSampleRate > 0)
        ? output.targetSampleRate ~/ 1000
        : (output != null ? output.sampleRate ~/ 1000 : 44);

    final outputBitDepth = (output != null && output.targetBitDepth > 0)
        ? output.targetBitDepth
        : (output?.bitDepth ?? 16);

    final deviceShortName = isUsb
        ? 'USB DAC'
        : (output?.deviceName.contains('Bluetooth') == true ||
                output?.deviceName.contains('A2DP') == true
            ? 'Bluetooth'
            : (output?.deviceName.contains('Speaker') == true
                ? 'Speaker'
                : 'DAC'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AudioQualitySheet.show(context, song!, activeColor),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 3 : 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                (isUsb ? const Color(0xFFFFD700) : info.badgeColor)
                    .withValues(alpha: 0.20),
                (isUsb ? const Color(0xFFFFD700) : info.badgeColor)
                    .withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (isUsb ? const Color(0xFFFFD700) : info.badgeColor)
                  .withValues(alpha: 0.45),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: (isUsb ? const Color(0xFFFFD700) : info.badgeColor)
                    .withValues(alpha: 0.14),
                blurRadius: 8,
                spreadRadius: -1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUsb ? Icons.usb_rounded : info.icon,
                size: compact ? 12 : 14,
                color: isUsb ? const Color(0xFFFFD700) : info.badgeColor,
              ),
              const SizedBox(width: 6),
              Text(
                info.shortBadgeLabel,
                style: TextStyle(
                  color: isUsb ? const Color(0xFFFFD700) : Colors.white,
                  fontSize: compact ? 10 : 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isBitPerfect
                    ? '$deviceShortName • Direct'
                    : '$deviceShortName • ${outputRate}kHz/${outputBitDepth}b',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: compact ? 9.5 : 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.tune_rounded,
                size: compact ? 11 : 13,
                color: (isUsb ? const Color(0xFFFFD700) : info.badgeColor)
                    .withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
