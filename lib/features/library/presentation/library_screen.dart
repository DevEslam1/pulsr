import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/song_classification.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dismissible.dart';
import '../../../data/db/app_database.dart';
import '../../../core/utils/formatters.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../sheets/song_info_sheet.dart';
import '../../sheets/sort_filter_sheet.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import '../../tag_editor/tag_editor_screen.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import 'widgets/category_card.dart';
import 'widgets/folder_browser_tab.dart';
import 'widgets/folder_tree_browser_tab.dart';
import 'widgets/genre_hierarchy_view.dart';
part 'tabs/library_songs_tab.dart';
part 'tabs/library_collections_tabs.dart';
part 'tabs/library_favorites_tab.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin, LibrarySongsTab, LibraryCollectionsTabs, LibraryFavoritesTab {
  @override
  late TabController _tabController;
  @override
  final ScrollController _songsScrollController = ScrollController();
  @override
  int _favTabFilter = 0; // 0: Local, 1: Online

  static const String _genreHierarchyPrefKey = 'library_genre_hierarchy';
  static const String _folderTreePrefKey = 'library_folder_tree';

  @override
  bool _genreHierarchy = false;
  @override
  bool _folderTree = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _songsScrollController.addListener(_onSongsScrollNearBottom);
    _loadLayoutPreferences();
  }

  Future<void> _loadLayoutPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _genreHierarchy = prefs.getBool(_genreHierarchyPrefKey) ?? false;
        _folderTree = prefs.getBool(_folderTreePrefKey) ?? false;
      });
    } catch (_) {}
  }

  @override
  void _setGenreHierarchy(bool value) {
    if (_genreHierarchy == value) return;
    setState(() => _genreHierarchy = value);
    _persistLayoutPref(_genreHierarchyPrefKey, value);
  }

  @override
  void _setFolderTree(bool value) {
    if (_folderTree == value) return;
    setState(() => _folderTree = value);
    _persistLayoutPref(_folderTreePrefKey, value);
  }

  Future<void> _persistLayoutPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _songsScrollController.removeListener(_onSongsScrollNearBottom);
    _tabController.dispose();
    _songsScrollController.dispose();
    super.dispose();
  }

  void _onSongsScrollNearBottom() {
    if (!_songsScrollController.hasClients) return;
    final pos = _songsScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 800) {
      try {
        context.read<LibraryCubit>().loadMoreSongs();
      } catch (_) {}
    }
  }

  static const double _songRowExtent = 58.0;

  @override
  void _scrollToLetter(String letter, List<SongsTableData> songs) {
    final index =
        songs.indexWhere((s) => s.title.toUpperCase().startsWith(letter));
    if (index == -1 || !_songsScrollController.hasClients) return;
    final trackCols = context.trackGridColumns;
    final double target;
    if (trackCols > 1) {
      // Grid rows are fixed mainAxisExtent 72 + 4 spacing.
      final row = index ~/ trackCols;
      target = row * 76.0;
    } else if (songs.length > 500) {
      // Fixed itemExtent path: exact offset, no proportional estimate.
      target = index * _songRowExtent;
    } else {
      final maxScroll = _songsScrollController.position.maxScrollExtent;
      target =
          songs.length > 1 ? (index / (songs.length - 1)) * maxScroll : 0.0;
    }
    final maxScroll = _songsScrollController.position.maxScrollExtent;
    _songsScrollController.animateTo(
      target.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final cubit = context.read<LibraryCubit>();
        final playerCubit = context.read<PlayerCubit>();
        final isMultiSelect = state.isMultiSelectMode;
        final p = context.palette;

        return Scaffold(
          appBar: isMultiSelect
              ? AppBar(
                  leading: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: cubit.clearSelection),
                  title: Text(context.l10n.selectedCount(state.selectedSongIds.length)),
                  actions: [
                    IconButton(
                        icon: const Icon(Icons.select_all_rounded),
                        tooltip: context.l10n.selectAllAction,
                        onPressed: () => cubit.selectAllSongs()),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded),
                      tooltip: context.l10n.addToPlaylist,
                      onPressed: () async {
                        final selected = await cubit.getSelectedSongs();
                        if (!context.mounted) return;
                        if (selected.isNotEmpty) {
                          AddToPlaylistSheet.show(
                            context,
                            song: selected.first,
                            songs: selected,
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note_rounded),
                      tooltip: context.l10n.browseBatchEditTags,
                      onPressed: () async {
                        final selected = await cubit.getSelectedSongs();
                        if (!context.mounted) return;
                        if (selected.isNotEmpty) {
                          cubit.clearSelection();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TagEditorScreen(
                                song: selected.first,
                                batchSongs: selected,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music_rounded),
                      tooltip: context.l10n.addToQueue,
                      onPressed: () async {
                        final selected = await cubit.getSelectedSongs();
                        if (!context.mounted) return;
                        for (final s in selected) {
                          playerCubit.addToQueue(s);
                        }
                        cubit.clearSelection();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(context.l10n
                                .addedToQueue(selected.length))));
                      },
                    ),
                  ],
                )
              : AppBar(
                  title: Text(context.l10n.navLibrary),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.dashboard_customize_rounded),
                      tooltip: 'Jump to Category',
                      onPressed: () => _showCategoryJumpSheet(context, state),
                    ),
                    IconButton(
                      icon: Icon(state.viewMode == LibraryViewMode.list
                          ? Icons.grid_view_rounded
                          : Icons.view_list_rounded),
                      onPressed: cubit.toggleViewMode,
                    ),
                    IconButton(
                      icon: const Icon(Icons.sort_rounded),
                      onPressed: () => SortFilterSheet.show(
                        context,
                        currentSort: state.sortBy,
                        ascending: state.ascending,
                        onApply: (sort, asc) => cubit.updateSort(sort, asc),
                      ),
                    ),
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    physics: const BouncingScrollPhysics(),
                    tabs: [
                      Tab(text: context.l10n.songs),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.l10n.downloaded),
                            if (state.songs
                                .where((s) => s.isDownloaded == true)
                                .isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${state.songs.where((s) => s.isDownloaded == true).length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: p.accent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Tab(text: context.l10n.albums),
                      Tab(text: context.l10n.artists),
                      Tab(text: context.l10n.favorites),
                      Tab(text: context.l10n.folders),
                      Tab(text: context.l10n.genres),
                      Tab(text: context.l10n.years),
                    ],
                  ),
                ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSongsTab(context, state, cubit, playerCubit),
                  _buildDownloadedTab(context, state, cubit, playerCubit),
                  _buildAlbumsTab(context, state),
                  _buildArtistsTab(context, state),
                  _buildFavoritesTab(context, state, playerCubit),
                  _buildFoldersTab(context),
                  _buildGenresTab(context, state),
                  _buildYearsTab(context, state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCategoryJumpSheet(BuildContext context, LibraryState state) {
    final p = context.palette;
    final downloadedCount =
        state.songs.where((s) => s.isDownloaded == true).length;

    final categories = [
      (
        index: 0,
        title: context.l10n.songs,
        subtitle: Formatters.formatSongCount(state.songs.length),
        icon: Icons.music_note_rounded,
        color: p.accent,
      ),
      (
        index: 1,
        title: context.l10n.downloaded,
        subtitle: '$downloadedCount ${context.l10n.downloaded.toLowerCase()}',
        icon: Icons.download_done_rounded,
        color: const Color(0xFF26A69A),
      ),
      (
        index: 2,
        title: context.l10n.albums,
        subtitle: '${state.albums.length} ${context.l10n.albums.toLowerCase()}',
        icon: Icons.album_rounded,
        color: const Color(0xFFFF9800),
      ),
      (
        index: 3,
        title: context.l10n.artists,
        subtitle: '${state.artists.length} ${context.l10n.artists.toLowerCase()}',
        icon: Icons.person_rounded,
        color: const Color(0xFFAB47BC),
      ),
      (
        index: 4,
        title: context.l10n.favorites,
        subtitle: Formatters.formatSongCount(state.favorites.length),
        icon: Icons.favorite_rounded,
        color: const Color(0xFFEF5350),
      ),
      (
        index: 5,
        title: context.l10n.folders,
        subtitle: '${state.folders.length} ${context.l10n.folders.toLowerCase()}',
        icon: Icons.folder_rounded,
        color: const Color(0xFFFFB300),
      ),
      (
        index: 6,
        title: context.l10n.genres,
        subtitle: '${state.genres.length} ${context.l10n.genres.toLowerCase()}',
        icon: Icons.category_rounded,
        color: const Color(0xFF29B6F6),
      ),
      (
        index: 7,
        title: context.l10n.years,
        subtitle: '${state.years.length} ${context.l10n.years.toLowerCase()}',
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF5C6BC0),
      ),
    ];

    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetContext) {
        return PulsrBottomSheetContainer(
          title: Text(context.l10n.navLibrary),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: sheetContext.isTablet ? 3 : 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 68,
              ),
              itemCount: categories.length,
              itemBuilder: (_, i) {
                final cat = categories[i];
                final isSelected = _tabController.index == cat.index;
                return CategoryCard(
                  icon: cat.icon,
                  title: cat.title,
                  subtitle: cat.subtitle,
                  color: cat.color,
                  isSelected: isSelected,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(sheetContext).pop();
                    _tabController.animateTo(cat.index);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Future<void> _handleRefresh(BuildContext context) async {
    final settingsCubit = context.read<SettingsCubit>();
    final libraryCubit = context.read<LibraryCubit>();
    final count = await settingsCubit.rescanLibrary();
    if (context.mounted) {
      await libraryCubit.init();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.scanResult(count)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget _buildEmpty(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
  }) {
    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: icon,
              title: title,
              subtitle: subtitle,
              primaryActionLabel: actionLabel ?? context.l10n.scanStorage,
              primaryActionIcon:
                  actionIcon ?? Icons.center_focus_strong_rounded,
              onPrimaryAction: onAction ?? () => _handleRefresh(context),
            ),
          ),
        ],
      ),
    );
  }


}

class _FavTabButton extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FavTabButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: p.accent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? p.onAccent : p.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? p.onAccent : p.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? p.onAccent.withValues(alpha: 0.25)
                    : p.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? p.onAccent : p.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: selected ? p.accent : p.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? p.onAccent : p.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? p.onAccent : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
