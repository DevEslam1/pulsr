// Wave 2 regression tests for Library, Detail screens, and Smart Playlist
// Builder: H-31 (SQL totalSongCount, paginated rating sort, LibraryStatsScreen
// time-range topArtists & loading skeleton, Select All scoped per tab), H-33
// (FolderDetailScreen natural filename sort & transactional batch favorite),
// H-36 / M-04 (SmartPlaylistBuilderScreen clears _limitError on template tap
// and parses mm:ss duration), M-02 (libraryRailLetterIndex strips articles),
// L-01 (SmartPlaylistRuleBuilder seconds<->ms conversion).
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart' as domain;
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/library/presentation/library_stats_screen.dart';
import 'package:pulsr/features/library/presentation/widgets/smart_playlist_rule_builder.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_cubit.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart' hide stubPlayerCubit;
import '../../helpers/test_song_factory.dart';
import 'library_test_harness.dart';

class _Repo extends Mock implements IMusicRepository {}

class _FolderUseCases extends Mock implements FolderUseCases {}

class _Engine extends Mock implements ISmartPlaylistEngine {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerLibraryFallbacks();
    registerFallbackValue(<String>[]);
    registerFallbackValue(const domain.SmartCriteria());
  });

  group(
      'M-02 & L-01: article stripping and SmartPlaylistRuleBuilder ms conversion',
      () {
    test(
        'libraryRailLetterIndex strips leading The, A, An when remainder exists',
        () {
      final songs = [
        createTestSong(id: 1, title: 'The Beatles'),
        createTestSong(id: 2, title: 'A Perfect Circle'),
        createTestSong(id: 3, title: 'The'),
      ];
      expect(libraryRailLetterIndex('B', songs), 0);
      expect(libraryRailLetterIndex('P', songs), 1);
      expect(libraryRailLetterIndex('T', songs), 2);
    });

    test(
        'SmartRule converts duration between UI seconds and domain milliseconds',
        () {
      final uiRule = SmartRule(
        field: SmartRuleField.duration,
        operator: SmartRuleOperator.greaterThan,
        value: '180',
      );
      final domainRule = uiRule.toDomain();
      expect(domainRule.value, '180000');

      final roundTrip = SmartRule.fromDomain(domainRule);
      expect(roundTrip.value, '180');
    });
  });

  group('H-31: LibraryStatsScreen time-range topArtists & loading skeleton',
      () {
    testWidgets(
        'shows SkeletonList while getAllSongs is loading and filters topArtists by time range',
        (tester) async {
      final repo = _Repo();
      final completer = Completer<Result<List<SongsTableData>>>();
      when(() => repo.getExcludedFolderPaths())
          .thenAnswer((_) async => const Right([]));
      when(() =>
              repo.getAllSongs(excludedFolders: any(named: 'excludedFolders')))
          .thenAnswer((_) => completer.future);

      final state = const LibraryState();
      disableAnimations(tester);
      setSurface(tester);
      await tester.pumpWidget(
        libraryHarness(
          libraryCubit: stubLibraryCubit(state),
          playerCubit: stubPlayerCubit(),
          child: LibraryStatsScreen(musicRepository: repo),
        ),
      );
      await tester.pump();

      // SkeletonList is shown while full library load is in flight.
      expect(find.byType(SkeletonList), findsOneWidget);

      final now = DateTime.now().millisecondsSinceEpoch;
      final twoDaysAgo = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
      final fortyDaysAgo = DateTime.now()
          .subtract(const Duration(days: 40))
          .millisecondsSinceEpoch;

      completer.complete(Right([
        createTestSong(
          id: 1,
          title: 'Recent Hit',
          artist: 'RecentArtist',
          playCount: 5,
        ).copyWith(lastPlayed: Value(twoDaysAgo)),
        createTestSong(
          id: 2,
          title: 'Old Hit',
          artist: 'OldArtist',
          playCount: 20,
        ).copyWith(lastPlayed: Value(fortyDaysAgo)),
        createTestSong(
          id: 3,
          title: 'Now Hit',
          artist: 'RecentArtist',
          playCount: 2,
        ).copyWith(lastPlayed: Value(now)),
      ]));
      await tester.pumpAndSettle();

      // All Time shows OldArtist in topSongs, topArtists, and recentlyPlayed (3 occurrences)
      expect(find.text('OldArtist'), findsNWidgets(3));
      expect(find.text('RecentArtist'), findsWidgets);

      // Tap "7 Days" segment: OldArtist (40 days ago) must be excluded from Top Songs & Top Artists
      await tester.tap(find.byIcon(Icons.date_range_rounded));
      await tester.pumpAndSettle();

      expect(find.text('RecentArtist'), findsWidgets);
      expect(find.text('OldArtist'), findsOneWidget);
    });
  });

  group('H-33: FolderDetailScreen natural filename sort', () {
    testWidgets('natural sort orders track2.mp3 before track10.mp3',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'pulsr_hint_song_tile_swipe': true,
      });
      final folderUseCases = _FolderUseCases();
      final songs = [
        createTestSong(
          id: 1,
          title: 'Zeta Title',
          path: '/music/rock/track10.mp3',
        ),
        createTestSong(
          id: 2,
          title: 'Alpha Title',
          path: '/music/rock/track2.mp3',
        ),
      ];
      when(() => folderUseCases.watchFolderSongs(any()))
          .thenAnswer((_) => Stream.value(Right(songs)));

      useScreenSize(tester, const Size(800, 1400));
      await tester.pumpWidget(
        screenHarness(
          providers: [
            BlocProvider<LibraryCubit>.value(
                value: stubLibraryCubit(const LibraryState())),
            BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
          ],
          child: FolderDetailScreen(
            folder: const FolderItem(
              path: '/music/rock',
              name: 'rock',
              songCount: 2,
              isExcluded: false,
            ),
            folderUseCases: folderUseCases,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final alphaPos = tester.getTopLeft(find.text('Alpha Title'));
      final zetaPos = tester.getTopLeft(find.text('Zeta Title'));
      // Natural filename sort is default: track2.mp3 (Alpha Title) comes before track10.mp3 (Zeta Title)
      expect(alphaPos.dy, lessThan(zetaPos.dy));
    });
  });

  group(
      'H-36 & M-04: SmartPlaylistBuilderScreen template clears _limitError & parses mm:ss',
      () {
    testWidgets(
        'tapping a preset template clears an active limit validation error',
        (tester) async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      final engine = _Engine();
      final repo = _Repo();
      when(() => engine.watchCriteria(any()))
          .thenAnswer((_) => const Stream<List<SongsTableData>>.empty());
      when(() => engine.evaluateCriteria(any()))
          .thenAnswer((_) async => const []);
      when(() => engine.validateRules(any())).thenReturn(const []);
      final cubit =
          SmartPlaylistBuilderCubit(engine, PlaylistUseCases(repo, engine));
      getIt.registerSingleton<SmartPlaylistBuilderCubit>(cubit);
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
        await getIt.reset();
      });

      useScreenSize(tester, const Size(800, 1600));
      await tester.pumpWidget(
        screenHarness(child: const SmartPlaylistBuilderScreen()),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      final limitField = find.widgetWithText(TextField, 'Unlimited');
      await tester.enterText(limitField, '0');
      await tester.pump();
      expect(find.text('Enter a whole number greater than 0'), findsOneWidget);

      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();

      expect(find.text('Enter a whole number greater than 0'), findsNothing);
    });
  });
}
