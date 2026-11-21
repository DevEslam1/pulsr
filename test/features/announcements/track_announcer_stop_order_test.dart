// Regression test for P0-1.10: with a 0 ms delay, a rapid track change used to
// fire stop() and speak() concurrently, so the previous track's stop could
// silence the new announcement. The announcer must await the in-flight stop
// before speaking.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/announcements/announcement_settings.dart';
import 'package:pulsr/features/announcements/track_announcer.dart';
import 'package:pulsr/features/announcements/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the call order and completes [stop] slowly, the way a platform TTS
/// engine acknowledges a cancel after a round-trip.
class _SlowStopEngine implements TtsEngine {
  final List<String> calls = <String>[];

  @override
  bool get isAvailable => true;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> speak(String text,
      {double volume = 1.0, bool duckAudio = false}) async {
    calls.add('speak:$text');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 0 ms delay still delivers stop before the new speak', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = await AnnouncementSettings.load();
    settings.setEnabled(true);
    settings.setDelayMs(0);
    settings.setElementEnabled(AnnouncementElement.title, true);
    settings.setElementEnabled(AnnouncementElement.artist, false);
    settings.setElementEnabled(AnnouncementElement.album, false);
    settings.setElementEnabled(AnnouncementElement.year, false);
    settings.setElementEnabled(AnnouncementElement.trackNumber, false);

    final items = StreamController<MediaItem?>.broadcast();
    final states = StreamController<PlaybackState>.broadcast();
    final engine = _SlowStopEngine();
    final announcer = TrackAnnouncer(
      mediaItemStream: items.stream,
      playbackStateStream: states.stream,
      settings: settings,
      engine: engine,
    )..start();
    addTearDown(() async {
      await announcer.dispose();
      await items.close();
      await states.close();
      settings.dispose();
    });

    states.add(PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
    items.add(const MediaItem(id: 'track-1', title: 'First Song'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.calls.where((call) => call.startsWith('speak')).length, 1);

    // Rapid skip while the first announcement's speech is live.
    items.add(const MediaItem(id: 'track-2', title: 'Second Song'));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final stopIndex = engine.calls.indexOf('stop');
    final secondSpeakIndex = engine.calls.indexOf('speak:Second Song');

    expect(stopIndex, isNot(-1));
    expect(secondSpeakIndex, isNot(-1));
    expect(stopIndex, lessThan(secondSpeakIndex),
        reason: 'the new sentence must wait for the pending stop');

    // And the new sentence is the last thing the engine was asked to do.
    expect(engine.calls.last, 'speak:Second Song');
  });

  test('stale track announcement is skipped if currentItem changed during pendingStop', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = await AnnouncementSettings.load();
    settings.setEnabled(true);
    settings.setDelayMs(0);
    settings.setElementEnabled(AnnouncementElement.title, true);
    settings.setElementEnabled(AnnouncementElement.artist, false);
    settings.setElementEnabled(AnnouncementElement.album, false);
    settings.setElementEnabled(AnnouncementElement.year, false);
    settings.setElementEnabled(AnnouncementElement.trackNumber, false);

    final items = StreamController<MediaItem?>.broadcast();
    final states = StreamController<PlaybackState>.broadcast();
    final engine = _SlowStopEngine();
    final announcer = TrackAnnouncer(
      mediaItemStream: items.stream,
      playbackStateStream: states.stream,
      settings: settings,
      engine: engine,
    )..start();
    addTearDown(() async {
      await announcer.dispose();
      await items.close();
      await states.close();
      settings.dispose();
    });

    states.add(PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
    items.add(const MediaItem(id: 'track-1', title: 'First Song'));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Rapid track skip 1 -> 2 -> 3 in quick succession
    items.add(const MediaItem(id: 'track-2', title: 'Second Song'));
    items.add(const MediaItem(id: 'track-3', title: 'Third Song'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(engine.calls.contains('speak:Second Song'), isFalse);
    expect(engine.calls.contains('speak:Third Song'), isTrue);
  });

  test('MethodChannelTtsEngine dispose disposes availability ValueNotifier', () async {
    final engine = MethodChannelTtsEngine();
    expect(engine.availability.value, isFalse);
    await engine.dispose();
    expect(() => engine.availability.addListener(() {}), throwsFlutterError);
  });
}
