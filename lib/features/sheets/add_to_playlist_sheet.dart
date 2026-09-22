// lib/features/sheets/add_to_playlist_sheet.dart
import 'package:flutter/material.dart';
import '../../core/di/injection.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../data/db/app_database.dart';
import '../../domain/usecases/playlist_usecases.dart';

import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
      builder: (_) => AddToPlaylistSheet(song: song, songs: songs),
    );
  }

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  bool _isMutating = false;

  List<SongsTableData> get _allSongs =>
      widget.songs != null && widget.songs!.length > 1
          ? widget.songs!
          : [widget.song];

  PlaylistUseCases get _useCases =>
      widget.playlistUseCases ?? getIt<PlaylistUseCases>();

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
        final result = await _useCases.createPlaylist(name);
        if (!context.mounted) return;
        final createdId = result.fold((failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          );
          return null;
        }, (id) => id);
        if (createdId == null) return;
        // Await the insert inside the try so `_isMutating` is not cleared before
        // the write completes (the previous async `fold` callback was dropped).
        if (_allSongs.length == 1) {
          await _useCases.addSongToPlaylist(createdId, widget.song.id);
        } else {
          await _useCases.addSongsToPlaylist(
              createdId, _allSongs.map((s) => s.id).toList());
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
        if (mounted) setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _addToExistingPlaylist(
      BuildContext context, PlaylistsTableData playlist) async {
    if (_isMutating) return;
    setState(() => _isMutating = true);
    try {
      if (_allSongs.length == 1) {
        await _useCases.addSongToPlaylist(playlist.id, widget.song.id);
      } else {
        await _useCases.addSongsToPlaylist(
            playlist.id, _allSongs.map((s) => s.id).toList());
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
      if (mounted) setState(() => _isMutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return PulsrBottomSheetContainer(
      title: Text(context.l10n.addToPlaylist),
      trailing: _isMutating
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: p.accent,
              ),
            )
          : PulsrPressable(
              onTap: () => _showNewPlaylistDialog(context),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accentContainer,
                  borderRadius: BorderRadius.circular(AppRadii.r10),
                ),
                child: Icon(Icons.add_rounded, color: p.accent, size: 20),
              ),
            ),
      child: IgnorePointer(
        ignoring: _isMutating,
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenHeight * 0.65),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
                child: StreamBuilder(
                  stream: _useCases.watchPlaylists(),
                  builder: (context, snapshot) {
                    // Avoid flashing the empty state during the initial subscription.
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: SizedBox(
                            width: AppSpacing.lg,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      );
                    }
                    final playlists = snapshot.data
                            ?.fold((l) => <PlaylistsTableData>[], (r) => r)
                            .where((p) => !p.isSmart)
                            .toList() ??
                        [];
                    if (playlists.isEmpty) {
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.queue_music_rounded,
                                  size: 48, color: p.textTertiary),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                context.l10n.emptyPlaylists,
                                style: TextStyle(
                                    color: p.textSecondary,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FilledButton.icon(
                                onPressed: () => _showNewPlaylistDialog(context),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(context.l10n.createPlaylist),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.s6),
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return PulsrPressable(
                          pressedScale: 0.98,
                          onTap: () => _addToExistingPlaylist(context, playlist),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s14,
                                vertical: AppSpacing.s10),
                            decoration: BoxDecoration(
                              color: p.surfaceContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(AppRadii.r14),
                              border: Border.all(color: p.hairline),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.xs),
                                  decoration: BoxDecoration(
                                    color: p.accentContainer,
                                    borderRadius:
                                        BorderRadius.circular(AppRadii.r10),
                                  ),
                                  child: Icon(Icons.queue_music_rounded,
                                      color: p.accent, size: 20),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    playlist.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(Icons.add_circle_outline_rounded,
                                    color: p.accent, size: 22),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (_isMutating)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: p.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
