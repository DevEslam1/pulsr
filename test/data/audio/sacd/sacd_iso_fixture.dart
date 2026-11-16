// test/data/audio/sacd/sacd_iso_fixture.dart
//
// Builds a synthetic SACD ISO image entirely in memory: primary volume
// descriptor, root directory, a SACD area directory with two TOC files, a
// Rock Ridge named entry, a readme file and DSD audio sectors that follow the
// assumed 12-byte per-sector frame header.
//
// The fixture is shared by the ISO9660, TOC, probe, extractor and indexer
// tests, so every layout fact lives in exactly one place.

import 'dart:convert';
import 'dart:typed_data';

/// ISO9660 sector size used by the fixture.
const int fixtureSectorSize = 2048;

/// Non-audio prefix of each audio sector in the fixture.
const int fixtureSectorHeaderBytes = 12;

/// A synthetic SACD image plus the offsets a test needs to reason about it.
class SacdIsoFixture {
  /// Builds the image.
  ///
  /// [tocFileNames] decides which TOC files the SACD directory holds,
  /// [trackCount] how the audio sectors are split between tracks, and
  /// [includeSacdDirectory] whether the `SACD` directory exists at all (probe
  /// and indexer negative cases).
  SacdIsoFixture({
    this.channels = 2,
    this.trackCount = 2,
    this.dataSectors = 4,
    this.tocFileNames = const <String>['SACD_2CH.TOC', 'SACD_MCH.TOC'],
    this.includeSacdDirectory = true,
    this.includeRockRidge = true,
    this.entrySize = 16,
    this.areaFlags = 1,
    this.durationSeconds = 5,
  })  : assert(trackCount >= 1),
        assert(dataSectors >= 1) {
    _build();
  }

  static const String readmeText = 'PULSR SACD FIXTURE';

  /// Channel count written into both TOC files.
  final int channels;

  /// Number of tracks the TOC files describe.
  final int trackCount;

  /// Number of audio sectors placed after the metadata sectors.
  final int dataSectors;

  /// TOC file names created inside the SACD directory.
  final List<String> tocFileNames;

  /// Whether the image exposes a `SACD` directory at all.
  final bool includeSacdDirectory;

  /// Whether the SACD directory holds a Rock Ridge `NM` named entry.
  final bool includeRockRidge;

  /// Track entry size declared by the TOC header.
  final int entrySize;

  /// Area flags byte written into the TOC header.
  final int areaFlags;

  /// Duration in seconds written into each TOC entry.
  final int durationSeconds;

  /// The complete image.
  late final Uint8List bytes;

  /// Sector holding the root directory extent.
  late final int rootSector;

  /// First sector of the SACD directory extent (two sectors long).
  late final int sacdSector;

  /// First sector of the audio area.
  late final int dataSector;

  /// Sector holding the root level readme file.
  late final int readmeSector;

  /// TOC file bytes, keyed by file name.
  final Map<String, Uint8List> tocFiles = <String, Uint8List>{};

  /// First sector of each TOC file, keyed by file name.
  final Map<String, int> tocSectors = <String, int>{};

  /// Sectors per track, in TOC order.
  late final List<int> trackSectors;

  /// Byte value of audio payload [payloadIndex] in [sectorIndex].
  int payloadByte(int sectorIndex, int payloadIndex) =>
      (sectorIndex * 37 + payloadIndex * 5 + 1) & 0xff;

  /// Payload bytes per sector once the frame header is removed.
  int get payloadPerSector => fixtureSectorSize - fixtureSectorHeaderBytes;

  /// Rock Ridge name of the extra SACD directory entry.
  static const String rockRidgeName = 'Rock Ridge Track.dsf';

