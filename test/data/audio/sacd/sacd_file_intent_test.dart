// test/data/audio/sacd/sacd_file_intent_test.dart
//
// End-to-end `.iso` open path through FileIntentHandler: the fixture image is
// probed, indexed, expanded into cached DSF files, turned into Songs and handed
// to the existing play/queue flow. Also covers the restored 5 s voice-search
// bound.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart' show Result;
import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_cache.dart';
import 'package:pulsr/data/audio/sacd/sacd_iso_library.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

import 'sacd_iso_fixture.dart';

class _MockRepository extends Mock implements IMusicRepository {}

class _MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late _MockRepository repository;
  late _MockPlayerCubit playerCubit;
  late FileIntentHandler handler;

  setUpAll(() {
    registerFallbackValue(const SongsTableData(
      id: 1,
      title: 'fallback',
      artist: 'fallback',
      album: 'fallback',
      durationMs: 0,
      path: '/fallback.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    ));
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulsr_sacd_intent');
    repository = _MockRepository();
    playerCubit = _MockPlayerCubit();
    when(() => playerCubit.playSong(any())).thenAnswer((_) async {});
    when(() => playerCubit.playSong(
          any(),
          queue: any(named: 'queue'),
          queueIndex: any(named: 'queueIndex'),
        )).thenAnswer((_) async {});
    when(() => playerCubit.addAllToQueue(any())).thenAnswer((_) async {});
    FileIntentHandler.sacdIsoLibraryOverride = SacdIsoLibrary(
      cache: SacdDsfCache(
        directory: Directory('${temp.path}${Platform.pathSeparator}cache'),
      ),
    );
    handler = FileIntentHandler(repository, playerCubit);
  });

  tearDown(() async {
    FileIntentHandler.sacdIsoLibraryOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/file_opener'),
      null,
    );
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeIso(String name, List<int> bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('an .iso opens, expands and plays the stereo tracks', () async {
    final iso = await writeIso('disc.iso', SacdIsoFixture().bytes);

    await handler.handleAudioUri(iso.path);

    final captured = verify(() => playerCubit.playSong(
          captureAny(),
          queue: captureAny(named: 'queue'),
          queueIndex: captureAny(named: 'queueIndex'),
        )).captured;
    final first = captured[0] as SongsTableData;
    final queue = captured[1] as List<SongsTableData>;
    expect(queue, hasLength(2));
    expect(queue.first.path, first.path);
    expect(queue.first.path.endsWith('.dsf'), isTrue);
    for (final song in queue) {
      expect(song.source, SongSource.local);
      expect(song.title, contains('disc - Track'));
      expect(File(song.path).existsSync(), isTrue);
    }
    expect(captured[2], 0);
  });

  test('an .iso delivered as a queued intent enqueues every track', () async {
    final iso = await writeIso('queued.iso', SacdIsoFixture().bytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/file_opener'),
      (call) async {
        // The first URI starts playback; the second (same image) is queued.
        if (call.method == 'getInitialAudioUris') {
          return <String>[iso.path, iso.path];
        }
        return null;
      },
    );

    await handler.checkInitialUri();

    final queued = verify(() => playerCubit.addAllToQueue(captureAny()))
        .captured
        .single as List<SongsTableData>;
    expect(queued, hasLength(2));
    expect(queued.every((song) => song.path.endsWith('.dsf')), isTrue);
  });

  test('a non-SACD ISO is still rejected without playing', () async {
    final iso = await writeIso(
      'plain.iso',
      Uint8List(20 * fixtureSectorSize),
    );

    await handler.handleAudioUri(iso.path);

    verifyNever(() => playerCubit.playSong(any()));
    verifyNever(() => playerCubit.addAllToQueue(any()));
  });

  test('voice search is bounded even when the repository never emits',
      () async {
    final controller = StreamController<Result<List<SongsTableData>>>();
    addTearDown(controller.close);
    when(() => repository.watchAllSongs(
          searchQuery: any(named: 'searchQuery'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) => controller.stream);

    final stopwatch = Stopwatch()..start();
    await handler
        .handleVoiceSearch('hang')
        .timeout(FileIntentHandler.voiceSearchTimeout * 2);
    stopwatch.stop();

    verifyNever(() => playerCubit.playSong(any()));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 12)));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
