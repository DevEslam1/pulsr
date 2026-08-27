import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p_path;
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';

class FolderTreeBrowserTab extends StatefulWidget {
  const FolderTreeBrowserTab({super.key});

  @override
  State<FolderTreeBrowserTab> createState() => _FolderTreeBrowserTabState();
}

class _FolderTreeBrowserTabState extends State<FolderTreeBrowserTab> {
  String? _currentPath;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final songs = state.songs;
        if (songs.isEmpty) {
          return Center(
            child: Text(
              'No music files indexed',
              style: TextStyle(color: p.textSecondary),
            ),
          );
        }

        // Determine all unique folders
        final folders = <String>{};
        for (final song in songs) {
          if (!song.path.startsWith('ytmusic://') && !song.path.startsWith('content://')) {
            final dir = p_path.dirname(song.path);
            if (dir.isNotEmpty && dir != '.') folders.add(dir);
          }
        }

        // Initialize root if null
        if (_currentPath == null && folders.isNotEmpty) {
          _currentPath = folders.first;
        }

        final currentDir = _currentPath ?? '';
        final childSongs = songs.where((s) => p_path.dirname(s.path) == currentDir).toList();
        final childFolders = folders.where((f) => f != currentDir && f.startsWith(currentDir)).toList();

        // Breadcrumb parts
        final breadcrumbs = p_path.split(currentDir);

        return Column(
          children: [
            // Breadcrumbs bar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: p.surfaceContainer.withValues(alpha: 0.4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: breadcrumbs.length,
                separatorBuilder: (_, __) => Icon(Icons.chevron_right_rounded, size: 18, color: p.textSecondary),
                itemBuilder: (context, index) {
                  final crumbPath = p_path.joinAll(breadcrumbs.take(index + 1));
                  final isLast = index == breadcrumbs.length - 1;

                  return Center(
                    child: InkWell(
                      onTap: isLast ? null : () => setState(() => _currentPath = crumbPath),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          breadcrumbs[index],
                          style: TextStyle(
                            color: isLast ? p.primary : p.textSecondary,
                            fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Content list (sub-folders + files)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  // Parent folder button
                  if (breadcrumbs.length > 1) ...[
                    ListTile(
                      leading: Icon(Icons.arrow_upward_rounded, color: p.primary),
                      title: Text('Parent Directory', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600)),
                      onTap: () {
                        setState(() {
                          _currentPath = p_path.dirname(currentDir);
                        });
                      },
                    ),
                    Divider(color: p.hairline),
                  ],

                  // Subfolders
                  for (final sub in childFolders.take(15)) ...[
                    ListTile(
                      leading: Icon(Icons.folder_rounded, color: p.primary),
                      title: Text(
                        p_path.basename(sub),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
                      onTap: () => setState(() => _currentPath = sub),
                    ),
                  ],

                  // Songs in current folder
                  for (int i = 0; i < childSongs.length; i++) ...[
                    SongTile(
                      song: childSongs[i],
                      onTap: () {
                        context.read<PlayerCubit>().playSong(childSongs[i], queue: childSongs);
                      },
                    ),
                  ],

                  if (childFolders.isEmpty && childSongs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Center(
                        child: Text('Folder is empty', style: TextStyle(color: p.textSecondary)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
