// lib/features/diagnostics/diagnostics_strings.dart
//
// Localized copy for the diagnostics module, backed by ARB (`AppLocalizations`)
// with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing copy for the diagnostics and safe-mode features.
abstract final class DiagnosticsStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  static String get screenTitle => _l10n().diagScreenTitle;
  static String get refreshTooltip => _l10n().diagRefreshTooltip;
  static String get retry => _l10n().diagRetry;

  static String get buildModeDebug => _l10n().diagBuildModeDebug;
  static String get buildModeProfile => _l10n().diagBuildModeProfile;
  static String get buildModeRelease => _l10n().diagBuildModeRelease;

  static String get deviceTitle => _l10n().diagDeviceTitle;
  static String get deviceUnknown => _l10n().diagDeviceUnknown;
  static String get usbUnavailable => _l10n().diagUsbUnavailable;

  static String get pathsTitle => _l10n().diagPathsTitle;
  static String get pathsNativeNotReported =>
      _l10n().diagPathsNativeNotReported;
  static String get pathsUnavailable => _l10n().diagPathsUnavailable;

  static String get dspTitle => _l10n().diagDspTitle;
  static String get dspNone => _l10n().diagDspNone;

  static String get safeModeTitle => _l10n().diagSafeModeTitle;
  static String get safeModeOn => _l10n().diagSafeModeOn;
  static String get safeModeOff => _l10n().diagSafeModeOff;
  static String get safeModeReset => _l10n().diagSafeModeReset;
  static String get safeModeEnter => _l10n().diagSafeModeEnter;
  static String get safeModeExit => _l10n().diagSafeModeExit;
  static String get safeModeEntered => _l10n().diagSafeModeEntered;
  static String get safeModeExited => _l10n().diagSafeModeExited;
  static String get safeModeResetDone => _l10n().diagSafeModeResetDone;
  static String get safeModeResetFailed => _l10n().diagSafeModeResetFailed;
  static String get safeModePersistFailed => _l10n().diagSafeModePersistFailed;

  static String get logsTitle => _l10n().diagLogsTitle;
  static String get logsEmpty => _l10n().diagLogsEmpty;

  static String get exportAction => _l10n().diagExportAction;
  static String get exportFailed => _l10n().diagExportFailed;
  static String get shareText => _l10n().diagShareText;

  static String get selfTestAction => _l10n().diagSelfTestAction;
  static String get selfTestRunning => _l10n().diagSelfTestRunning;

  static String get errorTitle => _l10n().diagErrorTitle;
  static String get errorSubtitle => _l10n().diagErrorSubtitle;

  /// App/version summary shown at the top of the screen.
  static String appSummary(
    String version,
    String platform,
    String mode, [
    AppLocalizations? l10n,
  ]) =>
      _l10n(l10n).diagAppSummary(version, platform, mode);

  /// One output path's counters.
  static String counterSummary(
    int xruns,
    int underruns, [
    AppLocalizations? l10n,
  ]) =>
      _l10n(l10n).diagCounterSummary(xruns, underruns);

  /// Whether the counters came from the native engine.
  static String countersReported(bool reported, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return reported ? l.diagCountersReported : l.diagCountersNotReported;
  }

  /// How many DSP stages are on.
  static String dspSummary(int enabled, int total, [AppLocalizations? l10n]) =>
      _l10n(l10n).diagDspSummary(enabled, total);

  /// Consecutive failure count for the current device.
  static String safeModeFailures(int count, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return count == 1
        ? l.diagSafeModeFailuresOne
        : l.diagSafeModeFailuresMany(count);
  }

  /// Failure threshold the controller falls back at.
  static String safeModeThreshold(int threshold, [AppLocalizations? l10n]) =>
      _l10n(l10n).diagSafeModeThreshold(threshold);

  /// Human description returned by the fallback.
  static String safeModeFallbackDescription(
    String device,
    int failures, [
    AppLocalizations? l10n,
  ]) =>
      _l10n(l10n).diagSafeModeFallbackDescription(device, failures);

  /// Self-test success line.
  static String selfTestPassed(
    int sections,
    int elapsedMs, [
    AppLocalizations? l10n,
  ]) =>
      _l10n(l10n).diagSelfTestPassed(sections, elapsedMs);

  /// Self-test failure line.
  static String selfTestFailed(String message, [AppLocalizations? l10n]) =>
      _l10n(l10n).diagSelfTestFailed(message);
}
