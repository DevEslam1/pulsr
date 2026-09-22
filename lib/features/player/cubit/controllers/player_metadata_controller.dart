// lib/features/player/cubit/controllers/player_metadata_controller.dart
// FIX-A1: Focused PlayerMetadataController for lyrics, SponsorBlock, CUE sheets, and quality enrichment
import 'dart:async';
import '../../../../core/utils/cue_parser.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../../domain/repositories/music_repository_interface.dart';
import '../managers/player_lyrics_manager.dart';
import '../managers/player_sponsorblock_manager.dart';
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

  Future<void> loadLyrics(SongsTableData song, {bool isOfflineOnly = false}) async {
    if (_isClosed() || !_isSameTrack(_getState().currentSong, song)) return;

    final cached = _lyricsManager.getCachedLyrics(song);
    if (cached != null) {
      if (_isSameTrack(_getState().currentSong, song)) {
        final s = _getState();
        _emit(s.copyWith(
          lyricsSlice: s.lyricsSlice.copyWith(
            lyrics: cached.lines,
            lyricsSource: cached.source,
            isLoadingLyrics: false,
          ),
        ));
        return;
      }
    }

    final gen = _lyricsManager.bumpGeneration();
    final result = await _lyricsManager.resolveLyrics(
      song,
      isOfflineOnly: isOfflineOnly,
      isStale: () => _isClosed() || gen != _lyricsManager.generation || !_isSameTrack(_getState().currentSong, song),
    );

    if (_isClosed() || gen != _lyricsManager.generation || !_isSameTrack(_getState().currentSong, song)) {
      return;
    }

    final s = _getState();
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        lyrics: result?.lines ?? const [],
        lyricsSource: result?.source ?? LyricsSource.none,
        isLoadingLyrics: false,
      ),
    ));
  }

  Future<void> loadSponsorBlock(SongsTableData song, {bool isOfflineOnly = false}) async {
    await _sponsorBlockManager.loadSegmentsForSong(
      song,
      isOfflineOnly: isOfflineOnly,
      isStale: () => _isClosed() || !_isSameTrack(_getState().currentSong, song),
    );
  }

  Future<void> loadCueChapters(SongsTableData song) async {
    if (song.cueFile == null || song.cueStartMs == null) {
      final state = _getState();
      if (state.cueChapters.isEmpty && state.currentCueIndex == 0) return;
      _emit(state.copyWith(
        queueSlice: state.queueSlice.copyWith(cueChapters: const [], currentCueIndex: 0),
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
    }
  }

  Future<void> enrichTrackParallel(SongsTableData song, {bool isOfflineOnly = false}) async {
    await Future.wait([
      loadLyrics(song, isOfflineOnly: isOfflineOnly),
      loadSponsorBlock(song, isOfflineOnly: isOfflineOnly),
      loadCueChapters(song),
      enrichAudioQuality(song),
    ]);
  }
}
