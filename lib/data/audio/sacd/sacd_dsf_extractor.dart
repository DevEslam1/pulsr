// lib/data/audio/sacd/sacd_dsf_extractor.dart
//
// Turns one SACD TOC track inside an `.iso` image into a standalone DSF file
// that the existing DSD decoder (lib/data/audio/dsd_decoder_helper.dart) can
// play unchanged.
//
// Assumed on-disc layout for a track's sectors (confirm on a device):
//   * every 2048-byte sector starts with a 12-byte frame header that is not
//     audio ([SacdLayout.sectorHeaderBytes]);
//   * the remaining 2036 bytes are DSD bytes, byte-interleaved across the
//     area's channels (L, R, L, R, ... for stereo);
//   * bytes keep the DSD bit order of the image unless [reverseBits] is set.
//
// DSF output layout written here:
//   DSD chunk (28 bytes) | fmt chunk (52 bytes) | data chunk header (12 bytes)
//   followed by data interleaved in channel-major blocks of
//   [blockSizePerChannel] bytes, the last block zero padded.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../core/utils/error_logger.dart';
import 'iso9660_reader.dart';
import 'sacd_toc.dart';

/// Thrown when a track cannot be extracted into a DSF file.
class SacdDsfException implements Exception {
  /// Creates the exception with a loggable [message].
  const SacdDsfException(this.message);

  /// Human-readable reason, safe to log.
  final String message;

  @override
  String toString() => 'SacdDsfException: $message';
}

/// Serialises the 92-byte DSF preamble (DSD + fmt chunks, data chunk header).
///
/// The byte layout is covered by unit tests; see `DsdHeaderWriter` usage in
/// [SacdDsfExtractor.extractTrack].
class DsfHeaderWriter {
  /// Creates a writer and validates the header fields it will serialise.
  ///
  /// Throws [ArgumentError] for a channel count DSF cannot describe, a
  /// non-positive sample rate or block size, a negative sample count, or a bit
  /// depth other than 1 or 8.
  DsfHeaderWriter({
    required this.channels,
    required this.sampleRateHz,
    required this.sampleCount,
    this.blockSizePerChannel = defaultBlockSize,
    this.bitsPerSample = 1,
  }) {
    if (channelTypeFor(channels) == 0) {
      throw ArgumentError.value(
        channels,
        'channels',
        'DSF supports 1..6 or 8 channels',
      );
    }
    if (sampleRateHz <= 0) {
      throw ArgumentError.value(sampleRateHz, 'sampleRateHz', 'must be > 0');
    }
    if (sampleCount < 0) {
      throw ArgumentError.value(sampleCount, 'sampleCount', 'must be >= 0');
    }
    if (blockSizePerChannel <= 0) {
      throw ArgumentError.value(
        blockSizePerChannel,
        'blockSizePerChannel',
        'must be > 0',
      );
    }
    if (bitsPerSample != 1 && bitsPerSample != 8) {
      throw ArgumentError.value(
        bitsPerSample,
        'bitsPerSample',
        'DSF allows 1 (LSB first) or 8 (MSB first)',
      );
    }
  }

  /// Size of the leading `DSD ` chunk.
  static const int dsdChunkSize = 28;

  /// Size of the `fmt ` chunk.
  static const int fmtChunkSize = 52;

  /// Size of the `data` chunk header that precedes the payload.
  static const int dataChunkHeaderSize = 12;

  /// Total size of [write]'s output: 28 + 52 + 12.
  static const int headerSize =
      dsdChunkSize + fmtChunkSize + dataChunkHeaderSize;

  /// Block size DSF specifies for DSD payloads.
  static const int defaultBlockSize = 4096;

  /// Channel count written into the fmt chunk.
  final int channels;

  /// DSD bit rate in Hz (2822400 for DSD64).
  final int sampleRateHz;

  /// Bits per channel actually carrying audio; padding beyond it is silence.
  final int sampleCount;

  /// Bytes per channel in one interleaved block.
  final int blockSizePerChannel;

  /// Bits per sample: 1 for LSB-first data, 8 for MSB-first data.
  final int bitsPerSample;

  /// DSF `channelType` code, or 0 when [channelCount] cannot be described.
  static int channelTypeFor(int channelCount) {
    switch (channelCount) {
      case 1:
      case 2:
      case 3:
      case 4:
      case 5:
      case 6:
        return channelCount;
      case 8:
        return 7;
      default:
        return 0;
    }
  }

