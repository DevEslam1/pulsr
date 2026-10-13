// TEMPORARY audit capture test (not part of the repo test suite).
// Renders the real SettingsScreen across categories/layouts and writes PNGs
// under test/audit_captures/ for visual review (run with --update-goldens).
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
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}
class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockAuthCubit extends Mock implements AuthCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('Manrope')
          ..addFont(
              rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDac),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDacEvents),
      (call) async => null,
    );
  });

  Widget buildScreen(SettingsCubit cubit, PlayerCubit player, AuthCubit auth) {
    return RepaintBoundary(
      key: const ValueKey('capture-root'),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: cubit),
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<AuthCubit>.value(value: auth),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AuraTheme.darkTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
  }

  Future<void> capture(
    WidgetTester tester,
    String name, {
    required String category,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(
        {'settings_last_selected_category': category});
    SettingsScreenController.resetSessionCategory();

    final scanner = MockMediaScannerService();
    final player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream).thenAnswer((_) => const Stream.empty());
    final auth = MockAuthCubit();
    when(() => auth.state).thenReturn(const AuthState());
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    final cubit = SettingsCubit(scannerService: scanner);

    await tester.pumpWidget(buildScreen(cubit, player, auth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byKey(const ValueKey('capture-root')),
      matchesGoldenFile('audit_captures/$name.png'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  }

  final cases = <(String, String, Size)>[
    ('phone_dashboard', 'all', const Size(390, 1400)),
    ('phone_sound', 'sound', const Size(390, 2400)),
    ('phone_look', 'look', const Size(390, 2400)),
    ('phone_library', 'library', const Size(390, 2400)),
    ('phone_network', 'network', const Size(390, 2400)),
    ('phone_privacy', 'privacy', const Size(390, 2400)),
    ('phone_about', 'about', const Size(390, 2400)),
    ('tablet_sound', 'sound', const Size(1280, 800)),
  ];

  for (final (name, category, size) in cases) {
    testWidgets('capture $name', (tester) async {
      await capture(tester, name, category: category, size: size);
    });
  }

  testWidgets('capture phone_search_results', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    SettingsScreenController.resetSessionCategory();
    final scanner = MockMediaScannerService();
    final player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream).thenAnswer((_) => const Stream.empty());
    final auth = MockAuthCubit();
    when(() => auth.state).thenReturn(const AuthState());
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    final cubit = SettingsCubit(scannerService: scanner);

    await tester.pumpWidget(buildScreen(cubit, player, auth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField), 'crossfade');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byKey(const ValueKey('capture-root')),
      matchesGoldenFile('audit_captures/phone_search_results.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });
}
