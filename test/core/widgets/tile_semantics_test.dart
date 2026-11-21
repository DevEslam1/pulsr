// test/core/widgets/tile_semantics_test.dart
import 'dart:ui' show SemanticsAction;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_list_tile.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

const _testSong = SongsTableData(
  id: 101,
  title: 'Accessible Track',
  artist: 'Accessible Artist',
  album: 'Accessible Album',
  durationMs: 180000,
  path: '/path/101.mp3',
  dateAdded: 0,
  isFavorite: false,
  isMissing: false,
  isDownloaded: false,
  playCount: 0,
  lastPositionMs: 0,
  source: 'local',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PulsrListTile semantics', () {
    testWidgets(
        'exposes trailing button to semantics tree outside excludeSemantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      var trailingTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: PulsrListTile(
              title: 'Settings Option',
              subtitle: 'Subtext description',
              onTap: () {},
              trailing: IconButton(
                key: const ValueKey('trailing_action'),
                tooltip: 'More Info',
                icon: const Icon(Icons.info),
                onPressed: () => trailingTapped = true,
              ),
            ),
          ),
        ),
      );

      final trailingFinder = find.byKey(const ValueKey('trailing_action'));
      expect(trailingFinder, findsOneWidget);

      final node = tester.getSemantics(trailingFinder);
      final data = node.getSemanticsData();
      expect(data.tooltip, contains('More Info'));
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(trailingFinder);
      await tester.pumpAndSettle();
      expect(trailingTapped, isTrue);

      handle.dispose();
    });
  });

  group('SongTile semantics', () {
    testWidgets('exposes trailing widget and more button to semantics tree',
        (tester) async {
      final handle = tester.ensureSemantics();
      final cubit = MockPlayerCubit();
      when(() => cubit.state).thenReturn(const PlayerState());
      when(() => cubit.stream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());

      var moreTapped = false;
      var starTapped = false;

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [BlocProvider<PlayerCubit>.value(value: cubit)],
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SongTile(
                song: _testSong,
                onTap: () {},
                onMorePressed: () => moreTapped = true,
                trailing: IconButton(
                  key: const ValueKey('star_button'),
                  tooltip: 'Star',
                  icon: const Icon(Icons.star),
                  onPressed: () => starTapped = true,
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Verify trailing widget has its own accessible node
      final starFinder = find.byKey(const ValueKey('star_button'));
      expect(starFinder, findsOneWidget);
      final starData = tester.getSemantics(starFinder).getSemanticsData();
      expect(starData.tooltip, contains('Star'));
      expect(starData.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(starFinder);
      expect(starTapped, isTrue);

      // 2. Verify onMorePressed icon button has its own accessible node
      final moreFinder = find.byIcon(Icons.more_vert_rounded);
      expect(moreFinder, findsOneWidget);
      final moreData = tester.getSemantics(moreFinder).getSemanticsData();
      expect(moreData.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(moreFinder);
      expect(moreTapped, isTrue);

      handle.dispose();
    });
  });
}
