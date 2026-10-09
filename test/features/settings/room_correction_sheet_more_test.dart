// Covers the idle/fallback branches of
// lib/features/settings/presentation/widgets/room_correction_sheet.dart that
// the existing idle/permission suite does not reach: the in-flight measuring
// state, cancelling a sweep, the superseded-capture unwind and dispose's
// stopCapture guard.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/room_correction_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/room_correction_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockRoomCorrectionService extends Mock
    implements RoomCorrectionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockPlayerCubit player;
  late MockRoomCorrectionService service;
  late Completer<bool> captureGate;

  const permissionChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    captureGate = Completer<bool>();
    service = MockRoomCorrectionService();
    when(() => service.startCapture())
        .thenAnswer((_) => captureGate.future);
    when(() => service.isCapturing).thenReturn(true);
    when(() => service.stopCapture()).thenAnswer((_) async => Int16List(0));
    if (getIt.isRegistered<RoomCorrectionService>()) {
      getIt.unregister<RoomCorrectionService>();
    }
    getIt.registerSingleton<RoomCorrectionService>(service);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'requestPermissions') {
        final requested = (call.arguments as List).cast<int>();
        // microphones group granted (index 1).
        return <int, int>{for (final p in requested) p: 1};
      }
      if (call.method == 'checkPermissionStatus') return 1;
      return null;
    });
  });

  tearDown(() {
    if (getIt.isRegistered<RoomCorrectionService>()) {
      getIt.unregister<RoomCorrectionService>();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: RoomCorrectionSheet()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('measuring phase cancels back to idle and unwinds the run',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Start 3-Point Calibration'));
    // The permission round-trip resolves and the capture is now parked on the
    // open gate; the UI must be showing the in-flight measuring state.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Measuring'), findsOneWidget);

    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Start 3-Point Calibration'), findsOneWidget);

    // Completing the superseded capture must unwind silently (no error banner).
    captureGate.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Start 3-Point Calibration'), findsOneWidget);
    expect(tester.takeException(), isNull);
    verify(() => service.stopCapture()).called(greaterThanOrEqualTo(1));
  });

  testWidgets('dispose stops an active capture', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Start 3-Point Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Measuring'), findsOneWidget);

    // Tear the widget down while the capture is still "active"; dispose must
    // stop it rather than leave the mic running.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    verify(() => service.stopCapture()).called(greaterThanOrEqualTo(1));
  });
}
