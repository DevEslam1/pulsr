// lib/data/audio/collaborators/playback_queue_manager.dart
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:pulsr/data/db/app_database.dart';

/// Manages playback queue operations, index sequencing, shuffle indices,
/// and sliding window source materialization.
class PlaybackQueueManager {
  List<SongsTableData> _songs = [];
  int _currentIndex = 0;
  List<int> _shuffleIndices = [];
  bool _isShuffle = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  List<SongsTableData> get songs => List.unmodifiable(_songs);
  int get currentIndex => _currentIndex;
  List<int> get shuffleIndices => List.unmodifiable(_shuffleIndices);
  bool get isShuffle => _isShuffle;
  AudioServiceRepeatMode get repeatMode => _repeatMode;
  bool get isRepeatOne => _repeatMode == AudioServiceRepeatMode.one;
  bool get isRepeatAll => _repeatMode == AudioServiceRepeatMode.all;

  SongsTableData? get currentSong {
    if (_currentIndex >= 0 && _currentIndex < _songs.length) {
      return _songs[_currentIndex];
    }
    return null;
  }

  void setQueue(List<SongsTableData> newQueue, {int initialIndex = 0}) {
    _songs = List.from(newQueue);
    _currentIndex = initialIndex.clamp(0, math.max(0, _songs.length - 1));
    _regenerateShuffleIndices();
  }

  void setCurrentIndex(int index) {
    if (_songs.isEmpty) {
      _currentIndex = 0;
      return;
    }
    _currentIndex = index.clamp(0, _songs.length - 1);
  }

  void setShuffle(bool enabled) {
    _isShuffle = enabled;
    if (enabled && _shuffleIndices.length != _songs.length) {
      _regenerateShuffleIndices();
    }
  }

  void setRepeatMode(AudioServiceRepeatMode mode) {
    _repeatMode = mode;
  }

  void _regenerateShuffleIndices() {
    _shuffleIndices = List.generate(_songs.length, (i) => i);
    if (_isShuffle && _songs.length > 1) {
      final current = _currentIndex;
      _shuffleIndices.remove(current);
      _shuffleIndices.shuffle();
      _shuffleIndices.insert(0, current);
    }
  }

  int? getNextIndex() {
    if (_songs.isEmpty) return null;
    if (isRepeatOne) return _currentIndex;

    if (_isShuffle && _shuffleIndices.isNotEmpty) {
      final pos = _shuffleIndices.indexOf(_currentIndex);
      if (pos >= 0 && pos + 1 < _shuffleIndices.length) {
        return _shuffleIndices[pos + 1];
      }
      if (isRepeatAll && _shuffleIndices.isNotEmpty) {
        return _shuffleIndices.first;
      }
      return null;
    }

    final next = _currentIndex + 1;
    if (next < _songs.length) {
      return next;
    } else if (isRepeatAll && _songs.isNotEmpty) {
      return 0;
    }
    return null;
  }

  int? getPreviousIndex() {
    if (_songs.isEmpty) return null;
    if (isRepeatOne) return _currentIndex;

    if (_isShuffle && _shuffleIndices.isNotEmpty) {
      final pos = _shuffleIndices.indexOf(_currentIndex);
      if (pos > 0) {
        return _shuffleIndices[pos - 1];
      }
      if (isRepeatAll && _shuffleIndices.isNotEmpty) {
        return _shuffleIndices.last;
      }
      return null;
    }

    final prev = _currentIndex - 1;
    if (prev >= 0) {
      return prev;
    } else if (isRepeatAll && _songs.isNotEmpty) {
      return _songs.length - 1;
    }
    return null;
  }

  /// Calculates the sliding window range [start, end] around currentIndex (P0-3).
  /// Typically [currentIndex - 2, currentIndex + 10] clamped to [0, songs.length].
  ({int start, int end}) getSlidingWindow({int windowBefore = 2, int windowAfter = 10}) {
    if (_songs.isEmpty) return (start: 0, end: 0);
    final start = math.max(0, _currentIndex - windowBefore);
    final end = math.min(_songs.length, _currentIndex + windowAfter + 1);
    return (start: start, end: end);
  }

  void addSong(SongsTableData song) {
    _songs.add(song);
    _regenerateShuffleIndices();
  }

  void addSongs(List<SongsTableData> songs) {
    _songs.addAll(songs);
    _regenerateShuffleIndices();
  }

  void insertSong(int index, SongsTableData song) {
    final target = index.clamp(0, _songs.length);
    _songs.insert(target, song);
    if (target <= _currentIndex) {
      _currentIndex++;
    }
    _regenerateShuffleIndices();
  }

  void removeSongAt(int index) {
    if (index < 0 || index >= _songs.length) return;
    _songs.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (_currentIndex >= _songs.length && _songs.isNotEmpty) {
      _currentIndex = _songs.length - 1;
    }
    _regenerateShuffleIndices();
  }

  void moveSong(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _songs.length || newIndex < 0 || newIndex >= _songs.length) return;
    final song = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, song);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    _regenerateShuffleIndices();
  }

  void clear() {
    _songs.clear();
    _currentIndex = 0;
    _shuffleIndices.clear();
  }
}
