// Regression tests for P0-1.1: a net-library file (SMB / WebDAV / FTP / SFTP
// played through the loopback proxy) is a finite, seekable stream. It must not
// be tagged as live radio (which resets the position on pause and shows the
// radio recommendation card) and must not be treated as a local file.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_queue_controller.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/presentation/widgets/radio_now_playing_recommendations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/player_test_support.dart';

/// Records every seek target so the test can prove pause/resume never rewinds
/// the stream to zero.
class _RemotePlaybackHandler extends RecordingAudioHandler {
  final List<Duration> seekTargets = <Duration>[];
  final List<String> transportOrder = <String>[];

  @override
  Future<void> seekDirect(Duration position) async {
    seekTargets.add(position);
    transportOrder.add('seek:${position.inMilliseconds}');
    await super.seekDirect(position);
  }

  @override
  Future<void> seek(Duration position) async {
    seekTargets.add(position);
    transportOrder.add('seek:${position.inMilliseconds}');
    await super.seek(position);
  }

  @override
  Future<void> pause() async {
    transportOrder.add('pause');
    await super.pause();
  }

  @override
  Future<void> play() async {
    transportOrder.add('play');
    await super.play();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SongsTableData remoteSong() => buildSong(
        -4242,
        title: 'NAS - Kind of Blue.flac',
        source: SongSource.remote,
        path: 'http://127.0.0.1:52110/stream/lib-1/Music/radio/Miles.flac',
        durationMs: 345000,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SongSource classification', () {
    test('remote is seekable network audio, not live and not local', () {
      expect(SongSource.remote, isNot(SongSource.radio));
      expect(SongSource.isLive(SongSource.remote), isFalse);
      expect(SongSource.isNetwork(SongSource.remote), isTrue);
      expect(SongSource.hasLocalFile(SongSource.remote), isFalse);
    });

    test('radio stays the only live source and local the only file source', () {
      expect(SongSource.isLive(SongSource.radio), isTrue);
      expect(SongSource.isLive(SongSource.local), isFalse);
      expect(SongSource.isLive(SongSource.youtube), isFalse);
      expect(SongSource.hasLocalFile(SongSource.local), isTrue);
      expect(SongSource.isNetwork(SongSource.local), isFalse);
      expect(SongSource.isNetwork(null), isFalse);
    });
  });

  group('Remote playback is not live radio', () {
    test('isLiveRadio is false and the radio card is hidden', () async {
      final handler = _RemotePlaybackHandler();
      final cubit = PlayerCubit(
        audioHandler: handler,
        repository: MockMusicRepository(),
        toggleFavoriteUseCase: MockToggleFavoriteUseCase(),
      );
      addTearDown(cubit.close);

      await cubit.playSong(remoteSong());

      expect(cubit.state.currentSong?.source, SongSource.remote);
      expect(cubit.queueController.isLiveRadio, isFalse);
      expect(
          RadioNowPlayingRecommendations.shouldShowFor(remoteSong()), isFalse);
      // A genuine radio row must still show it.
      expect(
          RadioNowPlayingRecommendations.shouldShowFor(
              buildSong(-5, source: SongSource.radio, path: 'https://s/radio')),
          isTrue);
    });

    test('pause keeps the position and resume continues without rewinding',
        () async {
      final handler = _RemotePlaybackHandler();
      final cubit = PlayerCubit(
        audioHandler: handler,
        repository: MockMusicRepository(),
        toggleFavoriteUseCase: MockToggleFavoriteUseCase(),
      );
      addTearDown(cubit.close);

      await cubit.playSong(remoteSong());
      // The engine is the source of truth for the position: seek into the file
      // and let the fake handler publish it, as ExoPlayer would.
      await cubit.seek(const Duration(seconds: 97));
      handler
          .positionStream.isEmpty; // touch the stream so the lint stays happy

      await cubit.pause();
      expect(handler.pauseCalls, 1);
      expect(cubit.state.position, const Duration(seconds: 97),
          reason: 'pause must not drop the position for a net-library file');

      handler.transportOrder.clear();
      handler.playCalls = 0;
      await cubit.play();
      expect(handler.playCalls, 1);
      expect(
          handler.transportOrder.where((c) => c.startsWith('seek:')), isEmpty,
          reason: 'resume must continue in place, never seek back to zero');
      expect(handler.seekTargets, isNot(contains(Duration.zero)));
    });

    test('seeking works in both directions', () async {
      final handler = _RemotePlaybackHandler();
      final cubit = PlayerCubit(
        audioHandler: handler,
        repository: MockMusicRepository(),
        toggleFavoriteUseCase: MockToggleFavoriteUseCase(),
      );
      addTearDown(cubit.close);

      await cubit.playSong(remoteSong());
      await cubit.seek(const Duration(minutes: 3));
      await cubit.seek(const Duration(seconds: 12));

      expect(handler.seekTargets, contains(const Duration(minutes: 3)));
      expect(handler.seekTargets, contains(const Duration(seconds: 12)));
      expect(cubit.state.position, const Duration(seconds: 12));
    });
  });
}
