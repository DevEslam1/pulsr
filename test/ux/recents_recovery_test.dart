import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/library/presentation/recents_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSongs extends Mock implements GetSongsUseCase {}

class MockPlayer extends Mock implements PlayerCubit {}

void main() {
  for (final thrown in [false, true]) {
    testWidgets(
        'history ${thrown ? 'stream' : 'repository'} failure retries the query',
        (tester) async {
      final songs = MockSongs();
      final player = MockPlayer();
      var queries = 0;
      when(() => player.state).thenReturn(const PlayerState());
      when(() => player.stream).thenAnswer((_) => const Stream.empty());
      when(() => songs.watchRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) {
        queries++;
        if (queries > 1) {
          return Stream.value(
              const Right<AppFailure, List<SongsTableData>>([]));
        }
        return thrown
            ? Stream.error(Exception('Database unavailable'))
            : Stream.value(const Left<AppFailure, List<SongsTableData>>(
                DatabaseFailure('Database unavailable')));
      });
      getIt.registerSingleton<GetSongsUseCase>(songs);
      addTearDown(() => getIt.unregister<GetSongsUseCase>());
      await tester.pumpWidget(BlocProvider<PlayerCubit>.value(
          value: player,
          child: MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const RecentsScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No recent songs'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(queries, 2);
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.history_toggle_off_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
