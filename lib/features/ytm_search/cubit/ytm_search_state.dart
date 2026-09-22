// lib/features/ytm_search/cubit/ytm_search_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../domain/models/ytm_track.dart';

part 'ytm_search_state.freezed.dart';

enum SearchPhase {
  idle,
  debouncing,
  fetching,
  displaying,
  error;

  bool get isTerminal => this == displaying || this == error;
}

@freezed
abstract class YtmSearchState with _$YtmSearchState {
  const YtmSearchState._();

  const factory YtmSearchState({
    @Default('') String query,
    @Default([]) List<YtmTrack> results,
    @Default(false) bool isLoading,
    String? errorMessage,
  }) = _YtmSearchState;

  bool get hasSearched => query.trim().isNotEmpty;

  SearchPhase get phase {
    if (errorMessage != null && errorMessage!.isNotEmpty) return SearchPhase.error;
    if (isLoading) return SearchPhase.fetching;
    if (results.isNotEmpty) return SearchPhase.displaying;
    if (query.trim().isNotEmpty) return SearchPhase.debouncing;
    return SearchPhase.idle;
  }
}
