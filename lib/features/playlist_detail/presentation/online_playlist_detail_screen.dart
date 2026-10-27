import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
// lib/features/playlist_detail/presentation/online_playlist_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/playlist_reorder_utils.dart';
import '../../../core/utils/search_algorithm_utils.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/tables.dart' show OnlineLibraryKind;
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class OnlinePlaylistDetailArgs {
  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? artworkUrl;
  final List<YtmTrack>? initialTracks;

  /// One of [OnlineLibraryKind]; used to classify the local cache entry.
  final String kind;

  const OnlinePlaylistDetailArgs({
    required this.playlistId,
    this.title,
    this.subtitle,
    this.artworkUrl,
    this.initialTracks,
    this.kind = OnlineLibraryKind.custom,
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
  bool _isDownloading = false;
  bool _isSaving = false;
  bool _isOfflineCache = false;
  bool _hasCustomOrder = false;
  DateTime? _cachedAt;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late final String _cachePlaylistId;
  late final String _kind;
  StreamSubscription<Result<List<YtmTrack>>>? _cacheSub;

  final Set<String> _selectedVideoIds = {};
  bool _isReordering = false;

  PlaylistUseCases get _useCases => getIt<PlaylistUseCases>();

  @override
  void initState() {
    super.initState();
    _cachePlaylistId = canonicalYtmPlaylistId(widget.args.playlistId);
    _kind = widget.args.kind;
    _title = widget.args.title ?? 'YouTube Music Playlist';
    _subtitle = widget.args.subtitle ?? 'Online Playlist';
    _artworkUrl = widget.args.artworkUrl;

    if (widget.args.initialTracks != null &&
        widget.args.initialTracks!.isNotEmpty) {
      _tracks = List<YtmTrack>.from(widget.args.initialTracks!);
      _artworkUrl ??= _tracks.firstOrNull?.artworkUrl;
    }

    _subscribeToCachedTracks();
    unawaited(_bootstrap());
  }

  bool _disposed = false;

  /// Incremented per fetch so a slow older request cannot overwrite the newer
  /// one's data or stop its spinner early.
  int _fetchGen = 0;

  @override
  void dispose() {
    _disposed = true;
    _cacheSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToCachedTracks() {
    // Offline cache access is best-effort: a partially initialised service
    // locator (widget previews/tests) must not take the screen down.
    try {
      _cacheSub = _useCases.watchOnlinePlaylistTracks(_cachePlaylistId).listen(
        (result) {
          if (_disposed || !mounted) return;
          result.fold((_) {}, (tracks) {
            if (tracks.isEmpty) return;
            setState(() {
              _tracks = tracks;
              _isLoading = false;
              final ids = {for (final track in tracks) track.videoId};
              _selectedVideoIds.removeWhere((id) => !ids.contains(id));
            });
          });
        },
        onError: (_) {},
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to subscribe to cached playlist tracks',
          error: e, stackTrace: st, category: 'OnlinePlaylistDetail');
    }
  }

  Future<void> _bootstrap() async {
    final hadPreview = _tracks.isNotEmpty;
    await _loadCachedPlaylist();
    if (_disposed || !mounted) return;

    // A freshly cached playlist opens instantly and avoids re-pulling a
    // potentially huge remote list on every visit. Pull-to-refresh or the
    // library sync still update it.
    final cachedAt = _cachedAt;
    final cacheIsFresh = cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10);
    if (_tracks.isNotEmpty && cacheIsFresh) {
      _warmStreamHead();
      return;
    }
    await _fetchTracks(isBackgroundRefresh: hadPreview || _tracks.isNotEmpty);
  }

  void _warmStreamHead() {
    if (!mounted || _tracks.isEmpty) return;
    context.read<PlayerCubit>().warmStreams(
      [for (final t in _tracks.take(3)) t.toSongData()],
    );
  }

  Future<void> _loadCachedPlaylist() async {
    try {
      final meta = await _useCases.getOnlinePlaylist(_cachePlaylistId);
      final cachedTracks =
          await _useCases.getOnlinePlaylistTracks(_cachePlaylistId);
      if (_disposed || !mounted) return;

      meta.fold((_) {}, (row) {
        if (row == null) return;
        setState(() {
          if (widget.args.title == null && row.title.isNotEmpty) {
            _title = row.title;
          }
          if (widget.args.subtitle == null && row.author.isNotEmpty) {
            _subtitle = row.author;
          }
          _artworkUrl ??= row.artworkUrl;
          _hasCustomOrder = row.hasCustomOrder;
          _cachedAt = row.cachedAt;
        });
      });

      cachedTracks.fold((_) {}, (tracks) {
        if (tracks.isEmpty) return;
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load cached online playlist',
          error: e, stackTrace: st, category: 'OnlinePlaylistDetail');
    }
  }

  Future<void> _fetchTracks({bool isBackgroundRefresh = false}) async {
    if (_disposed || !mounted) return;
    final gen = ++_fetchGen;
    if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final accountService = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      // Bound the whole fetch: paginated library playlists can otherwise
      // keep the spinner forever on slow/auth-challenged networks.
      // On timeout we fall back to the cached copy with retry.
      bool isTimeout = false;
      YtmPlaylistDetails? details;
      try {
        details = await accountService
            ?.fetchPlaylistDetails(
              widget.args.playlistId,
              maxTracks: kYtmMaxPlaylistTracks,
            )
            .timeout(const Duration(seconds: 120));
      } on TimeoutException {
        isTimeout = true;
        debugPrint(
            '[ONLINE_PLAYLIST] fetchPlaylistDetails timed out for ${widget.args.playlistId}');
      }

      if (_disposed || !mounted || gen != _fetchGen) return;

      List<YtmTrack> fetchedTracks = details?.tracks ?? const [];

      if (fetchedTracks.isEmpty) {
        final ytmService = getIt<YtmService>();
        try {
          fetchedTracks = await ytmService
              .getPlaylistTracks(
                widget.args.playlistId,
                limit: kYtmMaxPlaylistTracks,
              )
              .timeout(const Duration(seconds: 120));
        } on TimeoutException {
          isTimeout = true;
          debugPrint(
              '[ONLINE_PLAYLIST] getPlaylistTracks timed out for ${widget.args.playlistId}');
          fetchedTracks = const [];
        }
      }

      if (_disposed || !mounted || gen != _fetchGen) return;

      if (fetchedTracks.isEmpty) {
        if (_tracks.isNotEmpty) {
          // Cache/preview is still useful; keep it visible and mark it stale
          // instead of replacing the screen with an error.
          setState(() {
            _isLoading = false;
            _isOfflineCache = true;
            _errorMessage = null;
          });
          return;
        }
        if (!isBackgroundRefresh) {
          setState(() {
            _isLoading = false;
            _errorMessage = isTimeout
                ? 'Connection timed out. Check your network and try again.'
                : context.l10n.browseCouldNotLoadTracks;
          });
        }
        return;
      }

      final unique = <String, YtmTrack>{};
      for (final track in fetchedTracks) {
        if (track.videoId.isEmpty) continue;
        unique.putIfAbsent(track.videoId, () => track);
      }
      if (unique.isEmpty) {
        if (_tracks.isNotEmpty) {
          setState(() {
            _isLoading = false;
            _isOfflineCache = true;
          });
          return;
        }
        if (!isBackgroundRefresh) {
          setState(() {
            _isLoading = false;
            _errorMessage = context.l10n.browseCouldNotLoadTracks;
          });
        }
        return;
      }

      var resolvedTitle = _title;
      var resolvedSubtitle = _subtitle;
      var resolvedArtwork = _artworkUrl;
      if (details != null) {
        if (details.title.isNotEmpty &&
            details.title != 'YouTube Playlist' &&
            details.title != 'Playlist') {
          resolvedTitle = details.title;
        }
        if (details.author.isNotEmpty &&
            details.author != 'YouTube Music' &&
            details.author != 'Auto Playlist' &&
            !details.author.toLowerCase().startsWith('playlist ')) {
          resolvedSubtitle = details.author;
        }
        resolvedArtwork = details.artworkUrl ?? unique.values.first.artworkUrl;
      } else {
        resolvedArtwork ??= unique.values.first.artworkUrl;
      }

      // Persist the full snapshot first (merging into any hand-built order),
      // then read the ordered rows back so the list never flashes the remote
      // order over the saved one.
      var orderedTracks = unique.values.toList(growable: false);
      try {
        await _useCases.cacheOnlinePlaylist(
          playlistId: _cachePlaylistId,
          kind: _kind,
          title: resolvedTitle,
          author: resolvedSubtitle,
          artworkUrl: resolvedArtwork,
          tracks: orderedTracks,
        );
        final cached =
            await _useCases.getOnlinePlaylistTracks(_cachePlaylistId);
        cached.fold((_) {}, (tracks) {
          if (tracks.isNotEmpty) orderedTracks = tracks;
        });
        final meta = await _useCases.getOnlinePlaylist(_cachePlaylistId);
        meta.fold((_) {}, (row) {
          if (row != null) _hasCustomOrder = row.hasCustomOrder;
        });
      } catch (e, st) {
        debugPrint('[ONLINE_PLAYLIST] Cache write failed: $e\n$st');
      }

      if (_disposed || !mounted || gen != _fetchGen) return;

      setState(() {
        _tracks = orderedTracks;
        _isLoading = false;
        _isOfflineCache = false;
        _errorMessage = null;
        _title = resolvedTitle;
        _subtitle = resolvedSubtitle;
        _artworkUrl = resolvedArtwork;
      });
      // Speculative warm: pre-resolve the head of the list so a tap near the
      // top starts from the shared YtmUrlCache instead of a cold multi-engine
      // resolve. Staggered and bot-cooldown-aware inside warmStreams.
      _warmStreamHead();
    } catch (e) {
      if (_disposed || !mounted || gen != _fetchGen) return;
      if (_tracks.isNotEmpty) {
        setState(() {
          _isLoading = false;
          _isOfflineCache = true;
          _errorMessage = null;
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = e is TimeoutException
            ? 'Connection timed out. Check your network and try again.'
            : '${context.l10n.playlistLoadFailed} $e';
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

  Future<void> _downloadAll() async {
    if (_tracks.isEmpty || _isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final l10n = context.l10n;
      // The visible list is capped for rendering; fetch the complete playlist
      // so "download all" queues every track, not just the preview window.
      var tracks = _tracks;
      try {
        final fullTracks = await getIt<YtmService>()
            .getPlaylistTracks(
              widget.args.playlistId,
              limit: kYtmMaxPlaylistTracks,
            )
            .timeout(const Duration(seconds: 120));
        if (fullTracks.isNotEmpty) tracks = fullTracks;
      } catch (e) {
        debugPrint(
            '[ONLINE_PLAYLIST] Full track fetch for download failed: $e');
      }
      if (_disposed || !mounted) return;

      final songs = tracks.map((t) => t.toSongData()).toList();
      final downloadCubit = getIt.isRegistered<YtmDownloadCubit>()
          ? getIt<YtmDownloadCubit>()
          : null;
      if (downloadCubit == null) return;
      final report = await downloadCubit.downloadAllDetailed(songs);

      final summary = report.queued > 0
          ? l10n.queuedFromTitle(report.queued, _title)
          : l10n.allDownloaded(_title);
      final extras = describeBatchOutcomeExtras(
        l10n,
        capped: report.capped,
        skippedLocal: report.skippedLocal,
        failed: report.failed,
        firstError: report.firstError,
      );
      if (mounted) {
        PulsrToast.show(
          context,
          message: '$summary$extras',
          duration: const Duration(seconds: 4),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _saveToLocalPlaylists() async {
    if (_tracks.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    // Captured before async gaps (no context-across-gap).
    final saveFailedText = context.l10n.saveFailed;
    final loc = context.l10n;
    try {
      final playlistUseCases = getIt<PlaylistUseCases>();

      // The visible list is capped for rendering; save the complete playlist
      // instead of silently truncating it at the preview window.
      var tracksToSave = _tracks;
      try {
        final accountService = getIt.isRegistered<YtmAccountService>()
            ? getIt<YtmAccountService>()
            : null;
        if (accountService != null) {
          final details = await accountService
              .fetchPlaylistDetails(
                widget.args.playlistId,
                maxTracks: kYtmMaxPlaylistTracks,
              )
              .timeout(const Duration(seconds: 120));
          if (details != null && details.tracks.isNotEmpty) {
            tracksToSave = details.tracks;
          }
        } else {
          final fullTracks = await getIt<YtmService>()
              .getPlaylistTracks(
                widget.args.playlistId,
                limit: kYtmMaxPlaylistTracks,
              )
              .timeout(const Duration(seconds: 120));
          if (fullTracks.isNotEmpty) tracksToSave = fullTracks;
        }
      } catch (e) {
        debugPrint('[ONLINE_PLAYLIST] Full fetch for save failed: $e');
      }
      if (_disposed || !mounted) return;

      tracksToSave = _applyCurrentOrder(tracksToSave);

      // First ensure tracks are known in local favorites repository.
      // A negative result means the import failed: creating the playlist now
      // would leave it empty while reporting success.
      final libraryCubit = context.read<LibraryCubit>();
      final importedCount =
          await libraryCubit.importYtmTracksAsFavorites(tracksToSave);
      if (importedCount < 0) {
        if (mounted) {
          PulsrToast.show(context, message: saveFailedText, isError: true);
        }
        return;
      }

      // Hash-derived ids only exist when the import allocated exactly that id;
      // already-downloaded tracks keep their positive local id. Resolve the
      // real row ids by remoteId so the FK-constrained insert cannot fail.
      final songIds = await _resolveSavedSongIds(tracksToSave);

      final playlistRes = await playlistUseCases.createPlaylist(_title);
      final createdId = playlistRes.fold((l) => null, (r) => r);

      if (createdId == null) {
        if (mounted) {
          PulsrToast.show(context, message: saveFailedText, isError: true);
        }
        return;
      }

      final addRes =
          await playlistUseCases.addSongsToPlaylist(createdId, songIds);
      final addFailure = addRes.fold((f) => f.message, (_) => null);
      if (addFailure != null) {
        // Never leave the just-created playlist empty behind a success toast.
        await playlistUseCases.deletePlaylist(createdId);
        if (mounted) {
          PulsrToast.show(context, message: saveFailedText, isError: true);
        }
        return;
      }

      if (mounted) {
        PulsrToast.show(
          context,
          message: loc.savedToLocal(_title, songIds.length),
          isSuccess: true,
        );
      }
    } catch (_) {
      if (mounted) {
        PulsrToast.show(
          context,
          message: saveFailedText,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Keeps the user's saved order while adopting fresher remote metadata.
  /// Tracks that are new remotely append in remote order.
  List<YtmTrack> _applyCurrentOrder(List<YtmTrack> fresh) {
    if (fresh.isEmpty || _tracks.isEmpty) return fresh;
    final freshById = <String, YtmTrack>{
      for (final track in fresh) track.videoId: track,
    };
    final ordered = <YtmTrack>[];
    for (final track in _tracks) {
      final updated = freshById.remove(track.videoId);
      if (updated != null) ordered.add(updated);
    }
    for (final track in fresh) {
      final remaining = freshById.remove(track.videoId);
      if (remaining != null) ordered.add(remaining);
    }
    return ordered;
  }

  /// Maps every track's videoId to its real persisted row id. Falls back to
  /// the deterministic hash id when the row cannot be resolved (repository
  /// absent/failing), so a genuine FK failure still surfaces through the
  /// insert result instead of being silently swallowed.
  Future<List<int>> _resolveSavedSongIds([List<YtmTrack>? sourceTracks]) async {
    final tracks = sourceTracks ?? _tracks;
    final fallback = [for (final t in tracks) t.songId];
    if (!getIt.isRegistered<IMusicRepository>()) return fallback;
    try {
      final res = await getIt<IMusicRepository>().getFavorites();
      final byRemoteId = <String, int>{};
      res.fold((_) {}, (songs) {
        for (final song in songs) {
          final remoteId = song.remoteId;
          if (remoteId != null && remoteId.isNotEmpty) {
            byRemoteId[remoteId] = song.id;
          }
        }
      });
      if (byRemoteId.isEmpty) return fallback;
      return [for (final t in tracks) byRemoteId[t.videoId] ?? t.songId];
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _enterReorderMode() async {
    if (_tracks.isEmpty || _isReordering) return;

    // Reordering needs materialised rows; a preview-only list (offline with no
    // prior cache) is seeded without claiming to be a fresh full snapshot.
    // Seeding finishes before the list becomes draggable so a fast first drag
    // cannot race the seed write.
    try {
      final cached = await _useCases.getOnlinePlaylistTracks(_cachePlaylistId);
      final hasEntries =
          cached.fold((_) => false, (tracks) => tracks.isNotEmpty);
      if (!hasEntries && _tracks.isNotEmpty) {
        await _useCases.cacheOnlinePlaylist(
          playlistId: _cachePlaylistId,
          kind: _kind,
          title: _title,
          author: _subtitle,
          artworkUrl: _artworkUrl,
          tracks: _tracks,
          fullSnapshot: false,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to seed reorder cache for online playlist',
          error: e, stackTrace: st, category: 'OnlinePlaylistDetail');
    }
    if (_disposed || !mounted) return;

    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isReordering = true;
      _selectedVideoIds.clear();
    });
  }

  void _exitReorderMode() {
    setState(() {
      _isReordering = false;
      _selectedVideoIds.clear();
    });
  }

  void _toggleReorderSelection(String videoId) {
    setState(() {
      if (!_selectedVideoIds.add(videoId)) {
        _selectedVideoIds.remove(videoId);
      }
    });
  }

  void _selectAllForReorder(bool select) {
    setState(() {
      _selectedVideoIds.clear();
      if (select) {
        _selectedVideoIds.addAll(_tracks.map((t) => t.videoId));
      }
    });
  }

  bool _sameTrackOrder(List<YtmTrack> a, List<YtmTrack> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].videoId != b[i].videoId) return false;
    }
    return true;
  }

  Future<void> _orderSaveChain = Future.value();
  int _orderSaveVersion = 0;

  void _onReorder(int oldIndex, int newIndex) {
    final reordered = applyPlaylistReorder(
      items: _tracks,
      oldIndex: oldIndex,
      newIndex: newIndex,
      isSelected: (track) => _selectedVideoIds.contains(track.videoId),
    );
    if (_sameTrackOrder(reordered, _tracks)) return;
    final previous = _tracks;
    setState(() => _tracks = reordered);
    _queueOrderSave(previous, reordered);
  }

  void _moveSelected({required bool toTop}) {
    if (_selectedVideoIds.isEmpty) return;
    final reordered = moveSelectedToEdge(
      items: _tracks,
      isSelected: (track) => _selectedVideoIds.contains(track.videoId),
      toTop: toTop,
    );
    if (_sameTrackOrder(reordered, _tracks)) return;
    final previous = _tracks;
    setState(() => _tracks = reordered);
    _queueOrderSave(previous, reordered);
  }

  Future<int?> _showPositionPickerDialog({
    required BuildContext context,
    required int currentCount,
    int? initialPosition,
  }) async {
    final result = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.moveToPosition,
      message: context.l10n.enterPosition(currentCount),
      initialText: initialPosition != null ? '$initialPosition' : '1',
      hintText: '1 - $currentCount',
      icon: Icons.format_list_numbered_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
      keyboardType: TextInputType.number,
    );
    if (result == null) return null;
    final parsed = int.tryParse(result.trim());
    if (parsed == null) return null;
    return parsed.clamp(1, currentCount);
  }

  Future<void> _promptMoveSelectedToPosition() async {
    if (_selectedVideoIds.isEmpty || _tracks.isEmpty) return;
    final targetPos = await _showPositionPickerDialog(
      context: context,
      currentCount: _tracks.length,
    );
    if (targetPos == null) return;
    final targetIndex = targetPos - 1;
    final reordered = moveSelectedToPosition<YtmTrack>(
      items: _tracks,
      isSelected: (track) => _selectedVideoIds.contains(track.videoId),
      targetIndex: targetIndex,
    );
    if (_sameTrackOrder(reordered, _tracks)) return;
    final previous = _tracks;
    setState(() => _tracks = reordered);
    _queueOrderSave(previous, reordered);
  }

  Future<void> _promptMoveSingleToPosition(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final targetPos = await _showPositionPickerDialog(
      context: context,
      currentCount: _tracks.length,
      initialPosition: index + 1,
    );
    if (targetPos == null) return;
    final targetIndex = targetPos - 1;
    final track = _tracks[index];
    final reordered = moveSelectedToPosition<YtmTrack>(
      items: _tracks,
      isSelected: (t) => t.videoId == track.videoId,
      targetIndex: targetIndex,
    );
    if (_sameTrackOrder(reordered, _tracks)) return;
    final previous = _tracks;
    setState(() => _tracks = reordered);
    _queueOrderSave(previous, reordered);
  }

  void _moveSingleToEdge(int index, {required bool toTop}) {
    if (index < 0 || index >= _tracks.length) return;
    final track = _tracks[index];
    final reordered = moveSelectedToEdge<YtmTrack>(
      items: _tracks,
      isSelected: (t) => t.videoId == track.videoId,
      toTop: toTop,
    );
    if (_sameTrackOrder(reordered, _tracks)) return;
    final previous = _tracks;
    setState(() => _tracks = reordered);
    _queueOrderSave(previous, reordered);
  }

  Future<void> _showRenameDialog() async {
    final newTitle = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.browseRenamePlaylist,
      initialText: _title,
      hintText: context.l10n.playlistName,
      icon: Icons.edit_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    if (newTitle != null &&
        newTitle.trim().isNotEmpty &&
        newTitle.trim() != _title) {
      final trimmed = newTitle.trim();
      setState(() => _title = trimmed);
      try {
        await _useCases.renameOnlinePlaylist(_cachePlaylistId, trimmed);
      } catch (e) {
        debugPrint('[ONLINE_PLAYLIST] Failed to rename playlist: $e');
      }
    }
  }

  void _queueOrderSave(List<YtmTrack> previous, List<YtmTrack> next) {
    final version = ++_orderSaveVersion;
    final failureText = context.l10n.reorderFailed;
    _orderSaveChain = _orderSaveChain.then((_) async {
      // A newer drag happened while this save waited: only the latest order
      // needs to hit the database.
      if (version != _orderSaveVersion) return;
      String? failure;
      try {
        final result = await _useCases.reorderOnlinePlaylistTracks(
          _cachePlaylistId,
          [for (final track in next) track.videoId],
        );
        failure = result.fold((f) => f.message, (_) => null);
      } catch (e) {
        failure = e.toString();
      }
      if (!mounted || version != _orderSaveVersion) return;
      if (failure != null) {
        setState(() => _tracks = previous);
        PulsrToast.show(context, message: failureText, isError: true);
        return;
      }
      setState(() => _hasCustomOrder = true);
    });
  }

  Widget _buildReorderContent(PulsrPalette p) {
    final selectedCount = _selectedVideoIds.length;
    final allSelected = _tracks.isNotEmpty && selectedCount == _tracks.length;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsetsDirectional.fromSTEB(
            Adaptive.pagePadding(context),
            AppSpacing.sm,
            Adaptive.pagePadding(context),
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            border: Border(bottom: BorderSide(color: p.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedCount > 0
                    ? context.l10n.selectedCount(selectedCount)
                    : context.l10n.reorderInstructions,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s6),
              Wrap(
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _selectAllForReorder(!allSelected),
                    icon: Icon(
                      allSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 18,
                    ),
                    label: Text(
                      allSelected
                          ? context.l10n.browseDeselect
                          : context.l10n.selectAllAction,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : () => _moveSelected(toTop: true),
                    icon:
                        const Icon(Icons.vertical_align_top_rounded, size: 18),
                    label: Text(context.l10n.moveToTop),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : () => _moveSelected(toTop: false),
                    icon: const Icon(Icons.vertical_align_bottom_rounded,
                        size: 18),
                    label: Text(context.l10n.moveToBottom),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : _promptMoveSelectedToPosition,
                    icon: const Icon(Icons.format_list_numbered_rounded,
                        size: 18),
                    label: Text(context.l10n.moveToPosition),
                  ),
                  FilledButton.icon(
                    onPressed: _exitReorderMode,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(context.l10n.reorderDone),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: PulsrLayoutMetrics.scrollBottom(context),
            ),
            itemCount: _tracks.length,
            onReorderItem: _onReorder,
            itemBuilder: (context, index) {
              final track = _tracks[index];
              final selected = _selectedVideoIds.contains(track.videoId);
              return Padding(
                key: ValueKey('online_reorder_${track.videoId}'),
                padding: EdgeInsets.symmetric(
                  horizontal: Adaptive.pagePadding(context),
                  vertical: AppSpacing.xxs,
                ),
                child: Material(
                  color: selected
                      ? p.accent.withValues(alpha: p.isDark ? 0.14 : 0.08)
                      : p.surface,
                  borderRadius: AppRadii.r16All,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _toggleReorderSelection(track.videoId),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.xs,
                          AppSpacing.xs,
                          AppSpacing.xs,
                          AppSpacing.xs),
                      child: Row(
                        children: [
                          Checkbox(
                            value: selected,
                            onChanged: (_) =>
                                _toggleReorderSelection(track.videoId),
                            activeColor: p.accent,
                            checkColor: p.onAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.circular(AppRadii.r6),
                            ),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? p.accent.withValues(alpha: 0.2)
                                  : p.surfaceContainerHigh,
                              borderRadius: AppRadii.r8All,
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: selected ? p.accent : p.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: AppFontSize.caption,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          CachedArtwork(
                            id: track.songId,
                            remoteUrl: track.artworkUrl,
                            size: 44,
                            borderRadius: 10,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: AppFontSize.body,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded,
                                size: 20, color: p.textTertiary),
                            tooltip: context.l10n.moveToPosition,
                            onSelected: (val) {
                              if (val == 'top') {
                                _moveSingleToEdge(index, toTop: true);
                              } else if (val == 'bottom') {
                                _moveSingleToEdge(index, toTop: false);
                              } else if (val == 'position') {
                                _promptMoveSingleToPosition(index);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'top',
                                child: Row(
                                  children: [
                                    const Icon(Icons.vertical_align_top_rounded,
                                        size: 18),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(context.l10n.moveToTop),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'position',
                                child: Row(
                                  children: [
                                    const Icon(
                                        Icons.format_list_numbered_rounded,
                                        size: 18),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(context.l10n.moveToPosition),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'bottom',
                                child: Row(
                                  children: [
                                    const Icon(
                                        Icons.vertical_align_bottom_rounded,
                                        size: 18),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(context.l10n.moveToBottom),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s10),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: p.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final filtered = _searchQuery.isEmpty
        ? _tracks
        : _tracks.where((t) {
            final q = SearchAlgorithmUtils.normalize(_searchQuery);
            return SearchAlgorithmUtils.normalize(t.title).contains(q) ||
                SearchAlgorithmUtils.normalize(t.artist).contains(q);
          }).toList();

    final totalDurationMs =
        _tracks.fold<int>(0, (sum, t) => sum + t.duration.inMilliseconds);

    final Widget content;
    if (_isReordering && _tracks.isNotEmpty) {
      content = _buildReorderContent(p);
    } else {
      content = RefreshIndicator(
        onRefresh: _fetchTracks,
        color: p.accent,
        backgroundColor: p.surfaceContainer,
        child: ListView(
          padding:
              EdgeInsets.only(bottom: PulsrLayoutMetrics.scrollBottom(context)),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ── HERO BANNER ─────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: AppSpacing.sm,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _playAll(shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: Text(context.l10n.shuffle,
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surfaceContainerHigh,
                          foregroundColor: p.textPrimary,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    IconButton.filledTonal(
                      constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget),
                      onPressed: _enterReorderMode,
                      icon: const Icon(Icons.swap_vert_rounded, size: 20),
                      tooltip: context.l10n.reorderSongs,
                      style: IconButton.styleFrom(
                        backgroundColor: p.surfaceContainerHigh,
                        foregroundColor: p.textPrimary,
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
                        onPressed: _isDownloading ? null : _downloadAll,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(context.l10n.downloadAll,
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: p.hairline),
                          foregroundColor: p.textPrimary,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s10),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _saveToLocalPlaylists,
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: Text(context.l10n.saveToPulsr,
                            style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: p.hairline),
                          foregroundColor: p.textPrimary,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s10),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── SEARCH BAR ──────────────────────────────────────────────
            if (_tracks.isNotEmpty)
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
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
                            constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget),
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            tooltip: context.l10n.clear,
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: p.surfaceContainer,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.s10),
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.r14All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.r14All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
              ),

            // ── CONTENT / TRACKS LIST ───────────────────────────────────
            if (_isLoading && _tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: SkeletonList(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md)),
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
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.bodySmall),
                      ),
                      const SizedBox(height: AppSpacing.md),
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
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s40),
                child: Center(
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? '${context.l10n.browseNoSongsMatch} "$_searchQuery"'
                        : context.l10n.browsePlaylistHasNoSongs,
                    style: TextStyle(
                        color: p.textTertiary, fontSize: AppFontSize.body),
                  ),
                ),
              )
            else
              for (int index = 0; index < filtered.length; index++)
                Builder(builder: (context) {
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
                          constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget),
                          icon: Icon(Icons.more_vert_rounded,
                              size: 18, color: p.textTertiary),
                          tooltip: MaterialLocalizations.of(context)
                              .moreButtonTooltip,
                          onPressed: () =>
                              SongOptionsSheet.show(context, song: song),
                        ),
                      ],
                    ),
                    onTap: () {
                      final songs =
                          filtered.map((t) => t.toSongData()).toList();
                      context.read<PlayerCubit>().playSong(song, queue: songs);
                    },
                  );
                }),
          ],
        ),
      );
    }

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
              constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget),
              icon: const Icon(Icons.edit_rounded),
              tooltip: context.l10n.browseRenamePlaylist,
              onPressed: _showRenameDialog,
            ),
            IconButton(
              constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: context.l10n.browseRefreshPlaylist,
              onPressed: _isReordering ? null : _fetchTracks,
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
    const ytGradient = [AppColors.netflixRed, AppColors.ytRedDeep];

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r24All,
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
                    cacheWidth: 600,
                    cacheHeight: 360,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : _buildFallbackHeroGradient(ytGradient),
                    errorBuilder: (_, __, ___) =>
                        _buildFallbackHeroGradient(ytGradient),
                  )
                else
                  _buildFallbackHeroGradient(ytGradient),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.scrimAt(0.75),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                PositionedDirectional(
                  bottom: 16,
                  start: 16,
                  end: 16,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxs),
                        decoration: BoxDecoration(
                          color: AppColors.ytRed,
                          borderRadius: AppRadii.r6All,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle_fill_rounded,
                                color: Colors.white, size: 14),
                            const SizedBox(width: AppSpacing.xxs),
                            Text(
                              context.l10n.ytmHeader,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w900,
                                letterSpacing: AppTracking.medium,
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
            padding: const EdgeInsets.all(AppSpacing.s18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        style: TextStyle(
                          fontSize: AppFontSize.titleLarge,
                          fontWeight: FontWeight.w900,
                          color: p.textPrimary,
                          letterSpacing: AppTracking.heading,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      tooltip: context.l10n.browseRenamePlaylist,
                      onPressed: _showRenameDialog,
                      color: p.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _subtitle,
                  style: TextStyle(
                    fontSize: AppFontSize.bodySmall,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                Row(
                  children: [
                    Icon(Icons.music_note_rounded,
                        size: 14, color: p.textTertiary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      context.l10n.previewTrackCount(_tracks.length),
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (totalDurationMs > 0) ...[
                      const SizedBox(width: AppSpacing.s10),
                      Builder(
                        builder: (_) {
                          const bullet = '•';
                          return Text(bullet,
                              style: TextStyle(color: p.textTertiary));
                        },
                      ),
                      const SizedBox(width: AppSpacing.s10),
                      Icon(Icons.schedule_rounded,
                          size: 14, color: p.textTertiary),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        Formatters.formatDurationMs(totalDurationMs),
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: p.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_hasCustomOrder || _isOfflineCache) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.s6,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      if (_hasCustomOrder)
                        _buildHeroBadge(
                          p,
                          icon: Icons.reorder_rounded,
                          label: context.l10n.customOrder,
                        ),
                      if (_isOfflineCache)
                        _buildHeroBadge(
                          p,
                          icon: Icons.cloud_off_rounded,
                          label: context.l10n.cachedCopy,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge(
    PulsrPalette p, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: AppRadii.r6All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: p.accent),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
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
        child: Icon(Icons.queue_music_rounded, color: Colors.white, size: 54),
      ),
    );
  }
}
