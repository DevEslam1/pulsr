// lib/features/sheets/add_to_playlist_sheet.dart
import 'package:flutter/material.dart';
import '../../core/di/injection.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/adaptive.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../data/db/app_database.dart';
import '../../domain/usecases/playlist_usecases.dart';

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

  List<SongsTableData> get _allSongs => songs != null && songs!.length > 1 ? songs! : [song];

  PlaylistUseCases get _useCases =>
      playlistUseCases ?? getIt<PlaylistUseCases>();

  void _showNewPlaylistDialog(BuildContext context) {
    final p = context.palette;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(context.l10n.createPlaylist,
            style:
                TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: context.l10n.enterPlaylistName,
            filled: true,
            fillColor: p.surfaceContainer,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel,
                style: TextStyle(color: p.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
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
                      await _useCases.addSongsToPlaylist(id, _allSongs.map((s) => s.id).toList());
                    }
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.addedTo(name))),
                      );
                    }
                  },
                );
              }
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap:
              () {}, // Prevent taps on the sheet from bubbling to the dismiss detector
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Adaptive.maxSheetWidth,
              maxHeight: screenHeight * 0.75,
            ),
            child: Material(
              color: p.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.hairline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.l10n.addToPlaylist,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: p.textPrimary,
                                ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_rounded, color: p.accent),
                            onPressed: () => _showNewPlaylistDialog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder(
                        stream: _useCases.watchPlaylists(),
                        builder: (context, snapshot) {
                          final playlists = snapshot.data?.fold(
                                  (l) => <PlaylistsTableData>[], (r) => r) ??
                              [];
                          if (playlists.isEmpty) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    Text(
                                      context.l10n.emptyPlaylists,
                                      style: TextStyle(color: p.textSecondary),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _showNewPlaylistDialog(context),
                                      icon: const Icon(Icons.add_rounded),
                                      label: Text(context.l10n.createPlaylist),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: playlists.length,
                            itemBuilder: (context, index) {
                              final playlist = playlists[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainer,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Icon(Icons.queue_music_rounded,
                                      color: p.accent, size: 20),
                                ),
                                title: Text(playlist.name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: p.textPrimary)),
                                trailing: Icon(Icons.add_circle_outline_rounded,
                                    color: p.accent),
                                onTap: () async {
                                  if (_allSongs.length == 1) {
                                    await _useCases.addSongToPlaylist(playlist.id, song.id);
                                  } else {
                                    await _useCases.addSongsToPlaylist(playlist.id, _allSongs.map((s) => s.id).toList());
                                  }
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(_allSongs.length == 1 ? 'Added to ${playlist.name}' : 'Added ${_allSongs.length} tracks to ${playlist.name}')),
                                    );
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