  /// Total file size for [dataBytes] of payload.
  int totalFileSize(int dataBytes) => headerSize + dataBytes;

  /// Serialises the header for [dataBytes] of payload.
  ///
  /// [dataBytes] must be a multiple of `channels * blockSizePerChannel`; the
  /// extractor pads the final block to satisfy that.
  Uint8List write(int dataBytes) {
    if (dataBytes < 0) {
      throw ArgumentError.value(dataBytes, 'dataBytes', 'must be >= 0');
    }
    final buffer = Uint8List(headerSize);
    final view = ByteData.sublistView(buffer);
    // DSD chunk.
    _writeAscii(buffer, 0, 'DSD ');
    view.setUint64(4, dsdChunkSize, Endian.little);
    view.setUint64(12, totalFileSize(dataBytes), Endian.little);
    view.setUint64(20, 0, Endian.little); // metadata pointer, unused
    // fmt chunk.
    _writeAscii(buffer, 28, 'fmt ');
    view.setUint64(32, fmtChunkSize, Endian.little);
    view.setUint32(40, 1, Endian.little); // format version
    view.setUint32(44, 0, Endian.little); // format id: raw DSD
    view.setUint32(48, channelTypeFor(channels), Endian.little);
    view.setUint32(52, channels, Endian.little);
    view.setUint32(56, sampleRateHz, Endian.little);
    view.setUint32(60, bitsPerSample, Endian.little);
    view.setUint64(64, sampleCount, Endian.little);
    view.setUint32(72, blockSizePerChannel, Endian.little);
    view.setUint32(76, 0, Endian.little); // reserved
    // data chunk header; the payload follows immediately.
    _writeAscii(buffer, 80, 'data');
    view.setUint64(84, dataBytes + dataChunkHeaderSize, Endian.little);
    return buffer;
  }

  static void _writeAscii(Uint8List buffer, int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      buffer[offset + i] = text.codeUnitAt(i);
    }
  }
}

/// Extracts a single [SacdTrack] from a SACD ISO image into a DSF file.
class SacdDsfExtractor {
  /// Creates an extractor.
  ///
  /// [sectorHeaderBytes] is the non-audio prefix of each image sector,
  /// [blockSizePerChannel] the DSF interleaving block, [reverseBits] flips the
  /// DSD bit order per byte, and [maxOutputBytes] caps the written file size.
  SacdDsfExtractor({
    this.sectorHeaderBytes = SacdLayout.sectorHeaderBytes,
    this.blockSizePerChannel = DsfHeaderWriter.defaultBlockSize,
    this.reverseBits = false,
    this.maxOutputBytes = 512 * 1024 * 1024,
  });

  /// Non-audio bytes at the start of every image sector.
  final int sectorHeaderBytes;

  /// DSF interleaving block size, in bytes per channel.
  final int blockSizePerChannel;

  /// Whether to reverse the bit order of every DSD byte.
  final bool reverseBits;

  /// Upper bound for the written DSF payload, in bytes.
  final int maxOutputBytes;

