// lib/features/smart_playlist_builder/smart_playlist_builder_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/errors/app_error.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/smart_playlist_criteria.dart';

part 'smart_playlist_builder_state.freezed.dart';

@freezed
abstract class SmartPlaylistBuilderState with _$SmartPlaylistBuilderState {
  const SmartPlaylistBuilderState._();

  const factory SmartPlaylistBuilderState({
    @Default('') String name,
    @Default(SmartCriteria()) SmartCriteria criteria,
    @Default([]) List<SongsTableData> previewSongs,
    @Default(false) bool previewTruncated,
    @Default(false) bool isSubmitting,
    @Default(false) bool isEditing,
    int? editingPlaylistId,
    AppError? error,
  }) = _SmartPlaylistBuilderState;

  /// Display copy for the typed failure (existing UI contract).
  String? get errorMessage => error?.userMessage;
}
