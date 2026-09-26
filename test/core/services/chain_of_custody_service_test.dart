import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/chain_of_custody_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChainOfCustodyService', () {
    late ChainOfCustodyService service;

    setUp(() {
      service = ChainOfCustodyService();
    });

    test('generates valid report with deterministic SHA-256 integrity hash', () async {
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
      expect(report.trackSha256.isNotEmpty, isTrue);

      // Determinism: Same header bytes yield identical SHA-256
      final secondReport = await service.generateReport(
        trackId: 'track-42',
        trackTitle: 'Audiophile Test Tone',
        fileHeaderBytes: headerBytes,
      );
      expect(secondReport.trackSha256, report.trackSha256);
    });

    test('verifies badges correctly based on bit-exact and DSP states', () {
      final bitExactReport = ChainOfCustodyReport(
        trackId: '1',
        trackTitle: 'T',
        trackSha256: 'hash',
        decoderCodec: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        bufferSize: 512,
        activeDspStages: const [],
        isBitExactChain: true,
        isBitPerfectActive: true,
        isBypassCompareActive: false,
        rollingRtf: 0.0,
        estimatedLatencyMs: 5.3,
        thermalStatus: 0,
        verifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(bitExactReport.verificationBadge, contains('Bit-Exact Direct Output'));

      final dspReport = ChainOfCustodyReport(
        trackId: '2',
        trackTitle: 'T2',
        trackSha256: 'hash',
        decoderCodec: 'AAC',
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        bufferSize: 512,
        activeDspStages: const ['PARAMETRIC_EQ', 'LIMITER'],
        isBitExactChain: false,
        isBitPerfectActive: false,
        isBypassCompareActive: false,
        rollingRtf: 0.12,
        estimatedLatencyMs: 12.0,
        thermalStatus: 0,
        verifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(dspReport.verificationBadge, contains('Verified Native DSP (2 stages)'));
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
      expect(json['trackSha256'], isA<String>());
      expect(json['verificationBadge'], isA<String>());
      expect(json['verifiedAt'], isA<String>());
    });
  });
}
