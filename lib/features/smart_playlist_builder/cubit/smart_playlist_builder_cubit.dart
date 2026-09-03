// lib/features/smart_playlist_builder/cubit/smart_playlist_builder_cubit.dart
import 'dart:async';
import '../../../core/bloc/base_cubit.dart';
import 'package:injectable/injectable.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import '../../../domain/repositories/smart_playlist_engine_interface.dart';
import '../../../domain/usecases/playlist_usecases.dart';
import 'smart_playlist_builder_state.dart';

@injectable
class SmartPlaylistBuilderCubit extends PulsrCubit<SmartPlaylistBuilderState> {
  final ISmartPlaylistEngine _engine;
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription<void>? _previewSub;

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
    safeEmit(state.copyWith(
      name: playlist.name,
      criteria: criteria,
      isEditing: true,
      editingPlaylistId: playlist.id,
    ));
    _updatePreview();
  }

  void updateName(String name) {
    safeEmit(state.copyWith(name: name));
  }

  void toggleMatchAll(bool matchAll) {
    final newCriteria = state.criteria.copyWith(matchAll: matchAll);
    safeEmit(state.copyWith(criteria: newCriteria));
    _updatePreview();
  }

  void setLimit(int? limit) {
    final newCriteria = state.criteria.copyWith(limit: limit);
    safeEmit(state.copyWith(criteria: newCriteria));
    _updatePreview();
  }

  void setSortBy(String? sortBy, {bool? sortAscending}) {
    final newCriteria = state.criteria.copyWith(
      sortBy: sortBy,
      sortAscending: sortAscending ?? state.criteria.sortAscending,
    );
    safeEmit(state.copyWith(criteria: newCriteria));
    _updatePreview();
  }

  void addRule(SmartRule rule) {
    final rules = List<SmartRule>.from(state.criteria.rules)..add(rule);
    safeEmit(state.copyWith(criteria: state.criteria.copyWith(rules: rules)));
    _updatePreview();
  }

  void updateRule(int index, SmartRule rule) {
    if (index < 0 || index >= state.criteria.rules.length) return;
    final rules = List<SmartRule>.from(state.criteria.rules);
    rules[index] = rule;
    safeEmit(state.copyWith(criteria: state.criteria.copyWith(rules: rules)));
    _updatePreview();
  }

  void removeRule(int index) {
    if (index < 0 || index >= state.criteria.rules.length) return;
    final rules = List<SmartRule>.from(state.criteria.rules)..removeAt(index);
    safeEmit(state.copyWith(criteria: state.criteria.copyWith(rules: rules)));
    _updatePreview();
  }

  void _updatePreview() {
    _previewSub?.cancel();
    removeFromComposite(_previewSub);
    _previewSub = autoSub<List<SongsTableData>>(
      _engine.watchCriteria(state.criteria),
      (songs) {
        if (isClosed) return;
        safeEmit(state.copyWith(previewSongs: songs));
      },
      onError: (Object e, StackTrace st) {
        if (isClosed) return;
        safeEmit(state.copyWith(previewSongs: []));
      },
    );
  }

  Future<bool> savePlaylist() async {
    final name = state.name.trim();
    if (name.isEmpty) {
      safeEmit(state.copyWith(errorMessage: 'Please enter a playlist name'));
      return false;
    }
    if (name.length > 100) {
      safeEmit(state.copyWith(
          errorMessage: 'Playlist name cannot exceed 100 characters'));
      return false;
    }
    if (state.criteria.limit != null && state.criteria.limit! <= 0) {
      safeEmit(state.copyWith(errorMessage: 'Limit must be positive'));
      return false;
    }

    safeEmit(state.copyWith(isSubmitting: true, errorMessage: null));

    try {
      if (state.isEditing && state.editingPlaylistId != null) {
        final res = await _playlistUseCases.updateSmartPlaylist(
          state.editingPlaylistId!,
          name,
          state.criteria.toJsonString(),
        );
        if (isClosed) return false;
        final ok = res.fold(
          (f) {
            safeEmit(
                state.copyWith(isSubmitting: false, errorMessage: f.message));
            return false;
          },
          (_) {
            safeEmit(state.copyWith(isSubmitting: false));
            return true;
          },
        );
        return ok;
      } else {
        final res = await _playlistUseCases.createPlaylist(
          name,
          isSmart: true,
          smartCriteria: state.criteria.toJsonString(),
        );
        if (isClosed) return false;
        final ok = res.fold(
          (f) {
            safeEmit(
                state.copyWith(isSubmitting: false, errorMessage: f.message));
            return false;
          },
          (_) {
            safeEmit(state.copyWith(isSubmitting: false));
            return true;
          },
        );
        return ok;
      }
    } catch (e) {
      if (!isClosed) {
        safeEmit(state.copyWith(
            isSubmitting: false, errorMessage: 'Failed to save: $e'));
      }
      return false;
    }
  }

}


