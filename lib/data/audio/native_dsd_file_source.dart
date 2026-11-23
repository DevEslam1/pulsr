// lib/data/audio/native_dsd_file_source.dart
//
// File-backed DSD reader for the native session. The PCM/DoP path still
// decodes in memory and is capped; native playback must not be, because a
// 30-minute DSD64 stereo track is ~1.3 GB and DSD256 is several GB.
// This reader parses the header once and streams block/byte-interleaved
// payloads straight from disk, so the producer only ever holds one chunk.

import 'dart:async';
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
  int _seekGeneration = 0;
  bool _closed = false;
  Future<void> _opChain = Future<void>.value();

  bool get isClosed => _closed;

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
      final ext = path.split('.').last.toLowerCase();
      if (ext == 'dsf') return await _parseDsf(raf, length);
      if (ext == 'dff') return await _parseDff(raf, length);
      throw const FormatException('Unsupported DSD container');
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  static Future<NativeDsdFileSource> _parseDsf(
      RandomAccessFile raf, int fileLength) async {
    if (fileLength < 52) {
      throw const FormatException('Not a valid DSF file');
    }
    await raf.setPosition(0);
    final magic = await raf.read(4);
    if (magic.length < 4 || String.fromCharCodes(magic) != 'DSD ') {
      throw const FormatException('Not a valid DSF file');
    }
    var pos = 28;
    var channels = 2;
    var sampleRate = 2822400;
    var bitsPerSample = 1;
    var sampleCount = 0;
    var blockSize = 4096;
    var dataOffset = -1;
    var dataSize = -1;
    while (pos + 12 <= fileLength) {
      await raf.setPosition(pos);
      final hdr = await raf.read(12);
      if (hdr.length < 12) break;
      final hdrData = ByteData.sublistView(hdr);
      final id = String.fromCharCodes(hdr.sublist(0, 4));
      final size = hdrData.getUint64(4, Endian.little);
      if (size < 0) break;
      if (id == 'fmt ' && pos + 52 <= fileLength) {
        await raf.setPosition(pos);
        final fmt = await raf.read(52);
        if (fmt.length >= 52) {
          final data = ByteData.sublistView(fmt);
          channels = data.getUint32(24, Endian.little);
          sampleRate = data.getUint32(28, Endian.little);
          bitsPerSample = data.getUint32(32, Endian.little);
          sampleCount = data.getUint64(36, Endian.little);
          blockSize = data.getUint32(44, Endian.little);
        }
      } else if (id == 'data') {
        dataOffset = pos + 12;
        dataSize = size - 12;
        break;
      }
      if (size <= 0 || pos + size <= pos) break;
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

  static Future<NativeDsdFileSource> _parseDff(
      RandomAccessFile raf, int fileLength) async {
    if (fileLength < 32) {
      throw const FormatException('Not a valid DFF file');
    }
    await raf.setPosition(0);
    final magic = await raf.read(4);
    if (magic.length < 4 || String.fromCharCodes(magic) != 'FRM8') {
      throw const FormatException('Not a valid DFF file');
    }
    var pos = 16;
    var dsdRate = 64;
    var channels = 2;
    var dataOffset = -1;
    var dataSize = -1;
    while (pos + 12 <= fileLength) {
      await raf.setPosition(pos);
      final hdr = await raf.read(12);
      if (hdr.length < 12) break;
      final hdrData = ByteData.sublistView(hdr);
      final id = String.fromCharCodes(hdr.sublist(0, 4));
      final size = hdrData.getUint64(4, Endian.big);
      if (size < 0) break;
      if (id == 'PROP') {
        final end = math.min(pos + 12 + size, fileLength);
        var sub = pos + 16;
        while (sub + 12 <= end) {
          await raf.setPosition(sub);
          final subHdr = await raf.read(12);
          if (subHdr.length < 12) break;
          final subData = ByteData.sublistView(subHdr);
          final subId = String.fromCharCodes(subHdr.sublist(0, 4));
          final subSize = subData.getUint64(4, Endian.big);
          if (subSize < 0) break;
          if (subId == 'FS  ' && subSize >= 4 && sub + 16 <= end) {
            await raf.setPosition(sub + 12);
            final fs = await raf.read(4);
            if (fs.length == 4) {
              dsdRate = ByteData.sublistView(fs).getUint32(0, Endian.big) ~/ 44100;
            }
          } else if (subId == 'CHNL' && subSize >= 2 && sub + 14 <= end) {
            await raf.setPosition(sub + 12);
            final ch = await raf.read(2);
            if (ch.length == 2) {
              channels = ByteData.sublistView(ch).getUint16(0, Endian.big);
            }
          } else if (subId == 'CMPR' && subSize >= 4 && sub + 16 <= end) {
            await raf.setPosition(sub + 12);
            final cmpr = await raf.read(4);
            if (cmpr.length == 4) {
              final type = String.fromCharCodes(cmpr);
              if (type != 'DSD ') {
                throw DsdUnsupportedException(
                    'Compressed DFF ($type) is not supported');
              }
            }
          }
          final nextSub = sub + 12 + subSize + (subSize & 1);
          if (nextSub <= sub) break;
          sub = nextSub;
        }
      } else if (id == 'FS  ') {
        if (size >= 4 && pos + 16 <= fileLength) {
          await raf.setPosition(pos + 12);
          final fs = await raf.read(4);
          if (fs.length == 4) {
            dsdRate = ByteData.sublistView(fs).getUint32(0, Endian.big) ~/ 44100;
          }
        }
      } else if (id == 'DSD ') {
        dataOffset = pos + 12;
        dataSize = size;
        break;
      }
      final nextPos = pos + 12 + size + (size & 1);
      if (nextPos <= pos) break;
      pos = nextPos;
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

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final task = _opChain.then((_) => fn());
    _opChain = task.then<void>((_) {}, onError: (_, __) {});
    return task;
  }

  void seek(int byteOffset) {
    _seekGeneration++;
    _position = byteOffset.clamp(0, totalBytes);
  }

  Future<NativeDsdChunk?> readChunk(int maxBytes) {
    if (_closed) return Future<NativeDsdChunk?>.value(null);
    return _serialized(() => _readChunkUnlocked(maxBytes));
  }

  Future<NativeDsdChunk?> _readChunkUnlocked(int maxBytes) async {
    if (_closed || maxBytes <= 0 || _position >= totalBytes) return null;
    final startGen = _seekGeneration;
    final want = math.min(maxBytes, totalBytes - _position);
    if (isDsf) return _readDsfChunk(want, startGen);
    return _readDffChunk(want, startGen);
  }

  Future<NativeDsdChunk?> _readDsfChunk(int want, int startGen) async {
    final leftOut = Uint8List(want);
    final rightOut = Uint8List(want);
    var written = 0;
    var perChannelPos = _position;
    while (written < want) {
      if (_seekGeneration != startGen) return null;
      final blockIndex = perChannelPos ~/ blockSize;
      final within = perChannelPos % blockSize;
      final inBlock = math.min(blockSize - within, want - written);
      final leftOffset =
          dataOffset + blockIndex * blockSize * channels + within;
      final left = await _readAt(leftOffset, inBlock);
      if (_seekGeneration != startGen) return null;
      if (left.length < inBlock) {
        if (left.isEmpty && written == 0) return null;
        if (left.isNotEmpty) {
          leftOut.setRange(written, written + left.length, left);
        }
        leftOut.fillRange(written + left.length, written + inBlock, 0x69);
        if (channels == 2) {
          final right = await _readAt(leftOffset + blockSize, inBlock);
          if (_seekGeneration != startGen) return null;
          final copyR = math.min(right.length, inBlock);
          if (copyR > 0) {
            rightOut.setRange(written, written + copyR, right);
          }
          if (copyR < inBlock) {
            rightOut.fillRange(written + copyR, written + inBlock, 0x69);
          }
        } else {
          rightOut.setRange(written, written + inBlock, leftOut, written);
        }
        written += inBlock;
        perChannelPos = math.min(totalBytes, perChannelPos + inBlock);
        break;
      }
      leftOut.setRange(written, written + inBlock, left);
      if (channels == 2) {
        final right = await _readAt(leftOffset + blockSize, inBlock);
        if (_seekGeneration != startGen) return null;
        final copyR = math.min(right.length, inBlock);
        if (copyR > 0) {
          rightOut.setRange(written, written + copyR, right);
        }
        if (copyR < inBlock) {
          // Pad short final right-channel block with DSD silence (0x69).
          rightOut.fillRange(written + copyR, written + inBlock, 0x69);
          written += inBlock;
          perChannelPos = math.min(totalBytes, perChannelPos + inBlock);
          break;
        }
      } else {
        rightOut.setRange(written, written + inBlock, left);
      }
      written += inBlock;
      perChannelPos += inBlock;
    }
    if (_seekGeneration != startGen) return null;
    if (written == 0) return null;
    _position = perChannelPos;
    if (written == want) {
      return NativeDsdChunk(leftOut, rightOut);
    }
    return NativeDsdChunk(
      Uint8List.sublistView(leftOut, 0, written),
      Uint8List.sublistView(rightOut, 0, written),
    );
  }

  Future<NativeDsdChunk?> _readDffChunk(int want, int startGen) async {
    final frames = want;
    final fileOffset = dataOffset + _position * channels;
    final raw = await _readAt(fileOffset, frames * channels);
    if (_seekGeneration != startGen) return null;
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

  Future<void> close() {
    if (_closed) return _opChain;
    _closed = true;
    return _serialized(() => _file.close());
  }
}
