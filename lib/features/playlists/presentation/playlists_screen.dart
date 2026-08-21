import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../player/cubit/player_cubit.dart';
import '../cubit/playlist_cubit.dart';
import '../cubit/playlist_state.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  void _showCreateDialog(BuildContext context, PlaylistCubit cubit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Playlist', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['m3u', 'm3u8']);
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final playlistName = result.files.single.name.replaceAll(RegExp(r'\.m3u8?$', caseSensitive: false), '');
    final importUseCase = getIt<PlaylistImportUseCase>();

    final res = await importUseCase.importPlaylistFromFile(filePath: filePath, playlistName: playlistName);
    if (!context.mounted) return;

    res.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to import playlist: ${failure.message}')));
      },
      (importResult) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Playlist Imported', style: TextStyle(fontWeight: FontWeight.w800)),
            content: Text('${importResult.matchedTrackCount} of ${importResult.totalExtractedPaths} tracks matched.'),
            actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlaylistCubit, PlaylistState>(
      builder: (context, state) {
        final cubit = context.read<PlaylistCubit>();
        final getSongsUseCase = getIt<GetSongsUseCase>();
        final playerCubit = context.read<PlayerCubit>();
        final smartPlaylists = state.playlists.where((x) => x.isSmart).toList();
        final userPlaylists = state.playlists.where((x) => !x.isSmart).toList();
        final columns = Adaptive.gridColumns(context, minItemWidth: 170);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Playlists'),
            actions: [
              IconButton(icon: const Icon(Icons.file_upload_rounded), tooltip: 'Import M3U', onPressed: () => _importPlaylist(context)),
              IconButton(icon: const Icon(Icons.add_rounded), tooltip: 'Create Playlist', onPressed: () => _showCreateDialog(context, cubit)),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 160),
                children: [
                  // Liked songs hero card
                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 12, Adaptive.pagePadding(context), 4),
                    child: _PlaylistHeroCard(
                      title: 'Dr. Basbosa\'s Liked Songs 💕',
                      subtitle: 'Your favorites • Made for my #1 favorite person',
                      icon: Icons.favorite_rounded,
                      colors: [p.favorite, const Color(0xFFB0316B)],
                      onTap: () async {
                        final songs = await getSongsUseCase.getAllSongs();
                        songs.fold((l) => null, (list) {
                          final favs = list.where((s) => s.isFavorite).toList();
                          if (favs.isNotEmpty) playerCubit.playSong(favs.first, queue: favs);
                        });
                      },
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.only(left: Adaptive.pagePadding(context), top: 20, bottom: 10),
                    child: Text('SMART PLAYLISTS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary)),
                  ),
                  if (smartPlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                      child: InkWell(
                        onTap: () => context.push('/smart-playlist-builder'),
                        borderRadius: BorderRadius.circular(18),
                        child: DashedBorderCard(
                          color: p.accent,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_awesome_rounded, color: p.accent, size: 20),
                              const SizedBox(width: 10),
                              Text('Create Smart Playlist', style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.0,
                        ),
                        itemCount: smartPlaylists.length,
                        itemBuilder: (context, index) {
                          final pl = smartPlaylists[index];
                          final count = state.smartPlaylistCounts[pl.id] ?? 0;
                          return _PlaylistCard(
                            name: pl.name,
                            subtitle: '$count tracks • Smart',
                            icon: Icons.auto_awesome_rounded,
                            gradient: [p.accent.withValues(alpha: 0.65), p.accent.withValues(alpha: 0.25)],
                            onTap: () => context.push('/playlist', extra: pl),
                          );
                        },
                      ),
                    ),

                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 26, Adaptive.pagePadding(context), 10),
                    child: Text('YOUR PLAYLISTS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary)),
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
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.0,
                        ),
                        itemCount: userPlaylists.length,
                        itemBuilder: (context, index) {
                          final pl = userPlaylists[index];
                          return _PlaylistCard(
                            name: pl.name,
                            subtitle: 'Offline playlist',
                            icon: Icons.queue_music_rounded,
                            gradient: [p.surfaceContainerHigh, p.surfaceContainer],
                            muted: true,
                            onTap: () => context.push('/playlist', extra: pl),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  const _PlaylistHeroCard({required this.title, required this.subtitle, required this.icon, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: colors.first.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: -6, offset: const Offset(0, 12)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5)),
                ],
              ),
            ),
            Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, color: colors.first, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final bool muted;
  final VoidCallback onTap;

  const _PlaylistCard({required this.name, required this.subtitle, required this.icon, required this.gradient, required this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                ),
                child: Center(
                  child: Icon(icon, color: muted ? p.textSecondary : Colors.white, size: 40),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashedBorderCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const DashedBorderCard({super.key, required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.4),
        color: color.withValues(alpha: 0.05),
      ),
      child: child,
    );
  }
}
