import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/radio/presentation/radio_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class MockPlayerCubit extends Mock implements PlayerCubit {}

Widget _buildTestApp(
    {required Widget child, required MockPlayerCubit playerCubit}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RadioStationStore.resetForTesting();
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  testWidgets('RadioScreen renders empty state and Add Station button',
      (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RadioScreen), findsOneWidget);
    expect(find.byIcon(Icons.radio_rounded), findsWidgets);
    expect(find.text('Add Station'), findsWidgets);
  });

  testWidgets(
      'Add Station dialog opens and closes without controller disposal errors',
      (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    // Tap Add Station button in empty state
    await tester.tap(find.widgetWithText(FilledButton, 'Add Station'));
    await tester.pumpAndSettle();

    // Dialog is visible
    expect(find.text('Station name'), findsOneWidget);
    expect(find.text('Stream URL'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Verify dialog dismissed cleanly with no exceptions
    expect(find.text('Station name'), findsNothing);
  });

  testWidgets('Adding a valid station updates the list without error',
      (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    // Open Add Dialog via AppBar action
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    // Enter details
    await tester.enterText(
        find.widgetWithText(TextField, 'Station name'), 'Chill Beats');
    await tester.enterText(find.widgetWithText(TextField, 'Stream URL'),
        'https://stream.example.com/live.mp3');
    await tester.pump();

    // Tap Add
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Verify new station appears in the list
    expect(find.text('Chill Beats'), findsOneWidget);
    expect(find.text('https://stream.example.com/live.mp3'), findsOneWidget);
  });

  testWidgets('editing a station onto another station URL is refused',
      (tester) async {
    final alpha =
        RadioStation.create(name: 'Alpha', url: 'https://a.example.com/live');
    final beta =
        RadioStation.create(name: 'Beta', url: 'https://b.example.com/live');
    SharedPreferences.setMockInitialValues({
      RadioStationStore.prefsKey: jsonEncode([alpha.toJson(), beta.toJson()]),
    });

    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    // Edit Alpha and point it at Beta's URL.
    await tester.tap(find.byIcon(Icons.edit_rounded).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Stream URL'), beta.url);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The collision is surfaced and neither station is silently deleted.
    expect(
        find.text('A station with this URL already exists.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('an uppercase HTTPS scheme is accepted when adding a station',
      (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Station name'), 'Caps');
    await tester.enterText(find.widgetWithText(TextField, 'Stream URL'),
        'HTTPS://stream.example.com/live');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Caps'), findsOneWidget);
    expect(find.text('Please enter a URL'), findsNothing);
    expect(find.text('URL must start with http:// or https://'), findsNothing);
  });

  testWidgets('Import dialog opens and cancels cleanly', (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    // Tap overflow menu then Import
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.playlist_add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Import .m3u'), findsOneWidget);

    // Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Import .m3u'), findsNothing);
  });


  testWidgets(
      'long-pressing a radio card opens station actions sheet with sorting options',
      (tester) async {
    final s1 = RadioStation.create(
      name: 'Zeta Station',
      url: 'https://z.example.com/live',
      genre: 'Ambient',
    );
    final s2 = RadioStation.create(
      name: 'Alpha Station',
      url: 'https://a.example.com/live',
      genre: 'Rock',
    );
    SharedPreferences.setMockInitialValues({
      RadioStationStore.prefsKey: jsonEncode([s1.toJson(), s2.toJson()]),
    });

    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Zeta Station'), findsOneWidget);
    expect(find.text('Alpha Station'), findsOneWidget);

    // Long press on Zeta Station card
    await tester.longPress(find.text('Zeta Station'));
    await tester.pumpAndSettle();

    // Verify sheet contents: Edit, Delete, and Sort Order options
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Sort Order'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('A–Z'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);

    // Tap A-Z sort chip
    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();

    // Verify sort state updated
    expect(RadioStationStore.radioSortBy.value, 'name');
    expect(RadioStationStore.radioSortAsc.value, isTrue);

    // Verify stations are sorted alphabetically (Alpha first, Zeta second)
    final listTiles =
        tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final names = listTiles
        .map((t) => (t.title as dynamic)?.text)
        .whereType<String>()
        .toList();
    final alphaIndex = names.indexOf('Alpha Station');
    final zetaIndex = names.indexOf('Zeta Station');
    expect(alphaIndex, isNonNegative);
    expect(zetaIndex, isNonNegative);
    expect(alphaIndex, lessThan(zetaIndex));
  });

  testWidgets(
      'sorting by recent prioritizes most recently played radio station',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s1 = RadioStation.create(
      name: 'Old Played Station',
      url: 'https://old.example.com/live',
      lastPlayed: now - 50000,
    );
    final s2 = RadioStation.create(
      name: 'Recently Played Station',
      url: 'https://new.example.com/live',
      lastPlayed: now,
    );
    SharedPreferences.setMockInitialValues({
      RadioStationStore.prefsKey: jsonEncode([s1.toJson(), s2.toJson()]),
    });

    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    // Long press on a radio card
    await tester.longPress(find.text('Old Played Station'));
    await tester.pumpAndSettle();

    // Select Recent sort
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(RadioStationStore.radioSortBy.value, 'recent');
    expect(RadioStationStore.radioSortAsc.value, isFalse);

    // Verify Recently Played Station is ordered first
    final listTiles =
        tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final names = listTiles
        .map((t) => (t.title as dynamic)?.text)
        .whereType<String>()
        .toList();
    final recentIndex = names.indexOf('Recently Played Station');
    final oldIndex = names.indexOf('Old Played Station');
    expect(recentIndex, isNonNegative);
    expect(oldIndex, isNonNegative);
    expect(recentIndex, lessThan(oldIndex));
  });
}

