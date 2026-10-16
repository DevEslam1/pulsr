// TEMPORARY diagnostic probe (not part of the repo test suite).
// Verifies whether the settings search field keeps focus and its text-input
// connection when the on-screen keyboard opens (viewInsets.bottom > 0), which
// swaps _buildTopHeader to its compact subtree in the real screen.
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
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(PulsrChannels.hiresDac), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(PulsrChannels.audioEffects), null);
  });

  Widget buildScreen(SettingsCubit cubit, PlayerCubit player, AuthCubit auth,
      {required double keyboard, Locale locale = const Locale('en')}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: cubit),
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<AuthCubit>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('probe: focus + text connection across keyboard open',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
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
    addTearDown(cubit.close);

    await tester.pumpWidget(buildScreen(cubit, player, auth, keyboard: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 1. Tap the search field.
    final tf = find.byType(TextField);
    expect(tf, findsOneWidget);
    await tester.tap(tf);
    await tester.pump();

    bool hasFocus() => tester
        .widget<EditableText>(find.byType(EditableText).first)
        .focusNode
        .hasFocus;

    debugPrint('PROBE focus-after-tap=${hasFocus()} '
        'connection=${tester.testTextInput.isVisible}');

    // 2. Keyboard animates open -> viewInsets.bottom > 0 -> subtree swap.
    await tester
        .pumpWidget(buildScreen(cubit, player, auth, keyboard: 844 * 0.35));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    debugPrint('PROBE focus-after-keyboard=${hasFocus()} '
        'connection=${tester.testTextInput.isVisible}');

    // 3. Can we still type into the (recreated) field?
    await tester.enterText(find.byType(TextField).first, 'crossfade');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('PROBE query-after-enter="${tester.widget<TextField>(
              find.byType(TextField).first,
            ).controller?.text}" '
        'results=${find.byType(ListTile).evaluate().length} tiles');

    // 4. Keyboard closes.
    await tester.pumpWidget(buildScreen(cubit, player, auth, keyboard: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    debugPrint('PROBE focus-after-keyboard-close=${hasFocus()} '
        'connection=${tester.testTextInput.isVisible}');
  });
}
