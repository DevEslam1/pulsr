// test/core/telemetry/audio_session_log_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/telemetry/audio_session_log.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AudioSessionLog log;
  final fixedTime = DateTime.utc(2026, 9, 11, 12, 0, 0);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_session_log_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  AudioSessionLog buildLog({bool enabled = true, int maxSessions = 25}) =>
      AudioSessionLog(
        directoryProvider: () async => tempDir,
        enabledProvider: () async => enabled,
        maxSessions: maxSessions,
        clock: () => fixedTime,
      );

  group('record contents / shape', () {
    test('captures a single complete record per session', () async {
      log = buildLog();
      await log.startSession(
        trackId: '42',
        trackTitle: 'Test Track',
        routeType: AudioRouteType.bluetooth,
        bluetoothCodec: 'LDAC',
        sampleRate: 96000,
        bitDepth: 24,
        bitrateKbps: 990,
      );
      // Route change: bluetooth -> wired.
      await log.updateOutputInfo(
        routeType: AudioRouteType.wired,
        bluetoothCodec: null,
        sampleRate: 192000,
        bitDepth: 32,
      );
      await log.recordInterruption(AudioInterruptionKind.duck);
      await log.recordInterruption(AudioInterruptionKind.becomingNoisy);
      await log.recordUnderrun();
      await log.recordUnderrun();
      await log.recordDropout();
      await log.endSession();

      final records = await log.readAll();
      expect(records, hasLength(1));
      final r = records.single;
      expect(r.sessionId, isNotEmpty);
      expect(r.trackId, '42');
      expect(r.trackTitle, 'Test Track');
      expect(r.routeType, AudioRouteType.wired);
      expect(r.sampleRate, 192000);
      expect(r.bitDepth, 32);
      expect(r.bitrateKbps, 990);
      expect(r.routeChanges, hasLength(1));
      expect(r.routeChanges.single.from, AudioRouteType.bluetooth);
      expect(r.routeChanges.single.to, AudioRouteType.wired);
      expect(r.routeChanges.single.timestamp, isNotEmpty);
      expect(r.interruptions.map((e) => e.type), [
        AudioInterruptionKind.duck,
        AudioInterruptionKind.becomingNoisy,
      ]);
      expect(r.bufferUnderruns, 2);
      expect(r.dropouts, 1);
      expect(r.startedAt, isNotEmpty);
      expect(r.endedAt, isNotNull);

      // Persisted line is real JSON with the required keys.
      final file = File('${tempDir.path}/${AudioSessionLog.defaultFileName}');
      final line = (await file.readAsLines()).single;
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['sessionId'], r.sessionId);
      expect(decoded['routeChanges'], isA<List<dynamic>>());
      expect(decoded['interruptions'], isA<List<dynamic>>());
      expect(decoded['bufferUnderruns'], 2);
      expect(decoded['dropouts'], 1);
    });

    test('JSON round-trips without losing fields', () {
      final original = AudioSessionRecord(
        sessionId: 'sess_1',
        trackId: '7',
        trackTitle: 'Song',
        startedAt: '2026-09-11T12:00:00.000Z',
        routeType: AudioRouteType.wired,
        bluetoothCodec: 'aptX HD',
        sampleRate: 48000,
        bitDepth: 24,
        bitrateKbps: 320,
        routeChanges: const [
          AudioRouteChangeEvent(
            timestamp: '2026-09-11T12:01:00.000Z',
            from: AudioRouteType.speaker,
            to: AudioRouteType.wired,
          ),
        ],
        interruptions: const [
          AudioInterruptionEvent(
            timestamp: '2026-09-11T12:02:00.000Z',
            type: AudioInterruptionKind.pause,
          ),
        ],
        bufferUnderruns: 3,
        dropouts: 1,
        endedAt: '2026-09-11T12:03:00.000Z',
      );
      final restored =
          AudioSessionRecord.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(restored.sessionId, original.sessionId);
      expect(restored.routeType, AudioRouteType.wired);
      expect(restored.bitrateKbps, 320);
      expect(restored.routeChanges.single.to, AudioRouteType.wired);
      expect(restored.interruptions.single.type, AudioInterruptionKind.pause);
      expect(restored.bufferUnderruns, 3);
    });

    test('one record per session: starting a new session finalizes the old',
        () async {
      log = buildLog();
      await log.startSession(trackId: '1', trackTitle: 'One');
      await log.startSession(trackId: '2', trackTitle: 'Two');
      await log.endSession();

      final records = await log.readAll();
      expect(records, hasLength(2));
      expect(records.map((r) => r.trackId), ['1', '2']);
      expect(records.every((r) => r.endedAt != null), isTrue);
    });
  });

  group('ring bound', () {
    test('keeps only the newest maxSessions records', () async {
      log = buildLog(maxSessions: 3);
      for (var i = 0; i < 5; i++) {
        await log.startSession(trackId: '$i', trackTitle: 'Track $i');
      }
      await log.endSession();

      final records = await log.readAll();
      expect(records, hasLength(3));
      expect(records.map((r) => r.trackId), ['2', '3', '4']);
    });
  });

  group('disabled flag', () {
    test('is a complete no-op and writes nothing', () async {
      log = buildLog(enabled: false);
      await log.startSession(trackId: '1', trackTitle: 'Nope');
      expect(log.activeSessionId, isNull);
      await log.recordUnderrun();
      await log.recordDropout();
      await log.recordInterruption(AudioInterruptionKind.pause);
      await log.endSession();

      final file = File('${tempDir.path}/${AudioSessionLog.defaultFileName}');
      expect(await file.exists(), isFalse);
      expect(await log.readAll(), isEmpty);
    });
  });

  group('export', () {
    test('writes every record to a shareable JSONL file', () async {
      log = buildLog();
      await log.startSession(trackId: '1', trackTitle: 'One');
      await log.startSession(trackId: '2', trackTitle: 'Two');
      await log.endSession();

      final file = await log.exportToFile();
      expect(file, isNotNull);
      expect(await file!.exists(), isTrue);

      final lines = (await file.readAsString())
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(2));
      final exported = lines
          .map((l) => AudioSessionRecord.fromJson(
              jsonDecode(l) as Map<String, dynamic>))
          .toList();
      expect(exported.map((r) => r.trackId), ['1', '2']);
    });

    test('clear removes the persisted file', () async {
      log = buildLog();
      await log.startSession(trackId: '1', trackTitle: 'One');
      await log.endSession();
      expect(await File('${tempDir.path}/${AudioSessionLog.defaultFileName}')
          .exists(), isTrue);
      await log.clear();
      expect(await File('${tempDir.path}/${AudioSessionLog.defaultFileName}')
          .exists(), isFalse);
    });
  });

  group('route classification', () {
    test('maps output info to speaker / wired / bluetooth', () {
      expect(AudioSessionLog.routeTypeForInfo(null), AudioRouteType.speaker);
      expect(
        AudioSessionLog.routeTypeForInfo(const AudioOutputInfo(
          deviceName: 'Phone',
          isUsbDac: false,
          sampleRate: 48000,
          bitDepth: 16,
          isBitPerfectActive: false,
        )),
        AudioRouteType.speaker,
      );
      expect(
        AudioSessionLog.routeTypeForInfo(const AudioOutputInfo(
          deviceName: 'USB DAC',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: true,
          activeDeviceType: 'usb',
        )),
        AudioRouteType.wired,
      );
      expect(
        AudioSessionLog.routeTypeForInfo(const AudioOutputInfo(
          deviceName: 'LDAC Buds',
          isUsbDac: false,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: false,
          isBluetooth: true,
          btCodecName: 'LDAC',
        )),
        AudioRouteType.bluetooth,
      );
    });
  });
}
