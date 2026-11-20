// lib/features/remote_sources/remote_browser_sheet.dart
//
// P0-1 "remote sources": the folder browser.
//
// Loads one directory at a time through the provider it is handed, keeps a
// breadcrumb of the path, and reports a file tap to [onPlay]. It never closes
// the provider: the screen that created it owns that lifetime.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/pulsr_progress.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/remote/subsonic_client.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'remote_sources_strings.dart';
import 'subsonic_fs_provider.dart';

/// Bottom sheet that browses one remote source.
class RemoteBrowserSheet extends StatefulWidget {
  /// Creates the browser for [source] over [provider].
  const RemoteBrowserSheet({
    super.key,
    required this.source,
    required this.provider,
    this.onPlay,
  });

  /// Source being browsed (used for the title and the play callback).
  final RemoteSource source;

  /// Provider to list through; owned by the caller.
  final RemoteFsProvider provider;

  /// Invoked when the user taps a file.
  final Future<void> Function(RemoteSource source, RemoteEntry entry)? onPlay;

  @override
  State<RemoteBrowserSheet> createState() => _RemoteBrowserSheetState();
}

class _RemoteBrowserSheetState extends State<RemoteBrowserSheet> {
  String _path = '';
  final List<_Crumb> _crumbs = <_Crumb>[
    const _Crumb('', RemoteSourcesStrings.rootCrumb),
  ];
  List<RemoteEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String? _playError;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<RemoteEntry>? _searchResults;
  bool _searchLoading = false;
  String? _searchError;
  String _searchQuery = '';
  int _searchArtistOffset = 0;
  int _searchAlbumOffset = 0;
  int _searchSongOffset = 0;
  bool _searchHasMore = false;
  bool _searchLoadingMore = false;
  Timer? _debounceTimer;
  int _searchSequence = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    _debounceTimer?.cancel();
    final currentSeq = ++_searchSequence;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = null;
        _searchLoading = false;
        _searchError = null;
        _searchQuery = '';
        _searchHasMore = false;
      });
      return;
    }
    final provider = widget.provider;
    if (provider is! SubsonicFsProvider) return;

    setState(() {
      _searchLoading = true;
      _searchError = null;
    });

    try {
      final results = await provider.search(trimmed);
      if (!mounted || currentSeq != _searchSequence) return;
      final entries = _entriesFromSearch(provider, results);

      setState(() {
        _searchResults = entries;
        _searchQuery = trimmed;
        _searchArtistOffset = results.artists.length;
        _searchAlbumOffset = results.albums.length;
        _searchSongOffset = results.songs.length;
        _searchHasMore = results.artists.length >= 20 ||
            results.albums.length >= 20 ||
            results.songs.length >= 50;
        _searchLoading = false;
      });
    } on AppError catch (e, st) {
      if (!mounted || currentSeq != _searchSequence) return;
      ErrorLogger.log(
        'Subsonic search failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      if (!mounted) return;
      setState(() {
        _searchResults = null;
        _searchError = e.userMessage;
        _searchLoading = false;
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Subsonic search failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      if (!mounted) return;
      setState(() {
        _searchResults = null;
        _searchError = RemoteSourcesStrings.folderLoadFailed;
        _searchLoading = false;
      });
    }
  }

  List<RemoteEntry> _entriesFromSearch(
    SubsonicFsProvider provider,
    SubsonicSearchResult results,
  ) {
    final entries = <RemoteEntry>[];
    for (final artist in results.artists) {
      entries.add(RemoteEntry(
        path: SubsonicFsProvider.artistPath(artist.id),
        name: artist.name,
        isDirectory: true,
        artworkUri:
            provider.getCoverArtUrl(artist.coverArt, size: 160)?.toString(),
        artworkCacheKey:
            provider.getCoverArtCacheKey(artist.coverArt, size: 160),
      ));
    }
    for (final album in results.albums) {
      final displayName = album.artist.isNotEmpty
          ? '${album.name} • ${album.artist}'
          : album.name;
      entries.add(RemoteEntry(
        path: SubsonicFsProvider.albumPath(album.id),
        name: displayName,
        isDirectory: true,
        artworkUri:
            provider.getCoverArtUrl(album.coverArt, size: 160)?.toString(),
        artworkCacheKey:
            provider.getCoverArtCacheKey(album.coverArt, size: 160),
      ));
    }
    for (final song in results.songs) {
      final albumId = song.albumId ?? 'song';
      final displayName = song.artist != null && song.artist!.isNotEmpty
          ? '${song.title} • ${song.artist}'
          : song.title;
      entries.add(RemoteEntry(
        path: SubsonicFsProvider.songPath(albumId, song.id),
        name: displayName,
        isDirectory: false,
        sizeBytes: song.sizeBytes,
        artworkUri:
            provider.getCoverArtUrl(song.coverArt, size: 160)?.toString(),
        artworkCacheKey:
            provider.getCoverArtCacheKey(song.coverArt, size: 160),
      ));
    }
    return entries;
  }

  Future<void> _loadMoreSearch() async {
    final provider = widget.provider;
    if (provider is! SubsonicFsProvider ||
        _searchLoadingMore ||
        !_searchHasMore ||
        _searchQuery.isEmpty) {
      return;
    }
    final currentSeq = _searchSequence;
    setState(() => _searchLoadingMore = true);
    try {
      final results = await provider.search(
        _searchQuery,
        artistOffset: _searchArtistOffset,
        albumOffset: _searchAlbumOffset,
        songOffset: _searchSongOffset,
      );
      if (!mounted || currentSeq != _searchSequence) return;
      final existing = _searchResults ?? const <RemoteEntry>[];
      final seen = existing.map((e) => e.path).toSet();
      final additions = _entriesFromSearch(provider, results)
          .where((e) => seen.add(e.path))
          .toList();
      setState(() {
        _searchResults = [...existing, ...additions];
        _searchArtistOffset += results.artists.length;
        _searchAlbumOffset += results.albums.length;
        _searchSongOffset += results.songs.length;
        _searchHasMore = additions.isNotEmpty &&
            (results.artists.length >= 20 ||
                results.albums.length >= 20 ||
                results.songs.length >= 50);
        _searchLoadingMore = false;
      });
    } catch (e, st) {
      ErrorLogger.log('Subsonic search page failed',
          error: e, stackTrace: st, category: 'RemoteSources');
      if (mounted) setState(() => _searchLoadingMore = false);
    }
  }

  Future<void> _load(String path, {String? label}) async {
    setState(() {
      _path = path;
      _updateCrumbs(path, label);
      _loading = true;
      _error = null;
      _playError = null;
    });
    try {
      final entries = await widget.provider.list(path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'Remote folder could not be listed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = e.userMessage;
        _loading = false;
      });
    } catch (e, st) {
      ErrorLogger.log(
        'Remote folder could not be listed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = RemoteSourcesStrings.folderLoadFailed;
        _loading = false;
      });
    }
  }

  /// Keeps the breadcrumb in step with [_path].
  ///
  /// Jumping to an ancestor truncates the trail; entering a folder appends the
  /// entry's own name, so a provider whose paths are opaque ids (Subsonic,
  /// UPnP) still shows readable breadcrumbs. A refresh of the current path
  /// leaves the trail untouched.
  void _updateCrumbs(String path, String? label) {
    final index = _crumbs.indexWhere((crumb) => crumb.path == path);
    if (index >= 0) {
      _crumbs.removeRange(index + 1, _crumbs.length);
      return;
    }
    if (label != null) {
      _crumbs.add(_Crumb(path, label));
      return;
    }
    _crumbs.add(_Crumb(path, path.split('/').last));
  }

  Future<void> _play(RemoteEntry entry) async {
    final onPlay = widget.onPlay;
    if (onPlay == null) {
      setState(() => _playError = RemoteSourcesStrings.folderLoadFailed);
      return;
    }
    try {
      await onPlay(widget.source, entry);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'Remote file could not be played: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() => _playError = e.userMessage);
    } catch (e, st) {
      ErrorLogger.log(
        'Remote file could not be played',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': widget.source.authority},
      );
      if (!mounted) return;
      setState(() => _playError = RemoteSourcesStrings.folderLoadFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.source.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (widget.provider is SubsonicFsProvider)
                    IconButton(
                      tooltip: RemoteSourcesStrings.searchLibrary,
                      icon: Icon(_isSearching ? Icons.close : Icons.search),
                      onPressed: () {
                        setState(() {
                          _isSearching = !_isSearching;
                          if (!_isSearching) {
                            _searchController.clear();
                            _searchResults = null;
                            _searchError = null;
                          }
                        });
                      },
                    ),
                  IconButton(
                    tooltip: RemoteSourcesStrings.retry,
                    onPressed: _loading ? null : () => _load(_path),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: RemoteSourcesStrings.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_isSearching)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: RemoteSourcesStrings.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: RemoteSourcesStrings.searchClear,
                            onPressed: () {
                              _searchController.clear();
                              _performSearch('');
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _performSearch,
                ),
              )
            else ...[
              _Breadcrumbs(crumbs: _crumbs, onNavigate: _loading ? null : _load),
              const Divider(height: 1),
            ],
            Expanded(
              child: _isSearching ? _buildSearchResults() : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchLoading) {
      return const Center(
        child: SizedBox(width: 160, child: PulsrProgressBar()),
      );
    }
    final error = _searchError;
    if (error != null) {
      return _ErrorState(
        message: error,
        onRetry: () => _performSearch(_searchController.text),
      );
    }
    final results = _searchResults;
    if (results == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsetsDirectional.all(24),
          child: Text(RemoteSourcesStrings.searchHint),
        ),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsetsDirectional.all(24),
          child: Text(RemoteSourcesStrings.noSearchResults),
        ),
      );
    }
    return Column(
      children: [
        if (_playError != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 0),
            child: Text(
              _playError!,
              style: TextStyle(color: context.palette.error),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length + (_searchHasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= results.length) {
                return Padding(
                  padding: const EdgeInsetsDirectional.all(12),
                  child: Center(
                    child: TextButton(
                      onPressed:
                          _searchLoadingMore ? null : _loadMoreSearch,
                      child: Text(_searchLoadingMore
                          ? RemoteSourcesStrings.testing
                          : RemoteSourcesStrings.loadMore),
                    ),
                  ),
                );
              }
              final entry = results[index];
              return _EntryTile(
                entry: entry,
                onTap: () {
                  if (entry.isDirectory) {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                      _searchResults = null;
                    });
                    _load(entry.path, label: entry.name);
                  } else {
                    _play(entry);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 160, child: PulsrProgressBar()),
      );
    }
    final error = _error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: () => _load(_path));
    }
    final entries = _entries;
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsetsDirectional.all(24),
          child: Text(RemoteSourcesStrings.emptyFolder),
        ),
      );
    }
    return Column(
      children: [
        if (_playError != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 0),
            child: Text(
              _playError!,
              style: TextStyle(color: context.palette.error),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _EntryTile(
                entry: entry,
                onTap: () => entry.isDirectory
                    ? _load(entry.path, label: entry.name)
                    : _play(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final RemoteEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = entry.sizeBytes;
    final artworkUri = entry.artworkUri;

    Widget leadingWidget;
    if (artworkUri != null && artworkUri.isNotEmpty) {
      leadingWidget = CachedArtwork(
        id: 0,
        remoteUrl: artworkUri,
        cacheKeyOverride: entry.artworkCacheKey,
        size: 40,
        borderRadius: 4,
        fallbackIcon: entry.isDirectory
            ? Icons.folder_outlined
            : Icons.audio_file_outlined,
      );
    } else {
      leadingWidget = Icon(
        entry.isDirectory ? Icons.folder_outlined : Icons.audio_file_outlined,
        color: entry.isDirectory ? palette.accent : palette.textSecondary,
        semanticLabel: entry.isDirectory
            ? RemoteSourcesStrings.folderLabel
            : RemoteSourcesStrings.fileNameUnknown,
      );
    }

    return ListTile(
      minVerticalPadding: 12,
      leading: leadingWidget,
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.isDirectory || size == null
          ? null
          : Text(RemoteSourcesStrings.formatBytes(size)),
      trailing: Icon(
        entry.isDirectory ? Icons.chevron_right : Icons.play_arrow,
        color: palette.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.crumbs, required this.onNavigate});

  final List<_Crumb> crumbs;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
      child: Row(
        children: [
          for (var index = 0; index < crumbs.length; index++) ...[
            if (index > 0)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: palette.textTertiary,
              ),
            TextButton(
              onPressed: onNavigate == null
                  ? null
                  : () => onNavigate!(crumbs[index].path),
              child: Text(crumbs[index].label),
            ),
          ],
        ],
      ),
    );
  }
}

/// One breadcrumb stop: the path to open and the label to show.
class _Crumb {
  const _Crumb(this.path, this.label);

  /// Provider-relative path to navigate to.
  final String path;

  /// Display label (an entry name, not necessarily a path segment).
  final String label;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: palette.error, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text(RemoteSourcesStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
