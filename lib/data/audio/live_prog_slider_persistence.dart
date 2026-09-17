// Serialization for LiveProg slider positions.
//
// Kept out of EqualizerManager (a size-ratcheted file) and unit-tested through
// the manager's public round-trip. Values are validated the same way live input
// is: index 1..8 and a finite double, so corrupt or stale JSON can never seed
// the native engine with an out-of-range value.
import 'dart:convert';

import '../../core/utils/error_logger.dart';

String encodeLiveProgSliders(Map<int, double> sliders) =>
    jsonEncode(sliders.map((k, v) => MapEntry(k.toString(), v)));

/// Native LiveProg::setSlider only honors 1..8; anything else is dropped there
/// while the Dart mirror would keep it — reject up front so the two never
/// diverge.
bool isValidLiveProgSlider(int index, double value) {
  if (index < 1 || index > 8) {
    ErrorLogger.log('Rejected LiveProg slider index $index (valid 1..8)',
        category: 'EqualizerManager');
    return false;
  }
  if (!value.isFinite) {
    ErrorLogger.log('Rejected non-finite LiveProg slider value for index $index',
        category: 'EqualizerManager');
    return false;
  }
  return true;
}

Map<int, double> decodeLiveProgSliders(String? raw) {
  final result = <int, double>{};
  if (raw == null || raw.isEmpty) return result;
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    decoded.forEach((key, value) {
      final index = int.tryParse(key);
      final sliderValue = (value as num?)?.toDouble();
      if (index != null &&
          index >= 1 &&
          index <= 8 &&
          sliderValue != null &&
          sliderValue.isFinite) {
        result[index] = sliderValue;
      }
    });
  } catch (e, st) {
    ErrorLogger.log('Failed to restore LiveProg sliders',
        error: e, stackTrace: st, category: 'EqualizerManager');
  }
  return result;
}
