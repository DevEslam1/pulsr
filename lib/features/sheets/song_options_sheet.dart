// lib/features/sheets/song_options_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/constants/channels.dart';
import '../../core/di/injection.dart';
import '../../core/errors/error_message_resolver.dart';
import '../../core/router/app_router.dart';
import '../../core/services/ytm_service.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../core/widgets/pulsr_toast.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../domain/usecases/playlist_usecases.dart';
import '../../domain/usecases/toggle_favorite_usecase.dart';
import '../library/cubit/library_cubit.dart';
import '../player/cubit/player_cubit.dart';
import '../ytm_search/cubit/ytm_download_cubit.dart';
import 'add_to_playlist_sheet.dart';
import 'song_info_sheet.dart';

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

  const SongOptionsSheet({
    super.key,
    required this.song,
    this.playlist,
    this.onRemoveFromPlaylist,
    this.isFavoriteScreen = false,
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
      ),
    );
  }

  @override
  State<SongOptionsSheet> createState() => _SongOptionsSheetState();
}

class _SongOptionsSheetState extends State<SongOptionsSheet> {
  SongsTableData get song => widget.song;
  AppLifecycleListener? _settingsRetryListener;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.song.isFavorite;
  }

  @override
  void dispose() {
    _settingsRetryListener?.dispose();
    _settingsRetryListener = null;
    super.dispose();
  }

  // --- ACTIONS ---

  Future<void> _shareSong(BuildContext context) async {
    final text =
        '${context.l10n.browseCheckOut} "${song.title}" ${context.l10n.browseBy} ${song.artist} ${context.l10n.browseOnPulsr}';
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.somethingWentWrong)),
        );
      }
    }
  }

  void _playNext(BuildContext context) {
    context.read<PlayerCubit>().playNext(song);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.songPlayingNext(song.title)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addToQueue(BuildContext context) {
    context.read<PlayerCubit>().addToQueue(song);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.songAddedToQueue(song.title)),
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

  Future<void> _removeFromPlaylist(BuildContext context) async {
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
    if (result.isLeft()) {
      if (context.mounted) {
        PulsrToast.show(
          context,
          message: result.fold(
            (failure) => resolveUiErrorMessage(context, failure.message),
            (_) => context.l10n.somethingWentWrong,
          ),
          isError: true,
        );
      }
      return;
    }
    if (context.mounted) {
      PulsrToast.show(
        context,
        message: context.l10n.songRemovedFromPlaylist(song.title, pl.name),
        actionLabel: context.l10n.undo,
        onActionPressed: () async {
          final added =
              await playlistUseCases.addSongsToPlaylist(pl.id, [song.id]);
          if (added.isRight() && originalOrder.isNotEmpty) {
            await playlistUseCases.reorderPlaylistSongs(pl.id, originalOrder);
          }
        },
      );
    }
  }

  Future<void> _goToAlbum(BuildContext context) async {
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
      if (context.mounted) {
        if (targetAlbum != null) {
          context.push('/album', extra: targetAlbum);
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.albumNotFoundHint),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to go to album',
          error: e, stackTrace: st, category: 'SongOptionsSheet');
    }
  }

  Future<void> _goToArtist(BuildContext context) async {
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
      if (context.mounted) {
        if (targetArtist != null) {
          context.push('/artist', extra: targetArtist);
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.artistNotFoundHint),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to go to artist',
          error: e, stackTrace: st, category: 'SongOptionsSheet');
    }
  }

  Future<void> _startSongRadio(BuildContext context) async {
    final playerCubit = context.read<PlayerCubit>();
    final videoId = song.remoteId;
    if (videoId != null &&
        videoId.isNotEmpty &&
        getIt.isRegistered<YtmService>()) {
      await playerCubit.playSong(song);
      try {
        final radioTracks =
            await getIt<YtmService>().getRadioTracks(videoId, limit: 20);
        if (radioTracks.isNotEmpty && context.mounted) {
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

  Future<void> _setRingtone(BuildContext context, String type) async {
    const channel = MethodChannel(PulsrChannels.ringtone);
    final label = type == 'notification'
        ? context.l10n.browseNotificationSound
        : type == 'alarm'
            ? context.l10n.browseAlarmSound
            : context.l10n.ringtone;

    try {
      if (Platform.isAndroid) {
        final canWrite =
            await channel.invokeMethod<bool>('checkWriteSettingsPermission') ??
                true;
        if (!canWrite) {
          if (!context.mounted) return;
          final proceed = await PulsrDialogHelper.showConfirmDialog(
            context,
            title: context.l10n.permissionRequired,
            message:
                '${context.l10n.browseToSet} $label ${context.l10n.browseRequiresModifySettings}',
            icon: Icons.security_rounded,
            confirmLabel: context.l10n.openSettings,
            cancelLabel: context.l10n.cancel,
          );
          if (!context.mounted) return;
          if (proceed == true) {
            _openSettingsAndListenForRetry(channel, type);
          }
          return;
        }
      }

      final success = await channel.invokeMethod<bool>('setRingtone', {
        'filePath': song.path,
        'type': type,
      });
      if (!context.mounted) return;
      if (success ?? false) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ringtoneSet)),
        );
      } else {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ringtoneFailed)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.l10n.ringtoneFailed} $e')),
      );
    }
  }

  void _openSettingsAndListenForRetry(MethodChannel channel, String type) {
    _settingsRetryListener?.dispose();
    _settingsRetryListener = AppLifecycleListener(
      onResume: () async {
        final listener = _settingsRetryListener;
        _settingsRetryListener = null;
        listener?.dispose();
        try {
          final canWrite = await channel
                  .invokeMethod<bool>('checkWriteSettingsPermission') ??
              false;
          if (canWrite) {
            final activeContext = rootNavigatorKey.currentContext;
            if (activeContext != null && activeContext.mounted) {
              await _setRingtone(activeContext, type);
            }
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Auto-retry setRingtone failed after returning from settings',
            error: e,
            stackTrace: st,
            category: 'SongOptionsSheet',
          );
        }
      },
    );
    channel.invokeMethod('openWriteSettings');
  }

  void _showRingtoneSheet(BuildContext context) {
    final p = context.palette;
    PulsrSheetHelper.showPulsrSheet(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                context.l10n.setAudioAs,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.ring_volume_rounded, color: p.accent),
              title: Text(context.l10n.phoneRingtone,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setRingtone(context, 'ringtone');
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.notifications_active_rounded, color: p.accent),
              title: Text(context.l10n.notificationSound,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setRingtone(context, 'notification');
              },
            ),
            ListTile(
              leading: Icon(Icons.alarm_rounded, color: p.accent),
              title: Text(context.l10n.alarmSound,
                  style: TextStyle(color: p.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setRingtone(context, 'alarm');
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
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
                    Navigator.of(context).pop();
                    _playNext(context);
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.queue_music_rounded,
                  label: context.l10n.queueTab,
                  onTap: () {
                    Navigator.of(context).pop();
                    _addToQueue(context);
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.playlist_add_rounded,
                  label: context.l10n.addToPlaylist,
                  onTap: () {
                    Navigator.of(context).pop();
                    AddToPlaylistSheet.show(context, song: song);
                  },
                ),
                _buildQuickActionButton(
                  context: context,
                  icon: Icons.share_rounded,
                  label: context.l10n.share,
                  onTap: () {
                    Navigator.of(context).pop();
                    _shareSong(context);
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
              onTap: () => _removeFromPlaylist(context),
            ),
          _buildActionTile(
            context: context,
            icon: Icons.format_list_bulleted_rounded,
            title: context.l10n.goToQueue,
            onTap: () => context.push('/queue'),
          ),
          if (hasValidAlbum)
            _buildActionTile(
              context: context,
              icon: Icons.album_outlined,
              title: context.l10n.goToAlbum,
              onTap: () => _goToAlbum(context),
            ),
          if (hasValidArtist)
            _buildActionTile(
              context: context,
              icon: Icons.person_outline_rounded,
              title: context.l10n.goToArtist,
              onTap: () => _goToArtist(context),
            ),
          _buildActionTile(
            context: context,
            icon: Icons.radio_rounded,
            title: context.l10n.songRadio,
            onTap: () => _startSongRadio(context),
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
              onTap: () {
                try {
                  context.read<YtmDownloadCubit>().download(song);
                } catch (_) {}
              },
            ),
          if (isLocal)
            _buildActionTile(
              context: context,
              icon: Icons.edit_note_rounded,
              title: context.l10n.tagEditor,
              onTap: () => context.push('/tag-editor', extra: song),
            ),
          if (Platform.isAndroid && isLocal)
            _buildActionTile(
              context: context,
              icon: Icons.ring_volume_rounded,
              title: context.l10n.setAsRingtone,
              onTap: () => _showRingtoneSheet(context),
            ),
          _buildActionTile(
            context: context,
            icon: Icons.info_outline_rounded,
            title: context.l10n.songDetails,
            onTap: () => SongInfoSheet.show(context, song: song),
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
              HapticFeedback.lightImpact();
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
                      fontSize: AppFontSize.tiny,
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
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    final p = context.palette;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
        onTap();
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
    );
  }
}
