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

class AddToPlaylistSheet extends StatelessWidget {
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

  List<SongsTableData> get _allSongs =>
      songs != null && songs!.length > 1 ? songs! : [song];

  PlaylistUseCases get _useCases =>
      playlistUseCases ?? getIt<PlaylistUseCases>();

  void _showNewPlaylistDialog(BuildContext context) async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.createPlaylist,
      hintText: context.l10n.enterPlaylistName,
      icon: Icons.playlist_add_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );

    if (name != null && name.isNotEmpty && context.mounted) {
      final result = await _useCases.createPlaylist(name);
      result.fold(
        (failure) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(failure.message)),
            );
          }
        },
        (id) async {
          if (_allSongs.length == 1) {
            await _useCases.addSongToPlaylist(id, song.id);
          } else {
            await _useCases.addSongsToPlaylist(
                id, _allSongs.map((s) => s.id).toList());
          }
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _allSongs.length == 1
                      ? '${song.title}: ${context.l10n.addedToPlaylist} ($name)'
                      : '${context.l10n.addedToPlaylist} (${_allSongs.length}): $name',
                ),
              ),
            );
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return PulsrBottomSheetContainer(
      title: Text(context.l10n.addToPlaylist),
      trailing: PulsrPressable(
        onTap: () => _showNewPlaylistDialog(context),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: p.accentContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.add_rounded, color: p.accent, size: 20),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.65),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: StreamBuilder(
            stream: _useCases.watchPlaylists(),
            builder: (context, snapshot) {
              final playlists = snapshot.data
                      ?.fold((l) => <PlaylistsTableData>[], (r) => r)
                      .where((p) => !p.isSmart)
                      .toList() ??
                  [];
              if (playlists.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.queue_music_rounded,
                            size: 48, color: p.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.emptyPlaylists,
                          style: TextStyle(
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
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
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return PulsrPressable(
                    pressedScale: 0.98,
                    onTap: () async {
                      if (_allSongs.length == 1) {
                        await _useCases.addSongToPlaylist(
                            playlist.id, song.id);
                      } else {
                        await _useCases.addSongsToPlaylist(playlist.id,
                            _allSongs.map((s) => s.id).toList());
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(_allSongs.length == 1
                                  ? '${context.l10n.browseAdded} ${playlist.name}'
                                  : '${context.l10n.browseAdded} ${_allSongs.length} ${context.l10n.browseTracksTo} ${playlist.name}')),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accentContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.queue_music_rounded,
                                color: p.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              playlist.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
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
    );
  }
}
