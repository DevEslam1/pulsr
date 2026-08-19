// lib/features/tag_editor/tag_editor_state.dart
import 'dart:typed_data';
import '../../data/db/app_database.dart';

enum TagEditorStatus { initial, loading, loaded, saving, success, failure }

class TagEditorState {
  final SongsTableData song;
  final TagEditorStatus status;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final String trackNumber;
  final String comment;
  final String lyrics;
  final Uint8List? artworkBytes;
  final String? newArtworkPath;
  final bool removeArtwork;
  final String? errorMessage;

  const TagEditorState({
    required this.song,
    this.status = TagEditorStatus.initial,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.year = '',
    this.trackNumber = '',
    this.comment = '',
    this.lyrics = '',
    this.artworkBytes,
    this.newArtworkPath,
    this.removeArtwork = false,
    this.errorMessage,
  });

  TagEditorState copyWith({
    SongsTableData? song,
    TagEditorStatus? status,
    String? title,
    String? artist,
    String? album,
    String? genre,
    String? year,
    String? trackNumber,
    String? comment,
    String? lyrics,
    Uint8List? artworkBytes,
    bool clearArtworkBytes = false,
    String? newArtworkPath,
    bool clearNewArtworkPath = false,
    bool? removeArtwork,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return TagEditorState(
      song: song ?? this.song,
      status: status ?? this.status,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      comment: comment ?? this.comment,
      lyrics: lyrics ?? this.lyrics,
      artworkBytes: clearArtworkBytes ? null : (artworkBytes ?? this.artworkBytes),
      newArtworkPath: clearNewArtworkPath ? null : (newArtworkPath ?? this.newArtworkPath),
      removeArtwork: removeArtwork ?? this.removeArtwork,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
