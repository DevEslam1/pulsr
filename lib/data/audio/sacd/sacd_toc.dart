// lib/data/audio/sacd/sacd_toc.dart
//
// Parser for the SACD table-of-contents files that live inside a SACD image
// (`/SACD/SACD_2CH.TOC`, `/SACD/SACD_MCH.TOC`, `/SACD/SACD_MS.TOC`).
//
// No published specification covers these files, so the layout below is the
// layout this parser ASSUMES. It is written to be self-describing (entry size,
// entry count and table offset are declared in the header) so every field the
// parser relies on can be validated before use. A mismatch surfaces as
// [SacdTocError], never as a plausible-looking track list.
//
// ASSUMED HEADER (32 bytes, little-endian)
//   off  size  field
//   0x00   8   ASCII tag; only the "SACD" prefix is asserted
//   0x08   1   layout version (1..3 accepted)
//   0x09   1   channel count of the area (1..6)
//   0x0A   2   track entry size in bytes (12..64)
//   0x0C   2   track entry count (1..255)
//   0x0E   2   track entry table offset from file start (>= 0x20)
//   0x10   4   first track start sector (informational)
//   0x14   4   total sectors of the area (informational)
//   0x18   4   DSD rate multiplier relative to 44.1 kHz (0 => 64)
//   0x1C   1   area flags: bit0 two-channel, bit1 multi-channel, bit2 CD layer
//   0x1D   3   reserved
//
// ASSUMED TRACK ENTRY (entrySize bytes, at least 12)
//   +0x00  1   track number, 1-based (0 => table position + 1)
//   +0x01  1   entry flags: bit0 two-channel, bit1 multi-channel
//   +0x02  2   reserved
//   +0x04  4   start sector inside the image (2048-byte sectors)
//   +0x08  4   length in sectors
//   +0x0C  4   duration in seconds (0 => derived); read only when entrySize >= 16
//
// Every offset is bounds-checked against the buffer length, so truncated input
// cannot produce garbage tracks or a RangeError.

import 'dart:typed_data';

/// Thrown when a SACD TOC file does not match the assumed layout.
class SacdTocError implements Exception {
  /// Creates the error with a loggable [message] and an optional [offset].
  const SacdTocError(this.message, {this.offset});

  /// Human-readable reason, safe to log.
  final String message;

  /// Byte offset inside the TOC file the problem was detected at, if known.
  final int? offset;

  @override
  String toString() =>
      'SacdTocError: $message${offset == null ? '' : ' (byte $offset)'}';
}

/// Which SACD area a TOC file describes.
enum SacdAreaKind {
  /// Stereo area (`SACD_2CH.TOC`).
  twoChannel,

  /// Multichannel area (`SACD_MCH.TOC`).
  multiChannel,

  /// Master TOC (`SACD_MS.TOC`), which lists tracks without an area exclusive
  /// channel assignment.
  master,
}

/// Names and geometry constants shared by the SACD readers.
class SacdLayout {
  const SacdLayout._();

  /// Directory inside the image that holds the TOC and audio area files.
  static const String directoryName = 'SACD';

  /// Lower-case extension of a TOC file, without the leading dot.
  static const String tocExtension = 'toc';

  /// ISO9660 sector size used by SACD images.
  static const int sectorSize = 2048;

  /// Bytes reserved at the start of each audio sector for the frame header.
  ///
  /// The remaining `2048 - sectorHeaderBytes` bytes carry DSD audio. The size
  /// is part of the assumed layout: confirm it on a device before trusting an
  /// extraction.
  static const int sectorHeaderBytes = 12;

  /// True when [fileName] looks like a SACD TOC file.
  static bool isAreaTocFileName(String fileName) {
    final base = _baseName(fileName);
    return base.endsWith('.$tocExtension');
  }

  /// Classifies a TOC file name, or null when the name carries no area marker.
  static SacdAreaKind? areaKindForFileName(String fileName) {
    final base = _baseName(fileName);
    if (!base.endsWith('.$tocExtension')) return null;
    if (base.contains('2ch')) return SacdAreaKind.twoChannel;
    if (base.contains('mch')) return SacdAreaKind.multiChannel;
    if (base.contains('_ms')) return SacdAreaKind.master;
    return null;
  }

  static String _baseName(String fileName) =>
      fileName.split('/').last.split(r'\').last.toLowerCase();
}

/// One track of a SACD area, addressed in whole 2048-byte image sectors.
class SacdTrack {
  /// Creates an immutable track descriptor.
  const SacdTrack({
    required this.index,
    required this.startSector,
    required this.lengthSectors,
    required this.durationSeconds,
    required this.channels,
    required this.isTwoChannel,
    required this.dsdRateMultiplier,
  });

