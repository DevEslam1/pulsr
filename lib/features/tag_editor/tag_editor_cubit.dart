import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/bloc/base_cubit.dart';
import '../../core/constants/channels.dart';
import '../../core/services/metadata_search_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'tag_editor_state.dart';

class TagEditorCubit extends PulsrCubit<TagEditorState> {
  static const MethodChannel _channel = MethodChannel(PulsrChannels.tagEditor);
  final MediaScannerService _scannerService;
  final MetadataSearchService _metadataSearchService;
  final ImagePicker _imagePicker = ImagePicker();

  // Dirty flags for batch mode — tracks which fields were explicitly edited
  // so that an empty value means "clear" rather than "leave unchanged".
  bool _batchArtistEdited = false;
  bool _batchAlbumEdited = false;
  bool _batchGenreEdited = false;
  bool _batchYearEdited = false;
  bool _batchTrackEdited = false;
  bool _batchDiscEdited = false;
  bool _batchCommentEdited = false;

  // Fields the user already edited; an in-flight [loadTags] must not
  // overwrite them.
  final Set<String> _userEditedFields = <String>{};

  /// Undo stack: snapshots before each user edit. Cleared on save.
  final List<TagEditorState> _history = <TagEditorState>[];
  static const int _historyMax = 30;

  bool get canUndo => _history.isNotEmpty;

  void _pushHistory() {
    if (isClosed) return;
    _history.add(state);
    if (_history.length > _historyMax) {
      _history.removeRange(0, _history.length - _historyMax);
    }
  }

  /// Restores the state before the last user edit. Returns false when empty.
  bool undo() {
    if (isClosed || _history.isEmpty) return false;
    final prev = _history.removeLast();
    emit(prev);
    return true;
  }

