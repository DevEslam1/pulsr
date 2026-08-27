// test/file_intent_handler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}
class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMusicRepository repository;
  late MockPlayerCubit playerCubit;
  late FileIntentHandler fileIntentHandler;

  setUpAll(() {
    registerFallbackValue(const SongsTableData(
      id: 1,
      title: 'fallback',
      artist: 'fallback',
      album: 'fallback',
      durationMs: 180000,
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
    fileIntentHandler = FileIntentHandler(repository, playerCubit);
  });

  group('FileIntentHandler Tests', () {
    test('Plays existing library song when path matches', () async {
      const existingSong = SongsTableData(
        id: 42,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        durationMs: 354000,
        path: '/storage/music/queen.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      when(() => repository.getSongByPath('/storage/music/queen.mp3')).thenAnswer(
        (_) async => const Right(existingSong),
      );

      await fileIntentHandler.handleAudioUri('file:///storage/music/queen.mp3');

      verify(() => playerCubit.playSong(existingSong)).called(1);
    });

    test('Plays external unregistered audio file with synthetic metadata', () async {
      when(() => repository.getSongByPath('/storage/downloads/new_podcast.flac')).thenAnswer(
        (_) async => const Right(null),
      );
      when(() => repository.getSongByUri('/storage/downloads/new_podcast.flac')).thenAnswer(
        (_) async => const Right(null),
      );

      await fileIntentHandler.handleAudioUri('/storage/downloads/new_podcast.flac');

      final captured = verify(() => playerCubit.playSong(captureAny())).captured;
      expect(captured.length, equals(1));
      final capturedSong = captured.first as SongsTableData;
      expect(capturedSong.id, isNegative);
      expect(capturedSong.title, equals('new_podcast'));
      expect(capturedSong.path, equals('/storage/downloads/new_podcast.flac'));
    });
  });
}
