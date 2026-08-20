import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/song_tile.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/song_info_sheet.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _filters = ['All', 'Songs', 'Artists', 'Albums'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        final cubit = context.read<SearchCubit>();
        final playerCubit = context.read<PlayerCubit>();

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: Column(
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
                        onChanged: cubit.onQueryChanged,
                        decoration: InputDecoration(
                          hintText: 'Songs, artists, albums…',
                          prefixIcon: Icon(Icons.search_rounded, color: p.textTertiary),
                          suffixIcon: state.query.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, color: p.textTertiary),
                                  onPressed: () {
                                    _searchController.clear();
                                    cubit.clearQuery();
                                  })
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
                            for (final filter in _filters)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(filter),
                                  selected: state.selectedFilter == filter,
                                  labelStyle: TextStyle(
                                    color: state.selectedFilter == filter ? p.accent : p.textSecondary,
                                    fontWeight: state.selectedFilter == filter ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                  onSelected: (_) => cubit.setFilter(filter),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: state.isLoading
                          ? Center(child: CircularProgressIndicator(color: p.accent))
                          : state.results.isEmpty
                              ? state.query.isEmpty
                                  ? const EmptyStateWidget(
                                      icon: Icons.search_rounded,
                                      title: 'Search Your Music',
                                      subtitle: 'Find songs, artists, or albums in your local library.',
                                    )
                                  : EmptyStateWidget(
                                      icon: Icons.search_off_rounded,
                                      title: 'No Results Found',
                                      subtitle: 'No matches found for "${state.query}". Try a different search term.',
                                      primaryActionLabel: 'Clear Search',
                                      primaryActionIcon: Icons.backspace_rounded,
                                      onPrimaryAction: () {
                                        _searchController.clear();
                                        cubit.clearQuery();
                                      },
                                    )
                              : ListView(
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
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
