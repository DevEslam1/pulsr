// lib/features/tag_editor/tag_editor_cubit.dart
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/metadata_search_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'tag_editor_state.dart';

class TagEditorCubit extends Cubit<TagEditorState> {
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/tag_editor');
  final MediaScannerService _scannerService;
  final MetadataSearchService _metadataSearchService;
  final ImagePicker _imagePicker = ImagePicker();

  TagEditorCubit({
    required SongsTableData song,
    List<SongsTableData>? batchSongs,
    required MediaScannerService scannerService,
    MetadataSearchService? metadataSearchService,
  })  : _scannerService = scannerService,
        _metadataSearchService = metadataSearchService ?? MetadataSearchService(),
        super(TagEditorState(
          song: song,
          batchSongs: batchSongs ?? const [],
          title: (batchSongs != null && batchSongs.length > 1) ? '' : song.title,
          artist: song.artist,
          album: song.album,
          genre: song.genre ?? '',
          year: song.year != null ? song.year.toString() : '',
          trackNumber: (batchSongs != null && batchSongs.length > 1) ? '' : (song.trackNumber != null ? song.trackNumber.toString() : ''),
        )) {
    if (!state.isBatchMode) {
      loadTags();
    } else {
      emit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  Future<void> loadTags() async {
    emit(state.copyWith(status: TagEditorStatus.loading));
    try {
      final Map<dynamic, dynamic>? tags = await _channel.invokeMapMethod<dynamic, dynamic>(
        'readTags',
        {'path': state.song.path},
      );

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
      ErrorLogger.log('Failed to read native tags via MethodChannel for ${state.song.path}', error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(status: TagEditorStatus.loaded));
    }
  }

  void updateTitle(String val) => emit(state.copyWith(title: val));
  void updateArtist(String val) => emit(state.copyWith(artist: val));
  void updateAlbum(String val) => emit(state.copyWith(album: val));
  void updateGenre(String val) => emit(state.copyWith(genre: val));
  void updateYear(String val) => emit(state.copyWith(year: val));
  void updateTrackNumber(String val) => emit(state.copyWith(trackNumber: val));
  void updateComment(String val) => emit(state.copyWith(comment: val));
  void updateLyrics(String val) => emit(state.copyWith(lyrics: val));

  Future<void> pickArtwork() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        emit(state.copyWith(
          newArtworkPath: image.path,
          removeArtwork: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to pick artwork image: $e'));
    }
  }

  void removeArtworkImage() {
    emit(state.copyWith(
      removeArtwork: true,
      clearNewArtworkPath: true,
      clearArtworkBytes: true,
    ));
  }

  /// Automatically searches online (iTunes & MusicBrainz) and updates tags + cover art in 1 tap.
  Future<bool> autoFetchOnlineTags() async {
    emit(state.copyWith(isAutoFetching: true, clearErrorMessage: true));
    try {
      final searchTitle = state.title.isNotEmpty ? state.title : state.song.title;
      final searchArtist = state.artist.isNotEmpty ? state.artist : state.song.artist;

      final results = await _metadataSearchService.searchMetadata(
        title: searchTitle,
        artist: searchArtist,
        album: state.album,
      );

      if (results.isEmpty) {
        emit(state.copyWith(
          isAutoFetching: false,
          errorMessage: 'No matching online metadata found for this track.',
        ));
        return false;
      }

      final bestMatch = results.first;
      String? downloadedArtPath;
      if (bestMatch.artworkUrl != null) {
        downloadedArtPath = await _metadataSearchService.downloadArtworkToTemp(bestMatch.artworkUrl!);
      }

      emit(state.copyWith(
        isAutoFetching: false,
        title: bestMatch.title.isNotEmpty ? bestMatch.title : state.title,
        artist: bestMatch.artist.isNotEmpty ? bestMatch.artist : state.artist,
        album: bestMatch.album.isNotEmpty ? bestMatch.album : state.album,
        genre: (bestMatch.genre != null && bestMatch.genre!.isNotEmpty) ? bestMatch.genre : state.genre,
        year: (bestMatch.releaseYear != null && bestMatch.releaseYear!.isNotEmpty) ? bestMatch.releaseYear : state.year,
        trackNumber: (bestMatch.trackNumber != null && bestMatch.trackNumber!.isNotEmpty) ? bestMatch.trackNumber : state.trackNumber,
        newArtworkPath: downloadedArtPath ?? state.newArtworkPath,
        removeArtwork: false,
      ));
      return true;
    } catch (e, st) {
      ErrorLogger.log('Auto-fetch online tags failed', error: e, stackTrace: st, category: 'TagEditorCubit');
      emit(state.copyWith(
        isAutoFetching: false,
        errorMessage: 'Failed to auto-fetch online tags: $e',
      ));
      return false;
    }
  }

  Future<void> saveTags() async {
    emit(state.copyWith(status: TagEditorStatus.saving, clearErrorMessage: true));
    try {
      if (state.isBatchMode) {
        for (final s in state.batchSongs) {
          await _channel.invokeMethod('writeTags', {
            'path': s.path,
            'title': s.title, // keep individual title
            'artist': state.artist.isNotEmpty ? state.artist : s.artist,
            'album': state.album.isNotEmpty ? state.album : s.album,
            'genre': state.genre.isNotEmpty ? state.genre : (s.genre ?? ''),
            'year': state.year.isNotEmpty ? state.year : (s.year?.toString() ?? ''),
            'trackNumber': s.trackNumber?.toString() ?? '',
            'comment': state.comment.isNotEmpty ? state.comment : '',
            'lyrics': '',
            'artworkPath': state.newArtworkPath,
            'removeArtwork': state.removeArtwork,
          });
          await _scannerService.rescanSingleFile(s.path);
        }
        LrcParser.clearCache();
        emit(state.copyWith(status: TagEditorStatus.success));
        return;
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
        'lyrics': state.lyrics,
        'artworkPath': state.newArtworkPath,
        'removeArtwork': state.removeArtwork,
      });

      // Update Drift DB and clear cached parsed lyrics
      LrcParser.clearCache();
      await _scannerService.rescanSingleFile(state.song.path);

      emit(state.copyWith(status: TagEditorStatus.success));
    } on PlatformException catch (e) {
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage: e.message ?? 'Failed to save tags on this device.',
      ));
    } catch (e) {
      emit(state.copyWith(
        status: TagEditorStatus.failure,
        errorMessage: 'Failed to save tags: $e',
      ));
    }
  }
}
