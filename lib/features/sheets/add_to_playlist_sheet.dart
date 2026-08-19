// lib/features/sheets/add_to_playlist_sheet.dart
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

import '../../core/errors/failures.dart';

class AddToPlaylistSheet extends StatelessWidget {
  final SongsTableData song;
  final MusicRepository repository;

  const AddToPlaylistSheet({
    super.key,
    required this.song,
    required this.repository,
  });

  void _showNewPlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            filled: true,
            fillColor: AppColors.card,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final result = await repository.createPlaylist(name);
                result.fold(
                  (failure) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(failure.message)),
                      );
                    }
                  },
                  (id) async {
                    await repository.addSongToPlaylist(id, song.id);
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to $name')),
                      );
                    }
                  },
                );
              }
            },
            child: const Text('Create & Add'),
          ),
        ],
      ),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Add to Playlist',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, color: AppColors.primary),
                onPressed: () => _showNewPlaylistDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<Result<List<PlaylistsTableData>>>(
            stream: repository.watchPlaylists(),
            builder: (context, snapshot) {
              final playlists = snapshot.data?.fold((l) => <PlaylistsTableData>[], (r) => r) ?? [];
              if (playlists.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Column(
                      children: [
                        const Text(
                          'No playlists created yet.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showNewPlaylistDialog(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create Playlist'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: const Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 20),
                    ),
                    title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    trailing: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                    onTap: () async {
                      await repository.addSongToPlaylist(playlist.id, song.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to ${playlist.name}')),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
