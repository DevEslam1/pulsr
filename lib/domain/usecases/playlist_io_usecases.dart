import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

/// Supported playlist file formats for import/export.
enum PlaylistFormat {
  m3u,
  pls,
  wpl;

  String get extension => name;
}

String _escapeXml(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _decodeXmlEntities(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

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

  /// Generates a `[playlist]` PLS string for a list of songs.
  String generatePlsContent(List<SongsTableData> songs) {
    final buffer = StringBuffer();
    buffer.writeln('[playlist]');
    var index = 0;
    for (final song in songs) {
      if (song.source != SongSource.local) continue;
      index++;
      final artist =
          song.artist.trim().isNotEmpty ? song.artist.trim() : 'Unknown Artist';
      final title =
          song.title.trim().isNotEmpty ? song.title.trim() : 'Unknown Track';
      buffer.writeln('File$index=${song.path}');
      buffer.writeln('Title$index=$artist - $title');
    }
    buffer.writeln('NumberOfEntries=$index');
    buffer.writeln('Version=2');
    return buffer.toString();
  }

  /// Generates a Windows Media Playlist (SMIL) string for a list of songs.
  String generateWplContent(List<SongsTableData> songs) {
    final buffer = StringBuffer();
    buffer.writeln('<?wpl version="1.0"?>');
    buffer.writeln('<smil>');
    buffer.writeln('  <body>');
    buffer.writeln('    <seq>');
    for (final song in songs) {
      if (song.source != SongSource.local) continue;
      buffer.writeln('      <media src="${_escapeXml(song.path)}"/>');
    }
    buffer.writeln('    </seq>');
    buffer.writeln('  </body>');
    buffer.writeln('</smil>');
    return buffer.toString();
  }

  /// Writes playlist content to a temp file and returns the file object.
  Future<File> exportToFile(
    String playlistName,
    List<SongsTableData> songs, {
    PlaylistFormat format = PlaylistFormat.m3u,
  }) async {
    final content = switch (format) {
      PlaylistFormat.m3u => generateM3uContent(songs),
      PlaylistFormat.pls => generatePlsContent(songs),
      PlaylistFormat.wpl => generateWplContent(songs),
    };
    final tempDir = await getTemporaryDirectory();
    final sanitizedName = playlistName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${tempDir.path}/$sanitizedName.${format.extension}');
    await file.writeAsString(content);
    return file;
  }
}

/// Result of importing a playlist file (M3U/M3U8/PLS/WPL).
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

  /// Parses a `[playlist]` INI string and extracts the `FileN=` paths.
  List<String> parsePlsContent(String content) {
    final entries = <int, String>{};

    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final equalsIndex = trimmed.indexOf('=');
      if (equalsIndex <= 0) continue;

      final key = trimmed.substring(0, equalsIndex).trim().toLowerCase();
      if (!key.startsWith('file')) continue;

      final index = int.tryParse(key.substring('file'.length));
      if (index == null) continue;

      var value = trimmed.substring(equalsIndex + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) entries[index] = value;
    }

    final orderedIndexes = entries.keys.toList()..sort();
    return orderedIndexes.map((index) => entries[index]!).toList();
  }

  /// Parses a Windows Media Playlist (SMIL) string and extracts `<media src>`.
  List<String> parseWplContent(String content) {
    final paths = <String>[];
    final mediaRegex = RegExp(
      r'''<media\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')''',
      caseSensitive: false,
    );

    for (final match in mediaRegex.allMatches(content)) {
      final raw = match.group(1) ?? match.group(2) ?? '';
      final decoded = _decodeXmlEntities(raw).trim();
      if (decoded.isNotEmpty) paths.add(decoded);
    }

    return paths;
  }

  List<String> _parseByContent(String content, String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    final extension = dotIndex >= 0 && dotIndex < filePath.length - 1
        ? filePath.substring(dotIndex + 1).toLowerCase()
        : '';

    if (extension == 'pls') return parsePlsContent(content);
    if (extension == 'wpl') return parseWplContent(content);
    if (extension == 'm3u' || extension == 'm3u8') {
      return parseM3uContent(content);
    }

    final lower = content.toLowerCase();
    if (lower.contains('[playlist]')) return parsePlsContent(content);
    if (lower.contains('<smil') || lower.contains('<media')) {
      return parseWplContent(content);
    }
    return parseM3uContent(content);
  }

  /// Reads a playlist file (M3U/M3U8/PLS/WPL) with UTF-8 BOM, Latin-1 fallback,
  /// and relative path resolution.
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

      final rawPaths = _parseByContent(content, filePath);
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
        // Strip URI schemes if present (file:///)
        if (path.startsWith('file://')) {
          try {
            path = Uri.parse(path).toFilePath();
          } catch (_) {
            path = path.replaceFirst('file://', '');
          }
        }
        // Resolve relative paths against playlist parent directory
        if (!p.isAbsolute(path) &&
            !path.contains(':\\') &&
            !path.contains(':/')) {
          path = p.normalize(p.join(playlistDir, path));
        }
        path = path.replaceAll('\\', '/');

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
