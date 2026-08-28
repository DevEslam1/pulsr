// lib/domain/repositories/smart_playlist_engine_interface.dart
import '../../data/db/app_database.dart';
import '../models/smart_playlist_criteria.dart';

/// Domain interface for evaluating dynamic smart playlists and observing reactive criteria changes.
abstract class ISmartPlaylistEngine {
  /// Evaluates the given [criteria] against the database and returns matching songs.
  Future<List<SongsTableData>> evaluateCriteria(SmartCriteria criteria);

  /// Reactively observes database mutations and emits updated matching songs debounced by 500ms.
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria);

  /// Creates an immutable snapshot list of songs for safe playback queue loading.
  Future<List<SongsTableData>> createPlaybackSnapshot(SmartCriteria criteria);
}
