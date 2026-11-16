// lib/features/system_behavior/system_behavior_policy.dart
//
// Pure decision layer for the system-behaviour pack: no I/O, no timers, no
// platform calls. Every answer here is a function of (event, settings), so the
// whole table is unit-testable without a device or a widget tree.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import 'system_behavior_settings.dart';

/// A platform event the system-behaviour service has to react to.
enum SystemEvent {
  /// Audio focus was lost for good: a phone call, another player taking over,
  /// or an `unknown` interruption.
  audioFocusLossPermanent,

  /// Audio focus was lost for a moment: a navigation prompt or the assistant.
  audioFocusLossTransient,

  /// The previous focus holder gave focus back.
  audioFocusGain,

  /// A short system notification sound is playing.
  notificationSound,

  /// The output device was unplugged (`becoming noisy`).
  headsetUnplug,

  /// The app was removed from the recents list.
  taskRemoved,

  /// A hardware volume rocker was pressed twice in quick succession.
  volumeKeyDoublePress,
}

/// The delivery action chosen for a [SystemEvent].
enum SystemAction {
  /// Nothing to do; the event is not handled by this feature.
  ignore,

  /// Pause playback and keep the exclusive USB claim.
  pauseKeepUsb,

  /// Release the exclusive USB claim, then pause playback.
  pauseAndReleaseUsb,

  /// Stop playback and tear the session down.
  stop,

  /// Skip to the next queue item.
  nextTrack,

  /// Relative seek over the media-button path. Declared so the delivery layer
  /// shares one action vocabulary with the long-press seek gesture;
  /// [decide] never returns it today.
  seekDelta,

  /// Ramp the software volume down to zero, then pause.
  fadeOutPause,
}

/// Decides what a [SystemEvent] should do under [settings].
///
/// | Event                    | Condition                     | Action            |
/// |--------------------------|-------------------------------|-------------------|
/// | audioFocusLossPermanent  | usbRelease == permanent       | pauseAndReleaseUsb|
/// |                          | else fadeOutOnPauseMs > 0     | fadeOutPause      |
/// |                          | else                          | pauseKeepUsb      |
/// | audioFocusLossTransient  | usbRelease == transient       | pauseAndReleaseUsb|
/// |                          | else fadeOutOnPauseMs > 0     | fadeOutPause      |
/// |                          | else                          | pauseKeepUsb      |
/// | audioFocusGain           | any                           | ignore            |
/// | notificationSound        | !pauseOnNotificationSound     | ignore            |
/// |                          | else fadeOutOnPauseMs > 0     | fadeOutPause      |
/// |                          | else                          | pauseKeepUsb      |
/// | headsetUnplug            | any                           | pauseKeepUsb      |
/// | taskRemoved              | stopWhenTaskRemoved           | stop              |
/// |                          | else                          | pauseKeepUsb      |
/// | volumeKeyDoublePress     | volumeRockerTrackSwitch       | nextTrack         |
/// |                          | else                          | ignore            |
///
/// Precedence worth knowing: releasing the USB claim wins over a fade (the
/// sink is changing, so fading the old sink is pointless), and a fade wins over
/// a plain pause. [SystemEvent.headsetUnplug] never fades and never releases
/// the claim because the device is already gone; the pause stays resumable so
/// replugging the headset can restore playback.
///
/// Focus-loss / focus-gain bookkeeping itself lives in
/// `PlaybackInterruptionManager`; this table only decides how the pause is
/// delivered once that manager says playback should pause.
SystemAction decide(SystemEvent event, SystemBehaviorSettingsSnapshot settings) {
  switch (event) {
    case SystemEvent.audioFocusLossPermanent:
      return _pauseActionFor(
        settings,
        releaseUsb: settings.usbReleaseOnFocusLoss ==
            UsbReleaseOnFocusLoss.permanent,
      );
    case SystemEvent.audioFocusLossTransient:
      return _pauseActionFor(
        settings,
        releaseUsb: settings.usbReleaseOnFocusLoss ==
            UsbReleaseOnFocusLoss.transient,
      );
    case SystemEvent.audioFocusGain:
      // Resume is owned by the interruption manager and the audio handler; a
      // gain event only restores the pre-fade volume in the delivery layer.
      return SystemAction.ignore;
    case SystemEvent.notificationSound:
      if (!settings.pauseOnNotificationSound) return SystemAction.ignore;
      return settings.fadeOutOnPauseMs > 0
          ? SystemAction.fadeOutPause
          : SystemAction.pauseKeepUsb;
    case SystemEvent.headsetUnplug:
      return SystemAction.pauseKeepUsb;
    case SystemEvent.taskRemoved:
      return settings.stopWhenTaskRemoved
          ? SystemAction.stop
          : SystemAction.pauseKeepUsb;
    case SystemEvent.volumeKeyDoublePress:
      return settings.volumeRockerTrackSwitch
          ? SystemAction.nextTrack
          : SystemAction.ignore;
  }
}

