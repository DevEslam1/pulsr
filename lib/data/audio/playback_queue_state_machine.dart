// lib/data/audio/playback_queue_state_machine.dart
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart' show LoopMode;
import '../db/app_database.dart';

/// Pure, testable state machine for playback queue navigation and state.
///
/// Encapsulates:
/// - Queue item storage and current index tracking
/// - Bounded shuffle history (up to 50 items) with recent-window repetition avoidance
/// - Next/previous track index resolution across linear, shuffle, loop-one, and loop-all modes
/// - Queue neighbor discovery for skip control determination
/// - Queue mutation and persistence-dirty tracking
///
/// Deliberately free of platform dependencies so queue logic is unit-testable
/// without constructing [PulsrAudioHandler].
class PlaybackQueueStateMachine {
  final List<SongsTableData> _songs = [];
  int _currentIndex = 0;
  final List<int> _shuffleHistory = [];
  bool _queueDirty = false;
  int _savedQueueIndex = -1;
  final math.Random _random;

  PlaybackQueueStateMachine({
    List<SongsTableData>? initialSongs,
    int initialIndex = 0,
    math.Random? random,
  }) : _random = random ?? math.Random() {
    if (initialSongs != null && initialSongs.isNotEmpty) {
      setQueue(initialSongs, initialIndex: initialIndex);
    }
  }

  /// The current songs in the queue.
  List<SongsTableData> get songs => _songs;

  /// The current active queue index.
  int get currentIndex => _currentIndex;

  /// The current active song, or null if the queue is empty or index is out of bounds.
  SongsTableData? get currentSong =>
      (_songs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _songs.length)
          ? _songs[_currentIndex]
          : null;

  /// The number of songs in the queue.
  int get length => _songs.length;

  /// Whether the queue is empty.
  bool get isEmpty => _songs.isEmpty;

  /// Whether the queue has at least one song.
  bool get isNotEmpty => _songs.isNotEmpty;

  /// Direct access to the shuffle history for navigation.
  List<int> get shuffleHistory => _shuffleHistory;

  /// Whether the queue has been modified since last save.
  bool get isQueueDirty => _queueDirty;

  /// The queue index saved during the last snapshot.
  int get savedQueueIndex => _savedQueueIndex;

  void markQueueDirty() {
    _queueDirty = true;
  }

  void markQueueClean(int savedIndex) {
    _queueDirty = false;
    _savedQueueIndex = savedIndex;
  }

  void setSavedQueueIndex(int index) {
    _savedQueueIndex = index;
  }

  /// Sets or replaces the entire queue.
  void setQueue(List<SongsTableData> newSongs, {int initialIndex = 0}) {
    _songs.clear();
    _songs.addAll(newSongs);
    _currentIndex =
        _songs.isEmpty ? 0 : initialIndex.clamp(0, _songs.length - 1);
    _shuffleHistory.clear();
    _queueDirty = true;
  }

  /// Updates current track index within bounds.
  void setCurrentIndex(int index) {
    if (_songs.isEmpty) {
      _currentIndex = 0;
      return;
    }
    _currentIndex = index.clamp(0, _songs.length - 1);
  }

  /// Appends a song to the queue.
  void addSong(SongsTableData song) {
    _songs.add(song);
    _queueDirty = true;
  }

  /// Inserts a song at [index].
  void insertSong(int index, SongsTableData song) {
    final target = _songs.isEmpty ? 0 : index.clamp(0, _songs.length);
    _songs.insert(target, song);
    if (target <= _currentIndex && _songs.length > 1) {
      _currentIndex++;
    }
    _queueDirty = true;
  }

  /// Removes the song at [index] and adjusts [_currentIndex] accordingly.
  SongsTableData? removeSongAt(int index) {
    if (index < 0 || index >= _songs.length) return null;
    final removed = _songs.removeAt(index);
    _shuffleHistory.removeWhere((i) => i == index);
    for (int i = 0; i < _shuffleHistory.length; i++) {
      if (_shuffleHistory[i] > index) {
        _shuffleHistory[i]--;
      }
    }
    if (_songs.isEmpty) {
      _currentIndex = 0;
    } else if (index < _currentIndex) {
      _currentIndex = (_currentIndex - 1).clamp(0, _songs.length - 1);
    } else if (_currentIndex >= _songs.length) {
      _currentIndex = _songs.length - 1;
    }
    _queueDirty = true;
    return removed;
  }

