// lib/features/sheets/song_options_sheet.dart
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/di/injection.dart';
import '../../core/errors/error_message_resolver.dart';
import '../../core/services/ytm_service.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_toast.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../domain/usecases/playlist_usecases.dart';
import '../../domain/usecases/toggle_favorite_usecase.dart';
import '../library/cubit/library_cubit.dart';
import '../ytm_search/cubit/ytm_download_cubit.dart';
import 'add_to_playlist_sheet.dart';
import 'ringtone_retry_controller.dart';
import 'song_info_sheet.dart';

import '../../core/utils/pulsr_haptics.dart';

/// Modern track options bottom sheet.
///
/// Features:
/// - Hero track identity header (artwork, title, artist)
/// - Top quick-action row for the 5 most frequent actions:
///   [Favorite, Play Next, Queue, Playlist, Share]
/// - List of contextual actions below:
///   - Remove from playlist (when inside a playlist)
///   - Go to queue
///   - Go to album
///   - Go to artist
///   - Go to song radio
///   - Download offline (YTM)
///   - Edit audio tags (local)
///   - Set as ringtone (Android local)
///   - View song credits & audio specs (opens [SongInfoSheet])
class SongOptionsSheet extends StatefulWidget {
  final SongsTableData song;
  final PlaylistsTableData? playlist;
  final VoidCallback? onRemoveFromPlaylist;
  final bool isFavoriteScreen;
  final BuildContext? parentContext;

  const SongOptionsSheet({
    super.key,
    required this.song,
    this.playlist,
    this.onRemoveFromPlaylist,
    this.isFavoriteScreen = false,
    this.parentContext,
  });

  /// Opens the unified song options bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required SongsTableData song,
    PlaylistsTableData? playlist,
    VoidCallback? onRemoveFromPlaylist,
    bool isFavoriteScreen = false,
  }) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: true,
      builder: (_) => SongOptionsSheet(
        song: song,
        playlist: playlist,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        isFavoriteScreen: isFavoriteScreen,
        parentContext: context,
      ),
    );
  }

  @override
  State<SongOptionsSheet> createState() => _SongOptionsSheetState();
}

