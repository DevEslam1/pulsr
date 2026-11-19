// test/data/audio/autoeq_parametric_parser_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/audio/autoeq_parametric_parser.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

/// Real AutoEQ file shape: ten filters, mixed peaking/shelf types, a preamp
/// and one disabled filter. The filter values are representative of an
/// HD 600-style correction; they are not copied measurements.
const String _hd600Style = '''
Preamp: -6.2 dB
Filter 1: ON PK Fc 21 Hz Gain 5.9 dB Q 0.71
Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 3: ON PK Fc 109 Hz Gain -1.4 dB Q 2.49
Filter 4: ON PK Fc 181 Hz Gain -2.0 dB Q 1.41
Filter 5: ON PK Fc 1837 Hz Gain -2.7 dB Q 1.25
Filter 6: ON PK Fc 3032 Hz Gain 2.2 dB Q 1.12
Filter 7: ON PK Fc 4291 Hz Gain -1.8 dB Q 2.13
Filter 8: ON PK Fc 6700 Hz Gain 0.9 dB Q 3.00
Filter 9: ON HSC Fc 10000 Hz Gain -1.5 dB Q 0.70
Filter 10: OFF PK Fc 1000 Hz Gain 0.0 dB Q 1.00
''';

void main() {
  group('AutoEqParametricParser.parse', () {
    test('parses a real ten-filter profile in file order', () {
      final profile = AutoEqParametricParser.parse(_hd600Style);

      expect(profile, isNotNull);
      final parsed = profile!;
      expect(parsed.preampDb, -6.2);
      expect(parsed.bands.length, 10);
      expect(parsed.warnings, isEmpty);
      expect(parsed.bands.map((band) => band.filterIndex),
          [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(parsed.bands.first.frequencyHz, 21);
      expect(parsed.bands.first.gainDb, 5.9);
      expect(parsed.bands.first.q, 0.71);
      expect(parsed.bands[1].kind, EqFilterKind.lowShelf);
      expect(parsed.bands[8].kind, EqFilterKind.highShelf);
      expect(parsed.bands[9].enabled, isFalse);
      expect(parsed.enabledBands.length, 9);
    });

    test('maps to EqPreset preserving order and dropping disabled filters', () {
      final parsed = AutoEqParametricParser.parse(_hd600Style)!;
      final EqPreset preset = AutoEqParametricParser.toPreset(parsed);

      expect(preset.name, AutoEqParametricParser.defaultProfileName);
      expect(preset.gains,
          [5.9, 5.5, -1.4, -2.0, -2.7, 2.2, -1.8, 0.9, -1.5]);
      expect(preset.customFrequencies,
          [21, 105, 109, 181, 1837, 3032, 4291, 6700, 10000]);
      expect(preset.qFactors,
          [0.71, 0.70, 2.49, 1.41, 1.25, 1.12, 2.13, 3.00, 0.70]);
      expect(parsed.warnings, isEmpty);
    });

    test('parses Fc in kHz with or without a space', () {
      const text = '''
Preamp: 0 dB
Filter 1: ON PK Fc 1.2 kHz Gain -2.0 dB Q 3.0
Filter 2: ON PK Fc 10.5kHz Gain 1.0 dB Q 1.0
Filter 3: ON HP Fc 20 Hz Q 0.707
''';
      final parsed = AutoEqParametricParser.parse(text)!;

      expect(parsed.bands[0].frequencyHz, 1200);
      expect(parsed.bands[1].frequencyHz, 10500);
      expect(parsed.bands[2].frequencyHz, 20);
      expect(parsed.bands[2].kind, EqFilterKind.highPass);
      expect(parsed.warnings, isEmpty);
    });

    test('converts BW Oct to Q in both argument orders', () {
      const text = '''
Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB BW Oct 1.0
Filter 2: ON PK Fc 2000 Hz Gain -1.0 dB BW 0.5 Oct
''';
      final parsed = AutoEqParametricParser.parse(text)!;

      expect(parsed.bands[0].q, closeTo(1.41421356, 1e-8));
      expect(parsed.bands[1].q, closeTo(2.871, 1e-3));
      expect(AutoEqParametricParser.qFromBandwidthOctaves(1.0),
          closeTo(1.41421356, 1e-8));
      expect(AutoEqParametricParser.qFromBandwidthOctaves(0.5),
          closeTo(2.871, 1e-3));
      expect(AutoEqParametricParser.qFromBandwidthOctaves(0), 1.414);
      expect(AutoEqParametricParser.qFromBandwidthOctaves(double.nan), 1.414);
    });

    test('warns about malformed lines instead of throwing', () {
      const text = '''
Preamp: -3 dB
Filter 1: ON PK Fc 100 Hz Gain 2.0 dB Q 1.0
Filter 2: ON PK Gain 5.5 dB Q 1.0
Filter 3: ON XYZ Fc 300 Hz Gain 1.0 dB Q 1.0
Filter x: ON PK Fc 400 Hz Gain 1.0 dB Q 1.0
this line is not autoeq data
Filter 4: ON LSC Fc 500 Hz Gain 1.5 dB Q 0.7
''';
      final parsed = AutoEqParametricParser.parse(text)!;

      expect(parsed.bands.length, 2);
      expect(parsed.bands.map((band) => band.filterIndex), [1, 4]);
      expect(parsed.warnings.any((w) => w.contains('no "Fc"')), isTrue);
      expect(
        parsed.warnings.any((w) => w.contains('unsupported filter type "xyz"')),
        isTrue,
      );
      expect(parsed.warnings.any((w) => w.contains('unrecognised line')),
          isTrue);
    });

    test('clamps out-of-range values and reports each clamp', () {
      const text = '''
Preamp: -20 dB
Filter 1: ON PK Fc 30000 Hz Gain 40 dB Q 100
''';
      final parsed = AutoEqParametricParser.parse(text)!;
      final band = parsed.bands.single;

      expect(parsed.preampDb, -15.0);
      expect(band.frequencyHz, 24000);
      expect(band.gainDb, 24);
      expect(band.q, 30);
      expect(parsed.warnings.any((w) => w.contains('preamp -20 dB')), isTrue);
      expect(parsed.warnings.any((w) => w.contains('24000 Hz')), isTrue);
      expect(parsed.warnings.any((w) => w.contains('gain 40 dB')), isTrue);
      expect(parsed.warnings.any((w) => w.contains('Q 100')), isTrue);
    });

    test('caps the preset at 64 bands with an explicit warning', () {
      final buffer = StringBuffer('Preamp: -6 dB\n');
      for (var i = 1; i <= 70; i++) {
        buffer.writeln(
            'Filter $i: ON PK Fc ${20 + i * 200} Hz Gain 1.0 dB Q 1.0');
      }
      final parsed = AutoEqParametricParser.parse(buffer.toString())!;

      expect(parsed.bands.length, 70);
      expect(AutoEqParametricParser.maxBands, 64);
      final preset = AutoEqParametricParser.toPreset(parsed);
      expect(preset.gains.length, 64);
      expect(preset.customFrequencies!.length, 64);
      expect(preset.qFactors!.length, 64);
      expect(parsed.warnings.any((w) => w.contains('70 usable bands')), isTrue);
      expect(parsed.warnings.any((w) => w.contains('64')), isTrue);
    });

    test('returns null for empty, blank and comment-only input', () {
      expect(AutoEqParametricParser.parse(''), isNull);
      expect(AutoEqParametricParser.parse('   \n\n\t  '), isNull);
      expect(
        AutoEqParametricParser.parse('# comment\n// another comment\n\n'),
        isNull,
      );
    });

    test('throws the typed failure when content is wholly unparseable', () {
      expect(
        () => AutoEqParametricParser.parse('hello world\nnot an autoeq file'),
        throwsA(
          isA<AutoEqParametricParseFailure>().having(
            (failure) => failure.code,
            'code',
            'AUTOEQ_PARAMETRIC_PARSE_FAILURE',
          ),
        ),
      );
      expect(
        () => AutoEqParametricParser.parse('hello world'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('a preamp-only file parses with no bands and says so', () {
      final parsed = AutoEqParametricParser.parse('Preamp: -3.0 dB')!;

      expect(parsed.bands, isEmpty);
      expect(parsed.preampDb, -3.0);
      expect(parsed.warnings.any((w) => w.contains('no EQ bands')), isTrue);

      final preset = AutoEqParametricParser.toPreset(parsed);
      expect(preset.gains, isEmpty);
      expect(preset.customFrequencies, isNull);
      expect(preset.qFactors, isNull);
      expect(
        parsed.warnings.any((w) => w.contains('no usable EqPreset bands')),
        isTrue,
      );
    });

    test('warns when no filter state, duplicate index or shelf slope is seen',
        () {
      const missingState = 'Filter 1: PK Fc 100 Hz Gain 1.0 dB Q 1.0';
      final stateProfile = AutoEqParametricParser.parse(missingState)!;
      expect(stateProfile.bands.single.enabled, isTrue);
      expect(
        stateProfile.warnings.any((w) => w.contains('state is missing')),
        isTrue,
      );

      const duplicate = '''
Filter 1: ON PK Fc 100 Hz Gain 1.0 dB Q 1.0
Filter 1: ON PK Fc 1000 Hz Gain 2.0 dB Q 1.0
''';
      final duplicateProfile = AutoEqParametricParser.parse(duplicate)!;
      expect(duplicateProfile.bands.length, 2);
      expect(
        duplicateProfile.warnings.any((w) => w.contains('duplicate filter')),
        isTrue,
      );

      const slope = 'Filter 1: ON LS 6dB Fc 100 Hz Gain 5.0 dB Q 0.7';
      final slopeProfile = AutoEqParametricParser.parse(slope)!;
      expect(slopeProfile.bands.single.kind, EqFilterKind.lowShelf);
      expect(slopeProfile.bands.single.frequencyHz, 100);
      expect(
        slopeProfile.warnings.any((w) => w.contains('shelf slope')),
        isTrue,
      );
    });

    test('pass, notch and band-pass filters are dropped from EqPreset', () {
      const text = '''
Preamp: 0 dB
Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.0
Filter 2: ON HP Fc 20 Hz Q 0.707
Filter 3: ON NO Fc 6000 Hz Q 4.0
Filter 4: ON BP Fc 2000 Hz BW Oct 1.0
''';
      final parsed = AutoEqParametricParser.parse(text)!;
      expect(parsed.bands.length, 4);

      final preset = AutoEqParametricParser.toPreset(parsed);
      expect(preset.gains, [3.0]);
      expect(preset.customFrequencies, [1000]);
      expect(preset.qFactors, [1.0]);
      for (final label in ['high pass', 'notch', 'band pass']) {
        expect(
          parsed.warnings.any((w) => w.contains(label)),
          isTrue,
          reason: 'expected a warning mentioning "$label"',
        );
      }
    });

    test('toHeadphoneProfile keeps every filter type', () {
      const text = '''
Preamp: -4.0 dB
Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.0
Filter 2: ON HP Fc 20 Hz Q 0.707
Filter 3: ON NO Fc 6000 Hz Q 4.0
Filter 4: ON BP Fc 2000 Hz BW Oct 1.0
''';
      final parsed = AutoEqParametricParser.parse(text)!;
      final profile = AutoEqParametricParser.toHeadphoneProfile(parsed);

      expect(profile.filters.length, 4);
      expect(profile.filters.map((filter) => filter.filterType), [0, 4, 5, 6]);
      expect(profile.filters[1].frequency, 20);
      expect(profile.preampGain, -4.0);
      expect(profile.hasParametricFilters, isTrue);
      expect(profile.source, 'AutoEQ ParametricEQ');
      // `custom_` is what HeadphoneProfilesRepository persists; the AutoEQ
      // origin is carried by `source`, not by the id prefix.
      expect(profile.id, startsWith('custom_autoeq_'));
      expect(profile.gains, isEmpty);
      expect(profile.filters, isNotEmpty);
    });

    test('warns when filter frequencies are not ascending', () {
      const text = '''
Filter 1: ON PK Fc 2000 Hz Gain 1.0 dB Q 1.0
Filter 2: ON PK Fc 100 Hz Gain 1.0 dB Q 1.0
''';
      final parsed = AutoEqParametricParser.parse(text)!;
      AutoEqParametricParser.toPreset(parsed);

      expect(
        parsed.warnings.any((w) => w.contains('not strictly ascending')),
        isTrue,
      );
    });

    test('warnings are exposed as an unmodifiable view', () {
      final parsed = AutoEqParametricParser.parse(_hd600Style)!;
      expect(() => parsed.warnings.add('nope'), throwsUnsupportedError);
    });

    test('filter kinds use the native DspParams.h ordinals', () {
      expect(EqFilterKind.peaking.nativeIndex, 0);
      expect(EqFilterKind.lowShelf.nativeIndex, 1);
      expect(EqFilterKind.highShelf.nativeIndex, 2);
      expect(EqFilterKind.lowPass.nativeIndex, 3);
      expect(EqFilterKind.highPass.nativeIndex, 4);
      expect(EqFilterKind.notch.nativeIndex, 5);
      expect(EqFilterKind.bandPass.nativeIndex, 6);
      expect(EqFilterKind.allPass.nativeIndex, 7);
    });

    test('derives display names from profile paths', () {
      expect(
        AutoEqParametricParser.profileNameFromPath(
            r'C:\AutoEq\Sony WH-1000XM4 ParametricEQ.txt'),
        'Sony WH-1000XM4',
      );
      expect(
        AutoEqParametricParser.profileNameFromPath(
            '/tmp/AKG K371_Parametric EQ.txt'),
        'AKG K371',
      );
      expect(
        AutoEqParametricParser.profileNameFromPath('/tmp/Sennheiser HD 600.txt'),
        'Sennheiser HD 600',
      );
    });
  });

  group('AutoEqParametricParser.parseFile', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('autoeq_parametric_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('tolerates BOM, CRLF and comment lines', () async {
      final file = File(
          '${directory.path}${Platform.pathSeparator}'
          'Sennheiser HD 600 ParametricEQ.txt');
      const content = '\uFEFF# exported by AutoEQ\r\n'
          '// reference correction\r\n'
          '\r\n'
          'Preamp: -6.2 dB\r\n'
          'Filter 1: ON PK Fc 21 Hz Gain 5.9 dB Q 0.71\r\n'
          'Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70\r\n';
      await file.writeAsBytes(utf8.encode(content), flush: true);

      final parsed = await AutoEqParametricParser.parseFile(file);

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Sennheiser HD 600');
      expect(parsed.preampDb, -6.2);
      expect(parsed.bands.length, 2);
      expect(parsed.warnings, isEmpty);
    });

    test('returns null for a comment-only file', () async {
      final file = File('${directory.path}${Platform.pathSeparator}empty.txt');
      await file.writeAsString('# nothing here\r\n// still nothing\r\n');

      expect(await AutoEqParametricParser.parseFile(file), isNull);
    });

    test('throws the typed failure for unparseable file content', () async {
      final file = File('${directory.path}${Platform.pathSeparator}bad.txt');
      await file.writeAsString('not an AutoEQ profile at all\n');

      await expectLater(
        AutoEqParametricParser.parseFile(file),
        throwsA(isA<AutoEqParametricParseFailure>()),
      );
    });
  });
}
