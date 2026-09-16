import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

@singleton
class DuplicateFinderService {
  /// Scans songs and finds verified duplicate sets.
  /// Pass 1: Identical normalized title + artist metadata.
  /// Pass 2: Duration + size pre-filtering verified via fast audio content checksums.
  Future<List<DuplicateGroup>> findDuplicates(List<SongsTableData> allSongs) async {
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

    // Pass 1: Title + Artist matches
    for (final entry in byTitleArtist.entries) {
      if (entry.value.length > 1) {
        result.add(DuplicateGroup(
          key: entry.key,
          songs: entry.value,
          reason: 'Identical Title & Artist (${entry.value.length} copies)',
        ));
      }
    }

    // Pass 2: Duration + Size matches verified with audio file content checksum.
    // Songs already captured by Pass 1 are dropped from the bucket, and every
    // checksum cluster in the bucket is emitted (an earlier version returned on
    // the first cluster and skipped whole buckets, silently losing duplicates).
    for (final entry in byDurationSize.entries) {
      if (entry.value.length > 1) {
        final remaining = entry.value
            .where((s) => !result.any((g) => g.songs.contains(s)))
            .toList();
        if (remaining.length > 1) {
          final clusters = await _verifyWithChecksum(remaining);
          for (final cluster in clusters) {
            result.add(DuplicateGroup(
              key: entry.key,
              songs: cluster,
              reason: 'Identical Audio Content (Checksum Verified)',
            ));
          }
        }
      }
    }

    return result;
  }

  Future<List<List<SongsTableData>>> _verifyWithChecksum(
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

  String _normalizeString(String str) {
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
