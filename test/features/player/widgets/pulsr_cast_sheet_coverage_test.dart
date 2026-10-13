// test/features/player/widgets/pulsr_cast_sheet_coverage_test.dart
//
// Extra coverage for [PulsrCastSheet] beyond the base suite. The Android build
// branch previously threw during build because its device list created a
// `Material(shape: ..., borderRadius: ...)`; a framework assertion forbids
// carrying both (and borderRadius is ignored in release). The duplicate
// parameter has been removed, so these tests now enter the Android path, run
// the init / discovery plumbing in initState, and assert the sheet builds
// cleanly with no pending exception.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/features/player/presentation/widgets/pulsr_cast_sheet.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.castSession), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.cast), null);
  });

  Future<void> pumpAndroidCastSheet(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
      child: const PulsrCastSheet(),
    ));
    await tester.pump();
  }

  testWidgets('non-Android shows the Android-only notice without init',
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
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'Android init runs the mDNS fallback plumbing and the sheet builds',
      (tester) async {
    // Cast session plugin unavailable -> the mDNS/direct-device fallback path.
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.castSession), (call) async => false);
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.cast), (call) async => false);

    await pumpAndroidCastSheet(tester);

    // The former Material(shape + borderRadius) build assertion is fixed;
    // the sheet must build with no pending exception.
    expect(
      tester.takeException(),
      isNull,
      reason: 'the Android build branch must build cleanly',
    );

    // Tear the tree down so the 8s scan-timeout timer is cancelled.
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Android init takes the SDK route when a session is available',
      (tester) async {
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.castSession),
      (call) async {
        if (call.method == 'isAvailable') return true;
        return null;
      },
    );

    await pumpAndroidCastSheet(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'the Android build branch must build cleanly',
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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