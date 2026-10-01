// lib/features/player/cubit/controllers/player_metadata_controller.dart
// FIX-A1: Focused PlayerMetadataController for lyrics, SponsorBlock, CUE sheets, and quality enrichment
import 'dart:async';
import '../../../../core/services/sponsorblock_service.dart';
import '../../../../core/utils/cue_parser.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../../domain/repositories/music_repository_interface.dart';
import '../managers/player_lyrics_manager.dart';
import '../managers/player_sponsorblock_manager.dart';
import '../player_constants.dart';
import '../player_state.dart';

/// Manages track metadata, lyrics resolution, SponsorBlock skipping, and CUE chapters.
class PlayerMetadataController {
  final PlayerLyricsManager _lyricsManager;
  final PlayerSponsorBlockManager _sponsorBlockManager;
  final IMusicRepository _repository;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;
  final bool Function(SongsTableData? a, SongsTableData? b) _isSameTrack;

  PlayerMetadataController({
    required PlayerLyricsManager lyricsManager,
    required PlayerSponsorBlockManager sponsorBlockManager,
    required IMusicRepository repository,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    required bool Function(SongsTableData? a, SongsTableData? b) isSameTrack,
  })  : _lyricsManager = lyricsManager,
        _sponsorBlockManager = sponsorBlockManager,
        _repository = repository,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _isSameTrack = isSameTrack;

