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

    final streamingQuality = context.watch<SettingsCubit?>()?.state.streamingQuality;
    final info = AudioQualityInfo.fromSong(song, streamingQuality: streamingQuality);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AudioQualitySheet.show(context, song!, activeColor),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                info.badgeColor.withValues(alpha: 0.18),
                info.badgeColor.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: info.badgeColor.withValues(alpha: 0.4),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: info.badgeColor.withValues(alpha: 0.12),
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
                info.icon,
                size: compact ? 11 : 13,
                color: info.badgeColor,
              ),
              const SizedBox(width: 5),
              Text(
                info.shortBadgeLabel,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                size: compact ? 12 : 14,
                color: info.badgeColor.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
