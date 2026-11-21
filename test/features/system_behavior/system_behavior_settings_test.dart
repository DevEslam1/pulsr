// test/features/system_behavior/system_behavior_settings_test.dart
//
// Persistence contract: defaults on a fresh install, a full round-trip through
// SharedPreferences, tolerance for unknown enum names, clamping at the boundary,
// and no notifications after dispose.

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a fresh install reports the documented defaults', () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    expect(settings.isLoaded, isFalse);

    await settings.load();

    expect(settings.isLoaded, isTrue);
    expect(settings.snapshot, SystemBehaviorSettingsSnapshot.defaults);
    expect(settings.usbReleaseOnFocusLoss, UsbReleaseOnFocusLoss.never);
    expect(settings.closeUsbWhenBackgrounded, isFalse);
    expect(
      settings.pauseOnNotificationSound,
      isFalse,
      reason: 'the app default ducking mode is duck',
    );
    expect(settings.stopWhenTaskRemoved, isFalse);
    expect(settings.volumeRockerTrackSwitch, isFalse);
    expect(settings.fadeOutOnPauseMs, 0);
    expect(settings.softwareVolumeCurve, SoftwareVolumeCurve.linear);
    expect(settings.volumeStepPercent, 5);
    expect(settings.resumeAfterCall, isTrue);
  });

  test('the notification policy reads the app duckingMode pref', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.duckingMode: 'pause',
    });

    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    expect(settings.pauseOnNotificationSound, isTrue);
    expect(settings.snapshot.pauseOnNotificationSound, isTrue);
  });

  test('a stored audio duckingMode change is reflected without reload',
      () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();
    expect(settings.pauseOnNotificationSound, isFalse);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.duckingMode, 'pause');

    expect(
      settings.pauseOnNotificationSound,
      isTrue,
      reason: 'the screen must not keep a stale copy of the audio setting',
    );
    expect(settings.snapshot.pauseOnNotificationSound, isTrue);
  });

  test('a legacy sysbeh policy key cannot override duckingMode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sysbeh_pause_on_notification_sound': true,
      PrefsKeys.duckingMode: 'duck',
    });

    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    expect(settings.pauseOnNotificationSound, isFalse);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sysbeh_pause_on_notification_sound'), isTrue,
        reason: 'the old key is ignored, never read or migrated');
    expect(prefs.getString(PrefsKeys.duckingMode), 'duck');
  });

  test('setPauseOnNotificationSound writes duckingMode, not a new pref',
      () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    await settings.setPauseOnNotificationSound(true);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.duckingMode), 'pause');
    expect(prefs.containsKey('sysbeh_pause_on_notification_sound'), isFalse);
    expect(settings.pauseOnNotificationSound, isTrue);

    await settings.setPauseOnNotificationSound(false);
    expect(prefs.getString(PrefsKeys.duckingMode), 'duck');
    expect(settings.pauseOnNotificationSound, isFalse);
  });

  test('every value round-trips through prefs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SystemBehaviorPrefsKeys.usbReleaseOnFocusLoss: 'transient',
      SystemBehaviorPrefsKeys.closeUsbWhenBackgrounded: true,
      PrefsKeys.duckingMode: 'pause',
      SystemBehaviorPrefsKeys.stopWhenTaskRemoved: true,
      SystemBehaviorPrefsKeys.volumeRockerTrackSwitch: true,
      SystemBehaviorPrefsKeys.fadeOutOnPauseMs: 750,
      SystemBehaviorPrefsKeys.softwareVolumeCurve: 'logarithmic',
      SystemBehaviorPrefsKeys.volumeStepPercent: 8,
      PrefsKeys.resumeAfterInterruption: false,
    });

    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    expect(settings.snapshot.usbReleaseOnFocusLoss,
        UsbReleaseOnFocusLoss.transient);
    expect(settings.snapshot.closeUsbWhenBackgrounded, isTrue);
    expect(settings.snapshot.pauseOnNotificationSound, isTrue);
    expect(settings.snapshot.stopWhenTaskRemoved, isTrue);
    expect(settings.snapshot.volumeRockerTrackSwitch, isTrue);
    expect(settings.snapshot.fadeOutOnPauseMs, 750);
    expect(settings.snapshot.softwareVolumeCurve, SoftwareVolumeCurve.logarithmic);
    expect(settings.snapshot.volumeStepPercent, 8);
    expect(settings.snapshot.resumeAfterCall, isFalse);
  });

  test('setters persist and survive a restart', () async {
    final SystemBehaviorSettings first = SystemBehaviorSettings();
    await first.load();

    await first.setUsbReleaseOnFocusLoss(UsbReleaseOnFocusLoss.permanent);
    await first.setCloseUsbWhenBackgrounded(true);
    await first.setPauseOnNotificationSound(true);
    await first.setStopWhenTaskRemoved(true);
    await first.setVolumeRockerTrackSwitch(true);
    await first.setFadeOutOnPauseMs(320);
    await first.setSoftwareVolumeCurve(SoftwareVolumeCurve.logarithmic);
    await first.setVolumeStepPercent(7);
    await first.setResumeAfterCall(false);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SystemBehaviorPrefsKeys.usbReleaseOnFocusLoss),
        'permanent');
    expect(prefs.getBool(SystemBehaviorPrefsKeys.closeUsbWhenBackgrounded),
        isTrue);
    expect(prefs.getString(PrefsKeys.duckingMode), 'pause');
    expect(prefs.getBool(SystemBehaviorPrefsKeys.stopWhenTaskRemoved), isTrue);
    expect(prefs.getBool(SystemBehaviorPrefsKeys.volumeRockerTrackSwitch),
        isTrue);
    expect(prefs.getInt(SystemBehaviorPrefsKeys.fadeOutOnPauseMs), 320);
    expect(prefs.getString(SystemBehaviorPrefsKeys.softwareVolumeCurve),
        'logarithmic');
    expect(prefs.getInt(SystemBehaviorPrefsKeys.volumeStepPercent), 7);
    expect(prefs.getBool(PrefsKeys.resumeAfterInterruption), isFalse);

    final SystemBehaviorSettings restarted = SystemBehaviorSettings();
    await restarted.load();
    expect(restarted.snapshot, first.snapshot);
  });

  test('unknown enum names fall back to the safe default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SystemBehaviorPrefsKeys.usbReleaseOnFocusLoss: 'whenever',
      SystemBehaviorPrefsKeys.softwareVolumeCurve: 'cubic',
      SystemBehaviorPrefsKeys.fadeOutOnPauseMs: 500,
    });

    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    expect(settings.usbReleaseOnFocusLoss, UsbReleaseOnFocusLoss.never);
    expect(settings.softwareVolumeCurve, SoftwareVolumeCurve.linear);
    // The rest of the file still loads.
    expect(settings.fadeOutOnPauseMs, 500);
    expect(settings.pauseOnNotificationSound, isFalse);
  });

  test('unknown enum names never throw on parse', () {
    expect(UsbReleaseOnFocusLoss.parse(null), UsbReleaseOnFocusLoss.never);
    expect(UsbReleaseOnFocusLoss.parse(''), UsbReleaseOnFocusLoss.never);
    expect(UsbReleaseOnFocusLoss.parse('TRANSIENT'),
        UsbReleaseOnFocusLoss.never);
    expect(UsbReleaseOnFocusLoss.parse('transient'),
        UsbReleaseOnFocusLoss.transient);
    expect(SoftwareVolumeCurve.parse('nope'), SoftwareVolumeCurve.linear);
    expect(SoftwareVolumeCurve.parse('logarithmic'),
        SoftwareVolumeCurve.logarithmic);
  });

  test('persisted numbers are clamped into range', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SystemBehaviorPrefsKeys.fadeOutOnPauseMs: 99999,
      SystemBehaviorPrefsKeys.volumeStepPercent: 0,
    });

    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    expect(settings.fadeOutOnPauseMs, 2000);
    expect(settings.volumeStepPercent, 2);
  });

  test('setters clamp and write the clamped value', () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();

    await settings.setFadeOutOnPauseMs(5000);
    await settings.setFadeOutOnPauseMs(-20);
    await settings.setVolumeStepPercent(99);
    await settings.setVolumeStepPercent(1);

    expect(settings.fadeOutOnPauseMs, 0);
    expect(settings.volumeStepPercent, 2);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(SystemBehaviorPrefsKeys.fadeOutOnPauseMs), 0);
    expect(prefs.getInt(SystemBehaviorPrefsKeys.volumeStepPercent), 2);
  });

  test('listeners fire on real changes only', () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();
    int notifications = 0;
    settings.addListener(() => notifications += 1);

    await settings.setResumeAfterCall(false);
    expect(notifications, 1);

    await settings.setResumeAfterCall(false);
    expect(notifications, 1, reason: 'no notification for an unchanged value');

    await settings.setResumeAfterCall(true);
    expect(notifications, 2);
  });

  test('dispose stops notifications and makes setters inert', () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();
    int notifications = 0;
    settings.addListener(() => notifications += 1);

    settings.dispose();
    await settings.setResumeAfterCall(false);

    expect(notifications, 0);
    expect(settings.resumeAfterCall, isTrue);
    expect(settings.snapshot, SystemBehaviorSettingsSnapshot.defaults);
  });

  test('load can be called twice without duplicating state', () async {
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();
    await settings.setVolumeStepPercent(9);
    await settings.load();
    expect(settings.volumeStepPercent, 9);
    expect(settings.isLoaded, isTrue);
  });

  test('resumeAfterCall getter reflects live shared preferences overlay', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.resumeAfterInterruption, true);
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();
    expect(settings.resumeAfterCall, isTrue);

    await prefs.setBool(PrefsKeys.resumeAfterInterruption, false);
    expect(settings.resumeAfterCall, isFalse);
  });
}
