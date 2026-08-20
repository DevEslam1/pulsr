// lib/features/tag_editor/tag_editor_cubit.dart
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import 'tag_editor_state.dart';

class TagEditorCubit extends Cubit<TagEditorState> {
  static const MethodChannel _channel = MethodChannel('com.example.pulsr/tag_editor');
  final MediaScannerService _scannerService;
  final ImagePicker _imagePicker = ImagePicker();

  TagEditorCubit({
    required SongsTableData song,
    required MediaScannerService scannerService,
  })  : _scannerService = scannerService,
        super(TagEditorState(
          song: song,
          title: song.title,
          artist: song.artist,
          album: song.album,
          genre: song.genre ?? '',
          year: song.year != null ? song.year.toString() : '',
          trackNumber: song.trackNumber != null ? song.trackNumber.toString() : '',
        )) {
    loadTags();
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
    } catch (_) {
      // Fallback to loaded with default DB tags if MethodChannel fails or on non-Android platform
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

  Future<void> saveTags() async {
    emit(state.copyWith(status: TagEditorStatus.saving, clearErrorMessage: true));
    try {
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

      // Update Drift DB
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
