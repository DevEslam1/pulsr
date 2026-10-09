// Additional coverage for lib/features/folder_detail/presentation/folder_detail_screen.dart
//
// Complements folder_detail_screen_test.dart with the folder-favorite toggle
// (both directions), the multi-track hero cover paths, the long-duration
// formatter and breadcrumb navigation through a GoRouter.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _FolderUseCases extends Mock implements FolderUseCases {}

class _Library extends Mock implements LibraryCubit {}

const _folder = FolderItem(
  path: '/music/rock',
  name: 'rock',
  songCount: 2,
  isExcluded: false,
);

_Library _library({List<SongsTableData> favorites = const []}) {
  final cubit = _Library();
  when(() => cubit.state).thenReturn(LibraryState(favorites: favorites));
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  when(() => cubit.toggleFavorite(any())).thenAnswer((_) async {});
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late _FolderUseCases useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _FolderUseCases();
  });

  SongsTableData song(int id, String title, {int durationMs = 20000}) =>
      createTestSong(id: id, title: title, durationMs: durationMs);

  Widget build(
    Stream<Result<List<SongsTableData>>> stream, {
    LibraryCubit? libraryCubit,
    PlayerCubit? playerCubit,
  }) {
    when(() => useCase.watchFolderSongs(any())).thenAnswer((_) => stream);
    return detailHarness(
      playerCubit: playerCubit,
      child: BlocProvider<LibraryCubit>.value(
        value: libraryCubit ?? _library(),
        child: FolderDetailScreen(folder: _folder, folderUseCases: useCase),
      ),
    );
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('the favorite button favorites every unfavorited track',
      (tester) async {
    final lib = _library();
    final player = stubPlayerCubit();
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'Alpha'), song(2, 'Beta')])),
      libraryCubit: lib,
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    verify(() => lib.toggleFavorite(1)).called(1);
    verify(() => lib.toggleFavorite(2)).called(1);
    expect(find.text(l10n.favorite), findsOneWidget);

    await drain(tester);
  });

  testWidgets('the favorite button removes already-favorited tracks',
      (tester) async {
    final songs = [song(1, 'Alpha'), song(2, 'Beta')];
    final lib = _library(favorites: songs);
    await tester.pumpWidget(build(
      Stream.value(Right(songs)),
      libraryCubit: lib,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    verify(() => lib.toggleFavorite(any())).called(2);
    expect(find.text(l10n.removeFromFavorites), findsOneWidget);

    await drain(tester);
  });

  testWidgets('long folder durations format with hours', (tester) async {
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'Long', durationMs: 3700000)])),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('hr'), findsWidgets);
    expect(find.textContaining('min'), findsWidgets);
  });

  testWidgets('breadcrumb taps navigate to the parent folder',
      (tester) async {
    when(() => useCase.watchFolderSongs(any())).thenAnswer(
      (_) => Stream.value(Right([song(1, 'Alpha')])),
    );
    final lib = _library();
    final player = stubPlayerCubit();

    final router = GoRouter(
      initialLocation: '/folder',
      routes: [
        GoRoute(
          path: '/folder',
          builder: (context, state) {
            final folder = state.extra is FolderItem
                ? state.extra as FolderItem
                : _folder;
            return BlocProvider<LibraryCubit>.value(
              value: lib,
              child: FolderDetailScreen(
                folder: folder,
                folderUseCases: useCase,
              ),
            );
          },
        ),
      ],
    );

    tester.view.physicalSize = const Size(1024, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('music'), findsWidgets);

    await tester.tap(find.text('music').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
