import 'dart:typed_data';

/// Stub for platforms without `dart:ffi` (e.g. Web). Returning `null` tells
/// [DopEncoder] to use its pure-Dart fallback.
Uint8List? encodeDopPlanarNative({
  required Uint8List dsdLeft,
  required Uint8List dsdRight,
  required int containerBits,
  required bool reverseBits,
  required int firstMarker,
}) =>
    null;

void setDopNativeLibraryPathForTesting(String? path) {}
