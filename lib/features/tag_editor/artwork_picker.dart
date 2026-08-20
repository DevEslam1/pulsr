// lib/features/tag_editor/artwork_picker.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/cached_artwork.dart';

class ArtworkPicker extends StatelessWidget {
  final int songId;
  final String? newArtworkPath;
  final Uint8List? artworkBytes;
  final bool removeArtwork;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const ArtworkPicker({
    super.key,
    required this.songId,
    this.newArtworkPath,
    this.artworkBytes,
    this.removeArtwork = false,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bool hasCustomNewImage = newArtworkPath != null && File(newArtworkPath!).existsSync();
    final bool hasBytesImage = artworkBytes != null && artworkBytes!.isNotEmpty && !removeArtwork;

    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: p.surfaceContainer,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: removeArtwork
                    ? Center(
                        child: Icon(Icons.music_note_rounded, size: 64, color: p.textSecondary),
                      )
                    : hasCustomNewImage
                        ? Image.file(
                            File(newArtworkPath!),
                            fit: BoxFit.cover,
                            width: 150,
                            height: 150,
                          )
                        : hasBytesImage
                            ? Image.memory(
                                artworkBytes!,
                                fit: BoxFit.cover,
                                width: 150,
                                height: 150,
                              )
                            : CachedArtwork(
                                id: songId,
                                type: ArtworkType.AUDIO,
                                size: 150,
                                borderRadius: 20,
                              ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black.withAlpha(70),
                  ),
                ),
              ),
              InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(50),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.accent.withAlpha(200),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Change Cover'),
                style: TextButton.styleFrom(
                  foregroundColor: p.accent,
                ),
              ),
              if (hasCustomNewImage || hasBytesImage || !removeArtwork) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
