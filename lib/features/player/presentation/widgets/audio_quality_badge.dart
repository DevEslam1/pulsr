import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../../domain/models/ytm_audio_quality.dart';
import '../../../settings/cubit/settings_cubit.dart';
import 'audio_quality_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class AudioQualityBadge extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final bool compact;
  final bool showDevice;

  const AudioQualityBadge({
    super.key,
    required this.song,
    required this.activeColor,
    this.compact = false,
    this.showDevice = true,
  });

  @override
  Widget build(BuildContext context) {
    if (song == null) return const SizedBox.shrink();

    // F-14: select only the two settings fields this badge consumes instead
    // of watching the whole SettingsCubit state (any settings mutation used
    // to rebuild every badge in every player theme).
    final streamingQuality =
        context.select<SettingsCubit, YtmAudioQuality>((c) => c.state.streamingQuality);
    final output =
        context.select<SettingsCubit, AudioOutputInfo?>((c) => c.state.currentOutputDevice);
    final info =
        AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);
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
        borderRadius: BorderRadius.circular(AppRadii.r20),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 3 : 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                (isUsb ? AppColors.dacGold : info.badgeColor)
                    .withValues(alpha: 0.20),
                (isUsb ? AppColors.dacGold : info.badgeColor)
                    .withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadii.r20),
            border: Border.all(
              color: (isUsb ? AppColors.dacGold : info.badgeColor)
                  .withValues(alpha: 0.45),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: (isUsb ? AppColors.dacGold : info.badgeColor)
                    .withValues(alpha: 0.14),
                blurRadius: 8,
                spreadRadius: -1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUsb ? Icons.usb_rounded : info.icon,
                  size: compact ? 12 : 14,
                  color: isUsb ? AppColors.dacGold : info.badgeColor,
                ),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  info.shortBadgeLabel,
                  style: TextStyle(
                    color: isUsb ? AppColors.dacGold : Colors.white,
                    fontSize: compact ? AppFontSize.tiny : AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.overline,
                  ),
                ),
                if (showDevice) ...[
                  const SizedBox(width: AppSpacing.s6),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    isBitPerfect
                        ? '$deviceShortName • Direct'
                        : '$deviceShortName • ${outputRate}kHz/${outputBitDepth}b',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: compact ? AppFontSize.tiny : AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.tune_rounded,
                  size: compact ? 11 : 13,
                  color: (isUsb ? AppColors.dacGold : info.badgeColor)
                      .withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
