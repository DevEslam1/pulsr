// lib/features/system_behavior/system_behavior_settings.dart
//
// Persisted user choices for the system-behaviour pack. The settings class is
// one ChangeNotifier over SharedPreferences so the screen stays reactive, and
// it hands the service an immutable snapshot per event, so a decision never
// observes a half-written settings object.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';

/// How the exclusive USB path reacts when audio focus is lost.
enum UsbReleaseOnFocusLoss {
  /// Keep the USB claim across every focus loss; the DAC keeps the route.
  never,

  /// Release only on a permanent loss (phone call, another player taking over).
  permanent,

  /// Release on permanent *and* transient losses (navigation prompt, ding).
  transient;

  /// Parses a persisted value, falling back to [never] for unknown or null
  /// names so a downgrade or a renamed value cannot crash startup.
  static UsbReleaseOnFocusLoss parse(String? raw) => values.firstWhere(
        (UsbReleaseOnFocusLoss value) => value.name == raw,
        orElse: () => UsbReleaseOnFocusLoss.never,
      );
}

/// Shape of the software volume taper used by the volume-key stepping logic.
enum SoftwareVolumeCurve {
  /// Every step moves the same amount of linear gain.
  linear,

  /// Every step moves the same amount of perceived loudness; linear gain is
  /// squared so low levels get fine control and high levels get coarse control.
  logarithmic;

  /// Parses a persisted value, falling back to [linear] for unknown or null
  /// names.
  static SoftwareVolumeCurve parse(String? raw) => values.firstWhere(
        (SoftwareVolumeCurve value) => value.name == raw,
        orElse: () => SoftwareVolumeCurve.linear,
      );
}

/// Preference keys owned by the system-behaviour module.
///
/// They deliberately live here instead of `PrefsKeys`: the module owns its
/// storage contract and the `sysbeh_` prefix keeps it out of the global
/// preference namespace.
abstract final class SystemBehaviorPrefsKeys {
  static const String usbReleaseOnFocusLoss =
      'sysbeh_usb_release_on_focus_loss';
  static const String closeUsbWhenBackgrounded =
      'sysbeh_close_usb_when_backgrounded';
  static const String pauseOnNotificationSound =
      'sysbeh_pause_on_notification_sound';
  static const String stopWhenTaskRemoved = 'sysbeh_stop_when_task_removed';
  static const String volumeRockerTrackSwitch =
      'sysbeh_volume_rocker_track_switch';
  static const String fadeOutOnPauseMs = 'sysbeh_fade_out_on_pause_ms';
  static const String softwareVolumeCurve = 'sysbeh_software_volume_curve';
  static const String volumeStepPercent = 'sysbeh_volume_step_percent';
  static const String resumeAfterCall = 'sysbeh_resume_after_call';
}

/// Immutable settings values handed to the system-event decisions.
///
/// Construct through [SystemBehaviorSettingsSnapshot.normalized] (or its
/// [copyWith]) so persisted garbage is clamped once, at the boundary: a fade
/// outside 0..2000 ms or a step outside 2..10 % can never reach the policy.
@immutable
class SystemBehaviorSettingsSnapshot {
  /// Creates a snapshot. Values are assumed already normalized; prefer
  /// [SystemBehaviorSettingsSnapshot.normalized] for untrusted input.
  const SystemBehaviorSettingsSnapshot({
    this.usbReleaseOnFocusLoss = UsbReleaseOnFocusLoss.never,
    this.closeUsbWhenBackgrounded = false,
    this.pauseOnNotificationSound = true,
    this.stopWhenTaskRemoved = false,
    this.volumeRockerTrackSwitch = false,
    this.fadeOutOnPauseMs = 0,
    this.softwareVolumeCurve = SoftwareVolumeCurve.linear,
    this.volumeStepPercent = 5,
    this.resumeAfterCall = true,
  });

  /// Creates a snapshot with every numeric value clamped into its range.
  factory SystemBehaviorSettingsSnapshot.normalized({
    UsbReleaseOnFocusLoss usbReleaseOnFocusLoss = UsbReleaseOnFocusLoss.never,
    bool closeUsbWhenBackgrounded = false,
    bool pauseOnNotificationSound = true,
    bool stopWhenTaskRemoved = false,
    bool volumeRockerTrackSwitch = false,
    int fadeOutOnPauseMs = 0,
    SoftwareVolumeCurve softwareVolumeCurve = SoftwareVolumeCurve.linear,
    int volumeStepPercent = 5,
    bool resumeAfterCall = true,
  }) {
    return SystemBehaviorSettingsSnapshot(
      usbReleaseOnFocusLoss: usbReleaseOnFocusLoss,
      closeUsbWhenBackgrounded: closeUsbWhenBackgrounded,
      pauseOnNotificationSound: pauseOnNotificationSound,
      stopWhenTaskRemoved: stopWhenTaskRemoved,
      volumeRockerTrackSwitch: volumeRockerTrackSwitch,
      fadeOutOnPauseMs:
          fadeOutOnPauseMs.clamp(minFadeOutOnPauseMs, maxFadeOutOnPauseMs),
      softwareVolumeCurve: softwareVolumeCurve,
      volumeStepPercent:
          volumeStepPercent.clamp(minVolumeStepPercent, maxVolumeStepPercent),
      resumeAfterCall: resumeAfterCall,
    );
  }

