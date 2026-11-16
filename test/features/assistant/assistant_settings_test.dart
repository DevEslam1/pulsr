// test/features/assistant/assistant_settings_test.dart
//
// The system-search cache is opt-in. These tests pin the default-OFF contract
// and prove that a disabled sync clears what it previously published.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/assistant/assistant_search_channel.dart';
import 'package:pulsr/features/assistant/assistant_settings.dart';
import 'package:pulsr/features/assistant/assistant_suggestion_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRepository extends Mock implements IMusicRepository {}

class _RecordingChannel extends AssistantSearchChannel {
  _RecordingChannel() : super(channel: const MethodChannel('test/assistant'));

  bool cleared = false;
  List<AssistantSuggestion> pushed = <AssistantSuggestion>[];

  @override
  Future<bool> updateSuggestions(List<AssistantSuggestion> suggestions) async {
    pushed = List<AssistantSuggestion>.from(suggestions);
    return true;
  }

  @override
  Future<bool> clear() async {
    cleared = true;
    pushed = <AssistantSuggestion>[];
    return true;
  }
}

SongsTableData _song(int id, String title) => SongsTableData(
      id: id,
      title: title,
      artist: 'Artist',
      album: 'Album',
      path: '/music/$id.flac',
      durationMs: 180000,
      playCount: 0,
      lastPositionMs: 0,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      source: SongSource.local,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockRepository repository;
  late _RecordingChannel channel;

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = _MockRepository();
    channel = _RecordingChannel();
    when(() => repository.getRecentlyPlayed(
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer(
      (_) async => Right(<SongsTableData>[
        _song(1, 'Blue in Green'),
        _song(2, 'So What'),
      ]),
    );
  });

  test('suggestions default to off and persist the opt-in', () async {
    final settings = await AssistantSettings.load();
    addTearDown(settings.dispose);

    expect(settings.suggestionsEnabled, isFalse);
    expect(AssistantSettings.defaultSuggestionsEnabled, isFalse);

    settings.setSuggestionsEnabled(true);
    expect(settings.suggestionsEnabled, isTrue);
    await Future<void>.delayed(Duration.zero);

    final restored = await AssistantSettings.load();
    addTearDown(restored.dispose);
    expect(restored.suggestionsEnabled, isTrue);
  });

  test('pushRecent does nothing but clear while disabled', () async {
    final settings = await AssistantSettings.load();
    addTearDown(settings.dispose);
    final sync = AssistantSuggestionSync(
      repository: repository,
      channel: channel,
      settings: settings,
    );

    final pushed = await sync.pushRecent();

    expect(pushed, 0);
    expect(channel.cleared, isTrue);
    expect(channel.pushed, isEmpty);
    verifyNever(() => repository.getRecentlyPlayed(
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        ));
  });

  test('pushRecent publishes rows once enabled', () async {
    final settings = await AssistantSettings.load();
    addTearDown(settings.dispose);
    settings.setSuggestionsEnabled(true);
    final sync = AssistantSuggestionSync(
      repository: repository,
      channel: channel,
      settings: settings,
    );

    final pushed = await sync.pushRecent();

    expect(pushed, 2);
    expect(channel.pushed.map((s) => s.title), ['Blue in Green', 'So What']);
    expect(channel.pushed.first.subtitle, 'Artist · Album');
    expect(channel.cleared, isFalse);
  });

  test('clear always removes cached rows, even while disabled', () async {
    final settings = await AssistantSettings.load();
    addTearDown(settings.dispose);
    final sync = AssistantSuggestionSync(
      repository: repository,
      channel: channel,
      settings: settings,
    );

    await sync.clear();

    expect(channel.cleared, isTrue);
    expect(settings.suggestionsEnabled, isFalse);
  });
}