class _SongOptionsSheetState extends State<SongOptionsSheet> {
  SongsTableData get song => widget.song;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.song.isFavorite;
  }

  // --- ACTIONS ---

  Future<void> _shareSong(CapturedSheetContext env) async {
    final text =
        '${env.l10n.browseCheckOut} "${song.title}" ${env.l10n.browseBy} ${song.artist} ${env.l10n.browseOnPulsr}';
    try {
      if (song.path.isNotEmpty && !song.path.startsWith('ytmusic://')) {
        final exists = await File(song.path).exists();
        if (exists) {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(song.path)], text: text),
          );
          return;
        }
      }
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e, st) {
      ErrorLogger.log('Failed to share song',
          error: e, stackTrace: st, category: 'SongOptionsSheet');
      env.showSnackBar(
        SnackBar(content: Text(env.l10n.somethingWentWrong)),
      );
    }
  }

  void _playNext(CapturedSheetContext env) {
    final playerCubit = env.playerCubit;
    if (playerCubit == null) {
      env.showSnackBar(SnackBar(content: Text(env.l10n.somethingWentWrong)));
      return;
    }
    playerCubit.playNext(song);
    env.showSnackBar(
      SnackBar(
        content: Text(env.l10n.songPlayingNext(song.title)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addToQueue(CapturedSheetContext env) {
    final playerCubit = env.playerCubit;
    if (playerCubit == null) {
      env.showSnackBar(SnackBar(content: Text(env.l10n.somethingWentWrong)));
      return;
    }
    playerCubit.addToQueue(song);
    env.showSnackBar(
      SnackBar(
        content: Text(env.l10n.songAddedToQueue(song.title)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleFavorite(BuildContext context) async {
    try {
      context.read<LibraryCubit>().toggleFavorite(song.id);
    } catch (_) {
      try {
        final useCase = getIt<ToggleFavoriteUseCase>();
        await useCase(song.id);
      } catch (e, st) {
        ErrorLogger.log('Failed to toggle favorite',
            error: e, stackTrace: st, category: 'SongOptionsSheet');
      }
    }
  }

  Future<void> _removeFromPlaylist(CapturedSheetContext env) async {
    if (widget.onRemoveFromPlaylist != null) {
      widget.onRemoveFromPlaylist!();
      return;
    }
    final pl = widget.playlist;
    if (pl == null || pl.isSmart) return;

    final playlistUseCases = getIt<PlaylistUseCases>();
    // Capture the exact order first: Undo used to append the track, silently
    // moving it to the end of a hand-ordered playlist.
    List<int> originalOrder = const [];
    try {
      final orderRes = await playlistUseCases.watchPlaylistSongs(pl.id).first;
      originalOrder = orderRes.fold(
        (_) => const <int>[],
        (songs) => [for (final s in songs) s.id],
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to capture playlist order for undo',
          error: e, stackTrace: st, category: 'SongOptionsSheet');
    }
    final result =
        await playlistUseCases.removeSongFromPlaylist(pl.id, song.id);
    final hostContext = env.liveHostContext;
    if (result.isLeft()) {
      final msg = result.fold(
        (failure) => (hostContext != null && hostContext.mounted)
            ? resolveUiErrorMessage(hostContext, failure.message)
            : env.l10n.somethingWentWrong,
        (_) => env.l10n.somethingWentWrong,
      );
      if (hostContext != null && hostContext.mounted) {
        PulsrToast.show(hostContext, message: msg, isError: true);
      } else {
        env.showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    final removedMsg = env.l10n.songRemovedFromPlaylist(song.title, pl.name);
    Future<void> undoRemove() async {
      final added = await playlistUseCases.addSongsToPlaylist(pl.id, [song.id]);
      if (added.isRight() && originalOrder.isNotEmpty) {
        await playlistUseCases.reorderPlaylistSongs(pl.id, originalOrder);
      }
    }

    if (hostContext != null && hostContext.mounted) {
      PulsrToast.show(
        hostContext,
        message: removedMsg,
        actionLabel: env.l10n.undo,
        onActionPressed: undoRemove,
      );
    } else {
      env.showSnackBar(
        SnackBar(
          content: Text(removedMsg),
          action: SnackBarAction(
            label: env.l10n.undo,
            onPressed: undoRemove,
          ),
        ),
      );
    }
  }

  Future<void> _goToAlbum(CapturedSheetContext env) async {
    try {
      final repo = getIt<IMusicRepository>();
      AlbumsTableData? targetAlbum;
      if (song.albumId != null) {
        final res = await repo.getAlbumById(song.albumId!);
        targetAlbum = res.fold((_) => null, (a) => a);
      }
      if (targetAlbum == null && song.album.isNotEmpty) {
        final res = await repo.getAlbums();
        final all = res.fold((_) => <AlbumsTableData>[], (list) => list);
        targetAlbum = all
            .where((a) =>
                a.title.trim().toLowerCase() == song.album.trim().toLowerCase())
            .firstOrNull;
      }
      if (targetAlbum != null) {
        env.pushRoute('/album?id=${targetAlbum.id}', extra: targetAlbum);
      } else {
        env.showSnackBar(
          SnackBar(
            content: Text(env.l10n.albumNotFoundHint),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to go to album',
          error: e, stackTrace: st, category: 'SongOptionsSheet');
    }
  }

  Future<void> _goToArtist(CapturedSheetContext env) async {
    try {
      final repo = getIt<IMusicRepository>();
      ArtistsTableData? targetArtist;
      if (song.artistId != null) {
        final res = await repo.getArtistById(song.artistId!);
        targetArtist = res.fold((_) => null, (a) => a);
      }
      if (targetArtist == null && song.artist.isNotEmpty) {
        final res = await repo.getArtists();
        final all = res.fold((_) => <ArtistsTableData>[], (list) => list);
        targetArtist = all
            .where((a) =>
                a.name.trim().toLowerCase() == song.artist.trim().toLowerCase())
            .firstOrNull;
      }
      if (targetArtist != null) {
        env.pushRoute('/artist?id=${targetArtist.id}', extra: targetArtist);
      } else {
        env.showSnackBar(
          SnackBar(
            content: Text(env.l10n.artistNotFoundHint),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to go to artist',
          error: e, stackTrace: st, category: 'SongOptionsSheet');
    }
  }

  Future<void> _startSongRadio(CapturedSheetContext env) async {
    final playerCubit = env.playerCubit;
    if (playerCubit == null) {
      env.showSnackBar(SnackBar(content: Text(env.l10n.somethingWentWrong)));
      return;
    }
    final videoId = song.remoteId;
    if (videoId != null &&
        videoId.isNotEmpty &&
        getIt.isRegistered<YtmService>()) {
      await playerCubit.playSong(song);
      try {
        final radioTracks =
            await getIt<YtmService>().getRadioTracks(videoId, limit: 20);
        if (radioTracks.isNotEmpty) {
          final songs = radioTracks.map((t) => t.toSongData()).toList();
          await playerCubit.addAllToQueue(songs);
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to fetch radio tracks',
            error: e, stackTrace: st, category: 'SongOptionsSheet');
      }
    } else {
      final repo = getIt<IMusicRepository>();
      final res = await repo.getAllSongs();
      final all = res.fold((_) => <SongsTableData>[], (list) => list);
      final similar = all
          .where((s) =>
              s.id != song.id &&
              (s.artist == song.artist ||
                  (s.genre != null && s.genre == song.genre)))
          .toList()
        ..shuffle();
      final radioQueue = [song, ...similar.take(25)];
      await playerCubit.playSong(song, queue: radioQueue);
    }
  }

  void _showRingtoneSheet(CapturedSheetContext env) {
    final hostContext = env.liveHostContext;
    if (hostContext == null) return;
    RingtoneRetryController.showOptionsSheet(
      hostContext: hostContext,
      songPath: song.path,
      messenger: env.liveMessenger,
      l10n: env.l10n,
    );
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLocal =
        song.source == SongSource.local && !song.path.startsWith('ytmusic://');
    final canRemoveFromPlaylist =
        (widget.playlist != null && !widget.playlist!.isSmart) ||
            widget.onRemoveFromPlaylist != null;
    final hasValidAlbum =
        song.album.isNotEmpty && song.album != 'Unknown Album';
    final hasValidArtist =
        song.artist.isNotEmpty && song.artist != 'Unknown Artist';
    final isYtm = AppConfig.ytmEnabled &&
        song.remoteId != null &&
        song.remoteId!.isNotEmpty;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Track Identity
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                CachedArtwork(
                  id: song.id,
                  remoteUrl: song.remoteArtworkUrl,
                  type: ArtworkType.AUDIO,
                  size: 54,
                  borderRadius: 12,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                          letterSpacing: AppTracking.title,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.bodySmall,
                          fontWeight: FontWeight.w500,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Most-Used Items Quick Action Row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                _buildQuickActionButton(
                  context: context,
                  icon: _isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: context.l10n.favorite,
                  iconColor: _isFavorite ? p.favorite : null,
                  isActive: _isFavorite,
                  onTap: () {
                    setState(() => _isFavorite = !_isFavorite);
                    _toggleFavorite(context);
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.playlist_play_rounded,
                  label: context.l10n.playNext,
                  onTap: () {
                    final env = CapturedSheetContext.capture(
                      context,
                      parentContext: widget.parentContext,
                    );
                    env.popSheet();
                    _playNext(env);
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.queue_music_rounded,
                  label: context.l10n.queueTab,
                  onTap: () {
                    final env = CapturedSheetContext.capture(
                      context,
                      parentContext: widget.parentContext,
                    );
                    env.popSheet();
                    _addToQueue(env);
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.playlist_add_rounded,
                  label: context.l10n.addToPlaylist,
                  onTap: () {
                    final env = CapturedSheetContext.capture(
                      context,
                      parentContext: widget.parentContext,
                    );
                    env.popSheet();
                    final host = env.liveHostContext;
                    if (host != null) {
                      AddToPlaylistSheet.show(host, song: song);
                    }
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.share_rounded,
                  label: context.l10n.share,
                  onTap: () {
                    final env = CapturedSheetContext.capture(
                      context,
                      parentContext: widget.parentContext,
                    );
                    env.popSheet();
                    _shareSong(env);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: AppSpacing.xxs),

          // Contextual Action Items
          if (canRemoveFromPlaylist)
            _buildActionTile(
              context: context,
              icon: Icons.remove_circle_outline_rounded,
              title: context.l10n.removeFromPlaylist,
              iconColor: p.error,
              textColor: p.error,
              onTap: _removeFromPlaylist,
            ),
          _buildActionTile(
            context: context,
            icon: Icons.format_list_bulleted_rounded,
            title: context.l10n.goToQueue,
            onTap: (env) => env.pushRoute('/queue'),
          ),
          if (hasValidAlbum)
            _buildActionTile(
              context: context,
              icon: Icons.album_outlined,
              title: context.l10n.goToAlbum,
              onTap: _goToAlbum,
            ),
          if (hasValidArtist)
            _buildActionTile(
              context: context,
              icon: Icons.person_outline_rounded,
              title: context.l10n.goToArtist,
              onTap: _goToArtist,
            ),
          _buildActionTile(
            context: context,
            icon: Icons.radio_rounded,
            title: context.l10n.songRadio,
            onTap: _startSongRadio,
          ),
          if (isYtm)
            _buildActionTile(
              context: context,
              icon: song.isDownloaded == true
                  ? Icons.download_done_rounded
                  : Icons.download_rounded,
              iconColor: song.isDownloaded == true ? p.accent : null,
              title: song.isDownloaded == true
                  ? context.l10n.downloaded
                  : context.l10n.browseDownloadOffline,
              onTap: (env) {
                final downloadCubit = env.downloadCubit ??
                    (getIt.isRegistered<YtmDownloadCubit>()
                        ? getIt<YtmDownloadCubit>()
                        : null);
                if (downloadCubit == null) {
                  ErrorLogger.log(
                    'YtmDownloadCubit unavailable for offline download',
                    category: 'SongOptionsSheet',
                  );
                  env.showSnackBar(
                    SnackBar(content: Text(env.l10n.somethingWentWrong)),
                  );
                  return;
                }
                try {
                  downloadCubit.download(song);
                } catch (e, st) {
                  ErrorLogger.log(
                    'Failed to start offline download',
                    error: e,
                    stackTrace: st,
                    category: 'SongOptionsSheet',
                  );
                  env.showSnackBar(
                    SnackBar(content: Text(env.l10n.somethingWentWrong)),
                  );
                }
              },
            ),
          if (isLocal)
            _buildActionTile(
              context: context,
              icon: Icons.edit_note_rounded,
              title: context.l10n.tagEditor,
              onTap: (env) => env.pushRoute('/tag-editor', extra: song),
            ),
          if (Platform.isAndroid && isLocal)
            _buildActionTile(
              context: context,
              icon: Icons.ring_volume_rounded,
              title: context.l10n.setAsRingtone,
              onTap: _showRingtoneSheet,
            ),
          _buildActionTile(
            context: context,
            icon: Icons.info_outline_rounded,
            title: context.l10n.songDetails,
            onTap: (env) {
              final host = env.liveHostContext;
              if (host != null) {
                SongInfoSheet.show(host, song: song);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    bool isActive = false,
  }) {
    final p = context.palette;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              PulsrHaptics.lightImpact();
              onTap();
            },
            borderRadius: AppRadii.r16All,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.xs,
                horizontal: AppSpacing.xxs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isActive
                          ? p.favorite.withValues(alpha: 0.18)
                          : p.surface.withValues(alpha: p.isDark ? 0.45 : 0.65),
                      borderRadius: AppRadii.r16All,
                      border: Border.all(
                        color: isActive
                            ? p.favorite.withValues(alpha: 0.45)
                            : (p.isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : p.hairline),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 22,
                        color: iconColor ??
                            (isActive ? p.favorite : p.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600,
                      color: isActive ? p.favorite : p.textSecondary,
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

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required void Function(CapturedSheetContext env) onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: () {
          PulsrHaptics.lightImpact();
          final env = CapturedSheetContext.capture(
            context,
            parentContext: widget.parentContext,
          );
          env.popSheet();
          onTap(env);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s20,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: iconColor ?? p.textPrimary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.callout,
                    fontWeight: FontWeight.w500,
                    color: textColor ?? p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
