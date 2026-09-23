// lib/features/smart_playlist_builder/smart_playlist_builder_cubit.dart
import 'dart:async';
import 'package:injectable/injectable.dart';
import '../../core/bloc/base_cubit.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/smart_playlist_criteria.dart';
import '../../domain/repositories/smart_playlist_engine_interface.dart';
import '../../domain/usecases/playlist_usecases.dart';
import 'smart_playlist_builder_state.dart';

// FIX-A01: Migrate to PulsrCubit
@injectable
class SmartPlaylistBuilderCubit extends PulsrCubit<SmartPlaylistBuilderState> {
  final ISmartPlaylistEngine _engine;
  final PlaylistUseCases _playlistUseCases;
  StreamSubscription? _previewSub;
  Timer? _debounceTimer;
  // FIX-H3: Generation counter to discard stale preview results
  int _previewGen = 0;

  /// The live preview is capped so a rule set that matches the entire library
  /// cannot materialize every row into memory (OOM risk on large libraries).
  static const int previewCap = 100;

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

  /// Replaces the current rule set with a preset template.
  void applyTemplate(SmartCriteria template) {
    safeEmit(state.copyWith(criteria: template));
    _updatePreview();
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
    _debounceTimer?.cancel();
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 150), () {
      unawaited(_executePreview());
    }));
  }

  Future<void> _executePreview() async {
    if (isClosed) return;
    _debounceTimer?.cancel();
    final oldSub = _previewSub;
    _previewSub = null;
    if (oldSub != null) {
      removeFromComposite(oldSub);
      // FIX-H3 / H-09: Await cancellation before subscribing so the previous
      // stream cannot fire one more stale preview into the new generation.
      await oldSub.cancel();
    }
    if (isClosed) return;
    final gen = ++_previewGen;

    final queryLimit = (state.criteria.limit == null || state.criteria.limit! > previewCap)
        ? previewCap + 1
        : state.criteria.limit;
    
    final previewCriteria = state.criteria.copyWith(limit: queryLimit);

    _previewSub = autoSub(
      _engine.watchCriteria(previewCriteria),
      (songs) {
        // FIX-H3: Guard against superseded generation
        if (isClosed || gen != _previewGen) return;
        // Simplified truncation check: any query returning > previewCap is truncated
        final truncated = songs.length > previewCap;
        final visible = songs.take(previewCap).toList();
        safeEmit(state.copyWith(
          previewSongs: visible,
          previewTruncated: truncated,
        ));
      },
      onError: (e, st) {
        if (isClosed || gen != _previewGen) return;
        ErrorLogger.log('Smart playlist preview query failed',
            error: e, stackTrace: st, category: 'SmartPlaylist');
        safeEmit(state.copyWith(previewSongs: [], previewTruncated: false));
      },
    );
  }

  Future<bool> savePlaylist() async {
    final name = state.name.trim();
    if (name.isEmpty) {
      safeEmit(state.copyWith(errorMessage: 'Please enter a playlist name'));
      return false;
    }

    if (state.criteria.rules.isEmpty) {
      safeEmit(state.copyWith(errorMessage: 'Please add at least one rule'));
      return false;
    }

    for (int i = 0; i < state.criteria.rules.length; i++) {
      final rule = state.criteria.rules[i];
      if (rule.value.trim().isEmpty) {
        safeEmit(state.copyWith(errorMessage: 'Please enter a value for rule #${i + 1}'));
        return false;
      }
    }

    safeEmit(state.copyWith(isSubmitting: true, errorMessage: null));

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
    } catch (e, st) {
      ErrorLogger.log('Failed to save smart playlist',
          error: e, stackTrace: st, category: 'SmartPlaylist');
      return _finishSave(false, 'Could not save the playlist. Please try again.');
    }
  }

  bool _finishSave(bool succeeded, String? failureMessage) {
    if (!isClosed) {
      safeEmit(state.copyWith(
        isSubmitting: false,
        errorMessage: succeeded ? null : failureMessage,
      ));
    }
    return succeeded;
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _previewSub?.cancel();
    return super.close();
  }
}
