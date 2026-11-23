// Regression tests for P0-1.2: the command palette must run item callbacks
// against a context that survives the sheet's pop. Selecting a navigation item,
// an action item or the Equalizer item after the pop used to throw
// "Looking up a deactivated widget's ancestor is unsafe".
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_search_field.dart';
import 'package:pulsr/features/audio_profiles/audio_profiles_screen.dart';
import 'package:pulsr/features/command_palette/presentation/command_palette_sheet.dart';
import 'package:pulsr/features/diagnostics/diagnostics_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit playerCubit;
  late GoRouter router;

  setUp(() {
    playerCubit = MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    // BlocProvider starts listening on first read, so the mock needs a stream.
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.next()).thenAnswer((_) async {});
    when(() => playerCubit.clearError()).thenAnswer((_) {});
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => CommandPaletteSheet.show(context),
                child: const Text('open-palette'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/library',
          builder: (context, state) =>
              const Scaffold(body: Text('library-route')),
        ),
        GoRoute(
          path: '/diagnostics',
          builder: (context, state) => const DiagnosticsScreen(),
        ),
        GoRoute(
          path: '/audio-profiles',
          builder: (context, state) => const AudioProfilesScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
  });

  Widget app() => MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark().copyWith(
          extensions: [AuraTheme.defaultDark],
        ),
        // The provider sits above the Navigator so the app-level context the
        // palette captures can still read it after the sheet is gone.
        builder: (context, child) => BlocProvider<PlayerCubit>.value(
          value: playerCubit,
          child: child ?? const SizedBox.shrink(),
        ),
      );

  Future<void> openPalette(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-palette'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteSheet), findsOneWidget);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(PulsrSearchField), query);
    await tester.pumpAndSettle();
  }

  testWidgets('navigation item navigates after the sheet is popped',
      (tester) async {
    await openPalette(tester);
    await search(tester, 'library');

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CommandPaletteSheet), findsNothing);
    expect(find.text('library-route'), findsOneWidget);
  });

  testWidgets('action item reaches the cubit from the post-pop context',
      (tester) async {
    await openPalette(tester);
    await search(tester, 'next track');

    await tester.tap(find.text('Next Track'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CommandPaletteSheet), findsNothing);
    verify(() => playerCubit.next()).called(1);
  });

  testWidgets('Equalizer item opens its sheet from the post-pop context',
      (tester) async {
    await openPalette(tester);
    await search(tester, 'open equalizer');

    await tester.tap(find.text('Open Equalizer'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CommandPaletteSheet), findsNothing);
    expect(find.byType(EqualizerSheet), findsOneWidget);
  });

  testWidgets('Diagnostics item pushes DiagnosticsScreen directly',
      (tester) async {
    await openPalette(tester);
    await search(tester, 'diagnostics');

    final finder = find.text('Diagnostics');
    await tester.tap(finder);
    // Frame 1: handles tap, pops sheet, registers postFrameCallback
    await tester.pump();
    // Frame 2: runs postFrameCallback, calls Navigator.push
    await tester.pump();
    // Frame 3: builds pushed route
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.byType(CommandPaletteSheet), findsNothing);
    expect(find.byType(DiagnosticsScreen), findsOneWidget);
  });

  testWidgets('Audio Profiles item pushes AudioProfilesScreen directly',
      (tester) async {
    await openPalette(tester);
    await search(tester, 'audio profiles');

    await tester.tap(find.text('Audio Profiles'));
    // Frame 1: handles tap, pops sheet, registers postFrameCallback
    await tester.pump();
    // Frame 2: runs postFrameCallback, calls Navigator.push
    await tester.pump();
    // Frame 3: builds pushed route
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.byType(CommandPaletteSheet), findsNothing);
    expect(find.byType(AudioProfilesScreen), findsOneWidget);
  });
}
