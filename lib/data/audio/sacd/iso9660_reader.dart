// lib/data/audio/sacd/iso9660_reader.dart
//
// Minimal, read-only ISO9660 reader: just enough to walk a SACD image from the
// primary volume descriptor to a named file and read a bounded byte range.
//
// Deliberately unsupported: Joliet, multi-extent files, interleaved files,
// Rock Ridge beyond the `NM` (alternate name) entry, and continuation areas
// (`CE`). Those omissions are harmless for SACD images, whose TOC and audio
// data live on plain ISO9660 names.
//
// Safety: every offset and length taken from the image is checked against the
// image length before use, so truncated or hostile images fail with
// [IsoFormatException] and never with a RangeError.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown when an ISO9660 structure is missing, malformed or out of bounds.
class IsoFormatException implements Exception {
  /// Creates the exception with a loggable [message] and an optional [offset].
  const IsoFormatException(this.message, {this.offset});

  /// Human-readable reason, safe to log.
  final String message;

  /// Byte offset the problem was detected at, when known.
  final int? offset;

  @override
  String toString() =>
      'IsoFormatException: $message${offset == null ? '' : ' (byte $offset)'}';
}

/// One directory entry (file or directory) resolved from an ISO9660 image.
class IsoEntry {
  /// Creates an immutable directory entry.
  const IsoEntry({
    required this.name,
    required this.isoName,
    required this.isDirectory,
    required this.extentSector,
    required this.sizeBytes,
  });

  /// Display name: the Rock Ridge `NM` name when present, else [isoName].
  final String name;

  /// ISO9660 identifier with the `;1` version suffix and trailing dot removed.
  final String isoName;

  /// True when the entry is a directory.
  final bool isDirectory;

  /// Logical block address of the extent, in 2048-byte sectors.
  final int extentSector;

  /// Size of the extent in bytes.
  final int sizeBytes;

  /// Byte offset of the extent inside the image.
  int get extentOffset => extentSector * Iso9660Reader.sectorSize;

  @override
  String toString() =>
      'IsoEntry($name, iso: $isoName, dir: $isDirectory, lba: $extentSector, '
      'size: $sizeBytes)';
}

/// Read-only ISO9660 traversal with both-endian validation and bounded reads.
///
/// Open an image with [open] (file backed) or [fromBytes] (in-memory, used by
/// unit tests) and walk it with [list], [lookupPath] and [readFile].
class Iso9660Reader {
  Iso9660Reader._(this._source, this.root);

  /// ISO9660 logical sector size in bytes.
  static const int sectorSize = 2048;

  /// Sector holding the primary volume descriptor.
  static const int primaryVolumeDescriptorSector = 16;

  /// Upper bound for [readFile] so a hostile image cannot exhaust memory.
  static const int maxBoundedReadBytes = 16 * 1024 * 1024;

  static const int _maxDirectoryBytes = 512 * 1024;
  static const int _maxPathSegments = 12;
  static const String _volumeDescriptorMagic = 'CD001';

  final _IsoByteSource _source;

  /// Root directory of the volume.
  final IsoEntry root;

  /// Size of the image in bytes.
  int get fileLength => _source.length;

