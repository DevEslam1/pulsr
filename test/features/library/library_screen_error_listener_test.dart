// Covers the LibraryScreen errorMessage listener: a failed songs/albums/
// artists/folders stream surfaces a SnackBar and the message is consumed via
// clearError() instead of leaving the empty state unexplained.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_test_harness.dart';

import 'package:pulsr/core/errors/app_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
  });

  testWidgets(
      'a stream error over loaded content surfaces a toast and consumes the message',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final controller = StreamController<LibraryState>.broadcast();
    addTearDown(controller.close);
    final loaded = LibraryState(songs: [testSong(id: 1)]);
    final cubit = stubLibraryCubit(
      loaded,
      stream: controller.stream,
    );

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pump();

    controller.add(loaded.copyWith(error: uiError('read failed')));
    await tester.pumpAndSettle();

    expect(find.text('read failed'), findsOneWidget);
    verify(() => cubit.clearError()).called(1);
  });

  testWidgets(
      'a stream error with no content keeps the error card without clearing error',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final controller = StreamController<LibraryState>.broadcast();
    addTearDown(controller.close);
    final cubit = stubLibraryCubit(
      const LibraryState(),
      stream: controller.stream,
    );

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pump();

    controller.add(LibraryState(error: uiError('read failed')));
    await tester.pumpAndSettle();

    expect(find.text('read failed'), findsOneWidget);
    verifyNever(() => cubit.clearError());
  });

  testWidgets('an infoMessage still renders its own SnackBar', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final controller = StreamController<LibraryState>.broadcast();
    addTearDown(controller.close);
    final cubit = stubLibraryCubit(
      const LibraryState(),
      stream: controller.stream,
    );

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pump();

    controller.add(const LibraryState(infoMessage: 'cap reached'));
    await tester.pumpAndSettle();

    expect(find.text('cap reached'), findsOneWidget);
    verifyNever(() => cubit.clearError());
  });
}
