// F8: Multi-output routing (A2DP + speaker simultaneously).
import 'dart:async';
import 'package:flutter/services.dart';

enum MultiOutputMode { systemDefault, speakerAndBluetooth, speakerOnly, bluetoothOnly }

/// Best-effort simultaneous routing. Android has no public API for true
/// concurrent A2DP + speaker; we attempt the vendor route via the audio
/// effects channel and always degrade gracefully to system default.
class MultiOutputRouter {
  static const MethodChannel _channel =
      MethodChannel('com.pulsr.music/audio_effects');

  MultiOutputMode mode = MultiOutputMode.systemDefault;
  bool lastRouteSupported = true;
  String? lastError;

  final StreamController<MultiOutputMode> _changeSubject =
      StreamController<MultiOutputMode>.broadcast();
  Stream<MultiOutputMode> get changes => _changeSubject.stream;

  Future<bool> setMode(MultiOutputMode next) async {
    mode = next;
    if (!_changeSubject.isClosed) _changeSubject.add(next);
    if (next == MultiOutputMode.systemDefault) {
      lastRouteSupported = true;
      lastError = null;
      return true;
    }
    try {
      final result = await _channel.invokeMethod<String>('setMultiOutputRoute', {
        'mode': next.name,
      }).timeout(const Duration(seconds: 3));
      lastRouteSupported = result != 'unsupported';
      lastError = lastRouteSupported ? null : 'unsupported';
      return lastRouteSupported;
    } on MissingPluginException catch (e) {
      lastRouteSupported = false;
      lastError = e.toString();
      return false;
    } catch (e) {
      // Timeout / platform errors: keep playback alive on system default.
      lastRouteSupported = false;
      lastError = e.toString();
      return false;
    }
  }

  bool get isSimultaneous => mode == MultiOutputMode.speakerAndBluetooth;

  void dispose() => _changeSubject.close();
}
