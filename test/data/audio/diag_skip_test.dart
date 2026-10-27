// TEMP diagnostic: press Next while the player is still preparing a source.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'handler_test_harness.dart';

class SlowNativePlayer extends FakeNativeAudioPlayer {
  SlowNativePlayer(super.id);
  @override
  Future<LoadResponse> load(LoadRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.load(request);
  }
}

class SlowPlatform extends FakeJustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = SlowNativePlayer(request.id);
    players[request.id] = player;
    return player;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late SlowPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    platform = SlowPlatform();
    JustAudioPlatform.instance = platform;
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  test('DIAG next during source preparation', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);

    final loadFuture = handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    // Still inside the native load window: nothing is playing yet.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // ignore: avoid_print
    print('before-skip title=${handler!.mediaItem.value?.title} '
        'bb=${handler!.playbackState.value.playing} '
        'fakes=${platform.players.values.map((p) => p.playing).toList()}');

    await handler!.skipToNext();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // ignore: avoid_print
    print('after-skip  title=${handler!.mediaItem.value?.title} '
        'bb=${handler!.playbackState.value.playing} '
        'state=${handler!.playbackState.value.processingState} '
        'fakes=${platform.players.values.map((p) => p.playing).toList()}');
    await loadFuture.timeout(const Duration(seconds: 5)).catchError((_) {});

    expect(handler!.mediaItem.value?.title, 'Track 2');
    expect(platform.players.values.any((p) => p.playing), isTrue,
        reason:
            'Next during preparation must start the successor, not park it');
  }, timeout: const Timeout(Duration(seconds: 40)));
}
