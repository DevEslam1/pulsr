// lib/core/utils/haptics.dart
import 'pulsr_haptics.dart';

/// Legacy facade forwarding to [PulsrHaptics] so all tactile feedback honours
/// the single global [PulsrHaptics.enabled] switch.
abstract class Haptics {
  static Future<void> tap() => PulsrHaptics.light();
  static Future<void> select() => PulsrHaptics.selection();
  static Future<void> medium() => PulsrHaptics.confirm();
  static Future<void> heavy() => PulsrHaptics.destructive();
  static Future<void> success() => PulsrHaptics.success();
  static Future<void> error() => PulsrHaptics.error();
}
