// lib/features/playlist_detail/presentation/playlist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final PlaylistsTableData playlist;
  final PlaylistUseCases? playlistUseCases;

  const PlaylistDetailScreen({super.key, required this.playlist, this.playlistUseCases});

  PlaylistUseCases get _useCases => playlistUseCases ?? getIt<PlaylistUseCases>();

  Future<void> _exportPlaylist(BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export an empty playlist.')),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    await exportUseCase.exportToFile(playlist.name, songs);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist exported successfully (${songs.length} tracks).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePlaylist(BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot share an empty playlist.')),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    final file = await exportUseCase.exportToFile(playlist.name, songs);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'audio/x-mpegurl')],
      text: 'Playlist: ${playlist.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playlistUseCases = _useCases;

    final Stream<List<SongsTableData>> songsStream = playlist.isSmart && playlist.smartCriteria != null
        ? playlistUseCases.watchSmartPlaylistSongs(SmartCriteria.fromJsonString(playlist.smartCriteria!))
        : playlistUseCases.watchPlaylistSongs(playlist.id).map((res) => res.fold((l) => <SongsTableData>[], (r) => r));

    return StreamBuilder<List<SongsTableData>>(
      stream: songsStream,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? [];

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                if (playlist.isSmart) ...[
                  Icon(Icons.auto_awesome_rounded, color: p.accent, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(playlist.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            actions: [
              if (playlist.isSmart)
                IconButton(
                  icon: Icon(Icons.edit_rounded, color: p.accent),
                  onPressed: () => context.push('/smart-playlist-builder', extra: playlist),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  switch (value) {
                    case 'export':
                      await _exportPlaylist(context, songs);
                      break;
                    case 'share':
                      await _sharePlaylist(context, songs);
                      break;
                    case 'delete':
                      await playlistUseCases.deletePlaylist(playlist.id);
                      if (context.mounted) Navigator.pop(context);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.download_rounded, color: p.accent, size: 20),
                        const SizedBox(width: 12),
                        const Text('Export as M3U'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_rounded, color: p.accent, size: 20),
                        const SizedBox(width: 12),
                        const Text('Share Playlist'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: p.error, size: 20),
                        const SizedBox(width: 12),
                        Text('Delete Playlist', style: TextStyle(color: p.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                  ? Center(child: CircularProgressIndicator(color: p.accent))
                  : songs.isEmpty
                      ? EmptyStateWidget(
                          icon: playlist.isSmart ? Icons.auto_awesome_rounded : Icons.queue_music_rounded,
                          title: 'No Tracks',
                          subtitle: playlist.isSmart
                              ? 'No tracks match the rules for this smart playlist.'
                              : 'No tracks in this playlist yet.',
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 160),
                          children: [
                            // Header Controls
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        context.read<PlayerCubit>().playSong(songs.first, queue: songs);
                                      },
                                      icon: const Icon(Icons.play_arrow_rounded),
                                      label: const Text('Play All'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        final shuffled = List<SongsTableData>.from(songs)..shuffle();
                                        context.read<PlayerCubit>().playSong(shuffled.first, queue: shuffled);
                                      },
                                      icon: Icon(Icons.shuffle_rounded, color: p.accent),
                                      label: const Text('Shuffle'),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Tracks List
                            for (int i = 0; i < songs.length; i++)
                              SongTile(
                                song: songs[i],
                                index: i,
                                subtitleOverride: '${songs[i].artist} • ${songs[i].album}',
                                onTap: () => context.read<PlayerCubit>().playSong(songs[i], queue: songs),
                                onMorePressed: () => showModalBottomSheet(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => SongInfoSheet(song: songs[i]),
                                ),
                                trailing: playlist.isSmart
                                    ? null
                                    : IconButton(
                                        icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: p.textTertiary),
                                        onPressed: () {
                                          playlistUseCases.removeSongFromPlaylist(playlist.id, songs[i].id);
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
