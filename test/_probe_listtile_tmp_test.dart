// TEMPORARY diagnostic probe (not part of the repo test suite).
// Pumps the redesigned SettingsScreen in several states and enumerates every
// ListTile whose nearest Material ancestor is masked by a colored
// ColoredBox/DecoratedBox — the exact condition the newer Flutter SDK asserts.
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

  testWidgets('probe: list ListTile ancestor-masking violations',
      (tester) async {
    final captured = <Object>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      captured.add(details.exception);
    };

    SharedPreferences.setMockInitialValues({});
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

    final scanner = MockMediaScannerService();
    final player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream).thenAnswer((_) => const Stream.empty());
    final auth = MockAuthCubit();
    when(() => auth.state).thenReturn(const AuthState());
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    final settings = SettingsCubit(scannerService: scanner);

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      settings.close();
    });

    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: settings),
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<AuthCubit>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ));

    final printed = <String>{};

    void scan(String label) {
      for (final e in tester.allElements) {
        final w = e.widget;
        if (w is! ListTile) continue;
        Widget? intermediate;
        var past = false;
        final chain = <String>[];
        e.visitAncestorElements((a) {
          if (past) {
            chain.add('[${a.widget.runtimeType}]');
            return chain.length < 26;
          }
          chain.add(a.widget.runtimeType.toString());
          if (a.widget is Material) return false;
          final aw = a.widget;
          Color? color;
          if (aw is ColoredBox) color = aw.color;
          if (aw is DecoratedBox && aw.decoration is BoxDecoration) {
            color = (aw.decoration as BoxDecoration).color;
          }
          if (aw is DecoratedBox && aw.decoration is ShapeDecoration) {
            color = (aw.decoration as ShapeDecoration).color;
          }
          if (color != null && color.a > 0) {
            intermediate = aw;
            past = true;
          }
          return true;
        });
        if (intermediate != null) {
          final ro = e.renderObject;
          final creator = ro?.debugCreator?.toString() ?? '(no render creator)';
          final key = '$creator|${chain.take(14).join("|")}';
          if (printed.add(key)) {
            debugPrint('VIOLATION[$label] tile=${w.runtimeType} '
                'intermediate=${intermediate!.runtimeType}');
            debugPrint('  creator: $creator');
            debugPrint('  ancestors: ${chain.join(' << ')}');
          }
        }
      }
    }

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    scan('initial');

    for (int i = 0; i < 14; i++) {
      final lv = find.byType(ListView);
      if (lv.evaluate().isEmpty) break;
      await tester.drag(lv.first, const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      scan('scroll$i');
    }

    final pill = find.text('Sound & Playback');
    if (pill.evaluate().isNotEmpty) {
      await tester.tap(pill.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      scan('sound-tab');
      for (int i = 0; i < 14; i++) {
        final lv = find.byType(ListView);
        if (lv.evaluate().isEmpty) break;
        await tester.drag(lv.first, const Offset(0, -300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        scan('sound-scroll$i');
      }
    }

    final tf = find.byType(TextField);
    if (tf.evaluate().isNotEmpty) {
      await tester.enterText(tf.first, 'crossfade');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      scan('search');
    }

    FlutterError.onError = prevOnError;
    debugPrint('PROBE COMPLETE. distinct violations: ${printed.length}; '
        'captured errors: ${captured.length}');
  });
}
