// lib/domain/interfaces/widget_pusher_interface.dart
// FIX-A2: Dependency inversion interface for OS home widget updates

/// Contract for updating operating system home-screen widgets with active track
/// info.
///
/// Failure semantics:
/// - [updateWidget] is best-effort. A platform channel error (unsupported
///   widget host, missing plugin) must be swallowed/logged, never thrown into
///   the caller: the home widget is a non-critical surface and must not break
///   playback or navigation. Where supported, stale widget data is preferable
///   to a crash.
abstract class IWidgetPusher {
  /// Updates OS widget state with current [title], [artist], [isPlaying], and
  /// [artworkUri]. Best-effort; must not throw.
  Future<void> updateWidget({
    required String title,
    required String artist,
    required bool isPlaying,
    String? artworkUri,
  });
}
