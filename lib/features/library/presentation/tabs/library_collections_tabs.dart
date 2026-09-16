// ignore_for_file: unused_element_parameter
part of '../library_screen.dart';

mixin LibraryCollectionsTabs on State<LibraryScreen> {
  // ================= ALBUMS (adaptive grid / list) =================
  Widget _buildAlbumsTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final albums = state.albums;
    if (albums.isEmpty) {
      return _buildEmpty(context,
          title: context.l10n.noAlbumsFound,
          subtitle: context.l10n.browseScanForAlbums,
          icon: Icons.album_rounded);
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: isGrid
          ? GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
                  Adaptive.pagePadding(context), 160),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    Adaptive.gridColumns(context, minItemWidth: 168),
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
                childAspectRatio: 0.78,
              ),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                final album = albums[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/album', extra: album),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Hero(
                          tag: 'album_${album.id}',
                          child: CachedArtwork(
                              id: album.id,
                              type: ArtworkType.ALBUM,
                              size: double.infinity,
                              borderRadius: 18),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(
                          '${album.artist} • ${Formatters.formatTrackCount(album.songCount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                );
              },
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 160, top: 8),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                final album = albums[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Material(
                    color: p.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: p.hairline),
                    ),
                    child: ListTile(
                      leading: CachedArtwork(
                          id: album.id,
                          type: ArtworkType.ALBUM,
                          size: 48,
                          borderRadius: 12),
                      title: Text(album.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: p.textPrimary)),
                      subtitle: Text(
                          '${album.artist} • ${Formatters.formatTrackCount(album.songCount)}',
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: p.textTertiary),
                      onTap: () => context.push('/album', extra: album),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ================= ARTISTS =================
  Widget _buildArtistsTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final artists = state.artists;
    if (artists.isEmpty) {
      return _buildEmpty(context,
          title: context.l10n.browseNoArtistsFound,
          subtitle: context.l10n.browseScanForArtists,
          icon: Icons.person_rounded);
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: isGrid
          ? GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
                  Adaptive.pagePadding(context), 160),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Adaptive.gridColumns(context,
                    minItemWidth: 150, phoneColumns: 3, maxColumns: 8),
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
                childAspectRatio: 0.82,
              ),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/artist', extra: artist),
                  child: Column(
                    children: [
                      Expanded(
                        child: CachedArtwork(
                            id: artist.id,
                            type: ArtworkType.ARTIST,
                            size: double.infinity,
                            borderRadius: 999,
                            fallbackIcon: Icons.person_rounded),
                      ),
                      const SizedBox(height: 9),
                      Text(artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text(Formatters.formatTrackCount(artist.songCount),
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 11)),
                    ],
                  ),
                );
              },
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 160, top: 8),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Material(
                    color: p.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: p.hairline),
                    ),
                    child: ListTile(
                      leading: CachedArtwork(
                          id: artist.id,
                          type: ArtworkType.ARTIST,
                          size: 48,
                          borderRadius: 999,
                          fallbackIcon: Icons.person_rounded),
                      title: Text(artist.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: p.textPrimary)),
                      subtitle: Text(
                          Formatters.formatTrackCount(artist.songCount),
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: p.textTertiary),
                      onTap: () => context.push('/artist', extra: artist),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ================= FOLDERS / GENRES / YEARS =================
  Widget _buildFoldersTab(BuildContext context) {
    return Column(
      children: [
        _buildLayoutToggleHeader(
          context,
          hierarchySelected: _folderTree,
          flatLabel: context.l10n.browseList,
          hierarchyLabel: context.l10n.browseTree,
          flatIcon: Icons.view_list_rounded,
          hierarchyIcon: Icons.account_tree_rounded,
          onChanged: _setFolderTree,
        ),
        Expanded(
          child: _folderTree
              ? const FolderTreeBrowserTab()
              : const FolderBrowserTab(),
        ),
      ],
    );
  }

  Widget _buildGenresTab(BuildContext context, LibraryState state) {
    final p = context.palette;
    final genres = state.genres;
    if (genres.isEmpty) {
      return _buildEmpty(context,
          title: context.l10n.browseNoGenresFound,
          subtitle: context.l10n.browseScanForGenres,
          icon: Icons.style_rounded);
    }
    return Column(
      children: [
        _buildLayoutToggleHeader(
          context,
          hierarchySelected: _genreHierarchy,
          flatLabel: context.l10n.browseFlat,
          hierarchyLabel: context.l10n.browseCategories,
          flatIcon: Icons.grid_view_rounded,
          hierarchyIcon: Icons.category_rounded,
          onChanged: _setGenreHierarchy,
        ),
        Expanded(
          child: _genreHierarchy
              ? GenreHierarchyView(genres: genres)
              : _chipCategoryGrid(
                  context,
                  count: genres.length,
                  builder: (context, i) {
                    final g = genres[i];
                    return CategoryCard(
                      icon: Icons.style_rounded,
                      title: g.name,
                      subtitle: Formatters.formatTrackCount(g.songCount),
                      color: p.accent,
                      onTap: () => context.push('/genre', extra: g),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLayoutToggleHeader(
    BuildContext context, {
    required bool hierarchySelected,
    required String flatLabel,
    required String hierarchyLabel,
    required IconData flatIcon,
    required IconData hierarchyIcon,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Adaptive.pagePadding(context),
        10,
        Adaptive.pagePadding(context),
        2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _LayoutToggleButton(
            icon: flatIcon,
            label: flatLabel,
            selected: !hierarchySelected,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 8),
          _LayoutToggleButton(
            icon: hierarchyIcon,
            label: hierarchyLabel,
            selected: hierarchySelected,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _buildYearsTab(BuildContext context, LibraryState state) {
    final years = state.years;
    if (years.isEmpty) {
      return _buildEmpty(context,
          title: context.l10n.browseNoYearsFound,
          subtitle: context.l10n.browseScanForYears,
          icon: Icons.calendar_today_rounded);
    }
    return _chipCategoryGrid(
      context,
      count: years.length,
      builder: (context, i) {
        final y = years[i];
        return CategoryCard(
          icon: Icons.calendar_today_rounded,
          title: '${y.year}',
          subtitle: Formatters.formatTrackCount(y.songCount),
          color: const Color(0xFF40C4FF),
          onTap: () => context.push('/year', extra: y),
        );
      },
    );
  }

  Widget _chipCategoryGrid(BuildContext context,
      {required int count,
      required Widget Function(BuildContext, int) builder}) {
    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
            Adaptive.pagePadding(context), 160),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:
              Adaptive.gridColumns(context, minItemWidth: 160, phoneColumns: 2),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.4,
        ),
        itemCount: count,
        itemBuilder: builder,
      ),
    );
  }




































  // Requires: provided by the composing class (same library).
  Widget _buildEmpty(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
  });

  // Requires: provided by the composing class (same library).
  bool get _folderTree;

  // Requires: provided by the composing class (same library).
  bool get _genreHierarchy;

  // Requires: provided by the composing class (same library).
  Future<void> _handleRefresh(BuildContext context);

  // Requires: provided by the composing class (same library).
  void _setFolderTree(bool value);

  // Requires: provided by the composing class (same library).
  void _setGenreHierarchy(bool value);
}
