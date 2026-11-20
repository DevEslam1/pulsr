// lib/data/audio/native_dsd_file_source.dart
//
// File-backed DSD reader for the native session. The PCM/DoP path still
// decodes in memory and is capped; native playback must not be, because a
// 30-minute DSD64 stereo track is ~1.3 GB and DSD256 is several GB.
// This reader parses the header once and streams block/byte-interleaved
// payloads straight from disk, so the producer only ever holds one chunk.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dsd_decoder_helper.dart';

class NativeDsdChunk {
  final Uint8List left;
  final Uint8List right;
  const NativeDsdChunk(this.left, this.right);
}

class NativeDsdFileSource {
  final RandomAccessFile _file;
  final bool isDsf;
  final int dataOffset;
  final int totalBytes;
  final int dsdRate;
  final bool msbFirst;
  final int channels;
  final int blockSize;
  int _position = 0;

  NativeDsdFileSource._({
    required RandomAccessFile file,
    required this.isDsf,
    required this.dataOffset,
    required this.totalBytes,
    required this.dsdRate,
    required this.msbFirst,
    required this.channels,
    required this.blockSize,
  }) : _file = file;

  int get position => _position;
  double get _bytesPerSecondPerChannel => dsdRate * 44100.0 / 8.0;

  Duration get totalDuration {
    if (_bytesPerSecondPerChannel <= 0) return Duration.zero;
    return Duration(
      microseconds:
          (totalBytes / _bytesPerSecondPerChannel * 1000000).round(),
    );
  }