  void _build() {
    var cursor = 20;
    rootSector = cursor++;
    sacdSector = cursor;
    cursor += 2;
    for (final name in tocFileNames) {
      tocSectors[name] = cursor++;
    }
    readmeSector = cursor++;
    dataSector = cursor;
    cursor += dataSectors;

    final image = Uint8List(cursor * fixtureSectorSize);
    _writePrimaryVolumeDescriptor(image);

    var offset = rootSector * fixtureSectorSize;
    offset += _writeRecord(
      image,
      offset,
      identifier: const <int>[0x00],
      extentSector: rootSector,
      sizeBytes: fixtureSectorSize,
      isDirectory: true,
    );
    offset += _writeRecord(
      image,
      offset,
      identifier: const <int>[0x01],
      extentSector: rootSector,
      sizeBytes: fixtureSectorSize,
      isDirectory: true,
    );
    if (includeSacdDirectory) {
      offset += _writeRecord(
        image,
        offset,
        identifier: bytesOf('SACD'),
        extentSector: sacdSector,
        sizeBytes: 2 * fixtureSectorSize,
        isDirectory: true,
      );
    }
    offset += _writeRecord(
      image,
      offset,
      identifier: bytesOf('README.TXT;1'),
      extentSector: readmeSector,
      sizeBytes: readmeText.length,
      isDirectory: false,
    );
    _writeAscii(
      image,
      readmeSector * fixtureSectorSize,
      readmeText,
    );

    trackSectors = _splitSectors(dataSectors, trackCount);
    var nextTrackStart = dataSector;
    final trackTable = <({int start, int length})>[];
    for (final sectors in trackSectors) {
      trackTable.add((start: nextTrackStart, length: sectors));
      nextTrackStart += sectors;
    }
    for (final name in tocFileNames) {
      final toc = buildAreaToc(
        fileName: name,
        channels: channels,
        tracks: trackTable,
        entrySize: entrySize,
        areaFlags: areaFlags,
        durationSeconds: durationSeconds,
      );
      tocFiles[name] = toc;
      _writeBytes(image, tocSectors[name]! * fixtureSectorSize, toc);
    }

    offset = sacdSector * fixtureSectorSize;
    offset += _writeRecord(
      image,
      offset,
      identifier: const <int>[0x00],
      extentSector: sacdSector,
      sizeBytes: 2 * fixtureSectorSize,
      isDirectory: true,
    );
    offset += _writeRecord(
      image,
      offset,
      identifier: const <int>[0x01],
      extentSector: rootSector,
      sizeBytes: fixtureSectorSize,
      isDirectory: true,
    );
    for (final name in tocFileNames) {
      offset += _writeRecord(
        image,
        offset,
        identifier: bytesOf(name),
        extentSector: tocSectors[name]!,
        sizeBytes: tocFiles[name]!.length,
        isDirectory: false,
      );
    }
    offset += _writeRecord(
      image,
      offset,
      identifier: bytesOf('TRACK.DAT;1'),
      extentSector: dataSector,
      sizeBytes: dataSectors * fixtureSectorSize,
      isDirectory: false,
    );
    if (includeRockRidge) {
      _writeRecord(
        image,
        offset,
        identifier: bytesOf('OBJ_0001.DSF;1'),
        extentSector: dataSector,
        sizeBytes: dataSectors * fixtureSectorSize,
        isDirectory: false,
        rockRidgeName: rockRidgeName,
      );
    }

    _writeAudioSectors(image);
    bytes = image;
  }

  void _writeAudioSectors(Uint8List image) {
    for (var sector = 0; sector < dataSectors; sector++) {
      final base = (dataSector + sector) * fixtureSectorSize;
      for (var i = 0; i < fixtureSectorHeaderBytes; i++) {
        image[base + i] = 0xee;
      }
      for (var i = 0; i < payloadPerSector; i++) {
        image[base + fixtureSectorHeaderBytes + i] = payloadByte(sector, i);
      }
    }
  }

  void _writePrimaryVolumeDescriptor(Uint8List image) {
    final base = 16 * fixtureSectorSize;
    image[base] = 0x01;
    _writeAscii(image, base + 1, 'CD001');
    image[base + 6] = 0x01;
    _writeAscii(image, base + 8, 'PULSR');
    _writeRecord(
      image,
      base + 156,
      identifier: const <int>[0x00],
      extentSector: rootSector,
      sizeBytes: fixtureSectorSize,
      isDirectory: true,
    );
  }

