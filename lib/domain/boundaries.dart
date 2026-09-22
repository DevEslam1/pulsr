// lib/domain/boundaries.dart
// FIX-A3: Bounded Context Map documenting cross-feature boundaries and typed communication

import 'package:flutter/foundation.dart';
import '../data/db/app_database.dart';
import 'models/audio_output_info.dart';

/// Bounded Context Map:
/// Defines typed interfaces and contracts between distinct feature modules in Pulsr,
/// preventing ad-hoc, untyped or direct coupling between cubits.
///
/// 1. Player -> Settings (reads outputDevice, replayGain, bitPerfect)
/// 2. Player -> Library (toggleFavorite)
/// 3. Downloads -> Player (swapReconciledSong)
/// 4. Settings -> Player (crossfade duration push, DSP bypass)

/// Boundary contract: Player reading hardware output & DSP preferences from Settings.
abstract class IPlayerSettingsBoundary {
  /// Currently selected audio output device, or null for system default.
  AudioOutputInfo? get outputDevice;

  /// Whether bit-perfect output mode is active.
  bool get bitPerfectEnabled;

  /// Whether DSP should be bypassed when bit-perfect mode is active.
  bool get bypassDspOnBitPerfect;

  /// Preamp gain in dB to apply for ReplayGain.
  double get replayGainPreamp;
}

/// Boundary contract: Player triggering library favorite status changes.
abstract class IPlayerLibraryBoundary {
  /// Toggles the favorite status of [song] in the user's library.
  Future<void> toggleFavorite(SongsTableData song);
}

/// Boundary contract: Downloads notifying player of completed offline reconciliation.
abstract class IDownloadPlayerBoundary {
  /// Swaps an in-memory stream track with its local downloaded counterpart [localSong].
  void swapReconciledSong(int oldSongId, SongsTableData localSong);
}

/// Boundary contract: Settings pushing audio transport & DSP settings to Player.
abstract class ISettingsPlayerBoundary {
  /// Updates the crossfade duration for track transitions.
  void setCrossfadeDuration(Duration duration);

  /// Notifies the audio engine of an output device change.
  void notifyOutputDeviceChanged(AudioOutputInfo? device);
}

/// Typed event representing an audio device change across feature contexts.
@immutable
class AudioDeviceChangedEvent {
  /// The newly connected or configured audio output device.
  final AudioOutputInfo? device;

  /// Monotonic or wall-clock creation timestamp.
  final DateTime timestamp;

  AudioDeviceChangedEvent(this.device) : timestamp = DateTime.now();
}

/// Typed event representing completed download reconciliation.
@immutable
class SongReconciledEvent {
  /// Identifier of the remote track prior to download.
  final int originalId;

  /// Reconciled local song record in the database.
  final SongsTableData localSong;

  const SongReconciledEvent({required this.originalId, required this.localSong});
}
