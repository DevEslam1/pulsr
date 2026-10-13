// Regression: the settings search field must stay focused and keep its text
// input connection when the on-screen keyboard opens (viewInsets.bottom > 0).
//
// Previously `_buildTopHeader` swapped to a structurally different subtree
// when the keyboard opened, which recreated the field and closed the
// keyboard instantly — making settings search impossible to type into on
// phones.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(stubSettingsChannels);
  tearDown(clearSettingsChannels);

  Widget buildScreen(
    SettingsCubit cubit,
    PlayerCubit player,
    AuthCubit auth, {
    required double keyboard,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: cubit),
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<AuthCubit>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        locale: const Locale('en'),
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

  Future<void> pumpSettings(
    WidgetTester tester,
    SettingsCubit cubit,
    PlayerCubit player,
    AuthCubit auth, {
    required Size size,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
        buildScreen(cubit, player, auth, keyboard: keyboard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
  }

  ({SettingsCubit cubit, MockPlayerCubit player, MockAuthCubit auth})
      buildCubits(WidgetTester tester) {
    final scanner = MockMediaScannerService();
    final player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream).thenAnswer((_) => const Stream.empty());
    final auth = MockAuthCubit();
    when(() => auth.state).thenReturn(const AuthState());
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    final cubit = SettingsCubit(scannerService: scanner);
    addTearDown(cubit.close);
    return (cubit: cubit, player: player, auth: auth);
  }

  bool hasSearchFocus(WidgetTester tester) => tester
      .widget<EditableText>(find.byType(EditableText).first)
      .focusNode
      .hasFocus;

  testWidgets(
      'portrait: focus survives the keyboard opening and typing filters settings',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    SettingsScreenController.resetSessionCategory();
    final h = buildCubits(tester);

    await pumpSettings(tester, h.cubit, h.player, h.auth,
        size: const Size(390, 844));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(hasSearchFocus(tester), isTrue,
        reason: 'tapping the search field should focus it');
    expect(tester.testTextInput.isVisible, isTrue);

    // The keyboard animates open -> viewInsets.bottom > 0.
    await pumpSettings(tester, h.cubit, h.player, h.auth,
        size: const Size(390, 844), keyboard: 844 * 0.35);

    expect(hasSearchFocus(tester), isTrue,
        reason: 'search must keep focus when the keyboard opens');
    expect(tester.testTextInput.isVisible, isTrue,
        reason: 'the text-input connection must survive the inset change');

    // Typing filters settings live (300 ms debounce).
    await tester.enterText(find.byType(TextField).first, 'crossfade');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(
          of: find.byType(ListTile),
          matching: find.text(l10n.settingsSearchCrossfadeTitle)),
      findsOneWidget,
    );

    // Clearing returns to the category view.
    await tester.tap(find.descendant(
        of: find.byType(TextField),
        matching: find.byIcon(Icons.clear_rounded)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.settingsSearchCrossfadeTitle), findsNothing);
    expect(find.text(l10n.all), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact landscape: focus survives the keyboard opening',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    SettingsScreenController.resetSessionCategory();
    final h = buildCubits(tester);

    await pumpSettings(tester, h.cubit, h.player, h.auth,
        size: const Size(844, 390));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(hasSearchFocus(tester), isTrue);

    await pumpSettings(tester, h.cubit, h.player, h.auth,
        size: const Size(844, 390), keyboard: 390 * 0.35);

    expect(hasSearchFocus(tester), isTrue,
        reason: 'compact search must keep focus when the keyboard opens');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });
}
