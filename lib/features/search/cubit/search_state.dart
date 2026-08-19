// lib/features/search/cubit/search_state.dart
import '../../../data/db/app_database.dart';

class SearchState {
  final String query;
  final String selectedFilter; // 'All', 'Songs', 'Artists', 'Albums'
  final List<SongsTableData> results;
  final bool isLoading;

  const SearchState({
    this.query = '',
    this.selectedFilter = 'All',
    this.results = const [],
    this.isLoading = false,
  });

  SearchState copyWith({
    String? query,
    String? selectedFilter,
    List<SongsTableData>? results,
    bool? isLoading,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
