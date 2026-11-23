// lib/features/system_behavior/system_behavior_strings.dart
//
// Localized copy for the system-behaviour module, backed by ARB
// (`AppLocalizations`) with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing copy for the system-behaviour feature.
abstract final class SystemBehaviorStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  static String get screenTitle => _l10n().sysBehavScreenTitle;

  static String get sectionFocus => _l10n().sysBehavSectionFocus;
  static String get sectionUsb => _l10n().sysBehavSectionUsb;
  static String get sectionVolume => _l10n().sysBehavSectionVolume;
  static String get sectionLifecycle => _l10n().sysBehavSectionLifecycle;

  static String get pauseOnNotificationSoundTitle =>
      _l10n().sysBehavPauseOnNotifTitle;
  static String get pauseOnNotificationSoundSubtitle =>
      _l10n().sysBehavPauseOnNotifSubtitle;

  static String get resumeAfterCallTitle =>
      _l10n().sysBehavResumeAfterCallTitle;
  static String get resumeAfterCallSubtitle =>
      _l10n().sysBehavResumeAfterCallSubtitle;

  static String get usbReleaseOnFocusLossTitle =>
      _l10n().sysBehavUsbReleaseTitle;
  static String get usbReleaseOnFocusLossSubtitle =>
      _l10n().sysBehavUsbReleaseSubtitle;

  static String get usbReleaseNever => _l10n().sysBehavUsbReleaseNever;
  static String get usbReleasePermanent => _l10n().sysBehavUsbReleasePermanent;
  static String get usbReleaseTransient => _l10n().sysBehavUsbReleaseTransient;
  static String get usbReleaseNeverIconLabel =>
      _l10n().sysBehavUsbReleaseNeverIconLabel;
  static String get usbReleasePermanentIconLabel =>
      _l10n().sysBehavUsbReleasePermanentIconLabel;
  static String get usbReleaseTransientIconLabel =>
      _l10n().sysBehavUsbReleaseTransientIconLabel;

  static String get closeUsbWhenBackgroundedTitle =>
      _l10n().sysBehavCloseUsbBgTitle;
  static String get closeUsbWhenBackgroundedSubtitle =>
      _l10n().sysBehavCloseUsbBgSubtitle;

  static String get volumeRockerTrackSwitchTitle =>
      _l10n().sysBehavVolumeRockerTitle;
  static String get volumeRockerTrackSwitchSubtitle =>
      _l10n().sysBehavVolumeRockerSubtitle;

  static String get softwareVolumeCurveTitle =>
      _l10n().sysBehavVolumeCurveTitle;
  static String get softwareVolumeCurveSubtitle =>
      _l10n().sysBehavVolumeCurveSubtitle;

  static String get curveLinear => _l10n().sysBehavCurveLinear;
  static String get curveLogarithmic => _l10n().sysBehavCurveLogarithmic;
  static String get curveLinearIconLabel =>
      _l10n().sysBehavCurveLinearIconLabel;
  static String get curveLogarithmicIconLabel =>
      _l10n().sysBehavCurveLogarithmicIconLabel;

  static String get volumeStepPercentTitle => _l10n().sysBehavVolumeStepTitle;
  static String get volumeStepPercentSubtitle =>
      _l10n().sysBehavVolumeStepSubtitle;

  static String get fadeOutOnPauseMsTitle => _l10n().sysBehavFadeOutPauseTitle;
  static String get fadeOutOnPauseMsSubtitle =>
      _l10n().sysBehavFadeOutPauseSubtitle;

  static String get fadeOffValue => _l10n().sysBehavFadeOffValue;

  static String get stopWhenTaskRemovedTitle =>
      _l10n().sysBehavStopTaskRemovedTitle;
  static String get stopWhenTaskRemovedSubtitle =>
      _l10n().sysBehavStopTaskRemovedSubtitle;

  static String get androidOnlyLimit => _l10n().sysBehavAndroidOnlyLimit;
  static String get usbOnlyLimit => _l10n().sysBehavUsbOnlyLimit;
  static String get volumeRockerLimit => _l10n().sysBehavVolumeRockerLimit;

  /// Fade length shown next to the slider.
  static String fadeValue(int milliseconds, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return milliseconds == 0
        ? l.sysBehavFadeOffValue
        : l.sysBehavFadeValueMs(milliseconds);
  }

  /// Volume step shown next to the slider.
  static String volumeStepValue(int percent, [AppLocalizations? l10n]) =>
      _l10n(l10n).sysBehavVolumeStepValue(percent);
}
