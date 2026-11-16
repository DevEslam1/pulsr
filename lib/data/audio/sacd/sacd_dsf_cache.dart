// lib/data/audio/sacd/sacd_dsf_cache.dart
//
// On-disk cache for DSF files extracted from SACD `.iso` images.
//
// Extracting a track again on every open is wasteful, but a cache that grows
// without bound is worse: SACD stereo payload is roughly 1 MB per second of
// audio per channel pair. This cache therefore:
//
//   * names every entry from the image path, image modification time, track
//     identity and extraction parameters, so two discs (or two revisions of
//     one disc) can never collide on "track 01";
//   * prunes entries of a source image that changed on disk (delete on source
//     change) before the new revision is extracted;
//   * runs a startup janitor that removes entries older than [maxAge] and
//     enforces a hard [byteBudget], evicting the least recently written entries;
//   * makes room for a new track by evicting other images first, and fails with
//     a clean [SacdDsfException] when even that is not enough.
//
// Free space is not probed by default: Dart exposes no portable "free bytes"
// API. An optional [freeSpaceProbe] hook lets a host with a platform channel
// supply one; without it a write failure surfaces as a clean exception.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/utils/error_logger.dart';
import 'sacd_exceptions.dart';
import 'sacd_toc.dart';

/// Optional provider for the free bytes available under a cache directory.
typedef SacdFreeSpaceProbe = Future<int?> Function(Directory directory);

/// Cache directory manager plus janitor for extracted SACD DSF tracks.
class SacdDsfCache {
  /// Creates a cache.
  ///
  /// [directory] overrides the app cache path (used by tests); when null the
  /// `sacd_cache` folder under the temporary directory is used. [byteBudget] is
  /// the hard upper bound for the whole cache, [maxAge] the age after which the
  /// janitor deletes an entry regardless of the budget.
  SacdDsfCache({
    Directory? directory,
    this.byteBudget = defaultByteBudget,
    this.maxAge = defaultMaxAge,
    this.freeSpaceProbe,
    DateTime Function()? clock,
  })  : _directoryOverride = directory,
        _now = clock ?? DateTime.now {
    if (byteBudget <= 0) {
      throw ArgumentError.value(byteBudget, 'byteBudget', 'must be > 0');
    }
  }

  /// Default hard cache budget: 2 GiB, about one full stereo DSD64 disc.
  static const int defaultByteBudget = 2 * 1024 * 1024 * 1024;

  /// Default maximum age of a cached track.
  static const Duration defaultMaxAge = Duration(days: 7);

  /// Prefix of every file this cache owns.
  static const String filePrefix = 'sacd_';

  /// Suffix of every file this cache owns.
  static const String fileSuffix = '.dsf';

  final Directory? _directoryOverride;
  final int byteBudget;
  final Duration maxAge;
  final SacdFreeSpaceProbe? freeSpaceProbe;
  final DateTime Function() _now;

  Future<Directory>? _resolvedDirectory;
  Future<void>? _warmUpFuture;

  static SacdDsfCache? _shared;

  /// Process-wide cache used by the extractor and the ISO open path.
  static SacdDsfCache get shared => _shared ??= SacdDsfCache();

  /// Resolves (and remembers) the cache directory without creating it.
  Future<Directory> directory() {
    final override = _directoryOverride;
    if (override != null) return Future<Directory>.value(override);
    return _resolvedDirectory ??= _resolveDefaultDirectory();
  }

  static Future<Directory> _resolveDefaultDirectory() async {
    final cache = await getTemporaryDirectory();
    return Directory(
      '${cache.path}${Platform.pathSeparator}sacd_cache',
    );
  }

  /// Runs the janitor once per instance and awaits an in-flight run.
  ///
  /// Safe to call from a constructor; callers that need the cleanup finished
  /// (the open path) await the same future instead of racing it. Never throws.
  Future<void> warmUp() => _warmUpFuture ??= runJanitor();

