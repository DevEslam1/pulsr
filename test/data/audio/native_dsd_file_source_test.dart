// test/data/audio/native_dsd_file_source_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/native_dsd_file_source.dart';

Uint8List _dsfFixture({int blockSize = 4, int blocks = 2}) {
  final payloadLength = blockSize * 2 * blocks;
  final total = 28 + 52 + 12 + payloadLength;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'DSD ');
  data.setUint64(4, 28, Endian.little);
  data.setUint64(12, total, Endian.little);
  data.setUint64(20, 0, Endian.little);

  const fmt = 28;
  ascii(fmt, 'fmt ');
  data.setUint64(fmt + 4, 52, Endian.little);
  data.setUint32(fmt + 12, 1, Endian.little);
  data.setUint32(fmt + 16, 0, Endian.little);
  data.setUint32(fmt + 20, 2, Endian.little);
  data.setUint32(fmt + 24, 2, Endian.little);
  data.setUint32(fmt + 28, 2822400, Endian.little);
  data.setUint32(fmt + 32, 1, Endian.little);
  data.setUint64(fmt + 36, blockSize * 8 * blocks, Endian.little);
  data.setUint32(fmt + 44, blockSize, Endian.little);
  data.setUint32(fmt + 48, 0, Endian.little);

  final dataChunk = fmt + 52;
  ascii(dataChunk, 'data');
  data.setUint64(dataChunk + 4, 12 + payloadLength, Endian.little);
  for (var i = 0; i < payloadLength; i++) {
    bytes[dataChunk + 12 + i] = (i ~/ blockSize).isEven ? 0x69 : 0x96;
  }
  return bytes;
}

Uint8List _dffFixture({int frames = 4}) {
  // 2 channels, byte-interleaved payload.
  final payloadLength = frames * 2;
  final propSize = 4 + 16 + 22; // 'SND ' + FS + CHNL
  final total = 16 + 12 + propSize + 12 + payloadLength;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'FRM8');
  data.setUint64(4, total - 12, Endian.big);
  ascii(12, 'DSD ');

  var pos = 16;
  ascii(pos, 'PROP');
  data.setUint64(pos + 4, propSize, Endian.big);
  ascii(pos + 12, 'SND ');
  var sub = pos + 16;
  ascii(sub, 'FS  ');
  data.setUint64(sub + 4, 4, Endian.big);
  data.setUint32(sub + 12, 2822400, Endian.big);
  sub += 16;
  ascii(sub, 'CHNL');
  data.setUint64(sub + 4, 10, Endian.big);
  data.setUint16(sub + 12, 2, Endian.big);
  ascii(sub + 14, 'SLFT');
  ascii(sub + 18, 'SRGT');
  pos += 12 + propSize;

  ascii(pos, 'DSD ');
  data.setUint64(pos + 4, payloadLength, Endian.big);
  final audio = pos + 12;
  for (var i = 0; i < frames; i++) {
    bytes[audio + i * 2] = 0x69;
    bytes[audio + i * 2 + 1] = 0x96;
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_dsd_source_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('DSF source streams block-interleaved channels and seeks inside blocks',
      () async {
    final path = '${tempDir.path}${Platform.pathSeparator}track.dsf';
    await File(path).writeAsBytes(_dsfFixture(blockSize: 4, blocks: 2));
    final source = await NativeDsdFileSource.open(path);

    expect(source.isDsf, isTrue);
    expect(source.dsdRate, 64);
    expect(source.channels, 2);
    expect(source.msbFirst, isFalse);
    expect(source.totalBytes, 8);

    final first = await source.readChunk(4);
    expect(first, isNotNull);
    expect(first!.left.length, 4);
    expect(first.left[0], 0x69);
    expect(first.right.length, 4);
    expect(source.position, 4);

    source.seek(2);
    final crossBlock = await source.readChunk(4);
    expect(crossBlock, isNotNull);
    expect(crossBlock!.left.length, 4);
    expect(source.position, 6);

    final rest = await source.readChunk(4);
    expect(rest!.left.length, 2);
    expect(source.position, 8);
    expect(await source.readChunk(4), isNull);
    await source.close();
  });

  test('DFF source de-interleaves L/R and reports MSB-first', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}track.dff';
    await File(path).writeAsBytes(_dffFixture(frames: 4));
    final source = await NativeDsdFileSource.open(path);

    expect(source.isDsf, isFalse);
    expect(source.dsdRate, 64);
    expect(source.channels, 2);
    expect(source.msbFirst, isTrue);
    expect(source.totalBytes, 4);

    final chunk = await source.readChunk(4);
    expect(chunk, isNotNull);
    expect(chunk!.left, [0x69, 0x69, 0x69, 0x69]);
    expect(chunk.right, [0x96, 0x96, 0x96, 0x96]);
    expect(source.position, 4);
    expect(await source.readChunk(4), isNull);
    await source.close();
  });

  test('rejects a non-DSD extension and a malformed header', () async {
    final txt = '${tempDir.path}${Platform.pathSeparator}track.txt';
    await File(txt).writeAsString('nope');
    await expectLater(
      NativeDsdFileSource.open(txt),
      throwsA(isA<FormatException>()),
    );

    final bad = '${tempDir.path}${Platform.pathSeparator}bad.dsf';
    await File(bad).writeAsBytes(Uint8List.fromList(List.filled(80, 0)));
    await expectLater(
      NativeDsdFileSource.open(bad),
      throwsA(isA<FormatException>()),
    );
  });

  test('BUG-P1-4: readChunk after close returns null without throwing', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}closed.dsf';
    await File(path).writeAsBytes(_dsfFixture(blockSize: 4, blocks: 2));
    final source = await NativeDsdFileSource.open(path);
    await source.close();
    expect(source.isClosed, isTrue);
    expect(await source.readChunk(4), isNull);
  });
}
