import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class PlaylistExportUseCase {
  /// Generates #EXTM3U formatted string for a list of songs.
  String generateM3uContent(List<SongsTableData> songs) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    for (final song in songs) {
      // A `ytmusic://` sentinel is meaningless to any other player.
      if (song.source != SongSource.local) continue;
      final durationSec = (song.durationMs / 1000).round();
      final artist =
          song.artist.trim().isNotEmpty ? song.artist.trim() : 'Unknown Artist';
      final title =
          song.title.trim().isNotEmpty ? song.title.trim() : 'Unknown Track';
      buffer.writeln('#EXTINF:$durationSec,$artist - $title');
      buffer.writeln(song.path);
    }
    return buffer.toString();
  }

  /// Writes M3U content to a temp file and returns the file object.
  Future<File> exportToFile(
      String playlistName, List<SongsTableData> songs) async {
    final content = generateM3uContent(songs);
    final tempDir = await getTemporaryDirectory();
    final sanitizedName = playlistName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${tempDir.path}/$sanitizedName.m3u');
    await file.writeAsString(content);
    return file;
  }
}

class M3uImportResult {
  final String playlistName;
  final int totalExtractedPaths;
  final int matchedTrackCount;
  final int createdPlaylistId;
  final List<String> unmatchedPaths;

  const M3uImportResult({
    required this.playlistName,
    required this.totalExtractedPaths,
    required this.matchedTrackCount,
    required this.createdPlaylistId,
    required this.unmatchedPaths,
  });
}

@singleton
class PlaylistImportUseCase {
  final IMusicRepository _repository;

  PlaylistImportUseCase(this._repository);

  /// Parses M3U or M3U8 string content and extracts track file paths.
  List<String> parseM3uContent(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final paths = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      paths.add(trimmed);
    }

    return paths;
  }

  /// Reads M3U file with UTF-8 BOM, Latin-1 fallback, and relative path resolution.
  Future<Result<M3uImportResult>> importPlaylistFromFile({
    required String filePath,
    required String playlistName,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Left(DatabaseFailure('File not found: $filePath'));
      }

      String content;
      final bytes = await file.readAsBytes();
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = latin1.decode(bytes);
      }

      // Strip UTF-8 BOM if present
      if (content.startsWith('\uFEFF')) {
        content = content.substring(1);
      }

      final rawPaths = parseM3uContent(content);
      final playlistDir = file.parent.path;

      final songsResult = await _repository.getAllSongs();
      final allSongs = songsResult.fold((l) => <SongsTableData>[], (r) => r);

      final exactMap = <String, SongsTableData>{};
      final normalizedMap = <String, SongsTableData>{};
      final filenameMap = <String, SongsTableData>{};
      final filenameCounts = <String, int>{};

      for (final song in allSongs) {
        exactMap[song.path] = song;
        final normPath = song.path.replaceAll('\\', '/').toLowerCase();
        normalizedMap[normPath] = song;
        final filename =
            song.path.replaceAll('\\', '/').split('/').last.toLowerCase();
        if (filename.isNotEmpty) {
          filenameCounts[filename] = (filenameCounts[filename] ?? 0) + 1;
          filenameMap[filename] = song;
        }
      }
      // Remove ambiguous filenames that map to multiple songs
      filenameCounts.forEach((filename, count) {
        if (count > 1) filenameMap.remove(filename);
      });

      final matchedSongIds = <int>[];
      final unmatchedPaths = <String>[];

      for (final rawPath in rawPaths) {
        String path = rawPath;
        // Resolve relative paths against playlist parent directory
        if (!path.startsWith('/') &&
            !path.contains(':\\') &&
            !path.contains(':/')) {
          path = '$playlistDir/$path'.replaceAll('\\', '/');
        }

        SongsTableData? matchedSong = exactMap[path];

        if (matchedSong == null) {
          final normPath = path.replaceAll('\\', '/').toLowerCase();
          matchedSong = normalizedMap[normPath];
        }

        if (matchedSong == null) {
          final filename =
              path.replaceAll('\\', '/').split('/').last.toLowerCase();
          matchedSong = filenameMap[filename];
        }

        if (matchedSong != null) {
          matchedSongIds.add(matchedSong.id);
        } else {
          unmatchedPaths.add(rawPath);
        }
      }

      // Create new playlist with the given name
      final createRes = await _repository.createPlaylist(playlistName);
      return await createRes.fold(
        (failure) async => Left(failure),
        (playlistId) async {
          if (matchedSongIds.isNotEmpty) {
            await _repository.addSongsToPlaylist(playlistId, matchedSongIds);
          }

          return Right(
            M3uImportResult(
              playlistName: playlistName,
              totalExtractedPaths: rawPaths.length,
              matchedTrackCount: matchedSongIds.length,
              createdPlaylistId: playlistId,
              unmatchedPaths: unmatchedPaths,
            ),
          );
        },
      );
    } catch (e) {
      return Left(DatabaseFailure('Failed to import playlist', e));
    }
  }
}
