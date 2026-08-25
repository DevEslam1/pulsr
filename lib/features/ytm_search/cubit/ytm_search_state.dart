// lib/features/ytm_search/cubit/ytm_search_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../domain/models/ytm_track.dart';

part 'ytm_search_state.freezed.dart';

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
}
