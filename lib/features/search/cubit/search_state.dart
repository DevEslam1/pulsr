// lib/features/search/cubit/search_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/errors/app_error.dart';
import '../../../data/db/app_database.dart';

part 'search_state.freezed.dart';

@freezed
abstract class SearchState with _$SearchState {
  const SearchState._();

  const factory SearchState({
    @Default('') String query,
    @Default('All') String selectedFilter,
    @Default([]) List<SongsTableData> results,
    @Default(false) bool isLoading,
    @Default([]) List<String> history,
    AppError? error,
  }) = _SearchState;

  /// Display copy for the typed failure (existing UI contract).
  String? get errorMessage => error?.userMessage;
}
