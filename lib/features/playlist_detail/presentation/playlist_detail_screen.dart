// lib/features/playlist_detail/presentation/playlist_detail_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/playlist_share_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final PlaylistsTableData playlist;
  final PlaylistUseCases? playlistUseCases;
  final bool isEmbedded;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.playlistUseCases,
    this.isEmbedded = false,
  });

  PlaylistUseCases get _useCases =>
      playlistUseCases ?? getIt<PlaylistUseCases>();

  void _downloadPlaylist(BuildContext context, List<SongsTableData> songs) {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.cannotDownloadEmpty)),
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
              context.l10n.queuedForDownload(queuedCount)),
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
                ? context.l10n.browseAllOnlineTracksDownloaded
                : context.l10n.browseAllTracksOfflineLocal,
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
        SnackBar(content: Text(context.l10n.cannotExportEmpty)),
      );
      return;
    }
    final exportUseCase = getIt<PlaylistExportUseCase>();
    await exportUseCase.exportToFile(playlist.name, songs);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10n.playlistExported(songs.length)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePlaylist(
      BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.cannotShareEmpty)),
      );
      return;
    }
    final sharePrefix = context.l10n.browsePlaylistSharePrefix;

    // Primary path: PlaylistShareService's portable JSON bundle.
    if (await _sharePlaylistBundle(context, playlist.name, songs)) return;

    // Graceful fallback: existing M3U share.
    final exportUseCase = getIt<PlaylistExportUseCase>();
    final file = await exportUseCase.exportToFile(playlist.name, songs);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'audio/x-mpegurl')],
          text: '$sharePrefix ${playlist.name}',
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

  /// Shares the playlist as a [PlaylistShareService] JSON bundle. Returns
  /// false when the service cannot produce/validate it, so the caller can fall
  /// back to the M3U share.
  Future<bool> _sharePlaylistBundle(
      BuildContext context, String name, List<SongsTableData> songs) async {
    final sharePrefix = context.l10n.browsePlaylistSharePrefix;
    try {
      final shareService = getIt<PlaylistShareService>();
      final json = shareService.exportPlaylist(name, songs);
      if (json.isEmpty || shareService.importPlaylist(json) == null) {
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final bundle = File('${tempDir.path}/$safeName.pulsr.json');
      await bundle.writeAsString(json);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(bundle.path, mimeType: 'application/json')],
            text: '$sharePrefix $name',
          ),
        );
        return true;
      } finally {
        try {
          if (await bundle.exists()) await bundle.delete();
        } catch (_) {}
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playlistUseCases = _useCases;

    final Stream<List<SongsTableData>> songsStream =
        playlist.isSmart && playlist.smartCriteria != null
            ? playlistUseCases.watchSmartPlaylistSongs(
                SmartCriteria.fromJsonString(playlist.smartCriteria!))
            : playlistUseCases
                .watchPlaylistSongs(playlist.id)
                .map((res) => res.fold((l) => <SongsTableData>[], (r) => r));

    return StreamBuilder<List<SongsTableData>>(
      stream: songsStream,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? [];

        final scaffold = Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: isEmbedded ? null : const PulsrBackButton(),
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
                )
              else
                IconButton(
                  tooltip: context.l10n.manageSongs,
                  icon: Icon(Icons.playlist_add_check_rounded, color: p.accent),
                  onPressed: () =>
                      context.push('/playlist/manage', extra: playlist),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  switch (value) {
                    case 'manage':
                      context.push('/playlist/manage', extra: playlist);
                      break;
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
                  if (!playlist.isSmart)
                    PopupMenuItem(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add_check_rounded,
                              color: p.accent, size: 20),
                          const SizedBox(width: 12),
                          Text(context.l10n.manageSongs),
                        ],
                      ),
                    ),
                  if (AppConfig.ytmEnabled)
                    PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded,
                              color: p.accent, size: 20),
                          const SizedBox(width: 12),
                          Text(context.l10n.downloadAllTracks),
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
                        Text(context.l10n.exportM3u),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_rounded, color: p.accent, size: 20),
                        const SizedBox(width: 12),
                        Text(context.l10n.sharePlaylist),
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
                        Text(context.l10n.deletePlaylist,
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
                          title: context.l10n.browseNoTracks,
                          subtitle: playlist.isSmart
                              ? context.l10n.browseNoTracksMatchSmartRules
                              : context.l10n.emptyPlaylist,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 160),
                          itemCount: songs.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
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
                                        icon:
                                            const Icon(Icons.play_arrow_rounded),
                                        label: Text(context.l10n.playAll),
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
                                        label: Text(context.l10n.shuffle),
                                      ),
                                    ),
                                    if (AppConfig.ytmEnabled) ...[
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                        onPressed: () =>
                                            _downloadPlaylist(context, songs),
                                        icon: const Icon(Icons.download_rounded,
                                            size: 20),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              p.accent.withValues(alpha: 0.15),
                                          foregroundColor: p.accent,
                                        ),
                                        tooltip:
                                            context.l10n.browseDownloadAllOfflineActive,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }

                            final i = index - 1;
                            final song = songs[i];
                            return SongTile(
                              song: song,
                              index: i,
                              subtitleOverride:
                                  '${song.artist} • ${song.album}',
                              onTap: () => context
                                  .read<PlayerCubit>()
                                  .playSong(song, queue: songs),
                              onMorePressed: () => SongInfoSheet.show(context, song: song),
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
                                          Icons.remove_circle_outline_rounded,
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
          ),
        );
        return isEmbedded ? scaffold : PulsrPagePopScope(child: scaffold);
      },
    );
  }
}