  /// Factory defaults: the least surprising behaviour on a fresh install.
  static const SystemBehaviorSettingsSnapshot defaults =
      SystemBehaviorSettingsSnapshot();

  /// Smallest accepted fade duration (no fade).
  static const int minFadeOutOnPauseMs = 0;

  /// Largest accepted fade duration.
  static const int maxFadeOutOnPauseMs = 2000;

  /// Smallest accepted volume step.
  static const int minVolumeStepPercent = 2;

  /// Largest accepted volume step.
  static const int maxVolumeStepPercent = 10;

  /// Whether the exclusive USB claim is dropped on a focus loss.
  final UsbReleaseOnFocusLoss usbReleaseOnFocusLoss;

  /// Whether the USB claim is dropped when the app leaves the foreground.
  final bool closeUsbWhenBackgrounded;

  /// Whether a system notification sound pauses instead of ducking.
  final bool pauseOnNotificationSound;

  /// Whether removing the app from the recents list stops playback.
  final bool stopWhenTaskRemoved;

  /// Whether a double press of a volume rocker skips to the next track.
  final bool volumeRockerTrackSwitch;

  /// Fade-out ramp length applied before a pause, in milliseconds.
  final int fadeOutOnPauseMs;

  /// Taper used by the volume-key stepping logic.
  final SoftwareVolumeCurve softwareVolumeCurve;

  /// Size of one volume step, in percent of the full scale.
  final int volumeStepPercent;

  /// Whether playback resumes when a call or another interruption ends.
  final bool resumeAfterCall;

  /// Fade-out ramp as a [Duration]; [Duration.zero] when the fade is off.
  Duration get fadeOutDuration => Duration(milliseconds: fadeOutOnPauseMs);

  /// Copy with the given values replaced; numbers are re-clamped.
  SystemBehaviorSettingsSnapshot copyWith({
    UsbReleaseOnFocusLoss? usbReleaseOnFocusLoss,
    bool? closeUsbWhenBackgrounded,
    bool? pauseOnNotificationSound,
    bool? stopWhenTaskRemoved,
    bool? volumeRockerTrackSwitch,
    int? fadeOutOnPauseMs,
    SoftwareVolumeCurve? softwareVolumeCurve,
    int? volumeStepPercent,
    bool? resumeAfterCall,
  }) {
    return SystemBehaviorSettingsSnapshot.normalized(
      usbReleaseOnFocusLoss:
          usbReleaseOnFocusLoss ?? this.usbReleaseOnFocusLoss,
      closeUsbWhenBackgrounded:
          closeUsbWhenBackgrounded ?? this.closeUsbWhenBackgrounded,
      pauseOnNotificationSound:
          pauseOnNotificationSound ?? this.pauseOnNotificationSound,
      stopWhenTaskRemoved: stopWhenTaskRemoved ?? this.stopWhenTaskRemoved,
      volumeRockerTrackSwitch:
          volumeRockerTrackSwitch ?? this.volumeRockerTrackSwitch,
      fadeOutOnPauseMs: fadeOutOnPauseMs ?? this.fadeOutOnPauseMs,
      softwareVolumeCurve: softwareVolumeCurve ?? this.softwareVolumeCurve,
      volumeStepPercent: volumeStepPercent ?? this.volumeStepPercent,
      resumeAfterCall: resumeAfterCall ?? this.resumeAfterCall,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SystemBehaviorSettingsSnapshot &&
        other.usbReleaseOnFocusLoss == usbReleaseOnFocusLoss &&
        other.closeUsbWhenBackgrounded == closeUsbWhenBackgrounded &&
        other.pauseOnNotificationSound == pauseOnNotificationSound &&
        other.stopWhenTaskRemoved == stopWhenTaskRemoved &&
        other.volumeRockerTrackSwitch == volumeRockerTrackSwitch &&
        other.fadeOutOnPauseMs == fadeOutOnPauseMs &&
        other.softwareVolumeCurve == softwareVolumeCurve &&
        other.volumeStepPercent == volumeStepPercent &&
        other.resumeAfterCall == resumeAfterCall;
  }

  @override
  int get hashCode => Object.hash(
        usbReleaseOnFocusLoss,
        closeUsbWhenBackgrounded,
        pauseOnNotificationSound,
        stopWhenTaskRemoved,
        volumeRockerTrackSwitch,
        fadeOutOnPauseMs,
        softwareVolumeCurve,
        volumeStepPercent,
        resumeAfterCall,
      );

  @override
  String toString() => 'SystemBehaviorSettingsSnapshot('
      'usbReleaseOnFocusLoss: ${usbReleaseOnFocusLoss.name}, '
      'closeUsbWhenBackgrounded: $closeUsbWhenBackgrounded, '
      'pauseOnNotificationSound: $pauseOnNotificationSound, '
      'stopWhenTaskRemoved: $stopWhenTaskRemoved, '
      'volumeRockerTrackSwitch: $volumeRockerTrackSwitch, '
      'fadeOutOnPauseMs: $fadeOutOnPauseMs, '
      'softwareVolumeCurve: ${softwareVolumeCurve.name}, '
      'volumeStepPercent: $volumeStepPercent, '
      'resumeAfterCall: $resumeAfterCall)';
}

/// Live, persisted system-behaviour settings.
///
/// Every setter updates the in-memory snapshot, notifies listeners and then
/// writes its own key. A failed write is logged and does not roll the value
/// back: the UI already shows the user's choice, and the next successful write
/// of that key repairs the stored value.
class SystemBehaviorSettings extends ChangeNotifier {
  SystemBehaviorSettings();

