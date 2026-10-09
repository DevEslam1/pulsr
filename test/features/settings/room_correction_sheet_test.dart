// Covers the widget/branch surface of
// lib/features/settings/presentation/widgets/room_correction_sheet.dart that
// the pure-SNR unit test does not reach.
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
  // PermissionStatus index: denied = 0, granted = 1.
  int micStatus = 0;

  const permissionChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    micStatus = 0;
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'requestPermissions') {
        final requested = (call.arguments as List).cast<int>();
        return <int, int>{for (final p in requested) p: micStatus};
      }
      if (call.method == 'checkPermissionStatus') return micStatus;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    bool push = false,
  }) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sheet = BlocProvider<PlayerCubit>.value(
      value: player,
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: push
            ? Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RoomCorrectionSheet(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              )
            : const Scaffold(body: RoomCorrectionSheet()),
      ),
    );

    await tester.pumpWidget(sheet);
    if (push) {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pump();
    }
  }

  testWidgets('idle sheet renders the intro, 3-point switch and start button',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text(l10n.rcTitle), findsOneWidget);
    expect(find.text(l10n.rcQuietHint), findsOneWidget);
    expect(find.text(l10n.roomAveragingTitle), findsOneWidget);
    expect(find.text('Start 3-Point Calibration'), findsOneWidget);
  });

  testWidgets('toggling averaging switches the start button label',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(l10n.rcStart), findsOneWidget);
  });

  testWidgets('denied microphone permission surfaces a clear error',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Start 3-Point Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.rcMicNeeded), findsOneWidget);
  });

  testWidgets('capture-unavailable failure surfaces the error banner',
      (tester) async {
    micStatus = 1;
    final service = MockRoomCorrectionService();
    when(() => service.startCapture()).thenAnswer((_) async => false);
    when(() => service.isCapturing).thenReturn(false);
    when(() => service.stopCapture()).thenAnswer((_) async => Int16List(0));
    if (getIt.isRegistered<RoomCorrectionService>()) {
      getIt.unregister<RoomCorrectionService>();
    }
    getIt.registerSingleton<RoomCorrectionService>(service);
    addTearDown(() {
      if (getIt.isRegistered<RoomCorrectionService>()) {
        getIt.unregister<RoomCorrectionService>();
      }
    });

    await pumpSheet(tester);

    await tester.tap(find.text('Start 3-Point Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('capture unavailable'), findsOneWidget);
    verify(() => service.startCapture()).called(1);
  });

  testWidgets('close button pops the sheet', (tester) async {
    await pumpSheet(tester, push: true);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(find.text(l10n.rcTitle), findsNothing);
  });
}
