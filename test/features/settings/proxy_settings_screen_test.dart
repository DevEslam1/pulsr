import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/proxy_settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSettingsCubit mockSettingsCubit;
  late StreamController<SettingsState> stateController;

  setUp(() {
    mockSettingsCubit = MockSettingsCubit();
    stateController = StreamController<SettingsState>.broadcast();

    const initialState = SettingsState(
      proxyEnabled: true,
      proxyHost: '1.2.3.4',
      proxyPort: 8080,
      hasProxyPassword: true,
    );

    when(() => mockSettingsCubit.state).thenReturn(initialState);
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => stateController.stream);
    when(() => mockSettingsCubit.getProxyPassword())
        .thenAnswer((_) async => 'secret123');
  });

  tearDown(() {
    stateController.close();
  });

  testWidgets(
      '[M-07] _syncControllersWithState synchronizes password on state updates',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: mockSettingsCubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProxySettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify initial password populated from secure storage
    final passwordFieldFinder = find.widgetWithText(TextFormField, 'secret123');
    expect(passwordFieldFinder, findsOneWidget);

    // Now emit state where hasProxyPassword is false (e.g. proxy cleared or switched)
    when(() => mockSettingsCubit.getProxyPassword())
        .thenAnswer((_) async => '');
    stateController.add(const SettingsState(
      proxyEnabled: true,
      proxyHost: '1.2.3.4',
      proxyPort: 8080,
      hasProxyPassword: false,
    ));

    await tester.pumpAndSettle();

    // Password field should now be cleared
    final clearedFieldFinder = find.widgetWithText(TextFormField, 'secret123');
    expect(clearedFieldFinder, findsNothing);
  });
}
