// lib/features/sheets/add_to_playlist_sheet.dart
import 'package:flutter/material.dart';
import '../../core/di/injection.dart';
import '../../core/errors/failures.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/async_state_builder.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../data/db/app_database.dart';
import '../../domain/usecases/playlist_usecases.dart';

import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

// FIX-M9: Convert to StatefulWidget with in-flight progress indicator during playlist mutations
class AddToPlaylistSheet extends StatefulWidget {
  final SongsTableData song;
  final List<SongsTableData>? songs;
  final PlaylistUseCases? playlistUseCases;

  const AddToPlaylistSheet({
    super.key,
    required this.song,
    this.songs,
    this.playlistUseCases,
  });

  static Future<void> show(
    BuildContext context, {
    required SongsTableData song,
    List<SongsTableData>? songs,
  }) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => AddToPlaylistSheet(song: song, songs: songs),
    );
  }

  @visibleForTesting
  static Set<int> get activePlaylistMutations =>
      _AddToPlaylistSheetState._activePlaylistMutations;

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  static final Set<int> _activePlaylistMutations = <int>{};
  bool _isMutating = false;

  List<SongsTableData> get _allSongs =>
      widget.songs != null && widget.songs!.length > 1
          ? widget.songs!
          : [widget.song];

  PlaylistUseCases get _useCases =>
      widget.playlistUseCases ?? getIt<PlaylistUseCases>();

  Stream<Result<List<PlaylistsTableData>>>? _playlistsStream;

  /// Resolves every song to a persisted `songs.id`. Online search results have
  /// no row yet and stale local objects may point at an id a rescan replaced;
  /// both would trip the playlist_entries foreign key otherwise. Returns null
  /// after surfacing the failure.
  Future<List<int>?> _resolvePersistedSongIds() async {
    final ids = <int>[];
    for (final song in _allSongs) {
      final result = await _useCases.ensureSongPersisted(song);
      final failure = result.fold<AppFailure?>((f) => f, (_) => null);
      if (failure != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          );
        }
        return null;
      }
      ids.add(result.getOrElse((_) => song.id));
    }
    return ids;
  }

  void _showNewPlaylistDialog(BuildContext context) async {
    if (_isMutating) return;
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.createPlaylist,
      hintText: context.l10n.enterPlaylistName,
      icon: Icons.playlist_add_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );

    if (name != null && name.isNotEmpty && context.mounted) {
      setState(() => _isMutating = true);
      try {
        // Resolve before creating so a failure cannot leave an empty playlist.
        final songIds = await _resolvePersistedSongIds();
        if (songIds == null || !context.mounted) return;
        final result = await _useCases.createPlaylist(name);
        if (!context.mounted) return;
        final createdId = result.fold((failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          );
          return null;
        }, (id) => id);
        if (createdId == null) return;
        if (_activePlaylistMutations.contains(createdId)) return;
        _activePlaylistMutations.add(createdId);
        try {
          // Await the insert inside the try so `_isMutating` is not cleared before
          // the write completes (the previous async `fold` callback was dropped).
          final insertResult = songIds.length == 1
              ? await _useCases.addSongToPlaylist(createdId, songIds.single)
              : await _useCases.addSongsToPlaylist(createdId, songIds);
          if (!context.mounted) return;
          final insertFailure =
              insertResult.fold<String?>((f) => f.message, (_) => null);
          if (insertFailure != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(insertFailure)),
            );
            return;
          }
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _allSongs.length == 1
                      ? '${widget.song.title}: ${context.l10n.addedToPlaylist} ($name)'
                      : '${context.l10n.addedToPlaylist} (${_allSongs.length}): $name',
                ),
              ),
            );
          }
        } finally {
          _activePlaylistMutations.remove(createdId);
        }
      } finally {
        if (mounted) setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _addToExistingPlaylist(
      BuildContext context, PlaylistsTableData playlist) async {
    if (_isMutating || _activePlaylistMutations.contains(playlist.id)) return;
    _activePlaylistMutations.add(playlist.id);
    setState(() => _isMutating = true);
    try {
      final songIds = await _resolvePersistedSongIds();
      if (songIds == null) return;
      final insertResult = songIds.length == 1
          ? await _useCases.addSongToPlaylist(playlist.id, songIds.single)
          : await _useCases.addSongsToPlaylist(playlist.id, songIds);
      if (!context.mounted) return;
      final insertFailure =
          insertResult.fold<String?>((f) => f.message, (_) => null);
      if (insertFailure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(insertFailure)),
        );
        return;
      }
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_allSongs.length == 1
                ? '${context.l10n.browseAdded} ${playlist.name}'
                : '${context.l10n.browseAdded} ${_allSongs.length} ${context.l10n.browseTracksTo} ${playlist.name}'),
          ),
        );
      }
    } finally {
      _activePlaylistMutations.remove(playlist.id);
      if (mounted) setState(() => _isMutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.sizeOf(context).height;

    final subtitleText = _allSongs.length > 1
        ? context.l10n.songsCount(_allSongs.length)
        : '${widget.song.title} • ${widget.song.artist}';

    return PulsrBottomSheetContainer(
      title: Text(context.l10n.addToPlaylist),
      subtitle: Text(
        subtitleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _isMutating
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: p.accent,
              ),
            )
          : Semantics(
              button: true,
              label: context.l10n.createPlaylist,
              child: PulsrPressable(
                onTap: () => _showNewPlaylistDialog(context),
                child: Tooltip(
                  message: context.l10n.createPlaylist,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accentContainer,
                      borderRadius: AppRadii.r12All,
                      border: Border.all(
                        color: p.accent.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Icon(Icons.add_rounded, color: p.accent, size: 22),
                  ),
                ),
              ),
            ),
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: _isMutating,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 140,
                maxHeight: screenHeight * 0.65,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20,
                    AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
                child: StreamBuilder(
                  stream: _playlistsStream ??= _useCases.watchPlaylists(),
                  builder: (context, snapshot) {
                    Widget buildError() => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xl),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 48, color: p.error),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  context.l10n.somethingWentWrong,
                                  style: TextStyle(
                                      color: p.textSecondary,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextButton.icon(
                                  onPressed: () => setState(() {}),
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: Text(context.l10n.retry),
                                ),
                              ],
                            ),
                          ),
                        );

                    Widget buildEmpty() => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xl),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Icon(Icons.queue_music_rounded,
                                      size: 30, color: p.accent),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  context.l10n.emptyPlaylists,
                                  style: TextStyle(
                                      color: p.textSecondary,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                FilledButton.icon(
                                  onPressed: () =>
                                      _showNewPlaylistDialog(context),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: Text(context.l10n.createPlaylist),
                                ),
                              ],
                            ),
                          ),
                        );

                    return AsyncStateBuilder(
                      snapshot: snapshot,
                      // Avoid flashing the empty state during the initial
                      // subscription.
                      loadingWidget: const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: SizedBox(
                            width: AppSpacing.lg,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      ),
                      onError: (_) => buildError(),
                      emptyWidget: buildEmpty(),
                      isEmpty: (result) => result.fold(
                        (_) => false,
                        (playlists) =>
                            playlists.where((p) => !p.isSmart).isEmpty,
                      ),
                      onData: (result) => result.fold(
                        (_) => buildError(),
                        (rawPlaylists) {
                          final playlists =
                              rawPlaylists.where((p) => !p.isSmart).toList();
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final useTwoColumns =
                                  constraints.maxWidth >= 460 &&
                                      playlists.length >= 4;
                              if (useTwoColumns) {
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisExtent: 60,
                                    crossAxisSpacing: AppSpacing.xs,
                                    mainAxisSpacing: AppSpacing.xs,
                                  ),
                                  itemCount: playlists.length,
                                  itemBuilder: (context, index) =>
                                      _buildPlaylistCard(
                                          context, p, playlists[index]),
                                );
                              }

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int index = 0;
                                      index < playlists.length;
                                      index++) ...[
                                    if (index > 0)
                                      const SizedBox(height: AppSpacing.xs),
                                    _buildPlaylistCard(
                                        context, p, playlists[index]),
                                  ],
                                ],
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (_isMutating)
            Positioned.fill(
              child: Container(
                color: AppColors.scrimAt(0.25),
                // No cancel affordance: the playlist write cannot be aborted
                // once started, so offering "Cancel" only produced a silent
                // success. The sheet reports the real outcome and closes.
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: p.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    PulsrPalette p,
    PlaylistsTableData playlist,
  ) {
    return Semantics(
      button: true,
      label: '${context.l10n.addToPlaylist}: ${playlist.name}',
      child: PulsrPressable(
        pressedScale: 0.98,
        onTap: () => _addToExistingPlaylist(context, playlist),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: p.surfaceContainer.withValues(alpha: 0.72),
            borderRadius: AppRadii.r16All,
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accentContainer,
                  borderRadius: AppRadii.r10All,
                ),
                child: Icon(Icons.queue_music_rounded,
                    color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.body,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, color: p.accent, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
