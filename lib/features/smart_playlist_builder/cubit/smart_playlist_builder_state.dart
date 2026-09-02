// lib/features/smart_playlist_builder/cubit/smart_playlist_builder_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/smart_playlist_criteria.dart';

part 'smart_playlist_builder_state.freezed.dart';

@freezed
abstract class SmartPlaylistBuilderState with _$SmartPlaylistBuilderState {
  const factory SmartPlaylistBuilderState({
    @Default('') String name,
    @Default(SmartCriteria()) SmartCriteria criteria,
    @Default([]) List<SongsTableData> previewSongs,
    @Default(false) bool isSubmitting,
    @Default(false) bool isEditing,
    int? editingPlaylistId,
    String? errorMessage,
  }) = _SmartPlaylistBuilderState;
}

