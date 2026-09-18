// lib/data/audio/collaborators/playback_preload_orchestrator.dart

import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/audio/smart_preload_scheduler.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';

/// Orchestrates proactive background stream resolution and lookahead cache warming.
class PlaybackPreloadOrchestrator {
  final SmartPreloadScheduler scheduler;
  final StreamPreResolver preResolver;

  PlaybackPreloadOrchestrator({
    required this.scheduler,
    required this.preResolver,
  });

  void onTrackStarted({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    Duration? position,
    Duration? duration,
  }) {
    preResolver.onTrackStarted(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      position: position,
      duration: duration,
    );
  }

  void onQueueMutated({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    Duration? position,
    Duration? duration,
  }) {
    scheduler.clear();
    preResolver.onQueueMutated(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      position: position,
      duration: duration,
    );
  }

  void onTrackEnqueuedOrTapped(SongsTableData song) {
    preResolver.onTrackEnqueuedOrTapped(song);
  }

  void evaluatePreloadThreshold({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    required Duration position,
    required Duration duration,
    List<int>? shuffleIndices,
  }) {
    scheduler.schedulePreloads(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      position: position,
      duration: duration,
    );
  }

  void clear() {
    scheduler.clear();
    preResolver.cancel();
  }

  void dispose() {
    scheduler.clear();
    preResolver.dispose();
  }
}
