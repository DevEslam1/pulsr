// lib/features/player/cubit/managers/player_quran_manager.dart
// FIX-A1: Modular Quran manager extracted from PlayerCubit
import '../../../../core/services/quran_mode_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../../../../domain/models/quran_style_tuning.dart';
import '../quran_restore_snapshot.dart';

/// Manages Quran Mode lifecycle, preset profiles, and DSP state snapshots.
class PlayerQuranManager {
  final QuranModeService? _service;

  PlayerQuranManager({QuranModeService? service}) : _service = service;

  QuranRestoreSnapshot? _restoreSnapshot;
  QuranRestoreSnapshot? get restoreSnapshot => _restoreSnapshot;

  void setRestoreSnapshot(QuranRestoreSnapshot? snapshot) {
    _restoreSnapshot = snapshot;
  }

  /// Runs [action] against the service. A missing service yields
  /// [whenMissing]; a throwing one is logged and yields [onError], so callers
  /// never see a preference failure as an exception.
  Future<T> _guard<T>(
    String what, {
    required T whenMissing,
    required T onError,
    required Future<T> Function(QuranModeService service) action,
  }) async {
    final service = _service;
    if (service == null) return whenMissing;
    try {
      return await action(service);
    } catch (e, st) {
      ErrorLogger.log(what,
          error: e, stackTrace: st, category: 'PlayerQuranManager');
      return onError;
    }
  }

  Future<QuranModeProfile?> restoreInitialState() => _guard(
        'Failed to restore Quran Mode profile',
        whenMissing: null,
        onError: null,
        action: (s) => s.loadActiveProfile(),
      );

  /// Persists the enabled flag. Returns false when the write failed so callers
  /// never flip the in-memory mode to a state the service did not record.
  /// A missing service is treated as a successful no-op.
  Future<bool> setEnabled(bool enabled) => _guard(
        'Failed to set Quran Mode enabled: $enabled',
        whenMissing: true,
        onError: false,
        action: (s) async {
          await s.setEnabled(enabled);
          return true;
        },
      );

  /// Returns the persisted reciter style, falling back to Mujawwad.
  Future<QuranReciterStyle> getStyle() => _guard(
        'Failed to get Quran reciter style',
        whenMissing: QuranReciterStyle.mujawwad,
        onError: QuranReciterStyle.mujawwad,
        action: (s) => s.getStyle(),
      );

  /// Persists the reciter style. Returns false when the write failed.
  Future<bool> setStyle(QuranReciterStyle style) => _guard(
        'Failed to set Quran reciter style: $style',
        whenMissing: true,
        onError: false,
        action: (s) async {
          await s.setStyle(style);
          return true;
        },
      );

  /// The user's explicit on/off choice, or `null` when they never made one.
  /// A missing service (tests, pure builds) reports "no choice".
  Future<bool?> getUserOverride() => _guard<bool?>(
        'Failed to read Quran Mode user override',
        whenMissing: null,
        onError: null,
        action: (s) => s.getUserOverride(),
      );

  /// Persists the user's explicit choice (`null` clears it). Returns false
  /// when the write failed.
  Future<bool> setUserOverride(bool? value) => _guard(
        'Failed to persist Quran Mode user override',
        whenMissing: true,
        onError: false,
        action: (s) async {
          await s.setUserOverride(value);
          return true;
        },
      );

  Future<QuranStyleTuning> getStyleTuning(QuranReciterStyle style) => _guard(
        'Failed to load Quran style tuning',
        whenMissing: const QuranStyleTuning(),
        onError: const QuranStyleTuning(),
        action: (s) => s.getStyleTuning(style),
      );

  Future<bool> setStyleTuning(
          QuranReciterStyle style, QuranStyleTuning tuning) =>
      _guard(
        'Failed to save Quran style tuning',
        whenMissing: true,
        onError: false,
        action: (s) async {
          await s.setStyleTuning(style, tuning);
          return true;
        },
      );
}