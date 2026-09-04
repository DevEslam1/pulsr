// lib/data/audio/seamless_queue_transition.dart
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';

/// Manages hot-swapping between gapless (ConcatenatingAudioSource) and
/// crossfade (dual-player) modes without interrupting active playback.
class SeamlessQueueTransition {
  final ConcatenatingAudioSource Function(List<SongsTableData> songs)
      buildConcatSource;
  final Future<void> Function(
          AudioPlayer activePlayer, AudioPlayer inactivePlayer)?
      crossfadeToInactive;

  SeamlessQueueTransition({
    required this.buildConcatSource,
    this.crossfadeToInactive,
  });

  /// Transitions playback engine smoothly from dual-player crossfade to gapless
  /// or vice-versa.
  Future<void> hotSwapEngine({
    required bool toGapless,
    required List<SongsTableData> songs,
    required int currentIndex,
    required Duration currentPosition,
    required AudioPlayer activePlayer,
    required AudioPlayer inactivePlayer,
    required bool isPlaying,
  }) async {
    if (songs.isEmpty) return;

    if (toGapless) {
      final concat = buildConcatSource(songs);
      await inactivePlayer.setAudioSource(
        concat,
        initialIndex: currentIndex.clamp(0, songs.length - 1),
        initialPosition: currentPosition,
        preload: true,
      );

      if (isPlaying && crossfadeToInactive != null) {
        await crossfadeToInactive!(activePlayer, inactivePlayer);
      }
    }
  }
}