  /// Opens [file] and resolves its primary volume descriptor.
  ///
  /// Throws [IsoFormatException] when the image has no valid ISO9660 primary
  /// volume descriptor, and [FileSystemException] when the file cannot be read.
  static Future<Iso9660Reader> open(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final length = await handle.length();
      final source = _FileByteSource(handle, length);
      final rootEntry = await _readRootDirectory(source);
      return Iso9660Reader._(source, rootEntry);
    } catch (_) {
      if (handle != null) {
        await handle.close();
      }
      rethrow;
    }
  }

  /// Reads an image already held in memory.
  ///
  /// Throws [IsoFormatException] when [bytes] is not an ISO9660 image.
  static Future<Iso9660Reader> fromBytes(Uint8List bytes) async {
    final source = _MemoryByteSource(bytes);
    final rootEntry = await _readRootDirectory(source);
    return Iso9660Reader._(source, rootEntry);
  }

  /// Releases the underlying file handle (no-op for in-memory images).
  Future<void> close() => _source.close();

  /// Lists the direct children of [directory], skipping `.` and `..`.
  ///
  /// Throws [IsoFormatException] for a non-directory argument, a malformed
  /// record, or a directory extent that leaves the image or the read bound.
  Future<List<IsoEntry>> list(IsoEntry directory) async {
    if (!directory.isDirectory) {
      throw IsoFormatException(
        'Cannot list "${directory.name}": not a directory',
        offset: directory.extentOffset,
      );
    }
    if (directory.sizeBytes == 0) return const <IsoEntry>[];
    if (directory.sizeBytes > _maxDirectoryBytes) {
      throw IsoFormatException(
        'Directory extent of ${directory.sizeBytes} bytes exceeds the '
        '$_maxDirectoryBytes-byte read limit',
        offset: directory.extentOffset,
      );
    }
    final bytes =
        await _readExtent(directory.extentOffset, directory.sizeBytes);
    final entries = <IsoEntry>[];
    var position = 0;
    while (position < bytes.length) {
      final recordLength = bytes[position];
      if (recordLength == 0) {
        // A zero length byte means "rest of this sector is padding".
        final nextSector = ((position ~/ sectorSize) + 1) * sectorSize;
        if (nextSector <= position) break;
        position = nextSector;
        continue;
      }
      final record = _parseDirectoryRecord(
        bytes,
        position,
        bytes.length,
        absoluteBase: directory.extentOffset,
      );
      if (!record.isSelf && !record.isParent) {
        entries.add(record.entry);
      }
      position += recordLength;
    }
    return entries;
  }

  /// Resolves a slash separated path such as `SACD` or `SACD/SACD_2CH.TOC`.
  ///
  /// Matching is case-insensitive over both the Rock Ridge name and the ISO
  /// identifier. Returns null when any segment is missing; throws
  /// [IsoFormatException] when a directory extent is malformed.
  Future<IsoEntry?> lookupPath(String path) async {
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (segments.length > _maxPathSegments) return null;
    var current = root;
    for (final segment in segments) {
      if (!current.isDirectory) return null;
      final children = await list(current);
      final wanted = segment.toLowerCase();
      IsoEntry? match;
      for (final child in children) {
        if (child.name.toLowerCase() == wanted ||
            child.isoName.toLowerCase() == wanted) {
          match = child;
          break;
        }
      }
      if (match == null) return null;
      current = match;
    }
    return current;
  }

  /// Reads a whole file entry, bounded by [maxBytes].
  ///
  /// Throws [IsoFormatException] when the entry is a directory, when its size
  /// exceeds [maxBytes], or when its extent leaves the image.
  Future<Uint8List> readFile(
    IsoEntry file, {
    int maxBytes = maxBoundedReadBytes,
  }) async {
    if (file.isDirectory) {
      throw IsoFormatException(
        'Cannot read directory "${file.name}" as a file',
        offset: file.extentOffset,
      );
    }
    if (file.sizeBytes > maxBytes) {
      throw IsoFormatException(
        'File "${file.name}" is ${file.sizeBytes} bytes, above the '
        '$maxBytes-byte bounded read limit',
        offset: file.extentOffset,
      );
    }
    return _readExtent(file.extentOffset, file.sizeBytes);
  }

  /// Reads up to [length] bytes at [offset], clamped to the end of the image.
  ///
  /// Returns an empty buffer once [offset] is at or past the image end, which
  /// lets callers stream sectors without pre-computing every bound.
  Future<Uint8List> readAt(int offset, int length) async {
    if (offset < 0 || length < 0) {
      throw IsoFormatException('Negative read request at $offset (+$length)');
    }
    if (length == 0 || offset >= _source.length) return Uint8List(0);
    final available = _source.length - offset;
    final take = length < available ? length : available;
    return _source.read(offset, take);
  }

  Future<Uint8List> _readExtent(int offset, int length) async {
    if (offset < 0 || length < 0 || offset + length > _source.length) {
      throw IsoFormatException(
        'Extent at $offset (+$length bytes) runs past the end of the '
        '${_source.length}-byte image',
        offset: offset,
      );
    }
    if (length == 0) return Uint8List(0);
    return _source.read(offset, length);
  }

  static Future<IsoEntry> _readRootDirectory(_IsoByteSource source) async {
    const descriptorOffset = primaryVolumeDescriptorSector * sectorSize;
    if (source.length < descriptorOffset + sectorSize) {
      throw const IsoFormatException(
        'Image is smaller than the ISO9660 volume descriptor area',
        offset: descriptorOffset,
      );
    }
    final block = await source.read(descriptorOffset, sectorSize);
    if (block.length < sectorSize) {
      throw const IsoFormatException(
        'Short read of the ISO9660 primary volume descriptor',
        offset: descriptorOffset,
      );
    }
    if (block[0] != 0x01) {
      throw IsoFormatException(
        'Sector 16 is not a primary volume descriptor (type 0x'
        '${block[0].toRadixString(16)})',
        offset: descriptorOffset,
      );
    }
    final magic = String.fromCharCodes(block, 1, 6);
    if (magic != _volumeDescriptorMagic) {
      throw IsoFormatException(
        'Sector 16 does not carry the ISO9660 magic "CD001"',
        offset: descriptorOffset + 1,
      );
    }
    final record = _parseDirectoryRecord(
      block,
      156,
      sectorSize,
      absoluteBase: descriptorOffset,
    );
    if (!record.entry.isDirectory) {
      throw const IsoFormatException(
        'Primary volume descriptor has no root directory record',
        offset: descriptorOffset + 156,
      );
    }
    return record.entry;
  }

  static _DirRecord _parseDirectoryRecord(
    Uint8List data,
    int offset,
    int limit, {
    int absoluteBase = 0,
  }) {
    if (offset < 0 || offset + 34 > limit) {
      throw IsoFormatException(
        'Directory record header runs past the data it lives in',
        offset: absoluteBase + offset,
      );
    }
    final recordLength = data[offset];
    if (recordLength < 34) {
      throw IsoFormatException(
        'Directory record length $recordLength is below the ISO9660 minimum '
        'of 34',
        offset: absoluteBase + offset,
      );
    }
    if (offset + recordLength > limit) {
      throw IsoFormatException(
        'Directory record ($recordLength bytes) crosses the end of its extent',
        offset: absoluteBase + offset,
      );
    }
    final extentSector = _readBothEndianUint32(data, offset + 2, absoluteBase);
    final sizeBytes = _readBothEndianUint32(data, offset + 10, absoluteBase);
    final flags = data[offset + 25];
    final identifierLength = data[offset + 32];
    if (identifierLength == 0 ||
        offset + 33 + identifierLength > offset + recordLength) {
      throw IsoFormatException(
        'Directory record identifier length $identifierLength does not fit the '
        '$recordLength-byte record',
        offset: absoluteBase + offset + 32,
      );
    }
    final identifierStart = offset + 33;
    final identifier = Uint8List.sublistView(
      data,
      identifierStart,
      identifierStart + identifierLength,
    );
    final isSelf = identifier.length == 1 && identifier[0] == 0x00;
    final isParent = identifier.length == 1 && identifier[0] == 0x01;
    final isoName = isSelf
        ? '.'
        : isParent
            ? '..'
            : _decodeIsoIdentifier(identifier);
    var name = isoName;
    if (!isSelf && !isParent) {
      final rockRidgeName = _readRockRidgeName(
        data,
        offset,
        recordLength,
        identifierLength,
      );
      if (rockRidgeName != null && rockRidgeName.isNotEmpty) {
        name = rockRidgeName;
      }
    }
    return _DirRecord(
      entry: IsoEntry(
        name: name,
        isoName: isoName,
        isDirectory: flags & 0x02 != 0,
        extentSector: extentSector,
        sizeBytes: sizeBytes,
      ),
      isSelf: isSelf,
      isParent: isParent,
    );
  }

  static String _decodeIsoIdentifier(Uint8List identifier) {
    var text = String.fromCharCodes(identifier);
    final semicolon = text.lastIndexOf(';');
    if (semicolon >= 0) text = text.substring(0, semicolon);
    if (text.endsWith('.') && text.length > 1) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  /// Best-effort Rock Ridge `NM` name; null when the record has none.
  static String? _readRockRidgeName(
    Uint8List data,
    int recordOffset,
    int recordLength,
    int identifierLength,
  ) {
    var position = recordOffset + 33 + identifierLength;
    if (identifierLength.isEven) position += 1;
    final end = recordOffset + recordLength;
    final buffer = BytesBuilder(copy: false);
    while (position + 4 <= end) {
      final signature = String.fromCharCodes(data, position, position + 2);
      final entryLength = data[position + 2];
      if (entryLength < 4 || position + entryLength > end) break;
      if (signature == 'ST') break;
      if (signature == 'NM') {
        final flags = data[position + 4];
        final nameStart = position + 5;
        if (nameStart <= position + entryLength) {
          buffer.add(
            Uint8List.sublistView(data, nameStart, position + entryLength),
          );
        }
        // Bit 0 marks a name that continues in the next NM entry.
        if (flags & 0x01 == 0) break;
      }
      position += entryLength;
    }
    if (buffer.isEmpty) return null;
    return utf8.decode(buffer.takeBytes(), allowMalformed: true);
  }

  static int _readBothEndianUint32(
    Uint8List data,
    int offset,
    int absoluteBase,
  ) {
    if (offset < 0 || offset + 8 > data.length) {
      throw IsoFormatException(
        'Both-endian field runs past its buffer',
        offset: absoluteBase + offset,
      );
    }
    final view = ByteData.sublistView(data, offset, offset + 8);
    final little = view.getUint32(0, Endian.little);
    final big = view.getUint32(4, Endian.big);
    if (little != big) {
      throw IsoFormatException(
        'Both-endian directory field disagrees ($little vs $big)',
        offset: absoluteBase + offset,
      );
    }
    return little;
  }
}

