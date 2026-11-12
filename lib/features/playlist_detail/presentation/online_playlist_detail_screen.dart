// lib/features/playlist_detail/presentation/online_playlist_detail_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';

import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/playlist_reorder_utils.dart';
import '../../../core/utils/search_algorithm_utils.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_progress.dart';
import '../../../core/widgets/pulsr_refresh_indicator.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/tables.dart' show OnlineLibraryKind;
import '../../../domain/models/ytm_track.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../library/cubit/library_cubit.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_options_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';

import '../../../core/utils/pulsr_haptics.dart';
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
  int _fetchGen = 0;

  @override
  void dispose() {
    _disposed = true;
    _cacheSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToCachedTracks() {
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
      ErrorLogger.log(
        'Failed to subscribe to cached playlist tracks',
        error: e,
        stackTrace: st,
        category: 'OnlinePlaylistDetail',
      );
    }
  }

  Future<void> _bootstrap() async {
    final hadPreview = _tracks.isNotEmpty;
    await _loadCachedPlaylist();
    if (_disposed || !mounted) return;

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
      ErrorLogger.log(
        'Failed to load cached online playlist',
        error: e,
        stackTrace: st,
        category: 'OnlinePlaylistDetail',
      );
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
          '[ONLINE_PLAYLIST] fetchPlaylistDetails timed out for ${widget.args.playlistId}',
        );
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
            '[ONLINE_PLAYLIST] getPlaylistTracks timed out for ${widget.args.playlistId}',
          );
          fetchedTracks = const [];
        }
      }

      if (_disposed || !mounted || gen != _fetchGen) return;

      if (fetchedTracks.isEmpty) {
        if (_tracks.isNotEmpty) {
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
    PulsrHaptics.mediumImpact();
    final songs = _tracks.map((t) => t.toSongData()).toList();
    if (shuffle) {
      songs.shuffle();
    }
    context.read<PlayerCubit>().playSong(songs.first, queue: songs);
  }

  Future<void> _downloadAll() async {
    if (_tracks.isEmpty || _isDownloading) return;
    PulsrHaptics.selectionClick();
    setState(() => _isDownloading = true);
    try {
      final l10n = context.l10n;
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
          '[ONLINE_PLAYLIST] Full track fetch for download failed: $e',
        );
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
    PulsrHaptics.selectionClick();
    setState(() => _isSaving = true);
    final saveFailedText = context.l10n.saveFailed;
    final loc = context.l10n;
    try {
      final playlistUseCases = getIt<PlaylistUseCases>();

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

      final libraryCubit = context.read<LibraryCubit>();
      final importedCount =
          await libraryCubit.importYtmTracksAsFavorites(tracksToSave);
      if (importedCount < 0) {
        if (mounted) {
          PulsrToast.show(context, message: saveFailedText, isError: true);
        }
        return;
      }

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
    PulsrHaptics.selectionClick();

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
      ErrorLogger.log(
        'Failed to seed reorder cache for online playlist',
        error: e,
        stackTrace: st,
        category: 'OnlinePlaylistDetail',
      );
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
    PulsrHaptics.selectionClick();
    setState(() {
      _isReordering = false;
      _selectedVideoIds.clear();
    });
  }

  void _toggleReorderSelection(String videoId) {
    PulsrHaptics.selectionClick();
    setState(() {
      if (!_selectedVideoIds.add(videoId)) {
        _selectedVideoIds.remove(videoId);
      }
    });
  }

  void _selectAllForReorder(bool select) {
    PulsrHaptics.selectionClick();
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
    PulsrHaptics.lightImpact();
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
    PulsrHaptics.selectionClick();
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
    PulsrHaptics.selectionClick();
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
              Row(
                children: [
                  Icon(Icons.swap_vert_rounded, size: 16, color: p.accent),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: Text(
                      selectedCount > 0
                          ? context.l10n.selectedCount(selectedCount)
                          : context.l10n.reorderInstructions,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
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
                    icon: const Icon(
                      Icons.vertical_align_top_rounded,
                      size: 18,
                    ),
                    label: Text(context.l10n.moveToTop),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : () => _moveSelected(toTop: false),
                    icon: const Icon(
                      Icons.vertical_align_bottom_rounded,
                      size: 18,
                    ),
                    label: Text(context.l10n.moveToBottom),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : _promptMoveSelectedToPosition,
                    icon: const Icon(
                      Icons.format_list_numbered_rounded,
                      size: 18,
                    ),
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
                  vertical: 2,
                ),
                child: AnimatedContainer(
                  duration: context.motion(PulsrMotion.state),
                  decoration: BoxDecoration(
                    color: selected
                        ? p.accent.withValues(alpha: p.isDark ? 0.14 : 0.08)
                        : p.surface,
                    borderRadius: AppRadii.r16All,
                    border: Border.all(
                      color: selected
                          ? p.accent.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleReorderSelection(track.videoId),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              onChanged: (_) =>
                                  _toggleReorderSelection(track.videoId),
                              activeColor: p.accent,
                              checkColor: p.onAccent,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadii.circular(AppRadii.r6),
                              ),
                            ),
                            Container(
                              width: 30,
                              height: 26,
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
                                  fontWeight: FontWeight.w800,
                                  fontSize: AppFontSize.tiny,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
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
                              icon: Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                                color: p.textTertiary,
                              ),
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
                                      const Icon(
                                        Icons.vertical_align_top_rounded,
                                        size: 18,
                                      ),
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
                                        size: 18,
                                      ),
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
                                        size: 18,
                                      ),
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
    final filtered = _searchQuery.trim().isEmpty
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
      content = Column(
        children: [
          if (_isLoading && _tracks.isNotEmpty)
            PulsrProgressBar.indeterminate(
              height: 2,
              color: p.accent,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: PulsrRefreshIndicator(
              onRefresh: _fetchTracks,
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: PulsrLayoutMetrics.scrollBottom(context),
                ),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context),
                      vertical: AppSpacing.sm,
                    ),
                    child: _buildHeroCard(context, p, totalDurationMs),
                  ),
                  if (_tracks.isNotEmpty)
                    PulsrSearchField(
                      controller: _searchController,
                      debounceDuration: Duration.zero,
                      hintText: context.l10n.browseSearchWithinPlaylist,
                      margin: EdgeInsetsDirectional.fromSTEB(
                        Adaptive.pagePadding(context),
                        AppSpacing.xxs,
                        Adaptive.pagePadding(context),
                        AppSpacing.xs,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      onClear: () => setState(() => _searchQuery = ''),
                    ),
                  if (_isLoading && _tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: SkeletonList(
                        padding:
                            EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      ),
                    )
                  else if (_errorMessage != null && _tracks.isEmpty)
                    PulsrEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: context.l10n.playlistLoadFailed,
                      subtitle: _errorMessage!,
                      primaryActionLabel: context.l10n.retry,
                      primaryActionIcon: Icons.refresh_rounded,
                      onPrimaryAction: _fetchTracks,
                    )
                  else if (filtered.isEmpty)
                    PulsrEmptyState(
                      icon: Icons.search_off_rounded,
                      title: _searchQuery.isNotEmpty
                          ? '${context.l10n.browseNoSongsMatch} "$_searchQuery"'
                          : context.l10n.browsePlaylistHasNoSongs,
                    )
                  else
                    for (int index = 0; index < filtered.length; index++)
                      Builder(
                        builder: (context) {
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
                                    minHeight: AppSpacing.minTouchTarget,
                                  ),
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: p.textTertiary,
                                  ),
                                  tooltip: MaterialLocalizations.of(context)
                                      .moreButtonTooltip,
                                  onPressed: () => SongOptionsSheet.show(
                                      context,
                                      song: song),
                                ),
                              ],
                            ),
                            onTap: () {
                              final songs =
                                  filtered.map((t) => t.toSongData()).toList();
                              context
                                  .read<PlayerCubit>()
                                  .playSong(song, queue: songs);
                            },
                          );
                        },
                      ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (widget.isEmbedded) {
      return content;
    }

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          leading: _isReordering
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: context.l10n.cancel,
                  onPressed: _exitReorderMode,
                )
              : const PulsrBackButton(),
          backgroundColor: p.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _isReordering ? context.l10n.reorderSongs : _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_isReordering)
              TextButton.icon(
                onPressed: _exitReorderMode,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(context.l10n.reorderDone),
              )
            else ...[
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                icon: const Icon(Icons.edit_rounded, size: 20),
                tooltip: context.l10n.browseRenamePlaylist,
                onPressed: _showRenameDialog,
              ),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: context.l10n.browseRefreshPlaylist,
                onPressed: _fetchTracks,
              ),
            ],
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
    BuildContext context,
    PulsrPalette p,
    int totalDurationMs,
  ) {
    const ytGradient = [AppColors.netflixRed, AppColors.ytRedDeep];

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r24All,
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(p.isDark ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 164,
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
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.scrimAt(0.15),
                        p.surfaceContainer.withValues(alpha: 0.92),
                        p.surfaceContainer,
                      ],
                      stops: const [0.0, 0.78, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: AppSpacing.sm,
                  start: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ytRed,
                      borderRadius: AppRadii.r8All,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          context.l10n.ytmHeader,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppFontSize.tiny,
                            fontWeight: FontWeight.w900,
                            letterSpacing: AppTracking.medium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  bottom: 0,
                  start: AppSpacing.s18,
                  end: AppSpacing.s18,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.titleLarge,
                                fontWeight: FontWeight.w900,
                                color: p.textPrimary,
                                letterSpacing: AppTracking.heading,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.bodySmall,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: p.textSecondary,
                        ),
                        tooltip: context.l10n.browseRenamePlaylist,
                        onPressed: _showRenameDialog,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s18,
              AppSpacing.xs,
              AppSpacing.s18,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildHeroBadge(
                      p,
                      icon: Icons.music_note_rounded,
                      label: context.l10n.previewTrackCount(_tracks.length),
                    ),
                    if (totalDurationMs > 0)
                      _buildHeroBadge(
                        p,
                        icon: Icons.schedule_rounded,
                        label: Formatters.formatDurationMs(totalDurationMs),
                      ),
                    if (_hasCustomOrder)
                      _buildHeroBadge(
                        p,
                        icon: Icons.reorder_rounded,
                        label: context.l10n.customOrder,
                        highlight: true,
                      ),
                    if (_isOfflineCache)
                      _buildHeroBadge(
                        p,
                        icon: Icons.cloud_off_rounded,
                        label: context.l10n.cachedCopy,
                      ),
                  ],
                ),
                if (_tracks.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _playAll(shuffle: false),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: Text(
                            context.l10n.playAll,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                            foregroundColor: p.onAccent,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _playAll(shuffle: true),
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: Text(
                            context.l10n.shuffle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.surfaceContainerHigh,
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton.filledTonal(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
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
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isDownloading ? null : _downloadAll,
                          icon: _isDownloading
                              ? PulsrProgressBar.circular(
                                  size: 14,
                                  strokeWidth: 2,
                                  color: p.accent,
                                )
                              : const Icon(Icons.download_rounded, size: 16),
                          label: Text(
                            context.l10n.downloadAll,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.hairline),
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _saveToLocalPlaylists,
                          icon: _isSaving
                              ? PulsrProgressBar.circular(
                                  size: 14,
                                  strokeWidth: 2,
                                  color: p.accent,
                                )
                              : const Icon(
                                  Icons.playlist_add_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            context.l10n.saveToPulsr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.hairline),
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All,
                            ),
                          ),
                        ),
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
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: highlight ? p.accentSoft : p.surfaceContainerHigh,
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: highlight ? p.accent.withValues(alpha: 0.35) : p.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: highlight ? p.accent : p.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w700,
              color: highlight ? p.accent : p.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
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
