// lib/features/dlna/dlna_strings.dart
//
// Single translation point for every English string the DLNA screen shows.
import 'dlna_renderer_service.dart';

/// User-facing copy for the DLNA module.
abstract final class DlnaStrings {
  /// Screen title.
  static const String title = 'DLNA Renderers';

  /// One-line explanation under the title.
  static const String subtitle =
      'Play on a TV or speaker on your Wi-Fi network.';

  /// Label of the scan button.
  static const String scan = 'Scan for devices';

  /// Label of the button that picks a local file and casts it.
  static const String castFile = 'Cast file';

  /// Label of the button that casts the track playing on this device.
  static const String castCurrentTrack = 'Cast current track';

  /// Semantics label for the cast-file action.
  static const String castFileSemantics =
      'Choose a local audio file to cast to the renderer';

  /// Semantics label for the cast-current-track action.
  static const String castCurrentSemantics =
      'Cast the track currently playing on this device to the renderer';

  /// Label shown while discovery runs.
  static const String scanning = 'Searching for renderers';

  /// Empty-state copy when discovery finds nothing.
  static const String noDevices =
      'No DLNA renderers found. Check that your TV or speaker is on the same '
      'network and that media sharing is enabled.';

  /// Button that connects to one device.
  static const String connect = 'Connect';

  /// Shown for the device currently under control.
  static const String connected = 'Connected';

  /// Placeholder when nothing has been cast yet.
  static const String nothingPlaying = 'Nothing playing';

  /// Pause control label and tooltip.
  static const String pause = 'Pause';

  /// Resume control label and tooltip.
  static const String resume = 'Resume';

  /// Stop control label and tooltip.
  static const String stop = 'Stop';

  /// Label of the seek slider.
  static const String seek = 'Seek';

  /// Heading of the now-playing card.
  static const String nowPlaying = 'Now playing';

  /// Retry button in the error banner.
  static const String retry = 'Retry';

  /// Title of the error banner.
  static const String errorTitle = 'Could not reach the device';

  /// Semantics label for the scan button.
  static const String scanSemantics = 'Scan the network for DLNA renderers';

  /// Semantics label for the connect action on a named device.
  static String connectTo(String deviceName) => 'Connect to $deviceName';

  /// Semantics label for the device row, including the model when known.
  static String deviceRow(String name, String? model) =>
      model == null || model.isEmpty ? name : '$name, $model';

  /// Short label for the current transport state.
  static String stateLabel(DlnaState state) {
    switch (state) {
      case DlnaState.idle:
        return 'Ready';
      case DlnaState.discovering:
        return 'Scanning';
      case DlnaState.connecting:
        return 'Connecting';
      case DlnaState.playing:
        return 'Playing';
      case DlnaState.paused:
        return 'Paused';
      case DlnaState.stopped:
        return 'Stopped';
      case DlnaState.error:
        return 'Error';
    }
  }
}
