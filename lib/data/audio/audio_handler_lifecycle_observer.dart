// lib/data/audio/audio_handler_lifecycle_observer.dart
import 'dart:isolate';
import 'package:flutter/widgets.dart';

class AudioHandlerLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onBackground;
  final VoidCallback? onResume;
  final VoidCallback? onDetached;
  final VoidCallback? onHidden;

  AudioHandlerLifecycleObserver({
    required this.onBackground,
    this.onResume,
    this.onDetached,
    this.onHidden,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      if (onDetached != null) {
        onDetached!();
      } else {
        onBackground();
      }
      try {
        Isolate.run(() {});
      } catch (_) {}
    } else if (state == AppLifecycleState.hidden) {
      if (onHidden != null) {
        onHidden!();
      } else {
        onBackground();
      }
    } else if (state == AppLifecycleState.paused) {
      onBackground();
    } else if (state == AppLifecycleState.resumed) {
      onResume?.call();
    }
  }
}
