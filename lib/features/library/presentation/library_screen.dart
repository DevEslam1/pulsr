import 'dart:async';
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
import '../../../core/motion/pulsr_motion.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/song_classification.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_dismissible.dart';
import '../../../core/widgets/pulsr_segmented_control.dart';
import '../../../core/widgets/shimmer_skeleton.dart';
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
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import '../../../core/utils/error_logger.dart';
part 'tabs/library_songs_tab.dart';
part 'tabs/library_collections_tabs.dart';
part 'tabs/library_favorites_tab.dart';

enum LibraryTabItem {
  songs,
  downloaded,
  albums,
  artists,
  favorites,
  folders,
  genres,
  years;

  static const List<LibraryTabItem> defaultTabs = [
    LibraryTabItem.songs,
    LibraryTabItem.downloaded,
    LibraryTabItem.albums,
    LibraryTabItem.artists,
    LibraryTabItem.favorites,
  ];

  String title(BuildContext context) {
    switch (this) {
      case LibraryTabItem.songs:
        return context.l10n.songs;
      case LibraryTabItem.downloaded:
        return context.l10n.downloaded;
      case LibraryTabItem.albums:
        return context.l10n.albums;
      case LibraryTabItem.artists:
        return context.l10n.artists;
      case LibraryTabItem.favorites:
        return context.l10n.favorites;
      case LibraryTabItem.folders:
        return context.l10n.folders;
      case LibraryTabItem.genres:
        return context.l10n.genres;
      case LibraryTabItem.years:
        return context.l10n.years;
    }
  }

  String subtitle(BuildContext context, LibraryState state) {
    switch (this) {
      case LibraryTabItem.songs:
        return Formatters.formatSongCount(state.songs.length);
      case LibraryTabItem.downloaded:
        final count = state.songs.where(isDownloadedOnlineTrack).length;
        return '$count ${context.l10n.downloaded.toLowerCase()}';
      case LibraryTabItem.albums:
        return '${state.albums.length} ${context.l10n.albums.toLowerCase()}';
      case LibraryTabItem.artists:
        return '${state.artists.length} ${context.l10n.artists.toLowerCase()}';
      case LibraryTabItem.favorites:
        return Formatters.formatSongCount(state.favorites.length);
      case LibraryTabItem.folders:
        return '${state.folders.length} ${context.l10n.folders.toLowerCase()}';
      case LibraryTabItem.genres:
        return '${state.genres.length} ${context.l10n.genres.toLowerCase()}';
      case LibraryTabItem.years:
        return '${state.years.length} ${context.l10n.years.toLowerCase()}';
    }
  }

  IconData get icon {
    switch (this) {
      case LibraryTabItem.songs:
        return Icons.music_note_rounded;
      case LibraryTabItem.downloaded:
        return Icons.download_done_rounded;
      case LibraryTabItem.albums:
        return Icons.album_rounded;
      case LibraryTabItem.artists:
        return Icons.person_rounded;
      case LibraryTabItem.favorites:
        return Icons.favorite_rounded;
      case LibraryTabItem.folders:
        return Icons.folder_rounded;
      case LibraryTabItem.genres:
        return Icons.category_rounded;
      case LibraryTabItem.years:
        return Icons.calendar_today_rounded;
    }
  }

