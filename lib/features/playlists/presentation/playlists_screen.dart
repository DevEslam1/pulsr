// lib/features/playlists/presentation/playlists_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/widgets/artwork_placeholder.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../player/cubit/player_cubit.dart';
import '../../playlist_detail/presentation/playlist_detail_screen.dart';
import '../../smart_playlist_builder/smart_playlist_builder_screen.dart';
import '../cubit/playlist_cubit.dart';
import '../cubit/playlist_state.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  void _showCreateDialog(BuildContext context, PlaylistCubit cubit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Create Playlist'),
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
                await cubit.createPlaylist(name);
                if (context.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _importPlaylist(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8'],
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;
    final playlistName = fileName.replaceAll(RegExp(r'\.m3u8?$', caseSensitive: false), '');

    final importUseCase = getIt<PlaylistImportUseCase>();

    try {
      final importResult = await importUseCase.importPlaylistFromFile(
        filePath: filePath,
        playlistName: playlistName,
      );

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Playlist Imported'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Playlist: "${importResult.playlistName}"',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text('• ${importResult.matchedTrackCount} of ${importResult.totalExtractedPaths} tracks added to playlist.'),
                if (importResult.unmatchedPaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '• ${importResult.unmatchedPaths.length} tracks could not be matched with local library songs.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import playlist: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaylistCubit, PlaylistState>(
      builder: (context, state) {
        final cubit = context.read<PlaylistCubit>();
        final repository = context.read<MusicRepository>();
        final playerCubit = context.read<PlayerCubit>();

        final smartPlaylists = state.playlists.where((p) => p.isSmart).toList();
        final userPlaylists = state.playlists.where((p) => !p.isSmart).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Playlists',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.file_upload_rounded),
                tooltip: 'Import Playlist',
                onPressed: () => _importPlaylist(context),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Create Playlist',
                onPressed: () => _showCreateDialog(context, cubit),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            children: [
              // Create Buttons Card Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showCreateDialog(context, cubit),
                        borderRadius: AppRadii.cardRadius,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppRadii.cardRadius,
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, color: AppColors.primary, size: 22),
                              SizedBox(height: 4),
                              Text(
                                'New Playlist',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SmartPlaylistBuilderScreen(),
                            ),
                          );
                        },
                        borderRadius: AppRadii.cardRadius,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppRadii.cardRadius,
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 22),
                              SizedBox(height: 4),
                              Text(
                                'Smart Playlist',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.primary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _importPlaylist(context),
                        borderRadius: AppRadii.cardRadius,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppRadii.cardRadius,
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_upload_rounded, color: AppColors.primary, size: 22),
                              SizedBox(height: 4),
                              Text(
                                'Import M3U',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Smart Playlists Section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'SMART PLAYLISTS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),

              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.favorite.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: AppColors.favorite, size: 24),
                ),
                title: const Text('Liked Songs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Auto-populated from favorites', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                onTap: () async {
                  final songs = await repository.getAllSongs();
                  songs.fold((l) => null, (list) {
                    final favs = list.where((s) => s.isFavorite).toList();
                    if (favs.isNotEmpty) {
                      playerCubit.playSong(favs.first, queue: favs);
                    }
                  });
                },
              ),

              if (smartPlaylists.isNotEmpty)
                ...smartPlaylists.map((playlist) {
                  final count = state.smartPlaylistCounts[playlist.id] ?? 0;
                  return ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 24),
                    ),
                    title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text('$count tracks • Smart Rule Set', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(playlist: playlist),
                        ),
                      );
                    },
                  );
                }),

              const SizedBox(height: 16),

              // User Playlists
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'YOUR PLAYLISTS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),

              if (userPlaylists.isEmpty)
                EmptyStateWidget(
                  icon: Icons.playlist_add_rounded,
                  title: 'No Custom Playlists',
                  subtitle: 'Create a custom playlist or import an M3U file to organize your tracks.',
                  primaryActionLabel: 'Create Playlist',
                  primaryActionIcon: Icons.add_rounded,
                  onPrimaryAction: () => _showCreateDialog(context, cubit),
                  secondaryActionLabel: 'Import M3U',
                  secondaryActionIcon: Icons.file_upload_rounded,
                  onSecondaryAction: () => _importPlaylist(context),
                )
              else
                ...userPlaylists.map((playlist) {
                  return ListTile(
                    leading: const ArtworkPlaceholder(
                      size: 48,
                      borderRadius: 12,
                      icon: Icons.queue_music_rounded,
                    ),
                    title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Offline playlist', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(playlist: playlist),
                        ),
                      );
                    },
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