  /// 1-based track number as stored in the TOC (table position when absent).
  final int index;

  /// First sector of the track inside the ISO image.
  final int startSector;

  /// Track length in 2048-byte sectors.
  final int lengthSectors;

  /// Track duration in seconds (declared by the TOC, else estimated).
  final double durationSeconds;

  /// Channel count of the area this track belongs to.
  final int channels;

  /// True when the track comes from a two-channel area.
  final bool isTwoChannel;

  /// DSD rate multiplier relative to 44.1 kHz (64 for DSD64, 128 for DSD128).
  final int dsdRateMultiplier;

  /// DSD bit rate in Hz, e.g. 2822400 for DSD64.
  int get sampleRateHz => dsdRateMultiplier * 44100;

  /// Absolute byte offset of the track's first sector in the image.
  int get startOffsetBytes => startSector * SacdLayout.sectorSize;

  /// Raw byte span of the track, including per-sector frame headers.
  int get lengthBytes => lengthSectors * SacdLayout.sectorSize;

  @override
  String toString() => 'SacdTrack($index, lba: $startSector, '
      'sectors: $lengthSectors, ${durationSeconds.toStringAsFixed(2)}s, '
      'ch: $channels, dsd$dsdRateMultiplier)';
}

/// Parsed content of one SACD TOC file.
class SacdToc {
  SacdToc._({
    required this.fileName,
    required this.area,
    required this.channels,
    required this.dsdRateMultiplier,
    required this.areaFlags,
    required this.tracks,
  });

  /// Size of the assumed header in bytes.
  static const int headerSize = 0x20;

  /// Smallest track entry the parser accepts.
  static const int minEntrySize = 12;

  /// Largest track entry the parser accepts.
  static const int maxEntrySize = 64;

  /// Largest track count the parser accepts.
  static const int maxTracks = 255;

  /// Name of the TOC file this instance was parsed from.
  final String fileName;

  /// Area classification derived from the file name, then the area flags.
  final SacdAreaKind area;

  /// Channel count declared by the area.
  final int channels;

  /// DSD rate multiplier relative to 44.1 kHz.
  final int dsdRateMultiplier;

  /// Raw area flags byte from the header.
  final int areaFlags;

  /// Tracks in TOC order.
  final List<SacdTrack> tracks;

  /// True when this TOC describes the stereo area.
  bool get isTwoChannel => area == SacdAreaKind.twoChannel;

  /// Sum of [tracks] durations in seconds.
  double get totalDurationSeconds =>
      tracks.fold<double>(0, (sum, track) => sum + track.durationSeconds);

