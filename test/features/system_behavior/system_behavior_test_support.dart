// test/features/system_behavior/system_behavior_test_support.dart
//
// Shared helpers for the system-behaviour tests: a recording playback port
// (no platform, no audio handler) and a settings loader that exercises the
// real SharedPreferences code path.

import 'package:pulsr/features/system_behavior/system_behavior_service.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [SystemPlaybackPort] that records every call in order.
class RecordingPlaybackPort implements SystemPlaybackPort {
  RecordingPlaybackPort({this.volume = 0.5});

  /// Current volume the fake is at; updated by [setVolume].
  double volume;

  /// Ordered call log, e.g. `volume:0.4`, `pause`.
  final List<String> calls = <String>[];

  /// Every volume the service pushed, in order.
  final List<double> volumes = <double>[];

  /// Number of pause calls.
  int pauseCount = 0;

  /// Number of stop calls.
  int stopCount = 0;

  /// Number of next calls.
  int nextCount = 0;

  @override
  Future<void> pause() async {
    pauseCount += 1;
    calls.add('pause');
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    calls.add('stop');
  }

  @override
  Future<void> next() async {
    nextCount += 1;
    calls.add('next');
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    volumes.add(value);
    calls.add('volume:$value');
  }
}

/// Builds a loaded [SystemBehaviorSettings] from the given persisted values.
Future<SystemBehaviorSettings> loadSettings({
  UsbReleaseOnFocusLoss usbReleaseOnFocusLoss = UsbReleaseOnFocusLoss.never,
  bool closeUsbWhenBackgrounded = false,
  bool pauseOnNotificationSound = true,
  bool stopWhenTaskRemoved = false,
  bool volumeRockerTrackSwitch = false,
  int fadeOutOnPauseMs = 0,
  SoftwareVolumeCurve softwareVolumeCurve = SoftwareVolumeCurve.linear,
  int volumeStepPercent = 5,
  bool resumeAfterCall = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    SystemBehaviorPrefsKeys.usbReleaseOnFocusLoss:
        usbReleaseOnFocusLoss.name,
    SystemBehaviorPrefsKeys.closeUsbWhenBackgrounded:
        closeUsbWhenBackgrounded,
    SystemBehaviorPrefsKeys.pauseOnNotificationSound: pauseOnNotificationSound,
    SystemBehaviorPrefsKeys.stopWhenTaskRemoved: stopWhenTaskRemoved,
    SystemBehaviorPrefsKeys.volumeRockerTrackSwitch: volumeRockerTrackSwitch,
    SystemBehaviorPrefsKeys.fadeOutOnPauseMs: fadeOutOnPauseMs,
    SystemBehaviorPrefsKeys.softwareVolumeCurve: softwareVolumeCurve.name,
    SystemBehaviorPrefsKeys.volumeStepPercent: volumeStepPercent,
    SystemBehaviorPrefsKeys.resumeAfterCall: resumeAfterCall,
  });
  final SystemBehaviorSettings settings = SystemBehaviorSettings();
  await settings.load();
  return settings;
}

/// Builds a service wired to [port] for the given settings.
SystemBehaviorService buildService({
  required SystemBehaviorSettings settings,
  required RecordingPlaybackPort port,
  bool playing = true,
  Future<bool> Function(bool enabled)? usbRelease,
  Future<void> Function()? resumePlayback,
  DateTime Function()? clock,
}) {
  return SystemBehaviorService(
    settings: settings,
    port: port,
    volumeReader: () => port.volume,
    isPlaying: () => playing,
    resumePlayback: resumePlayback,
    usbRelease: usbRelease ?? (bool enabled) async => true,
    clock: clock,
  );
}
