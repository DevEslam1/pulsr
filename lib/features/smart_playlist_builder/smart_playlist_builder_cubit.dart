// lib/features/smart_playlist_builder/smart_playlist_builder_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/smart_playlist_criteria.dart';
import '../../domain/repositories/smart_playlist_engine_interface.dart';
import '../../domain/usecases/playlist_usecases.dart';
import 'smart_playlist_builder_state.dart';

@injectable
class SmartPlaylistBuilderCubit extends Cubit<SmartPlaylistBuilderState> {
  final ISmartPlaylistEngine _engine;
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription? _previewSub;

  SmartPlaylistBuilderCubit(this._engine, this._playlistUseCases)
      : super(const SmartPlaylistBuilderState()) {
    // Initialize with default initial rule
    addRule(const SmartRule(
      field: SmartRuleField.playCount,
      operator: SmartOperator.greaterThan,
      value: '0',
    ));
  }

  void initWithPlaylist(PlaylistsTableData playlist) {
    final criteria = playlist.smartCriteria != null
        ? SmartCriteria.fromJsonString(playlist.smartCriteria!)
        : const SmartCriteria();
    emit(state.copyWith(
      name: playlist.name,
      criteria: criteria,
      isEditing: true,
      editingPlaylistId: playlist.id,
    ));
    _updatePreview();
  }

  void updateName(String name) {
    emit(state.copyWith(name: name));
  }

  void toggleMatchAll(bool matchAll) {
    final newCriteria = state.criteria.copyWith(matchAll: matchAll);
    emit(state.copyWith(criteria: newCriteria));
    _updatePreview();
  }

  void setLimit(int? limit) {
    final newCriteria = state.criteria.copyWith(limit: limit);
    emit(state.copyWith(criteria: newCriteria));
    _updatePreview();
  }

  void setSortBy(String? sortBy, {bool? sortAscending}) {
    final newCriteria = state.criteria.copyWith(
      sortBy: sortBy,
      sortAscending: sortAscending ?? state.criteria.sortAscending,
    );
    emit(state.copyWith(criteria: newCriteria));
    _updatePreview();
  }

  void addRule(SmartRule rule) {
    final rules = List<SmartRule>.from(state.criteria.rules)..add(rule);
    emit(state.copyWith(criteria: state.criteria.copyWith(rules: rules)));
    _updatePreview();
  }

  void updateRule(int index, SmartRule rule) {
    if (index < 0 || index >= state.criteria.rules.length) return;
    final rules = List<SmartRule>.from(state.criteria.rules);
    rules[index] = rule;
    emit(state.copyWith(criteria: state.criteria.copyWith(rules: rules)));
    _updatePreview();
  }

  void removeRule(int index) {
    if (index < 0 || index >= state.criteria.rules.length) return;
    final rules = List<SmartRule>.from(state.criteria.rules)..removeAt(index);
    emit(state.copyWith(criteria: state.criteria.copyWith(rules: rules)));
    _updatePreview();
  }

  void _updatePreview() {
    _previewSub?.cancel();
    _previewSub = _engine.watchCriteria(state.criteria).listen(
      (songs) {
        if (isClosed) return;
        emit(state.copyWith(previewSongs: songs));
      },
      onError: (_) {
        if (isClosed) return;
        emit(state.copyWith(previewSongs: []));
      },
    );
  }

  Future<bool> savePlaylist() async {
    final name = state.name.trim();
    if (name.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please enter a playlist name'));
      return false;
    }

    emit(state.copyWith(isSubmitting: true, errorMessage: null));

    try {
      if (state.isEditing && state.editingPlaylistId != null) {
        final res = await _playlistUseCases.updateSmartPlaylist(
          state.editingPlaylistId!,
          name,
          state.criteria.toJsonString(),
        );
        return _finishSave(res.isRight(), res.getLeft().toNullable()?.message);
      }
      final res = await _playlistUseCases.createPlaylist(
        name,
        isSmart: true,
        smartCriteria: state.criteria.toJsonString(),
      );
      return _finishSave(res.isRight(), res.getLeft().toNullable()?.message);
    } catch (_) {
      return _finishSave(false, 'Could not save the playlist. Please try again.');
    }
  }

  bool _finishSave(bool succeeded, String? failureMessage) {
    if (!isClosed) {
      emit(state.copyWith(
        isSubmitting: false,
        errorMessage: succeeded ? null : failureMessage,
      ));
    }
    return succeeded;
  }

  @override
  Future<void> close() {
    _previewSub?.cancel();
    return super.close();
  }
}
