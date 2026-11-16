// lib/features/system_behavior/system_behavior_strings.dart
//
// Single translation point for the system-behaviour module. Every user-visible
// string the screen emits lives here, so the module can be localized by
// translating one class.

/// English copy for the system-behaviour feature.
abstract final class SystemBehaviorStrings {
  static const String screenTitle = 'System behaviour';

  static const String sectionFocus = 'Audio focus';
  static const String sectionUsb = 'USB output';
  static const String sectionVolume = 'Volume';
  static const String sectionLifecycle = 'Fade and lifecycle';

  static const String pauseOnNotificationSoundTitle =
      'Pause for notification sounds';
  static const String pauseOnNotificationSoundSubtitle =
      'Pauses instead of ducking when a system alert or navigation prompt '
      'plays. Turn this off to keep the music at a reduced level.';

  static const String resumeAfterCallTitle = 'Resume after calls';
  static const String resumeAfterCallSubtitle =
      'Continues playback when a phone call or another interruption ends, as '
      'long as nothing else took audio focus in the meantime.';

  static const String usbReleaseOnFocusLossTitle = 'USB release on focus loss';
  static const String usbReleaseOnFocusLossSubtitle =
      'Drops the exclusive USB claim when another app or a call takes audio '
      'focus, so the DAC can be claimed again afterwards.';

  static const String usbReleaseNever = 'Never';
  static const String usbReleasePermanent = 'Permanent';
  static const String usbReleaseTransient = 'Transient';
  static const String usbReleaseNeverIconLabel = 'Keep USB on every focus loss';
  static const String usbReleasePermanentIconLabel =
      'Release USB on permanent focus loss';
  static const String usbReleaseTransientIconLabel =
      'Release USB on any focus loss';

  static const String closeUsbWhenBackgroundedTitle = 'Close USB in background';
  static const String closeUsbWhenBackgroundedSubtitle =
      'Releases the exclusive claim when the app leaves the foreground, so '
      'another app on the device can use the DAC.';

  static const String volumeRockerTrackSwitchTitle =
      'Double-press volume to skip';
  static const String volumeRockerTrackSwitchSubtitle =
      'A double press of the hardware volume rocker skips to the next track '
      'instead of changing the volume twice.';

  static const String softwareVolumeCurveTitle = 'Volume curve';
  static const String softwareVolumeCurveSubtitle =
      'Linear moves the same amount of gain per step. Logarithmic moves the '
      'same amount of perceived loudness, which keeps the first steps quiet '
      'and the last steps usable.';

  static const String curveLinear = 'Linear';
  static const String curveLogarithmic = 'Logarithmic';
  static const String curveLinearIconLabel = 'Use a linear volume curve';
  static const String curveLogarithmicIconLabel =
      'Use a logarithmic volume curve';

  static const String volumeStepPercentTitle = 'Volume step';
  static const String volumeStepPercentSubtitle =
      'How far one volume step moves, as a percentage of the full scale.';

  static const String fadeOutOnPauseMsTitle = 'Fade out before pause';
  static const String fadeOutOnPauseMsSubtitle =
      'Ramps the volume to zero before pausing, so an interruption does not '
      'cut the music off. Set to 0 to pause immediately.';

  static const String fadeOffValue = 'Off';

  static const String stopWhenTaskRemovedTitle = 'Stop when swiped away';
  static const String stopWhenTaskRemovedSubtitle =
      'Stops playback when the app is removed from the recent apps list '
      'instead of pausing and keeping the queue.';

  static const String androidOnlyLimit =
      'Android-only: this platform gives the app no task-removal callback, so '
      'the setting cannot take effect here.';
  static const String usbOnlyLimit =
      'Android-only: exclusive USB output does not exist on this platform, so '
      'the setting cannot take effect here.';
  static const String volumeRockerLimit =
      'Android-only: hardware volume keys are not delivered to the app on this '
      'platform, so the setting cannot take effect here.';

  /// Fade length shown next to the slider.
  static String fadeValue(int milliseconds) =>
      milliseconds == 0 ? fadeOffValue : '$milliseconds ms';

  /// Volume step shown next to the slider.
  static String volumeStepValue(int percent) => '$percent %';
}
