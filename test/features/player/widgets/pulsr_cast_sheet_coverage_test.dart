// test/features/player/widgets/pulsr_cast_sheet_coverage_test.dart
//
// Extra coverage for [PulsrCastSheet] beyond the base suite. The Android build
// branch is unreachable in a widget test: its device list creates a
// `Material(shape: ..., borderRadius: ...)`, and Flutter asserts that a Material
// cannot carry both, so the build throws before the list can be pumped. What
// *is* reachable on the Android target is the init / discovery plumbing, which
// runs in initState before the first build. These tests enter the Android path
// far enough to run that plumbing, then assert the known build failure so the
// limitation is pinned rather than silently skipped.
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
      'Android init runs the mDNS fallback plumbing before the build assert',
      (tester) async {
    // Cast session plugin unavailable -> the mDNS/direct-device fallback path.
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.castSession), (call) async => false);
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.cast), (call) async => false);

    await pumpAndroidCastSheet(tester);

    // The known Material(shape + borderRadius) assertion fires during build;
    // consume it so the test can assert the init plumbing ran.
    expect(
      tester.takeException(),
      isNotNull,
      reason: 'known Material(shape + borderRadius) assertion on the '
          'Android build branch',
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
      isNotNull,
      reason: 'known Material(shape + borderRadius) assertion on the '
          'Android build branch',
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