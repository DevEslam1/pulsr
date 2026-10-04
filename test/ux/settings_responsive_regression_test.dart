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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(PulsrChannels.hiresDacEvents),
            (call) async => null);
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

  Widget buildTestScreen(double textScale, Locale locale, double keyboard) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
        BlocProvider<AuthCubit>.value(value: mockAuthCubit),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        locale: locale,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    );
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(800, 1280),
    const Size(1280, 800)
  ]) {
    for (final locale in [
      const Locale('en'),
      const Locale('ar'),
      const Locale('es')
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'settings $size ${locale.languageCode} text $scale and keyboard',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await (FontLoader('Manrope')
                ..addFont(rootBundle
                    .load('assets/fonts/Manrope-VariableFont_wght.ttf')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await tester.pumpWidget(buildTestScreen(scale, locale, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(tester.takeException(), isNull);
          await tester.enterText(find.byType(TextField), 'crossfade');
          await tester
              .pumpWidget(buildTestScreen(scale, locale, size.height * .35));
          await tester.pump(const Duration(milliseconds: 350));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
