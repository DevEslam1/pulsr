// lib/domain/usecases/folder_usecases.dart
import 'dart:io';
import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

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

class FolderUseCases {
  final MusicRepository _repository;

  FolderUseCases(this._repository);

  Stream<List<ExcludedFoldersTableData>> watchExcludedFolders() {
    return _repository.watchExcludedFolders();
  }

  Future<Either<AppFailure, void>> toggleExcludeFolder(String path) {
    return _repository.toggleFolderExclusion(path);
  }

  Future<List<FolderItem>> getFolderHierarchy() async {
    final songsResult = await _repository.getAllSongs();
    final excludedPaths = await _repository.getExcludedFolderPaths();

    final List<SongsTableData> songs = songsResult.fold((l) => [], (r) => r);
    final Map<String, int> folderSongCounts = {};

    for (final song in songs) {
      final file = File(song.path);
      final parentDir = file.parent.path;
      folderSongCounts[parentDir] = (folderSongCounts[parentDir] ?? 0) + 1;
    }

    final List<FolderItem> items = [];
    for (final entry in folderSongCounts.entries) {
      final path = entry.key;
      final name = path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).lastOrNull ?? path;
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
    return items;
  }
}
