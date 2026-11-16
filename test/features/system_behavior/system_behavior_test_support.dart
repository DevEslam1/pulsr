// test/features/system_behavior/system_behavior_test_support.dart
//
// Shared helpers for the system-behaviour tests: a recording playback port
// (no platform, no audio handler) and a settings loader that exercises the
// real SharedPreferences code path.

import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/system_behavior/system_behavior_service.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [SystemPlaybackPort] that records every call in order.
class RecordingPlaybackPort implements SystemPlaybackPort {
  RecordingPlaybackPort({this.volume = 0.5, this.playing = true});

  /// Current volume the fake is at; updated by [setVolume].
  double volume;

  /// Whether the fake reports playback as running.
  bool playing;

  /// Ordered call log, e.g. `volume:0.4`, `pause`.
  final List<String> calls = <String>[];

  /// Every volume the service pushed, in order.
  final List<double> volumes = <double>[];

  /// Number of play calls.
  int playCount = 0;

  /// Number of pause calls.
  int pauseCount = 0;

  /// Number of stop calls.
  int stopCount = 0;

  /// Number of next calls.
  int nextCount = 0;

  @override
  Future<void> play() async {
    playCount += 1;
    playing = true;
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    playing = false;
    calls.add('pause');
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    playing = false;
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
///
/// The notification policy lives in [PrefsKeys.duckingMode] (the single source
/// shared with the audio settings screen), not in a `sysbeh_` key.
Future<SystemBehaviorSettings> loadSettings({
  UsbReleaseOnFocusLoss usbReleaseOnFocusLoss = UsbReleaseOnFocusLoss.never,
  bool closeUsbWhenBackgrounded = false,
  bool pauseOnNotificationSound = false,
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
    PrefsKeys.duckingMode: pauseOnNotificationSound ? 'pause' : 'duck',
    SystemBehaviorPrefsKeys.stopWhenTaskRemoved: stopWhenTaskRemoved,
    SystemBehaviorPrefsKeys.volumeRockerTrackSwitch: volumeRockerTrackSwitch,
    SystemBehaviorPrefsKeys.fadeOutOnPauseMs: fadeOutOnPauseMs,
    SystemBehaviorPrefsKeys.softwareVolumeCurve: softwareVolumeCurve.name,
    SystemBehaviorPrefsKeys.volumeStepPercent: volumeStepPercent,
    PrefsKeys.resumeAfterInterruption: resumeAfterCall,
  });
  final SystemBehaviorSettings settings = SystemBehaviorSettings();
  await settings.load();
  return settings;
}

/// Builds a service wired to [port] for the given settings.
SystemBehaviorService buildService({
  required SystemBehaviorSettings settings,
  required RecordingPlaybackPort port,
  bool? playing,
  Future<bool> Function(bool enabled)? usbRelease,
  Future<void> Function()? resumePlayback,
  DateTime Function()? clock,
}) {
  return SystemBehaviorService(
    settings: settings,
    port: port,
    volumeReader: () => port.volume,
    isPlaying: () => playing ?? port.playing,
    resumePlayback: resumePlayback,
    usbRelease: usbRelease ?? (bool enabled) async => true,
    clock: clock,
  );
}
