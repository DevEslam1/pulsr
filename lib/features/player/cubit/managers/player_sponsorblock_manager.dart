// lib/features/player/cubit/managers/player_sponsorblock_manager.dart
// FIX-A1: Modular SponsorBlock manager extracted from PlayerCubit
import 'dart:async';
import '../../../../core/services/sponsorblock_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/db/app_database.dart';

/// Manages SponsorBlock segment retrieval, caching, and auto-skip logic.
class PlayerSponsorBlockManager {
  final SponsorBlockService _service;

  PlayerSponsorBlockManager({SponsorBlockService? service})
      : _service = service ?? SponsorBlockService.instance;

  List<SponsorBlockSegment> _currentSegments = const [];
  String? _currentVideoId;
  Duration? _lastSkippedSegmentEnd;
  DateTime? _lastSkipTime;

  List<SponsorBlockSegment> get currentSegments => _currentSegments;
  String? get currentVideoId => _currentVideoId;
  bool get isEnabled => _service.isEnabled;

  Future<void> loadPreferences() async {
    try {
      await _service.loadPreferences();
    } catch (e, st) {
      ErrorLogger.log('Failed to load SponsorBlock preferences',
          error: e, stackTrace: st, category: 'PlayerSponsorBlockManager');
    }
  }

  void reset() {
    _currentSegments = const [];
    _currentVideoId = null;
    _lastSkippedSegmentEnd = null;
  }

  Future<List<SponsorBlockSegment>> loadSegmentsForSong(
    SongsTableData song, {
    required bool isOfflineOnly,
    bool Function()? isStale,
  }) async {
    await loadPreferences();
    if (!_service.isEnabled || isOfflineOnly) {
      reset();
      return const [];
    }

    final videoId = (song.remoteId != null && song.remoteId!.isNotEmpty)
        ? song.remoteId!
        : (song.path.startsWith('ytmusic://')
            ? song.path.replaceFirst('ytmusic://', '').split('?').first
            : null);

    if (videoId == null || videoId.isEmpty) {
      reset();
      return const [];
    }

    if (_currentVideoId == videoId && _currentSegments.isNotEmpty) {
      return _currentSegments;
    }

    reset();

    try {
      final segments = await _service.getSegments(videoId);
      if (isStale != null && isStale()) {
        return const [];
      }
      _currentSegments = segments;
      _currentVideoId = videoId;
      _lastSkippedSegmentEnd = null;
      return segments;
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch SponsorBlock segments for $videoId',
          error: e, stackTrace: st, category: 'PlayerSponsorBlockManager');
      return const [];
    }
  }

  /// Evaluates whether the current position falls within a skippable segment.
  /// If so, returns the target duration to seek to.
  Duration? checkSkipTarget(Duration pos, {required bool isPlaying}) {
    if (_currentSegments.isEmpty || !isPlaying || !_service.isEnabled) {
      return null;
    }

    final now = DateTime.now();
    if (_lastSkipTime != null &&
        now.difference(_lastSkipTime!).inMilliseconds < 1500) {
      return null;
    }

    final seekTarget = _service.findSkipTarget(
      segments: _currentSegments,
      enabledCategories: _service.enabledCategories,
      position: pos,
    );
    if (seekTarget == null) return null;

    final target = seekTarget <= const Duration(milliseconds: 50)
        ? Duration.zero
        : seekTarget - const Duration(milliseconds: 50);

    if (_lastSkippedSegmentEnd != null &&
        (_lastSkippedSegmentEnd == target ||
            (pos - _lastSkippedSegmentEnd!).abs() <
                const Duration(seconds: 2))) {
      return null;
    }

    _lastSkippedSegmentEnd = target;
    _lastSkipTime = now;
    return seekTarget;
  }
}
