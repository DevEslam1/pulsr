// lib/features/sheets/song_info_sheet.dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/db/app_database.dart';

class SongInfoSheet extends StatelessWidget {
  final SongsTableData song;

  const SongInfoSheet({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.bottomSheetRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 64, borderRadius: 14),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          _buildInfoRow('Album', song.album),
          _buildInfoRow('Duration', Formatters.formatDuration(Duration(milliseconds: song.durationMs))),
          _buildInfoRow('File Path', song.path),
          _buildInfoRow('Play Count', '${song.playCount} times'),
          if (song.fileSize != null)
            _buildInfoRow('File Size', '${(song.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
