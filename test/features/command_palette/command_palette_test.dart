import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_search_field.dart';
import 'package:pulsr/features/command_palette/presentation/command_palette_sheet.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

Widget _buildHarness({
  required Widget child,
  PlayerCubit? playerCubit,
}) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      extensions: [AuraTheme.defaultDark],
    ),
    home: playerCubit != null
        ? BlocProvider<PlayerCubit>.value(
            value: playerCubit,
            child: Scaffold(body: Center(child: child)),
          )
        : Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockCubit;

  setUp(() {
    mockCubit = MockPlayerCubit();
    when(() => mockCubit.state).thenReturn(const PlayerState());
  });

  group('P6 Discoverability — Command Palette Tests', () {
    testWidgets(
        'Command Palette renders search field and all 3 sections by default',
        (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          playerCubit: mockCubit,
          child: const CommandPaletteSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PulsrSearchField), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);

      final listScrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Playback & Actions'),
        150.0,
        scrollable: listScrollable,
      );
      expect(find.text('Playback & Actions'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Settings'),
        150.0,
        scrollable: listScrollable,
      );
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Typing a query filters commands by title and keywords',
        (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          playerCubit: mockCubit,
          child: const CommandPaletteSheet(),
        ),
      );
      await tester.pumpAndSettle();

      // Search for equalizer
      await tester.enterText(find.byType(PulsrSearchField), 'equalizer');
      await tester.pumpAndSettle();

      expect(find.text('Open Equalizer'), findsOneWidget);
      expect(find.text('Playback & Actions'), findsOneWidget);

      // Search for something non-existent
      await tester.enterText(
          find.byType(PulsrSearchField), 'xyznonexistent123');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });

    testWidgets(
        'Command palette contains all new navigation items (Radio, DLNA, Diagnostics, Audio Profiles, Podcasts)',
        (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          playerCubit: mockCubit,
          child: const CommandPaletteSheet(),
        ),
      );
      await tester.pumpAndSettle();

      // Search for Radio
      await tester.enterText(find.byType(PulsrSearchField), 'radio');
      await tester.pumpAndSettle();
      expect(find.text('Radio'), findsOneWidget);

      // Search for DLNA
      await tester.enterText(find.byType(PulsrSearchField), 'dlna');
      await tester.pumpAndSettle();
      expect(find.text('DLNA / UPnP Cast'), findsOneWidget);

      // Search for Diagnostics
      await tester.enterText(find.byType(PulsrSearchField), 'diagnostics');
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics'), findsOneWidget);

      // Search for Audio Profiles
      await tester.enterText(find.byType(PulsrSearchField), 'audio profiles');
      await tester.pumpAndSettle();
      expect(find.text('Audio Profiles'), findsOneWidget);

      // Search for Podcasts
      await tester.enterText(find.byType(PulsrSearchField), 'podcasts');
      await tester.pumpAndSettle();
      expect(find.text('Podcasts & Audiobooks'), findsOneWidget);
    });

    testWidgets('Keyboard arrow navigation and Escape dismissal work cleanly',
        (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: BlocProvider<PlayerCubit>.value(
            value: mockCubit,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await CommandPaletteSheet.show(context);
                    popped = true;
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(CommandPaletteSheet), findsOneWidget);

      // Press ArrowDown to advance selection
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // Press Escape to dismiss
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPaletteSheet), findsNothing);
      expect(popped, isTrue);
    });

    testWidgets(
        'BUG-P2-29: Escape dismisses command palette even when search results are empty',
        (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: BlocProvider<PlayerCubit>.value(
            value: mockCubit,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await CommandPaletteSheet.show(context);
                    popped = true;
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandPaletteSheet), findsOneWidget);

      await tester.enterText(
          find.byType(PulsrSearchField), 'no_matching_command_xyz_999');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPaletteSheet), findsNothing);
      expect(popped, isTrue);
    });

    test('CommandPaletteItem matches keywords correctly', () {
      final item = CommandPaletteItem(
        id: 'test',
        title: 'Sound Settings',
        subtitle: 'Audio and DSP',
        icon: Icons.tune,
        section: CommandPaletteSection.settings,
        keywords: ['equalizer', 'bass', 'gain'],
        onSelect: (_) {},
      );

      expect(item.matches(''), isTrue);
      expect(item.matches('sound'), isTrue);
      expect(item.matches('audio'), isTrue);
      expect(item.matches('bass'), isTrue);
      expect(item.matches('gain'), isTrue);
      expect(item.matches('nonexistent'), isFalse);
    });
  });
}
