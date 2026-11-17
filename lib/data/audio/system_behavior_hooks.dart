// lib/data/audio/system_behavior_hooks.dart
//
// Delivery bridge between the audio handler's interruption path and the
// system-behaviour pack.
//
// The handler owns the audio_session streams, the interruption state machine
// and the queue. The SystemBehaviorService owns *how* a pause is delivered
// (fade ramp, USB release, plain pause), which setting decides it and how the
// volume comes back. This object is the seam between them: the handler calls a
// hook, and the hook answers `true` when the service already carried the event
// out, so the handler stands down instead of pausing or resuming a second time.
//
// Split from `PulsrAudioHandler` so tests can attach a recording bridge without
// constructing the system-behaviour settings/screen stack, and so the handler
// keeps no dependency on the feature layer.
import 'package:flutter/foundation.dart' show immutable;

/// One callback per platform event the handler forwards.
@immutable
class SystemBehaviorHooks {
  /// Creates the bridge. Every callback must be failure-tolerant.
  const SystemBehaviorHooks({
    required this.onAudioFocusLoss,
    required this.onAudioFocusGain,
    required this.onNotificationSound,
    required this.onNotificationSoundEnd,
    required this.onHeadsetUnplug,
  });

  /// Focus was lost. [permanent] distinguishes a call / another player
  /// (`true`) from a navigation prompt or the assistant (`false`).
  ///
  /// Returns true when the service started the pause delivery (immediately or
  /// through a fade ramp); false means the handler should pause itself.
  final Future<bool> Function({required bool permanent}) onAudioFocusLoss;

  /// Focus came back. Returns true when the service already resumed playback.
  final Future<bool> Function() onAudioFocusGain;

  /// A notification sound / navigation prompt started (duck begin).
  /// Returns true when the service delivered the pause instead of a duck.
  final Future<bool> Function() onNotificationSound;

  /// The notification sound ended (duck end). Returns true when the service
  /// already resumed playback.
  final Future<bool> Function() onNotificationSoundEnd;

  /// The output device was unplugged (`becoming noisy`). Returns true when the
  /// service delivered the pause.
  final Future<bool> Function() onHeadsetUnplug;
}
