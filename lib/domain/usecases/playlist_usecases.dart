// lib/domain/usecases/playlist_usecases.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/smart_playlist_engine_interface.dart';
import '../models/smart_playlist_criteria.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class PlaylistUseCases {
  final IMusicRepository _repository;
  final ISmartPlaylistEngine _smartPlaylistEngine;

  PlaylistUseCases(this._repository, this._smartPlaylistEngine);

  Stream<Result<List<PlaylistsTableData>>> watchPlaylists() {
    return _repository.watchPlaylists();
  }

  Stream<Result<List<SongsTableData>>> watchPlaylistSongs(int playlistId) {
    return _repository.watchPlaylistSongs(playlistId);
  }

  Stream<List<SongsTableData>> watchSmartPlaylistSongs(SmartCriteria criteria) {
    return _smartPlaylistEngine.watchCriteria(criteria);
  }

  Future<Result<int>> createPlaylist(String name,
      {bool isSmart = false, String? smartCriteria}) {
    return _repository.createPlaylist(name,
        isSmart: isSmart, smartCriteria: smartCriteria);
  }

  Future<Result<void>> renamePlaylist(int playlistId, String newName) {
    return _repository.renamePlaylist(playlistId, newName);
  }

  Future<Result<void>> updateSmartPlaylist(
      int playlistId, String name, String smartCriteria) {
    return _repository.updateSmartPlaylist(playlistId, name, smartCriteria);
  }

  Future<Result<void>> deletePlaylist(int playlistId) {
    return _repository.deletePlaylist(playlistId);
  }

  Future<Result<void>> addSongToPlaylist(int playlistId, int songId) {
    return _repository.addSongToPlaylist(playlistId, songId);
  }

  Future<Result<void>> addSongsToPlaylist(int playlistId, List<int> songIds) {
    return _repository.addSongsToPlaylist(playlistId, songIds);
  }

  Future<Result<void>> removeSongFromPlaylist(int playlistId, int songId) {
    return _repository.removeSongFromPlaylist(playlistId, songId);
  }

  Future<Result<void>> reorderPlaylistSongs(
      int playlistId, List<int> orderedSongIds) {
    return _repository.reorderPlaylistSongs(playlistId, orderedSongIds);
  }

  Future<void> seedDefaultSmartPlaylists() async {
    final defaults = [
      (
        name: 'Recently Added',
        criteria: const SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.dateAdded,
              operator: SmartOperator.withinDays,
              value: '30',
            ),
          ],
          matchAll: true,
          sortBy: 'dateAdded',
          sortAscending: false,
          limit: 50,
        ),
      ),
      (
        name: 'Most Played',
        criteria: const SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.playCount,
              operator: SmartOperator.greaterThan,
              value: '0',
            ),
          ],
          matchAll: true,
          sortBy: 'playCount',
          sortAscending: false,
          limit: 50,
        ),
      ),
      (
        name: 'Recently Played',
        criteria: const SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.lastPlayed,
              operator: SmartOperator.greaterThan,
              value: '0',
            ),
          ],
          matchAll: true,
          sortBy: 'lastPlayed',
          sortAscending: false,
          limit: 50,
        ),
      ),
      (
        name: 'Long Tracks',
        criteria: const SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.durationMs,
              operator: SmartOperator.greaterThanOrEqual,
              value: '300000',
            ),
          ],
          matchAll: true,
          sortBy: 'durationMs',
          sortAscending: false,
        ),
      ),
      (
        // Forgotten Gems: played before but least-recently — surfaces
        // high-play-count tracks untouched the longest.
        name: 'Forgotten Gems',
        criteria: const SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.playCount,
              operator: SmartOperator.greaterThan,
              value: '1',
            ),
            SmartRule(
              field: SmartRuleField.lastPlayed,
              operator: SmartOperator.greaterThan,
              value: '0',
            ),
          ],
          matchAll: true,
          sortBy: 'lastPlayed',
          sortAscending: true,
          limit: 50,
        ),
      ),
      (
        // Top Rated: prefs-backed star ratings, evaluated in Dart.
        name: 'Top Rated',
        criteria: const SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.rating,
              operator: SmartOperator.greaterThanOrEqual,
              value: '4',
            ),
          ],
          matchAll: true,
          sortBy: 'rating',
          sortAscending: false,
          limit: 50,
        ),
      ),
    ];

    final existingRes = await _repository.getPlaylists();
    final existingNames = existingRes.fold(
      (l) => <String>{},
      (r) => r.map((p) => p.name.toLowerCase()).toSet(),
    );

    for (final item in defaults) {
      if (existingNames.contains(item.name.toLowerCase())) continue;
      await _repository.createPlaylist(
        item.name,
        isSmart: true,
        smartCriteria: item.criteria.toJsonString(),
      );
    }
  }
}
