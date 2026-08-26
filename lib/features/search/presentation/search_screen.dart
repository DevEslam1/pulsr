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

  /// Whether the "Online" chip is active. Can only ever be true in an
  /// ENABLE_YTM build, since that is the only build where the chip is shown.
  bool _onlineMode = false;

  bool _isOnlineAvailable(BuildContext context) {
    final offlineOnly = context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;
    return AppConfig.ytmEnabled && !offlineOnly;
  }

  List<String> _filters(BuildContext context) => _isOnlineAvailable(context)
      ? const ['All', 'Songs', 'Artists', 'Albums', 'Online']
      : const ['All', 'Songs', 'Artists', 'Albums'];

  @override
  void initState() {
    super.initState();
    // Drive the clear button off the field itself so it stays correct in online
    // mode too, where keystrokes are routed to YtmSearchCubit and never touch
    // SearchState.query.
    _searchController.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(BuildContext context, String value) {
    if (AppConfig.ytmEnabled && _onlineMode) {
      context.read<YtmSearchCubit>().onQueryChanged(value);
    } else {
      context.read<SearchCubit>().onQueryChanged(value);
    }
  }

  void _clear(BuildContext context) {
    _searchController.clear();
    if (AppConfig.ytmEnabled && _onlineMode) {
      context.read<YtmSearchCubit>().clearQuery();
    } else {
      context.read<SearchCubit>().clearQuery();
    }
  }

  void _selectFilter(BuildContext context, String filter) {
    final query = _searchController.text;
    if (AppConfig.ytmEnabled && filter == 'Online') {
      if (_onlineMode) return;
      setState(() => _onlineMode = true);
      context.read<YtmSearchCubit>().onQueryChanged(query);
      return;
    }
    if (_onlineMode) setState(() => _onlineMode = false);
    final cubit = context.read<SearchCubit>();
    // Carry over anything typed while browsing online, then apply the filter.
    if (cubit.state.query != query) cubit.onQueryChanged(query);
    cubit.setFilter(filter);
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
                    Padding(
                      padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16, Adaptive.pagePadding(context), 12),
                      child: Text('Search', style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context)),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => _onQueryChanged(context, value),
                        decoration: InputDecoration(
                          hintText: (AppConfig.ytmEnabled && _onlineMode)
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
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Adaptive.pagePadding(context), vertical: 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (final filter in _filters(context))
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: _buildChip(context, state, filter, p),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: (_isOnlineAvailable(context) && _onlineMode)
                          ? const _OnlineResults()
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

  Widget _buildChip(BuildContext context, SearchState state, String filter, PulsrPalette p) {
    final selected = filter == 'Online' ? _onlineMode : (!_onlineMode && state.selectedFilter == filter);
    return ChoiceChip(
      label: Text(filter),
      selected: selected,
      labelStyle: TextStyle(
        color: selected ? p.accent : p.textSecondary,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      onSelected: (_) => _selectFilter(context, filter),
    );
  }

  Widget _buildLocalBody(BuildContext context, SearchState state, PlayerCubit playerCubit, PulsrPalette p) {
    if (state.isLoading) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (state.results.isEmpty) {
      return state.query.isEmpty
          ? EmptyStateWidget(
              icon: Icons.search_rounded,
              title: context.l10n.search,
              subtitle: context.l10n.searchPlaceholder,
            )
          : EmptyStateWidget(
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
  const _OnlineResults();

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
          return state.hasSearched
              ? EmptyStateWidget(
                  icon: Icons.search_off_rounded,
                  title: 'No Results Found',
                  subtitle: 'No YouTube Music matches for "${state.query.trim()}".',
                )
              : const EmptyStateWidget(
                  icon: Icons.travel_explore_rounded,
                  title: 'Search YouTube Music',
                  subtitle: 'Stream and download songs from YouTube Music, ad-free.',
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
