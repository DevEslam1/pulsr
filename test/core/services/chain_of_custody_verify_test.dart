// test/core/services/chain_of_custody_verify_test.dart
//
// Covers the measurement flow end to end on the Dart side with the platform
// channel stubbed: what a certificate may claim when a window completes, and what
// it must admit when arming fails, when no window ever arrives, or when the file
// cannot be read. The rule under test is that absence of measurement is never a
// pass.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/services/chain_of_custody_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];

  /// Engine config report. [bitPerfectActive] is the observed bypass state the
  /// custody verdict requires alongside the window's own arming fact.
  Map<String, dynamic> baseEngineReport({bool bitPerfectActive = false}) => {
        'nativeEngineLoaded': true,
        'sampleRate': 48000.0,
        'bufferSize': 512,
        'activeStages': ['EQUALIZER', 'LIMITER'],
        'isBitPerfectActive': bitPerfectActive,
        'isBypassCompareActive': false,
        'rollingRtf': 0.08,
        'estimatedLatencyMs': 14.0,
        'thermalStatus': 1,
      };

  /// Installs a handler whose custody behaviour is chosen by the case.
  void stubChannel({
    bool armed = true,
    String armReason = 'ok',
    Map<String, dynamic>? window,
    Map<String, dynamic>? engineReport,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getChainOfCustodyReport':
          return engineReport ?? baseEngineReport();
        case 'armCustodyWindow':
          return {'armed': armed, 'reason': armed ? 'ok' : armReason};
        case 'collectCustodyWindow':
          if (window == null) {
            return {'available': false, 'reason': 'noWindowCaptured'};
          }
          return {'available': true, ...window};
        case 'cancelCustodyWindow':
          return true;
      }
      return null;
    });
  }

  Map<String, dynamic> bitExactWindow() => const {
        'frames': 2048,
        'channels': 2,
        'sampleRate': 48000.0,
        'windowMs': 42.67,
        'activeStages': 0,
        'snapshotGeneration': 12,
        'bitPerfectAtArm': true,
        'bypassCompareAtArm': false,
        'truncated': false,
        'inputSha256':
            '1111111111111111111111111111111111111111111111111111111111111111',
        'outputSha256':
            '1111111111111111111111111111111111111111111111111111111111111111',
      };

  Map<String, dynamic> modifiedWindow() => const {
        'frames': 2048,
        'channels': 2,
        'sampleRate': 48000.0,
        'windowMs': 42.67,
        'activeStages': 17,
        'snapshotGeneration': 13,
        'bitPerfectAtArm': false,
        'bypassCompareAtArm': false,
        'truncated': false,
        'inputSha256':
            '2222222222222222222222222222222222222222222222222222222222222222',
        'outputSha256':
            '3333333333333333333333333333333333333333333333333333333333333333',
      };

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('verifyChain', () {
    test('records a measured bit-exact verdict from the window digests',
        () async {
      // A bit-exact claim needs the engine to have observed the bypass: the
      // window's arming fact alone would let a preferred-but-unused mode pass.
      stubChannel(
        window: bitExactWindow(),
        engineReport: baseEngineReport(bitPerfectActive: true),
      );
      final service =
          ChainOfCustodyService(contentHasher: (path, size) async => 'a' * 64);

      final report = await service.verifyChain(
        trackId: 't1',
        trackTitle: 'Silent Chain',
        filePath: null,
        hashFile: false,
      );

      expect(report.verdict, CustodyVerdict.bitExactMeasured);
      expect(report.verificationBadge, contains('Bit-Exact Output'));
      expect(report.verificationBadge, contains('2048 frames'));
      expect(report.measurement!.bitPerfectAtArm, isTrue);
      expect(report.measurement!.windowMs, closeTo(42.67, 0.01));
      expect(report.limitations, isEmpty);
      // Engine facts still come from the config report alongside the measurement.
      expect(report.activeDspStages, ['EQUALIZER', 'LIMITER']);
      expect(report.outputSampleRate, 48000);
      expect(report.bufferSize, 512);
    });

    test(
        'identical digests on a chain not observed bit-perfect stay unverified',
        () async {
      stubChannel(
        window: {
          ...bitExactWindow(),
          'bitPerfectAtArm': false,
        },
        engineReport: baseEngineReport(bitPerfectActive: true),
      );
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't1b',
        trackTitle: 'Armed Too Early',
        hashFile: false,
      );

      // The bytes matched, but the path was not bit-perfect while the window
      // ran, so no bit-exactness claim was ever established.
      expect(report.measurement!.bitExactMeasured, isTrue);
      expect(report.measurement!.bitPerfectAtArm, isFalse);
      expect(report.verdict, CustodyVerdict.unverified);
      expect(report.verificationBadge, contains('Not Verified'));
      expect(report.verificationBadge, contains('not reported bit-perfect'));
      expect(report.verificationBadge, isNot(contains('Bit-Exact')));
    });

    test('a truncated window is not promoted to a bit-exact verdict', () async {
      stubChannel(
        window: {
          ...bitExactWindow(),
          'frames': 512,
          'truncated': true,
        },
        engineReport: baseEngineReport(bitPerfectActive: true),
      );
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't1c',
        trackTitle: 'Short Window',
        hashFile: false,
      );

      // The digests still describe exactly what was captured, so the verdict is
      // not "chain modified" - but a partial window certifies fewer frames than
      // requested and cannot carry the bit-exact wording.
      expect(report.measurement!.bitExactMeasured, isTrue);
      expect(report.measurement!.truncated, isTrue);
      expect(report.verdict, CustodyVerdict.unverified);
      expect(report.verificationBadge, contains('Not Verified'));
      expect(report.verificationBadge, contains('partial 512-frame window'));
      expect(report.verificationBadge, isNot(contains('Bit-Exact')));
    });

    test('a window whose halves differ cannot be reported as bit-exact',
        () async {
      stubChannel(window: modifiedWindow());
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't2',
        trackTitle: 'Loud Chain',
        hashFile: false,
      );

      expect(report.verdict, CustodyVerdict.chainModifiedMeasured);
      expect(report.verificationBadge, contains('Chain Modified Samples'));
      expect(report.verificationBadge, isNot(contains('Bit-Exact')));
    });

    test('arm failure is recorded and no window is polled', () async {
      stubChannel(armed: false, armReason: 'windowAlreadyPending');
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't3',
        trackTitle: 'Busy',
        hashFile: false,
        timeout: const Duration(milliseconds: 120),
      );

      expect(report.verdict, CustodyVerdict.unverified);
      expect(report.limitations,
          contains('captureArmFailed:windowAlreadyPending'));
      expect(calls.where((c) => c.method == 'collectCustodyWindow'), isEmpty);
    });

    test('a window that never fills is cancelled and reported unverified',
        () async {
      stubChannel(window: null);
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't4',
        trackTitle: 'Paused',
        hashFile: false,
        timeout: const Duration(milliseconds: 150),
      );

      expect(report.verdict, CustodyVerdict.unverified);
      expect(report.verificationBadge, contains('Not Verified'));
      expect(report.measurement, isNull);
      expect(report.limitations,
          contains('noCaptureWindow:playbackIdleOrEngineUnloaded'));
      // The pending window must be released, or every later verification is
      // blocked by it.
      expect(calls.where((c) => c.method == 'cancelCustodyWindow').length, 1);
    });

    test('non-Android builds are "not supported", not "unverified"', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      stubChannel();
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't5',
        trackTitle: 'iOS',
        hashFile: false,
        timeout: const Duration(milliseconds: 120),
      );

      expect(report.verdict, CustodyVerdict.notSupported);
      expect(report.verificationBadge, contains('no native capture'));
      expect(calls.where((c) => c.method == 'armCustodyWindow'), isEmpty);
    });

    test('binds the certificate to a real whole-file digest', () async {
      stubChannel(window: bitExactWindow());
      final directory = await Directory.systemTemp.createTemp('pulsr_custody');
      final file = File('${directory.path}/track.flac');
      final bytes = List<int>.generate(4096, (i) => (i * 7) % 251);
      await file.writeAsBytes(bytes, flush: true);

      final service = ChainOfCustodyService();
      final report = await service.verifyChain(
        trackId: 't6',
        trackTitle: 'Hashed',
        filePath: file.path,
      );

      // Independent expectation, computed here rather than by calling the code
      // under test.
      expect(report.contentSha256, sha256.convert(bytes).toString());
      expect(report.fileSizeBytes, bytes.length);
      expect(report.fileModifiedMs, isNotNull);
      await directory.delete(recursive: true);
    });

    test('a missing file records a limitation instead of a fake identity',
        () async {
      stubChannel(window: modifiedWindow());
      final service = ChainOfCustodyService();

      final report = await service.verifyChain(
        trackId: 't7',
        trackTitle: 'Gone',
        filePath: r'D:\definitely\not\here.flac',
      );

      expect(report.contentSha256, isNull);
      expect(report.limitations, contains('contentHashFailed:fileNotFound'));
    });

    test('a hasher that throws is recorded as a limitation, not a crash',
        () async {
      stubChannel(window: modifiedWindow());
      final directory = await Directory.systemTemp.createTemp('pulsr_custody');
      final file = File('${directory.path}/broken.flac');
      await file.writeAsBytes(List<int>.filled(64, 3), flush: true);

      final service = ChainOfCustodyService(
          contentHasher: (path, size) => throw StateError('unreadable'));
      final report = await service.verifyChain(
        trackId: 't7b',
        trackTitle: 'Unreadable',
        filePath: file.path,
      );

      expect(report.contentSha256, isNull);
      expect(report.fileSizeBytes, 64);
      expect(report.limitations.any((l) => l.startsWith('contentHashFailed')),
          isTrue);
      await directory.delete(recursive: true);
    });

    test(
        'JSON carries the certificate digest and it verifies against a re-read',
        () async {
      stubChannel(window: modifiedWindow());
      final service = ChainOfCustodyService();
      final report = await service.verifyChain(
        trackId: 't8',
        trackTitle: 'Export',
        hashFile: false,
      );

      final exported = jsonEncode(report.toJson());
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      expect(decoded['certificateSha256'], isA<String>());
      expect((decoded['certificateSha256'] as String).length, 64);
      expect(decoded['verdict'], 'chainModifiedMeasured');
    });

    test(
        'concurrent verifyChain calls serialize cleanly without overlapping arm/collect',
        () async {
      final events = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        events.add(call.method);
        switch (call.method) {
          case 'getChainOfCustodyReport':
            return baseEngineReport(bitPerfectActive: true);
          case 'armCustodyWindow':
            await Future<void>.delayed(const Duration(milliseconds: 25));
            return {'armed': true, 'reason': 'ok'};
          case 'collectCustodyWindow':
            return {'available': true, ...bitExactWindow()};
          case 'cancelCustodyWindow':
            return true;
        }
        return null;
      });
      final service = ChainOfCustodyService();
      await Future.wait([
        service.verifyChain(trackId: 's1', trackTitle: 'One', hashFile: false),
        service.verifyChain(trackId: 's2', trackTitle: 'Two', hashFile: false),
      ]);

      final firstArm = events.indexOf('armCustodyWindow');
      final firstCollect = events.indexOf('collectCustodyWindow');
      final secondArm = events.lastIndexOf('armCustodyWindow');
      expect(firstArm, isNonNegative);
      expect(firstCollect, greaterThan(firstArm));
      expect(secondArm, greaterThan(firstCollect));
    });

    test(
        'contentHashFailed limitation scrubs user path PII from exception text',
        () async {
      stubChannel(window: modifiedWindow());
      final directory = await Directory.systemTemp.createTemp('pulsr_custody');
      final file = File('${directory.path}/broken.flac');
      await file.writeAsBytes(List<int>.filled(64, 3), flush: true);

      final service = ChainOfCustodyService(
        contentHasher: (path, size) =>
            throw StateError(r'Cannot read C:\Users\alice\Private\broken.flac'),
      );
      final report = await service.verifyChain(
        trackId: 't_pii',
        trackTitle: 'Redacted',
        filePath: file.path,
      );

      expect(
          report.limitations,
          anyElement(allOf(startsWith('contentHashFailed:'),
              isNot(contains('alice')), contains('[REDACTED_USER_PATH]'))));
      await directory.delete(recursive: true);
    });
  });
}
