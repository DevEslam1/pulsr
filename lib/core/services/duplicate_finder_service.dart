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
  /// Scans songs and finds duplicate sets based on normalized title/artist and duration match.
  List<DuplicateGroup> findDuplicates(List<SongsTableData> allSongs) {
    final Map<String, List<SongsTableData>> byTitleArtist = {};
    final Map<String, List<SongsTableData>> byDurationSize = {};

    for (final song in allSongs) {
      final normTitle = _normalizeString(song.title);
      final normArtist = _normalizeString(song.artist);
      final titleArtistKey = '$normTitle-$normArtist';

      byTitleArtist.putIfAbsent(titleArtistKey, () => []).add(song);

      if (song.durationMs > 10000 && song.fileSize != null) {
        // Group by duration bucket (within 1 second) and similar file size
        final durationBucket = (song.durationMs / 1000).round();
        final sizeBucket = (song.fileSize! / 10000).round();
        final durSizeKey = '$durationBucket-$sizeBucket';
        byDurationSize.putIfAbsent(durSizeKey, () => []).add(song);
      }
    }

    final List<DuplicateGroup> result = [];

    // Title + Artist matches
    for (final entry in byTitleArtist.entries) {
      if (entry.value.length > 1) {
        result.add(DuplicateGroup(
          key: entry.key,
          songs: entry.value,
          reason: 'Identical Title & Artist (${entry.value.length} copies)',
        ));
      }
    }

    // Duration + Size matches (where titles might differ slightly)
    for (final entry in byDurationSize.entries) {
      if (entry.value.length > 1) {
        final alreadyGrouped = result.any((g) => g.songs.contains(entry.value.first));
        if (!alreadyGrouped) {
          result.add(DuplicateGroup(
            key: entry.key,
            songs: entry.value,
            reason: 'Identical Audio Length & File Size',
          ));
        }
      }
    }

    return result;
  }

  String _normalizeString(String str) {
    var s = str
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), '') // remove parenthesized info like (Official Video)
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
        .replaceAll('ç', 'c');

    // Remove punctuation & symbols while preserving Arabic and Unicode alphanumeric letters
    return s.replaceAll(RegExp(r'[\s\-_.,!?:;/@#$%^&*()+={}\[\]|\\<>"~`]+'), '').trim();
  }
}
