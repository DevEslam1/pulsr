// lib/core/utils/haptic_patterns.dart
import 'pulsr_haptics.dart';

/// Legacy facade forwarding to [PulsrHaptics] so all tactile feedback honours
/// the single global [PulsrHaptics.enabled] switch.
class HapticPatterns {
  const HapticPatterns._();

  static void tap() => PulsrHaptics.light();
  static void confirm() => PulsrHaptics.confirm();
  static void destructive() => PulsrHaptics.destructive();
  static void selection() => PulsrHaptics.selection();
  static void vibrate() => PulsrHaptics.vibrate();
}
