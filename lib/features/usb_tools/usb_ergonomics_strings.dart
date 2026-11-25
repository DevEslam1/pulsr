// lib/features/usb_tools/usb_ergonomics_strings.dart
//
// Localized copy for the USB ergonomics module, backed by ARB
// (`AppLocalizations`) with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing strings for the USB ergonomics screen and service.
abstract final class UsbErgonomicsStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  /// Screen title.
  static String get screenTitle => _l10n().usbErgoScreenTitle;

  /// Section header for the attached device summary.
  static String get sectionDevice => _l10n().usbErgoSectionDevice;

  /// Section header for the quirk editor.
  static String get sectionQuirks => _l10n().usbErgoSectionQuirks;

  /// Section header for the diagnostics actions.
  static String get sectionDiagnostics => _l10n().usbErgoSectionDiagnostics;

  /// Section header for the JSON preview.
  static String get sectionJson => _l10n().usbErgoSectionJson;

  /// Subtitle under the JSON preview.
  static String get jsonHint => _l10n().usbErgoJsonHint;

  /// Empty state title when no DAC is attached.
  static String get noDeviceTitle => _l10n().usbErgoNoDeviceTitle;

  /// Empty state subtitle when no DAC is attached.
  static String get noDeviceSubtitle => _l10n().usbErgoNoDeviceSubtitle;

  /// Empty state action.
  static String get refreshAction => _l10n().usbErgoRefreshAction;

  /// Fallback device label when the DAC reports no name.
  static String get unknownDevice => _l10n().usbErgoUnknownDevice;

  /// Format of the vendor/product id line.
  static String ids(int vid, int pid) =>
      'VID 0x${vid.toRadixString(16).toUpperCase().padLeft(4, '0')}  ·  '
      'PID 0x${pid.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// Switch title for HID media keys.
  static String get hidTitle => _l10n().usbErgoHidTitle;

  /// Switch hint for HID media keys.
  static String get hidHint => _l10n().usbErgoHidHint;

  /// Section header for the direct-path transport quirks.
  static String get audioSectionTitle => _l10n().usbErgoAudioSectionTitle;

  /// Hint under the audio transport section.
  static String get audioSectionHint => _l10n().usbErgoAudioSectionHint;

  /// Switch title for forced 16-bit output.
  static String get force16Title => _l10n().usbErgoForce16Title;

  /// Switch hint for forced 16-bit output.
  static String get force16Hint => _l10n().usbErgoForce16Hint;

  /// Switch title for resetting the alt setting on stop.
  static String get altResetTitle => _l10n().usbErgoAltResetTitle;

  /// Switch hint for resetting the alt setting on stop.
  static String get altResetHint => _l10n().usbErgoAltResetHint;

  /// Switch title for ignoring the feedback endpoint.
  static String get disableFeedbackTitle => _l10n().usbErgoDisableFeedbackTitle;

  /// Switch hint for ignoring the feedback endpoint.
  static String get disableFeedbackHint => _l10n().usbErgoDisableFeedbackHint;

  /// Switch title for re-asserting the UAC1 rate.
  static String get uac1ReassertTitle => _l10n().usbErgoUac1ReassertTitle;

  /// Switch hint for re-asserting the UAC1 rate.
  static String get uac1ReassertHint => _l10n().usbErgoUac1ReassertHint;

  /// Switch title for keeping the device clock untouched.
  static String get disableClockSwitchTitle =>
      _l10n().usbErgoDisableClockSwitchTitle;

  /// Switch hint for keeping the device clock untouched.
  static String get disableClockSwitchHint =>
      _l10n().usbErgoDisableClockSwitchHint;

  /// Label of the pre-open silence field.
  static String get silenceLabel => _l10n().usbErgoSilenceLabel;

  /// Label of the transfer size field.
  static String get transferSizeLabel => _l10n().usbErgoTransferSizeLabel;

  /// Label of the reservoir field.
  static String get bufferLabel => _l10n().usbErgoBufferLabel;

  /// Label of the selector pin field.
  static String get selectorPinLabel => _l10n().usbErgoSelectorPinLabel;

  /// Label of the volume calibration field.
  static String get volumeCalibrationLabel =>
      _l10n().usbErgoVolumeCalibrationLabel;

  /// Validation error for a numeric field.
  static String get numberInvalid => _l10n().usbErgoNumberInvalid;

  /// Action that measures the bus speed.
  static String get probeAction => _l10n().usbErgoProbeAction;

  /// Tooltip of the probe action.
  static String get probeTooltip => _l10n().usbErgoProbeTooltip;

  /// Bus speed readout.
  static String busSpeed(double mbps) => '${mbps.toStringAsFixed(0)} Mbps';

  /// Bus speed before it has been measured.
  static String get busSpeedUnknown => _l10n().usbErgoBusSpeedUnknown;

  /// Label of the HID status row.
  static String get hidStatusLabel => _l10n().usbErgoHidStatusLabel;

  /// HID status when the interfaces are not claimed.
  static String get hidNotClaimed => _l10n().usbErgoHidNotClaimed;

  /// HID status when the interfaces are claimed with consumer controls.
  static String get hidClaimed => _l10n().usbErgoHidClaimed;

  /// HID status when the interfaces are claimed without consumer controls.
  static String get hidClaimedNoConsumer => _l10n().usbErgoHidClaimedNoConsumer;

  /// Action that returns the interface to alternate setting 0.
  static String get resetAltAction => _l10n().usbErgoResetAltAction;

  /// Tooltip of the reset action.
  static String get resetAltTooltip => _l10n().usbErgoResetAltTooltip;

  /// Primary action that stores the edited profile.
  static String get saveAction => _l10n().usbErgoSaveAction;

  /// Tooltip of the save action.
  static String get saveTooltip => _l10n().usbErgoSaveTooltip;

  /// Action that removes the stored profile.
  static String get deleteAction => _l10n().usbErgoDeleteAction;

  /// Tooltip of the delete action.
  static String get deleteTooltip => _l10n().usbErgoDeleteTooltip;

  /// Tooltip of the export action.
  static String get exportTooltip => _l10n().usbErgoExportTooltip;

  /// Tooltip of the copy action.
  static String get copyTooltip => _l10n().usbErgoCopyTooltip;

  /// Confirmation after copying the profile JSON.
  static String get copied => _l10n().usbErgoCopied;

  /// Confirmation after saving.
  static String get saved => _l10n().usbErgoSaved;

  /// Confirmation after deleting.
  static String get deleted => _l10n().usbErgoDeleted;

  /// Title of the diagnostics line for the active profile.
  static String get activeProfileLabel => _l10n().usbErgoActiveProfileLabel;

  /// Shown when no profile is stored for the device.
  static String get noProfileStored => _l10n().usbErgoNoProfileStored;

  /// Failure message when the store rejected a write.
  static String get saveFailed => _l10n().usbErgoSaveFailed;

  /// Failure message when the store rejected a delete.
  static String get deleteFailed => _l10n().usbErgoDeleteFailed;

  /// Failure message when the device has no USB ids.
  static String get noDeviceId => _l10n().usbErgoNoDeviceId;

  /// Failure message for a failed native apply.
  static String get applyFailed => _l10n().usbErgoApplyFailed;

  /// Failure message when the bus speed is not reported.
  static String get busSpeedUnavailable => _l10n().usbErgoBusSpeedUnavailable;

  /// Failure message for a failed alt-setting reset.
  static String get resetAltFailed => _l10n().usbErgoResetAltFailed;

  /// Snackbar when an export callback is not wired by the host.
  static String get exportUnavailable => _l10n().usbErgoExportUnavailable;
}