  TagEditorCubit({
    required SongsTableData song,
    List<SongsTableData>? batchSongs,
    required MediaScannerService scannerService,
    MetadataSearchService? metadataSearchService,
  })  : _scannerService = scannerService,
        _metadataSearchService =
            metadataSearchService ?? MetadataSearchService(),
        super(_createInitialState(song, batchSongs)) {
    if (!state.isBatchMode) {
      loadTags();
    } else {
      emit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  static TagEditorState _createInitialState(
      SongsTableData song, List<SongsTableData>? batchSongs) {
    final isBatch = batchSongs != null && batchSongs.length > 1;
    final allSameArtist =
        isBatch && batchSongs.every((s) => s.artist == song.artist);
    final allSameAlbum =
        isBatch && batchSongs.every((s) => s.album == song.album);
    final allSameGenre =
        isBatch && batchSongs.every((s) => s.genre == song.genre);
    final allSameYear = isBatch && batchSongs.every((s) => s.year == song.year);

    return TagEditorState(
      song: song,
      batchSongs: batchSongs ?? const [],
      title: isBatch ? '' : song.title,
      artist: isBatch ? (allSameArtist ? song.artist : '') : song.artist,
      album: isBatch ? (allSameAlbum ? song.album : '') : song.album,
      genre: isBatch
          ? (allSameGenre ? (song.genre ?? '') : '')
          : (song.genre ?? ''),
      year: isBatch
          ? (allSameYear ? (song.year?.toString() ?? '') : '')
          : (song.year != null ? song.year.toString() : ''),
      trackNumber: isBatch
          ? ''
          : (song.trackNumber != null ? song.trackNumber.toString() : ''),
      discNumber: isBatch
          ? ''
          : (song.discNumber != null ? song.discNumber.toString() : ''),
    );
  }

  Future<void> loadTags() async {
    if (isClosed) return;
    emit(state.copyWith(status: TagEditorStatus.loading));
    try {
      final Map<dynamic, dynamic>? tags =
          await _channel.invokeMapMethod<dynamic, dynamic>(
        'readTags',
        {'path': state.song.path},
      );
      if (isClosed) return;

      if (tags != null) {
        final title = (tags['title'] as String?)?.trim();
        final artist = (tags['artist'] as String?)?.trim();
        final album = (tags['album'] as String?)?.trim();
        final genre = (tags['genre'] as String?)?.trim();
        final year = (tags['year'] as String?)?.trim();
        final trackNumber = (tags['trackNumber'] as String?)?.trim();
        final discNumber = (tags['discNumber'] as String?)?.trim();
        final comment = (tags['comment'] as String?)?.trim();
        final lyrics = (tags['lyrics'] as String?)?.trim();
        final artworkData = (tags['artworkBytes'] as Uint8List?) ??
            (tags['artwork'] as Uint8List?);
        bool edited(String field) => _userEditedFields.contains(field);

        emit(state.copyWith(
          status: TagEditorStatus.loaded,
          title: (edited('title') || title == null || title.isEmpty)
              ? state.title
              : title,
          artist: (edited('artist') || artist == null || artist.isEmpty)
              ? state.artist
              : artist,
          album: (edited('album') || album == null || album.isEmpty)
              ? state.album
              : album,
          genre: edited('genre') ? state.genre : (genre ?? state.genre),
          year: edited('year') ? state.year : (year ?? state.year),
          trackNumber: edited('trackNumber')
              ? state.trackNumber
              : (trackNumber ?? state.trackNumber),
          discNumber: edited('discNumber')
              ? state.discNumber
              : (discNumber ?? state.discNumber),
          comment: edited('comment') ? state.comment : (comment ?? ''),
          lyrics: edited('lyrics') ? state.lyrics : (lyrics ?? ''),
          artworkBytes: edited('artwork') ? state.artworkBytes : artworkData,
        ));
      } else {
        emit(state.copyWith(status: TagEditorStatus.loaded));
      }
    } catch (e, st) {
      if (isClosed) return;
      ErrorLogger.log(
          'Failed to read native tags via MethodChannel for ${state.song.path}',
          error: e,
          stackTrace: st,
          category: 'TagEditorCubit');
      emit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  void updateTitle(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('title');
    emit(state.copyWith(title: val));
  }

  void updateArtist(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('artist');
    if (state.isBatchMode) _batchArtistEdited = true;
    emit(state.copyWith(artist: val));
  }

  void updateAlbum(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('album');
    if (state.isBatchMode) _batchAlbumEdited = true;
    emit(state.copyWith(album: val));
  }

  void updateGenre(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('genre');
    if (state.isBatchMode) _batchGenreEdited = true;
    emit(state.copyWith(genre: val));
  }

  void updateYear(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('year');
    if (state.isBatchMode) _batchYearEdited = true;
    emit(state.copyWith(year: val));
  }

  void updateTrackNumber(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('trackNumber');
    if (state.isBatchMode) _batchTrackEdited = true;
    emit(state.copyWith(trackNumber: val));
  }

  void updateDiscNumber(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('discNumber');
    if (state.isBatchMode) _batchDiscEdited = true;
    emit(state.copyWith(discNumber: val));
  }

  void updateComment(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('comment');
    if (state.isBatchMode) _batchCommentEdited = true;
    emit(state.copyWith(comment: val));
  }

  void updateLyrics(String val) {
    if (isClosed) return;
    _pushHistory();
    _userEditedFields.add('lyrics');
    emit(state.copyWith(lyrics: val));
  }

  Future<void> pickArtwork() async {
    if (isClosed) return;
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (isClosed) return;
      if (image != null) {
        // Reject very large images before they can cause OOM downstream.
        try {
          final sizeBytes = await image.length();
          if (sizeBytes > 15 * 1024 * 1024) {
            if (!isClosed) {
              emit(state.copyWith(
                  errorMessage:
                      'Image is too large (${(sizeBytes / 1048576).toStringAsFixed(1)} MB). Max 15 MB.'));
            }
            return;
          }
        } catch (_) {}
        _userEditedFields.add('artwork');
        emit(state.copyWith(
          newArtworkPath: image.path,
          removeArtwork: false,
        ));
      }
    } on PlatformException catch (e) {
      if (isClosed) return;
      final msg = e.code == 'photo_access_denied' || e.code == 'camera_access_denied'
          ? 'Permission denied to access gallery'
          : 'Failed to pick artwork image: ${e.message ?? e.code}';
      emit(state.copyWith(errorMessage: msg));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: 'Failed to pick artwork image: $e'));
    }
  }

  void removeArtworkImage() {
    if (isClosed) return;
    _userEditedFields.add('artwork');
    emit(state.copyWith(
      removeArtwork: true,
      clearNewArtworkPath: true,
      clearArtworkBytes: true,
    ));
  }

  /// Searches online metadata without immediately auto-applying.
  Future<List<OnlineTrackMetadata>> searchOnlineMatches() async {
    final searchTitle = state.title.isNotEmpty ? state.title : state.song.title;
    final searchArtist =
        state.artist.isNotEmpty ? state.artist : state.song.artist;
    return await _metadataSearchService.searchMetadata(
      title: searchTitle,
      artist: searchArtist,
      album: state.album,
    );
  }

  /// Applies the selected metadata result to the form state.
  Future<bool> applyMetadataResult(OnlineTrackMetadata match) async {
    if (isClosed) return false;
    emit(state.copyWith(isAutoFetching: true, clearErrorMessage: true));
    try {
      String? downloadedArtPath;
      if (match.artworkUrl != null) {
        downloadedArtPath = await _metadataSearchService
            .downloadArtworkToTemp(match.artworkUrl!);
      }
      if (isClosed) return false;

      emit(state.copyWith(
        isAutoFetching: false,
        title: match.title.isNotEmpty ? match.title : state.title,
        artist: match.artist.isNotEmpty ? match.artist : state.artist,
        album: match.album.isNotEmpty ? match.album : state.album,
        genre: (match.genre != null && match.genre!.isNotEmpty)
            ? match.genre
            : state.genre,
        year: (match.releaseYear != null && match.releaseYear!.isNotEmpty)
            ? match.releaseYear
            : state.year,
        trackNumber:
            (match.trackNumber != null && match.trackNumber!.isNotEmpty)
                ? match.trackNumber
                : state.trackNumber,
        newArtworkPath: downloadedArtPath ?? state.newArtworkPath,
        removeArtwork: false,
      ));
      return true;
    } catch (e, st) {
      if (isClosed) return false;
      ErrorLogger.log('Applying metadata result failed',
          error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(
        isAutoFetching: false,
        errorMessage: 'Failed to apply metadata: $e',
      ));
      return false;
    }
  }

  /// Automatically searches online (iTunes & MusicBrainz) and updates tags + cover art in 1 tap.
  Future<bool> autoFetchOnlineTags() async {
    if (isClosed) return false;
    emit(state.copyWith(isAutoFetching: true, clearErrorMessage: true));
    try {
      final results = await searchOnlineMatches();
      if (isClosed) return false;
      if (results.isEmpty) {
        emit(state.copyWith(
          isAutoFetching: false,
          errorMessage: 'No matching online metadata found for this track.',
        ));
        return false;
      }
      return await applyMetadataResult(results.first);
    } catch (e, st) {
      if (isClosed) return false;
      ErrorLogger.log('Auto-fetch online tags failed',
          error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(
        isAutoFetching: false,
        errorMessage: 'Failed to auto-fetch online tags: $e',
      ));
      return false;
    }
  }

  /// Batch auto-fetch: queries online metadata per track (capped at 20 to
  /// respect iTunes/MusicBrainz rate limits) and fills the shared form fields
  /// only where every resolved track agrees (artist/album/genre/year).
  /// A 300ms inter-request delay prevents HTTP 429 rate-limiting (BUG-11).
  /// Returns the number of tracks resolved.
  Future<int> autoFetchBatchTags({int maxTracks = 20}) async {
    if (isClosed || !state.isBatchMode) return 0;
    emit(state.copyWith(isAutoFetching: true, clearErrorMessage: true));
    try {
      final targets = state.batchSongs.take(maxTracks).toList();
      final artists = <String>[];
      final albums = <String>[];
      final genres = <String>[];
      final years = <String>[];
      var resolved = 0;
      for (int i = 0; i < targets.length; i++) {
        if (isClosed) return resolved;
        // Rate-limit: 300ms between requests to respect iTunes / MusicBrainz
        // limits (~5 req/s). Without this a 20-song batch fires 20 requests as
        // fast as the network allows and triggers HTTP 429 after ~5 (BUG-11).
        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (isClosed) return resolved;
        }
        try {
          final song = targets[i];
          final matches = await _metadataSearchService.searchMetadata(
            title: song.title,
            artist: song.artist,
            album: song.album,
          );
          if (matches.isEmpty) continue;
          resolved++;
          final m = matches.first;
          if (m.artist.isNotEmpty) artists.add(m.artist);
          if (m.album.isNotEmpty) albums.add(m.album);
          if (m.genre != null && m.genre!.isNotEmpty) genres.add(m.genre!);
          if (m.releaseYear != null && m.releaseYear!.isNotEmpty) {
            years.add(m.releaseYear!);
          }
        } catch (_) {}
      }
      if (isClosed) return resolved;
      String? unanimous(List<String> values) {
        if (values.isEmpty || values.length < resolved || resolved == 0) {
          return null;
        }
        final first = values.first.toLowerCase();
        if (values.every((v) => v.toLowerCase() == first)) return values.first;
        return null;
      }

      final artist = unanimous(artists);
      final album = unanimous(albums);
      final genre = unanimous(genres);
      final year = unanimous(years);
      if (artist != null) _batchArtistEdited = true;
      if (album != null) _batchAlbumEdited = true;
      if (genre != null) _batchGenreEdited = true;
      if (year != null) _batchYearEdited = true;
      emit(state.copyWith(
        isAutoFetching: false,
        artist: artist ?? state.artist,
        album: album ?? state.album,
        genre: genre ?? state.genre,
        year: year ?? state.year,
        errorMessage: resolved == 0
            ? 'No matching online metadata found for these tracks.'
            : null,
      ));
      return resolved;
    } catch (e, st) {
      if (isClosed) return 0;
      ErrorLogger.log('Batch auto-fetch online tags failed',
          error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(
        isAutoFetching: false,
        errorMessage: 'Failed to auto-fetch online tags: $e',
      ));
      return 0;
    }
  }

