import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../player/cubit/player_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/cubit/ytm_search_cubit.dart';
import '../../ytm_search/cubit/ytm_search_state.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// 0 = Local Music, 1 = Online Stream
  int _selectedTab = 0;
  StreamSubscription? _settingsSub;

  bool _isOnlineAvailable(BuildContext context) {
    final offlineOnly = context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;
    return AppConfig.ytmEnabled && !offlineOnly;
  }

  static const List<String> _localFilters = ['All', 'Songs', 'Artists', 'Albums'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onControllerChanged);

    // Reset to local tab if offline-only mode gets enabled
    _settingsSub = context.read<SettingsCubit?>()?.stream.listen((settings) {
      if (settings.offlineOnlyMode && _selectedTab == 1 && mounted) {
        setState(() => _selectedTab = 0);
      }
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _searchController.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(BuildContext context, String value) {
    if (_isOnlineTab) {
      context.read<YtmSearchCubit>().onQueryChanged(value);
    } else {
      context.read<SearchCubit>().onQueryChanged(value);
    }
  }

  void _clear(BuildContext context) {
    _searchController.clear();
    if (_isOnlineTab) {
      context.read<YtmSearchCubit>().clearQuery();
    } else {
      context.read<SearchCubit>().clearQuery();
    }
  }

  bool get _isOnlineTab => AppConfig.ytmEnabled && _selectedTab == 1;

  void _onTabChanged(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    final query = _searchController.text;
    if (index == 1 && AppConfig.ytmEnabled) {
      context.read<YtmSearchCubit>().onQueryChanged(query);
    } else {
      context.read<SearchCubit>().onQueryChanged(query);
    }
  }

  void _selectLocalFilter(BuildContext context, String filter) {
    context.read<SearchCubit>().setFilter(filter);
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = _buildScaffold(context);
    if (!AppConfig.ytmEnabled) return scaffold;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<YtmSearchCubit>()),
        BlocProvider(create: (_) => getIt<YtmDownloadCubit>()),
      ],
      child: scaffold,
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final p = context.palette;
    final showOnline = _isOnlineAvailable(context);
    final currentTab = showOnline ? _selectedTab : 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: Adaptive.contentConstraints(context),
            child: BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                final playerCubit = context.read<PlayerCubit>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---------- Header ----------
                    Padding(
                      padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16, Adaptive.pagePadding(context), 0),
                      child: Text(
                        context.l10n.search,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),

                    // ---------- Segmented Tab Selector (Local vs Online) ----------
                    if (showOnline) ...[
                      const SizedBox(height: 14),
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTabButton(
                                title: context.l10n.localMusic,
                                icon: Icons.library_music_rounded,
                                isSelected: currentTab == 0,
                                p: p,
                                onTap: () => _onTabChanged(0),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildTabButton(
                                title: context.l10n.onlineStream,
                                icon: Icons.public_rounded,
                                isSelected: currentTab == 1,
                                p: p,
                                onTap: () => _onTabChanged(1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ---------- Search Input Field ----------
                    const SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => _onQueryChanged(context, value),
                        decoration: InputDecoration(
                          hintText: (showOnline && currentTab == 1)
                              ? context.l10n.searchOnline
                              : context.l10n.searchPlaceholder,
                          prefixIcon: Icon(Icons.search_rounded, color: p.textTertiary),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, color: p.textTertiary),
                                  onPressed: () => _clear(context),
                                )
                              : null,
                        ),
                      ),
                    ),

                    // ---------- Filter Chips (Local Tab Only) ----------
                    if (currentTab == 0) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              for (final filter in _localFilters)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 8),
                                  child: _buildChip(context, state, filter, p),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // ---------- Search Content Body ----------
                    Expanded(
                      child: (showOnline && currentTab == 1)
                          ? _OnlineResults(
                              onSelectTag: (tag) {
                                _searchController.text = tag;
                                _onQueryChanged(context, tag);
                              },
                            )
                          : _buildLocalBody(context, state, playerCubit, p),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required PulsrPalette p,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: p.glow.withValues(alpha: 0.35),
                    blurRadius: 10,
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
              size: 17,
              color: isSelected ? p.onAccent : p.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? p.onAccent : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFilterLabel(BuildContext context, String filter) {
    switch (filter) {
      case 'All':
        return context.l10n.all;
      case 'Songs':
        return context.l10n.songs;
      case 'Artists':
        return context.l10n.artists;
      case 'Albums':
        return context.l10n.albums;
      default:
        return filter;
    }
  }

  Widget _buildChip(BuildContext context, SearchState state, String filter, PulsrPalette p) {
    final selected = state.selectedFilter == filter;
    return ChoiceChip(
      label: Text(_getFilterLabel(context, filter)),
      selected: selected,
      labelStyle: TextStyle(
        color: selected ? p.accent : p.textSecondary,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      onSelected: (_) => _selectLocalFilter(context, filter),
    );
  }

  Widget _buildLocalBody(BuildContext context, SearchState state, PlayerCubit playerCubit, PulsrPalette p) {
    if (state.isLoading) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (state.results.isEmpty) {
      if (state.query.isEmpty) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 48, color: p.textTertiary),
                const SizedBox(height: 12),
                Text(
                  context.l10n.search,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.searchPlaceholder,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Text(
                  'QUICK DISCOVERY',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.textTertiary, letterSpacing: 1.2),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in ['Rock', 'Pop', 'Hip-Hop', 'Acoustic', 'FLAC', 'Lossless', 'Jazz', 'Electronic'])
                      ActionChip(
                        label: Text(tag),
                        backgroundColor: p.surfaceContainer,
                        side: BorderSide(color: p.hairline),
                        labelStyle: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w700),
                        onPressed: () {
                          _searchController.text = tag;
                          _onQueryChanged(context, tag);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: context.l10n.noResultsFound,
        subtitle: context.l10n.noResultsSubtitle,
        primaryActionLabel: context.l10n.clearSearchHistory,
        primaryActionIcon: Icons.backspace_rounded,
        onPrimaryAction: () => _clear(context),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 160, top: 4),
      children: [
        for (final song in state.results)
          SongTile(
            song: song,
            subtitleOverride: '${song.artist} • ${song.album}',
            onTap: () => playerCubit.playSong(song, queue: state.results),
            onMorePressed: () => showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => SongInfoSheet(song: song),
            ),
          ),
      ],
    );
  }
}

