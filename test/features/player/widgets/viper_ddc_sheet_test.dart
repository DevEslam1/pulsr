// test/features/player/widgets/viper_ddc_sheet_test.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/viper_ddc_sheet.dart';

import 'player_sheet_test_support.dart';

Uint8List _float32(List<double> values) {
  final bd = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    bd.setFloat32(i * 4, values[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViperDdcParser', () {
    test('validateFilterStability uses the Jury criterion', () {
      expect(ViperDdcParser.validateFilterStability(0.5, 0.4), isTrue);
      expect(ViperDdcParser.validateFilterStability(0.0, 1.5), isFalse);
      expect(ViperDdcParser.validateFilterStability(3.0, 0.4), isFalse);
    });

    test('rejects files that are too short', () {
      expect(
        () => ViperDdcParser.parseBytes(Uint8List.fromList([1, 2])),
        throwsA(isA<String>()),
      );
    });

    test('parses comma-separated text biquad stages', () {
      final bytes = Uint8List.fromList(
        '1, 2, 3, -0.5, 0.1\r\n'.codeUnits,
      );
      final coeffs = ViperDdcParser.parseBytes(bytes);
      expect(coeffs, [1.0, 1.0, 2.0, 3.0, -0.5, 0.1]);
    });

    test('parses ###-delimited text blocks and skips comments', () {
      const text = '# a comment\n'
          '###\n'
          '1 2 3 -0.5 0.1\n'
          '###\n'
          '1 2 3 -0.4 0.2\n';
      final coeffs = ViperDdcParser.parseText(text);
      expect(coeffs.first, 1.0);
      expect(coeffs.length, 12);
    });

    test('rejects an unstable text stage', () {
      expect(
        () => ViperDdcParser.parseText('1 2 3 0 1.5\n'),
        throwsA(isA<String>()),
      );
    });

    test('rejects text with no valid coefficients', () {
      expect(
        () => ViperDdcParser.parseText('# only comments\n'),
        throwsA(isA<String>()),
      );
    });

    test('parses a valid binary coefficient block', () {
      final coeffs = ViperDdcParser.parseBytes(
        _float32([1.0, -0.5, 0.2, -0.5, 0.1]),
      );
      expect(coeffs, hasLength(5));
      expect(coeffs[0], closeTo(1.0, 0.0001));
    });

    test('rejects corrupt binary coefficients', () {
      expect(
        () => ViperDdcParser.parseBytes(
          _float32([20000.0, 1.0, 1.0, -0.5, 0.1]),
        ),
        throwsA(isA<String>()),
      );
    });

    test('rejects unstable binary coefficients', () {
      expect(
        () => ViperDdcParser.parseBytes(
          _float32([1.0, 1.0, 1.0, 0.0, 1.5]),
        ),
        throwsA(isA<String>()),
      );
    });

    test('rejects an invalid binary coefficient structure', () {
      expect(
        () => ViperDdcParser.parseBytes(
          _float32([1.0, 1.0, 1.0, -0.5, 0.1, 0.1, 0.2]),
        ),
        throwsA(isA<String>()),
      );
    });
  });

  group('ViperDdcSheet widget', () {
    MockPlayerCubit buildCubit({
      bool enabled = false,
      String profileName = '',
    }) {
      final cubit = stubPlayerCubit(
        state: PlayerState(
          dsp: DspSlice(
            isViperDdcEnabled: enabled,
            viperDdcProfileName: profileName,
          ),
        ),
      );
      when(() => cubit.setViperDdcEnabled(
            any(),
            profileName: any(named: 'profileName'),
            coeffs: any(named: 'coeffs'),
          )).thenAnswer((_) async {});
      when(() => cubit.setViperDdcEnabled(any())).thenAnswer((_) async {});
      return cubit;
    }

    testWidgets('renders profiles, toggles and selects a profile',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cubit = buildCubit();

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ViPER-DDC'), findsOneWidget);
      expect(find.text('Sennheiser HD650 Flat Neutral'), findsOneWidget);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

      // Enable switch.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(() => cubit.setViperDdcEnabled(any())).called(1);

      // Select a built-in profile.
      await tester.tap(find.text('Sony WH-1000XM4 Clarity Lift'));
      await tester.pump();
      verify(() => cubit.setViperDdcEnabled(
            true,
            profileName: any(named: 'profileName'),
            coeffs: any(named: 'coeffs'),
          )).called(1);

      // A/B compare toggles and shows a snackbar.
      await tester.tap(find.text('A/B Compare'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('renders the active profile name when set', (tester) async {
      final cubit = buildCubit(
        enabled: true,
        profileName: 'Sennheiser HD650 Flat Neutral',
      );
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Active Profile'), findsOneWidget);
      // Name appears in the header card and in the profile list.
      expect(
        find.text('Sennheiser HD650 Flat Neutral'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Active'), findsAtLeastNWidgets(1));
    });

    testWidgets('opening a VDC file reports failure when no picker exists',
        (tester) async {
      final cubit = buildCubit();
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open .vdc'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
