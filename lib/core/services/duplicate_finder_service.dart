import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/l10n_holder.dart';
import 'chain_of_custody_service.dart';

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

typedef RawDuplicateGroup = ({
  String key,
  List<SongsTableData> songs,
  bool isChecksum,
});

Future<List<RawDuplicateGroup>> _findRawDuplicatesWorker(
    List<SongsTableData> allSongs) async {
  return DuplicateFinderService.findRawDuplicates(allSongs);
}

@lazySingleton
class DuplicateFinderService {
  /// Scans songs and finds verified duplicate sets.
  /// Pass 1: Identical normalized title + artist, confirmed by album equality
  /// (when known) and a duration tolerance so only the same recording clusters.
  /// Pass 2: Duration + size pre-filtering verified via fast audio content checksums.
  /// Offloads execution to a background isolate via [compute] for larger collections.
  Future<List<DuplicateGroup>> findDuplicates(
      List<SongsTableData> allSongs) async {
    final List<RawDuplicateGroup> rawGroups;
    if (allSongs.length < 20) {
      rawGroups = await findRawDuplicates(allSongs);
    } else {
      rawGroups = await compute(_findRawDuplicatesWorker, allSongs);
    }
    return rawGroups.map(formatDuplicateGroup).toList();
  }

  static DuplicateGroup formatDuplicateGroup(RawDuplicateGroup raw) {
    return DuplicateGroup(
      key: raw.key,
      songs: raw.songs,
      reason: raw.isChecksum
          ? (L10nHolder.current?.dupReasonChecksum ??
              'Identical Audio Content (Checksum Verified)')
          : (L10nHolder.current?.dupReasonTitleArtist(raw.songs.length) ??
              'Identical Title & Artist (${raw.songs.length} copies)'),
    );
  }

  static Future<List<DuplicateGroup>> findDuplicatesInternal(
      List<SongsTableData> allSongs) async {
    final raw = await findRawDuplicates(allSongs);
    return raw.map(formatDuplicateGroup).toList();
  }