  static Future<NativeDsdFileSource> open(String path) async {
    final file = File(path);
    final length = await file.length();
    final raf = await file.open(mode: FileMode.read);
    try {
      final headLen = math.min(length, 256 * 1024);
      await raf.setPosition(0);
      final head = await raf.read(headLen);
      final ext = path.split('.').last.toLowerCase();
      if (ext == 'dsf') return _parseDsf(raf, head, length);
      if (ext == 'dff') return _parseDff(raf, head, length);
      throw const FormatException('Unsupported DSD container');
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  static NativeDsdFileSource _parseDsf(
      RandomAccessFile raf, Uint8List head, int fileLength) {
    if (head.length < 52 ||
        String.fromCharCodes(head.sublist(0, 4)) != 'DSD ') {
      throw const FormatException('Not a valid DSF file');
    }
    final data = ByteData.sublistView(head);
    var pos = 28;
    var channels = 2;
    var sampleRate = 2822400;
    var bitsPerSample = 1;
    var sampleCount = 0;
    var blockSize = 4096;
    var dataOffset = -1;
    var dataSize = -1;
    while (pos + 12 <= head.length) {
      final id = String.fromCharCodes(head.sublist(pos, pos + 4));
      final size = data.getUint64(pos + 4, Endian.little);
      if (size < 0) break;
      if (id == 'fmt ' && pos + 52 <= head.length) {
        channels = data.getUint32(pos + 24, Endian.little);
        sampleRate = data.getUint32(pos + 28, Endian.little);
        bitsPerSample = data.getUint32(pos + 32, Endian.little);
        sampleCount = data.getUint64(pos + 36, Endian.little);
        blockSize = data.getUint32(pos + 44, Endian.little);
      } else if (id == 'data') {
        dataOffset = pos + 12;
        dataSize = size - 12;
        break;
      }
      if (size <= 0) break;
      pos += size;
    }
    if (dataOffset < 0 || dataOffset >= fileLength) {
      throw const FormatException('DSF file contains no audio data');
    }
    if (channels != 1 && channels != 2) {
      throw DsdUnsupportedException(
          'DSF with $channels channels is not supported');
    }
    if (blockSize <= 0) blockSize = 4096;
    dataSize = math.min(dataSize, fileLength - dataOffset);
    final bytesPerChannel = dataSize ~/ channels;
    final trimmed = sampleCount > 0
        ? math.min(bytesPerChannel, (sampleCount + 7) ~/ 8)
        : bytesPerChannel;
    return NativeDsdFileSource._(
      file: raf,
      isDsf: true,
      dataOffset: dataOffset,
      totalBytes: trimmed,
      dsdRate: (sampleRate ~/ 44100).clamp(1, 1024),
      msbFirst: bitsPerSample == 8,
      channels: channels,
      blockSize: blockSize,
    );
  }

  static NativeDsdFileSource _parseDff(
      RandomAccessFile raf, Uint8List head, int fileLength) {
    if (head.length < 32 ||
        String.fromCharCodes(head.sublist(0, 4)) != 'FRM8') {
      throw const FormatException('Not a valid DFF file');
    }
    final data = ByteData.sublistView(head);
    var pos = 16;
    var dsdRate = 64;
    var channels = 2;
    var dataOffset = -1;
    var dataSize = -1;
    while (pos + 12 <= head.length) {
      final id = String.fromCharCodes(head.sublist(pos, pos + 4));
      final size = data.getUint64(pos + 4, Endian.big);
      if (size < 0) break;
      if (id == 'PROP') {
        final end = math.min(pos + 12 + size, head.length);
        var sub = pos + 16;
        while (sub + 12 <= end) {
          final subId = String.fromCharCodes(head.sublist(sub, sub + 4));
          final subSize = data.getUint64(sub + 4, Endian.big);
          if (subSize < 0) break;
          if (subId == 'FS  ' && subSize >= 4 && sub + 16 <= end) {
            dsdRate = data.getUint32(sub + 12, Endian.big) ~/ 44100;
          } else if (subId == 'CHNL' &&
              subSize >= 2 &&
              sub + 14 <= end) {
            channels = data.getUint16(sub + 12, Endian.big);
          } else if (subId == 'CMPR' && subSize >= 4 && sub + 16 <= end) {
            final type = String.fromCharCodes(head.sublist(sub + 12, sub + 16));
            if (type != 'DSD ') {
              throw DsdUnsupportedException(
                  'Compressed DFF ($type) is not supported');
            }
          }
          sub += 12 + subSize + (subSize & 1);
        }
      } else if (id == 'FS  ') {
        if (size >= 4 && pos + 16 <= head.length) {
          dsdRate = data.getUint32(pos + 12, Endian.big) ~/ 44100;
        }
      } else if (id == 'DSD ') {
        dataOffset = pos + 12;
        dataSize = size;
        break;
      }
      pos += 12 + size + (size & 1);
    }
    if (dataOffset < 0 || dataOffset >= fileLength) {
      throw const FormatException('DFF file contains no DSD audio chunk');
    }
    if (channels != 1 && channels != 2) {
      throw DsdUnsupportedException(
          'DFF with $channels channels is not supported');
    }
    dataSize = math.min(dataSize, fileLength - dataOffset);
    final perChannel = channels == 2 ? dataSize ~/ 2 : dataSize;
    return NativeDsdFileSource._(
      file: raf,
      isDsf: false,
      dataOffset: dataOffset,
      totalBytes: perChannel,
      dsdRate: dsdRate.clamp(1, 1024),
      msbFirst: true,
      channels: channels,
      blockSize: 0,
    );
  }

  void seek(int byteOffset) {
    _position = byteOffset.clamp(0, totalBytes);
  }

  Future<NativeDsdChunk?> readChunk(int maxBytes) async {
    if (maxBytes <= 0 || _position >= totalBytes) return null;
    final want = math.min(maxBytes, totalBytes - _position);
    if (isDsf) return _readDsfChunk(want);
    return _readDffChunk(want);
  }

  Future<NativeDsdChunk?> _readDsfChunk(int want) async {
    final leftOut = Uint8List(want);
    final rightOut = Uint8List(want);
    var written = 0;
    var perChannelPos = _position;
    while (written < want) {
      final blockIndex = perChannelPos ~/ blockSize;
      final within = perChannelPos % blockSize;
      final inBlock = math.min(blockSize - within, want - written);
      final leftOffset =
          dataOffset + blockIndex * blockSize * channels + within;
      final left = await _readAt(leftOffset, inBlock);
      if (left.length != inBlock) return null;
      leftOut.setRange(written, written + inBlock, left);
      if (channels == 2) {
        final right = await _readAt(leftOffset + blockSize, inBlock);
        if (right.length != inBlock) return null;
        rightOut.setRange(written, written + inBlock, right);
      } else {
        rightOut.setRange(written, written + inBlock, left);
      }
      written += inBlock;
      perChannelPos += inBlock;
    }
    _position = perChannelPos;
    return NativeDsdChunk(leftOut, rightOut);
  }

  Future<NativeDsdChunk?> _readDffChunk(int want) async {
    final frames = want;
    final fileOffset = dataOffset + _position * channels;
    final raw = await _readAt(fileOffset, frames * channels);
    final actualFrames = channels == 2 ? raw.length ~/ 2 : raw.length;
    if (actualFrames <= 0) return null;
    final leftOut = Uint8List(actualFrames);
    final rightOut = Uint8List(actualFrames);
    if (channels == 2) {
      for (var i = 0; i < actualFrames; i++) {
        leftOut[i] = raw[i * 2];
        rightOut[i] = raw[i * 2 + 1];
      }
    } else {
      leftOut.setAll(0, raw);
      rightOut.setAll(0, raw);
    }
    _position += actualFrames;
    return NativeDsdChunk(leftOut, rightOut);
  }

  Future<Uint8List> _readAt(int offset, int length) async {
    await _file.setPosition(offset);
    final bytes = await _file.read(length);
    return bytes;
  }

  Future<void> close() => _file.close();
}
