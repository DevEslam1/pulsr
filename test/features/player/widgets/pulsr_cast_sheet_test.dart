// test/features/player/widgets/pulsr_cast_sheet_test.dart
//
// The Android device-list branch of [PulsrCastSheet] builds a `Material` with
// both `shape` and `borderRadius`, which trips a framework assertion in debug
// builds, so it cannot be rendered in a widget test. These tests therefore
// cover the supported non-Android notice and the static [PulsrCastSheet.show]
// modal entry point (both under a non-Android target override).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/pulsr_cast_sheet.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non-Android renders the unsupported-platform notice',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final cubit = stubPlayerCubit();

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: const PulsrCastSheet(),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cast_rounded), findsOneWidget);
    expect(find.text('Google Cast'), findsOneWidget);
    expect(
      find.text('Casting is available on Android only in this build.'),
      findsOneWidget,
    );

    // testWidgets asserts the override is unset before the body returns.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('static show opens the sheet through the modal helper',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final cubit = stubPlayerCubit();

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => PulsrCastSheet.show(context),
          child: const Text('open-cast'),
        ),
      ),
    ));

    await tester.tap(find.text('open-cast'));
    await tester.pumpAndSettle();

    expect(find.byType(PulsrCastSheet), findsOneWidget);
    expect(find.text('Google Cast'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
