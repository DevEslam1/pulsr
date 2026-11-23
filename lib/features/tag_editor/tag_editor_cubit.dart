import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/bloc/base_cubit.dart';
import '../../core/constants/channels.dart';
import '../../core/services/metadata_search_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'tag_editor_state.dart';

import '../../core/errors/app_error.dart';

class TagEditorCubit extends PulsrCubit<TagEditorState> {
  static const String batchCheckpointKey = 'batch_tag_checkpoint';
  static const String batchCheckpointPayloadKey = 'batch_tag_checkpoint_payload';
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
  final List<String> _downloadedTempArtworkPaths = <String>[];

  static const Set<String> _smallLyricsLimitExts = {'.wav', '.aiff', '.aif'};
  static const Set<String> _unsupportedTagExts = {
    '.cue',
    '.m3u',
    '.m3u8',
    '.pls',
    '.wpl',
    '.mid',
    '.midi',
  };

  /// Returns a human-readable reason why [song] cannot be tag-edited, or
  /// `null` when the file is eligible for tag editing.
  static String? unsupportedTrackReason(SongsTableData song) {
    if (song.cueStartMs != null ||
        (song.cueFile != null && song.cueFile!.isNotEmpty)) {
      return 'Tag editing is not supported for CUE sheet virtual tracks.';
    }
    final lowerPath = song.path.trim().toLowerCase();
    if (lowerPath.isEmpty ||
        lowerPath.startsWith('ytmusic://') ||
        lowerPath.startsWith('http://') ||
        lowerPath.startsWith('https://') ||
        (song.source == SongSource.youtube && !song.isDownloaded)) {
      return 'Cannot edit tags on online streaming tracks. Download the track first.';
    }
    for (final ext in _unsupportedTagExts) {
      if (lowerPath.endsWith(ext)) {
        return 'Tag editing is not supported for this file format.';
      }
    }
    return null;
  }

  static bool _usesSmallLyricsLimit(String path) {
    final lower = path.trim().toLowerCase();
    return _smallLyricsLimitExts.any(lower.endsWith);
  }

  /// Undo stack: diff snapshots before each user edit. Cleared on save.
  // FIX-H12: Use ListQueue for O(1) eviction instead of O(n) removeRange
  final ListQueue<_TagEditorDiff> _history = ListQueue<_TagEditorDiff>();
  // FIX-L08 / B-21: Store diff instead of full state (avoids duplicate batchSongs refs)
  static const int _historyMax = 15;

  /// Consecutive edits to the same field inside this window coalesce into one
  /// undo step, so undo rewinds a typing burst instead of one character.
  static const Duration _historyCoalesceWindow = Duration(milliseconds: 500);
  String? _lastHistoryField;
  DateTime? _lastHistoryPushAt;

  bool get canUndo => _history.isNotEmpty;

  /// True when the user has edits that have not been written to disk.
  bool get hasUnsavedChanges =>
      _history.isNotEmpty ||
      _userEditedFields.isNotEmpty ||
      state.newArtworkPath != null ||
      state.removeArtwork;

  void _pushHistory(String field) {
    if (isClosed) return;
    final now = DateTime.now();
    final lastAt = _lastHistoryPushAt;
    if (field == _lastHistoryField &&
        lastAt != null &&
        now.difference(lastAt) < _historyCoalesceWindow) {
      return;
    }
    _lastHistoryField = field;
    _lastHistoryPushAt = now;
    _history.addLast(_TagEditorDiff.fromCubit(this));
    while (_history.length > _historyMax) {
      _history.removeFirst();
    }
  }

  void _resetHistoryCoalescing() {
    _lastHistoryField = null;
    _lastHistoryPushAt = null;
  }

  void _clearHistory() {
    _history.clear();
    _resetHistoryCoalescing();
  }

