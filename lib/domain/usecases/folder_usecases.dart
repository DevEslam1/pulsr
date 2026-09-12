// lib/domain/usecases/folder_usecases.dart
import 'dart:io';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

class FolderItem {
  final String path;
  final String name;
  final int songCount;
  final bool isExcluded;

  const FolderItem({
    required this.path,
    required this.name,
    required this.songCount,
    required this.isExcluded,
  });
}

@singleton
class FolderUseCases {
  final IMusicRepository _repository;

  FolderUseCases(this._repository);

  Stream<Result<List<ExcludedFoldersTableData>>> watchExcludedFolders() {
    return _repository.watchExcludedFolders();
  }

  Future<Result<List<String>>> getExcludedFolders() {
    return _repository.getExcludedFolderPaths();
  }

  Future<Result<void>> toggleExcludeFolder(String path) {
    return _repository.toggleFolderExclusion(path);
  }

  Future<Result<List<FolderItem>>> getFolderHierarchy() async {
    final pathsResult = await _repository.getLocalSongPaths();
    final excludedResult = await _repository.getExcludedFolderPaths();

    if (pathsResult.isLeft()) {
      return Left(
          pathsResult.fold((l) => l, (r) => const DatabaseFailure('Error')));
    }
    if (excludedResult.isLeft()) {
      return Left(
          excludedResult.fold((l) => l, (r) => const DatabaseFailure('Error')));
    }

    final List<String> paths = pathsResult.fold((l) => [], (r) => r);
    final List<String> excludedPaths = excludedResult.fold((l) => [], (r) => r);
    final Map<String, int> folderSongCounts = {};

    for (final path in paths) {
      final parentDir = p.dirname(path);
      folderSongCounts[parentDir] = (folderSongCounts[parentDir] ?? 0) + 1;
    }

    final List<FolderItem> items = [];
    for (final entry in folderSongCounts.entries) {
      final path = entry.key;
      final name = path
              .split(Platform.pathSeparator)
              .where((s) => s.isNotEmpty)
              .lastOrNull ??
          path;
      final isExcluded = excludedPaths.contains(path);
      items.add(
        FolderItem(
          path: path,
          name: name,
          songCount: entry.value,
          isExcluded: isExcluded,
        ),
      );
    }

    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Right(items);
  }

  Stream<Result<List<SongsTableData>>> watchFolderSongs(String folderPath) {
    return _repository.watchSongsInFolder(folderPath);
  }
}
