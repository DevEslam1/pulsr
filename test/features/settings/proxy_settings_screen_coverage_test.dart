// Extra coverage for lib/features/settings/presentation/proxy_settings_screen.dart
// (the existing proxy_settings_screen_test.dart only asserts password sync).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/network/proxy_config.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/proxy_settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockSettingsCubit cubit;

  setUp(() {
    registerFallbackValue(const ProxyConfig());
    registerFallbackValue(AppProxyType.http);
    registerFallbackValue(const ProxyEntry(id: 'x', host: 'h', port: 1));
    cubit = MockSettingsCubit();
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => cubit.getProxyPassword()).thenAnswer((_) async => '');
    when(() => cubit.setProxyEnabled(any())).thenAnswer((_) async {});
    when(() => cubit.setProxySettings(
          enabled: any(named: 'enabled'),
          type: any(named: 'type'),
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          bypassHosts: any(named: 'bypassHosts'),
        )).thenAnswer((_) async {});
    when(() => cubit.importProxiesFromText(any()))
        .thenAnswer((_) async => 2);
    when(() => cubit.clearProxyList()).thenAnswer((_) async {});
    when(() => cubit.testAllProxies()).thenAnswer((_) async {});
    when(() => cubit.sortProxiesByLatency()).thenAnswer((_) async {});
    when(() => cubit.selectProxyEntry(any())).thenAnswer((_) async {});
    when(() => cubit.testSingleProxyEntry(any())).thenAnswer((_) async {});
    when(() => cubit.removeProxyEntry(any())).thenAnswer((_) async {});
  });

  void stubState(SettingsState state) {
    when(() => cubit.state).thenReturn(state);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProxySettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('renders the master switch, protocol and config sections',
      (tester) async {
    stubState(const SettingsState());
    await pump(tester);

    expect(find.text(l10n.enableProxy), findsOneWidget);
    expect(find.text(l10n.settingsDisabledBadge), findsOneWidget);
    expect(find.text(l10n.settingsActiveProxyProtocol), findsOneWidget);
    expect(find.text(l10n.settingsActiveServerConfig), findsOneWidget);
    expect(find.text(l10n.settingsAuthenticationOptional), findsOneWidget);
    expect(find.text(l10n.proxyBypass), findsOneWidget);
    expect(find.text(l10n.quickPresets), findsOneWidget);
    expect(find.text(l10n.testProxy), findsOneWidget);
  });

  testWidgets('master switch and protocol selector update controls',
      (tester) async {
    stubState(const SettingsState(proxyEnabled: true));
    await pump(tester);

    expect(find.text(l10n.settingsActiveBadge), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    verify(() => cubit.setProxyEnabled(false)).called(1);

    await tester.tap(find.text(l10n.socks5).first);
    await tester.pump();
    expect(find.text(l10n.settingsProxySocksDesc), findsOneWidget);
  });

  testWidgets('quick presets fill the host/port fields', (tester) async {
    stubState(const SettingsState());
    await pump(tester);

    await tester.tap(find.text('Clash / V2Ray (7890)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('7890'), findsWidgets);
    expect(find.text(l10n.proxyPresetApplied('Clash / V2Ray', '127.0.0.1', 7890)),
        findsOneWidget);
  });

  testWidgets('bypass chips append unique hosts', (tester) async {
    stubState(const SettingsState(proxyBypassHosts: 'localhost, 127.0.0.1'));
    await pump(tester);

    await tester.tap(find.text('*.local'));
    await tester.pump();
    expect(find.text('localhost, 127.0.0.1, *.local'), findsWidgets);

    // Re-tapping an existing host must not duplicate it.
    await tester.tap(find.text('localhost').last);
    await tester.pump();
    expect(find.text('localhost, 127.0.0.1, *.local, localhost'), findsNothing);
  });

  testWidgets('test button shows the successful verdict card', (tester) async {
    stubState(const SettingsState(proxyEnabled: true, proxyHost: '1.2.3.4'));
    when(() => cubit.testProxyConnection(any())).thenAnswer(
        (_) async => (success: true, latencyMs: 42, error: null));
    await pump(tester);

    await tester.tap(find.text(l10n.testProxy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.settingsConnectionSuccessful), findsOneWidget);
    expect(find.text(l10n.settingsLatencyMs(42)), findsOneWidget);
  });

  testWidgets('test button shows the failure verdict card', (tester) async {
    stubState(
        const SettingsState(proxyEnabled: true, proxyHost: '1.2.3.4'));
    when(() => cubit.testProxyConnection(any())).thenAnswer((_) async =>
        (success: false, latencyMs: 0, error: 'refused'));
    await pump(tester);

    await tester.tap(find.text(l10n.testProxy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.settingsConnectionFailed), findsOneWidget);
    expect(find.text('refused'), findsOneWidget);
  });

  testWidgets('save button persists the controller values', (tester) async {
    stubState(const SettingsState(proxyEnabled: true, proxyHost: '1.2.3.4'));
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.setProxySettings(
          enabled: any(named: 'enabled'),
          type: any(named: 'type'),
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          bypassHosts: any(named: 'bypassHosts'),
        )).called(1);
    expect(find.text(l10n.proxySaved), findsOneWidget);
  });

  testWidgets('import dialog parses pasted proxies', (tester) async {
    stubState(const SettingsState());
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.settingsImportPasteProxies));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.importProxies), findsWidgets);

    final fieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 6);
    await tester.enterText(fieldFinder, '1.2.3.4:8080:user:pass');
    await tester.pump();

    await tester.tap(find.text(l10n.importParse));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    verify(() => cubit.importProxiesFromText('1.2.3.4:8080:user:pass'))
        .called(1);
    expect(find.text(l10n.proxyImported(2)), findsOneWidget);
  });

  testWidgets('import dialog can be cancelled', (tester) async {
    stubState(const SettingsState());
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.settingsImportPasteProxies));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    verifyNever(() => cubit.importProxiesFromText(any()));
  });
}