  /// TOC bytes for [fileName], built with the assumed header/entry layout.
  Uint8List buildAreaToc({
    required String fileName,
    required int channels,
    required List<({int start, int length})> tracks,
    int entrySize = 16,
    int areaFlags = 1,
    int rateMultiplier = 64,
    int durationSeconds = 5,
    int? declaredEntryCount,
    int? declaredTableOffset,
    String tag = 'SACDTTOC',
  }) {
    final tableOffset = declaredTableOffset ?? 0x20;
    final totalSize = tableOffset + tracks.length * entrySize;
    final buffer = Uint8List(totalSize);
    final view = ByteData.sublistView(buffer);
    _writeAscii(buffer, 0, tag);
    view.setUint8(0x08, 1);
    view.setUint8(0x09, channels);
    view.setUint16(0x0A, entrySize, Endian.little);
    view.setUint16(0x0C, declaredEntryCount ?? tracks.length, Endian.little);
    view.setUint16(0x0E, tableOffset, Endian.little);
    view.setUint32(
        0x10, tracks.isEmpty ? 0 : tracks.first.start, Endian.little);
    view.setUint32(
      0x14,
      tracks.fold<int>(0, (sum, track) => sum + track.length),
      Endian.little,
    );
    view.setUint32(0x18, rateMultiplier, Endian.little);
    view.setUint8(0x1C, areaFlags);
    for (var i = 0; i < tracks.length; i++) {
      final entry = tableOffset + i * entrySize;
      view.setUint8(entry, i + 1);
      if (entrySize >= 2) {
        view.setUint8(entry + 1, areaFlags & 0x03);
      }
      if (entrySize >= 12) {
        view.setUint32(entry + 4, tracks[i].start, Endian.little);
        view.setUint32(entry + 8, tracks[i].length, Endian.little);
      }
      if (entrySize >= 16) {
        view.setUint32(entry + 12, durationSeconds, Endian.little);
      }
    }
    return buffer;
  }

  /// Copy of [source] with one both-endian 32-bit field overwritten.
  static Uint8List withBothEndianU32(
    Uint8List source,
    int offset,
    int value,
  ) {
    final copy = Uint8List.fromList(source);
    final view = ByteData.sublistView(copy);
    view.setUint32(offset, value, Endian.little);
    view.setUint32(offset + 4, value, Endian.big);
    return copy;
  }

  static int _writeRecord(
    Uint8List image,
    int offset, {
    required List<int> identifier,
    required int extentSector,
    required int sizeBytes,
    required bool isDirectory,
    String? rockRidgeName,
  }) {
    final systemUse = <int>[];
    if (rockRidgeName != null) {
      final nameBytes = utf8.encode(rockRidgeName);
      systemUse
        ..add(0x4e) // 'N'
        ..add(0x4d) // 'M'
        ..add(nameBytes.length + 5)
        ..add(0x01)
        ..add(0x00)
        ..addAll(nameBytes);
    }
    final padAfterIdentifier = identifier.length.isEven ? 1 : 0;
    var length = 33 + identifier.length + padAfterIdentifier + systemUse.length;
    final evenPad = length.isOdd ? 1 : 0;
    length += evenPad;

    final view = ByteData.sublistView(image, offset, offset + length);
    image[offset] = length;
    image[offset + 1] = 0;
    view.setUint32(2, extentSector, Endian.little);
    view.setUint32(6, extentSector, Endian.big);
    view.setUint32(10, sizeBytes, Endian.little);
    view.setUint32(14, sizeBytes, Endian.big);
    image[offset + 25] = isDirectory ? 0x02 : 0x00;
    view.setUint16(28, 1, Endian.little);
    view.setUint16(30, 1, Endian.big);
    image[offset + 32] = identifier.length;
    for (var i = 0; i < identifier.length; i++) {
      image[offset + 33 + i] = identifier[i];
    }
    var cursor = offset + 33 + identifier.length + padAfterIdentifier;
    for (final byte in systemUse) {
      image[cursor++] = byte;
    }
    return length;
  }

  static List<int> _splitSectors(int total, int parts) {
    final base = total ~/ parts;
    final remainder = total % parts;
    return List<int>.generate(parts, (i) => base + (i < remainder ? 1 : 0));
  }

  static List<int> bytesOf(String text) => utf8.encode(text);

  static void _writeAscii(Uint8List target, int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      target[offset + i] = text.codeUnitAt(i);
    }
  }

  static void _writeBytes(Uint8List target, int offset, Uint8List source) {
    for (var i = 0; i < source.length; i++) {
      target[offset + i] = source[i];
    }
  }
}
