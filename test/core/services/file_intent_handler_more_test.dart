// test/core/services/file_intent_handler_more_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.fileOpener);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MockMusicRepository repository;
  late MockPlayerCubit playerCubit;
  late FileIntentHandler handler;

  const existingSong = SongsTableData(
    id: 7,
    title: 'Library Song',
    artist: 'Artist',
    album: 'Album',
    durationMs: 1000,
    path: '/music/library.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
  );

  setUpAll(() {
    registerFallbackValue(const SongsTableData(
      id: 1,
      title: 'fallback',
      artist: 'fallback',
      album: 'fallback',
      durationMs: 1,
      path: '/fallback.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    ));
  });

  setUp(() {
    repository = MockMusicRepository();
    playerCubit = MockPlayerCubit();
    when(() => playerCubit.playSong(any())).thenAnswer((_) async {});
    when(() => repository.getSongByPath(any()))
        .thenAnswer((_) async => const Right(null));
    when(() => repository.getSongByUri(any()))
        .thenAnswer((_) async => const Right(null));
    when(() => repository.watchAllSongs(
            searchQuery: any(named: 'searchQuery'),
            limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
    handler = FileIntentHandler(repository, playerCubit);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('extractYouTubeVideoId extra branches', () {
    test('rejects empty, over-long and plain dotted inputs', () {
      expect(FileIntentHandler.extractYouTubeVideoId(''), isNull);
      expect(FileIntentHandler.extractYouTubeVideoId('   '), isNull);
      expect(
          FileIntentHandler.extractYouTubeVideoId('a' * 2049), isNull);
      expect(FileIntentHandler.extractYouTubeVideoId('not.a.video.id'), isNull);
    });

    test('long regex supports embed, v and nocookie hosts', () {
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://www.youtube.com/embed/dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://youtube.com/v/dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
    });

    test('fallback query parameter is honoured for youtube hosts', () {
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://youtube.com/playlist?list=PL123&v=dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      // No youtube host and no fallback match -> null.
      expect(
          FileIntentHandler.extractYouTubeVideoId('https://example.com/?v=x'),
          isNull);
    });
  });

  group('handleAudioUri', () {
    test('routes a pulsr voice-search URI through handleVoiceSearch', () async {
      await handler.handleAudioUri('pulsr://voice-search?query=hello');
      verify(() => repository.watchAllSongs(
          searchQuery: 'hello', limit: 1)).called(1);
    });

    test('plays a song when only the original URI matches', () async {
      when(() => repository.getSongByUri('/tmp/my%20song.mp3'))
          .thenAnswer((_) async => const Right(existingSong));

      await handler.handleAudioUri('/tmp/my%20song.mp3');

      verify(() => repository.getSongByPath('/tmp/my song.mp3')).called(1);
      verify(() => repository.getSongByUri('/tmp/my%20song.mp3')).called(1);
      verify(() => playerCubit.playSong(existingSong)).called(1);
    });

    test('builds a synthetic song for an external file and records its size',
        () async {
      final temp = Directory.systemTemp.createTempSync('fih_file');
      addTearDown(() => temp.deleteSync(recursive: true));
      final audio = File('${temp.path}${Platform.pathSeparator}external.flac')
        ..writeAsStringSync('abcde');

      await handler.handleAudioUri(audio.path);

      final captured =
          verify(() => playerCubit.playSong(captureAny())).captured;
      final song = captured.single as SongsTableData;
      expect(song.title, 'external');
      expect(song.fileSize, 5);
      expect(song.id, isNegative);
      expect(song.artist, 'External Audio');
    });

    test('extracts a title from a content:// URI', () async {
      await handler
          .handleAudioUri('content://media/external/audio/1/My%20Song.mp3');

      final captured =
          verify(() => playerCubit.playSong(captureAny())).captured;
      final song = captured.single as SongsTableData;
      expect(song.title, 'My Song');
      expect(song.path, 'content://media/external/audio/1/My Song.mp3');
      expect(song.uri, 'content://media/external/audio/1/My%20Song.mp3');
    });

    test('treats an invalid percent escape as a literal path', () async {
      await handler.handleAudioUri('/music/bad%zz.mp3');
      verify(() => repository.getSongByPath('/music/bad%zz.mp3')).called(1);
    });

    test('imports proxies from a text file', () async {
      final temp = Directory.systemTemp.createTempSync('fih_proxy');
      addTearDown(() => temp.deleteSync(recursive: true));
      final list = File('${temp.path}${Platform.pathSeparator}proxies.txt')
        ..writeAsStringSync('proxy.example.com:8080\n');

      await handler.handleAudioUri(list.path);

      verifyNever(() => playerCubit.playSong(any()));
    });

    test('imports proxies from a bare proxy string', () async {
      await handler.handleAudioUri('proxy.example.com:8080');
      verifyNever(() => playerCubit.playSong(any()));
    });

    test('reports unsupported formats without playing', () async {
      await handler.handleAudioUri('#');
      verifyNever(() => playerCubit.playSong(any()));
    });

    test('swallows errors from the repository', () async {
      when(() => repository.getSongByPath(any()))
          .thenThrow(StateError('boom'));
      await handler.handleAudioUri('/music/explode.mp3');
      verifyNever(() => playerCubit.playSong(any()));
    });
  });

  group('handleVoiceSearch', () {
    test('ignores a blank query', () async {
      await handler.handleVoiceSearch('   ');
      verifyNever(() => repository.watchAllSongs(
          searchQuery: any(named: 'searchQuery'),
          limit: any(named: 'limit')));
    });

    test('plays the first matching song', () async {
      when(() => repository.watchAllSongs(
              searchQuery: any(named: 'searchQuery'),
              limit: any(named: 'limit')))
          .thenAnswer((_) => Stream.value(const Right([existingSong])));

      await handler.handleVoiceSearch('library');

      verify(() => playerCubit.playSong(existingSong)).called(1);
    });

    test('falls through when nothing matches', () async {
      await handler.handleVoiceSearch('nothing');
      verifyNever(() => playerCubit.playSong(any()));
    });

    test('handles repository errors', () async {
      when(() => repository.watchAllSongs(
              searchQuery: any(named: 'searchQuery'),
              limit: any(named: 'limit')))
          .thenAnswer((_) => Stream.error(StateError('nope')));
      await handler.handleVoiceSearch('boom');
      verifyNever(() => playerCubit.playSong(any()));
    });

    test('times out when the query stream never emits', () async {
      final controller = StreamController<Result<List<SongsTableData>>>();
      addTearDown(controller.close);
      when(() => repository.watchAllSongs(
              searchQuery: any(named: 'searchQuery'),
              limit: any(named: 'limit')))
          .thenAnswer((_) => controller.stream);

      await handler.handleVoiceSearch('hang');
      verifyNever(() => playerCubit.playSong(any()));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('channel plumbing', () {
    test('checkInitialUri plays an initial audio URI', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getInitialAudioUri') return '/music/init.mp3';
        return null;
      });
      when(() => repository.getSongByPath('/music/init.mp3'))
          .thenAnswer((_) async => const Right(existingSong));

      await handler.checkInitialUri();

      verify(() => playerCubit.playSong(existingSong)).called(1);
    });

    test('checkInitialUri survives a platform failure', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'fail');
      });
      await handler.checkInitialUri();
    });

    test('incoming onAudioFileOpened is handled', () async {
      await messenger.handlePlatformMessage(
        PulsrChannels.fileOpener,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onAudioFileOpened', '/music/x.mp3')),
        (_) {},
      );
      verify(() => repository.getSongByPath('/music/x.mp3')).called(1);
    });

    test('incoming onVoiceSearch is handled', () async {
      await messenger.handlePlatformMessage(
        PulsrChannels.fileOpener,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onVoiceSearch', 'hi')),
        (_) {},
      );
      verify(() => repository.watchAllSongs(
          searchQuery: 'hi', limit: 1)).called(1);
    });

    test('incoming call with null arguments is ignored', () async {
      await messenger.handlePlatformMessage(
        PulsrChannels.fileOpener,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onAudioFileOpened', null)),
        (_) {},
      );
      verifyNever(() => repository.getSongByPath(any()));
    });

    test('unknown incoming method is ignored', () async {
      await messenger.handlePlatformMessage(
        PulsrChannels.fileOpener,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('somethingElse', 'x')),
        (_) {},
      );
    });

    test('a malformed incoming argument is caught and logged', () async {
      await messenger.handlePlatformMessage(
        PulsrChannels.fileOpener,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onAudioFileOpened', 42)),
        (_) {},
      );
      // No crash, no repository interaction.
      verifyNever(() => repository.getSongByPath(any()));
    });
  });
}