  /// Reorders a song from [oldIndex] to [newIndex].
  bool reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _songs.length ||
        newIndex < 0 ||
        newIndex >= _songs.length) {
      return false;
    }
    final song = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, song);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    _queueDirty = true;
    return true;
  }

  /// Updates song data in-place at [index] (e.g. metadata / favorite updates).
  void updateSongAt(int index, SongsTableData song) {
    if (index >= 0 && index < _songs.length) {
      _songs[index] = song;
    }
  }

  /// Clears the queue and resets state.
  void clear() {
    _songs.clear();
    _currentIndex = 0;
    _shuffleHistory.clear();
    _queueDirty = true;
    _savedQueueIndex = -1;
  }

  /// Clears the shuffle history.
  void clearShuffleHistory() {
    _shuffleHistory.clear();
  }

  /// Computes the next track index given playback configuration.
  int? getNextIndex({
    int offset = 1,
    bool peek = false,
    bool shuffleModeEnabled = false,
    LoopMode loopMode = LoopMode.off,
  }) {
    if (_songs.isEmpty) return null;
    if (loopMode == LoopMode.one) {
      return _currentIndex;
    }
    if (shuffleModeEnabled && _songs.length > 1) {
      if (offset == 1 && !peek) {
        _shuffleHistory.add(_currentIndex);
        if (_shuffleHistory.length > 50) {
          _shuffleHistory.removeAt(0);
        }
      }
      if (_songs.length == 2) {
        // In a 2-song queue with shuffle enabled, alternate to the other song
        return _currentIndex == 0 ? 1 : 0;
      }
      if (_songs.length == 1) {
        return 0;
      }
      final recentWindow = math.min(_songs.length - 1, 10);
      final recent = _shuffleHistory.length >= recentWindow
          ? _shuffleHistory.sublist(_shuffleHistory.length - recentWindow)
          : _shuffleHistory;

      int next = _random.nextInt(_songs.length);
      int attempts = 0;
      final maxAttempts = _songs.length * 2;
      while ((next == _currentIndex || recent.contains(next)) &&
          attempts < maxAttempts &&
          _songs.length > 1) {
        next = _random.nextInt(_songs.length);
        attempts++;
      }
      if (next == _currentIndex && _songs.length > 1) {
        final candidates = [
          for (int i = 0; i < _songs.length; i++)
            if (i != _currentIndex) i
        ];
        next = candidates[_random.nextInt(candidates.length)];
      }
      return next;
    }
    if (_currentIndex + offset < _songs.length) {
      return _currentIndex + offset;
    } else if (loopMode == LoopMode.all && _songs.isNotEmpty) {
      return (_currentIndex + offset) % _songs.length;
    }
    return null;
  }

  /// Computes the previous track index given playback configuration.
  int? getPreviousIndex({
    bool forcePrevious = false,
    Duration position = Duration.zero,
    bool shuffleModeEnabled = false,
    LoopMode loopMode = LoopMode.off,
  }) {
    if (_songs.isEmpty) return null;
    if (!forcePrevious && position.inSeconds > 3) {
      return _currentIndex;
    }
    if (shuffleModeEnabled && _shuffleHistory.isNotEmpty) {
      // Drain any stale entries left over from a previous/shorter queue rather
      // than returning an out-of-range index.
      while (_shuffleHistory.isNotEmpty) {
        final previous = _shuffleHistory.removeLast();
        if (previous >= 0 && previous < _songs.length) return previous;
      }
    }
    if (_currentIndex - 1 >= 0) {
      return _currentIndex - 1;
    } else if (loopMode == LoopMode.all) {
      return _songs.length - 1;
    }
    return null;
  }

  /// Whether the queue holds another entry to skip to in [forward] direction.
  ///
  /// Non-destructive check for skip controls.
  bool hasQueueNeighbour({
    required bool forward,
    bool shuffleModeEnabled = false,
    LoopMode loopMode = LoopMode.off,
    bool gaplessMode = false,
    bool gaplessLoaded = false,
    bool playerHasNext = false,
    bool playerHasPrevious = false,
  }) {
    if (_songs.length <= 1) return false;
    if (shuffleModeEnabled) return true;
    if (loopMode == LoopMode.all) return true;
    if (gaplessMode && gaplessLoaded) {
      return forward ? playerHasNext : playerHasPrevious;
    }
    return forward ? _currentIndex + 1 < _songs.length : _currentIndex > 0;
  }
}