  SystemBehaviorSettingsSnapshot _snapshot =
      SystemBehaviorSettingsSnapshot.defaults;
  bool _loaded = false;
  bool _disposed = false;

  /// Current values; the service reads this once per event.
  SystemBehaviorSettingsSnapshot get snapshot => _snapshot;

  /// Whether [load] has completed at least once.
  bool get isLoaded => _loaded;

  /// Whether the exclusive USB claim is dropped on focus loss.
  UsbReleaseOnFocusLoss get usbReleaseOnFocusLoss =>
      _snapshot.usbReleaseOnFocusLoss;

  /// Whether the USB claim is dropped when the app leaves the foreground.
  bool get closeUsbWhenBackgrounded => _snapshot.closeUsbWhenBackgrounded;

  /// Whether a system notification sound pauses instead of ducking.
  bool get pauseOnNotificationSound => _snapshot.pauseOnNotificationSound;

  /// Whether removing the app from recents stops playback.
  bool get stopWhenTaskRemoved => _snapshot.stopWhenTaskRemoved;

  /// Whether a volume-rocker double press skips to the next track.
  bool get volumeRockerTrackSwitch => _snapshot.volumeRockerTrackSwitch;

  /// Fade-out ramp length before a pause, in milliseconds.
  int get fadeOutOnPauseMs => _snapshot.fadeOutOnPauseMs;

  /// Taper used by the volume-key stepping logic.
  SoftwareVolumeCurve get softwareVolumeCurve => _snapshot.softwareVolumeCurve;

  /// Size of one volume step, in percent of the full scale.
  int get volumeStepPercent => _snapshot.volumeStepPercent;

  /// Whether playback resumes when a call or another interruption ends.
  bool get resumeAfterCall => _snapshot.resumeAfterCall;

