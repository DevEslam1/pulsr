// lib/features/ytm_search/cubit/ytm_search_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/errors/app_error.dart';
import '../../../domain/models/ytm_track.dart';

part 'ytm_search_state.freezed.dart';

enum SearchPhase {
  idle,
  debouncing,
  fetching,
  displaying,
  noResults,
  error;

  bool get isTerminal =>
      this == displaying || this == noResults || this == error;
}

@freezed
abstract class YtmSearchState with _$YtmSearchState {
  const YtmSearchState._();

  const factory YtmSearchState({
    @Default('') String query,
    @Default([]) List<YtmTrack> results,
    @Default(false) bool isLoading,
    @Default(false) bool hasSearched,
    @Default(false) bool loadMoreFailed,
    AppError? error,
  }) = _YtmSearchState;

  /// Display copy for the typed failure (existing UI contract).
  String? get errorMessage => error?.userMessage;

  SearchPhase get phase {
    final message = error?.userMessage;
    if (message != null && message.isNotEmpty) {
      return SearchPhase.error;
    }
    if (isLoading) return SearchPhase.fetching;
    if (results.isNotEmpty) return SearchPhase.displaying;
    if (hasSearched) return SearchPhase.noResults;
    if (query.trim().isNotEmpty) return SearchPhase.debouncing;
    return SearchPhase.idle;
  }
}