  Future<void> saveTags() async {
    if (isClosed) return;
    if (!state.isBatchMode && state.title.trim().isEmpty) {
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage: 'Song title cannot be empty.',
      ));
      return;
    }
    // Validate year/track-number before hitting the native channel so
    // non-numeric input surfaces a form error instead of a native crash.
    final yearTrimmed = state.year.trim();
    if (yearTrimmed.isNotEmpty) {
      final yearNum = int.tryParse(yearTrimmed);
      if (yearNum == null || yearNum < 1000 || yearNum > 2100) {
        emit(state.copyWith(
          status: TagEditorStatus.failure,
          errorMessage: 'Year must be a number between 1000 and 2100.',
        ));
        return;
      }
    }
    final trackTrimmed = state.trackNumber.trim();
    if (trackTrimmed.isNotEmpty) {
      final trackNum = int.tryParse(trackTrimmed.split('/').first.trim());
      if (trackNum == null || trackNum < 0 || trackNum > 9999) {
        emit(state.copyWith(
          status: TagEditorStatus.failure,
          errorMessage: 'Track number must be a non-negative number.',
        ));
        return;
      }
    }

    emit(state.copyWith(
        status: TagEditorStatus.saving,
        clearErrorMessage: true,
        batchProgress: 0.0));
    try {
      if (state.isBatchMode) {
        final total = state.batchSongs.length;
        final List<String> failedFiles = [];
        final List<SongsTableData> taggedSongs = [];
        var lastEmitTime = DateTime.now();
        for (int i = 0; i < total; i++) {
          if (isClosed) return;
          final s = state.batchSongs[i];
          final now = DateTime.now();
          if (i == 0 ||
              i == total - 1 ||
              (i % 3 == 0) ||
              now.difference(lastEmitTime).inMilliseconds >= 200) {
            lastEmitTime = now;
            emit(state.copyWith(
              status: TagEditorStatus.saving,
              batchProgress: total > 0 ? (i + 1) / total : 1.0,
            ));
          }
          try {
            final payload = <String, dynamic>{
              'path': s.path,
              'title': s.title, // keep individual title
              'artist': _batchArtistEdited
                  ? state.artist
                  : (state.artist.isNotEmpty ? state.artist : s.artist),
              'album': _batchAlbumEdited
                  ? state.album
                  : (state.album.isNotEmpty ? state.album : s.album),
              'genre': _batchGenreEdited
                  ? state.genre
                  : (state.genre.isNotEmpty ? state.genre : (s.genre ?? '')),
              'year': _batchYearEdited
                  ? state.year
                  : (state.year.isNotEmpty
                      ? state.year
                      : (s.year?.toString() ?? '')),
              'trackNumber': _batchTrackEdited
                  ? state.trackNumber
                  : (s.trackNumber?.toString() ?? ''),
              'discNumber': _batchDiscEdited ? state.discNumber : '',
              'artworkPath': state.newArtworkPath,
              'removeArtwork': state.removeArtwork,
            };
            if (_batchCommentEdited) {
              payload['comment'] = state.comment;
            }
            // Do NOT include 'lyrics' in batch mode to preserve each track's embedded lyrics
            final batchResult =
                await _channel.invokeMethod<dynamic>('writeTags', payload);
            if (!_isWriteVerified(batchResult)) {
              throw const _UnverifiedTagWriteException();
            }
            if (isClosed) return;
            await _scannerService.rescanSingleFile(s.path);
            taggedSongs.add(s);
          } catch (e, st) {
            ErrorLogger.log('Failed to save tags for ${s.path}',
                error: e, stackTrace: st, category: 'TagEditor');
            failedFiles.add(s.title);
          }
          if (isClosed) return;
        }
        // Invalidate only the lyrics caches for the tagged files; a full
        // clearCache() also wiped every other song's cached lyrics + disk
        // cache just for editing one album.
        for (final tagged in taggedSongs) {
          LrcParser.invalidateSong(songId: tagged.id, path: tagged.path);
        }
        if (isClosed) return;
        if (failedFiles.isNotEmpty) {
          emit(state.copyWith(
            status: failedFiles.length == total
                ? TagEditorStatus.failure
                : TagEditorStatus.success,
            errorMessage:
                'Failed to tag ${failedFiles.length} file${failedFiles.length > 1 ? "s" : ""}: ${failedFiles.take(3).join(", ")}${failedFiles.length > 3 ? "…" : ""}',
            clearBatchProgress: true,
          ));
        } else {
          _batchArtistEdited = false;
          _batchAlbumEdited = false;
          _batchGenreEdited = false;
          _batchYearEdited = false;
          _batchTrackEdited = false;
          _batchDiscEdited = false;
          _batchCommentEdited = false;
          _history.clear();
          emit(state.copyWith(
              status: TagEditorStatus.success, clearBatchProgress: true));
        }
        return;
      }

      String lyrics = state.lyrics;
      bool lyricsTruncated = false;
      if (lyrics.length > 8192) {
        lyrics = lyrics.substring(0, 8192);
        lyricsTruncated = true;
      }

      final writeResult = await _channel.invokeMethod<dynamic>('writeTags', {
        'path': state.song.path,
        'title': state.title,
        'artist': state.artist,
        'album': state.album,
        'genre': state.genre,
        'year': state.year,
        'trackNumber': state.trackNumber,
        'discNumber': state.discNumber,
        'comment': state.comment,
        'lyrics': lyrics,
        'artworkPath': state.newArtworkPath,
        'removeArtwork': state.removeArtwork,
      });
      if (!_isWriteVerified(writeResult)) {
        if (isClosed) return;
        emit(state.copyWith(
          status: TagEditorStatus.failure,
          errorMessage:
              'Tags were sent but could not be verified on this device (storage permission or format limitation). Original file was restored when possible.',
        ));
        return;
      }
      if (isClosed) return;

      // Update Drift DB and clear cached parsed lyrics for THIS track only.
      LrcParser.invalidateSong(
        songId: state.song.id,
        path: state.song.path,
      );
      await _scannerService.rescanSingleFile(state.song.path);
      if (isClosed) return;

      if (lyricsTruncated && !isClosed) {
        _history.clear();
        emit(state.copyWith(
          status: TagEditorStatus.success,
          errorMessage:
              'Note: lyrics truncated to 8192 chars (device tag limit).',
        ));
      } else {
        _history.clear();
        emit(state.copyWith(status: TagEditorStatus.success));
      }
    } on _UnverifiedTagWriteException {
      if (isClosed) return;
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage:
            'Tag write could not be verified — file left unchanged when possible. Check storage permission (Android 11+ scoped storage) and WAV limitations.',
      ));
    } on PlatformException catch (e) {
      if (isClosed) return;
      final isScopedStorage = e.code == 'WRITE_TAGS_ERROR' &&
          (e.message ?? '').toLowerCase().contains('permission');
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage: isScopedStorage
            ? 'Storage permission denied (Android 11+ scoped storage). Grant All-files access and retry — no changes were applied.'
            : (e.message ?? 'Failed to save tags on this device.'),
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage: 'Failed to save tags: $e',
      ));
    }
  }
}