SystemAction _pauseActionFor(
  SystemBehaviorSettingsSnapshot settings, {
  required bool releaseUsb,
}) {
  if (releaseUsb) return SystemAction.pauseAndReleaseUsb;
  if (settings.fadeOutOnPauseMs > 0) return SystemAction.fadeOutPause;
  return SystemAction.pauseKeepUsb;
}

/// Length of the fade [action] runs for; [Duration.zero] for every action that
/// is not a fade.
Duration fadeDurationFor(
  SystemAction action,
  SystemBehaviorSettingsSnapshot settings,
) {
  if (action != SystemAction.fadeOutPause) return Duration.zero;
  return settings.fadeOutDuration;
}

/// Perceived level (0..1) of a linear gain, for the logarithmic taper.
double perceptualLevel(double gain) {
  if (!gain.isFinite || gain <= 0) return 0;
  return math.sqrt(gain.clamp(0.0, 1.0));
}

/// Linear gain (0..1) for a perceived level, for the logarithmic taper.
double gainForPerceptualLevel(double level) {
  if (!level.isFinite || level <= 0) return 0;
  final double bounded = level.clamp(0.0, 1.0);
  return bounded * bounded;
}

/// Volume after one step in [direction] (-1 down, +1 up, 0 unchanged).
///
/// [SoftwareVolumeCurve.linear] moves the linear gain by `volumeStepPercent`
/// of the full scale. [SoftwareVolumeCurve.logarithmic] moves the perceived
/// level by the same amount and converts back to gain, so one step feels the
/// same size at the bottom and the top of the range. Both curves clamp into
/// 0..1 and land exactly on 0 and 1 at the rails.
double nextVolume({
  required double current,
  required int direction,
  required SystemBehaviorSettingsSnapshot settings,
}) {
  final double base = current.isFinite ? current.clamp(0.0, 1.0) : 0.0;
  final int sign = direction == 0 ? 0 : (direction > 0 ? 1 : -1);
  if (sign == 0) return base;
  final double step = settings.volumeStepPercent / 100.0;
  switch (settings.softwareVolumeCurve) {
    case SoftwareVolumeCurve.linear:
      return (base + sign * step).clamp(0.0, 1.0);
    case SoftwareVolumeCurve.logarithmic:
      final double bumped =
          (perceptualLevel(base) + sign * step).clamp(0.0, 1.0);
      return bumped == 0 ? 0.0 : gainForPerceptualLevel(bumped);
  }
}

/// A monotonic volume ramp from [startVolume] down to exactly 0.
///
/// The ramp is a value object so the arithmetic can be tested without timers:
/// [stepInterval] is the period the service's timer uses, and the final step
/// ([volumeAtStep] with `index == steps`) is exactly 0. [elapsedAtStep] never
/// exceeds [total] because the interval is truncated, so "the ramp reaches 0
/// within the requested fade length" holds for any duration.
@immutable
class FadeRamp {
  /// Creates a ramp. [steps] must be positive; the default 16 gives a
  /// 62 ms tick on a 1 s fade, smooth enough for a software gain ramp.
  const FadeRamp({
    required this.startVolume,
    required this.total,
    this.steps = defaultSteps,
  }) : assert(steps > 0, 'A fade needs at least one step');

  /// Steps used by the service unless a caller asks otherwise.
  static const int defaultSteps = 16;

  /// Volume the ramp starts from, on the 0..1 linear gain scale.
  final double startVolume;

  /// Requested fade length.
  final Duration total;

  /// Number of ticks the ramp is split into.
  final int steps;

  /// Time between two ticks; truncating keeps `stepInterval * steps <= total`.
  Duration get stepInterval =>
      Duration(microseconds: total.inMicroseconds ~/ steps);

  /// Whether the ramp can actually move: a zero-length or silent ramp is
  /// treated as "pause now".
  bool get isAudible => total > Duration.zero && _safeStart > 0;

  /// Volume after [index] ticks; 0 once the ramp is complete.
  double volumeAtStep(int index) {
    if (index <= 0) return _safeStart;
    if (index >= steps) return 0;
    final double remaining = 1 - index / steps;
    return (_safeStart * remaining).clamp(0.0, 1.0);
  }

  /// Time the whole ramp takes; never longer than [total].
  Duration get elapsedAtStep => stepInterval * steps;

  double get _safeStart =>
      startVolume.isFinite ? startVolume.clamp(0.0, 1.0) : 0.0;
}
