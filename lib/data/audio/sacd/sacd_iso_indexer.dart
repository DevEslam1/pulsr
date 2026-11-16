// lib/data/audio/sacd/sacd_iso_indexer.dart
//
// Composes the ISO9660 reader, the TOC parser and the SACD probe into one
// cached "what tracks does this .iso contain" call for the library scanner.
//
// The cache is keyed by absolute path plus modification time and size, holds at
// most `cacheCapacity` images (LRU, default 4), and never outlives the process:
// SACD images are usually large and fat, so nothing is written to disk.

import 'dart:io';

import '../../../core/utils/error_logger.dart';
import 'iso9660_reader.dart';
import 'sacd_toc.dart';

/// Result of indexing one SACD image.
class SacdIsoIndex {
  /// Creates an immutable index.
  const SacdIsoIndex({
    required this.isoPath,
    required this.imageLengthSectors,
    required this.areas,
  });

  /// Absolute path of the indexed image.
  final String isoPath;

  /// Image length in whole 2048-byte sectors.
  final int imageLengthSectors;

  /// Parsed areas, most preferred first (stereo, multichannel, then master).
  final List<SacdToc> areas;

  /// Area the indexer recommends for playback, or null when none parsed.
  SacdToc? get preferred => areas.isEmpty ? null : areas.first;

  /// Tracks of [preferred], or an empty list when no area parsed.
  List<SacdTrack> get tracks => preferred?.tracks ?? const <SacdTrack>[];
}

/// Parses SACD TOC files out of an ISO image, with a small in-memory LRU.
class SacdIsoIndexer {
  /// Creates an indexer holding at most [cacheCapacity] images.
  SacdIsoIndexer({this.cacheCapacity = 4}) : assert(cacheCapacity > 0);

  /// Largest TOC file the indexer will read from an image.
  static const int maxTocBytes = 1024 * 1024;

  /// Maximum number of cached images.
  final int cacheCapacity;

  final Map<String, SacdIsoIndex> _cache = <String, SacdIsoIndex>{};

  /// Number of images currently cached.
  int get cachedImageCount => _cache.length;

  /// Tracks of the preferred area of [iso].
  ///
  /// Throws [IsoFormatException] when the image is not a readable ISO9660
  /// volume with a SACD directory, and [SacdTocError] when no TOC file inside
  /// it matches the assumed layout.
  Future<List<SacdTrack>> index(File iso) async => (await indexIso(iso)).tracks;

  /// Full index of [iso], cached per path + modification time + size.
  Future<SacdIsoIndex> indexIso(File iso) async {
    final stat = await iso.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw IsoFormatException('SACD image not found: ${iso.path}');
    }
    final key = '${iso.absolute.path}|${stat.modified.microsecondsSinceEpoch}'
        '|${stat.size}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // Re-insert so the most recent hit is last.
      return cached;
    }
    final index = await _build(iso);
    _cache[key] = index;
    while (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    return index;
  }

  /// Drops every cached image.
  void clearCache() => _cache.clear();

  Future<SacdIsoIndex> _build(File iso) async {
    final reader = await Iso9660Reader.open(iso);
    try {
      final area = await reader.lookupPath(SacdLayout.directoryName);
      if (area == null || !area.isDirectory) {
        throw IsoFormatException(
          'Image ${iso.path} has no ${SacdLayout.directoryName} directory',
        );
      }
      final children = await reader.list(area);
      final tocEntries = children
          .where(
            (child) =>
                !child.isDirectory && SacdLayout.isAreaTocFileName(child.name),
          )
          .toList()
        ..sort((a, b) => _areaRank(a.name) - _areaRank(b.name));
      if (tocEntries.isEmpty) {
        throw SacdTocError(
          'Image ${iso.path} contains no SACD TOC file in '
          '/${SacdLayout.directoryName}',
        );
      }
      final imageLengthSectors = reader.fileLength ~/ SacdLayout.sectorSize;
      final areas = <SacdToc>[];
      final failures = <String>[];
      for (final entry in tocEntries) {
        try {
          final bytes = await reader.readFile(entry, maxBytes: maxTocBytes);
          areas.add(
            SacdToc.parse(
              bytes,
              fileName: entry.name,
              imageLengthSectors: imageLengthSectors,
            ),
          );
        } on SacdTocError catch (error) {
          failures.add('${entry.name}: ${error.message}');
          ErrorLogger.log(
            'Unparsable SACD TOC entry ${entry.name}',
            error: error,
            category: 'SacdIndex',
          );
        } on IsoFormatException catch (error) {
          failures.add('${entry.name}: ${error.message}');
          ErrorLogger.log(
            'Unreadable SACD TOC entry ${entry.name}',
            error: error,
            category: 'SacdIndex',
          );
        }
      }
      if (areas.isEmpty) {
        throw SacdTocError(
          'No SACD TOC in ${iso.path} matched the assumed layout '
          '(${failures.join('; ')})',
        );
      }
      return SacdIsoIndex(
        isoPath: iso.absolute.path,
        imageLengthSectors: imageLengthSectors,
        areas: List<SacdToc>.unmodifiable(areas),
      );
    } finally {
      await reader.close();
    }
  }

  static int _areaRank(String fileName) {
    switch (SacdLayout.areaKindForFileName(fileName)) {
      case SacdAreaKind.twoChannel:
        return 0;
      case SacdAreaKind.multiChannel:
        return 1;
      case SacdAreaKind.master:
        return 2;
      case null:
        return 3;
    }
  }
}
