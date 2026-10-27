import 'package:flutter/material.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p_path;
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/folder_usecases.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../cubit/library_cubit.dart';
import '../../cubit/library_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';

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
          duration: PulsrMotion.standard,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final state = context.read<LibraryCubit>().state;
    _rootInitializedFromFolders = state.folders.isNotEmpty;
    _currentPath = _findRootFolder(_rootCandidates(state)) ??
        _findRootFolder(_getFolders(state));
  }

  bool _rootInitializedFromFolders = false;

  List<FolderItem>? _cachedFoldersRef;
  Set<String>? _cachedFolders;
  List<SongsTableData>? _cachedSongsRef;

  /// The tree is built from the full repository folder hierarchy
  /// ([LibraryState.folders]) plus every ancestor directory, not from the
  /// paginated songs window. The songs fallback only covers the brief window
  /// before the hierarchy query completes (or a repository failure).
  Set<String> _getFolders(LibraryState state) {
    final source = state.folders;
    if (source.isNotEmpty) {
      if (identical(_cachedFoldersRef, source) && _cachedFolders != null) {
        return _cachedFolders!;
      }
      _cachedFoldersRef = source;
      _cachedFolders = _extractFoldersFromItems(source);
      return _cachedFolders!;
    }
    final songs = state.songs;
    if (identical(_cachedSongsRef, songs) && _cachedFolders != null) {
      return _cachedFolders!;
    }
    _cachedSongsRef = songs;
    _cachedFolders = _extractFolders(songs);
    return _cachedFolders!;
  }

  /// Song-bearing folders from the full hierarchy plus their ancestors, so
  /// intermediate directories still render as navigable tiles.
  Set<String> _extractFoldersFromItems(List<FolderItem> folders) {
    final result = <String>{};
    for (final item in folders) {
      var dir = p_path.posix.normalize(item.path.replaceAll('\\', '/'));
      while (dir.isNotEmpty && dir != '.' && dir != '/') {
        result.add(dir);
        final parent = p_path.posix.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    return result;
  }

  Set<String> _extractFolders(List<SongsTableData> songs) {
    final folders = <String>{};
    for (final song in songs) {
      if (!song.path.startsWith('ytmusic://') &&
          !song.path.startsWith('content://')) {
        final normalized =
            p_path.posix.normalize(song.path.replaceAll('\\', '/'));
        final dir = p_path.posix.dirname(normalized);
        if (dir.isNotEmpty && dir != '.') folders.add(dir);
      }
    }
    return folders;
  }

  /// Root candidates are folders that actually contain songs (from the full
  /// hierarchy), so a common ancestor such as `/storage/emulated/0` is not
  /// promoted to the root. Falls back to all extracted dirs when the hierarchy
  /// has not loaded yet.
  Set<String> _rootCandidates(LibraryState state) {
    if (state.folders.isEmpty) return _getFolders(state);
    return state.folders
        .map((f) => p_path.posix.normalize(f.path.replaceAll('\\', '/')))
        .where((f) => f.isNotEmpty && f != '.' && f != '/')
        .toSet();
  }

  String? _findRootFolder(Set<String> folders) {
    if (folders.isEmpty) return null;
    final sorted = folders.toList()
      ..sort((a, b) {
        final depthA =
            a.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).length;
        final depthB =
            b.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).length;
        if (depthA != depthB) return depthA.compareTo(depthB);
        return a.length.compareTo(b.length);
      });
    return sorted.first;
  }

  Map<String, FolderItem> _representativeByDir(List<FolderItem> folders) {
    final map = <String, FolderItem>{};
    for (final item in folders) {
      var dir = p_path.posix.normalize(item.path.replaceAll('\\', '/'));
      while (dir.isNotEmpty && dir != '.' && dir != '/') {
        map.putIfAbsent(dir, () => item);
        final parent = p_path.posix.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    return map;
  }

  // One subscription per visited folder; rebuilding for theme/selection must
  // not resubscribe to the database watch.
  String? _songsStreamPath;
  Stream<Result<List<SongsTableData>>>? _songsStream;

  Stream<Result<List<SongsTableData>>> _folderSongsStream(
      LibraryCubit cubit, String path) {
    if (_songsStreamPath == path && _songsStream != null) {
      return _songsStream!;
    }
    _songsStreamPath = path;
    _songsStream = cubit.watchFolderSongs(path);
    return _songsStream!;
  }

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<LibraryCubit>();

    return BlocConsumer<LibraryCubit, LibraryState>(
      listener: (context, state) {
        // The hierarchy usually arrives after the songs stream. When it does,
        // snap the initial root to a song-bearing folder instead of leaving the
        // tree parked on a shared ancestor such as /storage/emulated/0.
        if (!_rootInitializedFromFolders && state.folders.isNotEmpty) {
          _rootInitializedFromFolders = true;
          final preferred = _findRootFolder(_rootCandidates(state));
          if (preferred != null) {
            setState(() => _currentPath = preferred);
            return;
          }
        }
        // Reconcile folder path asynchronously via listener instead of
        // mutating state during build().
        final folders = _getFolders(state);
        if (_currentPath != null && !folders.contains(_currentPath)) {
          setState(() {
            _currentPath = _findRootFolder(_rootCandidates(state));
          });
        } else if (_currentPath == null && folders.isNotEmpty) {
          setState(() {
            _currentPath = _findRootFolder(_rootCandidates(state));
          });
        }
      },
      builder: (context, state) {
        final folders = _getFolders(state);
        if (folders.isEmpty) {
          return Center(
            child: Text(
              context.l10n.noMusicIndexed,
              style: TextStyle(color: p.textSecondary),
            ),
          );
        }

        final representatives = _representativeByDir(state.folders);
        final effectivePath = _currentPath ??
            _findRootFolder(_rootCandidates(state)) ??
            _findRootFolder(folders) ??
            '';
        final currentDir =
            p_path.posix.normalize(effectivePath.replaceAll('\\', '/'));
        final dirPrefix =
            currentDir.endsWith('/') ? currentDir : '$currentDir/';
        final childFolders = folders.where((f) {
          final normF = p_path.posix.normalize(f.replaceAll('\\', '/'));
          return normF != currentDir && normF.startsWith(dirPrefix);
        }).toList()
          ..sort();

        // Breadcrumb parts (posix: MediaStore paths are always /-separated).
        final breadcrumbs = p_path.posix.split(currentDir);

        return StreamBuilder<Result<List<SongsTableData>>>(
          stream: _folderSongsStream(cubit, currentDir),
          builder: (context, snapshot) {
            final result = snapshot.data;
            final childSongs = result == null
                ? const <SongsTableData>[]
                : result.fold(
                    (_) => const <SongsTableData>[], (songs) => songs);

            return Column(
              children: [
                // Breadcrumbs bar
                Container(
                  height: 48,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  color: p.surfaceContainer.withValues(alpha: 0.4),
                  child: ListView.separated(
                    controller: _breadcrumbController,
                    scrollDirection: Axis.horizontal,
                    itemCount: breadcrumbs.length,
                    separatorBuilder: (_, __) => Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: p.textSecondary),
                    itemBuilder: (context, index) {
                      final crumbPath =
                          p_path.posix.joinAll(breadcrumbs.take(index + 1));
                      final isLast = index == breadcrumbs.length - 1;

                      return Center(
                        child: InkWell(
                          onTap: isLast ? null : () => _navigateTo(crumbPath),
                          borderRadius: AppRadii.r8All,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.xxs),
                            child: Text(
                              breadcrumbs[index],
                              style: TextStyle(
                                color: isLast ? p.primary : p.textSecondary,
                                fontWeight: isLast
                                    ? FontWeight.w700
                                    : FontWeight.normal,
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
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md, AppSpacing.xs, AppSpacing.md, 120),
                    children: [
                      // Parent folder button
                      if (breadcrumbs.length > 1) ...[
                        ListTile(
                          leading: Icon(Icons.arrow_upward_rounded,
                              color: p.primary),
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
                        Builder(
                          builder: (context) {
                            final item = representatives[p_path.posix
                                .normalize(sub.replaceAll('\\', '/'))];

                            final int? songId = item?.representativeSongId;
                            final int? albumId = item?.representativeAlbumId;
                            final String? remoteUrl =
                                item?.representativeRemoteUrl ??
                                    item?.representativeArtworkUri;

                            final hasArtwork = (songId != null && songId > 0) ||
                                (remoteUrl != null && remoteUrl.isNotEmpty);

                            return ListTile(
                              leading: hasArtwork
                                  ? CachedArtwork(
                                      id: songId ?? 0,
                                      albumId: albumId,
                                      remoteUrl: remoteUrl,
                                      type: ArtworkType.AUDIO,
                                      size: 40,
                                      borderRadius: AppRadii.r10,
                                      fallbackIcon: Icons.folder_rounded,
                                    )
                                  : Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: p.accentContainer,
                                        borderRadius: AppRadii.r10All,
                                      ),
                                      child: Icon(Icons.folder_rounded,
                                          color: p.accent, size: 20),
                                    ),
                              title: Text(
                                p_path.posix.basename(sub),
                                style: TextStyle(
                                    color: p.textPrimary,
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item != null)
                                    IconButton(
                                      icon: Icon(Icons.open_in_new_rounded,
                                          color: p.textSecondary, size: 18),
                                      tooltip:
                                          context.l10n.browseOpenFolderDetails,
                                      constraints: const BoxConstraints(
                                        minWidth: AppSpacing.minTouchTarget,
                                        minHeight: AppSpacing.minTouchTarget,
                                      ),
                                      onPressed: () {
                                        context.push(
                                            '/folder?path=${Uri.encodeComponent(item.path)}&name=${Uri.encodeComponent(item.name)}',
                                            extra: item);
                                      },
                                    ),
                                  Icon(Icons.chevron_right_rounded,
                                      color: p.textSecondary),
                                ],
                              ),
                              onTap: () => _navigateTo(sub),
                            );
                          },
                        ),
                      ],

                      // Songs in current folder (repository watch, not the
                      // paginated library page).
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          result == null)
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.md),
                          child: SkeletonList(itemCount: 3),
                        ),
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

                      if (childFolders.isEmpty &&
                          childSongs.isEmpty &&
                          snapshot.connectionState != ConnectionState.waiting)
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
      },
    );
  }
}
