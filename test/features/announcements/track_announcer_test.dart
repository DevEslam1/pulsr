// test/features/announcements/track_announcer_test.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/announcements/announcement_settings.dart';
import 'package:pulsr/features/announcements/track_announcer.dart';
import 'package:pulsr/features/announcements/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the announcer asked the engine to do.
class _FakeTtsEngine implements TtsEngine {
  _FakeTtsEngine({this.available = true});

  final bool available;
  final List<String> spoken = <String>[];
  int stopCount = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<bool> init() async => available;

  @override
  Future<void> speak(String text, {double volume = 1.0}) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {}
}

class _Harness {
  _Harness._(
      this.items, this.states, this.settings, this.engine, this.announcer);

  final StreamController<MediaItem?> items;
  final StreamController<PlaybackState> states;
  final AnnouncementSettings settings;
  final _FakeTtsEngine engine;
  final TrackAnnouncer announcer;

  static Future<_Harness> create({
    bool enabled = true,
    int delayMs = 10,
    bool engineAvailable = true,
    bool Function()? shouldSkip,
    bool Function()? isBitPerfect,
  }) async {
    final items = StreamController<MediaItem?>.broadcast();
    final states = StreamController<PlaybackState>.broadcast();
    final settings = await AnnouncementSettings.load();
    settings.setEnabled(enabled);
    settings.setDelayMs(delayMs);
    final engine = _FakeTtsEngine(available: engineAvailable);
    final announcer = TrackAnnouncer(
      mediaItemStream: items.stream,
      playbackStateStream: states.stream,
      settings: settings,
      engine: engine,
      shouldSkip: shouldSkip,
      isBitPerfect: isBitPerfect,
    )..start();
    final harness = _Harness._(items, states, settings, engine, announcer);
    addTearDown(() async {
      await announcer.dispose();
      await items.close();
      await states.close();
      settings.dispose();
    });
    return harness;
  }
}

PlaybackState _playing() => PlaybackState(
      processingState: AudioProcessingState.ready,
      playing: true,
    );

PlaybackState _paused() => PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    );

MediaItem _track(String letter) => MediaItem(
      id: letter,
      title: 'Track ${letter.toUpperCase()}',
      artist: 'Artist ${letter.toUpperCase()}',
      album: 'Album',
      duration: const Duration(minutes: 3),
    );

Future<void> _wait([int milliseconds = 60]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('announces each track once and ignores repeat emits', () async {
    final harness = await _Harness.create();
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, ['Track A, Artist A']);

    harness.items.add(_track('a'));
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, hasLength(1));
    expect(harness.announcer.announcedMediaId, 'a');
  });

  test('cancels the pending announcement when the track changes quickly',
      () async {
    final harness = await _Harness.create(delayMs: 120);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait(20);
    harness.items.add(_track('b'));
    await _wait(250);

    expect(harness.engine.spoken, ['Track B, Artist B']);
  });

  test('stays silent while playback is paused', () async {
    final harness = await _Harness.create();
    harness.states.add(_paused());
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, isEmpty);
  });

  test('stays silent when announcements are disabled', () async {
    final harness = await _Harness.create(enabled: false);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, isEmpty);
  });

  test('stays silent when the engine is unavailable', () async {
    final harness = await _Harness.create(engineAvailable: false);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, isEmpty);
  });

  test('stops speech when playback pauses', () async {
    final harness = await _Harness.create();
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();
    expect(harness.engine.spoken, hasLength(1));

    harness.states.add(_paused());
    await _wait(20);

    expect(harness.engine.stopCount, greaterThanOrEqualTo(1));
  });

  test('honours the cast skip gate', () async {
    var casting = true;
    final harness = await _Harness.create(shouldSkip: () => casting);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();
    expect(harness.engine.spoken, isEmpty);

    casting = false;
    harness.items.add(_track('a'));
    await _wait();
    expect(harness.engine.spoken, ['Track A, Artist A']);
  });

  test('speaks while casting when the cast skip toggle is off', () async {
    final harness = await _Harness.create(shouldSkip: () => true);
    harness.settings.setSkipWhenCasting(false);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, ['Track A, Artist A']);
  });

  test('honours the bit-perfect skip gate', () async {
    var bitPerfect = true;
    final harness = await _Harness.create(isBitPerfect: () => bitPerfect);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();
    expect(harness.engine.spoken, isEmpty);

    bitPerfect = false;
    harness.items.add(_track('a'));
    await _wait();
    expect(harness.engine.spoken, ['Track A, Artist A']);
  });

  test('speaks the configured delay after the track starts', () async {
    final harness = await _Harness.create(delayMs: 150);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait(60);
    expect(harness.engine.spoken, isEmpty);

    await _wait(200);
    expect(harness.engine.spoken, ['Track A, Artist A']);
  });

  test('announces a second track after the first', () async {
    final harness = await _Harness.create();
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();
    harness.items.add(_track('b'));
    await _wait();

    expect(harness.engine.spoken, ['Track A, Artist A', 'Track B, Artist B']);
  });

  test('maps media item extras onto year and track number', () {
    final item = MediaItem(
      id: 'x',
      title: 'Blue in Green',
      artist: 'Miles Davis',
      album: 'Kind of Blue',
      duration: const Duration(minutes: 5),
      extras: <String, dynamic>{'year': 1959, 'trackNumber': '3'},
    );

    final mapped = announcementTrackForMediaItem(item);
    expect(mapped.title, 'Blue in Green');
    expect(mapped.artist, 'Miles Davis');
    expect(mapped.album, 'Kind of Blue');
    expect(mapped.year, 1959);
    expect(mapped.trackNumber, 3);
    expect(mapped.discNumber, isNull);
    expect(mapped.duration, const Duration(minutes: 5));
  });

  test('composes nothing when no element is selected', () async {
    final harness = await _Harness.create();
    harness.settings.setElements(const <AnnouncementElement>[]);
    harness.states.add(_playing());
    harness.items.add(_track('a'));
    await _wait();

    expect(harness.engine.spoken, isEmpty);
  });
}
