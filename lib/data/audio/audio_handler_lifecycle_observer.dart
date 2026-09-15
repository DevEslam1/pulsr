// lib/data/audio/audio_handler_lifecycle_observer.dart
import 'package:flutter/widgets.dart';

class AudioHandlerLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onBackground;
  final VoidCallback? onResume;
  AudioHandlerLifecycleObserver({required this.onBackground, this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      onBackground();
    } else if (state == AppLifecycleState.resumed) {
      onResume?.call();
    }
  }
}
