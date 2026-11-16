// test/features/system_behavior/system_behavior_policy_test.dart
//
// The decision table is the contract of the whole feature, so it is asserted
// twice: once as a literal table (every event x every named setting variant)
// and once as an exhaustive property sweep over the whole setting space.

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/system_behavior/system_behavior_policy.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';

const Map<String, SystemBehaviorSettingsSnapshot> _variants =
    <String, SystemBehaviorSettingsSnapshot>{
  'defaults': SystemBehaviorSettingsSnapshot(),
  'releasePermanent': SystemBehaviorSettingsSnapshot(
    usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.permanent,
  ),
  'releaseTransient': SystemBehaviorSettingsSnapshot(
    usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.transient,
  ),
  'fade800': SystemBehaviorSettingsSnapshot(fadeOutOnPauseMs: 800),
  'noNotificationPause': SystemBehaviorSettingsSnapshot(
    pauseOnNotificationSound: false,
  ),
  'stopOnTaskRemoval': SystemBehaviorSettingsSnapshot(
    stopWhenTaskRemoved: true,
  ),
  'rockerSwitch': SystemBehaviorSettingsSnapshot(
    volumeRockerTrackSwitch: true,
  ),
};

void _expectRow(SystemEvent event, Map<String, SystemAction> expected) {
  expect(
    expected.keys.toSet(),
    _variants.keys.toSet(),
    reason: 'every variant must appear for ${event.name}',
  );
  expected.forEach((String variant, SystemAction action) {
    expect(
      decide(event, _variants[variant]!),
      action,
      reason: '${event.name} under $variant',
    );
  });
}

