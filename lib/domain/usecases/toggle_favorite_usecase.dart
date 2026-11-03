// lib/domain/usecases/toggle_favorite_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import '../../core/errors/failures.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class ToggleFavoriteUseCase {
  final IMusicRepository _repository;
  final Map<int, _SongLock> _locks = {};
  final Mutex _mapLock = Mutex();

  ToggleFavoriteUseCase(this._repository);

  Future<Result<bool>> call(int songId) async {
    final songLock = await _mapLock.protect(() async {
      final lock = _locks.putIfAbsent(songId, _SongLock.new);
      lock.refCount++;
      return lock;
    });

    await songLock.mutex.acquire();
    try {
      return await _repository.toggleFavorite(songId);
    } finally {
      songLock.mutex.release();
      await _mapLock.protect(() async {
        songLock.refCount--;
        if (songLock.refCount == 0 && _locks[songId] == songLock) {
          _locks.remove(songId);
        }
      });
    }
  }
}

class _SongLock {
  final Mutex mutex = Mutex();
  int refCount = 0;
}
