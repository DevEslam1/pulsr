import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_io_usecases.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../cubit/playlist_cubit.dart';
import '../cubit/playlist_state.dart';

enum _PlaylistTabMode { local, online }

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  _PlaylistTabMode _selectedTab = _PlaylistTabMode.local;

  void _showCreateDialog(BuildContext context, PlaylistCubit cubit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.createPlaylist, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: context.l10n.enterPlaylistName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await cubit.createPlaylist(name);
                if (context.mounted) Navigator.pop(ctx);
              }
            },
            child: Text(context.l10n.save),
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
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final playlistName = result.files.single.name.replaceAll(
      RegExp(r'\.m3u8?$', caseSensitive: false),
      '',
    );
    final importUseCase = getIt<PlaylistImportUseCase>();

    final res = await importUseCase.importPlaylistFromFile(
      filePath: filePath,
      playlistName: playlistName,
    );
    if (!context.mounted) return;

    res.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import playlist: ${failure.message}')),
        );
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

  void _showAddOnlinePlaylistDialog(BuildContext context, PlaylistCubit cubit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add YouTube Playlist', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist URL or ID',
            helperText: 'e.g. https://www.youtube.com/playlist?list=PLxxx',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                cubit.fetchOnlinePlaylistByUrl(url);
              }
            },
            child: const Text('Fetch'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<PlaylistCubit>();
    final getSongsUseCase = getIt<GetSongsUseCase>();
    final playerCubit = context.read<PlayerCubit>();

    return BlocBuilder<PlaylistCubit, PlaylistState>(
      builder: (context, state) {
        final smartPlaylists = state.playlists.where((x) => x.isSmart).toList();
        final userPlaylists = state.playlists.where((x) => !x.isSmart).toList();
        final columns = Adaptive.gridColumns(context, minItemWidth: 170);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Playlists'),
            actions: [
              if (_selectedTab == _PlaylistTabMode.online) ...[
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Sync Online Library',
                  onPressed: () => cubit.autoFetchOnlineLibrary(force: true),
                ),
                IconButton(
                  icon: const Icon(Icons.add_link_rounded),
                  tooltip: 'Add Playlist URL',
                  onPressed: () => _showAddOnlinePlaylistDialog(context, cubit),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.file_upload_rounded),
                  tooltip: 'Import M3U',
                  onPressed: () => _importPlaylist(context),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Create Playlist',
                  onPressed: () => _showCreateDialog(context, cubit),
                ),
              ],
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: RefreshIndicator(
                onRefresh: () async {
                  if (_selectedTab == _PlaylistTabMode.online) {
                    await cubit.autoFetchOnlineLibrary(force: true);
                  } else {
                    final count = await context.read<SettingsCubit>().rescanLibrary();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Rescan complete ($count songs found)'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 160, top: 12),
                  children: [
                    // Liked songs hero card (Local favorites)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                    child: _PlaylistHeroCard(
                      title: 'Liked Songs',
                      subtitle: 'Auto-populated from favorites',
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

                  // SMART PLAYLISTS Header
                  Padding(
                    padding: EdgeInsets.only(left: Adaptive.pagePadding(context), top: 24, bottom: 10),
                    child: Text(
                      'SMART PLAYLISTS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary),
                    ),
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
                              Text(
                                'Create Smart Playlist',
                                style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 14),
                              ),
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
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.0,
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

                  // ── YOUR PLAYLISTS SECTION ──────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 28, Adaptive.pagePadding(context), 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'YOUR PLAYLISTS',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary),
                        ),
                      ],
                    ),
                  ),

                  // ── TABS UNDER YOUR PLAYLISTS (Local vs Online) ─────────
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_PlaylistTabMode>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: _PlaylistTabMode.local,
                            label: Text('Local', style: TextStyle(fontWeight: FontWeight.w700)),
                            icon: Icon(Icons.folder_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: _PlaylistTabMode.online,
                            label: Text('Online', style: TextStyle(fontWeight: FontWeight.w700)),
                            icon: Icon(Icons.cloud_rounded, size: 16),
                          ),
                        ],
                        selected: {_selectedTab},
                        onSelectionChanged: (sel) {
                          setState(() => _selectedTab = sel.first);
                          if (sel.first == _PlaylistTabMode.online) {
                            cubit.autoFetchOnlineLibrary();
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── TAB CONTENT ─────────────────────────────────────────
                  if (_selectedTab == _PlaylistTabMode.local) ...[
                    // LOCAL PLAYLISTS VIEW
                    if (userPlaylists.isEmpty)
                      EmptyStateWidget(
                        icon: Icons.playlist_add_rounded,
                        title: context.l10n.emptyPlaylists,
                        subtitle: context.l10n.emptyPlaylistsSubtitle,
                        primaryActionLabel: context.l10n.createPlaylist,
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
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 1.0,
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
                  ] else ...[
                    // ONLINE PLAYLISTS VIEW (Auto-fetches YouTube Music library)
                    _OnlinePlaylistsContent(
                      cubit: cubit,
                      playerCubit: playerCubit,
                      onAddPlaylist: () => _showAddOnlinePlaylistDialog(context, cubit),
                    ),
                  ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONLINE PLAYLISTS CONTENT (Under 'Your Playlists' Online Tab)
// ─────────────────────────────────────────────────────────────────────────────

class _OnlinePlaylistsContent extends StatelessWidget {
  final PlaylistCubit cubit;
  final PlayerCubit playerCubit;
  final VoidCallback onAddPlaylist;

  const _OnlinePlaylistsContent({
    required this.cubit,
    required this.playerCubit,
    required this.onAddPlaylist,
  });

  Future<void> _playAccountPlaylist(
    BuildContext context,
    YtmAccountPlaylist playlist,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Loading "${playlist.title}"…'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final ytmService = getIt<YtmService>();
      final tracks = await ytmService.getPlaylistTracks(playlist.playlistId, limit: 200);
      if (tracks.isNotEmpty) {
        final songs = tracks.map((t) => t.toSongData()).toList();
        playerCubit.playSong(songs.first, queue: songs);
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Could not load tracks for this playlist.')),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to load playlist: $e')),
      );
    }
  }

  Future<void> _downloadAccountPlaylist(
    BuildContext context,
    YtmAccountPlaylist playlist,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Fetching "${playlist.title}" for download…'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final ytmService = getIt<YtmService>();
      final tracks =
          await ytmService.getPlaylistTracks(playlist.playlistId, limit: 200);
      if (tracks.isNotEmpty) {
        final songs = tracks.map((t) => t.toSongData()).toList();
        final downloadCubit = getIt<YtmDownloadCubit>();
        final queuedCount = downloadCubit.downloadAll(songs);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              queuedCount > 0
                  ? 'Queued $queuedCount tracks from "${playlist.title}" for download (3 active downloads)...'
                  : 'All tracks from "${playlist.title}" are already downloaded offline.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Could not load tracks for this playlist.')),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to load playlist: $e')),
      );
    }
  }

  void _downloadCustomPlaylist(
    BuildContext context,
    OnlinePlaylistEntry entry,
  ) {
    if (entry.tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks in this playlist.')),
      );
      return;
    }
    final songs = entry.tracks.map((t) => t.toSongData()).toList();
    final downloadCubit =
        context.read<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();
    final queuedCount = downloadCubit.downloadAll(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queuedCount > 0
              ? 'Queued $queuedCount tracks from "${entry.title}" for download (3 active downloads)...'
              : 'All tracks from "${entry.title}" are already downloaded offline.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _downloadLikedSongs(
    BuildContext context,
    List<YtmTrack> likedTracks,
  ) {
    if (likedTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No liked songs to download. Sync first.')),
      );
      return;
    }
    final songs = likedTracks.map((t) => t.toSongData()).toList();
    final downloadCubit =
        context.read<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();
    final queuedCount = downloadCubit.downloadAll(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queuedCount > 0
              ? 'Queued $queuedCount liked songs for download (3 active downloads)...'
              : 'All liked songs are already downloaded offline.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ytmAccount = getIt<YtmAccountService>();

    return ValueListenableBuilder<bool>(
      valueListenable: ytmAccount.loginState,
      builder: (context, isLoggedIn, _) {
        if (!isLoggedIn) {
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: 24,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.cloud_sync_rounded, size: 40, color: p.accent),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connect YouTube Music',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to auto-fetch your Liked Music library and all your online account playlists.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await YtmWebLoginSheet.show(context);
                        if (ok == true) {
                          cubit.autoFetchOnlineLibrary(force: true);
                        }
                      },
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Sign in to YouTube Music'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ValueListenableBuilder<YtmOnlineState>(
          valueListenable: cubit.ytmOnline,
          builder: (context, online, _) {
            final columns = Adaptive.gridColumns(context, minItemWidth: 170);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Liked Music Online Hero Card
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                  child: _LikedMusicOnlineCard(
                    status: online.likedStatus,
                    trackCount: online.likedTracks.length,
                    error: online.likedError,
                    onFetch: () => cubit.fetchLikedSongsPlaylist(),
                    onDownload: () => _downloadLikedSongs(context, online.likedTracks),
                    onPlay: () {
                      if (online.likedTracks.isNotEmpty) {
                        final songs = online.likedTracks.map((t) => t.toSongData()).toList();
                        playerCubit.playSong(songs.first, queue: songs);
                      }
                    },
                  ),
                ),

                // ── ACCOUNT PLAYLISTS SECTION ─────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 24, Adaptive.pagePadding(context), 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ACCOUNT PLAYLISTS',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary),
                        ),
                      ),
                      if (online.accountStatus == YtmFetchStatus.loading)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                        )
                      else if (online.accountPlaylists.isNotEmpty)
                        Text(
                          '${online.accountPlaylists.length} playlists',
                          style: TextStyle(color: p.textTertiary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),

                if (online.accountStatus == YtmFetchStatus.loading && online.accountPlaylists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: p.accent)),
                          const SizedBox(height: 12),
                          Text('Fetching account playlists…', style: TextStyle(color: p.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                else if (online.accountStatus == YtmFetchStatus.error && online.accountPlaylists.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: p.error, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              online.accountError ?? 'Failed to load account playlists',
                              style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                            ),
                          ),
                          TextButton(
                            onPressed: () => cubit.fetchAccountPlaylists(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (online.accountPlaylists.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.playlist_remove_rounded, color: p.textTertiary, size: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No playlists found in your YouTube Music library.',
                              style: TextStyle(color: p.textSecondary, fontSize: 13),
                            ),
                          ),
                        ],
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
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: online.accountPlaylists.length,
                      itemBuilder: (context, i) {
                        final pl = online.accountPlaylists[i];
                        return _AccountPlaylistCard(
                          playlist: pl,
                          onTap: () => _playAccountPlaylist(context, pl),
                          onDownload: () => _downloadAccountPlaylist(context, pl),
                        );
                      },
                    ),
                  ),

                // ── ADDED PLAYLISTS SECTION ─────────────────────────────
                if (online.customPlaylists.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 24, Adaptive.pagePadding(context), 10),
                    child: Text(
                      'ADDED PLAYLISTS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: online.customPlaylists.length,
                      itemBuilder: (context, i) {
                        final pl = online.customPlaylists[i];
                        return _OnlinePlaylistCard(
                          entry: pl,
                          onTap: () {
                            if (pl.tracks.isNotEmpty) {
                              final songs = pl.tracks.map((t) => t.toSongData()).toList();
                              playerCubit.playSong(songs.first, queue: songs);
                            }
                          },
                          onDownload: () => _downloadCustomPlaylist(context, pl),
                          onRemove: () => cubit.removeCustomPlaylist(pl.id),
                        );
                      },
                    ),
                  ),
                ],

                // Add YouTube Playlist Button
                Padding(
                  padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16, Adaptive.pagePadding(context), 0),
                  child: InkWell(
                    onTap: onAddPlaylist,
                    borderRadius: BorderRadius.circular(18),
                    child: DashedBorderCard(
                      color: const Color(0xFFFF0000),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_rounded, color: Color(0xFFFF0000), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Add YouTube Playlist URL',
                            style: TextStyle(
                              color: Color(0xFFFF0000),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account Playlist Card (from YouTube Music library)
// ─────────────────────────────────────────────────────────────────────────────

class _AccountPlaylistCard extends StatelessWidget {
  final YtmAccountPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  const _AccountPlaylistCard({
    required this.playlist,
    required this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const gradientColors = [Color(0xFFE50914), Color(0xFF8B0000)];

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                    child: playlist.artworkUrl != null
                        ? Image.network(
                            playlist.artworkUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.queue_music_rounded, color: Colors.white, size: 36),
                              ),
                            ),
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.queue_music_rounded, color: Colors.white, size: 36),
                            ),
                          ),
                  ),
                  if (onDownload != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onDownload,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.download_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Liked Music Online Hero Card
// ─────────────────────────────────────────────────────────────────────────────

class _LikedMusicOnlineCard extends StatelessWidget {
  final YtmFetchStatus status;
  final int trackCount;
  final String? error;
  final VoidCallback onFetch;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;

  const _LikedMusicOnlineCard({
    required this.status,
    required this.trackCount,
    required this.error,
    required this.onFetch,
    required this.onPlay,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    const gradientColors = [Color(0xFF1ED760), Color(0xFF14833B)];

    String subtitle;
    switch (status) {
      case YtmFetchStatus.idle:
        subtitle = 'Tap to sync from YouTube Music';
        break;
      case YtmFetchStatus.loading:
        subtitle = 'Syncing liked songs…';
        break;
      case YtmFetchStatus.done:
        subtitle = '$trackCount songs synced • Tap to play or download';
        break;
      case YtmFetchStatus.error:
        subtitle = error ?? 'Failed to fetch';
        break;
    }

    return InkWell(
      onTap: status == YtmFetchStatus.loading ? null : (status == YtmFetchStatus.done ? onPlay : onFetch),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.thumb_up_alt_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Liked Music',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: status == YtmFetchStatus.error ? 0.7 : 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (status == YtmFetchStatus.loading)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            else if (status == YtmFetchStatus.done)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onDownload != null) ...[
                    GestureDetector(
                      onTap: onDownload,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(Icons.play_arrow_rounded, color: gradientColors.first, size: 26),
                  ),
                ],
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(
                  status == YtmFetchStatus.error ? Icons.refresh_rounded : Icons.download_rounded,
                  color: gradientColors.first,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Online Playlist Card (custom URL/ID)
// ─────────────────────────────────────────────────────────────────────────────

class _OnlinePlaylistCard extends StatelessWidget {
  final OnlinePlaylistEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onDownload;

  const _OnlinePlaylistCard({
    required this.entry,
    required this.onTap,
    required this.onRemove,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const ytRed = Color(0xFFFF0000);
    return InkWell(
      onTap: onTap,
      onLongPress: onRemove,
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
                  gradient: LinearGradient(
                    colors: [ytRed.withValues(alpha: 0.8), ytRed.withValues(alpha: 0.35)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                ),
                child: Stack(
                  children: [
                    const Center(child: Icon(Icons.queue_music_rounded, color: Colors.white, size: 40)),
                    if (onDownload != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: GestureDetector(
                          onTap: onDownload,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.download_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text('${entry.tracks.length} tracks • Added', style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reused local components
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  const _PlaylistHeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

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
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
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
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5)),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
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

  const _PlaylistCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.muted = false,
  });

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
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
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
