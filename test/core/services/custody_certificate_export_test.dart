// test/core/services/custody_certificate_export_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/chain_of_custody_service.dart';
import 'package:pulsr/core/services/custody_certificate_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_cert_export');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  ChainOfCustodyReport report({
    String trackId = '42',
    CustodyMeasurement? measurement,
    List<String> limitations = const [],
  }) {
    return ChainOfCustodyReport(
      trackId: trackId,
      trackTitle: 'Certificate Track',
      contentSha256: 'a' * 64,
      sourceIdentitySha256: 'b' * 64,
      fileSizeBytes: 12345,
      fileModifiedMs: 1700000000000,
      decoderCodec: 'FLAC',
      sourceSampleRate: 96000,
      sourceBitDepth: 24,
      outputSampleRate: 96000,
      bufferSize: 512,
      activeDspStages: const ['EQUALIZER'],
      isBitPerfectActive: false,
      isBypassCompareActive: false,
      rollingRtf: 0.04,
      estimatedLatencyMs: 8.0,
      thermalStatus: 0,
      measurement: measurement,
      limitations: limitations,
      verifiedAt: DateTime.utc(2026, 11, 5, 9, 30),
    );
  }

  test('writes a verifiable artifact whose digest matches its own fields',
      () async {
    final source = report(
      measurement: CustodyMeasurement.fromWindowMap({
        'frames': 2048,
        'channels': 2,
        'sampleRate': 96000.0,
        'windowMs': 21.33,
        'activeStages': 1,
        'snapshotGeneration': 4,
        'inputSha256': 'c' * 64,
        'outputSha256': 'd' * 64,
      }),
    );

    final artifact =
        await exportCustodyCertificate(source, directory: tempDir);

    expect(artifact.file.existsSync(), isTrue);
    final decoded =
        jsonDecode(await artifact.file.readAsString()) as Map<String, dynamic>;
    expect(decoded['certificateSha256'], source.certificateSha256);
    expect(decoded['verdict'], 'chainModifiedMeasured');
    expect(decoded['measurement']['frames'], 2048);
    // Independent recomputation: re-serializing the artifact without its digest
    // field must reproduce the digest it carries.
    final recomputed = ChainOfCustodyReport(
      trackId: decoded['trackId'] as String,
      trackTitle: decoded['trackTitle'] as String,
      contentSha256: decoded['contentSha256'] as String,
      sourceIdentitySha256: decoded['sourceIdentitySha256'] as String,
      fileSizeBytes: decoded['fileSizeBytes'] as int,
      fileModifiedMs: decoded['fileModifiedMs'] as int,
      decoderCodec: decoded['decoderCodec'] as String,
      sourceSampleRate: decoded['sourceSampleRate'] as int,
      sourceBitDepth: decoded['sourceBitDepth'] as int,
      outputSampleRate: decoded['outputSampleRate'] as int,
      bufferSize: decoded['bufferSize'] as int,
      activeDspStages: (decoded['activeDspStages'] as List).cast<String>(),
      isBitPerfectActive: decoded['isBitPerfectActive'] as bool,
      isBypassCompareActive: decoded['isBypassCompareActive'] as bool,
      rollingRtf: (decoded['rollingRtf'] as num).toDouble(),
      estimatedLatencyMs: (decoded['estimatedLatencyMs'] as num).toDouble(),
      thermalStatus: decoded['thermalStatus'] as int,
      measurement: CustodyMeasurement.fromWindowMap(
          (decoded['measurement'] as Map).cast<String, dynamic>()),
      limitations: (decoded['limitations'] as List).cast<String>(),
      verifiedAt: DateTime.parse(decoded['verifiedAt'] as String),
    );
    expect(recomputed.certificateSha256, artifact.certificateSha256);
  });

  test('an unverified report exports as unverified, never as bit-exact',
      () async {
    final artifact = await exportCustodyCertificate(report(),
        directory: tempDir);
    final decoded =
        jsonDecode(artifact.jsonText) as Map<String, dynamic>;
    expect(decoded['verdict'], 'unverified');
    expect((decoded['verificationBadge'] as String), isNot(contains('Bit-Exact')));
  });

  test('the artifact carries no filesystem path of the track', () async {
    final artifact = await exportCustodyCertificate(
      report(limitations: const ['contentHashDeclined:noLocalFile']),
      directory: tempDir,
    );
    // The library path must not travel with a certificate shared outside the app.
    expect(artifact.jsonText.contains('file:///'), isFalse);
    expect(artifact.jsonText.contains(r'C:\'), isFalse);
    expect((jsonDecode(artifact.jsonText) as Map).containsKey('filePath'), isFalse);
  });

  test('hostile track ids cannot escape the output directory', () async {
    final artifact = await exportCustodyCertificate(
      report(trackId: '../../etc/passwd'),
      directory: tempDir,
    );
    final name = artifact.file.uri.pathSegments.last;
    expect(artifact.file.parent.path, tempDir.path);
    expect(name.contains('/'), isFalse);
    expect(name.contains(r'\'), isFalse);
    expect(name.startsWith('.'), isFalse);
    expect(name, contains('pulsr-certificate-'));
    expect(artifact.file.existsSync(), isTrue);
  });
}