/// Checks whether the native tag-write result indicates a confirmed success.
///
/// The native bridge has gone through three generations:
///   1. Bare `bool true` — legacy; no verification proof, but still a success.
///   2. `{ok: true}` map  — transitional; means the write was accepted.
///   3. `{verified: true}` map — current; explicit re-read verification.
///
/// Returning `false` for generations 1 & 2 caused the UI to always show
/// "could not be verified" even when the tag was written correctly (BUG-1).
bool _isWriteVerified(dynamic result) {
  if (result is bool) {
    // Generation 1: bare bool. Accept as success; log so we know the native
    // side hasn't been updated yet.
    assert(() {
      ErrorLogger.log(
        '[TagEditor] Legacy bare-bool result from writeTags — update native bridge to return {verified: true}.',
        category: 'tag_editor',
      );
      return true;
    }());
    return result;
  }
  if (result is Map) {
    // Generation 3 (current): explicit verified flag.
    final verified = result['verified'];
    if (verified is bool) return verified;
    // Generation 2 (transitional): {ok: true} without re-read proof.
    // Treat as success — failing here caused BUG-1 (always shows error).
    if (result['ok'] == true) return true;
  }
  return false;
}

class _UnverifiedTagWriteException implements Exception {
  const _UnverifiedTagWriteException();
}
