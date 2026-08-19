// lib/features/search/presentation/search_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state_widget.dart';
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
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        final cubit = context.read<SearchCubit>();
        final playerCubit = context.read<PlayerCubit>();

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Search',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: Column(
            children: [
              // Search Input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => cubit.onQueryChanged(val),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                    suffixIcon: state.query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              cubit.clearQuery();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.cardRadius,
                      borderSide: BorderSide(color: AppColors.outline),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: AppRadii.cardRadius,
                      borderSide: BorderSide(color: AppColors.outline),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: AppRadii.cardRadius,
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ),

              // Filter Chips
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filters.length,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final isSelected = state.selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        selectedColor: AppColors.primary.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            cubit.setFilter(filter);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Results List
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120, top: 4),
                            itemCount: state.results.length,
                            itemBuilder: (context, index) {
                              final song = state.results[index];
                              return ListTile(
                                leading: CachedArtwork(id: song.id, type: ArtworkType.AUDIO, size: 44, borderRadius: 10),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                subtitle: Text(
                                  '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (_) => SongInfoSheet(song: song),
                                    );
                                  },
                                ),
                                onTap: () {
                                  playerCubit.playSong(song, queue: state.results);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
