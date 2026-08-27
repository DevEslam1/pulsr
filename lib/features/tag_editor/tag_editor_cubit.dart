import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/channels.dart';
import '../../core/services/metadata_search_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'tag_editor_state.dart';

class TagEditorCubit extends Cubit<TagEditorState> {
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

  TagEditorCubit({
    required SongsTableData song,
    List<SongsTableData>? batchSongs,
    required MediaScannerService scannerService,
    MetadataSearchService? metadataSearchService,
  })  : _scannerService = scannerService,
        _metadataSearchService = metadataSearchService ?? MetadataSearchService(),
        super(_createInitialState(song, batchSongs)) {
    if (!state.isBatchMode) {
      loadTags();
    } else {
      emit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  static TagEditorState _createInitialState(SongsTableData song, List<SongsTableData>? batchSongs) {
    final isBatch = batchSongs != null && batchSongs.length > 1;
    final allSameArtist = isBatch && batchSongs.every((s) => s.artist == song.artist);
    final allSameAlbum = isBatch && batchSongs.every((s) => s.album == song.album);
    final allSameGenre = isBatch && batchSongs.every((s) => s.genre == song.genre);
    final allSameYear = isBatch && batchSongs.every((s) => s.year == song.year);

    return TagEditorState(
      song: song,
      batchSongs: batchSongs ?? const [],
      title: isBatch ? '' : song.title,
      artist: isBatch ? (allSameArtist ? song.artist : '') : song.artist,
      album: isBatch ? (allSameAlbum ? song.album : '') : song.album,
      genre: isBatch ? (allSameGenre ? (song.genre ?? '') : '') : (song.genre ?? ''),
      year: isBatch ? (allSameYear ? (song.year?.toString() ?? '') : '') : (song.year != null ? song.year.toString() : ''),
      trackNumber: isBatch ? '' : (song.trackNumber != null ? song.trackNumber.toString() : ''),
    );
  }

  Future<void> loadTags() async {
    if (isClosed) return;
    emit(state.copyWith(status: TagEditorStatus.loading));
    try {
      final Map<dynamic, dynamic>? tags = await _channel.invokeMapMethod<dynamic, dynamic>(
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
        final comment = (tags['comment'] as String?)?.trim();
        final lyrics = (tags['lyrics'] as String?)?.trim();
        final artworkData = tags['artwork'] as Uint8List?;

        emit(state.copyWith(
          status: TagEditorStatus.loaded,
          title: (title != null && title.isNotEmpty) ? title : state.title,
          artist: (artist != null && artist.isNotEmpty) ? artist : state.artist,
          album: (album != null && album.isNotEmpty) ? album : state.album,
          genre: genre ?? state.genre,
          year: year ?? state.year,
          trackNumber: trackNumber ?? state.trackNumber,
          comment: comment ?? '',
          lyrics: lyrics ?? '',
          artworkBytes: artworkData,
        ));
      } else {
        emit(state.copyWith(status: TagEditorStatus.loaded));
      }
    } catch (e, st) {
      if (isClosed) return;
      ErrorLogger.log('Failed to read native tags via MethodChannel for ${state.song.path}', error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  void updateTitle(String val) {
    if (isClosed) return;
    emit(state.copyWith(title: val));
  }

  void updateArtist(String val) {
    if (isClosed) return;
    if (state.isBatchMode) _batchArtistEdited = true;
    emit(state.copyWith(artist: val));
  }

  void updateAlbum(String val) {
    if (isClosed) return;
    if (state.isBatchMode) _batchAlbumEdited = true;
    emit(state.copyWith(album: val));
  }

  void updateGenre(String val) {
    if (isClosed) return;
    if (state.isBatchMode) _batchGenreEdited = true;
    emit(state.copyWith(genre: val));
  }

  void updateYear(String val) {
    if (isClosed) return;
    if (state.isBatchMode) _batchYearEdited = true;
    emit(state.copyWith(year: val));
  }

  void updateTrackNumber(String val) {
    if (isClosed) return;
    emit(state.copyWith(trackNumber: val));
  }

  void updateComment(String val) {
    if (isClosed) return;
    emit(state.copyWith(comment: val));
  }

  void updateLyrics(String val) {
    if (isClosed) return;
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
        emit(state.copyWith(
          newArtworkPath: image.path,
          removeArtwork: false,
        ));
      }
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: 'Failed to pick artwork image: $e'));
    }
  }

  void removeArtworkImage() {
    if (isClosed) return;
    emit(state.copyWith(
      removeArtwork: true,
      clearNewArtworkPath: true,
      clearArtworkBytes: true,
    ));
  }

  /// Searches online metadata without immediately auto-applying.
  Future<List<OnlineTrackMetadata>> searchOnlineMatches() async {
    final searchTitle = state.title.isNotEmpty ? state.title : state.song.title;
    final searchArtist = state.artist.isNotEmpty ? state.artist : state.song.artist;
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
        downloadedArtPath = await _metadataSearchService.downloadArtworkToTemp(match.artworkUrl!);
      }
      if (isClosed) return false;

      emit(state.copyWith(
        isAutoFetching: false,
        title: match.title.isNotEmpty ? match.title : state.title,
        artist: match.artist.isNotEmpty ? match.artist : state.artist,
        album: match.album.isNotEmpty ? match.album : state.album,
        genre: (match.genre != null && match.genre!.isNotEmpty) ? match.genre : state.genre,
        year: (match.releaseYear != null && match.releaseYear!.isNotEmpty) ? match.releaseYear : state.year,
        trackNumber: (match.trackNumber != null && match.trackNumber!.isNotEmpty) ? match.trackNumber : state.trackNumber,
        newArtworkPath: downloadedArtPath ?? state.newArtworkPath,
        removeArtwork: false,
      ));
      return true;
    } catch (e, st) {
      if (isClosed) return false;
      ErrorLogger.log('Applying metadata result failed', error: e, stackTrace: st, category: 'TagEditorCubit');
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
      ErrorLogger.log('Auto-fetch online tags failed', error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(
        isAutoFetching: false,
        errorMessage: 'Failed to auto-fetch online tags: $e',
      ));
      return false;
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

    emit(state.copyWith(status: TagEditorStatus.saving, clearErrorMessage: true, batchProgress: 0.0));
    try {
      if (state.isBatchMode) {
        final total = state.batchSongs.length;
        final List<String> failedFiles = [];
        var lastEmitTime = DateTime.now();
        for (int i = 0; i < total; i++) {
          if (isClosed) return;
          final s = state.batchSongs[i];
          final now = DateTime.now();
          if (i == 0 || i == total - 1 || (i % 3 == 0) || now.difference(lastEmitTime).inMilliseconds >= 200) {
            lastEmitTime = now;
            emit(state.copyWith(
              status: TagEditorStatus.saving,
              batchProgress: total > 0 ? (i + 1) / total : 1.0,
            ));
          }
          try {
            await _channel.invokeMethod('writeTags', {
              'path': s.path,
              'title': s.title, // keep individual title
              'artist': _batchArtistEdited ? state.artist : (state.artist.isNotEmpty ? state.artist : s.artist),
              'album': _batchAlbumEdited ? state.album : (state.album.isNotEmpty ? state.album : s.album),
              'genre': _batchGenreEdited ? state.genre : (state.genre.isNotEmpty ? state.genre : (s.genre ?? '')),
              'year': _batchYearEdited ? state.year : (state.year.isNotEmpty ? state.year : (s.year?.toString() ?? '')),
              'trackNumber': s.trackNumber?.toString() ?? '',
              'comment': state.comment.isNotEmpty ? state.comment : '',
              'lyrics': '',
              'artworkPath': state.newArtworkPath,
              'removeArtwork': state.removeArtwork,
            });
            if (isClosed) return;
            await _scannerService.rescanSingleFile(s.path);
          } catch (e, st) {
            ErrorLogger.log('Failed to save tags for ${s.path}', error: e, stackTrace: st, category: 'TagEditor');
            failedFiles.add(s.title);
          }
          if (isClosed) return;
        }
        LrcParser.clearCache();
        if (isClosed) return;
        if (failedFiles.isNotEmpty) {
          emit(state.copyWith(
            status: failedFiles.length == total ? TagEditorStatus.failure : TagEditorStatus.success,
            errorMessage: 'Failed to tag ${failedFiles.length} file${failedFiles.length > 1 ? "s" : ""}',
            clearBatchProgress: true,
          ));
        } else {
          emit(state.copyWith(status: TagEditorStatus.success, clearBatchProgress: true));
        }
        return;
      }

      String lyrics = state.lyrics;
      if (lyrics.length > 8192) {
        lyrics = lyrics.substring(0, 8192);
      }

      await _channel.invokeMethod('writeTags', {
        'path': state.song.path,
        'title': state.title,
        'artist': state.artist,
        'album': state.album,
        'genre': state.genre,
        'year': state.year,
        'trackNumber': state.trackNumber,
        'comment': state.comment,
        'lyrics': lyrics,
        'artworkPath': state.newArtworkPath,
        'removeArtwork': state.removeArtwork,
      });
      if (isClosed) return;

      // Update Drift DB and clear cached parsed lyrics
      LrcParser.clearCache();
      await _scannerService.rescanSingleFile(state.song.path);
      if (isClosed) return;

      emit(state.copyWith(status: TagEditorStatus.success));
    } on PlatformException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage: e.message ?? 'Failed to save tags on this device.',
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
