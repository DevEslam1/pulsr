import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/pulsr_back_button.dart';
import '../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/playlist_usecases.dart';

class ManagePlaylistScreen extends StatefulWidget {
  final PlaylistsTableData playlist;

  const ManagePlaylistScreen({super.key, required this.playlist});

  @override
  State<ManagePlaylistScreen> createState() => _ManagePlaylistScreenState();
}

class _ManagePlaylistScreenState extends State<ManagePlaylistScreen> {
  final Set<int> _selectedSongIds = {};
  final Set<int> _initialSongIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;

  late final PlaylistUseCases _playlistUseCases;
  late final GetSongsUseCase _getSongsUseCase;

  @override
  void initState() {
    super.initState();
    _playlistUseCases = getIt<PlaylistUseCases>();
    _getSongsUseCase = getIt<GetSongsUseCase>();
    _loadInitialPlaylistSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPlaylistSongs() async {
    final stream = _playlistUseCases.watchPlaylistSongs(widget.playlist.id);
    final firstBatch = await stream.first;
    firstBatch.fold(
      (failure) {},
      (songs) {
        if (mounted) {
          setState(() {
            _initialSongIds.clear();
            _selectedSongIds.clear();
            for (final song in songs) {
              _initialSongIds.add(song.id);
              _selectedSongIds.add(song.id);
            }
            _isLoading = false;
          });
        }
      },
    );
  }

  List<SongsTableData> _filterSongs(List<SongsTableData> songs) {
    if (_searchQuery.isEmpty) return songs;
    final query = _searchQuery.toLowerCase();
    return songs.where((s) {
      final title = s.title.toLowerCase();
      final artist = s.artist.toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.surface,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage Playlist',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text(
              widget.playlist.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: p.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          StreamBuilder(
            stream: _getSongsUseCase.watchSongs(),
            builder: (context, snapshot) {
              final allSongs = snapshot.data
                      ?.fold((l) => <SongsTableData>[], (r) => r) ??
                  [];
              final visibleSongs = _filterSongs(allSongs);
              final isAllSelected = visibleSongs.isNotEmpty &&
                  visibleSongs.every((s) => _selectedSongIds.contains(s.id));

              return TextButton.icon(
                onPressed: visibleSongs.isEmpty
                    ? null
                    : () {
                        setState(() {
                          if (isAllSelected) {
                            for (final s in visibleSongs) {
                              _selectedSongIds.remove(s.id);
                            }
                          } else {
                            for (final s in visibleSongs) {
                              _selectedSongIds.add(s.id);
                            }
                          }
                        });
                      },
                icon: Icon(
                  isAllSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                  color: p.accent,
                  size: 18,
                ),
                label: Text(
                  isAllSelected ? 'Deselect' : 'Select All',
                  style: TextStyle(
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(p.accent),
              ),
            )
          : Column(
              children: [
                _buildSearchBar(p),
                _buildCountBanner(p),
                Expanded(
                  child: StreamBuilder(
                    stream: _getSongsUseCase.watchSongs(),
                    builder: (context, snapshot) {
                      final allSongs = snapshot.data
                              ?.fold((l) => <SongsTableData>[], (r) => r) ??
                          [];
                      final filteredSongs = _filterSongs(allSongs);

                      if (filteredSongs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 48, color: p.textTertiary),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No songs in library'
                                    : 'No songs matching "$_searchQuery"',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(
                            top: 8, bottom: 100, left: 12, right: 12),
                        itemCount: filteredSongs.length,
                        itemBuilder: (context, index) {
                          final song = filteredSongs[index];
                          final isSelected =
                              _selectedSongIds.contains(song.id);

                          return StaggeredListItem(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: AppRadii.cardRadius,
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedSongIds.remove(song.id);
                                      } else {
                                        _selectedSongIds.add(song.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: AppRadii.cardRadius,
                                      color: isSelected
                                          ? p.accent.withValues(
                                              alpha: p.isDark ? 0.12 : 0.08)
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? p.accent.withValues(alpha: 0.3)
                                            : Colors.transparent,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Checkbox
                                        Checkbox(
                                          value: isSelected,
                                          activeColor: p.accent,
                                          checkColor: p.onAccent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedSongIds.add(song.id);
                                              } else {
                                                _selectedSongIds.remove(song.id);
                                              }
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                        // Artwork
                                        CachedArtwork(
                                          id: song.id,
                                          remoteUrl: song.remoteArtworkUrl,
                                          type: ArtworkType.AUDIO,
                                          size: 44,
                                          borderRadius: 10,
                                        ),
                                        const SizedBox(width: 12),
                                        // Track details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                song.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: p.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                song.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: p.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
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
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomActionBar(p),
      ),
    );
  }

  Widget _buildSearchBar(PulsrPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GlassContainer(
        blur: 16,
        opacity: p.isDark ? 0.9 : 0.95,
        borderRadius: AppRadii.full,
        color: p.surfaceContainer,
        border: Border.all(color: p.hairline, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: p.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: TextStyle(color: p.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search songs by title or artist...',
                  hintStyle: TextStyle(color: p.textTertiary, fontSize: 13.5),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close_rounded, color: p.textSecondary, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBanner(PulsrPalette p) {
    final toAdd = _selectedSongIds.difference(_initialSongIds).length;
    final toRemove = _initialSongIds.difference(_selectedSongIds).length;
    final hasChanges = toAdd > 0 || toRemove > 0;

    if (!hasChanges) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: p.isDark ? 0.14 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: p.accent.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: p.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Will add: $toAdd track${toAdd == 1 ? '' : 's'} • Will remove: $toRemove track${toRemove == 1 ? '' : 's'}',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(PulsrPalette p) {
    final toAdd = _selectedSongIds.difference(_initialSongIds).length;
    final toRemove = _initialSongIds.difference(_selectedSongIds).length;
    final hasChanges = toAdd > 0 || toRemove > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.hairline, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton.icon(
          onPressed: hasChanges && !_isSaving ? _applyChanges : null,
          icon: _isSaving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(p.onAccent),
                  ),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 20),
          label: Text(
            hasChanges
                ? 'Apply Changes (+$toAdd / -$toRemove)'
                : 'No Changes to Save',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasChanges ? p.accent : p.surfaceContainerHigh,
            foregroundColor: hasChanges ? p.onAccent : p.textTertiary,
            elevation: hasChanges ? 3 : 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.buttonRadius,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyChanges() async {
    setState(() => _isSaving = true);

    final toAdd = _selectedSongIds.difference(_initialSongIds).toList();
    final toRemove = _initialSongIds.difference(_selectedSongIds).toList();

    if (toAdd.isNotEmpty) {
      await _playlistUseCases.addSongsToPlaylist(widget.playlist.id, toAdd);
    }

    for (final songId in toRemove) {
      await _playlistUseCases.removeSongFromPlaylist(widget.playlist.id, songId);
    }

    if (mounted) {
      Navigator.of(context).pop(true);
      PulsrToast.show(
        context,
        message:
            'Playlist updated (+${toAdd.length}, -${toRemove.length})',
        icon: Icons.check_circle_rounded,
      );
    }
  }
}
