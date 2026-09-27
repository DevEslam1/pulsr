// lib/core/services/sound_feedback_service.dart
import 'package:flutter/services.dart';

/// Centralized UI sound design service.
/// Optional and off by default per design specification; when enabled,
/// triggers subtle system audio feedback on key user actions.
class SoundFeedbackService {
  SoundFeedbackService._();

  static bool _enabled = false;

  /// Whether subtle UI sound feedback is currently active.
  static bool get enabled => _enabled;

  /// Sets whether UI sound feedback is active.
  static void setEnabled(bool value) {
    _enabled = value;
  }

  /// Emits a subtle click sound when enabled.
  static void playClick() {
    if (!_enabled) return;
    SystemSound.play(SystemSoundType.click);
  }

  /// Emits an alert sound when enabled.
  static void playAlert() {
    if (!_enabled) return;
    SystemSound.play(SystemSoundType.alert);
  }
}
