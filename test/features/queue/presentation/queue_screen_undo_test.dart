// The reorder-undo snackbar outlives the queue screen on the root messenger.
// Its action must use the cubit captured before the snackbar was shown, not a
// lookup from the (possibly deactivated) screen context.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/queue/presentation/queue_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('undo still reorders after the queue screen is popped',
      (tester) async {
    final songs = [
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ];
    final player = stubPlayerCubit(
      PlayerState(queueSlice: QueueSlice(queue: songs)),
    );
    when(() => player.reorderQueue(any(), any())).thenAnswer((_) async {});

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/queue',
          builder: (_, __) => BlocProvider<PlayerCubit>.value(
            value: player,
            child: const QueueScreen(),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ));
    router.push('/queue');
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 1);
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    verify(() => player.reorderQueue(0, 1)).called(1);
    verify(() => player.reorderQueue(1, 0)).called(1);
  });
}
