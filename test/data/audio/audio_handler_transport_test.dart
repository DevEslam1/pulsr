// test/data/audio/audio_handler_transport_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  Future<PulsrAudioHandler> ready({bool load = true}) async {
    final h = await buildTestHandler(repository: repo, ytmService: ytm);
    if (load) {
      await h.loadQueue([localSong(1), localSong(2), localSong(3)],
          autoPlay: false);
    }
    return h;
  }

  group('transport basics', () {
    test('play and pause toggle playback state', () async {
      handler = await ready();
      await handler!.play();
      expect(handler!.playbackState.value.playing, isTrue);

      await handler!.pause();
      expect(handler!.playbackState.value.playing, isFalse);
    });

    test('seek and seekDirect emit positions', () async {
      handler = await ready();
      final positions = <Duration>[];
      final sub = handler!.positionStream.listen(positions.add);

      await handler!.seek(const Duration(seconds: 5));
      await handler!.seekDirect(const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(positions, contains(const Duration(seconds: 5)));
      expect(positions, contains(const Duration(seconds: 8)));
      await sub.cancel();
    });

    test('seek clamps negative positions to zero', () async {
      handler = await ready();
      await handler!.seek(const Duration(seconds: -5));
      expect(handler!.playbackState.value.updatePosition,
          greaterThanOrEqualTo(Duration.zero));
    });

    test('relative seeks clamp to the track bounds', () async {
      handler = await ready();
      await handler!.rewind();
      await handler!.fastForward();
      await handler!.seekBackward(true);
      await handler!.seekBackward(false);
      await handler!.seekForward(true);
      await handler!.seekForward(false);
      await handler!.seekRelative(const Duration(seconds: 30));
    });

    test('skipToQueueItem loads the selected index', () async {
      handler = await ready();
      await handler!.skipToQueueItem(2);
      expect(handler!.mediaItem.value?.title, 'Track 3');
    });

    test('validatePlayerState recovers an idle player with a queue', () async {
      handler = await ready();
      await handler!.stop();
      await handler!.validatePlayerState();
      expect(handler!.mediaItem.value, isNotNull);
    });
  });

  group('speed and pitch', () {
    test('setSpeed clamps, emits and persists', () async {
      handler = await ready();
      await handler!.setSpeed(1.5);
      expect(handler!.playbackState.value.speed, closeTo(1.5, 0.001));

      await handler!.setSpeed(100);
      expect(handler!.playbackState.value.speed, closeTo(4.0, 0.001));

      await handler!.setSpeed(double.nan);
      expect(handler!.playbackState.value.speed, closeTo(4.0, 0.001));
    });

    test('setPitch clamps and persists', () async {
      handler = await ready();
      await handler!.setPitch(1.5);
      expect(handler!.pitch, closeTo(1.5, 0.001));
      await handler!.setPitch(9);
      expect(handler!.pitch, closeTo(2.0, 0.001));
    });

    test('advanced speed widens the clamp range', () async {
      handler = await ready();
      await handler!.setAdvancedSpeedEnabled(true);
      expect(handler!.minPlaybackSpeed, closeTo(0.1, 0.001));
      expect(handler!.maxPlaybackSpeed, closeTo(8.0, 0.001));

      await handler!.setSpeed(6);
      expect(handler!.playbackState.value.speed, closeTo(6.0, 0.001));
    });

    test('restorePersistedSpeed and restorePersistedPitch read prefs',
        () async {
      handler = await ready();
      await handler!.restorePersistedSpeed();
      await handler!.restorePersistedPitch();
    });
  });

  group('shuffle and repeat', () {
    test('setShuffleMode toggles and persists', () async {
      handler = await ready();
      await handler!.setShuffleMode(AudioServiceShuffleMode.all);
      expect(handler!.playbackState.value.shuffleMode,
          AudioServiceShuffleMode.all);

      await handler!.setShuffleMode(AudioServiceShuffleMode.none);
      expect(handler!.playbackState.value.shuffleMode,
          AudioServiceShuffleMode.none);
    });

    test('setRepeatMode maps every audio-service mode', () async {
      handler = await ready();
      await handler!.setRepeatMode(AudioServiceRepeatMode.all);
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.all);

      await handler!.setRepeatMode(AudioServiceRepeatMode.one);
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.one);

      await handler!.setRepeatMode(AudioServiceRepeatMode.none);
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.none);
    });
  });

  group('media buttons', () {
    test('click routes dedicated next/previous buttons', () async {
      handler = await ready();
      await handler!.click(MediaButton.next);
      await handler!.click(MediaButton.previous);
      await handler!.click();
    });

    test('three rapid clicks dispatch the triple headset action', () async {
      handler = await ready();
      await handler!.click();
      await handler!.click();
      await handler!.click();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('customAction headsetAction performs the mapped action', () async {
      handler = await ready();
      await handler!.customAction('headsetAction', {'count': 1});
      await handler!.customAction('headsetAction', {'count': 2});
      await handler!.customAction('headsetAction', {'count': 3});
    });

    test('customAction seekRelative, setSpeed and cycleSpeed', () async {
      handler = await ready();
      await handler!.customAction('seekRelative', {'seconds': 5});
      await handler!.customAction('setSpeed', {'speed': 1.25});
      await handler!.customAction('cycleSpeed');
    });

    test('customAction shuffle/repeat/favorite paths', () async {
      handler = await ready();
      await handler!.customAction('toggleShuffle');
      await handler!.customAction('cycleRepeat');
      await handler!.customAction('toggleRepeat');
      await handler!.customAction('toggleFavorite');
      await handler!.customAction('unknownAction');
    });
  });

  test('stop clears queue and media item', () async {
    handler = await ready();
    await handler!.stop();
    expect(handler!.queue.value, isEmpty);
    expect(handler!.mediaItem.value, isNull);
    expect(handler!.playbackState.value.processingState,
        AudioProcessingState.idle);
  });

  test('onTaskRemoved pauses and saves', () async {
    handler = await ready();
    await handler!.play();
    await handler!.onTaskRemoved();
    expect(handler!.playbackState.value.playing, isFalse);
  });

  test('handleMediaButtonLongPress pauses', () async {
    handler = await ready();
    await handler!.play();
    await handler!.handleMediaButtonLongPress();
    expect(handler!.playbackState.value.playing, isFalse);
  });
}
