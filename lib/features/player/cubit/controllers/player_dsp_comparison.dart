// lib/features/player/cubit/controllers/player_dsp_comparison.dart
part of 'player_dsp_controller.dart';

/// A/B comparison, band-count mode, comparison-slot switching, and preset
/// import/export — the EQ comparison & preset-I/O surface of the DSP
/// controller. Split out of player_dsp_controller.dart (pure code movement, no
/// behaviour change) to keep that file focused and within the controller size
/// budget. Lives in the same library (`part of`), so it can read the private
/// `_abRevertTimer` field and the shared `_audioHandler` / `_getState` / `_emit`
/// members directly.
extension PlayerDspComparisonExtension on PlayerDspController {
  Future<void> startAbComparison() async {
    _abRevertTimer?.cancel();
    _abRevertTimer = Timer(const Duration(seconds: 10), () {
      endAbComparison().catchError((Object e, StackTrace st) {
        ErrorLogger.log('Auto-end A/B comparison failed',
            error: e, stackTrace: st, category: 'PlayerDspComparison');
      });
    });
    return _audioHandler.startAbComparison();
  }

  Future<void> endAbComparison() {
    _abRevertTimer?.cancel();
    _abRevertTimer = null;
    return _audioHandler.endAbComparison();
  }

  Future<void> setBandMode(int count) async {
    if (!guardDsp('Equalizer Band Mode')) return;
    try {
      if (count == 10 || count == 32) {
        await _audioHandler.set32BandMode(count == 32);
      } else if (count == 64) {
        await _audioHandler.equalizerManager.setBandMode(64);
      } else {
        return;
      }
      final state = _getState();
      _emit(state.copyWith(
          dsp: state.dsp.copyWith(
        eqPreset: _audioHandler.currentPreset,
        selectedHeadphoneProfile: null,
      )));
    } catch (e, st) {
      ErrorLogger.log('Failed to set band mode',
          error: e, stackTrace: st, category: 'PlayerDspComparison');
    }
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    try {
      await _audioHandler.switchComparisonSlot(slot);
      final state = _getState();
      _emit(state.copyWith(
          dsp: state.dsp.copyWith(
        eqPreset: _audioHandler.currentPreset,
        selectedHeadphoneProfile: null,
      )));
    } catch (e, st) {
      ErrorLogger.log('Failed to switch comparison slot',
          error: e, stackTrace: st, category: 'PlayerDspComparison');
    }
  }

  String exportPresetToJson() => _audioHandler.exportPresetToJson();

  Future<bool> importPresetFromJson(String jsonStr) async {
    if (!guardDsp('Equalizer Preset')) return false;
    try {
      final ok = await _audioHandler.importPresetFromJson(jsonStr);
      if (ok) {
        final state = _getState();
        _emit(state.copyWith(
            dsp: state.dsp.copyWith(
          eqPreset: _audioHandler.currentPreset,
          selectedHeadphoneProfile: null,
        )));
      }
      return ok;
    } catch (e, st) {
      ErrorLogger.log('Failed to import preset from JSON',
          error: e, stackTrace: st, category: 'PlayerDspComparison');
      return false;
    }
  }
}
