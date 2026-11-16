// lib/features/diagnostics/diagnostics_strings.dart
//
// Single translation point for the diagnostics module: screen copy, bundle
// labels and the safe-mode description all live here.

/// English copy for the diagnostics and safe-mode features.
abstract final class DiagnosticsStrings {
  static const String screenTitle = 'Diagnostics';
  static const String refreshTooltip = 'Refresh diagnostics';
  static const String retry = 'Retry';

  static const String buildModeDebug = 'debug';
  static const String buildModeProfile = 'profile';
  static const String buildModeRelease = 'release';

  static const String deviceTitle = 'Output device';
  static const String deviceUnknown = 'Unknown output device';
  static const String usbUnavailable = 'USB diagnostics unavailable';

  static const String pathsTitle = 'Output paths';
  static const String pathsNativeNotReported = 'native-not-reported';
  static const String pathsUnavailable =
      'The native engine on this build does not report xrun counters. Zeros '
      'below mean "not measured", not "no glitches".';

  static const String dspTitle = 'DSP stages';
  static const String dspNone = 'No DSP stages are enabled';

  static const String safeModeTitle = 'Safe mode';
  static const String safeModeOn = 'Safe mode is active';
  static const String safeModeOff = 'Safe mode is off';
  static const String safeModeReset = 'Reset safe mode';
  static const String safeModeEnter = 'Enter safe mode';
  static const String safeModeExit = 'Exit safe mode';
  static const String safeModeEntered =
      'Safe mode is on. AAudio, USB volume and strict bit-perfect are off.';
  static const String safeModeExited =
      'Safe mode is off. Your previous output settings were restored.';
  static const String safeModeResetDone = 'Safe mode was reset.';
  static const String safeModeResetFailed = 'Resetting safe mode failed.';
  static const String safeModePersistFailed =
      'The safe-mode state could not be saved.';

  static const String logsTitle = 'Recent log';
  static const String logsEmpty = 'No log entries are buffered yet.';

  static const String exportAction = 'Export bundle';
  static const String exportFailed = 'Exporting the diagnostics bundle failed.';
  static const String shareText = 'Pulsr diagnostics bundle';

  static const String selfTestAction = 'Re-run self test';
  static const String selfTestRunning = 'Running the self test...';

  static const String errorTitle = 'Diagnostics unavailable';
  static const String errorSubtitle =
      'The bundle could not be built. Retry in a moment.';

  /// App/version summary shown at the top of the screen.
  static String appSummary(String version, String platform, String mode) =>
      'Pulsr $version - $platform - $mode build';

  /// One output path's counters.
  static String counterSummary(int xruns, int underruns) =>
      'xruns $xruns - underruns $underruns';

  /// Whether the counters came from the native engine.
  static String countersReported(bool reported) => reported
      ? 'Reported by the native engine'
      : 'Not reported by the native engine';

  /// How many DSP stages are on.
  static String dspSummary(int enabled, int total) =>
      '$enabled of $total stages enabled';

  /// Consecutive failure count for the current device.
  static String safeModeFailures(int count) => count == 1
      ? '1 consecutive output failure'
      : '$count consecutive output failures';

  /// Failure threshold the controller falls back at.
  static String safeModeThreshold(int threshold) =>
      'Falls back after $threshold consecutive failures.';

  /// Human description returned by the fallback.
  static String safeModeFallbackDescription(String device, int failures) =>
      'Turned off AAudio direct output, USB hardware volume and strict '
      'bit-perfect, and switched DSD to PCM for $device after $failures '
      'consecutive output failures.';

  /// Self-test success line.
  static String selfTestPassed(int sections, int elapsedMs) =>
      'Self test passed: $sections sections collected in $elapsedMs ms.';

  /// Self-test failure line.
  static String selfTestFailed(String message) => 'Self test failed: $message';
}
