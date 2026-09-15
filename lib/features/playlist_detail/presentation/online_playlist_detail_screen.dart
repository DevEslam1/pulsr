// lib/features/playlist_detail/presentation/online_playlist_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';

class OnlinePlaylistDetailArgs {
  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? artworkUrl;
  final List<YtmTrack>? initialTracks;

  const OnlinePlaylistDetailArgs({
    required this.playlistId,
    this.title,
    this.subtitle,
    this.artworkUrl,
    this.initialTracks,
  });
}

class OnlinePlaylistDetailScreen extends StatefulWidget {
  final OnlinePlaylistDetailArgs args;
  final bool isEmbedded;

  const OnlinePlaylistDetailScreen({
    super.key,
    required this.args,
    this.isEmbedded = false,
  });

  @override
  State<OnlinePlaylistDetailScreen> createState() =>
      _OnlinePlaylistDetailScreenState();
}

class _OnlinePlaylistDetailScreenState
    extends State<OnlinePlaylistDetailScreen> {
  late String _title;
  late String _subtitle;
  String? _artworkUrl;
  List<YtmTrack> _tracks = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _title = widget.args.title ?? 'YouTube Music Playlist';
    _subtitle = widget.args.subtitle ?? 'Online Playlist';
    _artworkUrl = widget.args.artworkUrl;

    if (widget.args.initialTracks != null &&
        widget.args.initialTracks!.isNotEmpty) {
      _tracks = List<YtmTrack>.from(widget.args.initialTracks!);
      _artworkUrl ??= _tracks.firstOrNull?.artworkUrl;
    } else {
      _fetchTracks();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTracks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accountService = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      // Bound the whole fetch: paginated library playlists can otherwise
      // keep the spinner forever on slow/auth-challenged networks.
      // On timeout we fall through to the error state with retry.
      YtmPlaylistDetails? details;
      try {
        details = await accountService
            ?.fetchPlaylistDetails(
              widget.args.playlistId,
              maxTracks: 300,
            )
            .timeout(const Duration(seconds: 45));
      } on TimeoutException {
        debugPrint(
            '[ONLINE_PLAYLIST] fetchPlaylistDetails timed out for ${widget.args.playlistId}');
      }

      List<YtmTrack> fetchedTracks = details?.tracks ?? const [];

      if (fetchedTracks.isEmpty) {
        final ytmService = getIt<YtmService>();
        try {
          fetchedTracks = await ytmService
              .getPlaylistTracks(
                widget.args.playlistId,
                limit: 300,
              )
              .timeout(const Duration(seconds: 45));
        } on TimeoutException {
          debugPrint(
              '[ONLINE_PLAYLIST] getPlaylistTracks timed out for ${widget.args.playlistId}');
          fetchedTracks = const [];
        }
      }

      if (!mounted) return;

      if (fetchedTracks.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = context.l10n.browseCouldNotLoadTracks;
        });
        return;
      }

      setState(() {
        _tracks = fetchedTracks;
        _isLoading = false;
        if (details != null) {
          if (details.title.isNotEmpty &&
              details.title != 'YouTube Playlist' &&
              details.title != 'Playlist') {
            _title = details.title;
          }
          if (details.author.isNotEmpty) {
            _subtitle = details.author;
          }
          _artworkUrl = details.artworkUrl ?? fetchedTracks.firstOrNull?.artworkUrl;
        } else {
          _artworkUrl ??= fetchedTracks.firstOrNull?.artworkUrl;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '${context.l10n.playlistLoadFailed} $e';
      });
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_tracks.isEmpty) return;
    final songs = _tracks.map((t) => t.toSongData()).toList();
    if (shuffle) {
      songs.shuffle();
    }
    context.read<PlayerCubit>().playSong(songs.first, queue: songs);
  }

  void _downloadAll() {
    if (_tracks.isEmpty) return;
    final songs = _tracks.map((t) => t.toSongData()).toList();
    final downloadCubit = getIt<YtmDownloadCubit>();
    final count = downloadCubit.downloadAll(songs);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
          count > 0
              ? context.l10n.queuedFromTitle(count, _title)
              : context.l10n.allDownloaded(_title),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveToLocalPlaylists() async {
    if (_tracks.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    // Captured before async gaps (no context-across-gap).
    final saveFailedText = context.l10n.saveFailed;
    final loc = context.l10n;
    try {
      final playlistUseCases = getIt<PlaylistUseCases>();
      final songs = _tracks.map((t) => t.toSongData()).toList();

      // First ensure tracks are known in local favorites repository
      final libraryCubit = context.read<LibraryCubit>();
      await libraryCubit.importYtmTracksAsFavorites(_tracks);

      final playlistRes = await playlistUseCases.createPlaylist(_title);
      final createdId = playlistRes.fold((l) => null, (r) => r);

      if (createdId != null) {
        for (final s in songs) {
          await playlistUseCases.addSongToPlaylist(createdId, s.id);
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(loc.savedToLocal(_title, songs.length)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(saveFailedText),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final filtered = _searchQuery.isEmpty
        ? _tracks
        : _tracks.where((t) {
            final q = _searchQuery.toLowerCase();
            return t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q);
          }).toList();

    final totalDurationMs =
        _tracks.fold<int>(0, (sum, t) => sum + t.duration.inMilliseconds);

    final content = RefreshIndicator(
      onRefresh: _fetchTracks,
      color: p.accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 160),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // ── HERO BANNER ─────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Adaptive.pagePadding(context),
              vertical: 12,
            ),
            child: _buildHeroCard(context, p, totalDurationMs),
          ),

          // ── QUICK ACTIONS ROW ───────────────────────────────────────
          if (_tracks.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _playAll(shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(context.l10n.playAll,
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _playAll(shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: Text(context.l10n.shuffle,
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.surfaceContainerHigh,
                        foregroundColor: p.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── SECONDARY ACTIONS (Download / Save Local) ────────────────
          if (_tracks.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _downloadAll,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(context.l10n.downloadAll,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: p.hairline),
                        foregroundColor: p.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveToLocalPlaylists,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: Text(context.l10n.saveToPulsr,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: p.hairline),
                        foregroundColor: p.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── SEARCH BAR ──────────────────────────────────────────────
          if (_tracks.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                Adaptive.pagePadding(context),
                12,
                Adaptive.pagePadding(context),
                10,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: context.l10n.browseSearchWithinPlaylist,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: p.surfaceContainer,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                ),
              ),
            ),

          // ── CONTENT / TRACKS LIST ───────────────────────────────────
          if (_isLoading && _tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: p.accent),
                    ),
                    const SizedBox(height: 16),
                    Text(context.l10n.fetchingYtmTracks,
                        style: TextStyle(color: p.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_errorMessage != null && _tracks.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: 40,
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 48, color: p.textTertiary),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _fetchTracks,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? '${context.l10n.browseNoSongsMatch} "$_searchQuery"'
                      : context.l10n.browsePlaylistHasNoSongs,
                  style: TextStyle(color: p.textTertiary, fontSize: 14),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final track = filtered[index];
                final song = track.toSongData();
                return SongTile(
                  key: ValueKey('online_${track.videoId}_$index'),
                  song: song,
                  index: index,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      YtmDownloadButton(song: song, iconSize: 18),
                      IconButton(
                        icon: Icon(Icons.more_vert_rounded,
                            size: 18, color: p.textTertiary),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => SongInfoSheet(song: song),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    final songs = filtered.map((t) => t.toSongData()).toList();
                    context.read<PlayerCubit>().playSong(song, queue: songs);
                  },
                );
              },
            ),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return content;
    }

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          leading: const PulsrBackButton(),
          backgroundColor: p.surface,
          elevation: 0,
          title: Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: context.l10n.browseRefreshPlaylist,
              onPressed: _fetchTracks,
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(
      BuildContext context, PulsrPalette p, int totalDurationMs) {
    const ytGradient = [Color(0xFFE50914), Color(0xFF7A0000)];

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top cover artwork or gradient
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_artworkUrl != null && _artworkUrl!.isNotEmpty)
                  Image.network(
                    _artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildFallbackHeroGradient(ytGradient),
                  )
                else
                  _buildFallbackHeroGradient(ytGradient),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                            Text(context.l10n.ytmHeader,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: p.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.music_note_rounded,
                        size: 14, color: p.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.previewTrackCount(_tracks.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: p.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (totalDurationMs > 0) ...[
                      const SizedBox(width: 10),
                      Builder(
                        builder: (_) {
                          const bullet = '•';
                          return Text(bullet, style: TextStyle(color: p.textTertiary));
                        },
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.schedule_rounded,
                          size: 14, color: p.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        Formatters.formatDurationMs(totalDurationMs),
                        style: TextStyle(
                          fontSize: 12,
                          color: p.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHeroGradient(List<Color> gradient) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.queue_music_rounded,
            color: Colors.white, size: 54),
      ),
    );
  }
}
