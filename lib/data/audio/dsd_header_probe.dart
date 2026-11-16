// lib/data/audio/dsd_header_probe.dart
//
// Reads only the rate multiple (64/128/256/512) and, for DSF, the declared bit
// order from a DSF/DFF header.
//
// The playback router must know the rate *before* decoding (the transport
// decision depends on whether a DoP carrier exists at that rate), while the
// full decoder needs the whole file in memory. This probe therefore reads at
// most 8 KB and never throws: an unreadable header returns 0, and the router
// then decodes to PCM instead of guessing a carrier.

import 'dart:io';
import 'dart:typed_data';

/// Extracts the DSD rate multiple from a DSF/DFF file header.
abstract final class DsdHeaderProbe {
  /// Bytes read from the head of the file. DFF keeps the sample-rate chunk
  /// inside PROP/SND, which in practice sits within the first few hundred
  /// bytes; 8 KB covers files with long metadata blocks before the sound data.
  static const int probeBytes = 8 * 1024;

  /// Returns 64, 128, 256 or 512, or 0 when the rate cannot be determined.
  static Future<int> probeMultiple(String path) async {
    final head = await _readHead(path);
    if (head == null) return 0;
    return _extensionOf(path) == 'dsf'
        ? parseDsfMultiple(head)
        : parseDffMultiple(head);
  }

  /// Returns 1 (LSB first) or 8 (MSB first) for a DSF file, 0 when unknown.
  ///
  /// DFF is always MSB first and is not described by a header field.
  static Future<int> probeBitsPerSample(String path) async {
    if (_extensionOf(path) != 'dsf') return 0;
    final head = await _readHead(path);
    if (head == null) return 0;
    return parseDsfBitsPerSample(head);
  }

  static Future<Uint8List?> _readHead(String path) async {
    final ext = _extensionOf(path);
    if (ext != 'dsf' && ext != 'dff') return null;
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      final length = await handle.length();
      final readLength = length < probeBytes ? length : probeBytes;
      return await handle.read(readLength);
    } on FileSystemException {
      return null;
    } finally {
      try {
        await handle?.close();
      } on FileSystemException {
        // Best effort: a failed close on a read-only probe changes nothing.
      }
    }
  }

  /// Parses the sample frequency field of a Sony DSF header.
  ///
  /// DSF layout: `DSD ` (0x00), chunk size (0x04, 8 bytes LE), file size
  /// (0x0C), metadata pointer (0x14), `fmt ` (0x1C), fmt chunk size (0x20).
  /// Inside the fmt chunk: format version +12 (0x28), format id +16 (0x2C),
  /// channel type +20 (0x30), channel count +24 (0x34), **sampling frequency
  /// +28 (0x38, 4 bytes LE)**, bits per sample +32 (0x3C).
  ///
  /// The sampling frequency used to be read at 0x34 — the channel count — so
  /// every stereo DSF probed as "unknown rate" and never reached DoP.
  static int parseDsfMultiple(Uint8List head) {
    if (head.length < 0x3C) return 0;
    if (!_matchesAscii(head, 0, 'DSD ')) return 0;
    if (!_matchesAscii(head, 0x1C, 'fmt ')) return 0;
    final rate = _readUint32Le(head, 0x38);
    return multipleFromSampleRate(rate);
  }

  /// Parses the `bitsPerSample` field of a DSF fmt chunk (0x3C).
  ///
  /// Returns 1 for LSB-first data, 8 for MSB-first data, 0 for anything else
  /// (including a truncated header), matching `DsdDecoderHelper.parseDsfBytes`,
  /// which derives `msbFirst = bitsPerSample == 8`.
  static int parseDsfBitsPerSample(Uint8List head) {
    if (head.length < 0x40) return 0;
    if (!_matchesAscii(head, 0, 'DSD ')) return 0;
    if (!_matchesAscii(head, 0x1C, 'fmt ')) return 0;
    final bits = _readUint32Le(head, 0x3C);
    return bits == 1 || bits == 8 ? bits : 0;
  }

  /// Parses the sample rate inside a Philips DFF header.
  ///
  /// DFF layout: `FRM8` + size, `DSD ` form type, then chunks. The rate lives
  /// in `PROP` -> `SND ` -> `FS  ` (4-byte big-endian sample rate). The chunk
  /// walk is bounded by the probed bytes and tolerates an unknown chunk order.
  static int parseDffMultiple(Uint8List head) {
    if (head.length < 16) return 0;
    if (!_matchesAscii(head, 0, 'FRM8')) return 0;

    var offset = 16; // after 'FRM8' + 8-byte size + 'DSD ' form type
    while (offset + 12 <= head.length) {
      final id = String.fromCharCodes(head.sublist(offset, offset + 4));
      final size = _readUint64Be(head, offset + 4);
      if (size < 0 || size > head.length) {
        // A malformed or truncated size cannot be trusted; stop the walk.
        return 0;
      }
      if (id == 'PROP') {
        return _parsePropChunk(head, offset + 12, size);
      }
      offset += 12 + size + (size.isOdd ? 1 : 0);
    }
    return 0;
  }

  static int _parsePropChunk(Uint8List head, int start, int size) {
    final end = (start + size).clamp(0, head.length);
    var offset = start;
    // PROP starts with a 4-byte form type ('SND ' for sound properties).
    if (offset + 4 <= end) offset += 4;
    while (offset + 12 <= end) {
      final id = String.fromCharCodes(head.sublist(offset, offset + 4));
      final chunkSize = _readUint64Be(head, offset + 4);
      if (chunkSize < 0 || chunkSize > end - offset - 12) return 0;
      if (id == 'FS  ') {
        if (chunkSize < 4) return 0;
        final rate = _readUint32Be(head, offset + 12);
        return multipleFromSampleRate(rate);
      }
      offset += 12 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return 0;
  }

  /// Maps a DSD sample rate (Hz) to its 44.1 kHz multiple.
  static int multipleFromSampleRate(int rateHz) {
    if (rateHz <= 0) return 0;
    final multiple = rateHz ~/ 44100;
    if (rateHz % 44100 != 0) return 0;
    const known = {64, 128, 256, 512};
    return known.contains(multiple) ? multiple : 0;
  }

  static String _extensionOf(String path) {
    final clean = path.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return '';
    return clean.substring(dot + 1).toLowerCase();
  }

  static bool _matchesAscii(Uint8List bytes, int offset, String ascii) {
    if (offset + ascii.length > bytes.length) return false;
    for (var i = 0; i < ascii.length; i++) {
      if (bytes[offset + i] != ascii.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _readUint32Le(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static int _readUint32Be(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// 64-bit big-endian size, clamped to the Dart int range used here.
  static int _readUint64Be(Uint8List bytes, int offset) {
    if (offset + 8 > bytes.length) return -1;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    return value < 0 ? -1 : value;
  }
}
