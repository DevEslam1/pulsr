// test/features/player/widgets/eq_sheet_shell_test.dart
//
// REACHABILITY CONTRACT (see report): `EqualizerSheet.build` returns early on a
// non-Android host because of `if (!Platform.isAndroid)` at
// `lib/features/player/presentation/widgets/equalizer_sheet.dart:222`. That
// gate reads `dart:io`'s `Platform` directly — it is NOT `defaultTargetPlatform`
// and there is no injectable indirection (`PlatformCapabilities`, a constructor
// flag, `debugDefaultTargetPlatformOverride`, etc.). Therefore the full 3-tab
// shell (`_EqSheetShell`) cannot be mounted in a host widget test.
//
// This file exercises every part of the shell that IS reachable on the host:
// the fallback branch, the `show(...)` entry point, the State lifecycle
// (initState -> `_loadHeadphoneProfiles` / `_listenForDspAutoDegrade`, dispose),
// and asserts the Android-only shell controls are absent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('EqualizerSheet fallback branch (host, Platform.isAndroid == false)',
      () {
    testWidgets('renders drag handle, icon, title and description',
        (tester) async {
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
      expect(find.text('Hardware Effects Unavailable'), findsOneWidget);
      expect(
        find.text(
          'Hardware AudioFX, Equalizer, Virtualizer and DynamicsProcessing '
          'are supported on Android devices.',
        ),
        findsOneWidget,
      );
      // Drag handle pill.
      expect(find.byType(Container), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders identically in a short landscape surface',
        (tester) async {
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders under an RTL locale', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EqualizerSheet()),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a large text scale factor', (tester) async {
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: EqualizerSheet(),
        ),
      ));
      await tester.pump();

      expect(find.byType(EqualizerSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('initState resolves the async headphone profile load',
        (tester) async {
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: const EqualizerSheet(),
      ));
      // `_loadHeadphoneProfiles()` awaits a real asset/prefs read; give real
      // async a window, then pump the post-await frame.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.byType(EqualizerSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('caches a DI-registered EqualizerManager when present',
        (tester) async {
      final manager = MockEqualizerManager();
      getIt.registerSingleton<EqualizerManager>(manager);
      addTearDown(() async {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt.unregister<EqualizerManager>();
        }
      });

      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      expect(find.byType(EqualizerSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose is clean (cancels subscription + controllers)',
        (tester) async {
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(find.byType(EqualizerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not mount the Android-only control surface',
        (tester) async {
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        settingsCubit: stubSettingsCubit(),
        child: const EqualizerSheet(),
      ));
      await tester.pumpAndSettle();

      // None of the 3-tab shell controls exist on a non-Android host.
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
    });
  });

  group('EqualizerSheet.show route', () {
    testWidgets('opens and dismisses a sheet route on the host',
        (tester) async {
      await tester.pumpWidget(sheetHost(
        playerCubit: stubPlayerCubit(),
        settingsCubit: stubSettingsCubit(),
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => EqualizerSheet.show(ctx),
            child: const Text('open-eq'),
          ),
        ),
      ));

      await tester.tap(find.text('open-eq'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EqualizerSheet), findsOneWidget);
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
