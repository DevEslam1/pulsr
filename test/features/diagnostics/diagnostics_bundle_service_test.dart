// test/features/diagnostics/diagnostics_bundle_service_test.dart
//
// The privacy gate for exported bundles: storage paths, home paths, URL
// credentials and tokens must never survive, and a missing native probe must
// degrade one section instead of the whole bundle.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/diagnostics/diagnostics_bundle_service.dart';
import 'package:pulsr/features/diagnostics/diagnostics_log_buffer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late Directory temp;

  DiagnosticsBundleService buildService({
    DiagnosticsAsyncMapProbe? usb,
    DiagnosticsMapProbe? device,
    DiagnosticsMapProbe? counters,
  }) =>
      DiagnosticsBundleService(
        prefs: prefs,
        outputDevice: device ??
            () => <String, Object?>{
                  'name': 'USB DAC',
                  'path': '/home/eslam/output',
                },
        usbDiagnostics: usb ??
            () async => <String, Object?>{
                  'usbDevice': '/storage/emulated/0/dac',
                },
        outputPathCounters: counters,
        appVersion: () => '9.9.9',
        clock: () => DateTime.utc(2026, 5, 6, 7, 8, 9),
        tempDirectory: () async => temp,
      );

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.eqEnabled: true,
      PrefsKeys.eqPresetName: 'Harman',
      PrefsKeys.ditherEnabled: false,
      'setting_custom_reverb_ir_path': '/storage/emulated/0/Music/ir.wav',
      'user_home': '/home/eslam/Music',
      'windows_home': r'C:\Users\Eslam\Music\a.flac',
      'backend_url': 'https://user:pass@example.com/api',
      'backend_token': 'supersecret-token',
      'auth_header': 'Authorization: Bearer abc.def.ghi',
      'cookie_jar': <String>['SID=abc123; HSID=def456'],
    });
    prefs = await SharedPreferences.getInstance();
    temp = await Directory.systemTemp.createTemp('pulsr_bundle_test_');
    DiagnosticsLogBuffer.clear();
  });

  tearDown(() async {
    DiagnosticsLogBuffer.clear();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('redacts paths, credentials and tokens before serialization', () async {
    DiagnosticsLogBuffer.add(
      'open failed for /home/eslam/Music/a.flac',
      level: 'ERROR',
      category: 'Audio',
    );

    final bundle = await buildService().build();
    final json = jsonEncode(bundle.toJson());
    final lower = json.toLowerCase();

    expect(json.contains('/storage/'), isFalse);
    expect(lower.contains('eslam'), isFalse);
    expect(lower.contains('/home/'), isFalse);
    expect(json.contains('user:pass'), isFalse);
    expect(json.contains('supersecret-token'), isFalse);
    expect(json.contains('abc.def.ghi'), isFalse);
    expect(json.contains('SID=abc123'), isFalse);
    expect(json, contains('[REDACTED'));
    expect(bundle.preferences['backend_token'], '[REDACTED]');
    expect(bundle.preferences.containsKey('backend_token'), isTrue);
  });

  test('reports unavailable native counters with an explicit flag', () async {
    final bundle = await buildService().build();

    expect(bundle.outputPathCounters['reported'], isFalse);
    expect(
      bundle.outputPathCounters['source'],
      'native-not-reported',
    );
    final paths = bundle.outputPathCounters['paths'] as Map<String, Object?>;
    expect(paths.keys,
        containsAll(<String>['primary', 'usb_exclusive', 'aaudio']));
    for (final key in <String>['primary', 'usb_exclusive', 'aaudio']) {
      final counters = paths[key] as Map<String, Object?>;
      expect(counters['xruns'], 0);
      expect(counters['underruns'], 0);
      expect(counters['reported'], isFalse);
      expect(counters['source'], 'native-not-reported');
    }
  });

  test('uses injected counters when the native side reports them', () async {
    final bundle = await buildService(
      counters: () => <String, Object?>{
        'reported': true,
        'source': 'aaudio',
        'paths': <String, Object?>{
          'primary': <String, Object?>{
            'xruns': 4,
            'underruns': 2,
            'reported': true,
          },
        },
      },
    ).build();

    expect(bundle.outputPathCounters['reported'], isTrue);
    expect(bundle.outputPathCounters['source'], 'aaudio');
    final paths = bundle.outputPathCounters['paths'] as Map<String, Object?>;
    final primary = paths['primary'] as Map<String, Object?>;
    expect(primary['xruns'], 4);
    expect(primary['underruns'], 2);
  });

  test('collects app metadata and the DSP stage list', () async {
    final bundle = await buildService().build();

    expect(bundle.app['appVersion'], '9.9.9');
    expect(bundle.app['buildMode'], 'debug');
    expect(bundle.dspStages.length, 18);
    final equalizer =
        bundle.dspStages.firstWhere((stage) => stage['stage'] == 'equalizer');
    expect(equalizer['enabled'], isTrue);
    expect(equalizer['detail'], 'Harman');
    final dither =
        bundle.dspStages.firstWhere((stage) => stage['stage'] == 'dither');
    expect(dither['enabled'], isFalse);
    final loudness = bundle.dspStages
        .firstWhere((stage) => stage['stage'] == 'loudness_contour');
    expect(loudness['enabled'], isFalse);
    expect(bundle.enabledDspStageCount, 1);
  });

  test('survives a failing USB probe', () async {
    final bundle = await buildService(
      usb: () async => throw StateError('no platform channel'),
    ).build();

    expect(bundle.usb['status'], 'unavailable');
  });

  test('survives a failing output-device probe', () async {
    final bundle = await buildService(
      device: () => throw StateError('no audio session'),
    ).build();

    expect('${bundle.outputDevice['status']}', contains('Unknown'));
  });

  test('export writes bundle.json and bundle.log with redacted content',
      () async {
    DiagnosticsLogBuffer.add(
      'tap at /storage/emulated/0/Music/x.flac',
      level: 'ERROR',
      category: 'Audio',
    );

    final files = await buildService().export();

    expect(files.length, 2);
    final jsonFile = File(files.first.path);
    final logFile = File(files.last.path);
    expect(p.basename(jsonFile.path), DiagnosticsBundleService.bundleFileName);
    expect(p.basename(logFile.path), DiagnosticsBundleService.logFileName);

    final json = await jsonFile.readAsString();
    final log = await logFile.readAsString();
    expect(json.contains('/storage/'), isFalse);
    expect(json.toLowerCase().contains('eslam'), isFalse);
    expect(log.toLowerCase().contains('eslam'), isFalse);
    expect(log.contains('/storage/'), isFalse);
    expect(log, contains('[Audio]'));
  });

  test('reads every DSP detail with the type the equalizer persists', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.eqEnabled: true,
      PrefsKeys.eqPresetName: 'Studio',
      PrefsKeys.crossfeedEnabled: true,
      PrefsKeys.crossfeedMode: 2,
      PrefsKeys.saturationEnabled: true,
      PrefsKeys.saturationMode: 1,
      PrefsKeys.stereoWidthEnabled: true,
      PrefsKeys.stereoWidthMultiband: true,
      PrefsKeys.dynamicBassEnabled: true,
      PrefsKeys.dynamicBassPreset: 4,
      PrefsKeys.multibandCompressorEnabled: true,
      PrefsKeys.multibandCompressorBands: jsonEncode(<Object>[
        <String, Object>{'frequency': 120},
        <String, Object>{'frequency': 800},
        <String, Object>{'frequency': 3000},
        <String, Object>{'frequency': 9000},
      ]),
      PrefsKeys.convolutionReverbEnabled: true,
      PrefsKeys.convolutionReverbPreset: 3,
      PrefsKeys.lookaheadLimiterEnabled: true,
      PrefsKeys.lookaheadLimiterThresholdDb: -1.5,
      PrefsKeys.ditherEnabled: true,
      PrefsKeys.ditherTargetBitDepth: 24,
      PrefsKeys.dacVoicingEnabled: true,
      PrefsKeys.dacVoicingCharacter: 2,
    });
    prefs = await SharedPreferences.getInstance();

    final bundle = await buildService().build();
    final details = <String, Object?>{
      for (final stage in bundle.dspStages)
        '${stage['stage']}': stage['detail'],
    };

    expect(details['equalizer'], 'Studio');
    expect(details['crossfeed'], '2');
    expect(details['saturation'], '1');
    expect(details['stereo_width'], 'multiband');
    expect(details['dynamic_bass'], '4');
    expect(details['multiband_compressor'], '4 bands');
    expect(details['convolution_reverb'], '3');
    expect(details['limiter'], '-1.5 dB');
    expect(details['dither'], '24-bit');
    expect(details['dac_voicing'], '2');
    expect(bundle.enabledDspStageCount, 10);
  });

  test('a wrong-typed DSP preference falls back instead of throwing', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.crossfeedMode: '2',
      PrefsKeys.saturationMode: '1',
      PrefsKeys.dynamicBassPreset: '4',
      PrefsKeys.convolutionReverbPreset: '3',
      PrefsKeys.dacVoicingCharacter: '2',
      PrefsKeys.ditherTargetBitDepth: '32',
      PrefsKeys.lookaheadLimiterThresholdDb: 'loud',
      PrefsKeys.multibandCompressorBands: 4,
    });
    prefs = await SharedPreferences.getInstance();

    final bundle = await buildService().build();
    final details = <String, Object?>{
      for (final stage in bundle.dspStages)
        '${stage['stage']}': stage['detail'],
    };

    expect(details['crossfeed'], 'off');
    expect(details['saturation'], 'off');
    expect(details['dynamic_bass'], 'flat');
    expect(details['convolution_reverb'], 'none');
    expect(details['dac_voicing'], 'neutral');
    expect(details['dither'], '24-bit');
    expect(details['limiter'], '0.0 dB');
    expect(details['multiband_compressor'], '4 bands');
  });

  test('redacts internal data, opt and UNC paths', () {
    final redacted = DiagnosticsBundleService.redactText(
      'a /data/user/0/com.pulsr.music/files/x.flac '
      'b /data/data/com.pulsr.music/cache/y '
      'c /opt/pulsr/bin/pulsr '
      r'd \\nas\share\music\track.flac',
    );

    expect(redacted.contains('/data/user/0'), isFalse);
    expect(redacted.contains('/data/data'), isFalse);
    expect(redacted.contains('/opt/'), isFalse);
    expect(redacted.contains(r'\\nas\share'), isFalse);
    expect(redacted, contains('[REDACTED_PATH]'));
  });

  test('redacts paths nested in list and map preference values', () async {
    prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'nested_list',
      <String>['/data/user/0/com.pulsr.music/files/a', '/opt/tool/b'],
    );
    await prefs.setString(
      'nested_map',
      jsonEncode(<String, Object?>{
        'outer': <String, Object?>{
          'inner': <String>['/data/data/com.pulsr.music/c', r'\\host\share\d'],
        },
      }),
    );

    final bundle = await buildService().build();
    final json = jsonEncode(bundle.toJson());

    expect(json.contains('/data/user/0'), isFalse);
    expect(json.contains('/data/data'), isFalse);
    expect(json.contains('/opt/'), isFalse);
    expect(json.contains(r'\\host\share'), isFalse);
  });

  test('redacts sensitive keys and paths inside nested probe maps', () async {
    final bundle = await buildService(
      usb: () async => <String, Object?>{
        'status': 'ok',
        'auth': <String, Object?>{
          'token': 'supersecret',
          'header': 'Authorization: Bearer abc.def',
        },
        'files': <Object?>[
          <String, Object?>{
            'path': '/data/user/0/com.pulsr.music/files/a.flac',
            'name': 'a.flac',
          },
        ],
      },
    ).build();

    final auth = bundle.usb['auth'] as Map<String, Object?>;
    expect(auth['token'], '[REDACTED]');
    expect(auth['header'], contains('REDACTED'));
    expect(auth['header'], isNot(contains('abc.def')));
    final files = bundle.usb['files'] as List<Object?>;
    final file = files.single as Map<String, Object?>;
    expect('${file['path']}', contains('REDACTED'));
    expect('${file['path']}', isNot(contains('/data/user/0')));
    expect(file['name'], 'a.flac');
  });

  test('cleanupExport removes the temporary bundle directory', () async {
    final service = buildService();
    final files = await service.export();

    expect(await temp.exists(), isTrue);
    for (final file in files) {
      expect(await File(file.path).exists(), isTrue);
    }

    await service.cleanupExport();

    expect(await temp.exists(), isFalse);
  });

  test('redacts JSON-quoted credentials, unquoted pairs, and private IPs', () {
    const input =
        '{"token": "secret123", "password":"xyz", "username":"admin", "host":"192.168.1.100", "gateway":"10.0.0.1", "ipv6":"::1"} and token=secret456';
    final redacted = DiagnosticsBundleService.redactText(input);

    expect(redacted.contains('secret123'), isFalse);
    expect(redacted.contains('xyz'), isFalse);
    expect(redacted.contains('admin'), isFalse);
    expect(redacted.contains('secret456'), isFalse);
    expect(redacted.contains('192.168.1.100'), isFalse);
    expect(redacted.contains('10.0.0.1'), isFalse);
    expect(redacted.contains('::1'), isFalse);
    expect(redacted, contains('"token": "[REDACTED_SECRET]"'));
    expect(redacted, contains('"password": "[REDACTED_SECRET]"'));
    expect(redacted, contains('"username":"[REDACTED_SECRET]"'));
    expect(redacted, contains('token=[REDACTED_SECRET]'));
    expect(redacted, contains('[REDACTED_IP]'));
  });
}
