// test/data/services/download_service_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/repositories/lyrics_repository.dart';
import 'package:pulsr/data/services/download_service.dart';

class MockLyricsRepository extends Mock implements LyricsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadService carriesTags container support', () {
    test('recognizes standard supported tag containers', () {
      expect(DownloadService.carriesTags('m4a'), isTrue);
      expect(DownloadService.carriesTags('mp4'), isTrue);
      expect(DownloadService.carriesTags('flac'), isTrue);
      expect(DownloadService.carriesTags('mp3'), isTrue);
      expect(DownloadService.carriesTags('ogg'), isTrue);
      expect(DownloadService.carriesTags('.m4a'), isTrue);
      expect(DownloadService.carriesTags('FLAC'), isTrue);
    });

    test('correctly rejects containers that do not carry standard ID3/MP4 tags',
        () {
      expect(DownloadService.carriesTags('webm'), isFalse);
      expect(DownloadService.carriesTags('opus'), isFalse);
      expect(DownloadService.carriesTags('wav'), isFalse);
      expect(DownloadService.carriesTags(''), isFalse);
    });
  });

  group('DownloadService sidecar .lrc saving', () {
    late Directory tempDir;
    late DownloadService service;
    late MockLyricsRepository mockLyricsRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pulsr_tagger_test_');
      mockLyricsRepo = MockLyricsRepository();
      service = DownloadService(lyricsRepository: mockLyricsRepo);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves sidecar .lrc file alongside audio file', () async {
      final audioFile = File('${tempDir.path}/track.webm');
      await audioFile.writeAsString('audio binary content');

      const lrcContent = '''
[00:12.34]Line 1
[00:15.67]Line 2
''';

      await service.saveSidecarLrc(audioFile.path, lrcContent);

      final lrcFile = File('${tempDir.path}/track.lrc');
      expect(await lrcFile.exists(), isTrue);
      final readContent = await lrcFile.readAsString();
      expect(readContent, lrcContent);
    });

    test('creates sidecar .lrc when tagging container that does not carry tags',
        () async {
      final audioFile = File('${tempDir.path}/song.webm');
      await audioFile.writeAsString('audio bytes');

      const expectedLrc = '[00:01.00]Hello world';

      when(() => mockLyricsRepo.fetchLyricsLrc(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            durationMs: any(named: 'durationMs'),
            videoId: any(named: 'videoId'),
          )).thenAnswer((_) async => expectedLrc);

      await service.tagCompletedDownload(
        filePath: audioFile.path,
        title: 'Song Title',
        artist: 'Song Artist',
        videoId: 'vid123',
      );

      final lrcFile = File('${tempDir.path}/song.lrc');
      expect(await lrcFile.exists(), isTrue);
      expect(await lrcFile.readAsString(), expectedLrc);
    });
  });
}