/// The "Online" tab body: live YouTube Music results with per-row download
/// controls. Only ever mounted in an ENABLE_YTM build, under the
/// [YtmSearchCubit] / [YtmDownloadCubit] providers created by [SearchScreen].
class _OnlineResults extends StatelessWidget {
  final ValueChanged<String>? onSelectTag;

  const _OnlineResults({this.onSelectTag});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return BlocBuilder<YtmSearchCubit, YtmSearchState>(
      builder: (context, state) {
        if (state.isLoading) {
          return Center(child: CircularProgressIndicator(color: p.accent));
        }

        if (state.errorMessage != null) {
          return EmptyStateWidget(
            icon: Icons.cloud_off_rounded,
            title: 'Search Failed',
            subtitle: state.errorMessage!,
            primaryActionLabel: 'Try Again',
            primaryActionIcon: Icons.refresh_rounded,
            onPrimaryAction: context.read<YtmSearchCubit>().retry,
          );
        }

        if (state.results.isEmpty) {
          if (state.hasSearched) {
            return EmptyStateWidget(
              icon: Icons.search_off_rounded,
              title: 'No Results Found',
              subtitle: 'No YouTube Music matches for "${state.query.trim()}".',
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore_rounded, size: 48, color: p.textTertiary),
                  const SizedBox(height: 12),
                  Text(
                    'Search YouTube Music',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Stream and download millions of songs from YouTube Music, ad-free.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'POPULAR SEARCHES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.textTertiary, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final tag in ['Top Hits', 'Trending', 'Lo-Fi Beats', 'Pop', 'Hip-Hop', 'Rock Classics', 'Chillout', 'Electronic'])
                        ActionChip(
                          label: Text(tag),
                          backgroundColor: p.surfaceContainer,
                          side: BorderSide(color: p.hairline),
                          labelStyle: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w700),
                          onPressed: () => onSelectTag?.call(tag),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        final songs = [for (final track in state.results) track.toSongData()];
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 160, top: 4),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return SongTile(
              song: song,
              subtitleOverride: state.results[index].artist,
              onTap: () => playerCubit.playSong(song, queue: songs),
              trailing: YtmDownloadButton(song: song),
            );
          },
        );
      },
    );
  }
}
