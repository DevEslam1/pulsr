// test/features/player/player_playback_options_lyrics_test.dart
//
// Coverage for the AB-loop / bookmark / lyrics / earbud extension on
// [PlayerPlaybackOptionsController].
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/earbud_optimization_service.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/playback_bookmark_store.dart';
import 'package:pulsr/data/db/tables.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/controllers/player_playback_options_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

class _MockAudioHandler extends Mock implements PulsrAudioHandler {}

class _MockHiRes extends Mock implements HiResAudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(buildSong(0));
    registerFallbackValue(const AudioOutputInfo(
      deviceName: 'x',
      isUsbDac: false,
      sampleRate: 44100,
      bitDepth: 16,
      isBitPerfectActive: false,
    ));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PlayerPlaybackOptionsController make(
    _MockAudioHandler handler, {
    PlayerState Function()? getState,
    void Function(PlayerState)? emit,
    bool Function()? isClosed,
    Future<void> Function(Object song, {bool isOfflineOnly})? onLoadLyrics,
    EarbudOptimizationService? earbudService,
    HiResAudioService? hiRes,
  }) {
    return PlayerPlaybackOptionsController(
      audioHandler: handler,
      earbudOptimizationService: earbudService,
      hiResAudioService: hiRes,
      getState: getState ?? () => const PlayerState(),
      emit: emit ?? (_) {},
      isClosed: isClosed ?? () => false,
      onLoadLyrics: onLoadLyrics == null
          ? null
          : (song, {bool isOfflineOnly = false}) =>
              onLoadLyrics(song, isOfflineOnly: isOfflineOnly),
    );
  }

  group('AB loop', () {
    test('setAbPointA arms the loop only when B already sits later', () {
      final handler = _MockAudioHandler();
      var state = PlayerState(
        playback: const PlaybackSlice(position: Duration(seconds: 10)),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);

      controller.setAbPointA();
      expect(state.abPointA, const Duration(seconds: 10));
      expect(state.abLoopEnabled, isFalse);

      state = state.copyWith(
          playback: state.playback.copyWith(abPointB: const Duration(seconds: 5)));
      controller.setAbPointA(); // B before position -> loop stays off
      expect(state.abLoopEnabled, isFalse);

      state = state.copyWith(
          playback: state.playback.copyWith(abPointB: const Duration(seconds: 30)));
      controller.setAbPointA(); // B after position -> loop armed
      expect(state.abLoopEnabled, isTrue);
    });

    test('setAbPointB arms the loop only when A sits earlier', () {
      final handler = _MockAudioHandler();
      var state = PlayerState(
        playback: const PlaybackSlice(position: Duration(seconds: 10)),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);

      controller.setAbPointB();
      expect(state.abPointB, const Duration(seconds: 10));
      expect(state.abLoopEnabled, isFalse);

      state = state.copyWith(
          playback: state.playback.copyWith(abPointA: const Duration(seconds: 2)));
      controller.setAbPointB(); // A earlier -> armed
      expect(state.abLoopEnabled, isTrue);
    });

    test('clear, guard and toggle AB loop', () {
      final handler = _MockAudioHandler();
      var state = const PlayerState();
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);

      // Missing points: toggle is a no-op.
      controller.toggleAbLoop();
      expect(state.abLoopEnabled, isFalse);

      state = state.copyWith(
          playback: state.playback.copyWith(
              abPointA: const Duration(seconds: 1),
              abPointB: const Duration(seconds: 9)));
      controller.toggleAbLoop();
      expect(state.abLoopEnabled, isTrue);
      controller.toggleAbLoop();
      expect(state.abLoopEnabled, isFalse);

      controller.clearAbLoop();
      expect(state.abPointA, isNull);
      expect(state.abPointB, isNull);
      expect(state.abLoopEnabled, isFalse);
    });
  });

  group('bookmarks', () {
    test('seekToBookmark seeks only when a bookmark is present', () async {
      final handler = _MockAudioHandler();
      when(() => handler.seek(any())).thenAnswer((_) async {});

      var state = const PlayerState();
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);

      controller.seekToBookmark(); // null -> no seek
      verifyNever(() => handler.seek(any()));

      state = state.copyWith(
          playback: state.playback
              .copyWith(bookmarkPosition: const Duration(seconds: 42)));
      controller.seekToBookmark();
      verify(() => handler.seek(const Duration(seconds: 42))).called(1);
    });

    test('dismissBookmark clears the position', () {
      final handler = _MockAudioHandler();
      var state = PlayerState(
        playback: const PlaybackSlice(
            bookmarkPosition: Duration(seconds: 5)),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      controller.dismissBookmark();
      expect(state.bookmarkPosition, isNull);
    });

    test('saveBookmark guards, persists and emits', () async {
      final handler = _MockAudioHandler();
      final store = PlaybackBookmarkStore();
      when(() => handler.bookmarkStore).thenReturn(store);
      when(() => handler.persistBookmarks()).thenAnswer((_) async {});

      // No song.
      final noSong = make(handler);
      expect(await noSong.saveBookmark(), isFalse);

      var state = PlayerState(
        playback: PlaybackSlice(
          currentSong: buildSong(1),
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 5),
        ),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      expect(await controller.saveBookmark(), isTrue);
      expect(state.bookmarkPosition, const Duration(seconds: 30));

      // Negative position is rejected.
      state = state.copyWith(
          playback: state.playback
              .copyWith(position: const Duration(milliseconds: -5)));
      expect(await controller.saveBookmark(), isFalse);
    });

    test('saveBookmark returns false when persistence throws', () async {
      final handler = _MockAudioHandler();
      when(() => handler.bookmarkStore).thenReturn(PlaybackBookmarkStore());
      when(() => handler.persistBookmarks()).thenThrow(Exception('disk'));

      var state = PlayerState(
        playback: PlaybackSlice(
          currentSong: buildSong(1),
          position: const Duration(seconds: 30),
        ),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      expect(await controller.saveBookmark(), isFalse);
    });

    test('storedBookmarkFor reads through and swallows failures', () {
      final handler = _MockAudioHandler();
      final song = buildSong(2);
      final bookmark = PlaybackBookmark(
        trackKey: 'k',
        positionMs: 1000,
        updatedAt: DateTime(2020),
      );
      when(() => handler.recallBookmarkFor(song)).thenReturn(bookmark);
      final controller = make(handler);
      expect(controller.storedBookmarkFor(song), bookmark);

      final throwing = _MockAudioHandler();
      when(() => throwing.recallBookmarkFor(any())).thenThrow(Exception('x'));
      expect(make(throwing).storedBookmarkFor(song), isNull);
    });

    test('clearBookmark guards and emits', () async {
      final handler = _MockAudioHandler();
      final song = buildSong(3);
      when(() => handler.clearBookmarkFor(song)).thenAnswer((_) async {});

      // No song.
      expect(make(handler).clearBookmark(), completes);

      var state = PlayerState(
        playback: PlaybackSlice(
            currentSong: song,
            bookmarkPosition: const Duration(seconds: 9)),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      await controller.clearBookmark();
      expect(state.bookmarkPosition, isNull);
    });

    test('clearBookmark swallows handler failures', () async {
      final handler = _MockAudioHandler();
      final song = buildSong(3);
      when(() => handler.clearBookmarkFor(any())).thenThrow(Exception('x'));
      var state = PlayerState(playback: PlaybackSlice(currentSong: song));
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      await controller.clearBookmark();
    });
  });

  group('updateLyrics', () {
    test('empty list is rejected without emitting', () async {
      final handler = _MockAudioHandler();
      var emitted = false;
      final controller = make(handler, emit: (_) => emitted = true);
      expect(await controller.updateLyrics(const []), isFalse);
      expect(emitted, isFalse);
    });

    test('no current song emits but returns false', () async {
      final handler = _MockAudioHandler();
      final controller = make(handler);
      final lines = [
        const LyricsLine(timestamp: Duration(seconds: 1), text: 'a'),
      ];
      expect(await controller.updateLyrics(lines), isFalse);
    });

    test('non-local track caches the result and returns false', () async {
      final handler = _MockAudioHandler();
      var state = PlayerState(
        playback: PlaybackSlice(
            currentSong:
                buildSong(4, source: SongSource.youtube, path: 'ytmusic://a')),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      final lines = [
        const LyricsLine(timestamp: Duration(seconds: 1), text: 'a'),
      ];
      expect(await controller.updateLyrics(lines), isFalse);
      expect(state.lyrics, lines);
    });

    test('local track writes a sidecar .lrc and returns true', () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_lrc');
      addTearDown(() => dir.deleteSync(recursive: true));
      final audio = File('${dir.path}${Platform.pathSeparator}song.mp3')
        ..writeAsStringSync('audio');

      final handler = _MockAudioHandler();
      var state = PlayerState(
        playback: PlaybackSlice(currentSong: buildSong(5, path: audio.path)),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      final lines = [
        const LyricsLine(timestamp: Duration(seconds: 1), text: 'hello world'),
      ];
      expect(await controller.updateLyrics(lines), isTrue);
      final sidecar =
          File('${dir.path}${Platform.pathSeparator}song.lrc');
      expect(sidecar.existsSync(), isTrue);
    });

    test('local write failure is reported and returns false', () async {
      final handler = _MockAudioHandler();
      // A file used as a parent directory makes the sidecar write throw.
      final dir = Directory.systemTemp.createTempSync('pulsr_lrc_fail');
      addTearDown(() => dir.deleteSync(recursive: true));
      final blocker = File('${dir.path}${Platform.pathSeparator}blocker')
        ..writeAsStringSync('not a dir');
      final badPath =
          '${blocker.path}${Platform.pathSeparator}song.mp3';
      var state = PlayerState(
        playback: PlaybackSlice(currentSong: buildSong(6, path: badPath)),
      );
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      final lines = [
        const LyricsLine(timestamp: Duration(seconds: 1), text: 'x'),
      ];
      expect(await controller.updateLyrics(lines), isFalse);
    });
  });

  group('refreshLyrics', () {
    test('no song is a no-op', () async {
      final handler = _MockAudioHandler();
      final controller = make(handler);
      await controller.refreshLyrics();
    });

    test('with callback success flips loading off', () async {
      final handler = _MockAudioHandler();
      var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(7)));
      var loaded = 0;
      final controller = make(
        handler,
        getState: () => state,
        emit: (s) => state = s,
        onLoadLyrics: (song, {bool isOfflineOnly = false}) async {
          loaded++;
        },
      );
      await controller.refreshLyrics();
      expect(loaded, 1);
      expect(state.isLoadingLyrics, isFalse);
    });

    test('with callback throwing still clears loading', () async {
      final handler = _MockAudioHandler();
      var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(8)));
      final controller = make(
        handler,
        getState: () => state,
        emit: (s) => state = s,
        onLoadLyrics: (song, {bool isOfflineOnly = false}) async =>
            throw Exception('boom'),
      );
      await controller.refreshLyrics();
      expect(state.isLoadingLyrics, isFalse);
    });

    test('without callback clears loading immediately', () async {
      final handler = _MockAudioHandler();
      var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(9)));
      final controller =
          make(handler, getState: () => state, emit: (s) => state = s);
      await controller.refreshLyrics();
      expect(state.isLoadingLyrics, isFalse);
    });

    test('closed controller leaves loading set', () async {
      final handler = _MockAudioHandler();
      var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(10)));
      final controller = make(
        handler,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => true,
        onLoadLyrics: (song, {bool isOfflineOnly = false}) async {},
      );
      await controller.refreshLyrics();
      expect(state.isLoadingLyrics, isTrue);
    });
  });

  group('detectEarbudCapabilities', () {
    test('null service returns the default capabilities', () async {
      final handler = _MockAudioHandler();
      final caps = await make(handler).detectEarbudCapabilities();
      expect(caps.deviceName, 'Default output');
      expect(caps.codec, EarbudCodec.unknown);
    });

    test('null hi-res info still detects from the service', () async {
      final handler = _MockAudioHandler();
      final caps = await make(
        handler,
        earbudService: EarbudOptimizationService(),
      ).detectEarbudCapabilities();
      expect(caps.deviceName, 'Default output');
    });

    test('uses cached output info when present', () async {
      final handler = _MockAudioHandler();
      final hiRes = _MockHiRes();
      when(() => hiRes.currentOutputInfo).thenReturn(const AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      ));
      final caps = await make(
        handler,
        earbudService: EarbudOptimizationService(),
        hiRes: hiRes,
      ).detectEarbudCapabilities();
      expect(caps.deviceName, 'USB DAC');
      expect(caps.isUsbDac, isTrue);
    });

    test('falls back to getAudioOutputInfo and swallows throws', () async {
      final handler = _MockAudioHandler();
      final hiRes = _MockHiRes();
      when(() => hiRes.currentOutputInfo).thenReturn(null);
      when(() => hiRes.getAudioOutputInfo()).thenAnswer((_) async =>
          const AudioOutputInfo(
            deviceName: 'BT Buds',
            isUsbDac: false,
            sampleRate: 48000,
            bitDepth: 16,
            isBitPerfectActive: false,
            isBluetooth: true,
            btCodecName: 'SBC',
          ));
      final caps = await make(
        handler,
        earbudService: EarbudOptimizationService(),
        hiRes: hiRes,
      ).detectEarbudCapabilities();
      expect(caps.deviceName, 'BT Buds');

      final failing = _MockHiRes();
      when(() => failing.currentOutputInfo).thenReturn(null);
      when(() => failing.getAudioOutputInfo()).thenThrow(Exception('boom'));
      final fallback = await make(
        handler,
        earbudService: EarbudOptimizationService(),
        hiRes: failing,
      ).detectEarbudCapabilities();
      expect(fallback.deviceName, 'Default output');
    });
  });
}
