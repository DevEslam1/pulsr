// lib/data/audio/seamless_queue_transition.dart
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';

/// Manages hot-swapping between gapless (AudioPlayer playlist) and
/// crossfade (dual-player) modes without interrupting active playback.
class SeamlessQueueTransition {
  final List<AudioSource> Function(List<SongsTableData> songs)
      buildAudioSources;
  final Future<void> Function(
          AudioPlayer activePlayer, AudioPlayer inactivePlayer)?
      crossfadeToInactive;
  final Future<AudioSource> Function(SongsTableData song)?
      buildSingleSource;

  SeamlessQueueTransition({
    required this.buildAudioSources,
    this.crossfadeToInactive,
    this.buildSingleSource,
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
    final safeIndex = currentIndex.clamp(0, songs.length - 1);

    if (toGapless) {
      final sources = buildAudioSources(songs);
      await inactivePlayer.setAudioSources(
        sources,
        initialIndex: safeIndex,
        initialPosition: currentPosition,
        preload: true,
      );

      if (isPlaying && crossfadeToInactive != null) {
        await crossfadeToInactive!(activePlayer, inactivePlayer);
      }
      return;
    }

    // toGapless == false: dual-player engine = single source per track.
    // Mirror of the gapless path: stage the current track on the inactive
    // player, then fade the old engine out so the caller can swap.
    final single = buildSingleSource != null
        ? await buildSingleSource!(songs[safeIndex])
        : buildAudioSources([songs[safeIndex]]).first;
    await inactivePlayer.setAudioSource(
      single,
      initialPosition: currentPosition,
      preload: true,
    );
    if (isPlaying) {
      await inactivePlayer.play();
      if (crossfadeToInactive != null) {
        await crossfadeToInactive!(activePlayer, inactivePlayer);
      }
      try {
        await activePlayer.stop();
      } catch (_) {}
    }
  }
}
