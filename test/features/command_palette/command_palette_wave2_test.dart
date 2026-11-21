import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_search_field.dart';
import 'package:pulsr/features/command_palette/presentation/command_palette_sheet.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));
  late _MockPlayerCubit playerCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CommandPaletteSheet.debugResetRecentActions();

    playerCubit = _MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => playerCubit.next()).thenAnswer((_) async {});
    when(() => playerCubit.previous()).thenAnswer((_) async {});
    when(() => playerCubit.toggleShuffle()).thenAnswer((_) async {});
    when(() => playerCubit.toggleFavorite()).thenAnswer((_) async {});
    when(() => playerCubit.toggleMute()).thenAnswer((_) async {});
    when(() => playerCubit.toggleLyrics()).thenReturn(null);
  });

  tearDown(CommandPaletteSheet.debugResetRecentActions);

  Widget buildSheetHarness({
    bool disableAnimations = false,
    GoRouter? router,
  }) {
    if (router != null) {
      return MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          ),
          child: BlocProvider<PlayerCubit>.value(
            value: playerCubit,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      );
    }

    return MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 1200),
          disableAnimations: disableAnimations,
        ),
        child: BlocProvider<PlayerCubit>.value(
          value: playerCubit,
          child: const Scaffold(
            body: Center(child: CommandPaletteSheet()),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'records last 5 executed commands in MRU order and displays Recent section when query is empty',
      (tester) async {
    final router = GoRouter(
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
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Text('settings-route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(buildSheetHarness(router: router));
    await tester.pumpAndSettle();

    Future<void> runCommand(String query, String title) async {
      await tester.tap(find.text('open-palette'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(PulsrSearchField), query);
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
    }

    // Execute 6 distinct commands; cap must keep the most recent 5.
    await runCommand('play / pause', l10n.commandPaletteActionPlay);
    await runCommand('next track', l10n.shortcutNext);
    await runCommand('previous track', l10n.shortcutPrevious);
    await runCommand('toggle favorite', l10n.shortcutFavorite);
    await runCommand('toggle mute', l10n.shortcutMute);
    await runCommand('toggle lyrics', l10n.shortcutLyrics);

    expect(
      CommandPaletteSheet.recentActionIds,
      [
        'action_lyrics',
        'action_mute',
        'action_favorite',
        'action_prev',
        'action_next',
      ],
    );

    // Reopen palette with empty query -> Recent section appears at the top.
    await tester.tap(find.text('open-palette'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.sortRadioCardsRecent), findsOneWidget);

    // Searching filters canonical commands without duplicating items from Recent.
    await tester.enterText(find.byType(PulsrSearchField), 'toggle lyrics');
    await tester.pumpAndSettle();
    expect(find.text(l10n.sortRadioCardsRecent), findsNothing);
    expect(find.text(l10n.shortcutLyrics), findsOneWidget);
  });

  testWidgets('renders inline keyboard shortcut badges on bound commands',
      (tester) async {
    await tester.pumpWidget(buildSheetHarness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(PulsrSearchField), 'queue');
    await tester.pumpAndSettle();
    expect(find.text('Q'), findsOneWidget);

    await tester.enterText(find.byType(PulsrSearchField), 'play / pause');
    await tester.pumpAndSettle();
    expect(find.text('Space'), findsOneWidget);

    await tester.enterText(find.byType(PulsrSearchField), 'next track');
    await tester.pumpAndSettle();
    expect(find.text('N'), findsOneWidget);

    await tester.enterText(find.byType(PulsrSearchField), 'keyboard shortcuts');
    await tester.pumpAndSettle();
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('Open Settings command navigates to /settings', (tester) async {
    final router = GoRouter(
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
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Text('settings-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(buildSheetHarness(router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-palette'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(PulsrSearchField), 'open settings');
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.openSettings));
    await tester.pumpAndSettle();

    expect(find.text('settings-destination'), findsOneWidget);
  });

  testWidgets(
      'exposes full Semantics (headers, button/selected flags, liveRegion, >= 48dp hit targets) and respects reduce motion',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(buildSheetHarness(disableAnimations: true));
    await tester.pumpAndSettle();

    // Section header carries semantic header flag.
    final navHeader =
        tester.getSemantics(find.text(l10n.commandPaletteSectionRoutes));
    expect(navHeader.flagsCollection.isHeader, isTrue);

    Finder rowSemanticsFor(String label) => find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == label,
        );

    // First item ('Home') is highlighted -> button + selected.
    final homeSemantics = tester.getSemantics(rowSemanticsFor('Home').first);
    expect(homeSemantics.flagsCollection.isButton, isTrue);
    expect(homeSemantics.flagsCollection.isSelected, Tristate.isTrue);

    // Hit target height >= 48dp.
    final homeRowSize = tester.getSize(rowSemanticsFor('Home').first);
    expect(homeRowSize.height, greaterThanOrEqualTo(48.0));

    // ArrowDown moves selected semantics cleanly with animations disabled.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final librarySemantics =
        tester.getSemantics(rowSemanticsFor('Library').first);
    expect(librarySemantics.flagsCollection.isSelected, Tristate.isTrue);

    // No-results empty state is a semantic live region.
    await tester.enterText(
      find.byType(PulsrSearchField),
      'definitely_no_such_command_xyz',
    );
    await tester.pumpAndSettle();
    final emptySemantics =
        tester.getSemantics(find.text(l10n.commandPaletteNoResults));
    expect(emptySemantics.flagsCollection.isLiveRegion, isTrue);

    semantics.dispose();
  });
}
