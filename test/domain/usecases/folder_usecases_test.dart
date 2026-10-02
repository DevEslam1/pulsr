// test/domain/usecases/folder_usecases_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  late MockMusicRepository repo;
  late FolderUseCases useCases;

  setUp(() {
    repo = MockMusicRepository();
    useCases = FolderUseCases(repo);
  });

  group('FolderUseCases.getFolderHierarchy separator normalization', () {
    test('Windows backslash paths yield the leaf folder name', () async {
      when(() => repo.getLocalSongPaths()).thenAnswer(
        (_) async => const Right([
          r'C:\Music\Adele\25\song1.flac',
          r'C:\Music\Adele\25\song2.flac',
          r'C:\Music\Radiohead\In Rainbows\track.mp3',
        ]),
      );
      when(() => repo.getExcludedFolderPaths())
          .thenAnswer((_) async => const Right([]));

      final result = await useCases.getFolderHierarchy();
      final items = result.fold((l) => throw l, (r) => r);

      final adele = items.firstWhere((i) => i.path == r'C:\Music\Adele\25');
      expect(adele.name, '25');
      expect(adele.songCount, 2);

      final radiohead =
          items.firstWhere((i) => i.path == r'C:\Music\Radiohead\In Rainbows');
      expect(radiohead.name, 'In Rainbows');
    });

    test('forward-slash paths still yield the leaf folder name', () async {
      when(() => repo.getLocalSongPaths()).thenAnswer(
        (_) async => const Right([
          'C:/Music/Adele/25/song1.flac',
          'C:/Music/Adele/25/song2.flac',
        ]),
      );
      when(() => repo.getExcludedFolderPaths())
          .thenAnswer((_) async => const Right([]));

      final result = await useCases.getFolderHierarchy();
      final items = result.fold((l) => throw l, (r) => r);

      expect(items.length, 1);
      expect(items.first.name, '25');
      expect(items.first.songCount, 2);
    });

    test('marks excluded folders', () async {
      when(() => repo.getLocalSongPaths()).thenAnswer(
        (_) async => const Right([
          r'C:\Music\Junk\a.mp3',
        ]),
      );
      when(() => repo.getExcludedFolderPaths()).thenAnswer(
        (_) async => const Right([r'C:\Music\Junk']),
      );

      final result = await useCases.getFolderHierarchy();
      final items = result.fold((l) => throw l, (r) => r);
      expect(items.single.name, 'Junk');
      expect(items.single.isExcluded, isTrue);
    });
  });
}
