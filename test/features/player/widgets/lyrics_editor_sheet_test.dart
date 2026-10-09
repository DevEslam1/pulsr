// test/features/player/widgets/lyrics_editor_sheet_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_editor_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'player_sheet_test_support.dart';

/// Hosts the sheet above a two-route navigator so `Navigator.pop()` inside the
/// Save handler has a route to return to. The Provider is installed inside the
/// sheet route itself so the pushed route reliably sees it.
Widget lyricsHost({
  required PlayerCubit? cubit,
  required WidgetBuilder sheetBuilder,
}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Navigator(
      onGenerateInitialRoutes: (_, __) => [
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.shrink()),
        ),
        MaterialPageRoute<void>(
          builder: (ctx) {
            final sheet = Material(child: sheetBuilder(ctx));
            if (cubit == null) return sheet;
            return BlocProvider<PlayerCubit>.value(
              value: cubit,
              child: sheet,
            );
          },
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  tearDown(() async {
    await getIt.reset();
  });

  const initial = [
    LyricsLine(timestamp: Duration(seconds: 5), text: 'Second line'),
    LyricsLine(timestamp: Duration(seconds: 2), text: 'First line'),
  ];

  group('LyricsEditorSheet', () {
    testWidgets('renders rows, adds, deletes, sorts, stamps and saves',
        (tester) async {
      final controller = StreamController<Duration>.broadcast();
      addTearDown(controller.close);
      final cubit = stubPlayerCubit(positionStream: controller.stream);
      when(() => cubit.seek(any())).thenAnswer((_) async {});
      // Belt-and-suspenders: the widget's play handler falls back to GetIt when
      // the provider lookup misses, so register it for that path too.
      getIt.registerSingleton<PlayerCubit>(cubit);
      List<LyricsLine>? saved;

      await tester.pumpWidget(lyricsHost(
        cubit: cubit,
        sheetBuilder: (_) => LyricsEditorSheet(
          song: testSong,
          currentPosition: const Duration(seconds: 3),
          initialLyrics: initial,
          onSave: (lines) => saved = lines,
        ),
      ));
      await tester.pump();

      expect(find.byType(LyricsEditorSheet), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));

      // Live position update flows through the cubit stream.
      controller.add(const Duration(seconds: 12));
      await tester.pump();

      // Add a line via the header button.
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.add_rounded).first)
          .onPressed!();
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(3));

      // Shift the first row later, then earlier.
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.add_rounded).at(1))
          .onPressed!();
      await tester.pump();
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.remove_rounded).first)
          .onPressed!();
      await tester.pump();

      // Stamp the current position onto the first row.
      tester
          .widget<InkWell>(find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(InkWell),
              )
              .first)
          .onTap!();
      await tester.pump();

      // Edit text.
      await tester.enterText(find.byType(TextFormField).first, 'edited text');
      await tester.pump();

      // Preview/seek the first line.
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.play_arrow_rounded).first)
          .onPressed!();
      await tester.pump();
      verify(() => cubit.seek(any())).called(greaterThanOrEqualTo(1));

      // Delete the last row.
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline_rounded).last)
          .onPressed!();
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(2));

      // Sort by timestamp, then save.
      tester
          .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.sort_rounded))
          .onPressed!();
      await tester.pump();
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.first.timestamp, const Duration(seconds: 2));
      expect(saved!.first.text, 'First line');
    });

    testWidgets('seeds a placeholder line when no lyrics are supplied',
        (tester) async {
      final cubit = stubPlayerCubit();
      await tester.pumpWidget(lyricsHost(
        cubit: cubit,
        sheetBuilder: (_) => LyricsEditorSheet(
          song: testSong,
          currentPosition: Duration.zero,
          initialLyrics: const [],
          onSave: (_) {},
        ),
      ));
      await tester.pump();

      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('falls back to a periodic timer when no cubit is available',
        (tester) async {
      await tester.pumpWidget(lyricsHost(
        cubit: null,
        sheetBuilder: (_) => LyricsEditorSheet(
          song: testSong,
          currentPosition: Duration.zero,
          initialLyrics: const [
            LyricsLine(timestamp: Duration.zero, text: 'line'),
          ],
          onSave: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.byType(LyricsEditorSheet), findsOneWidget);

      // Let the fallback timer tick once, then dispose to cancel it.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}