  Color color(PulsrPalette p) {
    switch (this) {
      case LibraryTabItem.songs:
        return p.accent;
      case LibraryTabItem.downloaded:
        return const Color(0xFF26A69A);
      case LibraryTabItem.albums:
        return const Color(0xFFFF9800);
      case LibraryTabItem.artists:
        return const Color(0xFFAB47BC);
      case LibraryTabItem.favorites:
        return const Color(0xFFEF5350);
      case LibraryTabItem.folders:
        return AppColors.warning;
      case LibraryTabItem.genres:
        return const Color(0xFF29B6F6);
      case LibraryTabItem.years:
        return const Color(0xFF5C6BC0);
    }
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with TickerProviderStateMixin, LibrarySongsTab, LibraryCollectionsTabs, LibraryFavoritesTab {
  @override
  late TabController _tabController;
  @override
  final ScrollController _songsScrollController = ScrollController();
  @override
  int _favTabFilter = 0; // 0: Local, 1: Online

  int _lastPersistedTab = 0;

  static const String _genreHierarchyPrefKey = 'library_genre_hierarchy';
  static const String _folderTreePrefKey = 'library_folder_tree';
  static const String _activeTabsPrefKey = 'library_active_tabs';
  static const String _tabNamePrefKey = 'library_selected_tab_name';
  static const String _tabIndexPrefKey = 'library_tab_index';

  List<LibraryTabItem> _activeTabs = List.from(LibraryTabItem.defaultTabs);

  @override
  bool _genreHierarchy = false;
  @override
  bool _folderTree = false;

  @override
  final TextEditingController _importYtmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _activeTabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _songsScrollController.addListener(_onSongsScrollNearBottom);
    _loadLayoutPreferences();
  }

  /// Remember the user's last library surface so reopening Library resumes
  /// where they left off (e.g. Albums) instead of always snapping to Songs.
  void _onTabChanged() => unawaited(_persistSelectedTab());

  Future<void> _persistSelectedTab() async {
    if (_tabController.indexIsChanging) return;
    final index = _tabController.index;
    if (index == _lastPersistedTab) return;
    _lastPersistedTab = index;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_tabIndexPrefKey, index);
      if (index >= 0 && index < _activeTabs.length) {
        await prefs.setString(_tabNamePrefKey, _activeTabs[index].name);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to persist library tab index',
          error: e, stackTrace: st, category: 'Library');
    }
  }

  void _rebuildTabController({int initialIndex = 0}) {
    final oldController = _tabController;
    oldController.removeListener(_onTabChanged);
    final safeIndex = initialIndex.clamp(0, _activeTabs.length - 1);
    _tabController = TabController(
      length: _activeTabs.length,
      vsync: this,
      initialIndex: safeIndex,
    );
    _lastPersistedTab = safeIndex;
    _tabController.addListener(_onTabChanged);
    oldController.dispose();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _songsScrollController.removeListener(_onSongsScrollNearBottom);
    _songsScrollController.dispose();
    _importYtmController.dispose();
    super.dispose();
  }

  Future<void> _loadLayoutPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final savedTabNames = prefs.getStringList(_activeTabsPrefKey);
      if (savedTabNames != null && savedTabNames.isNotEmpty) {
        final loaded = savedTabNames
            .map((name) {
              for (final item in LibraryTabItem.values) {
                if (item.name == name) return item;
              }
              return null;
            })
            .whereType<LibraryTabItem>()
            .toList();
        if (loaded.isNotEmpty) {
          _activeTabs = loaded;
        }
      }

      final savedTabName = prefs.getString(_tabNamePrefKey);
      int targetIndex = 0;
      if (savedTabName != null) {
        final found = _activeTabs.indexWhere((t) => t.name == savedTabName);
        if (found != -1) targetIndex = found;
      } else {
        final savedTab = prefs.getInt(_tabIndexPrefKey);
        if (savedTab != null &&
            savedTab >= 0 &&
            savedTab < _activeTabs.length) {
          targetIndex = savedTab;
        }
      }

      if (!mounted) return;

      if (_tabController.length != _activeTabs.length ||
          _tabController.index != targetIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Rebuild with the new controller; disposing the old one without a
            // setState left mounted TabBar/TabBarView holding a dead controller.
            setState(() => _rebuildTabController(initialIndex: targetIndex));
          }
        });
      }

      if (mounted) {
        setState(() {
          _genreHierarchy = prefs.getBool(_genreHierarchyPrefKey) ?? false;
          _folderTree = prefs.getBool(_folderTreePrefKey) ?? false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load library preferences',
          error: e, stackTrace: st, category: 'Library');
    }
  }

  void _toggleTab(LibraryTabItem tab) {
    final currentTabItem = (_tabController.index >= 0 &&
            _tabController.index < _activeTabs.length)
        ? _activeTabs[_tabController.index]
        : null;

    final isPresent = _activeTabs.contains(tab);
    if (isPresent) {
      if (_activeTabs.length <= 1) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${context.l10n.navLibrary}: at least one tab is required'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      HapticFeedback.lightImpact();
      setState(() {
        _activeTabs.remove(tab);
        int newIndex = 0;
        if (currentTabItem != null) {
          final found = _activeTabs.indexOf(currentTabItem);
          if (found != -1) {
            newIndex = found;
          } else {
            newIndex =
                (_tabController.index - 1).clamp(0, _activeTabs.length - 1);
          }
        }
        _rebuildTabController(initialIndex: newIndex);
      });
    } else {
      HapticFeedback.mediumImpact();
      setState(() {
        _activeTabs.add(tab);

        int newIndex = 0;
        if (currentTabItem != null) {
          final found = _activeTabs.indexOf(currentTabItem);
          if (found != -1) newIndex = found;
        }
        _rebuildTabController(initialIndex: newIndex);
      });
    }

    unawaited(_persistActiveTabs());
  }

  void _onReorderTabs(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    final currentTabItem = (_tabController.index >= 0 &&
            _tabController.index < _activeTabs.length)
        ? _activeTabs[_tabController.index]
        : null;

    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _activeTabs.removeAt(oldIndex);
      _activeTabs.insert(newIndex, item);

      int newCurrentIndex = 0;
      if (currentTabItem != null) {
        final found = _activeTabs.indexOf(currentTabItem);
        if (found != -1) newCurrentIndex = found;
      }
      _rebuildTabController(initialIndex: newCurrentIndex);
    });

    unawaited(_persistActiveTabs());
  }

  Future<void> _persistActiveTabs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _activeTabsPrefKey,
        _activeTabs.map((t) => t.name).toList(),
      );
      if (_tabController.index >= 0 &&
          _tabController.index < _activeTabs.length) {
        await prefs.setString(
            _tabNamePrefKey, _activeTabs[_tabController.index].name);
        await prefs.setInt(_tabIndexPrefKey, _tabController.index);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to persist active library tabs',
          error: e, stackTrace: st, category: 'Library');
    }
  }

  void _resetDefaultTabs() {
    HapticFeedback.mediumImpact();
    setState(() {
      _activeTabs = List.from(LibraryTabItem.defaultTabs);
      _rebuildTabController(initialIndex: 0);
    });
    unawaited(_persistActiveTabs());
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
    } catch (e, st) {
      ErrorLogger.log('Failed to persist layout preference',
          error: e, stackTrace: st, category: 'Library');
    }
  }

  void _onSongsScrollNearBottom() {
    if (!_songsScrollController.hasClients) return;
    final pos = _songsScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 800) {
      try {
        context.read<LibraryCubit>().loadMoreSongs();
      } catch (e, st) {
        ErrorLogger.log('Failed to load more songs',
            error: e, stackTrace: st, category: 'Library');
      }
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
      duration: context.motionMs(250),
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
                      icon: const Icon(Icons.add_rounded),
                      tooltip: '${context.l10n.navLibrary} Tabs',
                      onPressed: () => _showManageTabsSheet(context, state),
                    ),
                    IconButton(
                      icon: Icon(state.viewMode == LibraryViewMode.list
                          ? Icons.grid_view_rounded
                          : Icons.view_list_rounded),
                      tooltip: state.viewMode == LibraryViewMode.list
                          ? context.l10n.libraryGridView
                          : context.l10n.libraryListView,
                      onPressed: cubit.toggleViewMode,
                    ),
                    IconButton(
                      icon: const Icon(Icons.sort_rounded),
                      tooltip: context.l10n.sortBy,
                      onPressed: () => SortFilterSheet.show(
                        context,
                        currentSort: state.sortBy,
                        ascending: state.ascending,
                        onApply: (sort, asc) => cubit.updateSort(sort, asc),
                      ),
                    ),
                  ],
                  bottom: TabBar(
                    key: ValueKey(
                        'library_tab_bar_${_activeTabs.map((t) => t.name).join('_')}'),
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    physics: const BouncingScrollPhysics(),
                    tabs: _activeTabs
                        .map((tab) => _buildTabItem(context, tab, state, p))
                        .toList(),
                  ),
                ),
          body: Center(
            child: ConstrainedBox(
              constraints: Adaptive.contentConstraints(context),
              child: TabBarView(
                key: ValueKey(
                    'library_tab_view_${_activeTabs.map((t) => t.name).join('_')}'),
                controller: _tabController,
                children: _activeTabs
                    .map((tab) => _buildTabView(
                        context, tab, state, cubit, playerCubit))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    LibraryTabItem tab,
    LibraryState state,
    PulsrPalette p,
  ) {
    Widget content;
    switch (tab) {
      case LibraryTabItem.songs:
        content = Text(context.l10n.songs);
        break;
      case LibraryTabItem.downloaded:
        final count = state.songs.where(isDownloadedOnlineTrack).length;
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.downloaded),
            if (count > 0) ...[
              const SizedBox(width: AppSpacing.s6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s6,
                  vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadii.r10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ),
            ],
          ],
        );
        break;
      case LibraryTabItem.albums:
        content = Text(context.l10n.albums);
        break;
      case LibraryTabItem.artists:
        content = Text(context.l10n.artists);
        break;
      case LibraryTabItem.favorites:
        content = Text(context.l10n.favorites);
        break;
      case LibraryTabItem.folders:
        content = Text(context.l10n.folders);
        break;
      case LibraryTabItem.genres:
        content = Text(context.l10n.genres);
        break;
      case LibraryTabItem.years:
        content = Text(context.l10n.years);
        break;
    }

    return Tab(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showManageTabsSheet(context, state, initialOrganizeMode: true);
        },
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }

  Widget _buildTabView(
    BuildContext context,
    LibraryTabItem tab,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    switch (tab) {
      case LibraryTabItem.songs:
        return _buildSongsTab(context, state, cubit, playerCubit);
      case LibraryTabItem.downloaded:
        return _buildDownloadedTab(context, state, cubit, playerCubit);
      case LibraryTabItem.albums:
        return _buildAlbumsTab(context, state);
      case LibraryTabItem.artists:
        return _buildArtistsTab(context, state);
      case LibraryTabItem.favorites:
        return _buildFavoritesTab(context, state, playerCubit);
      case LibraryTabItem.folders:
        return _buildFoldersTab(context);
      case LibraryTabItem.genres:
        return _buildGenresTab(context, state);
      case LibraryTabItem.years:
        return _buildYearsTab(context, state);
    }
  }

  void _showManageTabsSheet(
    BuildContext context,
    LibraryState state, {
    bool initialOrganizeMode = false,
  }) {
    bool isOrganizeMode = initialOrganizeMode;

    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setSheetState) {
            final p = modalContext.palette;
            final inactiveTabs = LibraryTabItem.values
                .where((t) => !_activeTabs.contains(t))
                .toList();

            return PulsrBottomSheetContainer(
              title: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${modalContext.l10n.navLibrary} Tabs',
                          style: TextStyle(
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          isOrganizeMode
                              ? '${_activeTabs.length} / ${LibraryTabItem.values.length} tabs • Drag to reorder'
                              : '${_activeTabs.length} / ${LibraryTabItem.values.length} tabs • Long-press to organize',
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setSheetState(() {
                        isOrganizeMode = !isOrganizeMode;
                      });
                    },
                    icon: Icon(
                      isOrganizeMode
                          ? Icons.check_rounded
                          : Icons.swap_vert_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isOrganizeMode
                          ? modalContext.l10n.done
                          : modalContext.l10n.edit,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight:
                            isOrganizeMode ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: p.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _resetDefaultTabs();
                      setSheetState(() {});
                    },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: Text(
                      modalContext.l10n.reset,
                      style: const TextStyle(fontSize: AppFontSize.label),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: p.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                    ),
                  ),
                ],
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  setSheetState(() {
                    isOrganizeMode = !isOrganizeMode;
                  });
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: AnimatedSwitcher(
                    duration: modalContext.motionMs(220),
                    child: isOrganizeMode
                        ? _buildOrganizeList(
                            modalContext,
                            sheetContext,
                            state,
                            p,
                            inactiveTabs,
                            setSheetState,
                            onToggleMode: () {
                              setSheetState(() {
                                isOrganizeMode = false;
                              });
                            },
                          )
                        : _buildTabsGrid(
                            modalContext,
                            sheetContext,
                            state,
                            setSheetState,
                            onEnterOrganize: () {
                              setSheetState(() {
                                isOrganizeMode = true;
                              });
                            },
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabsGrid(
    BuildContext modalContext,
    BuildContext sheetContext,
    LibraryState state,
    StateSetter setSheetState, {
    required VoidCallback onEnterOrganize,
  }) {
    return GridView.builder(
      key: ValueKey('tabs_grid_${_activeTabs.map((t) => t.name).join('_')}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: sheetContext.isTablet ? 3 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 74,
      ),
      itemCount: LibraryTabItem.values.length,
      itemBuilder: (_, i) {
        final item = LibraryTabItem.values[i];
        final isActive = _activeTabs.contains(item);
        return _buildTabSelectionCard(
          modalContext,
          key: ValueKey('tab_card_${item.name}_$isActive'),
          item: item,
          state: state,
          isActive: isActive,
          onToggle: () {
            _toggleTab(item);
            setSheetState(() {});
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onEnterOrganize();
          },
        );
      },
    );
  }

  Widget _buildOrganizeList(
    BuildContext modalContext,
    BuildContext sheetContext,
    LibraryState state,
    PulsrPalette p,
    List<LibraryTabItem> inactiveTabs,
    StateSetter setSheetState, {
    required VoidCallback onToggleMode,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.58,
      ),
      child: ReorderableListView.builder(
        key: ValueKey(
            'reorder_list_${_activeTabs.map((t) => t.name).join('_')}'),
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Material(
                color: Colors.transparent,
                elevation: 6,
                shadowColor: Colors.black45,
                borderRadius: BorderRadius.circular(AppRadii.r18),
                child: child,
              );
            },
            child: child,
          );
        },
        itemCount: _activeTabs.length,
        itemBuilder: (context, i) {
          final item = _activeTabs[i];
          return _buildReorderTabRow(
            modalContext,
            key: ValueKey('reorder_item_${item.name}'),
            item: item,
            state: state,
            index: i,
            p: p,
            onRemove: () {
              _toggleTab(item);
              setSheetState(() {});
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onToggleMode();
            },
          );
        },
        footer: inactiveTabs.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add_rounded,
                              size: 16, color: p.textSecondary),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            '${modalContext.l10n.navLibrary} • Inactive (${inactiveTabs.length})',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              letterSpacing: AppTracking.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...inactiveTabs.map(
                      (item) => _buildInactiveTabRow(
                        modalContext,
                        key: ValueKey('inactive_${item.name}'),
                        item: item,
                        state: state,
                        p: p,
                        onAdd: () {
                          _toggleTab(item);
                          setSheetState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
        // ignore: deprecated_member_use
        onReorder: (oldIndex, newIndex) {
          _onReorderTabs(oldIndex, newIndex);
          setSheetState(() {});
        },
      ),
    );
  }

  Widget _buildReorderTabRow(
    BuildContext context, {
    required Key key,
    required LibraryTabItem item,
    required LibraryState state,
    required int index,
    required PulsrPalette p,
    required VoidCallback onRemove,
    required VoidCallback onLongPress,
  }) {
    final itemColor = item.color(p);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(
          color: p.hairline,
          width: 1.0,
        ),
      ),
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                    end: AppSpacing.s10,
                  ),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: p.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: itemColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                ),
                child: Icon(item.icon, color: itemColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      item.subtitle(context, state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                      ),
                    ),
                  ],
                ),
              ),
              if (_activeTabs.length > 1)
                IconButton(
                  icon:
                      const Icon(Icons.remove_circle_outline_rounded, size: 20),
                  color: AppColors.error.withValues(alpha: 0.8),
                  splashRadius: 20,
                  onPressed: onRemove,
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInactiveTabRow(
    BuildContext context, {
    required Key key,
    required LibraryTabItem item,
    required LibraryState state,
    required PulsrPalette p,
    required VoidCallback onAdd,
  }) {
    final itemColor = item.color(p);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(
          color: p.hairline.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.xs,
                  end: AppSpacing.s10,
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: p.textSecondary.withValues(alpha: 0.5),
                  size: 22,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: itemColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                ),
                child: Icon(item.icon,
                    color: itemColor.withValues(alpha: 0.7), size: 20),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      item.subtitle(context, state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                color: p.accent,
                splashRadius: 20,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabSelectionCard(
    BuildContext context, {
    Key? key,
    required LibraryTabItem item,
    required LibraryState state,
    required bool isActive,
    required VoidCallback onToggle,
    required VoidCallback onLongPress,
  }) {
    final p = context.palette;
    final itemColor = item.color(p);
    final title = item.title(context);
    final subtitle = item.subtitle(context, state);

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        child: AnimatedContainer(
          duration: context.motionMs(180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: isActive
                ? itemColor.withValues(alpha: 0.12)
                : p.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.r18),
            border: Border.all(
              color: isActive ? itemColor.withValues(alpha: 0.65) : p.hairline,
              width: isActive ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: itemColor.withValues(alpha: isActive ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                ),
                child: Icon(item.icon, color: itemColor, size: 20),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive ? itemColor : p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.label,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AnimatedContainer(
                duration: context.motionMs(180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? itemColor : p.surfaceContainerHigh,
                  border: Border.all(
                    color: isActive ? itemColor : p.hairline,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isActive ? Icons.check_rounded : Icons.add_rounded,
                  size: 16,
                  color: isActive ? p.onAccent : p.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final p = context.palette;
    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
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
      borderRadius: BorderRadius.circular(AppRadii.r12),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.r12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? p.onAccent : p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.label,
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
