// lib/domain/usecases/folder_usecases.dart
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
  final int? representativeSongId;
  final int? representativeAlbumId;
  final String? representativeArtworkUri;
  final String? representativeRemoteUrl;

  const FolderItem({
    required this.path,
    required this.name,
    required this.songCount,
    required this.isExcluded,
    this.representativeSongId,
    this.representativeAlbumId,
    this.representativeArtworkUri,
    this.representativeRemoteUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderItem &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          name == other.name &&
          songCount == other.songCount &&
          isExcluded == other.isExcluded &&
          representativeSongId == other.representativeSongId &&
          representativeAlbumId == other.representativeAlbumId &&
          representativeArtworkUri == other.representativeArtworkUri &&
          representativeRemoteUrl == other.representativeRemoteUrl;

  @override
  int get hashCode =>
      path.hashCode ^
      name.hashCode ^
      songCount.hashCode ^
      isExcluded.hashCode ^
      representativeSongId.hashCode ^
      representativeAlbumId.hashCode ^
      representativeArtworkUri.hashCode ^
      representativeRemoteUrl.hashCode;
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
    Result<List<FolderSongEntry>> entriesResult;
    try {
      entriesResult = await _repository.getLocalSongEntries();
    } catch (_) {
      final pathsResult = await _repository.getLocalSongPaths();
      entriesResult = pathsResult.map((paths) =>
          paths.map((p) => FolderSongEntry(path: p, id: 0)).toList());
    }

    final excludedResult = await _repository.getExcludedFolderPaths();

    if (entriesResult.isLeft()) {
      return Left(
          entriesResult.fold((l) => l, (r) => const DatabaseFailure('Error')));
    }
    if (excludedResult.isLeft()) {
      return Left(
          excludedResult.fold((l) => l, (r) => const DatabaseFailure('Error')));
    }

    final List<FolderSongEntry> entries =
        entriesResult.fold((l) => [], (r) => r);
    final List<String> excludedPaths = excludedResult.fold((l) => [], (r) => r);
    final Map<String, int> folderSongCounts = {};
    final Map<String, FolderSongEntry> folderRepresentative = {};

    for (final entry in entries) {
      final parentDir = p.dirname(entry.path);
      folderSongCounts[parentDir] = (folderSongCounts[parentDir] ?? 0) + 1;
      folderRepresentative.putIfAbsent(parentDir, () => entry);
    }

    final List<FolderItem> items = [];
    for (final entry in folderSongCounts.entries) {
      final path = entry.key;
      // Normalize Windows '\' separators to '/' before splitting. Splitting on
      // Platform.pathSeparator alone left a whole Windows path as one segment,
      // so the generated folder name became the full path.
      final name = path
              .replaceAll('\\', '/')
              .split('/')
              .where((s) => s.isNotEmpty)
              .lastOrNull ??
          path;
      final isExcluded = excludedPaths.contains(path);
      final rep = folderRepresentative[path];
      items.add(
        FolderItem(
          path: path,
          name: name,
          songCount: entry.value,
          isExcluded: isExcluded,
          representativeSongId: rep?.id,
          representativeAlbumId: rep?.albumId,
          representativeArtworkUri: rep?.artworkUri,
          representativeRemoteUrl: rep?.remoteArtworkUrl,
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
