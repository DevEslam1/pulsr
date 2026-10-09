// SmartPlaylistBuilderScreen widget suite.
//
// Drives the create/edit chrome, rule mutation, the limit validator, preset
// template application, the empty preview and the save validation path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_cubit.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';

class _Engine extends Mock implements ISmartPlaylistEngine {}

class _Repo extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Engine engine;
  late _Repo repo;
  late SmartPlaylistBuilderCubit cubit;

  setUpAll(() {
    registerFallbackValue(const SmartCriteria());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine = _Engine();
    repo = _Repo();
    when(() => engine.watchCriteria(any()))
        .thenAnswer((_) => const Stream<List<SongsTableData>>.empty());
    when(() => engine.evaluateCriteria(any()))
        .thenAnswer((_) async => const []);
    cubit = SmartPlaylistBuilderCubit(engine, PlaylistUseCases(repo, engine));
    getIt.registerSingleton<SmartPlaylistBuilderCubit>(cubit);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
      await getIt.reset();
    });
  });

  Future<void> pumpBuilder(WidgetTester tester,
      {PlaylistsTableData? initial}) async {
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(screenHarness(
        child: SmartPlaylistBuilderScreen(initialPlaylist: initial)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the create-mode chrome and the empty preview',
      (tester) async {
    await pumpBuilder(tester);

    expect(find.text('New Smart Playlist'), findsOneWidget);
    expect(find.text('Playlist Name'), findsOneWidget);
    expect(find.text('Match All Rules'), findsOneWidget);
    expect(find.text('Match Any Rule'), findsOneWidget);
    expect(find.text('RULES'), findsOneWidget);
    expect(find.text('MATCHING TRACKS PREVIEW'), findsOneWidget);
    expect(find.text('No tracks match the selected rules.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('adds a rule card when Add Rule is tapped', (tester) async {
    await pumpBuilder(tester);

    expect(
        find.byType(DropdownButtonFormField<SmartRuleField>), findsOneWidget);

    await tester.tap(find.text('Add Rule'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<SmartRuleField>),
        findsNWidgets(2));
  });

  testWidgets('rejects a non-positive track limit and clears on a valid one',
      (tester) async {
    await pumpBuilder(tester);

    final limitField = find.widgetWithText(TextField, 'Unlimited');
    expect(limitField, findsOneWidget);

    await tester.enterText(limitField, '0');
    await tester.pump();
    expect(find.text('Enter a whole number greater than 0'), findsOneWidget);

    await tester.enterText(limitField, '20');
    await tester.pump();
    expect(find.text('Enter a whole number greater than 0'), findsNothing);
  });

  testWidgets('applying a preset template seeds the name when empty',
      (tester) async {
    await pumpBuilder(tester);

    final chips = find.byType(ActionChip);
    expect(chips, findsWidgets);

    await tester.tap(chips.first);
    await tester.pumpAndSettle();

    // The selected template's name lands in the (previously empty) name field.
    final nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'e.g. 80s Rock Hits, Heavy Rotation...'));
    expect(nameField.controller!.text, isNotEmpty);
  });

  testWidgets('saving with an empty name surfaces the validation error',
      (tester) async {
    await pumpBuilder(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Please enter a playlist name'), findsOneWidget);
  });

  testWidgets('saving a named playlist creates a smart playlist',
      (tester) async {
    when(() => repo.createPlaylist(any(),
            isSmart: any(named: 'isSmart'),
            smartCriteria: any(named: 'smartCriteria')))
        .thenAnswer((_) async => const Right(1));

    await pumpBuilder(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'e.g. 80s Rock Hits, Heavy Rotation...'),
        'My Smart Mix');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => repo.createPlaylist(
          'My Smart Mix',
          isSmart: true,
          smartCriteria: any(named: 'smartCriteria'),
        )).called(1);
  });

  testWidgets('renders edit mode when seeded with an existing playlist',
      (tester) async {
    final existing = PlaylistsTableData(
      id: 42,
      name: 'My Smart',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      isSmart: true,
      smartCriteria:
          '{"rules":[{"field":"year","operator":">","value":"2000"}],"matchAll":true,"sortAscending":true}',
    );

    await pumpBuilder(tester, initial: existing);

    expect(find.text('Edit Playlist'), findsOneWidget);
    final nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'e.g. 80s Rock Hits, Heavy Rotation...'));
    expect(nameField.controller!.text, 'My Smart');
  });
}
