// lib/features/usb_tools/usb_ergonomics_strings.dart
//
// Single translation point for every English string the USB ergonomics module
// renders or returns as an error message. A localisation pass touches this file
// only.

/// English strings for the USB ergonomics screen and service.
abstract final class UsbErgonomicsStrings {
  /// Screen title.
  static const String screenTitle = 'USB ergonomics';

  /// Section header for the attached device summary.
  static const String sectionDevice = 'Attached DAC';

  /// Section header for the quirk editor.
  static const String sectionQuirks = 'Device quirks';

  /// Section header for the diagnostics actions.
  static const String sectionDiagnostics = 'Diagnostics';

  /// Section header for the JSON preview.
  static const String sectionJson = 'Profile JSON';

  /// Subtitle under the JSON preview.
  static const String jsonHint =
      'Copy or share this to reproduce the setup on another device.';

  /// Empty state title when no DAC is attached.
  static const String noDeviceTitle = 'No USB DAC attached';

  /// Empty state subtitle when no DAC is attached.
  static const String noDeviceSubtitle =
      'Connect a USB audio device to edit its quirks.';

  /// Empty state action.
  static const String refreshAction = 'Check again';

  /// Fallback device label when the DAC reports no name.
  static const String unknownDevice = 'USB DAC';

  /// Format of the vendor/product id line.
  static String ids(int vid, int pid) =>
      'VID 0x${vid.toRadixString(16).toUpperCase().padLeft(4, '0')}  ·  '
      'PID 0x${pid.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// Switch title for HID media keys.
  static const String hidTitle = 'HID media keys';

  /// Switch hint for HID media keys.
  static const String hidHint =
      'Reads play/pause, skip and volume from the DAC buttons.';

  /// Section header for the direct-path transport quirks.
  static const String audioSectionTitle = 'Audio transport quirks';

  /// Hint under the audio transport section.
  static const String audioSectionHint =
      'Applied only to the direct USB path. Values that change bit-perfect '
      'semantics are reported in the stream status.';

  /// Switch title for forced 16-bit output.
  static const String force16Title = 'Force 16-bit output';

  /// Switch hint for forced 16-bit output.
  static const String force16Hint =
      'Truncates wider sources; the stream can no longer claim bit-perfect.';

  /// Switch title for resetting the alt setting on stop.
  static const String altResetTitle = 'Reset alt setting on stop';

  /// Switch hint for resetting the alt setting on stop.
  static const String altResetHint =
      'Returns the DAC to alt 0 before releasing the interface.';

  /// Switch title for ignoring the feedback endpoint.
  static const String disableFeedbackTitle = 'Ignore feedback endpoint';

  /// Switch hint for ignoring the feedback endpoint.
  static const String disableFeedbackHint =
      'For DACs whose feedback stream is broken; drift is then steered.';

  /// Switch title for re-asserting the UAC1 rate.
  static const String uac1ReassertTitle = 'Re-assert UAC1 rate';

  /// Switch hint for re-asserting the UAC1 rate.
  static const String uac1ReassertHint =
      'Writes the sample rate again after selecting the alt setting.';

  /// Switch title for keeping the device clock untouched.
  static const String disableClockSwitchTitle = 'Do not program UAC2 clock';

  /// Switch hint for keeping the device clock untouched.
  static const String disableClockSwitchHint =
      'The DAC keeps its own clock; bit-perfect cannot be verified.';

  /// Label of the pre-open silence field.
  static const String silenceLabel = 'Silence before start (ms)';

  /// Label of the transfer size field.
  static const String transferSizeLabel = 'Transfer size (bytes, 0 = auto)';

  /// Label of the reservoir field.
  static const String bufferLabel = 'Buffer target (ms, 0 = auto)';

  /// Label of the selector pin field.
  static const String selectorPinLabel = 'Clock selector pin (blank = auto)';

  /// Label of the volume calibration field.
  static const String volumeCalibrationLabel =
      'Volume calibration (dB, -24.0 to +24.0)';

  /// Validation error for a numeric field.
  static const String numberInvalid = 'Enter a number in the allowed range.';

  /// Action that measures the bus speed.
  static const String probeAction = 'Probe bus speed';

  /// Tooltip of the probe action.
  static const String probeTooltip = 'Measure USB bus speed';

  /// Bus speed readout.
  static String busSpeed(double mbps) => '${mbps.toStringAsFixed(0)} Mbps';

  /// Bus speed before it has been measured.
  static const String busSpeedUnknown = 'Not measured';

  /// Label of the HID status row.
  static const String hidStatusLabel = 'HID status';

  /// HID status when the interfaces are not claimed.
  static const String hidNotClaimed = 'Not claimed';

  /// HID status when the interfaces are claimed with consumer controls.
  static const String hidClaimed = 'Claimed, consumer controls ready';

  /// HID status when the interfaces are claimed without consumer controls.
  static const String hidClaimedNoConsumer = 'Claimed, no consumer report';

  /// Action that returns the interface to alternate setting 0.
  static const String resetAltAction = 'Reset alt setting';

  /// Tooltip of the reset action.
  static const String resetAltTooltip = 'Return the DAC to alt setting 0';

  /// Primary action that stores the edited profile.
  static const String saveAction = 'Save profile';

  /// Tooltip of the save action.
  static const String saveTooltip = 'Save this device profile';

  /// Action that removes the stored profile.
  static const String deleteAction = 'Delete profile';

  /// Tooltip of the delete action.
  static const String deleteTooltip = 'Delete this device profile';

  /// Tooltip of the export action.
  static const String exportTooltip = 'Export JSON';

  /// Tooltip of the copy action.
  static const String copyTooltip = 'Copy JSON';

  /// Confirmation after copying the profile JSON.
  static const String copied = 'Profile JSON copied';

  /// Confirmation after saving.
  static const String saved = 'Profile saved and applied';

  /// Confirmation after deleting.
  static const String deleted = 'Profile deleted, using defaults';

  /// Title of the diagnostics line for the active profile.
  static const String activeProfileLabel = 'Active profile';

  /// Shown when no profile is stored for the device.
  static const String noProfileStored = 'Defaults (nothing stored)';

  /// Failure message when the store rejected a write.
  static const String saveFailed = 'Could not save the profile.';

  /// Failure message when the store rejected a delete.
  static const String deleteFailed = 'Could not delete the profile.';

  /// Failure message when the device has no USB ids.
  static const String noDeviceId =
      'The DAC reports no USB ids, so no profile can be stored.';

  /// Failure message for a failed native apply.
  static const String applyFailed = 'The native USB ergonomics call failed.';

  /// Failure message when the bus speed is not reported.
  static const String busSpeedUnavailable =
      'Bus speed is not reported by this device.';

  /// Failure message for a failed alt-setting reset.
  static const String resetAltFailed = 'Resetting the alternate setting failed.';

  /// Snackbar when an export callback is not wired by the host.
  static const String exportUnavailable =
      'Export is not available on this screen.';
}
