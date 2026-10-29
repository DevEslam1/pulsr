// test/dsp_debug_report_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/dsp_debug_report.dart';

void main() {
  group('DspDebugReport Model Tests', () {
    test('fromMap parses all fields and stages accurately', () {
      final map = {
        'audioSessionId': 42,
        'isSessionAttached': true,
        'dspPreference': 'native',
        'isBitPerfectBypassActive': false,
        'isNativeDspLoaded': true,
        'activeDspStagesMask': 15,
        'autoDegradedStagesMask': 0,
        'hasOemAudio': true,
        'detectedEngines': ['com.dolby.daxservice', 'com.dirac.audio'],
        'stages': [
          {
            'name': 'Graphic Equalizer',
            'category': 'Android HAL (DynamicsProcessing)',
            'isSupported': true,
            'isEnabled': true,
            'isBypassed': false,
            'isDegraded': false,
            'parameters': {'bandCount': 10, 'preampDb': 2.5},
            'statusDescription': '10 Bands Active (Preamp: 2.5 dB)',
          },
          {
            'name': 'True-Peak Lookahead Limiter',
            'category': 'Native C++ Engine',
            'isSupported': true,
            'isEnabled': true,
            'isBypassed': false,
            'isDegraded': false,
            'parameters': {'thresholdDb': -0.2, 'lookaheadMs': 3.0},
            'statusDescription': 'Threshold: -0.2 dB, Lookahead: 3.0 ms',
          }
        ],
        'activeEffectNames': [
          'Graphic Equalizer (10 Bands, Preamp: 2.5 dB)',
          'Lookahead Limiter (Thresh: -0.2dB, Lookahead: 3.0ms)'
        ]
      };

      final report = DspDebugReport.fromMap(map);

      expect(report.audioSessionId, equals(42));
      expect(report.isSessionAttached, isTrue);
      expect(report.dspPreference, equals('native'));
      expect(report.isBitPerfectBypassActive, isFalse);
      expect(report.isNativeDspLoaded, isTrue);
      expect(report.activeDspStagesMask, equals(15));
      expect(report.autoDegradedStagesMask, equals(0));
      expect(report.hasOemAudio, isTrue);
      expect(report.detectedOemEngines, contains('com.dolby.daxservice'));
      expect(report.stages.length, equals(2));
      expect(report.stages.first.name, equals('Graphic Equalizer'));
      expect(report.stages.first.isEnabled, isTrue);
      expect(report.stages.first.parameters['bandCount'], equals(10));
      expect(report.activeEffectNames.length, equals(2));

      final jsonString = report.toFormattedJson();
      expect(jsonString, contains('"audioSessionId": 42'));
      expect(jsonString, contains('"Graphic Equalizer"'));
    });

    test('fromMap handles null and empty maps safely', () {
      final report = DspDebugReport.fromMap({});

      expect(report.audioSessionId, equals(0));
      expect(report.isSessionAttached, isFalse);
      expect(report.dspPreference, equals('native'));
      expect(report.isBitPerfectBypassActive, isFalse);
      expect(report.isNativeDspLoaded, isFalse);
      expect(report.stages, isEmpty);
      expect(report.activeEffectNames, isEmpty);
      expect(report.detectedOemEngines, isEmpty);
    });

    test('fromMap tolerates numeric/string flags and non-string params', () {
      final report = DspDebugReport.fromMap(<dynamic, dynamic>{
        'audioSessionId': '42',
        'isSessionAttached': 1,
        'isNativeDspLoaded': 'true',
        'activeDspStagesMask': '15',
        'autoDegradedStagesMask': 2.0,
        'stages': [
          <dynamic, dynamic>{
            'name': 'EQ',
            'isSupported': 1,
            'isEnabled': 0,
            'parameters': <dynamic, dynamic>{1: 'one'},
          },
        ],
      });

      expect(report.audioSessionId, 42);
      expect(report.isSessionAttached, isTrue);
      expect(report.isNativeDspLoaded, isTrue);
      expect(report.activeDspStagesMask, 15);
      expect(report.autoDegradedStagesMask, 2);
      expect(report.stages.single.isSupported, isTrue);
      expect(report.stages.single.isEnabled, isFalse);
      expect(report.stages.single.parameters['1'], 'one');
    });

    test('numeric timestamp is parsed as epoch milliseconds', () {
      final report = DspDebugReport.fromMap(<dynamic, dynamic>{
        'timestamp': 1000,
      });
      expect(report.timestamp.millisecondsSinceEpoch, 1000);
    });
  });
}
