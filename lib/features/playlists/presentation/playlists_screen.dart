// lib/features/playlists/presentation/playlists_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/widgets/artwork_placeholder.dart';
import '../../../data/repositories/music_repository.dart';
import '../../player/cubit/player_cubit.dart';
import '../../playlist_detail/presentation/playlist_detail_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaylistCubit, PlaylistState>(
      builder: (context, state) {
        final cubit = context.read<PlaylistCubit>();
        final repository = context.read<MusicRepository>();
        final playerCubit = context.read<PlayerCubit>();

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Playlists',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _showCreateDialog(context, cubit),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            children: [
              // Create New Playlist Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: InkWell(
                  onTap: () => _showCreateDialog(context, cubit),
                  borderRadius: AppRadii.cardRadius,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppRadii.cardRadius,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Playlist',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Build custom offline mixes',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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

              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 24),
                ),
                title: const Text('Top 30 Most Played', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Your heavy rotation tracks', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                onTap: () async {
                  final songs = await repository.getAllSongs();
                  songs.fold((l) => null, (list) {
                    final top = list.where((s) => s.playCount > 0).toList()
                      ..sort((a, b) => b.playCount.compareTo(a.playCount));
                    if (top.isNotEmpty) {
                      playerCubit.playSong(top.first, queue: top.take(30).toList());
                    }
                  });
                },
              ),

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

              if (state.playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text('No custom playlists yet', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                ...state.playlists.map((playlist) {
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
