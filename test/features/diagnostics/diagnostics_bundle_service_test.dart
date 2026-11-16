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
    expect(bundle.dspStages.length, 10);
    final equalizer =
        bundle.dspStages.firstWhere((stage) => stage['stage'] == 'equalizer');
    expect(equalizer['enabled'], isTrue);
    expect(equalizer['detail'], 'Harman');
    final dither =
        bundle.dspStages.firstWhere((stage) => stage['stage'] == 'dither');
    expect(dither['enabled'], isFalse);
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
}
