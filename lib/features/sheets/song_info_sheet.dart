// lib/features/sheets/song_info_sheet.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/db/app_database.dart';
import '../tag_editor/tag_editor_screen.dart';

class SongInfoSheet extends StatelessWidget {
  final SongsTableData song;

  const SongInfoSheet({super.key, required this.song});

  void _shareSong(BuildContext context) {
    final text = 'Check out "${song.title}" by ${song.artist} on Pulsr Music!';
    final file = File(song.path);
    if (file.existsSync()) {
      Share.shareXFiles([XFile(song.path)], text: text);
    } else {
      Share.share(text);
    }
  }

  Future<void> _setRingtone(BuildContext context, String type) async {
    const channel = MethodChannel('com.example.pulsr/ringtone');
    try {
      final success = await channel.invokeMethod<bool>('setRingtone', {
        'filePath': song.path,
        'type': type,
      });
      if (context.mounted && (success ?? false)) {
        final label = type == 'notification'
            ? 'Notification sound'
            : type == 'alarm'
                ? 'Alarm sound'
                : 'Ringtone';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label set successfully!')),
        );
      }
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'PERMISSION_DENIED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permission required to change system settings'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                channel.invokeMethod('openWriteSettings');
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set ringtone: ${e.message}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to set ringtone: $e')),
      );
    }
  }

  void _showRingtoneOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.bottomSheetRadius,
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Set Audio As',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.ring_volume_rounded, color: AppColors.primary),
                  title: const Text('Phone Ringtone'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setRingtone(context, 'ringtone');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_active_rounded, color: AppColors.primary),
                  title: const Text('Notification Sound'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setRingtone(context, 'notification');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.alarm_rounded, color: AppColors.primary),
                  title: const Text('Alarm Sound'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setRingtone(context, 'alarm');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: const BorderSide(color: AppColors.outline),
                  ),
                  onPressed: () => _shareSong(context),
                  icon: const Icon(Icons.share_rounded, size: 20, color: AppColors.textPrimary),
                  label: const Text(
                    'Share',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ),
              if (defaultTargetPlatform == TargetPlatform.android) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: const BorderSide(color: AppColors.outline),
                    ),
                    onPressed: () => _showRingtoneOptions(context),
                    icon: const Icon(Icons.ring_volume_rounded, size: 20, color: AppColors.textPrimary),
                    label: const Text(
                      'Ringtone',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TagEditorScreen(song: song),
                  ),
                );
              },
              icon: const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text(
                'Edit Tags',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
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
