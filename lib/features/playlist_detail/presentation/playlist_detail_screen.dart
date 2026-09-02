// lib/features/playlist_detail/presentation/playlist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
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
import '../../downloads/cubit/ytm_download_cubit.dart';
import '../../downloads/presentation/widgets/ytm_download_button.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistsTableData playlist;
  final PlaylistUseCases? playlistUseCases;

  const PlaylistDetailScreen(
      {super.key, required this.playlist, this.playlistUseCases});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  PlaylistUseCases get _useCases =>
      widget.playlistUseCases ?? getIt<PlaylistUseCases>();

  /// Created once so StreamBuilder keeps a single drift subscription across
  /// rebuilds — a fresh Stream per build tears down and re-subscribes the
  /// watch, re-issuing the DB query on every rebuild. [playlist] is a route
  /// argument and cannot change for this mount.
  late final Stream<List<SongsTableData>> _songsStream =
      widget.playlist.isSmart && widget.playlist.smartCriteria != null
          ? _useCases.watchSmartPlaylistSongs(
              SmartCriteria.fromJsonString(widget.playlist.smartCriteria!))
          : _useCases
              .watchPlaylistSongs(widget.playlist.id)
              .map((res) => res.fold((l) => <SongsTableData>[], (r) => r));

  void _downloadPlaylist(BuildContext context, List<SongsTableData> songs) {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot download an empty playlist.')),
      );
      return;
    }

    final downloadCubit =
        context.read<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();
    final queuedCount = downloadCubit.downloadAll(songs);

    if (queuedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Queued $queuedCount tracks for download (3 active downloads)...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final hasOnlineTracks =
          songs.any((s) => s.remoteId != null && s.remoteId!.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasOnlineTracks
                ? 'All online tracks are already downloaded or in progress.'
                : 'All tracks in this playlist are already offline local files.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportPlaylist(
      BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export an empty playlist.')),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    await exportUseCase.exportToFile(widget.playlist.name, songs);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Playlist exported successfully (${songs.length} tracks).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePlaylist(
      BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot share an empty playlist.')),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    final file = await exportUseCase.exportToFile(widget.playlist.name, songs);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'audio/x-mpegurl')],
          text: 'Playlist: ${widget.playlist.name}',
        ),
      );
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playlist = widget.playlist;
    final playlistUseCases = _useCases;

    return StreamBuilder<List<SongsTableData>>(
      stream: _songsStream,
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
                Expanded(
                    child:
                        Text(playlist.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            actions: [
              if (playlist.isSmart)
                IconButton(
                  icon: Icon(Icons.edit_rounded, color: p.accent),
                  onPressed: () =>
                      context.push('/smart-playlist-builder', extra: playlist),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  switch (value) {
                    case 'download':
                      _downloadPlaylist(context, songs);
                      break;
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
                  if (AppConfig.ytmEnabled)
                    PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded,
                              color: p.accent, size: 20),
                          const SizedBox(width: 12),
                          const Text('Download All Tracks'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.file_upload_outlined,
                            color: p.accent, size: 20),
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
                        Icon(Icons.delete_outline_rounded,
                            color: p.error, size: 20),
                        const SizedBox(width: 12),
                        Text('Delete Playlist',
                            style: TextStyle(color: p.error)),
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
              child: snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData
                  ? Center(child: CircularProgressIndicator(color: p.accent))
                  : songs.isEmpty
                      ? EmptyStateWidget(
                          icon: playlist.isSmart
                              ? Icons.auto_awesome_rounded
                              : Icons.queue_music_rounded,
                          title: 'No Tracks',
                          subtitle: playlist.isSmart
                              ? 'No tracks match the rules for this smart playlist.'
                              : 'No tracks in this playlist yet.',
                        )
                      : CustomScrollView(
                          // Builder-based slivers (F-04): header as a box
                          // adapter, track list virtualized.
                          slivers: [
                            SliverToBoxAdapter(
                              // Header Controls
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: Adaptive.pagePadding(context),
                                    vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          context.read<PlayerCubit>().playSong(
                                              songs.first,
                                              queue: songs);
                                        },
                                        icon: const Icon(
                                            Icons.play_arrow_rounded),
                                        label: const Text('Play All'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          final shuffled =
                                              List<SongsTableData>.from(songs)
                                                ..shuffle();
                                          context.read<PlayerCubit>().playSong(
                                              shuffled.first,
                                              queue: shuffled);
                                        },
                                        icon: Icon(Icons.shuffle_rounded,
                                            color: p.accent),
                                        label: const Text('Shuffle'),
                                      ),
                                    ),
                                    if (AppConfig.ytmEnabled) ...[
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                        onPressed: () =>
                                            _downloadPlaylist(context, songs),
                                        icon: const Icon(
                                            Icons.download_rounded,
                                            size: 20),
                                        style: IconButton.styleFrom(
                                          backgroundColor: p.accent
                                              .withValues(alpha: 0.15),
                                          foregroundColor: p.accent,
                                        ),
                                        tooltip:
                                            'Download all offline (3 active downloads)',
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),

                            // Tracks List
                            SliverPadding(
                              padding:
                                  const EdgeInsets.only(bottom: 160),
                              sliver: SliverList.builder(
                                itemCount: songs.length,
                                itemBuilder: (context, index) {
                                  final song = songs[index];
                                  return SongTile(
                                    song: song,
                                    index: index,
                                    subtitleOverride:
                                        '${song.artist} • ${song.album}',
                                    onTap: () => context
                                        .read<PlayerCubit>()
                                        .playSong(song, queue: songs),
                                    onMorePressed: () =>
                                        showModalBottomSheet<void>(
                                      context: context,
                                      useRootNavigator: true,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => SongInfoSheet(song: song),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (AppConfig.ytmEnabled &&
                                            song.remoteId != null &&
                                            song.remoteId!.isNotEmpty)
                                          YtmDownloadButton(song: song),
                                        if (!playlist.isSmart)
                                          IconButton(
                                            icon: Icon(
                                                Icons
                                                    .remove_circle_outline_rounded,
                                                size: 20,
                                                color: p.textTertiary),
                                            onPressed: () {
                                              playlistUseCases
                                                  .removeSongFromPlaylist(
                                                      playlist.id, song.id);
                                            },
                                          ),
                                      ],
                                    ),
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
