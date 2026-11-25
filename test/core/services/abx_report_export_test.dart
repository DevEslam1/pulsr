// test/core/services/abx_report_export_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/abx_report_export.dart';
import 'package:pulsr/domain/models/abx_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_abx_export_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  const usbDac = AbxOutputDeviceInfo(
    name: 'FiiO KA17',
    type: 'usb',
    isUsbDac: true,
    sampleRate: 96000,
    bitDepth: 24,
    isBitPerfectActive: false,
  );

  test('refuses to build a report from an incomplete session', () {
    final session = AbxSession(trials: 12, seed: 42);
    session.answer(AbxAnswer.a);

    expect(
      () => AbxReport.fromSession(
        session,
        outputDevice: usbDac,
        sampleRate: 96000,
        codec: 'FLAC',
      ),
      throwsStateError,
    );
  });

  test(
      'exports completed session JSON with trials, exact binomial p-value, verdict, device, rate, and codec',
      () async {
    final session = AbxSession(trials: 12, seed: 19);
    for (final trial in session.trials) {
      session.answer(
        trial.hiddenX == AbxStimulus.a ? AbxAnswer.a : AbxAnswer.b,
      );
    }

    final exportedAt = DateTime.utc(2026, 11, 20, 1, 2, 3);
    final report = AbxReport.fromSession(
      session,
      outputDevice: usbDac,
      sampleRate: 96000,
      codec: 'FLAC',
      trackTitle: 'Reference Track',
      trackArtist: 'Studio Ensemble',
      sourceSampleRate: 96000,
      sourceBitDepth: 24,
      exportedAt: exportedAt,
    );

    final artifact = await exportAbxReport(report, directory: tempDir);
    expect(artifact.file.existsSync(), isTrue);

    final decoded =
        jsonDecode(await artifact.file.readAsString()) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], 1);
    expect(decoded['kind'], 'abx_report');
    expect(decoded['exportedAt'], exportedAt.toIso8601String());
    expect(decoded['totalTrials'], 12);
    expect(decoded['answeredTrials'], 12);
    expect(decoded['correctCount'], 12);
    expect(decoded['proportionCorrect'], 1.0);
    // 12/12 under H0: p = 0.5 -> 2^-12 = 0.000244140625
    expect(decoded['pValue'], closeTo(0.000244140625, 1e-12));
    expect(decoded['confidence'], closeTo(1.0 - 0.000244140625, 1e-12));
    expect(decoded['verdict'], AbxSession.strongKey);
    expect(decoded['sampleRate'], 96000);
    expect(decoded['codec'], 'FLAC');

    final device = decoded['outputDevice'] as Map<String, dynamic>;
    expect(device['name'], 'FiiO KA17');
    expect(device['type'], 'usb');
    expect(device['isUsbDac'], isTrue);
    expect(device['sampleRate'], 96000);
    expect(device['bitDepth'], 24);

    final track = decoded['track'] as Map<String, dynamic>;
    expect(track['title'], 'Reference Track');
    expect(track['artist'], 'Studio Ensemble');
    expect(track['codec'], 'FLAC');
    expect(track.containsKey('path'), isFalse);

    final trials =
        (decoded['trials'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(trials, hasLength(12));
    for (var i = 0; i < 12; i++) {
      expect(trials[i]['index'], i);
      expect(trials[i]['trialNumber'], i + 1);
      expect(trials[i]['hiddenX'], anyOf('a', 'b'));
      expect(trials[i]['answer'], trials[i]['hiddenX']);
      expect(trials[i]['correct'], isTrue);
    }
  });

  test('AbxRedactor scrubs paths, URLs, serial numbers, UUIDs, and MACs', () {
    expect(
      AbxRedactor.redact('Listening on C:\\Users\\Alice\\Music\\track.flac'),
      'Listening on [PATH_REDACTED]',
    );
    expect(
      AbxRedactor.redact('Playing from /storage/emulated/0/Music/track.mp3'),
      'Playing from [PATH_REDACTED]',
    );
    expect(
      AbxRedactor.redact(
          'Streamed via https://subsonic.server.com/rest/stream'),
      'Streamed via [URL_REDACTED]',
    );
    expect(
      AbxRedactor.redact('Device DAC SN: KA17-98765-XYZ'),
      'Device DAC SN: [SERIAL_REDACTED]',
    );
    expect(
      AbxRedactor.redact(
          'Session ID 12345678-1234-1234-1234-123456789abc finished'),
      'Session ID [UUID_REDACTED] finished',
    );
    expect(
      AbxRedactor.redact('Bluetooth DAC AA:BB:CC:DD:EE:FF connected'),
      'Bluetooth DAC [MAC_REDACTED] connected',
    );
  });

  test('AbxReport scrubs PII and calculates twoSidedPValue', () {
    final session = AbxSession(trials: 12, seed: 19);
    for (final trial in session.trials) {
      session.answer(
        trial.hiddenX == AbxStimulus.a ? AbxAnswer.a : AbxAnswer.b,
      );
    }

    final exportedAt = DateTime.utc(2026, 11, 20, 1, 2, 3);
    const device = AbxOutputDeviceInfo(
      name: 'FiiO KA17 SN: 98765-ABC',
      type: 'usb',
      isUsbDac: true,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: false,
    );

    final report = AbxReport.fromSession(
      session,
      outputDevice: device,
      sampleRate: 96000,
      codec: 'FLAC',
      trackTitle: 'Reference Track C:\\Music\\Track.flac',
      trackArtist: 'Studio Ensemble https://bandcamp.com/artist',
      sourceSampleRate: 96000,
      sourceBitDepth: 24,
      exportedAt: exportedAt,
    );

    final json = report.toJson();
    expect(json['twoSidedPValue'], closeTo(0.00048828125, 1e-12));
    expect(json['outputDevice']['name'], 'FiiO KA17 SN: [SERIAL_REDACTED]');
    expect(json['track']['title'], 'Reference Track [PATH_REDACTED]');
    expect(json['track']['artist'], 'Studio Ensemble [URL_REDACTED]');
  });

  test('golden abx_report_fixture matches contract structure', () {
    final file = File('test/fixtures/contracts/abx_report_fixture.json');
    expect(file.existsSync(), isTrue,
        reason: 'abx_report_fixture.json must exist');
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    expect(decoded['schemaVersion'], 1);
    expect(decoded['kind'], 'abx_report');
    expect(decoded['totalTrials'], 12);
    expect(decoded['answeredTrials'], 12);
    expect(decoded['correctCount'], 12);
    expect(decoded['proportionCorrect'], 1.0);
    expect(decoded['pValue'], closeTo(0.000244140625, 1e-12));
    expect(decoded['twoSidedPValue'], closeTo(0.00048828125, 1e-12));
    expect(decoded['confidence'], closeTo(0.999755859375, 1e-12));
    expect(decoded['verdict'], 'strong');
    expect(decoded['outputDevice']['name'], contains('[SERIAL_REDACTED]'));
    expect(decoded['track']['title'], contains('[PATH_REDACTED]'));
    expect(decoded['track']['artist'], contains('[URL_REDACTED]'));
    expect(decoded['trials'], hasLength(12));
  });
}
