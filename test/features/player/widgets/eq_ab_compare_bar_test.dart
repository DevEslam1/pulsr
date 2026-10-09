// test/features/player/widgets/eq_ab_compare_bar_test.dart
//
// `eq_ab_compare_bar.dart` is a `part of equalizer_sheet.dart`; the A/B compare
// toggle and slot selector live in the Android-only branch of
// `EqualizerSheet.build` (guarded by `dart:io`'s `Platform.isAndroid`), so they
// cannot be mounted by a host widget test. This file pins the reachable
// fallback contract only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('EqualizerSheet fallback renders the unavailable message',
      (tester) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
      child: const EqualizerSheet(),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}