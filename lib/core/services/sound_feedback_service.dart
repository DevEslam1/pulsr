// lib/core/services/sound_feedback_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';
import '../utils/pulsr_haptics.dart';

/// Semantic verbs for UI sound feedback cues.
enum SoundFeedbackVerb {
  click,
  toggle,
  success,
  warning,
  error,
  alert,
}

/// Centralized UI sound design service.
///
/// **Accessibility & Sound Policy:**
/// - Sound cues are optional and disabled by default per user privacy and comfort specifications.
/// - Sound cues MUST ALWAYS accompany, NEVER replace, visual and semantic affordances (`Semantics` / `label`).
/// - Every auditory cue is mirrored with tactile feedback (`PulsrHaptics`) so deaf and
///   hard-of-hearing users maintain 100% feature and emotional parity.
/// - When music is actively playing, subtle non-critical feedback (clicks/toggles) can be
///   automatically ducked / gated so that cues never jarringly ride over music playback.
class SoundFeedbackService {
  SoundFeedbackService._();

  static final ValueNotifier<bool> _enabledNotifier = ValueNotifier<bool>(false);

  /// ValueNotifier exposing the current enabled state for reactive UI bindings.
  static ValueNotifier<bool> get enabledNotifier => _enabledNotifier;

  /// Whether subtle UI sound feedback is currently active.
  static bool get enabled => _enabledNotifier.value;

  /// Optional query callback to check if music is actively playing.
  static bool Function()? isMusicPlaying;

  /// When true (default), subtle selection sounds are gated while music is playing.
  static bool duckUnderMusic = true;

  /// Test hook called whenever a sound verb is triggered.
  @visibleForTesting
  static void Function(SoundFeedbackVerb verb)? onSoundEmitted;

  /// Recorded emissions for unit/widget testing.
  @visibleForTesting
  static final List<SoundFeedbackVerb> testEmissions = [];

  /// Resets test emissions and listeners.
  @visibleForTesting
  static void resetForTesting() {
    testEmissions.clear();
    onSoundEmitted = null;
    isMusicPlaying = null;
    duckUnderMusic = true;
    _enabledNotifier.value = false;
  }

  /// Initializes the sound feedback preference from disk cache.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getBool(PrefsKeys.soundFeedbackEnabled) ?? false;
      _enabledNotifier.value = val;
    } catch (_) {}
  }

  /// Sets whether UI sound feedback is active and optionally persists to SharedPreferences.
  static void setEnabled(bool value, {bool persist = true}) {
    _enabledNotifier.value = value;
    if (persist) {
      unawaited(SharedPreferences.getInstance().then((prefs) {
        prefs.setBool(PrefsKeys.soundFeedbackEnabled, value);
      }).catchError((_) {}));
    }
  }

  static bool _shouldPlay(SoundFeedbackVerb verb) {
    if (!enabled) return false;
    if (duckUnderMusic && (isMusicPlaying?.call() ?? false)) {
      // Gate subtle clicks and toggles under music; allow alerts/warnings/errors/success
      if (verb == SoundFeedbackVerb.click || verb == SoundFeedbackVerb.toggle) {
        return false;
      }
    }
    return true;
  }

  static void _emit(SoundFeedbackVerb verb, {VoidCallback? playAction}) {
    if (kDebugMode || kProfileMode) {
      testEmissions.add(verb);
      onSoundEmitted?.call(verb);
    }
    if (!_shouldPlay(verb)) return;
    try {
      playAction?.call();
    } catch (_) {}
  }

  static void _triggerHaptic(VoidCallback hapticAction) {
    try {
      hapticAction();
    } catch (_) {}
  }

  /// Emits a subtle click sound for selection or button presses.
  static void playClick({bool mirrorHaptics = false}) {
    if (mirrorHaptics) _triggerHaptic(PulsrHaptics.light);
    _emit(
      SoundFeedbackVerb.click,
      playAction: () => SystemSound.play(SystemSoundType.click),
    );
  }

  /// Emits a subtle toggle sound for switches, checkboxes, and chips.
  static void playToggle({bool mirrorHaptics = false}) {
    if (mirrorHaptics) _triggerHaptic(PulsrHaptics.tap);
    _emit(
      SoundFeedbackVerb.toggle,
      playAction: () => SystemSound.play(SystemSoundType.click),
    );
  }

  /// Emits a positive confirmation sound for success actions (saved, completed).
  static void playSuccess({bool mirrorHaptics = false}) {
    if (mirrorHaptics) _triggerHaptic(PulsrHaptics.confirm);
    _emit(
      SoundFeedbackVerb.success,
      playAction: () => SystemSound.play(SystemSoundType.click),
    );
  }

  /// Emits a warning sound for destructive operations (delete, remove, clear).
  static void playWarning({bool mirrorHaptics = false}) {
    if (mirrorHaptics) _triggerHaptic(PulsrHaptics.destructive);
    _emit(
      SoundFeedbackVerb.warning,
      playAction: () => SystemSound.play(SystemSoundType.alert),
    );
  }

  /// Emits an error sound for failed operations (auth failure, network drop).
  static void playError({bool mirrorHaptics = false}) {
    if (mirrorHaptics) _triggerHaptic(PulsrHaptics.destructive);
    _emit(
      SoundFeedbackVerb.error,
      playAction: () => SystemSound.play(SystemSoundType.alert),
    );
  }

  /// Emits an alert sound when enabled.
  static void playAlert({bool mirrorHaptics = false}) {
    if (mirrorHaptics) _triggerHaptic(PulsrHaptics.confirm);
    _emit(
      SoundFeedbackVerb.alert,
      playAction: () => SystemSound.play(SystemSoundType.alert),
    );
  }
}
