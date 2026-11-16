// lib/data/audio/sacd/sacd_iso_library.dart
//
// End-to-end open path for a SACD `.iso` image:
//
//   probe (structural)  ->  index (TOC areas)  ->  expand the stereo area's
//   tracks into cached DSF files  ->  hand playable file paths to the caller.
//
// Only the stereo area is expanded: the in-memory DSD decoder supports mono and
// stereo, so extracting a 6-channel area would waste gigabytes on files the
// decoder rejects. An image with only a multichannel area fails with a clean
// [SacdDsfException] instead.
//
// Cached files are content addressed (image path + mtime + track + extraction
// parameters) and complete files are reused across opens; a partially written
// file from an interrupted run is deleted and re-extracted.

import 'dart:io';

import 'sacd_dsf_cache.dart';
import 'sacd_dsf_extractor.dart';
import 'sacd_iso_indexer.dart';
import 'sacd_iso_probe.dart';
import 'sacd_toc.dart';

/// One track expanded from an image, with its cached DSF file.
class SacdOpenedTrack {
  /// Creates an immutable result.
  const SacdOpenedTrack({required this.track, required this.file});

  /// TOC descriptor of the track (number, duration, rate, channels).
  final SacdTrack track;

  /// Cached DSF file the decoder can play directly.
  final File file;
}

/// Opens SACD images and expands their stereo tracks into playable DSF files.
class SacdIsoLibrary {
  /// Creates a library; every collaborator is injectable for tests.
  SacdIsoLibrary({
    SacdIsoIndexer? indexer,
    SacdDsfExtractor? extractor,
    SacdDsfCache? cache,
  })  : _indexer = indexer ?? SacdIsoIndexer(),
        cache = cache ?? SacdDsfCache.shared,
        _extractor = extractor;

  static SacdIsoLibrary? _shared;

  /// Process-wide instance used by the file-intent open path.
  static SacdIsoLibrary get shared => _shared ??= SacdIsoLibrary();

  final SacdIsoIndexer _indexer;

  /// Cache used for extracted DSF files.
  final SacdDsfCache cache;

  final SacdDsfExtractor? _extractor;

  SacdDsfExtractor get _effectiveExtractor =>
      _extractor ?? SacdDsfExtractor(cache: cache);

  /// Runs the cache janitor once. Never throws.
  Future<void> warmUp() => cache.warmUp();

  /// Structural probe, never throws.
  Future<bool> isSacdImage(String path) => isSacdIso(path);

  /// Full index of [iso], cached by the indexer.
  Future<SacdIsoIndex> index(File iso) => _indexer.indexIso(iso);

  /// Expands the stereo tracks of [iso] into cached DSF files.
  ///
  /// [trackNumbers] limits expansion to the TOC track numbers given (the
  /// "selected tracks" case); null expands every stereo track. Throws
  /// [SacdDsfException] when the image is not a SACD image, carries no stereo
  /// area, or a track exceeds the shared in-memory decode limit.
  /// Throws [IsoFormatException] / [SacdTocError] for unreadable images.
  Future<List<SacdOpenedTrack>> openStereo(
    File iso, {
    Set<int>? trackNumbers,
  }) async {
    await cache.warmUp();
    final stat = await iso.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw SacdDsfException('SACD image not found: ${iso.path}');
    }
    await cache.pruneSource(iso, stat);
    final index = await _indexer.indexIso(iso);
    final area = index.stereoToc;
    if (area == null) {
      throw SacdDsfException(
        'Image ${iso.path} has no stereo area; only multichannel SACD areas '
        'were found and the DSD decoder supports 1..2 channels',
      );
    }
    final directory = await cache.directory();
    await directory.create(recursive: true);
    final extractor = _effectiveExtractor;
    final opened = <SacdOpenedTrack>[];
    for (final track in area.tracks) {
      if (trackNumbers != null && !trackNumbers.contains(track.index)) continue;
      final expected = extractor.estimateOutputBytes(track);
      if (expected > extractor.maxOutputBytes) {
        throw SacdDsfException(
          'Track ${track.index} needs $expected bytes, above the '
          '${extractor.maxOutputBytes}-byte in-memory DSD limit',
        );
      }
      final file = await cache.trackFile(
        iso,
        track,
        sectorHeaderBytes: extractor.sectorHeaderBytes,
        blockSizePerChannel: extractor.blockSizePerChannel,
        reverseBits: extractor.reverseBits,
        directory: directory,
      );
      if (!await cache.isReusable(file, expected)) {
        await cache.ensureRoom(expected, keepSourcePath: iso.path);
        await extractor.extractTrack(iso, track, outDir: directory);
      }
      final stat = await file.stat();
      if (stat.size != expected) {
        await cache.isReusable(file, expected); // deletes the short file
        throw SacdDsfException(
          'Extracted track ${track.index} is ${stat.size} bytes, expected '
          '$expected',
        );
      }
      opened.add(SacdOpenedTrack(track: track, file: file));
    }
    return opened;
  }
}