class _DirRecord {
  const _DirRecord({
    required this.entry,
    required this.isSelf,
    required this.isParent,
  });

  final IsoEntry entry;
  final bool isSelf;
  final bool isParent;
}

abstract class _IsoByteSource {
  int get length;

  Future<Uint8List> read(int offset, int length);

  Future<void> close();
}

class _MemoryByteSource implements _IsoByteSource {
  _MemoryByteSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || length < 0 || offset + length > _bytes.length) {
      throw IsoFormatException(
        'Read of $length bytes at $offset runs past the end of the '
        '${_bytes.length}-byte image',
        offset: offset,
      );
    }
    return Uint8List.sublistView(_bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {}
}

class _FileByteSource implements _IsoByteSource {
  _FileByteSource(this._handle, this.length);

  final RandomAccessFile _handle;

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || length < 0 || offset + length > this.length) {
      throw IsoFormatException(
        'Read of $length bytes at $offset runs past the end of the '
        '${this.length}-byte image',
        offset: offset,
      );
    }
    await _handle.setPosition(offset);
    final bytes = await _handle.read(length);
    if (bytes.length != length) {
      throw IsoFormatException(
        'Short read: wanted $length bytes at $offset, got ${bytes.length}',
        offset: offset,
      );
    }
    return bytes;
  }

  @override
  Future<void> close() => _handle.close();
}
