import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/router/app_router.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/player_shortcut_scope.dart';
import 'package:pulsr/features/shell/presentation/widgets/shortcut_help_sheet.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockRepo extends Mock implements IMusicRepository {}

class _MockScanner extends Mock implements MediaScannerService {}

void main() {
  late Map<String, int> calls;

  void hit(String name) => calls[name] = (calls[name] ?? 0) + 1;

  Widget build({bool withTextField = false}) {
    return MaterialApp(
      home: PlayerShortcutScope(
        onTogglePlayPause: () => hit('playPause'),
        onSeekForward: () => hit('seekForward'),
        onSeekBackward: () => hit('seekBackward'),
        onVolumeUp: () => hit('volumeUp'),
        onVolumeDown: () => hit('volumeDown'),
        onNext: () => hit('next'),
        onPrevious: () => hit('previous'),
        onToggleMute: () => hit('mute'),
        onToggleLyrics: () => hit('lyrics'),
        onToggleQueue: () => hit('queue'),
        child: Scaffold(
          body: withTextField
              ? const Center(child: TextField())
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget buildArrowScope({bool withTextField = false}) {
    return MaterialApp(
      home: PlayerArrowShortcutScope(
        onSeekForward: () => hit('seekForward'),
        onSeekBackward: () => hit('seekBackward'),
        onVolumeUp: () => hit('volumeUp'),
        onVolumeDown: () => hit('volumeDown'),
        child: Scaffold(
          body: withTextField
              ? const Center(child: TextField())
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  setUp(() => calls = <String, int>{});

  testWidgets('space toggles play/pause', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    await press(tester, LogicalKeyboardKey.space);
    expect(calls['playPause'], 1);
  });

  testWidgets('arrow keys seek and adjust volume', (tester) async {
    await tester.pumpWidget(buildArrowScope());
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(calls['seekForward'], 1);
    expect(calls['seekBackward'], 1);
    expect(calls['volumeUp'], 1);
    expect(calls['volumeDown'], 1);
  });

  testWidgets('N/P/M/L/Q map to their actions', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyN);
    await press(tester, LogicalKeyboardKey.keyP);
    await press(tester, LogicalKeyboardKey.keyM);
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.keyQ);
    expect(calls['next'], 1);
    expect(calls['previous'], 1);
    expect(calls['mute'], 1);
    expect(calls['lyrics'], 1);
    expect(calls['queue'], 1);
  });

  testWidgets('shortcuts are suppressed while a text field is focused',
      (tester) async {
    await tester.pumpWidget(build(withTextField: true));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.space);
    await press(tester, LogicalKeyboardKey.keyN);
    expect(calls['playPause'], isNull);
    expect(calls['next'], isNull);
  });

  testWidgets('isTextInputFocused is false with no focus', (tester) async {
    expect(PlayerShortcutScope.isTextInputFocused(), isFalse);
  });

  testWidgets('H-50 character "?" opens ShortcutHelpSheet even without US slash key',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlayerShortcutScope(
          onTogglePlayPause: () => hit('playPause'),
          onSeekForward: () => hit('seekForward'),
          onSeekBackward: () => hit('seekBackward'),
          onVolumeUp: () => hit('volumeUp'),
          onVolumeDown: () => hit('volumeDown'),
          onNext: () => hit('next'),
          onPrevious: () => hit('previous'),
          onToggleMute: () => hit('mute'),
          onToggleLyrics: () => hit('lyrics'),
          onToggleQueue: () => hit('queue'),
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyM,
      character: '?',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();

    expect(find.byType(ShortcutHelpSheet), findsOneWidget);
  });

  testWidgets('H-50 rootNavigatorKey pages wrap content in PlayerShortcutScope on createRoute',
      (tester) async {
    final mockPlayer = _MockPlayerCubit();
    when(() => mockPlayer.state).thenReturn(const PlayerState());
    when(() => mockPlayer.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.togglePlayPause()).thenAnswer((_) async {});

    final router = createRouter(_MockScanner(), _MockRepo());
    addTearDown(router.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: mockPlayer,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final albumRoute = router.configuration.routes
        .whereType<GoRoute>()
        .firstWhere((r) => r.path == '/album');
    final state = GoRouterState(
      router.configuration,
      uri: Uri.parse('/album'),
      matchedLocation: '/album',
      fullPath: '/album',
      pathParameters: const {},
      pageKey: const ValueKey('/album'),
    );
    final page = albumRoute.pageBuilder!(ctx, state) as MaterialPage<void>;
    final builtRoute = page.createRoute(ctx);
    expect(builtRoute, isA<PageRoute<void>>());

    Navigator.of(ctx).push(builtRoute);
    await tester.pumpAndSettle();

    expect(find.byType(PlayerShortcutScope), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    verify(() => mockPlayer.togglePlayPause()).called(1);
  });
}
