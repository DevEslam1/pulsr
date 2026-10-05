// SmartPlaylistBuilderCubit behavioural suite.
//
// Covers the rule builder's full lifecycle: rule mutation, match-all toggle,
// limit/sort, debounced preview (with the 100-row cap and stale-generation
// guard), initial seeding, edit mode rehydration, save validation and the
// success/failure paths.
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_cubit.dart';

import '../../helpers/test_song_factory.dart';

class _Engine extends Mock implements ISmartPlaylistEngine {}

class _Repository extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Engine engine;
  late PlaylistUseCases useCases;

  final emittedCriteria = <SmartCriteria>[];

  setUpAll(() {
    registerFallbackValue(const SmartCriteria());
  });

  setUp(() {
    engine = _Engine();
    useCases = PlaylistUseCases(_Repository(), engine);
    emittedCriteria.clear();
    when(() => engine.watchCriteria(any()))
        .thenAnswer((invocation) {
      emittedCriteria
          .add(invocation.positionalArguments.first as SmartCriteria);
      return const Stream<List<SongsTableData>>.empty();
    });
    when(() => engine.evaluateCriteria(any()))
        .thenAnswer((_) async => const []);
  });

  group('initial state', () {
    test('seeds one default playCount rule and matchAll on', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      expect(cubit.state.criteria.rules, hasLength(1));
      expect(cubit.state.criteria.rules.first.field, SmartRuleField.playCount);
      expect(cubit.state.criteria.rules.first.operator,
          SmartOperator.greaterThan);
      expect(cubit.state.criteria.rules.first.value, '0');
      expect(cubit.state.criteria.matchAll, isTrue);
      expect(cubit.state.isEditing, isFalse);
      await cubit.close();
    });

    test('constructor schedules a debounced preview query', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emittedCriteria, isNotEmpty);
      await cubit.close();
    });
  });

  group('rule mutation', () {
    test('addRule appends and re-runs the preview', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      cubit.addRule(const SmartRule(
        field: SmartRuleField.isFavorite,
        operator: SmartOperator.equals,
        value: 'true',
      ));
      expect(cubit.state.criteria.rules, hasLength(2));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emittedCriteria.length, greaterThanOrEqualTo(1));
      await cubit.close();
    });

    test('removeRule drops by index and ignores out-of-range', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      cubit.addRule(const SmartRule(
          field: SmartRuleField.artist,
          operator: SmartOperator.contains,
          value: 'A'));
      cubit.removeRule(0);
      expect(cubit.state.criteria.rules, hasLength(1));
      final before = cubit.state.criteria.rules.length;
      cubit.removeRule(-1);
      cubit.removeRule(99);
      expect(cubit.state.criteria.rules, hasLength(before));
      await cubit.close();
    });

    test('updateRule replaces by index and ignores out-of-range', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      const replacement = SmartRule(
        field: SmartRuleField.album,
        operator: SmartOperator.equals,
        value: 'AlbumX',
      );
      cubit.updateRule(0, replacement);
      expect(cubit.state.criteria.rules.first.field, SmartRuleField.album);
      expect(cubit.state.criteria.rules.first.value, 'AlbumX');
      final snapshot = cubit.state.criteria.rules;
      cubit.updateRule(5, replacement);
      expect(cubit.state.criteria.rules, snapshot);
      await cubit.close();
    });

    test('toggleMatchAll flips the conjunction mode', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      expect(cubit.state.criteria.matchAll, isTrue);
      cubit.toggleMatchAll(false);
      expect(cubit.state.criteria.matchAll, isFalse);
      cubit.toggleMatchAll(true);
      expect(cubit.state.criteria.matchAll, isTrue);
      await cubit.close();
    });

    test('setLimit and setSortBy update criteria', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      cubit.setLimit(25);
      expect(cubit.state.criteria.limit, 25);
      cubit.setSortBy('title', sortAscending: false);
      expect(cubit.state.criteria.sortBy, 'title');
      expect(cubit.state.criteria.sortAscending, isFalse);
      await cubit.close();
    });

    test('applyTemplate replaces the rule set', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      cubit.applyTemplate(const SmartCriteria(
        rules: [
          SmartRule(
              field: SmartRuleField.rating,
              operator: SmartOperator.greaterThanOrEqual,
              value: '4'),
        ],
        limit: 50,
      ));
      expect(cubit.state.criteria.rules, hasLength(1));
      expect(cubit.state.criteria.rules.first.field, SmartRuleField.rating);
      expect(cubit.state.criteria.limit, 50);
      await cubit.close();
    });
  });

  group('preview', () {
    test('emits songs and flags truncation above the 100-row cap', () async {
      final many = List.generate(
          150, (i) => createTestSong(id: i + 1, title: 'Song $i'));
      final controller = StreamController<List<SongsTableData>>.broadcast();
      when(() => engine.watchCriteria(any()))
          .thenAnswer((_) => controller.stream);

      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      cubit.addRule(const SmartRule(
          field: SmartRuleField.title,
          operator: SmartOperator.contains,
          value: 'Song'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      controller.add(many);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.previewSongs, hasLength(100));
      expect(cubit.state.previewTruncated, isTrue,
          reason: 'results above the cap must flag truncation');
      await cubit.close();
      await controller.close();
    });

    test('caps the engine query at previewCap + 1', () async {
      final controller = StreamController<List<SongsTableData>>.broadcast();
      when(() => engine.watchCriteria(any())).thenAnswer((invocation) {
        emittedCriteria
            .add(invocation.positionalArguments.first as SmartCriteria);
        return controller.stream;
      });

      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      cubit.setLimit(100000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emittedCriteria.last.limit,
          SmartPlaylistBuilderCubit.previewCap + 1);
      await cubit.close();
      await controller.close();
    });

    test('preview errors degrade to an empty, untruncated list', () async {
      final controller = StreamController<List<SongsTableData>>.broadcast();
      when(() => engine.watchCriteria(any()))
          .thenAnswer((_) => controller.stream);

      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      controller.addError(Exception('db down'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.previewSongs, isEmpty);
      expect(cubit.state.previewTruncated, isFalse);
      await cubit.close();
      await controller.close();
    });

    test('a rapid second edit cancels the stale preview subscription',
        () async {
      final controllerA = StreamController<List<SongsTableData>>.broadcast();
      final controllerB = StreamController<List<SongsTableData>>.broadcast();
      var calls = 0;
      when(() => engine.watchCriteria(any())).thenAnswer((_) {
        calls++;
        return calls == 1 ? controllerA.stream : controllerB.stream;
      });

      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      cubit.addRule(const SmartRule(
          field: SmartRuleField.genre,
          operator: SmartOperator.equals,
          value: 'Rock'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // The first controller belongs to a superseded generation; feeding it
      // must not change state.
      controllerA.add([createTestSong(id: 999, title: 'Stale')]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cubit.state.previewSongs, isEmpty);

      controllerB.add([createTestSong(id: 1, title: 'Fresh')]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cubit.state.previewSongs.single.title, 'Fresh');
      await cubit.close();
      await controllerA.close();
      await controllerB.close();
    });
  });

  group('edit mode', () {
    test('initWithPlaylist rehydrates name, criteria and id', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      final playlist = PlaylistsTableData(
        id: 42,
        name: 'My Smart',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        isSmart: true,
        smartCriteria:
            '{"rules":[{"field":"year","operator":">","value":"2000"}],"matchAll":true,"sortAscending":true}',
      );
      cubit.initWithPlaylist(playlist);
      expect(cubit.state.isEditing, isTrue);
      expect(cubit.state.editingPlaylistId, 42);
      expect(cubit.state.name, 'My Smart');
      expect(cubit.state.criteria.rules.first.field, SmartRuleField.year);
      await cubit.close();
    });

    test('initWithPlaylist with null criteria uses an empty rule set', () async {
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);
      final playlist = PlaylistsTableData(
        id: 7,
        name: 'Plain',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        isSmart: false,
      );
      cubit.initWithPlaylist(playlist);
      expect(cubit.state.criteria.rules, isEmpty);
      expect(cubit.state.editingPlaylistId, 7);
      await cubit.close();
    });
  });

  group('save', () {
    _Repository repo(bool ok) {
      final r = _Repository();
      when(() => r.createPlaylist(any(),
              isSmart: any(named: 'isSmart'),
              smartCriteria: any(named: 'smartCriteria')))
          .thenAnswer((_) async => ok
              ? const Right(1)
              : Left(const DatabaseFailure('nope')));
      when(() => r.updateSmartPlaylist(any(), any(), any()))
          .thenAnswer((_) async =>
              ok ? const Right(null) : Left(const DatabaseFailure('nope')));
      return r;
    }

    test('rejects an empty name', () async {
      final cubit = SmartPlaylistBuilderCubit(_Engine(), useCases);
      final saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, isNotNull);
      await cubit.close();
    });

    test('rejects a rule set with no rules', () async {
      final cubit = SmartPlaylistBuilderCubit(_Engine(), useCases);
      cubit.updateName('Valid');
      cubit.removeRule(0);
      final saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, isNotNull);
      await cubit.close();
    });

    test('rejects a non-boolean rule with an empty value', () async {
      final cubit = SmartPlaylistBuilderCubit(_Engine(), useCases);
      cubit.updateName('Valid');
      cubit.addRule(const SmartRule(
          field: SmartRuleField.artist,
          operator: SmartOperator.equals,
          value: ''));
      final saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, contains('rule #2'));
      await cubit.close();
    });

    test('normalises an empty boolean rule to false instead of rejecting',
        () async {
      final r = repo(true);
      final cubit = SmartPlaylistBuilderCubit(_Engine(), PlaylistUseCases(r, engine));
      cubit.updateName('Favorites only');
      cubit
        ..removeRule(0)
        ..addRule(const SmartRule(
            field: SmartRuleField.isFavorite,
            operator: SmartOperator.equals,
            value: ''));
      final saved = await cubit.savePlaylist();
      expect(saved, isTrue, reason: 'empty bool rule is normalised to false');
      verify(() => r.createPlaylist(
            'Favorites only',
            isSmart: true,
            smartCriteria: any(named: 'smartCriteria'),
          )).called(1);
      await cubit.close();
    });

    test('creates a new playlist on success', () async {
      final r = repo(true);
      final cubit =
          SmartPlaylistBuilderCubit(_Engine(), PlaylistUseCases(r, engine));
      cubit.updateName('New');
      final saved = await cubit.savePlaylist();
      expect(saved, isTrue);
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.errorMessage, isNull);
      await cubit.close();
    });

    test('surfaces a failure message when the repository rejects', () async {
      final r = repo(false);
      final cubit =
          SmartPlaylistBuilderCubit(_Engine(), PlaylistUseCases(r, engine));
      cubit.updateName('New');
      final saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, isNotNull);
      await cubit.close();
    });

    test('updates the existing playlist when editing', () async {
      final r = repo(true);
      final cubit =
          SmartPlaylistBuilderCubit(_Engine(), PlaylistUseCases(r, engine));
      cubit.initWithPlaylist(PlaylistsTableData(
          id: 5,
          name: 'Edit me',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          isSmart: true,
          smartCriteria:
              '{"rules":[{"field":"playCount","operator":">","value":"3"}],"matchAll":true,"sortAscending":true}'));
      final saved = await cubit.savePlaylist();
      expect(saved, isTrue);
      verify(() => r.updateSmartPlaylist(5, 'Edit me', any())).called(1);
      await cubit.close();
    });
  });
}
