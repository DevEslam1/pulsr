import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
// lib/features/playlist_detail/presentation/playlist_detail_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:on_audio_query/on_audio_query.dart' show ArtworkType;

import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/playlist_share_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/search_algorithm_utils.dart';
import '../../../core/widgets/async_state_builder.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/playlist_reorder_utils.dart';
import '../../../core/widgets/pulsr_empty_state.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../data/usecases/playlist_io_usecases.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import '../../player/cubit/player_cubit.dart';
import '../../library/cubit/library_cubit.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../sheets/song_options_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Reactively-loaded playlist contents or the failure that prevented loading,
/// so a DB error surfaces as a retryable state instead of an empty list.
class _PlaylistSongsResult {
  final List<SongsTableData> songs;
  final String? error;

  const _PlaylistSongsResult({this.songs = const [], this.error});
}

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistsTableData playlist;
  final PlaylistUseCases? playlistUseCases;
  final bool isEmbedded;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.playlistUseCases,
    this.isEmbedded = false,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  PlaylistsTableData get playlist => widget.playlist;

  PlaylistUseCases get _useCases =>
      widget.playlistUseCases ?? getIt<PlaylistUseCases>();

  /// Memoized so the `StreamBuilder` does not resubscribe on every rebuild.
  /// Cleared on retry to force a fresh subscription.
  Stream<_PlaylistSongsResult>? _songsStream;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isReordering = false;
  List<SongsTableData> _reorderSongs = [];
  final Set<int> _selectedReorderIds = {};
  Future<void> _orderSaveChain = Future.value();
  int _orderSaveVersion = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _enterReorderMode(List<SongsTableData> songs) {
    if (playlist.isSmart || songs.isEmpty || _isReordering) return;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isReordering = true;
      _selectedReorderIds.clear();
      _reorderSongs = List<SongsTableData>.from(songs);
    });
  }

  void _exitReorderMode() {
    setState(() {
      _isReordering = false;
      _selectedReorderIds.clear();
      _reorderSongs = [];
    });
  }

  void _toggleReorderSelection(int songId) {
    setState(() {
      if (!_selectedReorderIds.add(songId)) {
        _selectedReorderIds.remove(songId);
      }
    });
  }

  void _selectAllForReorder(bool select) {
    setState(() {
      _selectedReorderIds.clear();
      if (select) {
        _selectedReorderIds.addAll(_reorderSongs.map((s) => s.id));
      }
    });
  }

  bool _sameSongOrder(List<SongsTableData> a, List<SongsTableData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _onReorder(int oldIndex, int newIndex) {
    final reordered = applyPlaylistReorder(
      items: _reorderSongs,
      oldIndex: oldIndex,
      newIndex: newIndex,
      isSelected: (song) => _selectedReorderIds.contains(song.id),
    );
    if (_sameSongOrder(reordered, _reorderSongs)) return;
    final previous = _reorderSongs;
    setState(() => _reorderSongs = reordered);
    _queueOrderSave(previous, reordered);
  }

  void _moveSelected({required bool toTop}) {
    if (_selectedReorderIds.isEmpty) return;
    final reordered = moveSelectedToEdge(
      items: _reorderSongs,
      isSelected: (song) => _selectedReorderIds.contains(song.id),
      toTop: toTop,
    );
    if (_sameSongOrder(reordered, _reorderSongs)) return;
    final previous = _reorderSongs;
    setState(() => _reorderSongs = reordered);
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
    if (_selectedReorderIds.isEmpty || _reorderSongs.isEmpty) return;
    final targetPos = await _showPositionPickerDialog(
      context: context,
      currentCount: _reorderSongs.length,
    );
    if (targetPos == null) return;
    final targetIndex = targetPos - 1;
    final reordered = moveSelectedToPosition<SongsTableData>(
      items: _reorderSongs,
      isSelected: (song) => _selectedReorderIds.contains(song.id),
      targetIndex: targetIndex,
    );
    if (_sameSongOrder(reordered, _reorderSongs)) return;
    final previous = _reorderSongs;
    setState(() => _reorderSongs = reordered);
    _queueOrderSave(previous, reordered);
  }

  Future<void> _promptMoveSingleToPosition(int index) async {
    if (index < 0 || index >= _reorderSongs.length) return;
    final targetPos = await _showPositionPickerDialog(
      context: context,
      currentCount: _reorderSongs.length,
      initialPosition: index + 1,
    );
    if (targetPos == null) return;
    final targetIndex = targetPos - 1;
    final song = _reorderSongs[index];
    final reordered = moveSelectedToPosition<SongsTableData>(
      items: _reorderSongs,
      isSelected: (s) => s.id == song.id,
      targetIndex: targetIndex,
    );
    if (_sameSongOrder(reordered, _reorderSongs)) return;
    final previous = _reorderSongs;
    setState(() => _reorderSongs = reordered);
    _queueOrderSave(previous, reordered);
  }

  void _moveSingleToEdge(int index, {required bool toTop}) {
    if (index < 0 || index >= _reorderSongs.length) return;
    final song = _reorderSongs[index];
    final reordered = moveSelectedToEdge<SongsTableData>(
      items: _reorderSongs,
      isSelected: (s) => s.id == song.id,
      toTop: toTop,
    );
    if (_sameSongOrder(reordered, _reorderSongs)) return;
    final previous = _reorderSongs;
    setState(() => _reorderSongs = reordered);
    _queueOrderSave(previous, reordered);
  }

  void _queueOrderSave(
      List<SongsTableData> previous, List<SongsTableData> next) {
    final version = ++_orderSaveVersion;
    final failureText = context.l10n.reorderFailed;
    final useCases = _useCases;
    _orderSaveChain = _orderSaveChain.then((_) async {
      if (version != _orderSaveVersion) return;
      String? failure;
      try {
        final result = await useCases.reorderPlaylistSongs(
          playlist.id,
          [for (final song in next) song.id],
        );
        failure = result.fold((f) => f.message, (_) => null);
      } catch (e) {
        failure = e.toString();
      }
      if (!mounted || version != _orderSaveVersion) return;
      if (failure != null) {
        setState(() => _reorderSongs = previous);
        PulsrToast.show(context, message: failureText, isError: true);
      }
    });
  }

  Stream<_PlaylistSongsResult> _resolveSongsStream(String invalidRulesMessage) {
    final cached = _songsStream;
    if (cached != null) return cached;
    final useCases = _useCases;
    final Stream<_PlaylistSongsResult> stream;
    if (playlist.isSmart && playlist.smartCriteria != null) {
      final criteria = SmartCriteria.tryDecode(playlist.smartCriteria);
      if (criteria != null) {
        stream = useCases
            .watchSmartPlaylistSongs(criteria)
            .map((songs) => _PlaylistSongsResult(songs: songs));
      } else {
        // Corrupt criteria: surface a retryable error instead of pretending the
        // playlist is simply empty.
        stream = Stream.value(
          _PlaylistSongsResult(error: invalidRulesMessage),
        );
      }
    } else {
      stream = useCases.watchPlaylistSongs(playlist.id).map(
            (res) => res.fold(
              (failure) => _PlaylistSongsResult(error: failure.message),
              (songs) => _PlaylistSongsResult(songs: songs),
            ),
          );
    }
    return _songsStream = stream;
  }

  void _retryLoad() {
    setState(() => _songsStream = null);
  }

  Future<void> _downloadPlaylist(
      BuildContext context, List<SongsTableData> songs) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.cannotDownloadEmpty)),
      );
      return;
    }

    final downloadCubit = context.read<YtmDownloadCubit?>() ??
        (getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null);
    if (downloadCubit == null) return;
    final report = await downloadCubit.downloadAllDetailed(songs);
    if (!context.mounted) return;
    final queuedCount = report.queued;
    final extras = describeBatchOutcomeExtras(
      context.l10n,
      capped: report.capped,
      failed: report.failed,
      firstError: report.firstError,
      skippedLocal: report.skippedLocal,
    );

    if (queuedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${context.l10n.queuedForDownload(queuedCount)}$extras'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final hasOnlineTracks =
          songs.any((s) => s.remoteId != null && s.remoteId!.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${hasOnlineTracks ? context.l10n.browseAllOnlineTracksDownloaded : context.l10n.browseAllTracksOfflineLocal}$extras',
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
    try {
      await exportUseCase.exportToFile(playlist.name, songs);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.exportFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.playlistExported(songs.length)),
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

  Widget _buildReorderContent(BuildContext context, PulsrPalette p) {
    final selectedCount = _selectedReorderIds.length;
    final allSelected =
        _reorderSongs.isNotEmpty && selectedCount == _reorderSongs.length;

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
            itemCount: _reorderSongs.length,
            onReorderItem: _onReorder,
            itemBuilder: (context, index) {
              final song = _reorderSongs[index];
              final selected = _selectedReorderIds.contains(song.id);
              return Padding(
                key: ValueKey('reorder_song_${song.id}'),
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
                    onTap: () => _toggleReorderSelection(song.id),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Row(
                        children: [
                          Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleReorderSelection(song.id),
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
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 44,
                            borderRadius: 10,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
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
                                  song.artist,
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
    final playlistUseCases = _useCases;

    final Stream<_PlaylistSongsResult> songsStream =
        _resolveSongsStream(context.l10n.browseCouldNotLoadTracks);

    return StreamBuilder<_PlaylistSongsResult>(
      stream: songsStream,
      builder: (context, snapshot) {
        final songs = snapshot.data?.songs ?? [];
        final noTracksState = PulsrEmptyState(
          icon: playlist.isSmart
              ? Icons.auto_awesome_rounded
              : Icons.queue_music_rounded,
          title: context.l10n.browseNoTracks,
          subtitle: playlist.isSmart
              ? context.l10n.browseNoTracksMatchSmartRules
              : context.l10n.emptyPlaylist,
        );

        final scaffold = Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: _isReordering
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.l10n.cancel,
                    onPressed: _exitReorderMode,
                  )
                : (widget.isEmbedded ? null : const PulsrBackButton()),
            title: _isReordering
                ? Text(context.l10n.reorderSongs)
                : Row(
                    children: [
                      if (playlist.isSmart) ...[
                        Icon(Icons.auto_awesome_rounded,
                            color: p.accent, size: 20),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Expanded(
                          child: Text(playlist.name,
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
            actions: [
              if (_isReordering)
                TextButton.icon(
                  onPressed: _exitReorderMode,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(context.l10n.reorderDone),
                )
              else ...[
                if (!playlist.isSmart && songs.isNotEmpty)
                  IconButton(
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    tooltip: context.l10n.reorderSongs,
                    icon: const Icon(Icons.swap_vert_rounded),
                    onPressed: () => _enterReorderMode(songs),
                  ),
                if (playlist.isSmart)
                  IconButton(
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    icon: Icon(Icons.edit_rounded, color: p.accent),
                    tooltip: context.l10n.edit,
                    onPressed: () => context.push('/smart-playlist-builder',
                        extra: playlist),
                  )
                else
                  IconButton(
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    tooltip: context.l10n.manageSongs,
                    icon:
                        Icon(Icons.playlist_add_check_rounded, color: p.accent),
                    onPressed: () =>
                        context.push('/playlist/manage', extra: playlist),
                  ),
              ],
              if (!_isReordering)
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
                        final messenger = ScaffoldMessenger.of(context);
                        final undoLabel = context.l10n.undo;
                        final plName = playlist.name;
                        final isSmart = playlist.isSmart;
                        final smartCriteria = playlist.smartCriteria;
                        final songIds = songs.map((s) => s.id).toList();
                        final deletedMessage =
                            context.l10n.playlistDeleted(plName);
                        final confirmed =
                            await PulsrDialogHelper.showConfirmDialog(
                          context,
                          title: context.l10n.deletePlaylist,
                          message: context.l10n.deletePlaylistPrompt,
                          icon: Icons.delete_outline_rounded,
                          confirmLabel: context.l10n.delete,
                          isDestructive: true,
                        );
                        if (confirmed != true || !context.mounted) break;
                        final result =
                            await playlistUseCases.deletePlaylist(playlist.id);
                        if (result.isLeft()) {
                          if (context.mounted) {
                            messenger.showSnackBar(SnackBar(
                              content: Text(result.fold(
                                  (failure) => failure.message,
                                  (_) => context.l10n.somethingWentWrong)),
                            ));
                          }
                          break;
                        }
                        // Embedded two-pane mode has no route of its own: popping
                        // here would tear down the enclosing /playlists shell.
                        if (!widget.isEmbedded && context.mounted) {
                          Navigator.pop(context);
                        }
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(deletedMessage),
                            action: SnackBarAction(
                              label: undoLabel,
                              onPressed: () async {
                                final res =
                                    await playlistUseCases.createPlaylist(
                                  plName,
                                  isSmart: isSmart,
                                  smartCriteria: smartCriteria,
                                );
                                if (!isSmart && songIds.isNotEmpty) {
                                  final newId = res.getOrElse((_) => -1);
                                  if (newId > 0) {
                                    await playlistUseCases.addSongsToPlaylist(
                                        newId, songIds);
                                  }
                                }
                              },
                            ),
                          ),
                        );
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
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(child: Text(context.l10n.manageSongs)),
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
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                                child: Text(context.l10n.downloadAllTracks)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.file_upload_outlined,
                              color: p.accent, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(child: Text(context.l10n.exportM3u)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, color: p.accent, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(child: Text(context.l10n.sharePlaylist)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: p.error, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(context.l10n.deletePlaylist,
                                style: TextStyle(color: p.error)),
                          ),
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
              child: AsyncStateBuilder<_PlaylistSongsResult>(
                snapshot: snapshot,
                loadingWidget: const SkeletonList(
                    padding: EdgeInsets.only(top: AppSpacing.xs)),
                emptyWidget: noTracksState,
                onError: (_) => noTracksState,
                isEmpty: (data) => data.error == null && data.songs.isEmpty,
                onData: (data) {
                  if (data.error != null) {
                    return PulsrEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: context.l10n.playlistLoadFailed,
                      subtitle: data.error!,
                      primaryActionLabel: context.l10n.retry,
                      onPrimaryAction: _retryLoad,
                    );
                  }
                  if (_isReordering) {
                    return _buildReorderContent(context, p);
                  }
                  final normalizedQuery = _searchQuery.trim().isEmpty
                      ? null
                      : SearchAlgorithmUtils.normalize(_searchQuery);
                  final visibleSongs = normalizedQuery == null
                      ? songs
                      : songs
                          .where((s) =>
                              SearchAlgorithmUtils.normalize(s.title)
                                  .contains(normalizedQuery) ||
                              SearchAlgorithmUtils.normalize(s.artist)
                                  .contains(normalizedQuery))
                          .toList();
                  return ListView.builder(
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: EdgeInsets.only(
                        bottom: PulsrLayoutMetrics.scrollBottom(context)),
                    itemCount:
                        visibleSongs.isEmpty ? 3 : visibleSongs.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: Adaptive.pagePadding(context),
                              vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: p.accent,
                                    foregroundColor: p.onAccent,
                                  ),
                                  onPressed: () {
                                    context
                                        .read<PlayerCubit>()
                                        .playSong(songs.first, queue: songs);
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: Text(context.l10n.playAll),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
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
                                const SizedBox(width: AppSpacing.xs),
                                IconButton.filledTonal(
                                  constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget),
                                  onPressed: () =>
                                      _downloadPlaylist(context, songs),
                                  icon: const Icon(Icons.download_rounded,
                                      size: 20),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        p.accent.withValues(alpha: 0.15),
                                    foregroundColor: p.accent,
                                  ),
                                  tooltip: context
                                      .l10n.browseDownloadAllOfflineActive,
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      if (index == 1) {
                        return Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            Adaptive.pagePadding(context),
                            0,
                            Adaptive.pagePadding(context),
                            AppSpacing.xs,
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val),
                            decoration: InputDecoration(
                              hintText: context.l10n.browseSearchWithinPlaylist,
                              prefixIcon:
                                  const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget),
                                      icon: const Icon(Icons.clear_rounded,
                                          size: 18),
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
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.s10),
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
                        );
                      }

                      if (visibleSongs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s40),
                          child: Center(
                            child: Text(
                              '${context.l10n.browseNoSongsMatch} "$_searchQuery"',
                              style: TextStyle(
                                  color: p.textTertiary,
                                  fontSize: AppFontSize.body),
                            ),
                          ),
                        );
                      }

                      final i = index - 2;
                      final song = visibleSongs[i];
                      return SongTile(
                        song: song,
                        index: i,
                        subtitleOverride: '${song.artist} • ${song.album}',
                        onTap: () => context
                            .read<PlayerCubit>()
                            .playSong(song, queue: visibleSongs),
                        onMorePressed: () => SongOptionsSheet.show(
                          context,
                          song: song,
                          playlist: playlist,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (AppConfig.ytmEnabled &&
                                song.remoteId != null &&
                                song.remoteId!.isNotEmpty)
                              YtmDownloadButton(song: song),
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              tooltip: context.l10n.favorite,
                              icon: Icon(
                                song.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: song.isFavorite
                                    ? p.favorite
                                    : p.textTertiary,
                                size: 20,
                              ),
                              onPressed: () {
                                try {
                                  context
                                      .read<LibraryCubit>()
                                      .toggleFavorite(song.id);
                                } on ProviderNotFoundException {
                                  getIt<ToggleFavoriteUseCase>()(song.id);
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
        return widget.isEmbedded
            ? scaffold
            : PulsrPagePopScope(child: scaffold);
      },
    );
  }
}
