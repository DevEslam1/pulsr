// lib/features/settings/cubit/settings_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/scanner/media_scanner_service.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final MediaScannerService _scannerService;
  static const String _keyGapless = 'setting_gapless';
  static const String _keyCrossfade = 'setting_crossfade';
  static const String _keyMinDuration = 'setting_min_duration';
  static const String _keyDynamicTheme = 'setting_dynamic_theme';

  SettingsCubit({required MediaScannerService scannerService})
      : _scannerService = scannerService,
        super(const SettingsState()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      emit(state.copyWith(
        gaplessPlayback: prefs.getBool(_keyGapless) ?? true,
        crossfadeSeconds: prefs.getDouble(_keyCrossfade) ?? 0.0,
        minDurationSec: prefs.getInt(_keyMinDuration) ?? 30,
        dynamicThemingEnabled: prefs.getBool(_keyDynamicTheme) ?? true,
      ));
    } catch (_) {}
  }

  Future<void> setGapless(bool value) async {
    emit(state.copyWith(gaplessPlayback: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGapless, value);
  }

  Future<void> setCrossfade(double seconds) async {
    emit(state.copyWith(crossfadeSeconds: seconds));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCrossfade, seconds);
  }

  Future<void> setMinDuration(int seconds) async {
    emit(state.copyWith(minDurationSec: seconds));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinDuration, seconds);
  }

  Future<void> setDynamicTheming(bool value) async {
    emit(state.copyWith(dynamicThemingEnabled: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDynamicTheme, value);
  }

  Future<int> rescanLibrary() async {
    emit(state.copyWith(isScanning: true, scanResultCount: null));
    try {
      final count = await _scannerService.scanDeviceLibrary(
        ignoreShortFiles: state.minDurationSec > 0,
        minDurationSec: state.minDurationSec,
      );
      emit(state.copyWith(isScanning: false, scanResultCount: count));
      return count;
    } catch (e) {
      emit(state.copyWith(isScanning: false, errorMessage: e.toString()));
      return 0;
    }
  }
}