  static Future<List<RawDuplicateGroup>> findRawDuplicates(
      List<SongsTableData> allSongs) async {
    final Map<String, List<SongsTableData>> byTitleArtist = {};
    final Map<(int, int), List<SongsTableData>> byDurationSize = {};

    for (final song in allSongs) {
      if (!SongSource.hasLocalFile(song.source) || song.path.isEmpty) {
        continue;
      }
      final normTitle = _normalizeString(song.title);
      final normArtist = _normalizeString(song.artist);
      final titleArtistKey = '$normTitle-$normArtist';

      byTitleArtist.putIfAbsent(titleArtistKey, () => []).add(song);

      if (song.durationMs > 10000 && song.fileSize != null) {
        final durationBucket = (song.durationMs / 1000).round();
        final sizeBucket = (song.fileSize! / 10000).round();
        byDurationSize
            .putIfAbsent((durationBucket, sizeBucket), () => [])
            .add(song);
      }
    }

    final List<RawDuplicateGroup> result = [];
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
          result.add((
            key: '${entry.key}-${anchor.id}',
            songs: cluster,
            isChecksum: false,
          ));
          for (final song in cluster) {
            capturedSongIds.add(song.id);
          }
        }
      }
    }

    // Pass 2: Duration + Size matches (including adjacent +/-1 buckets for
    // rounding boundary immunity; hygiene pass) verified with checksum.
    final seenCandidateSets = <String>{};
    for (final entry in byDurationSize.entries) {
      final durBucket = entry.key.$1;
      final sizeBucket = entry.key.$2;
      final candidates = <SongsTableData>[];
      final seenIds = <int>{};
      for (var dd = -1; dd <= 1; dd++) {
        for (var ds = -1; ds <= 1; ds++) {
          final neighbor = byDurationSize[(durBucket + dd, sizeBucket + ds)];
          if (neighbor == null) continue;
          for (final song in neighbor) {
            if (!capturedSongIds.contains(song.id) && seenIds.add(song.id)) {
              candidates.add(song);
            }
          }
        }
      }
      if (candidates.length <= 1) continue;
      final sortedIds = (candidates.map((s) => s.id).toList()..sort()).join(',');
      if (!seenCandidateSets.add(sortedIds)) continue;
      final clusters = await _verifyWithChecksum(candidates);
      for (final cluster in clusters) {
        result.add((
          key: '$durBucket-$sizeBucket-${cluster.first.id}',
          songs: cluster,
          isChecksum: true,
        ));
        for (final song in cluster) {
          capturedSongIds.add(song.id);
        }
      }
    }

    return result;
  }

  static const String _promoWords =
      r'(?:official\s+(?:audio|video|music\s+video)|lyric\s+video|audio|video|visualizer|hq|hd|4k)';
  static final RegExp _promotionalNoise = RegExp(
    r'\(\s*' + _promoWords + r'\s*\)|\[\s*' + _promoWords + r'\s*\]',
    caseSensitive: false,
  );

  static final RegExp _versionTagPattern = RegExp(
    r'\b(remix|live|version|edit|acoustic|instrumental|deluxe|mix|extended|clean|explicit|remaster|remastered)\b',
    caseSensitive: false,
  );

  static String _extractVersionTags(String str) {
    final matches = _versionTagPattern.allMatches(str.toLowerCase());
    return matches.map((m) => m.group(0)!).join(',');
  }

  static bool _isUnknownAlbum(String normalizedAlbum) =>
      normalizedAlbum.isEmpty || normalizedAlbum == 'unknownalbum';

  /// Two files inside a title+artist group are the same recording when their
  /// albums agree, missing/zero-duration tracks do not pair with timed tracks or
  /// empty-album siblings, and their durations fall within tolerance.
  static bool _isSameRecording(SongsTableData a, SongsTableData b) {
    final albumA = _normalizeString(a.album);
    final albumB = _normalizeString(b.album);
    final unknownA = _isUnknownAlbum(albumA);
    final unknownB = _isUnknownAlbum(albumB);
    if (!unknownA && !unknownB && albumA != albumB) {
      return false;
    }
    if ((a.durationMs > 0) != (b.durationMs > 0)) {
      return false;
    }
    if (a.durationMs <= 0 && b.durationMs <= 0) {
      return !unknownA && !unknownB && albumA == albumB;
    }
    final diffMs = (a.durationMs - b.durationMs).abs();
    if ((unknownA || unknownB) && diffMs > 2000) {
      return false;
    }
    final tagsA = _extractVersionTags(a.title);
    final tagsB = _extractVersionTags(b.title);
    if (tagsA != tagsB && (tagsA.isNotEmpty || tagsB.isNotEmpty)) {
      if (tagsA.isNotEmpty && tagsB.isNotEmpty && tagsA != tagsB) {
        return false;
      }
      return diffMs <= 2000;
    }
    return diffMs <= _pass1DurationToleranceMs;
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
    final verifiedClusters = <List<SongsTableData>>[];
    for (final cluster in byHash.values.where((c) => c.length > 1)) {
      // Confirm with inline streaming SHA-256 (already running inside compute()
      // for large libraries, avoiding nested Isolate.run spawns).
      final byFullHash = <String, List<SongsTableData>>{};
      for (final song in cluster) {
        final file = File(song.path);
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size > ChainOfCustodyService.maxHashableBytes) continue;
        final fullHash =
            await ChainOfCustodyService.hashFileContentsInline(song.path, size);
        if (fullHash != null) {
          byFullHash.putIfAbsent(fullHash, () => []).add(song);
        }
      }
      for (final verified in byFullHash.values.where((c) => c.length > 1)) {
        verifiedClusters.add(verified);
      }
    }
    return verifiedClusters;
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
    var s = str.replaceAll(_promotionalNoise, '').trim().toLowerCase();

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
