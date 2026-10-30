// Regression coverage for Quran Mode user intent.
//
// Automatic activation is a metadata heuristic (`isQuranTrack` matches
// "quran", "surah", reciter names, ...). It may drive the mode for a user who
// never touched the toggle, but it must never override an explicit choice:
// before this test, a manually enabled mode was switched off (and persisted as
// off) by the next unrelated track, and a manually disabled mode came back on.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/quran_mode_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/managers/player_quran_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

/// The shared recorder forwards unknown DSP calls through `noSuchMethod`, which
/// cannot match `setPreamp(double)`. Answer it explicitly so the Quran pass
/// runs without a logged NoSuchMethodError.
class _QuranTestHandler extends RecordingAudioHandler {
  @override
  Future<void> setPreamp(double value) async {}
}

SongsTableData _song({
  required int id,
  required String title,
  String? genre,
  String artist = 'Unknown',
}) =>
    SongsTableData(
      id: id,
      title: title,
      artist: artist,
      album: '',
      durationMs: 180000,
      path: '/music/$id.flac',
      genre: genre,
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ({
    PlayerPlaybackOptionsController controller,
    PlayerState Function() state,
    QuranModeService service,
  }) harness() {
    final service = QuranModeService();
    var state = const PlayerState();
    final controller = PlayerPlaybackOptionsController(
      audioHandler: _QuranTestHandler(),
      quranManager: PlayerQuranManager(service: service),
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => false,
    );
    return (controller: controller, state: () => state, service: service);
  }

  test('a manual "off" is not undone by a later Quran-looking track', () async {
    final h = harness();

    await h.controller.setQuranModeEnabled(true);
    await h.controller.setQuranModeEnabled(false);
    expect(h.state().isQuranModeEnabled, isFalse);
    expect(await h.service.getUserOverride(), isFalse);

    await h.controller.handleTrackChangeQuranMode(
      _song(id: 1, title: 'Surah Al-Fatiha', genre: 'Quran'),
    );

    expect(h.state().isQuranModeEnabled, isFalse,
        reason: 'explicit off must survive the metadata heuristic');
    expect(await h.service.isEnabled(), isFalse);
  });

  test('a manual "on" is not undone by a non-Quran track', () async {
    final h = harness();

    await h.controller.setQuranModeEnabled(true);
    expect(h.state().isQuranModeEnabled, isTrue);
    expect(await h.service.getUserOverride(), isTrue);

    await h.controller.handleTrackChangeQuranMode(
      _song(id: 2, title: 'Ordinary Song', artist: 'Band'),
    );

    expect(h.state().isQuranModeEnabled, isTrue,
        reason: 'a pinned mode must not be switched off automatically');
    expect(await h.service.isEnabled(), isTrue);
  });

  test('automatic activation still works for a user who never chose', () async {
    final h = harness();
    expect(await h.service.getUserOverride(), isNull);

    await h.controller.handleTrackChangeQuranMode(
      _song(id: 3, title: 'Tilawat', genre: 'Quran'),
    );

    expect(h.state().isQuranModeEnabled, isTrue);
    // An automatic activation is not a user decision.
    expect(await h.service.getUserOverride(), isNull);
  });

  test('manual toggles persist the explicit choice', () async {
    final h = harness();

    await h.controller.setQuranModeEnabled(true);
    expect(await h.service.getUserOverride(), isTrue);

    await h.controller.setQuranModeEnabled(false);
    expect(await h.service.getUserOverride(), isFalse);
  });
}
