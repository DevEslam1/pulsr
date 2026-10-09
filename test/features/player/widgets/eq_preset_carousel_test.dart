// test/features/player/widgets/eq_preset_carousel_test.dart
//
// `eq_preset_carousel.dart` is a `part of equalizer_sheet.dart`; its preset
// carousel / dialog helpers are only reachable from the Android-only branch of
// `EqualizerSheet.build` (guarded by `dart:io`'s `Platform.isAndroid`). This
// file pins the reachable contract on the host: the sheet's `show` entry point
// can be invoked and dismissed without throwing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('EqualizerSheet.show opens and dismisses a sheet route',
      (tester) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => EqualizerSheet.show(ctx),
          child: const Text('open-eq'),
        ),
      ),
    ));

    await tester.tap(find.text('open-eq'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EqualizerSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}