  /// Removes expired entries and evicts least recently written entries until
  /// the cache is inside [byteBudget]. Never throws.
  Future<void> runJanitor() async {
    try {
      final dir = await directory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        return;
      }
      final now = _now();
      final entries = <_CacheEntry>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !_isCacheFile(entity.path)) continue;
        try {
          final stat = await entity.stat();
          if (stat.type == FileSystemEntityType.notFound) continue;
          if (now.difference(stat.modified) > maxAge) {
            await _deleteQuietly(entity);
            continue;
          }
          entries.add(_CacheEntry(entity, stat.modified, stat.size));
        } catch (error, stack) {
          ErrorLogger.log(
            'Could not stat a cached SACD extraction',
            error: error,
            stackTrace: stack,
            category: 'SacdCache',
          );
        }
      }
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      var total = entries.fold<int>(0, (sum, entry) => sum + entry.size);
      for (final entry in entries) {
        if (total <= byteBudget) break;
        if (await _deleteQuietly(entry.file)) total -= entry.size;
      }
    } catch (error, stack) {
      ErrorLogger.log(
        'SACD cache janitor failed',
        error: error,
        stackTrace: stack,
        category: 'SacdCache',
      );
    }
  }

  /// Deletes cached tracks of [image] that were extracted from a different
  /// revision of the image (path same, modification time or size differs).
  ///
  /// Should be called before extracting from [image] again.
  Future<void> pruneSource(File image, FileStat stat) async {
    try {
      final dir = await directory();
      if (!await dir.exists()) return;
      final stem = sourceStem(image.absolute.path);
      final currentPrefix = '$stem${stat.modified.microsecondsSinceEpoch}_';
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _baseName(entity.path);
        if (!name.startsWith(stem)) continue;
        if (name.startsWith(currentPrefix)) continue;
        await _deleteQuietly(entity);
      }
    } catch (error, stack) {
      ErrorLogger.log(
        'Could not prune stale SACD extractions',
        error: error,
        stackTrace: stack,
        category: 'SacdCache',
      );
    }
  }

  /// Ensures [requiredBytes] can be stored without breaking [byteBudget].
  ///
  /// Evicts the oldest entries of other images first; entries of
  /// [keepSourcePath] are preserved because the caller is about to play them.
  /// Throws [SacdDsfException] when the budget cannot be honoured.
  Future<void> ensureRoom(
    int requiredBytes, {
    required String keepSourcePath,
  }) async {
    if (requiredBytes <= 0) return;
    if (requiredBytes > byteBudget) {
      throw SacdDsfException(
        'The extracted track needs $requiredBytes bytes, above the '
        '$byteBudget-byte SACD cache budget',
      );
    }
    final dir = await directory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return;
    }
    final probe = freeSpaceProbe;
    if (probe != null) {
      try {
        final free = await probe(dir);
        if (free != null && free < requiredBytes) {
          throw SacdDsfException(
            'Not enough free space for a $requiredBytes-byte SACD track '
            '($free bytes available)',
          );
        }
      } on SacdDsfException {
        rethrow;
      } catch (error, stack) {
        // A failing probe must not block playback: fall through and let the
        // write itself fail cleanly if the disk is truly full.
        ErrorLogger.log(
          'SACD free-space probe failed',
          error: error,
          stackTrace: stack,
          category: 'SacdCache',
        );
      }
    }
    final keepPrefix = sourceStem(normalizeSourcePath(keepSourcePath));
    final entries = <_CacheEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !_isCacheFile(entity.path)) continue;
      if (_baseName(entity.path).startsWith(keepPrefix)) continue;
      try {
        final stat = await entity.stat();
        entries.add(_CacheEntry(entity, stat.modified, stat.size));
      } catch (_) {
        // A file that vanished between list and stat needs no eviction.
      }
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    var evicted = 0;
    for (final entry in entries) {
      if (total + requiredBytes <= byteBudget) break;
      if (await _deleteQuietly(entry.file)) {
        total -= entry.size;
        evicted += entry.size;
      }
    }
    if (total + requiredBytes > byteBudget) {
      throw SacdDsfException(
        'SACD cache is still full after evicting $evicted bytes: a '
        '$requiredBytes-byte track does not fit the $byteBudget-byte budget',
      );
    }
  }

  /// Whether [file] holds a complete extraction of [expectedBytes].
  ///
  /// A size mismatch means the previous write was interrupted (crash, power
  /// loss); the file is deleted so the caller re-extracts instead of playing a
  /// truncated stream.
  Future<bool> isReusable(File file, int expectedBytes) async {
    try {
      if (!await file.exists()) return false;
      final stat = await file.stat();
      if (stat.size == expectedBytes) return true;
      await _deleteQuietly(file);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Cache file for one track of [image], named by path + mtime + track.
  ///
  /// Every parameter that changes the payload participates in the name, so a
  /// changed sector layout or bit-order setting can never reuse stale audio.
  Future<File> trackFile(
    File image,
    SacdTrack track, {
    required int sectorHeaderBytes,
    required int blockSizePerChannel,
    required bool reverseBits,
    Directory? directory,
  }) async {
    final dir = directory ?? await this.directory();
    final stat = await image.stat();
    return trackFileFor(
      directory: dir,
      imagePath: image.absolute.path,
      imageModifiedUs: stat.modified.microsecondsSinceEpoch,
      track: track,
      sectorHeaderBytes: sectorHeaderBytes,
      blockSizePerChannel: blockSizePerChannel,
      reverseBits: reverseBits,
    );
  }

  /// Pure name builder used by the extractor and the open path alike.
  static File trackFileFor({
    required Directory directory,
    required String imagePath,
    required int imageModifiedUs,
    required SacdTrack track,
    required int sectorHeaderBytes,
    required int blockSizePerChannel,
    required bool reverseBits,
  }) {
    final sourceStemValue = sourceStem(normalizeSourcePath(imagePath));
    final parameters = [
      sectorHeaderBytes,
      blockSizePerChannel,
      reverseBits ? 1 : 0,
      track.channels,
      track.startSector,
      track.lengthSectors,
      track.dsdRateMultiplier,
    ].join(',');
    final name = '$sourceStemValue${imageModifiedUs}_'
        't${track.index.toString().padLeft(2, '0')}_'
        '${_fnv1a32(parameters)}'
        '$fileSuffix';
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  /// Filename stem shared by every extraction of [imagePath]:
  /// `sacd_<pathHash>_`.
  static String sourceStem(String imagePath) =>
      '$filePrefix${_fnv1a32(normalizeSourcePath(imagePath))}_';

  /// Normalises a source path so the same image always hashes the same.
  static String normalizeSourcePath(String path) {
    var value = path.replaceAll('\\', '/');
    if (Platform.isWindows) value = value.toLowerCase();
    return value;
  }

  /// Extension-only view of the cache file naming contract.
  static bool _isCacheFile(String path) {
    final name = _baseName(path);
    return name.startsWith(filePrefix) && name.endsWith(fileSuffix);
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    final cut = slash > backslash ? slash : backslash;
    return cut >= 0 ? path.substring(cut + 1) : path;
  }

  static Future<bool> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
      return true;
    } on FileSystemException catch (error) {
      ErrorLogger.log(
        'Could not delete a cached SACD extraction',
        error: error,
        category: 'SacdCache',
      );
      return false;
    }
  }

  /// 32-bit FNV-1a; stable across processes and platforms.
  static String _fnv1a32(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      hash ^= (unit >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _CacheEntry {
  const _CacheEntry(this.file, this.modified, this.size);

  final File file;
  final DateTime modified;
  final int size;
}