  /// Restores the state before the last user edit. Returns false when empty.
  bool undo() {
    if (isClosed || _history.isEmpty) return false;
    final prevDiff = _history.removeLast();
    _resetHistoryCoalescing();
    _userEditedFields
      ..clear()
      ..addAll(prevDiff.userEditedFields);
    _batchArtistEdited = prevDiff.batchArtistEdited;
    _batchAlbumEdited = prevDiff.batchAlbumEdited;
    _batchGenreEdited = prevDiff.batchGenreEdited;
    _batchYearEdited = prevDiff.batchYearEdited;
    _batchTrackEdited = prevDiff.batchTrackEdited;
    _batchDiscEdited = prevDiff.batchDiscEdited;
    _batchCommentEdited = prevDiff.batchCommentEdited;
    safeEmit(prevDiff.applyTo(state));
    return true;
  }

  Map<String, dynamic> _buildBatchCheckpointPayload(List<String> pendingPaths) {
    return <String, dynamic>{
      'paths': pendingPaths,
      'artist': state.artist,
      'album': state.album,
      'genre': state.genre,
      'year': state.year,
      'trackNumber': state.trackNumber,
      'discNumber': state.discNumber,
      'comment': state.comment,
      'newArtworkPath': state.newArtworkPath,
      'removeArtwork': state.removeArtwork,
      'batchArtistEdited': _batchArtistEdited,
      'batchAlbumEdited': _batchAlbumEdited,
      'batchGenreEdited': _batchGenreEdited,
      'batchYearEdited': _batchYearEdited,
      'batchTrackEdited': _batchTrackEdited,
      'batchDiscEdited': _batchDiscEdited,
      'batchCommentEdited': _batchCommentEdited,
      'userEditedFields': _userEditedFields.toList(),
    };
  }

  Future<void> _writeBatchCheckpoint(
    SharedPreferences prefs,
    List<String> pendingPaths,
  ) async {
    await prefs.setStringList(batchCheckpointKey, pendingPaths);
    await prefs.setString(
      batchCheckpointPayloadKey,
      jsonEncode(_buildBatchCheckpointPayload(pendingPaths)),
    );
  }

  static Future<void> clearBatchCheckpoint(SharedPreferences prefs) async {
    await prefs.remove(batchCheckpointKey);
    await prefs.remove(batchCheckpointPayloadKey);
  }

  /// Restores batch edit state from [prefs] before retrying an interrupted
  /// batch save.
  Future<void> restoreBatchCheckpoint(SharedPreferences prefs) async {
    if (isClosed) return;
    final rawJson = prefs.getString(batchCheckpointPayloadKey);
    if (rawJson == null || rawJson.isEmpty) return;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      _batchArtistEdited = map['batchArtistEdited'] == true;
      _batchAlbumEdited = map['batchAlbumEdited'] == true;
      _batchGenreEdited = map['batchGenreEdited'] == true;
      _batchYearEdited = map['batchYearEdited'] == true;
      _batchTrackEdited = map['batchTrackEdited'] == true;
      _batchDiscEdited = map['batchDiscEdited'] == true;
      _batchCommentEdited = map['batchCommentEdited'] == true;

      final restoredFields = (map['userEditedFields'] as List?)
              ?.whereType<String>()
              .toSet() ??
          <String>{};
      if (_batchArtistEdited) restoredFields.add('artist');
      if (_batchAlbumEdited) restoredFields.add('album');
      if (_batchGenreEdited) restoredFields.add('genre');
      if (_batchYearEdited) restoredFields.add('year');
      if (_batchTrackEdited) restoredFields.add('trackNumber');
      if (_batchDiscEdited) restoredFields.add('discNumber');
      if (_batchCommentEdited) restoredFields.add('comment');
      final artPath = map['newArtworkPath'] as String?;
      final remArt = map['removeArtwork'] == true;
      if (artPath != null || remArt) restoredFields.add('artwork');
      _userEditedFields
        ..clear()
        ..addAll(restoredFields);

      safeEmit(state.copyWith(
        artist: _batchArtistEdited
            ? (map['artist'] as String? ?? '')
            : state.artist,
        album:
            _batchAlbumEdited ? (map['album'] as String? ?? '') : state.album,
        genre:
            _batchGenreEdited ? (map['genre'] as String? ?? '') : state.genre,
        year: _batchYearEdited ? (map['year'] as String? ?? '') : state.year,
        trackNumber: _batchTrackEdited
            ? (map['trackNumber'] as String? ?? '')
            : state.trackNumber,
        discNumber: _batchDiscEdited
            ? (map['discNumber'] as String? ?? '')
            : state.discNumber,
        comment: _batchCommentEdited
            ? (map['comment'] as String? ?? '')
            : state.comment,
        newArtworkPath: artPath ?? state.newArtworkPath,
        removeArtwork: remArt ? true : state.removeArtwork,
      ));
    } catch (e, st) {
      ErrorLogger.log('Failed to restore batch tag checkpoint',
          error: e, stackTrace: st, category: 'TagEditor');
    }
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
      safeEmit(state.copyWith(status: TagEditorStatus.loaded));
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
    final unsupported = unsupportedTrackReason(state.song);
    if (unsupported != null) {
      safeEmit(state.copyWith(
        status: TagEditorStatus.loaded,
        error: uiError(unsupported),
      ));
      return;
    }
    safeEmit(state.copyWith(status: TagEditorStatus.loading));
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