  /// Reads every key. Safe to call more than once; missing or unparseable
  /// values keep their defaults or are clamped into range.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _snapshot = SystemBehaviorSettingsSnapshot.normalized(
        usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.parse(
          prefs.getString(SystemBehaviorPrefsKeys.usbReleaseOnFocusLoss),
        ),
        closeUsbWhenBackgrounded:
            prefs.getBool(SystemBehaviorPrefsKeys.closeUsbWhenBackgrounded) ??
                SystemBehaviorSettingsSnapshot
                    .defaults.closeUsbWhenBackgrounded,
        pauseOnNotificationSound:
            prefs.getBool(SystemBehaviorPrefsKeys.pauseOnNotificationSound) ??
                SystemBehaviorSettingsSnapshot
                    .defaults.pauseOnNotificationSound,
        stopWhenTaskRemoved:
            prefs.getBool(SystemBehaviorPrefsKeys.stopWhenTaskRemoved) ??
                SystemBehaviorSettingsSnapshot.defaults.stopWhenTaskRemoved,
        volumeRockerTrackSwitch:
            prefs.getBool(SystemBehaviorPrefsKeys.volumeRockerTrackSwitch) ??
                SystemBehaviorSettingsSnapshot
                    .defaults.volumeRockerTrackSwitch,
        fadeOutOnPauseMs:
            prefs.getInt(SystemBehaviorPrefsKeys.fadeOutOnPauseMs) ??
                SystemBehaviorSettingsSnapshot.defaults.fadeOutOnPauseMs,
        softwareVolumeCurve: SoftwareVolumeCurve.parse(
          prefs.getString(SystemBehaviorPrefsKeys.softwareVolumeCurve),
        ),
        volumeStepPercent:
            prefs.getInt(SystemBehaviorPrefsKeys.volumeStepPercent) ??
                SystemBehaviorSettingsSnapshot.defaults.volumeStepPercent,
        resumeAfterCall:
            prefs.getBool(SystemBehaviorPrefsKeys.resumeAfterCall) ??
                SystemBehaviorSettingsSnapshot.defaults.resumeAfterCall,
      );
      _loaded = true;
    } catch (e, st) {
      ErrorLogger.log(
        'Loading system-behaviour settings failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehaviorSettings',
      );
    }
    if (!_disposed) notifyListeners();
  }

  /// Sets how the USB claim reacts to a focus loss.
  Future<void> setUsbReleaseOnFocusLoss(UsbReleaseOnFocusLoss value) {
    return _apply(
      _snapshot.copyWith(usbReleaseOnFocusLoss: value),
      (SharedPreferences prefs) => prefs.setString(
          SystemBehaviorPrefsKeys.usbReleaseOnFocusLoss, value.name),
    );
  }

  /// Sets whether the USB claim is dropped when the app is backgrounded.
  Future<void> setCloseUsbWhenBackgrounded(bool value) {
    return _apply(
      _snapshot.copyWith(closeUsbWhenBackgrounded: value),
      (SharedPreferences prefs) => prefs.setBool(
          SystemBehaviorPrefsKeys.closeUsbWhenBackgrounded, value),
    );
  }

  /// Sets whether a notification sound pauses instead of ducking.
  Future<void> setPauseOnNotificationSound(bool value) {
    return _apply(
      _snapshot.copyWith(pauseOnNotificationSound: value),
      (SharedPreferences prefs) => prefs.setBool(
          SystemBehaviorPrefsKeys.pauseOnNotificationSound, value),
    );
  }

  /// Sets whether removing the task stops playback.
  Future<void> setStopWhenTaskRemoved(bool value) {
    return _apply(
      _snapshot.copyWith(stopWhenTaskRemoved: value),
      (SharedPreferences prefs) =>
          prefs.setBool(SystemBehaviorPrefsKeys.stopWhenTaskRemoved, value),
    );
  }

  /// Sets whether a volume-rocker double press skips to the next track.
  Future<void> setVolumeRockerTrackSwitch(bool value) {
    return _apply(
      _snapshot.copyWith(volumeRockerTrackSwitch: value),
      (SharedPreferences prefs) => prefs.setBool(
          SystemBehaviorPrefsKeys.volumeRockerTrackSwitch, value),
    );
  }

  /// Sets the fade-out ramp length; values outside 0..2000 ms are clamped.
  Future<void> setFadeOutOnPauseMs(int value) {
    final SystemBehaviorSettingsSnapshot next =
        _snapshot.copyWith(fadeOutOnPauseMs: value);
    return _apply(
      next,
      (SharedPreferences prefs) => prefs.setInt(
          SystemBehaviorPrefsKeys.fadeOutOnPauseMs, next.fadeOutOnPauseMs),
    );
  }

  /// Sets the volume taper used by the stepping logic.
  Future<void> setSoftwareVolumeCurve(SoftwareVolumeCurve value) {
    return _apply(
      _snapshot.copyWith(softwareVolumeCurve: value),
      (SharedPreferences prefs) => prefs.setString(
          SystemBehaviorPrefsKeys.softwareVolumeCurve, value.name),
    );
  }

  /// Sets the volume step in percent; values outside 2..10 are clamped.
  Future<void> setVolumeStepPercent(int value) {
    final SystemBehaviorSettingsSnapshot next =
        _snapshot.copyWith(volumeStepPercent: value);
    return _apply(
      next,
      (SharedPreferences prefs) => prefs.setInt(
          SystemBehaviorPrefsKeys.volumeStepPercent, next.volumeStepPercent),
    );
  }

  /// Sets whether playback resumes after a call.
  Future<void> setResumeAfterCall(bool value) {
    return _apply(
      _snapshot.copyWith(resumeAfterCall: value),
      (SharedPreferences prefs) =>
          prefs.setBool(SystemBehaviorPrefsKeys.resumeAfterCall, value),
    );
  }

  Future<void> _apply(
    SystemBehaviorSettingsSnapshot next,
    Future<bool> Function(SharedPreferences prefs) persist,
  ) async {
    if (_disposed || next == _snapshot) return;
    _snapshot = next;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await persist(prefs);
    } catch (e, st) {
      ErrorLogger.log(
        'Persisting a system-behaviour setting failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehaviorSettings',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
