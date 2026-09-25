import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p_path;
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/folder_usecases.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class FolderTreeBrowserTab extends StatefulWidget {
  const FolderTreeBrowserTab({super.key});

  @override
  State<FolderTreeBrowserTab> createState() => _FolderTreeBrowserTabState();
}

class _FolderTreeBrowserTabState extends State<FolderTreeBrowserTab> {
  String? _currentPath;
  final ScrollController _breadcrumbController = ScrollController();

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbController.hasClients) {
        _breadcrumbController.animateTo(
          _breadcrumbController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final songs = context.read<LibraryCubit>().state.songs;
    final folders = _extractFolders(songs);
    _currentPath = _findRootFolder(folders);
  }

  Set<String> _extractFolders(List<SongsTableData> songs) {
    final folders = <String>{};
    for (final song in songs) {
      if (!song.path.startsWith('ytmusic://') &&
          !song.path.startsWith('content://')) {
        final normalized = p_path.posix.normalize(song.path.replaceAll('\\', '/'));
        final dir = p_path.posix.dirname(normalized);
        if (dir.isNotEmpty && dir != '.') folders.add(dir);
      }
    }
    return folders;
  }

  String? _findRootFolder(Set<String> folders) {
    if (folders.isEmpty) return null;
    final sorted = folders.toList()
      ..sort((a, b) {
        final depthA = a.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).length;
        final depthB = b.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).length;
        if (depthA != depthB) return depthA.compareTo(depthB);
        return a.length.compareTo(b.length);
      });
    return sorted.first;
  }

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocConsumer<LibraryCubit, LibraryState>(
      listener: (context, state) {
        // M-09: Reconcile folder path asynchronously via listener instead of mutating state during build()
        final folders = _extractFolders(state.songs);
        if (_currentPath != null && !folders.contains(_currentPath)) {
          setState(() {
            _currentPath = _findRootFolder(folders);
          });
        } else if (_currentPath == null && folders.isNotEmpty) {
          setState(() {
            _currentPath = _findRootFolder(folders);
          });
        }
      },
      builder: (context, state) {
        final songs = state.songs;
        if (songs.isEmpty) {
          return Center(
            child: Text(context.l10n.noMusicIndexed,
              style: TextStyle(color: p.textSecondary),
            ),
          );
        }

        final folders = _extractFolders(songs);
        final effectivePath = _currentPath ?? _findRootFolder(folders) ?? '';
        final currentDir = p_path.posix.normalize(effectivePath.replaceAll('\\', '/'));
        final dirPrefix = currentDir.endsWith('/') ? currentDir : '$currentDir/';
        final childSongs = songs.where((s) {
          final dir = p_path.posix.dirname(
            p_path.posix.normalize(s.path.replaceAll('\\', '/')),
          );
          return dir == currentDir;
        }).toList();
        final childFolders = folders
            .where((f) {
              final normF = p_path.posix.normalize(f.replaceAll('\\', '/'));
              return normF != currentDir && normF.startsWith(dirPrefix);
            })
            .toList()
          ..sort();

        FolderItem? folderItemFor(String path) {
          final normalized = p_path.posix.normalize(path.replaceAll('\\', '/')).toLowerCase();
          for (final f in state.folders) {
            if (p_path.posix.normalize(f.path.replaceAll('\\', '/')).toLowerCase() == normalized) {
              return f;
            }
          }
          return null;
        }

        // Breadcrumb parts (posix: MediaStore paths are always /-separated).
        final breadcrumbs = p_path.posix.split(currentDir);

        return Column(
          children: [
            // Breadcrumbs bar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              color: p.surfaceContainer.withValues(alpha: 0.4),
              child: ListView.separated(
                controller: _breadcrumbController,
                scrollDirection: Axis.horizontal,
                itemCount: breadcrumbs.length,
                separatorBuilder: (_, __) => Icon(Icons.chevron_right_rounded,
                    size: 18, color: p.textSecondary),
                itemBuilder: (context, index) {
                  final crumbPath = p_path.posix
                      .joinAll(breadcrumbs.take(index + 1));
                  final isLast = index == breadcrumbs.length - 1;

                  return Center(
                    child: InkWell(
                      onTap: isLast
                          ? null
                          : () => _navigateTo(crumbPath),
                      borderRadius: BorderRadius.circular(AppRadii.r8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s6, vertical: AppSpacing.xxs),
                        child: Text(
                          breadcrumbs[index],
                          style: TextStyle(
                            color: isLast ? p.primary : p.textSecondary,
                            fontWeight:
                                isLast ? FontWeight.w700 : FontWeight.normal,
                            fontSize: AppFontSize.bodySmall,
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
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 120),
                children: [
                  // Parent folder button
                  if (breadcrumbs.length > 1) ...[
                    ListTile(
                      leading:
                          Icon(Icons.arrow_upward_rounded, color: p.primary),
                      title: Text(context.l10n.parentDirectory,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600)),
                      onTap: () {
                        _navigateTo(p_path.posix.dirname(currentDir));
                      },
                    ),
                    Divider(color: p.hairline),
                  ],

                  // Subfolders (all of them — ListView virtualizes, no cap).
                  for (final sub in childFolders) ...[
                    ListTile(
                      leading: Icon(Icons.folder_rounded, color: p.primary),
                      title: Text(
                        p_path.posix.basename(sub),
                        style: TextStyle(
                            color: p.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (folderItemFor(sub) != null)
                            IconButton(
                              icon: Icon(Icons.open_in_new_rounded,
                                  color: p.textSecondary, size: 18),
                              tooltip: context.l10n.browseOpenFolderDetails,
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              onPressed: () {
                                final item = folderItemFor(sub);
                                if (item != null) {
                                  context.push('/folder', extra: item);
                                }
                              },
                            ),
                          Icon(Icons.chevron_right_rounded,
                              color: p.textSecondary),
                        ],
                      ),
                      onTap: () => _navigateTo(sub),
                    ),
                  ],

                  // Songs in current folder
                  for (int i = 0; i < childSongs.length; i++) ...[
                    SongTile(
                      song: childSongs[i],
                      onTap: () {
                        context
                            .read<PlayerCubit>()
                            .playSong(childSongs[i], queue: childSongs);
                      },
                    ),
                  ],

                  if (childFolders.isEmpty && childSongs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: Text(context.l10n.folderEmpty,
                            style: TextStyle(color: p.textSecondary)),
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