        safeEmit(state.copyWith(
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
        safeEmit(state.copyWith(status: TagEditorStatus.loaded));
      }
    } on MissingPluginException {
      if (isClosed) return;
      safeEmit(state.copyWith(status: TagEditorStatus.loaded));
    } catch (e, st) {
      if (isClosed) return;
      ErrorLogger.log(
          'Failed to read native tags via MethodChannel for ${state.song.path}',
          error: e,
          stackTrace: st,
          category: 'TagEditorCubit');
      safeEmit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  TagEditorStatus? get _clearedFailureStatus =>
      state.status == TagEditorStatus.failure ? TagEditorStatus.loaded : null;

  void setAutoFetching(bool value) {
    if (isClosed || state.isAutoFetching == value) return;
    safeEmit(state.copyWith(
      isAutoFetching: value,
      clearError: value,
    ));
  }

  void updateTitle(String val) {
    if (isClosed) return;
    _pushHistory('title');
    _userEditedFields.add('title');
    safeEmit(state.copyWith(
      title: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateArtist(String val) {
    if (isClosed) return;
    _pushHistory('artist');
    _userEditedFields.add('artist');
    if (state.isBatchMode) _batchArtistEdited = true;
    safeEmit(state.copyWith(
      artist: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateAlbum(String val) {
    if (isClosed) return;
    _pushHistory('album');
    _userEditedFields.add('album');
    if (state.isBatchMode) _batchAlbumEdited = true;
    safeEmit(state.copyWith(
      album: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateGenre(String val) {
    if (isClosed) return;
    _pushHistory('genre');
    _userEditedFields.add('genre');
    if (state.isBatchMode) _batchGenreEdited = true;
    safeEmit(state.copyWith(
      genre: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateYear(String val) {
    if (isClosed) return;
    _pushHistory('year');
    _userEditedFields.add('year');
    if (state.isBatchMode) _batchYearEdited = true;
    safeEmit(state.copyWith(
      year: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateTrackNumber(String val) {
    if (isClosed) return;
    _pushHistory('trackNumber');
    _userEditedFields.add('trackNumber');
    if (state.isBatchMode) _batchTrackEdited = true;
    safeEmit(state.copyWith(
      trackNumber: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateDiscNumber(String val) {
    if (isClosed) return;
    _pushHistory('discNumber');
    _userEditedFields.add('discNumber');
    if (state.isBatchMode) _batchDiscEdited = true;
    safeEmit(state.copyWith(
      discNumber: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateComment(String val) {
    if (isClosed) return;
    _pushHistory('comment');
    _userEditedFields.add('comment');
    if (state.isBatchMode) _batchCommentEdited = true;
    safeEmit(state.copyWith(
      comment: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
  }

  void updateLyrics(String val) {
    if (isClosed) return;
    _pushHistory('lyrics');
    _userEditedFields.add('lyrics');
    safeEmit(state.copyWith(
      lyrics: val,
      status: _clearedFailureStatus,
      clearError: true,
    ));
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
              safeEmit(state.copyWith(
                  error: uiError(
                      'Image is too large (${(sizeBytes / 1048576).toStringAsFixed(1)} MB). Max 15 MB.')));
            }
            return;
          }
        } catch (_) {}
        _pushHistory('artwork');
        _userEditedFields.add('artwork');
        safeEmit(state.copyWith(
          newArtworkPath: image.path,
          removeArtwork: false,
          status: _clearedFailureStatus,
          clearError: true,
        ));
      }
    } on PlatformException catch (e) {
      if (isClosed) return;
      final msg =
          e.code == 'photo_access_denied' || e.code == 'camera_access_denied'
              ? 'Permission denied to access gallery'
              : 'Failed to pick artwork image: ${e.message ?? e.code}';
      safeEmit(state.copyWith(error: uiError(msg)));
    } catch (e) {
      if (isClosed) return;
      safeEmit(
          state.copyWith(error: uiError('Failed to pick artwork image: $e')));
    }
  }

  void removeArtworkImage() {
    if (isClosed) return;
    _pushHistory('artwork');
    _userEditedFields.add('artwork');
    safeEmit(state.copyWith(
      removeArtwork: true,
      clearNewArtworkPath: true,
      clearArtworkBytes: true,
      status: _clearedFailureStatus,
      clearError: true,
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
  Future<bool> applyMetadataResult(OnlineTrackMetadata match) {
    return _applyMetadataResultInternal(match);
  }

  Future<bool> _applyMetadataResultInternal(OnlineTrackMetadata match) async {
    if (isClosed) return false;
    safeEmit(state.copyWith(isAutoFetching: true, clearError: true));
    try {
      String? downloadedArtPath;
      if (match.artworkUrl != null) {
        downloadedArtPath = await _metadataSearchService
            .downloadArtworkToTemp(match.artworkUrl!);
        if (downloadedArtPath != null) {
          _downloadedTempArtworkPaths.add(downloadedArtPath);
        }
      }
      if (isClosed) return false;

      _pushHistory('metadata');

      // Applied metadata is a deliberate user edit: a slow loadTags that lands
      // afterwards must not overwrite it with the file's stale tags.
      if (match.title.isNotEmpty) _userEditedFields.add('title');
      if (match.artist.isNotEmpty) _userEditedFields.add('artist');
      if (match.album.isNotEmpty) _userEditedFields.add('album');
      if (match.genre != null && match.genre!.isNotEmpty) {
        _userEditedFields.add('genre');
      }
      if (match.releaseYear != null && match.releaseYear!.isNotEmpty) {
        _userEditedFields.add('year');
      }
      if (match.trackNumber != null && match.trackNumber!.isNotEmpty) {
        _userEditedFields.add('trackNumber');
      }
      if (downloadedArtPath != null) _userEditedFields.add('artwork');

      safeEmit(state.copyWith(
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
        status: _clearedFailureStatus,
        clearError: true,
      ));
      return true;
    } catch (e, st) {
      if (isClosed) return false;
      ErrorLogger.log('Applying metadata result failed',
          error: e, stackTrace: st, category: 'TagEditorCubit');
      safeEmit(state.copyWith(
        isAutoFetching: false,
        error: uiError('Failed to apply metadata: $e'),
      ));
      return false;
    }
  }

  /// Automatically searches online (iTunes & MusicBrainz) and updates tags + cover art in 1 tap.
  Future<bool> autoFetchOnlineTags() async {
    if (isClosed || state.isAutoFetching) return false;
    safeEmit(state.copyWith(isAutoFetching: true, clearError: true));
    try {
      final results = await searchOnlineMatches();
      if (isClosed) return false;
      if (results.isEmpty) {
        safeEmit(state.copyWith(
          isAutoFetching: false,
          error: uiError('No matching online metadata found for this track.'),
        ));
        return false;
      }
      return await _applyMetadataResultInternal(results.first);
    } catch (e, st) {
      if (isClosed) return false;
      ErrorLogger.log('Auto-fetch online tags failed',
          error: e, stackTrace: st, category: 'TagEditorCubit');
      safeEmit(state.copyWith(
        isAutoFetching: false,
        error: uiError('Failed to auto-fetch online tags: $e'),
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
    if (isClosed || !state.isBatchMode || state.isAutoFetching) return 0;
    safeEmit(state.copyWith(isAutoFetching: true, clearError: true));
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
      if (artist != null || album != null || genre != null || year != null) {
        _pushHistory('metadata');
      }
      if (artist != null) _batchArtistEdited = true;
      if (album != null) _batchAlbumEdited = true;
      if (genre != null) _batchGenreEdited = true;
      if (year != null) _batchYearEdited = true;
      safeEmit(state.copyWith(
        isAutoFetching: false,
        artist: artist ?? state.artist,
        album: album ?? state.album,
        genre: genre ?? state.genre,
        year: year ?? state.year,
        clearError: resolved > 0,
        error: resolved == 0
            ? uiError('No matching online metadata found for these tracks.')
            : null,
      ));
      return resolved;
    } catch (e, st) {
      if (isClosed) return 0;
      ErrorLogger.log('Batch auto-fetch online tags failed',
          error: e, stackTrace: st, category: 'TagEditorCubit');
      safeEmit(state.copyWith(
        isAutoFetching: false,
        error: uiError('Failed to auto-fetch online tags: $e'),
      ));
      return 0;
    }
  }

  Future<void> saveTags() async {
    if (isClosed) return;
    // A failed save leaves status at failure; the user must be able to fix the
    // offending field and retry, so only in-flight/uninitialised states block
    // entry. (Previously every retry after any failure was a silent no-op.)
    if (state.status == TagEditorStatus.saving ||
        state.status == TagEditorStatus.loading ||
        state.status == TagEditorStatus.initial) {
      return;
    }
    if (!state.isBatchMode && state.title.trim().isEmpty) {
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError('Song title cannot be empty.'),
      ));
      return;
    }
    // Validate year/track-number before hitting the native channel so
    // non-numeric input surfaces a form error instead of a native crash.
    final yearTrimmed = state.year.trim();
    if (yearTrimmed.isNotEmpty) {
      final yearNum = int.tryParse(yearTrimmed);
      if (yearNum == null || yearNum < 1000 || yearNum > 2100) {
        safeEmit(state.copyWith(
          status: TagEditorStatus.failure,
          error: uiError('Year must be a number between 1000 and 2100.'),
        ));
        return;
      }
    }
    final trackTrimmed = state.trackNumber.trim();
    if (trackTrimmed.isNotEmpty) {
      final trackNum = int.tryParse(trackTrimmed.split('/').first.trim());
      if (trackNum == null || trackNum < 0 || trackNum > 9999) {
        safeEmit(state.copyWith(
          status: TagEditorStatus.failure,
          error: uiError('Track number must be a non-negative number.'),
        ));
        return;
      }
    }
    final discTrimmed = state.discNumber.trim();
    if (discTrimmed.isNotEmpty) {
      final parts = discTrimmed.split('/');
      final discNum = int.tryParse(parts.first.trim());
      final totalValid = parts.length == 1 ||
          (parts.length == 2 &&
              (int.tryParse(parts[1].trim()) ?? 0) >= (discNum ?? 1));
      if (discNum == null || discNum <= 0 || discNum > 999 || !totalValid) {
        safeEmit(state.copyWith(
          status: TagEditorStatus.failure,
          error: uiError('Disc number must be a positive number.'),
        ));
        return;
      }
    }

    safeEmit(state.copyWith(
        status: TagEditorStatus.saving,
        clearError: true,
        batchProgress: 0.0,
        batchFailedCount: 0));
    try {
      if (state.isBatchMode) {
        final total = state.batchSongs.length;
        final List<String> failedFiles = [];
        final List<SongsTableData> taggedSongs = [];
        bool hadRescanError = false;
        SharedPreferences? prefs;
        List<String> pendingPaths = [];
        try {
          prefs = await SharedPreferences.getInstance();
          pendingPaths = state.batchSongs.map((s) => s.path).toList();
          await _writeBatchCheckpoint(prefs, pendingPaths);
        } catch (_) {}

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
            safeEmit(state.copyWith(
              status: TagEditorStatus.saving,
              batchProgress: total > 0 ? (i + 1) / total : 1.0,
            ));
          }
          if (unsupportedTrackReason(s) != null) {
            failedFiles.add(s.title);
            continue;
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
              'discNumber': _batchDiscEdited
                  ? state.discNumber
                  : (s.discNumber?.toString() ?? ''),
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
            // FIX-C8: 100ms delay to let native file buffers flush
            await Future.delayed(const Duration(milliseconds: 100));
            if (isClosed) return;
            try {
              await _scannerService.rescanSingleFile(s.path);
              await CachedArtwork.invalidate(id: s.id);
            } catch (e, st) {
              hadRescanError = true;
              ErrorLogger.log('Tag write succeeded but rescan failed for ${s.path}',
                  error: e, stackTrace: st, category: 'TagEditor');
            }
            taggedSongs.add(s);
            pendingPaths.remove(s.path);
            // C-04: Persist the shrinking checkpoint periodically rather than
            // for every single file — a 200-track batch previously issued a
            // platform-channel disk write per file. The final remove below
            // always clears it.
            if (prefs != null && taggedSongs.length % 10 == 0) {
              try {
                await _writeBatchCheckpoint(prefs, pendingPaths);
              } catch (e, st) {
                ErrorLogger.log('Failed to update batch checkpoint',
                    error: e, stackTrace: st, category: 'TagEditor');
              }
            }
          } catch (e, st) {
            ErrorLogger.log('Failed to save tags for ${s.path}',
                error: e, stackTrace: st, category: 'TagEditor');
            failedFiles.add(s.title);
          }
          if (isClosed) return;
        }
        if (prefs != null) {
          try {
            if (failedFiles.isEmpty) {
              await clearBatchCheckpoint(prefs);
            } else {
              // Keep the paths that still need tagging so the next editor open
              // can offer to retry the remainder instead of just informing.
              await _writeBatchCheckpoint(prefs, pendingPaths);
            }
          } catch (_) {}
        }
        // Invalidate only the lyrics caches for the tagged files; a full
        // clearCache() also wiped every other song's cached lyrics + disk
        // cache just for editing one album.
        for (final tagged in taggedSongs) {
          LrcParser.invalidateSong(songId: tagged.id, path: tagged.path);
        }
        if (isClosed) return;
        if (failedFiles.isNotEmpty) {
          safeEmit(state.copyWith(
            status: failedFiles.length == total
                ? TagEditorStatus.failure
                : TagEditorStatus.success,
            error: uiError(
                'Failed to tag ${failedFiles.length} file${failedFiles.length > 1 ? "s" : ""}: ${failedFiles.take(3).join(", ")}${failedFiles.length > 3 ? "…" : ""}'),
            batchFailedCount: failedFiles.length,
            clearBatchProgress: true,
          ));
        } else {
          _clearHistory();
          _userEditedFields.clear();
          _batchArtistEdited = false;
          _batchAlbumEdited = false;
          _batchGenreEdited = false;
          _batchYearEdited = false;
          _batchTrackEdited = false;
          _batchDiscEdited = false;
          _batchCommentEdited = false;
          // FIX-C08: Inform user that lyrics are not editable in batch mode
          final notes = <String>[
            if (state.lyrics.isNotEmpty)
              'Note: lyrics are not editable in batch mode — use single-track editor for lyrics.',
            if (hadRescanError)
              'Tags were written to the files, but refreshing the library index failed for one or more tracks.',
          ];
          safeEmit(state.copyWith(
            status: TagEditorStatus.success,
            error: notes.isEmpty ? null : uiError(notes.join(' ')),
            batchFailedCount: 0,
            clearBatchProgress: true,
          ));
        }
        return;
      }

      final singleUnsupported = unsupportedTrackReason(state.song);
      if (singleUnsupported != null) {
        safeEmit(state.copyWith(
          status: TagEditorStatus.failure,
          error: uiError(singleUnsupported),
        ));
        return;
      }

      String lyrics = state.lyrics;
      bool lyricsTruncated = false;
      if (_usesSmallLyricsLimit(state.song.path) && lyrics.length > 8192) {
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
      // FIX-M08 / B-17: Distinguish between write rejected ({ok: false}), write failed (bool false), and verification failed
      final isVerified = _isWriteVerified(writeResult);
      if (!isVerified) {
        if (isClosed) return;
        final writeOutcome = _checkTagWriteOutcome(writeResult);
        final errorText = switch (writeOutcome) {
          _TagWriteOutcome.unavailable =>
            'Tag editor unavailable on this device (native bridge did not respond).',
          _TagWriteOutcome.rejected =>
            'Tag write was rejected by the native bridge or audio subsystem.',
          _TagWriteOutcome.failed =>
            'Tag write failed. The audio file could not be updated.',
          _TagWriteOutcome.unverified =>
            'Tags were sent but could not be verified on this device (storage permission or format limitation). Original file was restored when possible.',
          _ => 'Failed to save tags.',
        };
        safeEmit(state.copyWith(
          status: TagEditorStatus.failure,
          error: uiError(errorText),
        ));
        return;
      }
      if (isClosed) return;

      // Update Drift DB and clear cached parsed lyrics for THIS track only.
      LrcParser.invalidateSong(
        songId: state.song.id,
        path: state.song.path,
      );
      // FIX-C8: 100ms delay to let native file buffers flush
      await Future.delayed(const Duration(milliseconds: 100));
      if (isClosed) return;
      bool rescanWarning = false;
      try {
        await _scannerService.rescanSingleFile(state.song.path);
        if (isClosed) return;
        await CachedArtwork.invalidate(id: state.song.id);
      } catch (e, st) {
        rescanWarning = true;
        ErrorLogger.log('Tag write succeeded but rescan failed for ${state.song.path}',
            error: e, stackTrace: st, category: 'TagEditor');
      }

      _userEditedFields.clear();
      final notes = <String>[
        if (lyricsTruncated)
          'Note: lyrics truncated to 8192 chars (container tag limit).',
        if (rescanWarning)
          'Tags were saved to the file, but refreshing the library index failed.',
      ];
      _clearHistory();
      safeEmit(state.copyWith(
        status: TagEditorStatus.success,
        error: notes.isEmpty ? null : uiError(notes.join(' ')),
        batchFailedCount: 0,
      ));
    } on MissingPluginException {
      if (isClosed) return;
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError(
            'Tag editing is not supported on this platform (no native tag writer available).'),
      ));
    } on _TagWriteRejectedException {
      if (isClosed) return;
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError(
            'Tag write was rejected by the system. Check file permissions.'),
      ));
    } on _TagWriteFailedException {
      if (isClosed) return;
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError('Tag write failed. Could not write to the audio file.'),
      ));
    } on _UnverifiedTagWriteException {
      if (isClosed) return;
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError(
            'Tag write could not be verified — file left unchanged when possible. Check storage permission (Android 11+ scoped storage) and WAV limitations.'),
      ));
    } on PlatformException catch (e) {
      if (isClosed) return;
      final isScopedStorage = e.code == 'WRITE_TAGS_ERROR' &&
          (e.message ?? '').toLowerCase().contains('permission');
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError(isScopedStorage
            ? 'Storage permission denied (Android 11+ scoped storage). Grant All-files access and retry — no changes were applied.'
            : (e.message ?? 'Failed to save tags on this device.')),
      ));
    } catch (e) {
      if (isClosed) return;
      safeEmit(state.copyWith(
        status: TagEditorStatus.failure,
        error: uiError('Failed to save tags: $e'),
      ));
    }
  }

  @override
  Future<void> close() {
    for (final path in _downloadedTempArtworkPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _downloadedTempArtworkPaths.clear();
    _clearHistory();
    _userEditedFields.clear();
    return super.close();
  }
}

// FIX-M08 / H-10: Distinct outcomes for native bridge responses
enum _TagWriteOutcome {
  verified,
  accepted,
  rejected,
  failed,
  unverified,
  unavailable
}

_TagWriteOutcome _checkTagWriteOutcome(dynamic result) {
  // H-10: A null response means the platform channel never answered (bridge
  // disconnected). Surface that distinctly instead of "could not be verified".
  if (result == null) return _TagWriteOutcome.unavailable;
  if (result is bool) {
    if (result) return _TagWriteOutcome.accepted;
    return _TagWriteOutcome.failed;
  }
  if (result is Map) {
    if (result['verified'] == true) return _TagWriteOutcome.verified;
    if (result['verified'] == false) return _TagWriteOutcome.unverified;
    if (result['ok'] == true) return _TagWriteOutcome.accepted;
    if (result['ok'] == false) return _TagWriteOutcome.rejected;
  }
  return _TagWriteOutcome.failed;
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
  if (result == true) return true;
  if (result is Map) {
    if (result['verified'] == true) return true;
    if (result['verified'] == false) return false;
    if (result['ok'] == true) return true; // treat ok:true as verified
  }
  return false;
}

class _TagEditorDiff {
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final String trackNumber;
  final String discNumber;
  final String comment;
  final String lyrics;
  final String? newArtworkPath;
  final bool removeArtwork;
  final Uint8List? artworkBytes;
  final Set<String> userEditedFields;
  final bool batchArtistEdited;
  final bool batchAlbumEdited;
  final bool batchGenreEdited;
  final bool batchYearEdited;
  final bool batchTrackEdited;
  final bool batchDiscEdited;
  final bool batchCommentEdited;

  _TagEditorDiff.fromCubit(TagEditorCubit c)
      : title = c.state.title,
        artist = c.state.artist,
        album = c.state.album,
        genre = c.state.genre,
        year = c.state.year,
        trackNumber = c.state.trackNumber,
        discNumber = c.state.discNumber,
        comment = c.state.comment,
        lyrics = c.state.lyrics,
        newArtworkPath = c.state.newArtworkPath,
        removeArtwork = c.state.removeArtwork,
        artworkBytes = c.state.artworkBytes,
        userEditedFields = Set<String>.from(c._userEditedFields),
        batchArtistEdited = c._batchArtistEdited,
        batchAlbumEdited = c._batchAlbumEdited,
        batchGenreEdited = c._batchGenreEdited,
        batchYearEdited = c._batchYearEdited,
        batchTrackEdited = c._batchTrackEdited,
        batchDiscEdited = c._batchDiscEdited,
        batchCommentEdited = c._batchCommentEdited;

  TagEditorState applyTo(TagEditorState s) => s.copyWith(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year,
        trackNumber: trackNumber,
        discNumber: discNumber,
        comment: comment,
        lyrics: lyrics,
        newArtworkPath: newArtworkPath,
        clearNewArtworkPath: newArtworkPath == null,
        removeArtwork: removeArtwork,
        artworkBytes: artworkBytes,
        clearArtworkBytes: artworkBytes == null,
        status: s.status == TagEditorStatus.failure
            ? TagEditorStatus.loaded
            : s.status,
        clearError: true,
      );
}

class _TagWriteRejectedException implements Exception {
  const _TagWriteRejectedException();
}

class _TagWriteFailedException implements Exception {
  const _TagWriteFailedException();
}

class _UnverifiedTagWriteException implements Exception {
  const _UnverifiedTagWriteException();
}