  /// Writes track [track] of image [iso] as a DSF file and returns it.
  ///
  /// The file lands in [outDir] when given, otherwise in a `sacd` folder under
  /// the app cache directory. Throws [SacdDsfException] when the track extent,
  /// channel count or output size cannot be honoured, and [IsoFormatException]
  /// when the image is not readable ISO9660.
  Future<File> extractTrack(
    File iso,
    SacdTrack track, {
    Directory? outDir,
  }) async {
    if (track.lengthSectors <= 0) {
      throw SacdDsfException('Track ${track.index} has no sectors to extract');
    }
    if (sectorHeaderBytes < 0 || sectorHeaderBytes >= SacdLayout.sectorSize) {
      throw SacdDsfException(
        'Sector header size $sectorHeaderBytes is not inside 0..'
        '${SacdLayout.sectorSize - 1}',
      );
    }
    if (DsfHeaderWriter.channelTypeFor(track.channels) == 0) {
      throw SacdDsfException(
        'Track ${track.index} declares ${track.channels} channels, which a DSF '
        'file cannot describe',
      );
    }
    final payloadPerSector = SacdLayout.sectorSize - sectorHeaderBytes;
    final totalPayloadBytes = track.lengthSectors * payloadPerSector;
    final bytesPerChannel = totalPayloadBytes ~/ track.channels;
    if (bytesPerChannel == 0) {
      throw SacdDsfException(
        'Track ${track.index} is shorter than one interleaved frame',
      );
    }
    final blocks =
        (bytesPerChannel + blockSizePerChannel - 1) ~/ blockSizePerChannel;
    final paddedPerChannel = blocks * blockSizePerChannel;
    final dataBytes = paddedPerChannel * track.channels;
    if (dataBytes > maxOutputBytes) {
      throw SacdDsfException(
        'Track ${track.index} needs $dataBytes bytes, above the '
        '$maxOutputBytes-byte extraction limit',
      );
    }
    final trackEndBytes = track.startOffsetBytes + track.lengthBytes;
    final reader = await Iso9660Reader.open(iso);
    if (trackEndBytes > reader.fileLength) {
      await reader.close();
      throw SacdDsfException(
        'Track ${track.index} ends at byte $trackEndBytes, past the '
        '${reader.fileLength}-byte image',
      );
    }
    final directory = outDir ?? await _defaultOutputDirectory();
    final output = File(
      '${directory.path}${Platform.pathSeparator}'
      'sacd_track_${track.index.toString().padLeft(2, '0')}_'
      '${track.channels}ch.dsf',
    );
    RandomAccessFile? handle;
    var completed = false;
    try {
      await directory.create(recursive: true);
      handle = await output.open(mode: FileMode.write);
      final header = DsfHeaderWriter(
        channels: track.channels,
        sampleRateHz: track.sampleRateHz,
        sampleCount: bytesPerChannel * 8,
        blockSizePerChannel: blockSizePerChannel,
      ).write(dataBytes);
      await handle.writeFrom(header);
      final channelBlocks = List<Uint8List>.generate(
        track.channels,
        (_) => Uint8List(blockSizePerChannel),
      );
      var filled = 0;
      var channelCursor = 0;
      for (var sector = 0; sector < track.lengthSectors; sector++) {
        final payload = await reader.readAt(
          track.startOffsetBytes +
              sector * SacdLayout.sectorSize +
              sectorHeaderBytes,
          payloadPerSector,
        );
        if (payload.length < payloadPerSector) {
          throw SacdDsfException(
            'Short read in sector ${track.startSector + sector} of track '
            '${track.index}',
          );
        }
        for (var i = 0; i < payload.length; i++) {
          final value = payload[i];
          channelBlocks[channelCursor][filled] =
              reverseBits ? _bitReverse(value) : value;
          channelCursor++;
          if (channelCursor == track.channels) {
            channelCursor = 0;
            filled++;
            if (filled == blockSizePerChannel) {
              await _writeBlocks(handle, channelBlocks);
              filled = 0;
            }
          }
        }
      }
      if (filled > 0) {
        for (final block in channelBlocks) {
          block.fillRange(filled, blockSizePerChannel, 0);
        }
        await _writeBlocks(handle, channelBlocks);
      }
      await handle.flush();
      completed = true;
      return output;
    } finally {
      await handle?.close();
      await reader.close();
      if (!completed) {
        await _discardPartial(output);
      }
    }
  }

  static Future<void> _writeBlocks(
    RandomAccessFile handle,
    List<Uint8List> blocks,
  ) async {
    for (final block in blocks) {
      await handle.writeFrom(block);
    }
  }

  static Future<Directory> _defaultOutputDirectory() async {
    final cache = await getTemporaryDirectory();
    return Directory('${cache.path}${Platform.pathSeparator}sacd');
  }

  static Future<void> _discardPartial(File output) async {
    try {
      if (await output.exists()) await output.delete();
    } on FileSystemException catch (error) {
      ErrorLogger.log(
        'Could not delete a partially written SACD extraction',
        error: error,
        category: 'SacdExtract',
      );
    }
  }

  static Uint8List? _table;

  /// Bit-reversed byte value, for images whose DSD bit order is inverted.
  static int _bitReverse(int value) {
    final table = _table ??= _buildReverseTable();
    return table[value & 0xff];
  }

  static Uint8List _buildReverseTable() {
    final table = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      var reversed = 0;
      for (var bit = 0; bit < 8; bit++) {
        reversed = (reversed << 1) | ((i >> bit) & 1);
      }
      table[i] = reversed;
    }
    return table;
  }
}
