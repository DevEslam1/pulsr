import 'dart:async';
import 'package:mutex/mutex.dart';

import '../../../../core/utils/error_logger.dart';
import '../player_state.dart';
import 'dsp_slice_descriptors.dart';

/// Reconciles a failed DSP attempt against its pre-attempt snapshot, restoring
/// only the fields the attempt actually changed using table-driven descriptors.
class DspRollbackPolicy {
  const DspRollbackPolicy._();

  static DspSlice merge(
      DspSlice current, DspSlice previous, DspSlice attempted) {
    var result = current;
    for (final field in dspSliceFields) {
      result = field.rollbackIfChanged(result, previous, attempted);
    }
    return result;
  }
}

/// Applies guarded DSP mutations with unified state emission and rollback.
class DspEffectApplier {
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final void Function() _markUserInteracting;
  final bool Function(String feature, {bool showError}) _guardDsp;
  final Future<void> Function() _rebalanceVolumeBoost;
  final Mutex _mutex = Mutex();

  DspEffectApplier({
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required void Function() markUserInteracting,
    required bool Function(String feature, {bool showError}) guardDsp,
    required Future<void> Function() rebalanceVolumeBoost,
  })  : _getState = getState,
        _emit = emit,
        _markUserInteracting = markUserInteracting,
        _guardDsp = guardDsp,
        _rebalanceVolumeBoost = rebalanceVolumeBoost;

  Future<bool> apply({
    required String featureName,
    bool requiresGuard = true,
    bool guardCondition = true,
    bool showErrorOnGuard = true,
    bool rebalanceVolumeBoost = true,
    required DspSlice Function(DspSlice current) updateDsp,
    required Future<void> Function() applyAudioHandler,
    String? failureMessage,
  }) async {
    _markUserInteracting();
    if (requiresGuard &&
        guardCondition &&
        !_guardDsp(featureName, showError: showErrorOnGuard)) {
      return false;
    }
    return _mutex.protect(() async {
      final state = _getState();
      final previousDsp = state.dsp;
      final attemptedDsp = updateDsp(previousDsp);
      _emit(state.copyWith(
        dsp: attemptedDsp,
        playback: state.playback.copyWith(errorMessage: null),
      ));
      try {
        await applyAudioHandler();
        if (rebalanceVolumeBoost) {
          // Rebalancing is best-effort. The bare unawaited() call turned a
          // native failure into an unhandled zone error after the setter had
          // already succeeded, which could crash debug builds/tests.
          unawaited(_rebalanceVolumeBoost().catchError(
            (Object e, StackTrace st) {
              ErrorLogger.log('Failed to rebalance volume boost',
                  error: e, stackTrace: st, category: 'PlayerDspController');
            },
          ));
        }
        return true;
      } catch (e, st) {
        ErrorLogger.log('Failed to set $featureName',
            error: e, stackTrace: st, category: 'PlayerDspController');
        final s = _getState();
        final rolledBackDsp =
            DspRollbackPolicy.merge(s.dsp, previousDsp, attemptedDsp);
        _emit(s.copyWith(
          dsp: rolledBackDsp,
          playback: s.playback.copyWith(
            errorMessage: failureMessage ??
                'Failed to set ${featureName.toLowerCase()}: $e',
          ),
        ));
        return false;
      }
    });
  }
}
