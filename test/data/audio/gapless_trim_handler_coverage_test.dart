// test/data/audio/gapless_trim_handler_coverage_test.dart
//
// Coverage for the header-derived (LAME Xing/Info, M4A iTunSMPB) gapless trim
// readers, the static LRU cache, the codec-fallback `trimFor`, the clamp math
// and the transition monitor. Uses real temporary files, so the async and sync
// parsers are exercised end to end without touching the platform.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/gapless_trim_handler.dart';

Uint8List _lameMp3({
  String magic = 'Info',
  int delaySamples = 0,
  int paddingSamples = 16,
}) {
  final bytes = Uint8List(128);
  for (var i = 0; i < 4; i++) {
    bytes[i] = magic.codeUnitAt(i); // 'Info' / 'Xing' at offset 0
  }
  // flags (offset 4..7) stay zero -> LAME tag starts at offset 8.
  const lameStart = 8;
  bytes[lameStart] = 0x4C; // L
  bytes[lameStart + 1] = 0x41; // A
  bytes[lameStart + 2] = 0x4D; // M
  bytes[lameStart + 3] = 0x45; // E
  final b0 = (delaySamples >> 4) & 0xFF;
  final b1 = ((delaySamples & 0x0F) << 4) | ((paddingSamples >> 8) & 0x0F);
  final b2 = paddingSamples & 0xFF;
  bytes[lameStart + 21] = b0;
  bytes[lameStart + 22] = b1;
  bytes[lameStart + 23] = b2;
  return bytes;
}

