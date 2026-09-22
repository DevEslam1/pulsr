// lib/domain/interfaces/widget_pusher_interface.dart
// FIX-A2: Dependency inversion interface for OS home widget updates

/// Contract for updating operating system home-screen widgets with active track info.
abstract class IWidgetPusher {
  /// Updates OS widget state with current [title], [artist], [isPlaying], and [artworkUri].
  Future<void> updateWidget({
    required String title,
    required String artist,
    required bool isPlaying,
    String? artworkUri,
  });
}