  Future<void> loadLyrics(SongsTableData song,
      {bool isOfflineOnly = false}) async {
    final gen = _lyricsManager.bumpGeneration();
    if (_isClosed() || !_isSameTrack(_getState().currentSong, song)) return;

    final cached = _lyricsManager.getCachedLyrics(song);
    if (cached != null) {
      if (_isClosed() ||
          gen != _lyricsManager.generation ||
          !_isSameTrack(_getState().currentSong, song)) {
        return;
      }
      final s = _getState();
      if (_isClosed() ||
          gen != _lyricsManager.generation ||
          !_isSameTrack(s.currentSong, song)) {
        return;
      }
      _emit(s.copyWith(
        lyricsSlice: s.lyricsSlice.copyWith(
          lyrics: cached.lines,
          lyricsSource: cached.source,
          isLoadingLyrics: false,
        ),
      ));
      return;
    }

    if (_lyricsManager.hasFreshNegativeCache(song)) {
      if (_isClosed() ||
          gen != _lyricsManager.generation ||
          !_isSameTrack(_getState().currentSong, song)) {
        return;
      }
      final s = _getState();
      if (_isClosed() ||
          gen != _lyricsManager.generation ||
          !_isSameTrack(s.currentSong, song)) {
        return;
      }
      _emit(s.copyWith(
        lyricsSlice: s.lyricsSlice.copyWith(
          lyrics: const [],
          lyricsSource: LyricsSource.none,
          isLoadingLyrics: false,
        ),
      ));
      return;
    }

    final result = await _lyricsManager
        .resolveLyrics(
          song,
          isOfflineOnly: isOfflineOnly,
          isStale: () =>
              _isClosed() ||
              gen != _lyricsManager.generation ||
              !_isSameTrack(_getState().currentSong, song),
        )
        .timeout(PlayerConstants.lyricsTimeout, onTimeout: () => null);

    if (_isClosed() ||
        gen != _lyricsManager.generation ||
        !_isSameTrack(_getState().currentSong, song)) {
      return;
    }

    final s = _getState();
    if (_isClosed() ||
        gen != _lyricsManager.generation ||
        !_isSameTrack(s.currentSong, song)) {
      return;
    }
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        lyrics: result?.lines ?? const [],
        lyricsSource: result?.source ?? LyricsSource.none,
        isLoadingLyrics: false,
      ),
    ));
  }

  Future<void> loadSponsorBlock(SongsTableData song,
      {bool isOfflineOnly = false}) async {
    try {
      await _sponsorBlockManager
          .loadSegmentsForSong(
            song,
            isOfflineOnly: isOfflineOnly,
            isStale: () =>
                _isClosed() || !_isSameTrack(_getState().currentSong, song),
          )
          .timeout(const Duration(seconds: 10),
              onTimeout: () => const <SponsorBlockSegment>[]);
    } catch (e, st) {
      ErrorLogger.log('Failed to load SponsorBlock for ${song.id}',
          error: e, stackTrace: st, category: 'PlayerMetadataController');
      rethrow;
    }
  }

  /// Evaluates the current position against the loaded SponsorBlock segments
  /// and returns the seek target when the position falls inside a skippable
  /// segment, or null when nothing should be skipped.
  Duration? evaluateSponsorBlockSkip(Duration pos, {required bool isPlaying}) =>
      _sponsorBlockManager.checkSkipTarget(pos, isPlaying: isPlaying);

  Future<void> loadCueChapters(SongsTableData song) async {
    if (song.cueFile == null || song.cueStartMs == null) {
      final state = _getState();
      if (state.cueChapters.isEmpty && state.currentCueIndex == 0) return;
      _emit(state.copyWith(
        queueSlice: state.queueSlice
            .copyWith(cueChapters: const [], currentCueIndex: 0),
      ));
      return;
    }
    try {
      final chapters = await CueParser.findAndParseCue(song.path);
      if (_isClosed() || !_isSameTrack(_getState().currentSong, song)) return;
      final index = chapters.indexWhere((c) => c.index == song.trackNumber);
      final s = _getState();
      _emit(s.copyWith(
        queueSlice: s.queueSlice.copyWith(
          cueChapters: chapters,
          currentCueIndex: index < 0 ? 0 : index,
        ),
      ));
    } catch (e, st) {
      ErrorLogger.log('Failed to load cue chapters for ${song.path}',
          error: e, stackTrace: st, category: 'PlayerMetadataController');
      rethrow;
    }
  }

  Future<void> enrichAudioQuality(SongsTableData song) async {
    try {
      final refreshed = await _repository.getSongById(song.id);
      final updated = refreshed.fold((_) => null, (s) => s);
      if (updated != null &&
          !_isClosed() &&
          _isSameTrack(_getState().currentSong, updated)) {
        final state = _getState();
        final updatedQueue = state.queue
            .map((s) => _isSameTrack(s, updated) ? updated : s)
            .toList();
        _emit(state.copyWith(
          playback: state.playback.copyWith(currentSong: updated),
          queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
        ));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to enrich audio quality for ${song.id}',
          error: e, stackTrace: st, category: 'PlayerMetadataController');
      rethrow;
    }
  }

  Future<void> enrichTrackParallel(SongsTableData song,
      {bool isOfflineOnly = false}) async {
    final failures = <String>[];
    await Future.wait([
      loadLyrics(song, isOfflineOnly: isOfflineOnly)
          .catchError((Object e, StackTrace st) {
        failures.add('lyrics');
        ErrorLogger.log('Parallel lyrics failed',
            error: e, stackTrace: st, category: 'PlayerMetadataController');
      }),
      loadSponsorBlock(song, isOfflineOnly: isOfflineOnly)
          .catchError((Object e, StackTrace st) {
        failures.add('sponsorBlock');
        ErrorLogger.log('Parallel sponsorBlock failed',
            error: e, stackTrace: st, category: 'PlayerMetadataController');
      }),
      loadCueChapters(song).catchError((Object e, StackTrace st) {
        failures.add('cue');
        ErrorLogger.log('Parallel cue chapters failed',
            error: e, stackTrace: st, category: 'PlayerMetadataController');
      }),
      enrichAudioQuality(song).catchError((Object e, StackTrace st) {
        failures.add('quality');
        ErrorLogger.log('Parallel audio quality enrichment failed',
            error: e, stackTrace: st, category: 'PlayerMetadataController');
      }),
    ], eagerError: false);

    if (failures.isNotEmpty && !_isClosed()) {
      final state = _getState();
      if (_isSameTrack(state.currentSong, song)) {
        _emit(state.copyWith(
          playback: state.playback.copyWith(
            errorMessage: 'Track enrichment failed (${failures.join(', ')})',
          ),
        ));
      }
    }
  }

  void dispose() {}
}
