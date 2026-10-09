// Focused coverage for the proxy pool / latency sections defined in
// lib/features/settings/presentation/proxy_settings_sections.dart (rendered by
// ProxySettingsScreen).
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

  final entries = const [
    ProxyEntry(
      id: 'a',
      host: '1.1.1.1',
      port: 1111,
      username: 'user',
      type: AppProxyType.socks5,
      isWorking: true,
      latencyMs: 120,
    ),
    ProxyEntry(id: 'b', host: '2.2.2.2', port: 2222, isWorking: false),
    ProxyEntry(id: 'c', host: '3.3.3.3', port: 3333, isTesting: true),
    ProxyEntry(id: 'd', host: '4.4.4.4', port: 4444),
  ];

  setUp(() {
    registerFallbackValue(const ProxyEntry(id: 'x', host: 'h', port: 1));
    cubit = MockSettingsCubit();
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => cubit.getProxyPassword()).thenAnswer((_) async => '');
    when(() => cubit.clearProxyList()).thenAnswer((_) async {});
    when(() => cubit.testAllProxies()).thenAnswer((_) async {});
    when(() => cubit.sortProxiesByLatency()).thenAnswer((_) async {});
    when(() => cubit.selectProxyEntry(any())).thenAnswer((_) async {});
    when(() => cubit.testSingleProxyEntry(any())).thenAnswer((_) async {});
    when(() => cubit.removeProxyEntry(any())).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester, SettingsState state) async {
    when(() => cubit.state).thenReturn(state);
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

  SettingsState poolState({bool testingAll = false}) => SettingsState(
        proxyEnabled: true,
        proxyHost: '1.1.1.1',
        proxyPort: 1111,
        proxyUsername: 'user',
        proxyList: entries,
        isTestingAllProxies: testingAll,
      );

  testWidgets('renders pool entries with every latency/verdict chip variant',
      (tester) async {
    await pump(tester, poolState());

    expect(find.text(l10n.savedProxyPool), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text(l10n.activeLabel), findsOneWidget);

    expect(find.text('120ms'), findsOneWidget);
    expect(find.text(l10n.failedLabel), findsOneWidget);
    expect(find.text(l10n.testingLabel), findsOneWidget);
    expect(find.text(l10n.unverifiedLabel), findsOneWidget);

    // Protocol + auth tags.
    expect(find.text(l10n.socks5), findsWidgets);
    expect(find.text(l10n.settingsHttpLabel), findsWidgets);
    expect(find.text('user'), findsWidgets);

    expect(find.text(l10n.settingsTestAllSpeeds), findsOneWidget);
    expect(find.text(l10n.sortBySpeed), findsOneWidget);
  });

  testWidgets('selecting a pool entry activates it', (tester) async {
    await pump(tester, poolState());

    await tester.tap(find.text('2.2.2.2:2222'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.selectProxyEntry(
        any(that: predicate<ProxyEntry>((e) => e.id == 'b')))).called(1);
  });

  testWidgets('per-entry test and delete controls wire to the cubit',
      (tester) async {
    await pump(tester, poolState());

    await tester.tap(find.byTooltip(l10n.settingsTestLatency).first);
    await tester.pump();
    verify(() => cubit.testSingleProxyEntry('a')).called(1);

    await tester.tap(find.byTooltip(l10n.settingsRemoveProxy).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    verify(() => cubit.removeProxyEntry('a')).called(1);
  });

  testWidgets('test-all and sort actions call the cubit', (tester) async {
    await pump(tester, poolState());

    await tester.tap(find.text(l10n.settingsTestAllSpeeds));
    await tester.pump();
    verify(() => cubit.testAllProxies()).called(1);

    await tester.tap(find.text(l10n.sortBySpeed));
    await tester.pump();
    verify(() => cubit.sortProxiesByLatency()).called(1);
  });

  testWidgets('clear-all confirms before clearing the pool', (tester) async {
    await pump(tester, poolState());

    await tester.tap(find.text(l10n.clearAll));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.clearPoolTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.clearAll));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.clearProxyList()).called(1);
  });

  testWidgets('testing-all shows the busy skeleton and disables the action',
      (tester) async {
    await pump(tester, poolState(testingAll: true));

    expect(find.text(l10n.settingsTestingAll), findsOneWidget);
    final testAll = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.settingsTestingAll),
    );
    expect(testAll.onPressed, isNull);
  });

  testWidgets('empty pool shows the import empty state', (tester) async {
    await pump(tester, const SettingsState());

    expect(find.text(l10n.noProxiesPool), findsOneWidget);
    expect(find.text(l10n.importProxiesDesc), findsOneWidget);
    expect(find.text(l10n.settingsTestAllSpeeds), findsNothing);
  });
}
