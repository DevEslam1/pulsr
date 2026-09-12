import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/radio/presentation/radio_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

Widget _buildTestApp({required Widget child, required MockPlayerCubit playerCubit}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
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
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  testWidgets('RadioScreen renders empty state and Add Station button', (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RadioScreen), findsOneWidget);
    expect(find.byIcon(Icons.radio_rounded), findsWidgets);
    expect(find.text('Add Station'), findsWidgets);
  });

  testWidgets('Add Station dialog opens and closes without controller disposal errors', (tester) async {
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

  testWidgets('Adding a valid station updates the list without error', (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    // Open Add Dialog via AppBar action
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    // Enter details
    await tester.enterText(find.widgetWithText(TextField, 'Station name'), 'Chill Beats');
    await tester.enterText(find.widgetWithText(TextField, 'Stream URL'), 'https://stream.example.com/live.mp3');
    await tester.pump();

    // Tap Add
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Verify new station appears in the list
    expect(find.text('Chill Beats'), findsOneWidget);
    expect(find.text('https://stream.example.com/live.mp3'), findsOneWidget);
  });

  testWidgets('Import dialog opens and cancels cleanly', (tester) async {
    await tester.pumpWidget(_buildTestApp(
      child: const RadioScreen(),
      playerCubit: mockPlayerCubit,
    ));
    await tester.pumpAndSettle();

    // Tap Import button in app bar
    await tester.tap(find.byIcon(Icons.playlist_add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Import .m3u'), findsOneWidget);

    // Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Import .m3u'), findsNothing);
  });
}