void main() {
  group('decision table', () {
    test('permanent focus loss', () {
      _expectRow(SystemEvent.audioFocusLossPermanent, <String, SystemAction>{
        'defaults': SystemAction.pauseKeepUsb,
        'releasePermanent': SystemAction.pauseAndReleaseUsb,
        'releaseTransient': SystemAction.pauseKeepUsb,
        'fade800': SystemAction.fadeOutPause,
        'noNotificationPause': SystemAction.pauseKeepUsb,
        'stopOnTaskRemoval': SystemAction.pauseKeepUsb,
        'rockerSwitch': SystemAction.pauseKeepUsb,
      });
    });

    test('transient focus loss', () {
      _expectRow(SystemEvent.audioFocusLossTransient, <String, SystemAction>{
        'defaults': SystemAction.pauseKeepUsb,
        'releasePermanent': SystemAction.pauseKeepUsb,
        'releaseTransient': SystemAction.pauseAndReleaseUsb,
        'fade800': SystemAction.fadeOutPause,
        'noNotificationPause': SystemAction.pauseKeepUsb,
        'stopOnTaskRemoval': SystemAction.pauseKeepUsb,
        'rockerSwitch': SystemAction.pauseKeepUsb,
      });
    });

    test('focus gain never pokes playback directly', () {
      _expectRow(SystemEvent.audioFocusGain, <String, SystemAction>{
        'defaults': SystemAction.ignore,
        'releasePermanent': SystemAction.ignore,
        'releaseTransient': SystemAction.ignore,
        'fade800': SystemAction.ignore,
        'noNotificationPause': SystemAction.ignore,
        'stopOnTaskRemoval': SystemAction.ignore,
        'rockerSwitch': SystemAction.ignore,
      });
    });

    test('notification sound', () {
      _expectRow(SystemEvent.notificationSound, <String, SystemAction>{
        'defaults': SystemAction.pauseKeepUsb,
        'releasePermanent': SystemAction.pauseKeepUsb,
        'releaseTransient': SystemAction.pauseKeepUsb,
        'fade800': SystemAction.fadeOutPause,
        'noNotificationPause': SystemAction.ignore,
        'stopOnTaskRemoval': SystemAction.pauseKeepUsb,
        'rockerSwitch': SystemAction.pauseKeepUsb,
      });
    });

    test('headset unplug never fades into a dead sink', () {
      _expectRow(SystemEvent.headsetUnplug, <String, SystemAction>{
        'defaults': SystemAction.pauseKeepUsb,
        'releasePermanent': SystemAction.pauseKeepUsb,
        'releaseTransient': SystemAction.pauseKeepUsb,
        'fade800': SystemAction.pauseKeepUsb,
        'noNotificationPause': SystemAction.pauseKeepUsb,
        'stopOnTaskRemoval': SystemAction.pauseKeepUsb,
        'rockerSwitch': SystemAction.pauseKeepUsb,
      });
    });

    test('task removed', () {
      _expectRow(SystemEvent.taskRemoved, <String, SystemAction>{
        'defaults': SystemAction.pauseKeepUsb,
        'releasePermanent': SystemAction.pauseKeepUsb,
        'releaseTransient': SystemAction.pauseKeepUsb,
        'fade800': SystemAction.pauseKeepUsb,
        'noNotificationPause': SystemAction.pauseKeepUsb,
        'stopOnTaskRemoval': SystemAction.stop,
        'rockerSwitch': SystemAction.pauseKeepUsb,
      });
    });

    test('volume rocker double press', () {
      _expectRow(SystemEvent.volumeKeyDoublePress, <String, SystemAction>{
        'defaults': SystemAction.ignore,
        'releasePermanent': SystemAction.ignore,
        'releaseTransient': SystemAction.ignore,
        'fade800': SystemAction.ignore,
        'noNotificationPause': SystemAction.ignore,
        'stopOnTaskRemoval': SystemAction.ignore,
        'rockerSwitch': SystemAction.nextTrack,
      });
    });
  });

  group('exhaustive sweep', () {
    test('every event under every combination is total, pure and stable', () {
      final List<SystemBehaviorSettingsSnapshot> combinations =
          <SystemBehaviorSettingsSnapshot>[];
      for (final UsbReleaseOnFocusLoss usb
          in UsbReleaseOnFocusLoss.values) {
        for (final bool pauseOnNotificationSound in <bool>[true, false]) {
          for (final bool stopWhenTaskRemoved in <bool>[true, false]) {
            for (final bool volumeRockerTrackSwitch in <bool>[true, false]) {
              for (final int fade in <int>[0, 250, 2000]) {
                combinations.add(
                  SystemBehaviorSettingsSnapshot.normalized(
                    usbReleaseOnFocusLoss: usb,
                    pauseOnNotificationSound: pauseOnNotificationSound,
                    stopWhenTaskRemoved: stopWhenTaskRemoved,
                    volumeRockerTrackSwitch: volumeRockerTrackSwitch,
                    fadeOutOnPauseMs: fade,
                  ),
                );
              }
            }
          }
        }
      }
      expect(combinations.length, 72);

      for (final SystemBehaviorSettingsSnapshot settings in combinations) {
        for (final SystemEvent event in SystemEvent.values) {
          final SystemAction action = decide(event, settings);
          expect(
            decide(event, settings),
            action,
            reason: 'decide must be a pure function',
          );
          expect(
            action,
            isNot(SystemAction.seekDelta),
            reason: 'seekDelta has no event yet',
          );
          switch (event) {
            case SystemEvent.audioFocusGain:
              expect(action, SystemAction.ignore);
            case SystemEvent.headsetUnplug:
              expect(action, SystemAction.pauseKeepUsb);
            case SystemEvent.volumeKeyDoublePress:
              expect(
                action,
                settings.volumeRockerTrackSwitch
                    ? SystemAction.nextTrack
                    : SystemAction.ignore,
              );
            case SystemEvent.taskRemoved:
              expect(
                action,
                settings.stopWhenTaskRemoved
                    ? SystemAction.stop
                    : SystemAction.pauseKeepUsb,
              );
            case SystemEvent.notificationSound:
              expect(
                action,
                settings.pauseOnNotificationSound
                    ? (settings.fadeOutOnPauseMs > 0
                        ? SystemAction.fadeOutPause
                        : SystemAction.pauseKeepUsb)
                    : SystemAction.ignore,
              );
            case SystemEvent.audioFocusLossPermanent:
              expect(
                action,
                settings.usbReleaseOnFocusLoss ==
                        UsbReleaseOnFocusLoss.permanent
                    ? SystemAction.pauseAndReleaseUsb
                    : (settings.fadeOutOnPauseMs > 0
                        ? SystemAction.fadeOutPause
                        : SystemAction.pauseKeepUsb),
              );
            case SystemEvent.audioFocusLossTransient:
              expect(
                action,
                settings.usbReleaseOnFocusLoss ==
                        UsbReleaseOnFocusLoss.transient
                    ? SystemAction.pauseAndReleaseUsb
                    : (settings.fadeOutOnPauseMs > 0
                        ? SystemAction.fadeOutPause
                        : SystemAction.pauseKeepUsb),
              );
          }
        }
      }
    });

    test('USB release wins over a configured fade', () {
      const SystemBehaviorSettingsSnapshot settings =
          SystemBehaviorSettingsSnapshot(
        usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.permanent,
        fadeOutOnPauseMs: 2000,
      );
      expect(
        decide(SystemEvent.audioFocusLossPermanent, settings),
        SystemAction.pauseAndReleaseUsb,
      );
      expect(
        decide(SystemEvent.audioFocusLossTransient, settings),
        SystemAction.fadeOutPause,
      );
    });
  });

  group('fade duration', () {
    test('only the fade-out action has a duration', () {
      const SystemBehaviorSettingsSnapshot settings =
          SystemBehaviorSettingsSnapshot(fadeOutOnPauseMs: 640);
      for (final SystemAction action in SystemAction.values) {
        expect(
          fadeDurationFor(action, settings),
          action == SystemAction.fadeOutPause
              ? const Duration(milliseconds: 640)
              : Duration.zero,
          reason: action.name,
        );
      }
    });

    test('a disabled fade is a zero duration', () {
      expect(
        fadeDurationFor(
          SystemAction.fadeOutPause,
          SystemBehaviorSettingsSnapshot.defaults,
        ),
        Duration.zero,
      );
    });

    test('out-of-range persisted fades are clamped by the settings boundary',
        () {
      final SystemBehaviorSettingsSnapshot tooLong =
          SystemBehaviorSettingsSnapshot.normalized(fadeOutOnPauseMs: 9000);
      expect(tooLong.fadeOutOnPauseMs, 2000);
      expect(
        fadeDurationFor(SystemAction.fadeOutPause, tooLong),
        const Duration(milliseconds: 2000),
      );
      final SystemBehaviorSettingsSnapshot negative =
          SystemBehaviorSettingsSnapshot.normalized(fadeOutOnPauseMs: -50);
      expect(negative.fadeOutOnPauseMs, 0);
      expect(fadeDurationFor(SystemAction.fadeOutPause, negative),
          Duration.zero);
    });
  });
}
