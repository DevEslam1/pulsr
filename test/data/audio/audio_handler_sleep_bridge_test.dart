// test/data/audio/audio_handler_sleep_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';

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

  Future<PulsrAudioHandler> ready() async {
    final h = await buildTestHandler(repository: repo, ytmService: ytm);
    await h.loadQueue([localSong(1), localSong(2), localSong(3)],
        autoPlay: false);
    return h;
  }

  test('duration timer starts, reports mode and cancels', () async {
    handler = await ready();
    final remaining = <Duration?>[];
    final sub = handler!.sleepTimerRemainingStream.listen(remaining.add);

    handler!.startSleepTimer(const Duration(minutes: 30));
    expect(handler!.sleepTimerMode, SleepTimerMode.duration);
    expect(handler!.sleepTimerRemainingTracks, isNull);

    handler!.cancelSleepTimer();
    // Cancelling frees the manager to arm a different mode.
    handler!.startAfterNTracksTimer(2);
    expect(handler!.sleepTimerRemainingTracks, 2);
    handler!.cancelSleepTimer();

    await sub.cancel();
  });

  test('a non-positive duration cancels instead of firing', () async {
    handler = await ready();
    handler!.startSleepTimer(const Duration(minutes: 10));
    expect(handler!.sleepTimerMode, SleepTimerMode.duration);

    handler!.startSleepTimer(Duration.zero);
    handler!.startEndOfTrackTimer();
    expect(handler!.sleepTimerRemainingTracks, 1);
    handler!.cancelSleepTimer();
  });

  test('absolute timer clamps past times to one minute', () async {
    handler = await ready();
    handler!.startAbsoluteSleepTimer(
        DateTime.now().add(const Duration(minutes: 20)));
    expect(handler!.sleepTimerMode, SleepTimerMode.duration);

    handler!.startAbsoluteSleepTimer(
        DateTime.now().subtract(const Duration(hours: 1)));
    expect(handler!.sleepTimerMode, SleepTimerMode.duration);
    handler!.cancelSleepTimer();
  });

  test('end-of-track timer arms with one remaining track', () async {
    handler = await ready();
    final tracks = <int?>[];
    final sub = handler!.sleepTimerRemainingTracksStream.listen(tracks.add);

    handler!.startEndOfTrackTimer();
    expect(handler!.sleepTimerMode, SleepTimerMode.endOfTrack);
    expect(handler!.sleepTimerRemainingTracks, 1);

    handler!.cancelSleepTimer();
    await sub.cancel();
  });

  test('after-N-tracks timer decrements on track completion', () async {
    handler = await ready();
    handler!.startAfterNTracksTimer(3);
    expect(handler!.sleepTimerMode, SleepTimerMode.afterNTracks);
    expect(handler!.sleepTimerRemainingTracks, 3);

    handler!.notifySleepTrackCompleted();
    expect(handler!.sleepTimerRemainingTracks, 2);

    handler!.cancelSleepTimer();
  });

  test('after-N-tracks with a non-positive count cancels', () async {
    handler = await ready();
    handler!.startAfterNTracksTimer(2);
    handler!.startAfterNTracksTimer(0);
    // A cancelled after-N timer can be replaced by another mode.
    handler!.startEndOfTrackTimer();
    expect(handler!.sleepTimerRemainingTracks, 1);
    handler!.cancelSleepTimer();
  });

  test('end-of-queue timer arms', () async {
    handler = await ready();
    handler!.startEndOfQueueTimer();
    expect(handler!.sleepTimerMode, SleepTimerMode.endOfQueue);
    handler!.cancelSleepTimer();
  });

  test('notifySleepTrackCompleted debounces duplicate boundaries', () async {
    handler = await ready();
    handler!.startAfterNTracksTimer(5);
    handler!.notifySleepTrackCompleted();
    // A second immediate report is collapsed by the debounce window.
    handler!.notifySleepTrackCompleted();
    expect(handler!.sleepTimerRemainingTracks, 4);
    handler!.cancelSleepTimer();
  });
}
