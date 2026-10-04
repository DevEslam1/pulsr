import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';

class DuplicateGroup {
  final String key;
  final List<SongsTableData> songs;
  final String reason;

  const DuplicateGroup({
    required this.key,
    required this.songs,
    required this.reason,
  });
}

Future<List<DuplicateGroup>> _findDuplicatesWorker(
    List<SongsTableData> allSongs) async {
  return DuplicateFinderService.findDuplicatesInternal(allSongs);
}

@singleton
class DuplicateFinderService {
  /// Scans songs and finds verified duplicate sets.
  /// Pass 1: Identical normalized title + artist, confirmed by album equality
  /// (when known) and a duration tolerance so only the same recording clusters.
  /// Pass 2: Duration + size pre-filtering verified via fast audio content checksums.
  /// Offloads execution to a background isolate via [compute] for larger collections.
  Future<List<DuplicateGroup>> findDuplicates(
      List<SongsTableData> allSongs) async {
    if (allSongs.length < 20) {
      return findDuplicatesInternal(allSongs);
    }
    return compute(_findDuplicatesWorker, allSongs);
  }

  static Future<List<DuplicateGroup>> findDuplicatesInternal(
      List<SongsTableData> allSongs) async {
    final Map<String, List<SongsTableData>> byTitleArtist = {};
    final Map<String, List<SongsTableData>> byDurationSize = {};

    for (final song in allSongs) {
      final normTitle = _normalizeString(song.title);
      final normArtist = _normalizeString(song.artist);
      final titleArtistKey = '$normTitle-$normArtist';

      byTitleArtist.putIfAbsent(titleArtistKey, () => []).add(song);

      if (song.durationMs > 10000 && song.fileSize != null) {
        final durationBucket = (song.durationMs / 1000).round();
        final sizeBucket = (song.fileSize! / 10000).round();
        final durSizeKey = '$durationBucket-$sizeBucket';
        byDurationSize.putIfAbsent(durSizeKey, () => []).add(song);
      }
    }

    final List<DuplicateGroup> result = [];
    final Set<int> capturedSongIds = {};

    // Pass 1: Title + Artist matches, refined by same-recording heuristics so
    // unrelated tracks that merely share a name (e.g. "Intro" on two albums)
    // are not reported as duplicates. Codec variants of one recording (FLAC vs
    // MP3) still cluster: album must match when both are known and durations
    // must be within [_pass1DurationToleranceMs].
    for (final entry in byTitleArtist.entries) {
      final remaining = List<SongsTableData>.from(entry.value);
      while (remaining.length > 1) {
        final anchor = remaining.removeAt(0);
        final cluster = <SongsTableData>[anchor];
        for (var i = remaining.length - 1; i >= 0; i--) {
          if (_isSameRecording(anchor, remaining[i])) {
            cluster.add(remaining.removeAt(i));
          }
        }
        if (cluster.length > 1) {
          result.add(DuplicateGroup(
            key: '${entry.key}-${anchor.id}',
            songs: cluster,
            reason: 'Identical Title & Artist (${cluster.length} copies)',
          ));
          for (final song in cluster) {
            capturedSongIds.add(song.id);
          }
        }
      }
    }

    // Pass 2: Duration + Size matches verified with audio file content checksum.
    for (final entry in byDurationSize.entries) {
      if (entry.value.length > 1) {
        final remaining =
            entry.value.where((s) => !capturedSongIds.contains(s.id)).toList();
        if (remaining.length > 1) {
          final clusters = await _verifyWithChecksum(remaining);
          for (final cluster in clusters) {
            result.add(DuplicateGroup(
              key: '${entry.key}-${cluster.first.id}',
              songs: cluster,
              reason: 'Identical Audio Content (Checksum Verified)',
            ));
            for (final song in cluster) {
              capturedSongIds.add(song.id);
            }
          }
        }
      }
    }

    return result;
  }

  /// Two files inside a title+artist group are the same recording when their
  /// albums agree (an unknown/empty album is treated as compatible) and their
  /// durations are within [_pass1DurationToleranceMs]. File sizes are
  /// deliberately ignored so lossless and lossy encodes of one track cluster.
  static bool _isSameRecording(SongsTableData a, SongsTableData b) {
    final albumA = _normalizeString(a.album);
    final albumB = _normalizeString(b.album);
    if (albumA.isNotEmpty && albumB.isNotEmpty && albumA != albumB) {
      return false;
    }
    if (a.durationMs <= 0 || b.durationMs <= 0) return true;
    return (a.durationMs - b.durationMs).abs() <= _pass1DurationToleranceMs;
  }

  static const int _pass1DurationToleranceMs = 5000;

  static Future<List<List<SongsTableData>>> _verifyWithChecksum(
      List<SongsTableData> candidates) async {
    final Map<String, List<SongsTableData>> byHash = {};
    for (final song in candidates) {
      final hash = await computeAudioChecksum(song.path);
      if (hash != null) {
        byHash.putIfAbsent(hash, () => []).add(song);
      }
    }
    return byHash.values.where((cluster) => cluster.length > 1).toList();
  }

  /// Computes a fast, collision-resistant audio fingerprint for local files
  /// using the first 64KB and file length.
  static Future<String?> computeAudioChecksum(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final raf = await file.open();
      try {
        final length = await file.length();
        final readLen = length < 65536 ? length : 65536;
        final buffer = await raf.read(readLen);
        final digest = sha256.convert([...buffer, ...utf8.encode('-$length')]);
        return digest.toString();
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  static String _normalizeString(String str) {
    var s = str
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'),
            '') // remove parenthesized info like (Official Video)
        .replaceAll(RegExp(r'\[[^\]]*\]'), ''); // remove bracketed info

    // Strip Arabic Tashkeel
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Normalize Arabic letters
    s = s
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    // Normalize Latin accents
    s = s
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c')
        // Strip Unicode combining diacritical marks (NFD accents e.g. e + \u0301)
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '');

    // Remove punctuation & symbols while preserving Arabic and Unicode alphanumeric letters
    return s
        .replaceAll(RegExp(r'[\s\-_.,!?:;/@#$%^&*()+={}\[\]|\\<>"~`]+'), '')
        .trim();
  }
}
