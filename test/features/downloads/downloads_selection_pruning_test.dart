// test/features/downloads/downloads_selection_pruning_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_tile.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockDownloadsCubit extends Mock implements DownloadsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pruneSelectedVideoIds', () {
    test('drops ids that no longer have a live task', () {
      expect(
        pruneSelectedVideoIds({'a', 'b', 'c'}, {'a', 'c'}),
        {'a', 'c'},
      );
    });

    test('keeps surviving ids and clears everything when list is empty', () {
      expect(pruneSelectedVideoIds({'a'}, {'a'}), {'a'});
      expect(pruneSelectedVideoIds({'x', 'y'}, const <String>{}), isEmpty);
      expect(pruneSelectedVideoIds(const <String>{}, {'a'}), isEmpty);
    });
  });

  testWidgets(
      'selection mode exits when the selected task disappears from state',
      (tester) async {
    final controller = StreamController<DownloadsState>.broadcast();
    addTearDown(controller.close);

    final mockDownloads = MockDownloadsCubit();
    var current = DownloadsState(
      tasks: {
        'vid1': DownloadTask(
          id: 'vid1',
          videoId: 'vid1',
          title: 'Pruned Song',
          artist: 'Artist',
          createdAt: DateTime(2024),
        ),
      },
    );
    when(() => mockDownloads.state).thenAnswer((_) => current);
    when(() => mockDownloads.stream).thenAnswer((_) => controller.stream);

    await tester.pumpWidget(
      BlocProvider<DownloadsCubit>.value(
        value: mockDownloads,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DownloadsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DownloadTile), findsOneWidget);

    // Long-press enters selection mode.
    await tester.longPress(find.byType(DownloadTile));
    await tester.pump();
    expect(find.textContaining('selected'), findsOneWidget);

    // The task is removed (e.g. completed + cleared). The selection listener
    // must prune the stale id and leave selection mode.
    current = const DownloadsState();
    controller.add(current);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('selected'), findsNothing);
    expect(find.byType(DownloadTile), findsNothing);
  });
}
