// lib/features/player/cubit/managers/player_quran_manager.dart
// FIX-A1: Modular Quran manager extracted from PlayerCubit
import 'dart:async';
import '../../../../core/services/quran_mode_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../domain/models/quran_mode_profile.dart';
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

  Future<QuranModeProfile?> restoreInitialState() async {
    final service = _service;
    if (service == null) return null;
    try {
      final profile = await service.loadActiveProfile();
      return profile;
    } catch (e, st) {
      ErrorLogger.log('Failed to restore Quran Mode profile',
          error: e, stackTrace: st, category: 'PlayerQuranManager');
      return null;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final service = _service;
    if (service == null) return;
    try {
      await service.setEnabled(enabled);
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran Mode enabled: $enabled',
          error: e, stackTrace: st, category: 'PlayerQuranManager');
    }
  }

  Future<void> setStyle(QuranReciterStyle style) async {
    final service = _service;
    if (service == null) return;
    try {
      await service.setStyle(style);
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran reciter style: $style',
          error: e, stackTrace: st, category: 'PlayerQuranManager');
    }
  }
}
