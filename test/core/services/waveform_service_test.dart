// test/core/services/waveform_service_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/waveform_service.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _waveformChannel = MethodChannel('com.pulsr.music/waveform');

String _fnv(String s) {
  int hash = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late int decodeCalls;

  final service = WaveformService.instance;

  setUpAll(() {
    tempRoot = Directory.systemTemp.createTempSync('waveform_test');
  });

  tearDownAll(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    decodeCalls = 0;
    service.clearMemoryCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      return tempRoot.path;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_waveformChannel, (call) async {
      if (call.method == 'decode') {
        decodeCalls++;
        final count = call.arguments['count'] as int;
        return List<Object?>.generate(count, (i) => (i + 1) / count);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_waveformChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  File diskFileFor(String path, int count) {
    final file = File(path);
    final stat = file.statSync();
    return File(
        '${tempRoot.path}/waveforms/${_fnv(path)}_${stat.modified.millisecondsSinceEpoch}_${stat.size}_$count.json');
  }

  group('getInstantWaveform', () {
    test('returns a deterministic normalized waveform immediately', () {
      final first = service.getInstantWaveform(songId: 9001);
      final second = service.getInstantWaveform(songId: 9001);

      expect(first.length, 60);
      expect(
          first,
          everyElement(
              allOf(greaterThanOrEqualTo(0.05), lessThanOrEqualTo(1.0))));
      expect(second, equals(first));
      expect(decodeCalls, 0,
          reason: 'the instant path must never touch native');
    });

    test('respects the requested bar count', () {
      expect(service.getInstantWaveform(songId: 9002, count: 12).length, 12);
    });

    test('different songs produce different waveforms', () {
      final a = service.getInstantWaveform(songId: 9003);
      final b = service.getInstantWaveform(songId: 9004);
      expect(a, isNot(equals(b)));
    });

    test('the memory key is per-song and per-count, ignoring the file path',
        () {
      final withPath =
          service.getInstantWaveform(songId: 9005, filePath: '/music/a.mp3');
      final withoutPath = service.getInstantWaveform(songId: 9005);
      // Same song id + count is the cache identity; the first computed entry
      // (seeded by the path) is served for the path-less request too.
      expect(identical(withPath, withoutPath), isTrue);
    });

    test('serves a cached list on repeat calls and refreshes LRU position', () {
      final first = service.getInstantWaveform(songId: 9006);
      final second = service.getInstantWaveform(songId: 9006);
      expect(identical(first, second), isTrue);
    });

    test('evicts the oldest entry once the memory cache is full', () {
      final first = service.getInstantWaveform(songId: 100000);
      for (var i = 1; i < 101; i++) {
        service.getInstantWaveform(songId: 100000 + i);
      }
      // The entry for song 100000 was evicted, so it must be regenerated as a
      // new list instance rather than served from the cache.
      final regenerated = service.getInstantWaveform(songId: 100000);
      expect(identical(first, regenerated), isFalse);
      expect(regenerated, equals(first));
    });
  });

  group('getWaveform', () {
    test('remote https paths use the synthetic generator', () async {
      final samples = await service.getWaveform(
        songId: 9100,
        filePath: 'https://example.com/stream.m4a',
      );
      expect(samples.length, 60);
      expect(decodeCalls, 0);
    });

    test('ytmusic:// sentinels use the synthetic generator', () async {
      final samples = await service.getWaveform(
        songId: 9101,
        filePath: 'ytmusic://dQw4w9WgXcQ',
      );
      expect(samples.length, 60);
      expect(decodeCalls, 0);
    });

    test('a null path uses the synthetic generator', () async {
      final samples = await service.getWaveform(songId: 9102);
      expect(samples.length, 60);
      expect(decodeCalls, 0);
    });

    test('a local file is decoded natively and written to the disk cache',
        () async {
      final audio = File('${tempRoot.path}/native_song.bin')
        ..writeAsBytesSync(List<int>.filled(4096, 3));

      final first = await service.getWaveform(
        songId: 9103,
        filePath: audio.path,
        count: 32,
      );

      expect(first.length, 32);
      expect(decodeCalls, 1);

      final cacheFile = diskFileFor(audio.path, 32);
      expect(cacheFile.existsSync(), isTrue);
      final onDisk = jsonDecode(cacheFile.readAsStringSync()) as List;
      expect(onDisk.length, 32);
    });

    test('a second call is served from cache without re-decoding', () async {
      final audio = File('${tempRoot.path}/cached_song.bin')
        ..writeAsBytesSync(List<int>.filled(2048, 7));

      await service.getWaveform(songId: 9104, filePath: audio.path, count: 16);
      expect(decodeCalls, 1);

      final again = await service.getWaveform(
          songId: 9104, filePath: audio.path, count: 16);
      expect(again.length, 16);
      expect(decodeCalls, 1,
          reason: 'memory cache should absorb the second call');
    });

    test('a memory clear falls back to the persisted disk cache', () async {
      final audio = File('${tempRoot.path}/disk_song.bin')
        ..writeAsBytesSync(List<int>.filled(3000, 1));

      final original = await service.getWaveform(
          songId: 9105, filePath: audio.path, count: 24);
      expect(decodeCalls, 1);

      service.clearMemoryCache();
      final restored = await service.getWaveform(
          songId: 9105, filePath: audio.path, count: 24);

      expect(decodeCalls, 1, reason: 'disk cache should be reused');
      expect(restored, equals(original));
    });

    test('a corrupt disk entry is ignored and re-decoded', () async {
      final audio = File('${tempRoot.path}/corrupt_song.bin')
        ..writeAsBytesSync(List<int>.filled(2500, 9));

      await service.getWaveform(songId: 9106, filePath: audio.path, count: 20);
      expect(decodeCalls, 1);

      diskFileFor(audio.path, 20).writeAsStringSync('{not valid json');
      service.clearMemoryCache();

      final restored = await service.getWaveform(
          songId: 9106, filePath: audio.path, count: 20);
      expect(decodeCalls, 2);
      expect(restored.length, 20);
    });

    test('a disk entry with the wrong length is re-decoded', () async {
      final audio = File('${tempRoot.path}/wronglen_song.bin')
        ..writeAsBytesSync(List<int>.filled(2600, 4));

      await service.getWaveform(songId: 9107, filePath: audio.path, count: 20);
      diskFileFor(audio.path, 20).writeAsStringSync(jsonEncode([1.0, 2.0]));
      service.clearMemoryCache();

      final restored = await service.getWaveform(
          songId: 9107, filePath: audio.path, count: 20);
      expect(decodeCalls, 2);
      expect(restored.length, 20);
    });

    test('a PlatformException from the decoder falls back to synthetic',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_waveformChannel, (call) async {
        throw PlatformException(code: 'DECODE_FAILED');
      });
      final audio = File('${tempRoot.path}/broken_codec.bin')
        ..writeAsBytesSync(List<int>.filled(1800, 1));

      final samples = await service.getWaveform(
          songId: 9108, filePath: audio.path, count: 15);

      expect(samples.length, 15);
      expect(samples, everyElement(greaterThanOrEqualTo(0.05)));
    });

    test('a MissingPluginException falls back to synthetic', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_waveformChannel, (call) async {
        throw MissingPluginException();
      });
      final audio = File('${tempRoot.path}/no_plugin.bin')
        ..writeAsBytesSync(List<int>.filled(1800, 2));

      final samples = await service.getWaveform(
          songId: 9109, filePath: audio.path, count: 15);

      expect(samples.length, 15);
    });

    test('content:// paths use the content-keyed disk cache', () async {
      const path = 'content://media/external/audio/media/1234';

      final first =
          await service.getWaveform(songId: 9110, filePath: path, count: 18);
      expect(first.length, 18);
      expect(decodeCalls, 1);

      final cacheFile =
          File('${tempRoot.path}/waveforms/content_${_fnv(path)}_18.json');
      expect(cacheFile.existsSync(), isTrue);

      service.clearMemoryCache();
      await service.getWaveform(songId: 9110, filePath: path, count: 18);
      expect(decodeCalls, 1, reason: 'second read should hit the disk cache');
    });

    test('a file:// URI is decoded through its filesystem path', () async {
      final audio = File('${tempRoot.path}/uri_song.bin')
        ..writeAsBytesSync(List<int>.filled(2200, 5));
      final uri = Uri.file(audio.path).toString();

      final samples =
          await service.getWaveform(songId: 9111, filePath: uri, count: 10);

      expect(samples.length, 10);
      expect(decodeCalls, 1);
      final entries = Directory('${tempRoot.path}/waveforms')
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('${_fnv(uri)}_'));
      expect(entries, isNotEmpty);
    });

    test('re-tagging a file prunes the stale cache entry', () async {
      final audio = File('${tempRoot.path}/retagged.bin')
        ..writeAsBytesSync(List<int>.filled(2000, 6));

      await service.getWaveform(songId: 9112, filePath: audio.path, count: 22);
      final stale = diskFileFor(audio.path, 22);
      expect(stale.existsSync(), isTrue);

      // Append bytes so size (and therefore the cache key) changes.
      audio.writeAsBytesSync(List<int>.filled(4000, 6), mode: FileMode.append);
      service.clearMemoryCache();

      await service.getWaveform(songId: 9112, filePath: audio.path, count: 22);

      expect(stale.existsSync(), isFalse,
          reason: 'the old mtime/size entry should have been pruned');
      expect(diskFileFor(audio.path, 22).existsSync(), isTrue);
    });

    test('a non-existent local file still yields a waveform', () async {
      final samples = await service.getWaveform(
        songId: 9113,
        filePath: '${tempRoot.path}/does_not_exist.wav',
        count: 14,
      );
      expect(samples.length, 14);
    });

    test('empty native output falls back to the synthetic generator', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_waveformChannel, (call) async {
        decodeCalls++;
        return <Object?>[];
      });
      final audio = File('${tempRoot.path}/empty_decode.bin')
        ..writeAsBytesSync(List<int>.filled(1500, 1));

      final samples = await service.getWaveform(
          songId: 9114, filePath: audio.path, count: 12);

      expect(samples.length, 12);
      expect(samples, everyElement(greaterThanOrEqualTo(0.05)));
    });

    test('clearMemoryCache forces a rebuild of instant waveforms', () {
      final first = service.getInstantWaveform(songId: 9200);
      service.clearMemoryCache();
      final rebuilt = service.getInstantWaveform(songId: 9200);
      expect(rebuilt, equals(first));
    });
  });
}
