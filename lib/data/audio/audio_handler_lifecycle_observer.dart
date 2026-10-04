// lib/data/audio/audio_handler_lifecycle_observer.dart
import 'package:flutter/widgets.dart';

class AudioHandlerLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onBackground;
  final VoidCallback? onResume;
  final VoidCallback? onDetached;
  final VoidCallback? onHidden;

  /// Flutter 3.13+ walks inactive -> hidden -> paused (and finally detached)
  /// when the app leaves the foreground. Without this latch [onBackground]
  /// ran twice per trip (hidden + paused), doubling position/queue persistence.
  bool _inBackground = false;

  AudioHandlerLifecycleObserver({
    required this.onBackground,
    this.onResume,
    this.onDetached,
    this.onHidden,
  });

  void _enterBackground() {
    if (_inBackground) return;
    _inBackground = true;
    onBackground();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        // Last chance to persist state. (The old `Isolate.run(() {})` here did
        // nothing useful, returned an un-awaited Future that a try/catch can't
        // catch, and spawned an isolate while the engine was tearing down.)
        if (onDetached != null) {
          onDetached!();
        } else {
          _enterBackground();
        }
        break;
      case AppLifecycleState.hidden:
        if (onHidden != null) {
          onHidden!();
        } else {
          _enterBackground();
        }
        break;
      case AppLifecycleState.paused:
        _enterBackground();
        break;
      case AppLifecycleState.resumed:
        _inBackground = false;
        onResume?.call();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }
}