  /// Parses [bytes] as a SACD TOC file.
  ///
  /// [fileName] selects the area classification and appears in error messages.
  /// When [imageLengthSectors] is supplied, every track extent is checked
  /// against it so a TOC cannot point past the end of the image.
  ///
  /// Throws [SacdTocError] when the buffer is too small, the tag is missing, or
  /// any declared size, count, offset or extent is inconsistent.
  static SacdToc parse(
    Uint8List bytes, {
    required String fileName,
    int? imageLengthSectors,
  }) {
    if (bytes.length < headerSize) {
      throw SacdTocError(
        'TOC "$fileName" is ${bytes.length} bytes, shorter than the '
        '$headerSize-byte header',
        offset: 0,
      );
    }
    final tag = String.fromCharCodes(bytes, 0, 8);
    if (!tag.startsWith('SACD')) {
      throw SacdTocError(
        'TOC "$fileName" does not start with a SACD tag '
        '(found "${_printable(tag)}")',
        offset: 0,
      );
    }
    final view = ByteData.sublistView(bytes);
    final version = view.getUint8(0x08);
    if (version == 0 || version > 3) {
      throw SacdTocError(
        'TOC "$fileName" declares unsupported layout version $version',
        offset: 0x08,
      );
    }
    final channels = view.getUint8(0x09);
    if (channels < 1 || channels > 6) {
      throw SacdTocError(
        'TOC "$fileName" declares $channels channels (expected 1..6)',
        offset: 0x09,
      );
    }
    final entrySize = view.getUint16(0x0A, Endian.little);
    if (entrySize < minEntrySize || entrySize > maxEntrySize) {
      throw SacdTocError(
        'TOC "$fileName" declares a $entrySize-byte track entry '
        '(expected $minEntrySize..$maxEntrySize)',
        offset: 0x0A,
      );
    }
    final entryCount = view.getUint16(0x0C, Endian.little);
    if (entryCount < 1 || entryCount > maxTracks) {
      throw SacdTocError(
        'TOC "$fileName" declares $entryCount tracks '
        '(expected 1..$maxTracks)',
        offset: 0x0C,
      );
    }
    final tableOffset = view.getUint16(0x0E, Endian.little);
    if (tableOffset < headerSize) {
      throw SacdTocError(
        'TOC "$fileName" places its track table at $tableOffset, inside the '
        'header',
        offset: 0x0E,
      );
    }
    final tableEnd = tableOffset + entryCount * entrySize;
    if (tableEnd > bytes.length) {
      throw SacdTocError(
        'TOC "$fileName" track table ends at $tableEnd but the file is only '
        '${bytes.length} bytes',
        offset: 0x0E,
      );
    }
    final declaredRate = view.getUint32(0x18, Endian.little);
    final rateMultiplier = declaredRate == 0 ? 64 : declaredRate;
    if (rateMultiplier != 64 &&
        rateMultiplier != 128 &&
        rateMultiplier != 256 &&
        rateMultiplier != 512) {
      throw SacdTocError(
        'TOC "$fileName" declares an unsupported DSD rate multiplier '
        '$rateMultiplier (expected 64, 128, 256 or 512)',
        offset: 0x18,
      );
    }
    final areaFlags = view.getUint8(0x1C);
    final area = SacdLayout.areaKindForFileName(fileName) ??
        _kindFromFlags(areaFlags, channels);
    final tracks = <SacdTrack>[];
    var previousStart = -1;
    for (var i = 0; i < entryCount; i++) {
      final entryOffset = tableOffset + i * entrySize;
      final number = view.getUint8(entryOffset);
      final flags = view.getUint8(entryOffset + 1);
      final startSector = view.getUint32(entryOffset + 4, Endian.little);
      final lengthSectors = view.getUint32(entryOffset + 8, Endian.little);
      if (startSector == 0 || lengthSectors == 0) {
        throw SacdTocError(
          'TOC "$fileName" track entry ${i + 1} has an empty extent '
          '(start sector $startSector, length $lengthSectors)',
          offset: entryOffset,
        );
      }
      if (startSector < previousStart) {
        throw SacdTocError(
          'TOC "$fileName" track entries are not ordered by start sector '
          '(entry ${i + 1} starts at $startSector, previous at $previousStart)',
          offset: entryOffset,
        );
      }
      if (imageLengthSectors != null &&
          startSector + lengthSectors > imageLengthSectors) {
        throw SacdTocError(
          'TOC "$fileName" track entry ${i + 1} extends past the end of the '
          'image ($startSector + $lengthSectors > $imageLengthSectors sectors)',
          offset: entryOffset,
        );
      }
      previousStart = startSector;
      final declaredDuration =
          entrySize >= 16 ? view.getUint32(entryOffset + 12, Endian.little) : 0;
      tracks.add(
        SacdTrack(
          index: number == 0 ? i + 1 : number,
          startSector: startSector,
          lengthSectors: lengthSectors,
          durationSeconds: declaredDuration > 0
              ? declaredDuration.toDouble()
              : _estimateDuration(lengthSectors, channels, rateMultiplier),
          channels: channels,
          isTwoChannel: flags & 0x01 != 0 || area == SacdAreaKind.twoChannel,
          dsdRateMultiplier: rateMultiplier,
        ),
      );
    }
    return SacdToc._(
      fileName: fileName,
      area: area,
      channels: channels,
      dsdRateMultiplier: rateMultiplier,
      areaFlags: areaFlags,
      tracks: List<SacdTrack>.unmodifiable(tracks),
    );
  }

  /// Duration estimate used when the TOC leaves the duration field at zero.
  ///
  /// Ignores the per-sector frame header, so it runs about 0.6 % long; it is a
  /// display fallback, not a playback timing source.
  static double _estimateDuration(
    int lengthSectors,
    int channels,
    int rateMultiplier,
  ) {
    final sampleRate = rateMultiplier * 44100;
    final bitsPerChannel = lengthSectors * SacdLayout.sectorSize * 8 / channels;
    return bitsPerChannel / sampleRate;
  }

  static SacdAreaKind _kindFromFlags(int flags, int channels) {
    if (flags & 0x01 != 0) return SacdAreaKind.twoChannel;
    if (flags & 0x02 != 0) return SacdAreaKind.multiChannel;
    return channels == 2 ? SacdAreaKind.twoChannel : SacdAreaKind.multiChannel;
  }

  static String _printable(String raw) =>
      raw.replaceAll(RegExp(r'[^\x20-\x7e]'), '?');

  @override
  String toString() => 'SacdToc($fileName, $area, ch: $channels, '
      'tracks: ${tracks.length})';
}
