// test/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_hero_card.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockAuthCubit extends Mock implements AuthCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaScannerService mockScanner;
  late MockPlayerCubit mockPlayerCubit;
  late MockAuthCubit mockAuthCubit;
  late SettingsCubit settingsCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDac),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        if (call.method == 'setSystemEffectsPolicy') {
          return <String, dynamic>{
            'status': 'unsupportedDevice',
            'detectedBundles': <String>[],
          };
        }
        return null;
      },
    );

    mockScanner = MockMediaScannerService();
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());

    mockAuthCubit = MockAuthCubit();
    when(() => mockAuthCubit.state).thenReturn(const AuthState());
    when(() => mockAuthCubit.stream).thenAnswer((_) => const Stream.empty());

    settingsCubit = SettingsCubit(scannerService: mockScanner);
  });

  tearDown(() {
    settingsCubit.close();
  });

  Widget buildTestScreen() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        BlocProvider<AuthCubit>.value(value: mockAuthCubit),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    );
  }

  // NOTE: these tests use fixed pumps instead of pumpAndSettle because the
  // search TextField's InputDecorator/EditableText tickers stay warm in the
  // test env and never settle (ambient framework animation, not an app bug —
  // the screen renders and behaves correctly; verified via TickerMode probe).
  // A phone surface (400x800) forces the phone layout: the default 800x600
  // test viewport hits the >=720 tablet breakpoint (master-detail without
  // the 'all' hero card these tests assert).
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildTestScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settleAnims(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Redesigned SettingsScreen UI', () {
    testWidgets('renders header, search bar, category pills, and hero card',
        (tester) async {
      await pumpScreen(tester);

      // Header title and search box
      expect(find.text('Settings'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search settings, sound, appearance...'), findsOneWidget);

      // Hero Account / Cloud card
      expect(find.byType(SettingsHeroCard), findsOneWidget);

      // Category filter pills (row is lazily built: scroll to reveal later pills)
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Audio & Sound'), findsWidgets);
      expect(find.text('Playback'), findsWidgets);
      final pillsRow = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      );
      expect(pillsRow, findsOneWidget);
      for (var i = 0;
          i < 6 && find.text('Appearance').evaluate().isEmpty;
          i++) {
        await tester.drag(pillsRow, const Offset(-320, 0));
        await settleAnims(tester);
      }
      expect(find.text('Appearance'), findsWidgets);
    });

    testWidgets('live search filters settings correctly and displays category badge',
        (tester) async {
      await pumpScreen(tester);

      // Enter search query "crossfade"
      await tester.enterText(find.byType(TextField), 'crossfade');
      await settleAnims(tester);

      // Category filter row is hidden during search mode
      expect(find.text('All'), findsNothing);

      // Search result item appears
      expect(find.text('Crossfade & Gapless'), findsOneWidget);
      expect(find.text('PLAYBACK'), findsOneWidget);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await settleAnims(tester);

      // Category row restored
      expect(find.text('All'), findsOneWidget);
    });

    testWidgets('empty search shows helpful empty state', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'xyznonexistent123');
      await settleAnims(tester);

      expect(find.text('No settings found for "xyznonexistent123"'), findsOneWidget);
    });

    testWidgets('tapping category filter changes active category', (tester) async {
      await pumpScreen(tester);

      // Tap "Playback" category filter pill
      final playbackPill = find.widgetWithText(GestureDetector, 'Playback');
      expect(playbackPill, findsOneWidget);
      await tester.tap(playbackPill);
      await settleAnims(tester);

      // Only playback section is visible in filtered mode (scroll: lazy list)
      for (var i = 0;
          i < 8 && find.text('PLAYBACK').evaluate().isEmpty;
          i++) {
        await tester.dragFrom(
            const Offset(200, 500), const Offset(0, -500));
        await settleAnims(tester);
      }
      expect(find.text('PLAYBACK'), findsWidgets);
    });
  });
}
