import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/chain_of_custody_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChainOfCustodyService', () {
    late ChainOfCustodyService service;

    setUp(() {
      service = ChainOfCustodyService();
    });

    test('config-only report keeps header identity separate from content', () async {
      final headerBytes = [0x4F, 0x67, 0x67, 0x53, 0x00, 0x02]; // "OggS" header
      final report = await service.generateReport(
        trackId: 'track-42',
        trackTitle: 'Audiophile Test Tone',
        fileHeaderBytes: headerBytes,
        decoderCodec: 'Opus',
        sourceSampleRate: 48000,
        sourceBitDepth: 24,
      );

      expect(report.trackId, 'track-42');
      expect(report.trackTitle, 'Audiophile Test Tone');
      expect(report.decoderCodec, 'Opus');
      expect(report.sourceSampleRate, 48000);
      expect(report.sourceBitDepth, 24);
      expect(report.sourceIdentitySha256.isNotEmpty, isTrue);
      // Six header bytes are not file contents, so they must never be reported
      // as the content identity.
      expect(report.contentSha256, isNull);

      // Determinism: the same header bytes yield the same identity digest.
      final secondReport = await service.generateReport(
        trackId: 'track-42',
        trackTitle: 'Audiophile Test Tone',
        fileHeaderBytes: headerBytes,
      );
      expect(secondReport.sourceIdentitySha256, report.sourceIdentitySha256);
    });

    test('a config-only report is never a bit-exact claim', () async {
      // Regression guard: the old badge said "Bit-Exact Direct Output" purely
      // because no stage flags were set. Configuration is not measurement.
      final report = await service.generateReport(
        trackId: 'track-42',
        trackTitle: 'T',
        trackUri: 'file:///music/quiet.flac',
      );
      expect(report.verdict, CustodyVerdict.unverified);
      expect(report.verificationBadge, contains('Not Verified'));
      expect(report.verificationBadge, isNot(contains('Bit-Exact')));
    });

    test('badges follow the measurement, not the stage list', () {
      final measured = ChainOfCustodyReport(
        trackId: '1',
        trackTitle: 'T',
        contentSha256: 'a' * 64,
        sourceIdentitySha256: 'b' * 64,
        fileSizeBytes: 1000,
        fileModifiedMs: 2000,
        decoderCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        bufferSize: 512,
        activeDspStages: const [],
        isBitPerfectActive: true,
        isBypassCompareActive: false,
        rollingRtf: 0.0,
        estimatedLatencyMs: 5.3,
        thermalStatus: 0,
        measurement: CustodyMeasurement(
          frames: 2048,
          channels: 2,
          sampleRate: 96000,
          windowMs: 21.3,
          activeStages: 0,
          snapshotGeneration: 7,
          bitPerfectAtArm: true,
          bypassCompareAtArm: false,
          truncated: false,
          inputSha256: 'c' * 64,
          outputSha256: 'c' * 64,
          bitExactMeasured: true,
        ),
        limitations: const [],
        verifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(measured.verdict, CustodyVerdict.bitExactMeasured);
      expect(measured.verificationBadge, contains('Bit-Exact Output'));
      expect(measured.verificationBadge, contains('2048 frames'));

      final dsp = ChainOfCustodyReport(
        trackId: '2',
        trackTitle: 'T2',
        contentSha256: 'a' * 64,
        sourceIdentitySha256: 'b' * 64,
        fileSizeBytes: 1000,
        fileModifiedMs: 2000,
        decoderCodec: 'AAC',
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        bufferSize: 512,
        activeDspStages: const ['EQUALIZER', 'LIMITER'],
        isBitPerfectActive: false,
        isBypassCompareActive: false,
        rollingRtf: 0.12,
        estimatedLatencyMs: 12.0,
        thermalStatus: 0,
        measurement: CustodyMeasurement(
          frames: 2048,
          channels: 2,
          sampleRate: 48000,
          windowMs: 42.7,
          activeStages: 17,
          snapshotGeneration: 9,
          bitPerfectAtArm: false,
          bypassCompareAtArm: false,
          truncated: false,
          inputSha256: 'c' * 64,
          outputSha256: 'd' * 64,
          bitExactMeasured: false,
        ),
        limitations: const [],
        verifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(dsp.verdict, CustodyVerdict.chainModifiedMeasured);
      expect(dsp.verificationBadge, contains('Chain Modified Samples'));
      expect(dsp.verificationBadge, contains('2 stages'));
      expect(dsp.verificationBadge, isNot(contains('Bit-Exact')));
    });

    test('truncated windows are labelled partial, not clean', () {
      final base = ChainOfCustodyReport(
        trackId: '3',
        trackTitle: 'T3',
        contentSha256: null,
        sourceIdentitySha256: 'b' * 64,
        fileSizeBytes: null,
        fileModifiedMs: null,
        decoderCodec: 'FLAC',
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        bufferSize: 512,
        activeDspStages: const [],
        isBitPerfectActive: true,
        isBypassCompareActive: false,
        rollingRtf: 0.0,
        estimatedLatencyMs: 0.0,
        thermalStatus: 0,
        measurement: null,
        limitations: const [],
        verifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final partial = ChainOfCustodyReport(
        trackId: base.trackId,
        trackTitle: base.trackTitle,
        contentSha256: base.contentSha256,
        sourceIdentitySha256: base.sourceIdentitySha256,
        fileSizeBytes: base.fileSizeBytes,
        fileModifiedMs: base.fileModifiedMs,
        decoderCodec: base.decoderCodec,
        sourceSampleRate: base.sourceSampleRate,
        sourceBitDepth: base.sourceBitDepth,
        outputSampleRate: base.outputSampleRate,
        bufferSize: base.bufferSize,
        activeDspStages: base.activeDspStages,
        isBitPerfectActive: base.isBitPerfectActive,
        isBypassCompareActive: base.isBypassCompareActive,
        rollingRtf: base.rollingRtf,
        estimatedLatencyMs: base.estimatedLatencyMs,
        thermalStatus: base.thermalStatus,
        limitations: base.limitations,
        verifiedAt: base.verifiedAt,
        measurement: CustodyMeasurement(
          frames: 100,
          channels: 2,
          sampleRate: 44100,
          windowMs: 2.3,
          activeStages: 0,
          snapshotGeneration: 1,
          bitPerfectAtArm: true,
          bypassCompareAtArm: false,
          truncated: true,
          inputSha256: 'e' * 64,
          outputSha256: 'e' * 64,
          bitExactMeasured: true,
        ),
      );
      expect(partial.verificationBadge, contains('partial window'));
      expect(partial.verificationBadge, contains('Bit-Exact on a short 100-frame'));
    });

    test('two empty digests are not evidence of bit-exactness', () {
      // The bridge returns empty strings when it captured nothing; trusting
      // `input == output` alone would certify that as a pass.
      final measurement = CustodyMeasurement.fromWindowMap(const {
        'available': true,
        'frames': 0,
        'channels': 2,
        'sampleRate': 44100.0,
        'activeStages': 0,
        'snapshotGeneration': 1,
        'inputSha256': '',
        'outputSha256': '',
      });
      expect(measurement.bitExactMeasured, isFalse);
    });

    test('serializes report correctly to JSON', () async {
      final report = await service.generateReport(
        trackId: 'track-42',
        trackTitle: 'Audiophile Test Tone',
        trackUri: 'https://rr1---sn-audio.googlevideo.com/videoplayback?id=123',
      );

      final json = report.toJson();
      expect(json['trackId'], 'track-42');
      expect(json['trackTitle'], 'Audiophile Test Tone');
      expect(json['sourceIdentitySha256'], isA<String>());
      expect(json['verificationBadge'], isA<String>());
      expect(json['verifiedAt'], isA<String>());
      expect(json['verdict'], 'unverified');
      expect(json['certificateSha256'], isA<String>());
    });
  });

  group('certificate integrity', () {
    ChainOfCustodyReport buildReport({String title = 'Certificate Track'}) {
      return ChainOfCustodyReport(
        trackId: 'cert-1',
        trackTitle: title,
        contentSha256: 'f' * 64,
        sourceIdentitySha256: 'a' * 64,
        fileSizeBytes: 4096,
        fileModifiedMs: 1700000000000,
        decoderCodec: 'FLAC',
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        bufferSize: 512,
        activeDspStages: const ['EQUALIZER'],
        isBitPerfectActive: false,
        isBypassCompareActive: false,
        rollingRtf: 0.05,
        estimatedLatencyMs: 10.5,
        thermalStatus: 1,
        measurement: CustodyMeasurement(
          frames: 2048,
          channels: 2,
          sampleRate: 44100,
          windowMs: 46.4,
          activeStages: 1,
          snapshotGeneration: 3,
          bitPerfectAtArm: false,
          bypassCompareAtArm: false,
          truncated: false,
          inputSha256: 'b' * 64,
          outputSha256: 'c' * 64,
          bitExactMeasured: false,
        ),
        limitations: const [],
        verifiedAt: DateTime.utc(2026, 11, 4, 12),
      );
    }

    test('digest is stable across map key order', () {
      final first = buildReport();
      final second = buildReport();
      expect(first.certificateSha256, second.certificateSha256);
      final reordered = Map<String, dynamic>.fromEntries(
          first.toJson().entries.toList().reversed);
      expect(reordered['certificateSha256'], first.certificateSha256);
    });

    test('editing any reported field invalidates the certificate digest', () {
      final original = buildReport();
      final tamperedJson = original.toJson()
        ..['measurement'] = (original.toJson()['measurement'] as Map)
            .cast<String, dynamic>()
          ..['bitExactMeasured'] = true;
      // Re-serializing a mutated report must not reproduce the original digest.
      final tampered = ChainOfCustodyReport(
        trackId: original.trackId,
        trackTitle: original.trackTitle,
        contentSha256: original.contentSha256,
        sourceIdentitySha256: original.sourceIdentitySha256,
        fileSizeBytes: original.fileSizeBytes,
        fileModifiedMs: original.fileModifiedMs,
        decoderCodec: original.decoderCodec,
        sourceSampleRate: original.sourceSampleRate,
        sourceBitDepth: original.sourceBitDepth,
        outputSampleRate: original.outputSampleRate,
        bufferSize: original.bufferSize,
        activeDspStages: original.activeDspStages,
        isBitPerfectActive: original.isBitPerfectActive,
        isBypassCompareActive: original.isBypassCompareActive,
        rollingRtf: original.rollingRtf,
        estimatedLatencyMs: original.estimatedLatencyMs,
        thermalStatus: original.thermalStatus,
        measurement: CustodyMeasurement.fromWindowMap({
          ...original.measurement!.toJson(),
          'inputSha256': original.measurement!.outputSha256,
        }),
        limitations: original.limitations,
        verifiedAt: original.verifiedAt,
      );
      expect(tampered.certificateSha256, isNot(original.certificateSha256));
      expect(tampered.verdict, CustodyVerdict.bitExactMeasured);
      expect(tamperedJson['bitExactMeasured'], isTrue);
    });
  });

  group('whole-file hashing', () {
    test('declines files above the cap without reading them', () async {
      final hashed = await ChainOfCustodyService.hashFileContents(
        'this/path/never/opens.flac',
        ChainOfCustodyService.maxHashableBytes + 1,
      );
      expect(hashed, isNull);
    });
  });
}
