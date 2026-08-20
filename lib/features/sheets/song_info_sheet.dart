// lib/features/sheets/song_info_sheet.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_radii.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/adaptive.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/audio_quality_info.dart';
import '../player/presentation/widgets/audio_quality_badge.dart';

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
    const channel = MethodChannel('com.pulsr.music/ringtone');
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
    final p = context.palette;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: p.surface,
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
                    color: p.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Set Audio As',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.ring_volume_rounded, color: p.accent),
                  title: Text('Phone Ringtone', style: TextStyle(color: p.textPrimary)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setRingtone(context, 'ringtone');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.notifications_active_rounded, color: p.accent),
                  title: Text('Notification Sound', style: TextStyle(color: p.textPrimary)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setRingtone(context, 'notification');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.alarm_rounded, color: p.accent),
                  title: Text('Alarm Sound', style: TextStyle(color: p.textPrimary)),
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
    final p = context.palette;
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
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                                    fontWeight: FontWeight.w800,
                                    color: p.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Divider(color: p.hairline),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final quality = AudioQualityInfo.fromSong(song);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'QUALITY & CODEC',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: p.textSecondary,
                                ),
                              ),
                              AudioQualityBadge(song: song, activeColor: p.accent, compact: true),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow('Audio Format', quality.format, p),
                          if (quality.bitrateKbps != null)
                            _buildInfoRow('Bitrate', '${quality.bitrateKbps} kbps (${quality.tierLabel})', p),
                          _buildInfoRow('Sample Rate', '${quality.bitDepth} / ${quality.sampleRate}', p),
                          _buildInfoRow('Channels', quality.channels, p),
                          const SizedBox(height: 6),
                          Divider(color: p.hairline),
                          const SizedBox(height: 6),
                        ],
                      );
                    },
                  ),
                  _buildInfoRow('Album', song.album, p),
                  _buildInfoRow('Duration', Formatters.formatDuration(Duration(milliseconds: song.durationMs)), p),
                  _buildInfoRow('File Path', song.path, p),
                  _buildInfoRow('Play Count', '${song.playCount} times', p),
                  if (song.fileSize != null)
                    _buildInfoRow('File Size', '${(song.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB', p),
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
                            side: BorderSide(color: p.hairline),
                          ),
                          onPressed: () => _shareSong(context),
                          icon: Icon(Icons.share_rounded, size: 20, color: p.textPrimary),
                          label: Text(
                            'Share',
                            style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary),
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
                              side: BorderSide(color: p.hairline),
                            ),
                            onPressed: () => _showRingtoneOptions(context),
                            icon: Icon(Icons.ring_volume_rounded, size: 20, color: p.textPrimary),
                            label: Text(
                              'Ringtone',
                              style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (defaultTargetPlatform == TargetPlatform.android)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push('/tag-editor', extra: song);
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
            ),
          ),
        ),
      ),
    );
}

  Widget _buildInfoRow(String label, String value, PulsrPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 100),
            child: Text(
              label,
              style: TextStyle(color: p.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
