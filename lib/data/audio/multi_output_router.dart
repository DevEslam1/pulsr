// F8: Multi-output routing (A2DP + speaker simultaneously).
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/constants/channels.dart';

enum MultiOutputMode {
  systemDefault,
  speakerAndBluetooth,
  speakerOnly,
  bluetoothOnly
}

/// Best-effort simultaneous routing. Android has no public API for true
/// concurrent A2DP + speaker; we attempt the vendor route via the audio
/// effects channel and always degrade gracefully to system default.
class MultiOutputRouter {
  static const MethodChannel _channel =
      MethodChannel(PulsrChannels.audioEffects);

  MultiOutputMode mode = MultiOutputMode.systemDefault;
  bool lastRouteSupported = true;
  String? lastError;

  final StreamController<MultiOutputMode> _changeSubject =
      StreamController<MultiOutputMode>.broadcast();
  Stream<MultiOutputMode> get changes => _changeSubject.stream;

  Future<bool> setMode(MultiOutputMode next) async {
    final previous = mode;
    try {
      final result =
          await _channel.invokeMethod<String>('setMultiOutputRoute', {
        'mode': next.name,
      }).timeout(const Duration(seconds: 3));
      if (result == 'unsupported' && next != MultiOutputMode.systemDefault) {
        mode = previous;
        lastRouteSupported = false;
        lastError = 'unsupported';
        return false;
      }
      mode = next;
      lastRouteSupported = true;
      lastError = null;
      if (!_changeSubject.isClosed) _changeSubject.add(next);
      return true;
    } on MissingPluginException catch (e) {
      if (next == MultiOutputMode.systemDefault) {
        mode = next;
        lastRouteSupported = true;
        lastError = null;
        if (!_changeSubject.isClosed) _changeSubject.add(next);
        return true;
      }
      mode = previous;
      lastRouteSupported = false;
      lastError = e.toString();
      return false;
    } catch (e) {
      // Timeout / platform errors: keep playback alive on the last known route,
      // except systemDefault resets local tracking gracefully as documented.
      if (next == MultiOutputMode.systemDefault) {
        mode = next;
        lastRouteSupported = true;
        lastError = e.toString();
        if (!_changeSubject.isClosed) _changeSubject.add(next);
        return true;
      }
      mode = previous;
      lastRouteSupported = false;
      lastError = e.toString();
      return false;
    }
  }

  bool get isSimultaneous => mode == MultiOutputMode.speakerAndBluetooth;

  void dispose() => _changeSubject.close();
}