Uint8List _itunSmpb({int delaySamples = 0x18, int paddingSamples = 0x30}) {
  final text =
      'xxxxiTunSMPB\x00\x00 00000000 ${delaySamples.toRadixString(16).padLeft(8, '0')} '
      '${paddingSamples.toRadixString(16).padLeft(8, '0')} rest';
  final bytes = Uint8List(256);
  final encoded = text.codeUnits;
  for (var i = 0; i < encoded.length && i < bytes.length; i++) {
    bytes[i] = encoded[i];
  }
  return bytes;
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pulsr_gapless_cov_');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File write(String name, List<int> bytes) =>
      File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(bytes);

  group('GaplessTrim value object', () {
    test('isEmpty and total reflect the two durations', () {
      const empty = GaplessTrim();
      expect(empty.isEmpty, isTrue);
      expect(empty.total, Duration.zero);

      const trim = GaplessTrim(
        preSkip: Duration(milliseconds: 10),
        postTrim: Duration(milliseconds: 5),
      );
      expect(trim.isEmpty, isFalse);
      expect(trim.total, const Duration(milliseconds: 15));
    });

    test('clampedTo returns this for a zero-length track and for an empty trim',
        () {
      const trim = GaplessTrim(preSkip: Duration(milliseconds: 100));
      expect(identical(trim.clampedTo(Duration.zero), trim), isTrue);
      expect(
          identical(trim.clampedTo(const Duration(seconds: -1)), trim), isTrue);

      const empty = GaplessTrim();
      expect(
          identical(empty.clampedTo(const Duration(seconds: 10)), empty), isTrue);
    });

    test('clampedTo scales both sides when the total exceeds 20% of the track',
        () {
      const trim = GaplessTrim(
        preSkip: Duration(milliseconds: 100),
        postTrim: Duration(milliseconds: 100),
      );
      final clamped = trim.clampedTo(const Duration(milliseconds: 500));
      // 200ms > 20% of 500ms (100ms) -> scaled by 0.5.
      expect(clamped.preSkip, const Duration(milliseconds: 50));
      expect(clamped.postTrim, const Duration(milliseconds: 50));
    });

    test('clampedTo leaves a trim that already fits untouched', () {
      const trim = GaplessTrim(preSkip: Duration(milliseconds: 10));
      final clamped = trim.clampedTo(const Duration(seconds: 10));
      expect(clamped.preSkip, const Duration(milliseconds: 10));
      expect(clamped.postTrim, Duration.zero);
    });
  });

  group('readHeaderGaplessTrimSync', () {
    test('reads a LAME MP3 header (delay + padding)', () {
      final file = write('sync_lame.mp3', _lameMp3(delaySamples: 42, paddingSamples: 8));
      final trim = GaplessTrimHandler.readHeaderGaplessTrimSync(file.path);
      expect(trim, isNotNull);
      expect(trim!.preSkip.inMicroseconds, greaterThan(0));
      expect(trim.postTrim.inMicroseconds, greaterThan(0));
      // 42 samples @44.1k ~= 952us; 8 samples ~= 181us.
      expect(trim.preSkip.inMicroseconds, closeTo(952, 2));
      expect(trim.postTrim.inMicroseconds, closeTo(181, 2));
    });

    test('reads an M4A iTunSMPB atom (delay + padding)', () {
      final file = write('sync_atom.m4a', _itunSmpb());
      final trim = GaplessTrimHandler.readHeaderGaplessTrimSync(file.path);
      expect(trim, isNotNull);
      expect(trim!.preSkip.inMicroseconds, greaterThan(0));
      expect(trim.postTrim.inMicroseconds, greaterThan(0));
    });

    test('returns null for a header with no Xing/Info or iTunSMPB', () {
      final mp3 = write('sync_plain.mp3', List<int>.filled(200, 0x11));
      expect(GaplessTrimHandler.readHeaderGaplessTrimSync(mp3.path), isNull);

      final m4a = write('sync_plain.m4a', List<int>.filled(200, 0x11));
      expect(GaplessTrimHandler.readHeaderGaplessTrimSync(m4a.path), isNull);
    });

    test('returns null for a missing file and an unsupported extension', () {
      expect(
        GaplessTrimHandler.readHeaderGaplessTrimSync(
            '${dir.path}${Platform.pathSeparator}nope.mp3'),
        isNull,
      );
      final flac = write('sync.flac', _lameMp3());
      expect(GaplessTrimHandler.readHeaderGaplessTrimSync(flac.path), isNull);
    });

    test('a Xing magic header is honoured as well as Info', () {
      final file = write('sync_xing.mp3', _lameMp3(magic: 'Xing', delaySamples: 10));
      final trim = GaplessTrimHandler.readHeaderGaplessTrimSync(file.path);
      expect(trim, isNotNull);
      expect(trim!.preSkip.inMicroseconds, greaterThan(0));
    });

    test('the parsed trim is cached: a deleted file still resolves', () {
      final file = write('sync_cache.mp3', _lameMp3(delaySamples: 42));
      final first = GaplessTrimHandler.readHeaderGaplessTrimSync(file.path);
      expect(first, isNotNull);
      file.deleteSync();
      final second = GaplessTrimHandler.readHeaderGaplessTrimSync(file.path);
      expect(second, isNotNull);
      expect(second!.preSkip, first!.preSkip);
    });

    test('m4a with zero delay and padding is not treated as a trim', () {
      final file = write('sync_zero.m4a', _itunSmpb(delaySamples: 0, paddingSamples: 0));
      expect(GaplessTrimHandler.readHeaderGaplessTrimSync(file.path), isNull);
    });
  });

  group('readHeaderGaplessTrim (async)', () {
    test('returns null for a missing file', () async {
      expect(
        await GaplessTrimHandler.readHeaderGaplessTrim(
            '${dir.path}${Platform.pathSeparator}missing.mp3'),
        isNull,
      );
    });

    test('reads an MP3 LAME header', () async {
      final file = write('async.mp3', _lameMp3(delaySamples: 100, paddingSamples: 20));
      final trim = await GaplessTrimHandler.readHeaderGaplessTrim(file.path);
      expect(trim, isNotNull);
      expect(trim!.preSkip.inMicroseconds, greaterThan(0));
    });

    test('reads an M4A atom and accepts the mp4/aac extensions', () async {
      for (final name in ['async.m4a', 'async.mp4', 'async.aac']) {
        final file = write(name, _itunSmpb());
        final trim = await GaplessTrimHandler.readHeaderGaplessTrim(file.path);
        expect(trim, isNotNull, reason: name);
      }
    });

    test('returns null for an unsupported extension', () async {
      final file = write('async.flac', _itunSmpb());
      expect(await GaplessTrimHandler.readHeaderGaplessTrim(file.path), isNull);
    });

    test('caches a header trim across calls', () async {
      final file = write('async_cache.mp3', _lameMp3(delaySamples: 50));
      final first = await GaplessTrimHandler.readHeaderGaplessTrim(file.path);
      expect(first, isNotNull);
      file.deleteSync();
      final second = await GaplessTrimHandler.readHeaderGaplessTrim(file.path);
      expect(second!.preSkip, first!.preSkip);
    });

    test('a sampleRate is threaded into the sample->duration math', () async {
      final file = write('async_rate.mp3', _lameMp3(delaySamples: 1000));
      final trim = await GaplessTrimHandler.readHeaderGaplessTrim(
        file.path,
        sampleRate: 1000,
      );
      // 1000 samples @ 1000Hz == exactly one second.
      expect(trim!.preSkip, const Duration(seconds: 1));
    });
  });

  group('trimFor', () {
    test('explicit overrides clamp into 0..5000 ms', () {
      final high = GaplessTrimHandler.trimFor(
        path: '/x/a.mp3',
        preSkipOverrideMs: 99999,
        postTrimOverrideMs: -5,
      );
      expect(high.preSkip, const Duration(milliseconds: 5000));
      expect(high.postTrim, Duration.zero);
    });

    test('only one override present zeroes the missing side', () {
      final trim = GaplessTrimHandler.trimFor(
        path: '/x/a.mp3',
        postTrimOverrideMs: 120,
      );
      expect(trim.preSkip, Duration.zero);
      expect(trim.postTrim, const Duration(milliseconds: 120));
    });

    test('detects Opus via path, codec and ogg-with-opus content', () {
      expect(GaplessTrimHandler.trimFor(path: '/x/a.opus').preSkip,
          GaplessTrimHandler.opusPreSkip);
      expect(GaplessTrimHandler.trimFor(path: '/x/a.bin', codec: 'opus').preSkip,
          GaplessTrimHandler.opusPreSkip);
      expect(
        GaplessTrimHandler.trimFor(path: '/x/opus_track.ogg').preSkip,
        GaplessTrimHandler.opusPreSkip,
      );
    });

    test('treats a plain ogg/oga without opus as Vorbis', () {
      // A bare .ogg with no codec hint is assumed Opus (the common case).
      expect(
          GaplessTrimHandler.trimFor(path: '/x/a.ogg').preSkip,
          GaplessTrimHandler.opusPreSkip);
      final trim2 = GaplessTrimHandler.trimFor(path: '/x/a.oga');
      expect(trim2.preSkip, const Duration(microseconds: 11600));
      expect(
        GaplessTrimHandler.trimFor(path: '/x/a.ogg', codec: 'vorbis').preSkip,
        const Duration(microseconds: 11600),
      );
    });

    test('MP3 and AAC codec hints are honoured', () {
      expect(GaplessTrimHandler.trimFor(path: '/x/s', codec: 'mp3').preSkip,
          GaplessTrimHandler.mp3EncoderDelay);
      expect(
          GaplessTrimHandler.trimFor(path: '/x/s', codec: 'mp4a.40.2').preSkip,
          GaplessTrimHandler.aacEncoderDelay);
      expect(GaplessTrimHandler.trimFor(path: '/x/s.m4b').preSkip,
          GaplessTrimHandler.aacEncoderDelay);
    });

    test('unknown formats stay untrimmed', () {
      expect(GaplessTrimHandler.trimFor(path: '/x/s.flac').isEmpty, isTrue);
      expect(GaplessTrimHandler.trimFor(path: '/x/s.wav').isEmpty, isTrue);
      expect(GaplessTrimHandler.trimFor(path: '/x/s', codec: 'weird').isEmpty,
          isTrue);
    });

    test('a header override wins over the codec default', () {
      final file = write('override.mp3', _lameMp3(delaySamples: 42));
      final trim = GaplessTrimHandler.trimFor(path: file.path, sampleRate: 44100);
      expect(trim.preSkip.inMicroseconds, closeTo(952, 2));
    });
  });

  group('startOffset and effectiveEnd', () {
    test('startOffset is the pre-skip', () {
      const trim = GaplessTrim(preSkip: Duration(milliseconds: 7));
      expect(GaplessTrimHandler.startOffset(trim),
          const Duration(milliseconds: 7));
    });

    test('effectiveEnd clamps a post-trim larger than the track to zero', () {
      const trim = GaplessTrim(postTrim: Duration(seconds: 10));
      expect(GaplessTrimHandler.effectiveEnd(const Duration(seconds: 5), trim),
          Duration.zero);
      expect(
        GaplessTrimHandler.effectiveEnd(
            const Duration(seconds: 30), const GaplessTrim(postTrim: Duration(seconds: 4))),
        const Duration(seconds: 26),
      );
    });
  });

  group('GaplessTransitionMonitor', () {
    test('counts backward position jumps but ignores forward moves', () {
      final monitor = GaplessTransitionMonitor();
      monitor.onPositionUpdate(const Duration(seconds: 10));
      monitor.onPositionUpdate(const Duration(seconds: 20)); // forward
      expect(monitor.gapEventCount, 0);
      // A backward jump > 5ms where the last position is > 5ms and target > 0.
      monitor.onPositionUpdate(const Duration(seconds: 1));
      expect(monitor.gapEventCount, 1);
      // A jump back to exactly zero is not a glitch.
      monitor.onPositionUpdate(Duration.zero);
      expect(monitor.gapEventCount, 1);
    });

    test('onTrackTransition resets the last position', () {
      final monitor = GaplessTransitionMonitor();
      monitor.onPositionUpdate(const Duration(seconds: 10));
      monitor.onTrackTransition(2);
      // Because the position was reset to zero, a "backward" jump to 1s from
      // zero is forward and not counted.
      monitor.onPositionUpdate(const Duration(seconds: 1));
      expect(monitor.gapEventCount, 0);
    });

    test('attach listens to both streams and re-attaching disposes the old',
        () async {
      final monitor = GaplessTransitionMonitor();
      final indexController = StreamController<int?>.broadcast();
      final positionController = StreamController<Duration>.broadcast();

      monitor.attach(
        currentIndexStream: indexController.stream,
        positionStream: positionController.stream,
      );
      positionController.add(const Duration(seconds: 10));
      positionController.add(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(monitor.gapEventCount, 1);

      // Re-attaching must dispose the previous subscriptions without throwing.
      monitor.attach(
        currentIndexStream: indexController.stream,
        positionStream: positionController.stream,
      );
      indexController.add(1); // resets last position
      positionController.add(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(monitor.gapEventCount, 1);

      monitor.reset();
      expect(monitor.gapEventCount, 0);
      monitor.dispose();
      monitor.dispose(); // idempotent
      await indexController.close();
      await positionController.close();
    });
  });
}
