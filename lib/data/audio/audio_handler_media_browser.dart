part of 'audio_handler.dart';

extension PulsrAudioMediaBrowser on PulsrAudioHandler {
  MediaItem _fastSongToMediaItem(SongsTableData song) {
    final artUri = song.artworkUri != null
        ? Uri.tryParse(song.artworkUri!)
        : (song.remoteArtworkUrl != null ? Uri.tryParse(song.remoteArtworkUrl!) : null);
    return _songToMediaItem(song, artUri);
  }

  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AudioService.recentRootId:
      case 'root_recent':
        final recentRes = await _repository.getRecentlyPlayed();
        final list = recentRes.fold((l) => <SongsTableData>[], (r) => r);
        return list.map(_fastSongToMediaItem).toList();

      case 'root':
      case 'android_auto_root':
      case '/':
      case '':
        return [
          const MediaItem(
            id: 'songs',
            title: 'Songs',
            playable: false,
          ),
          const MediaItem(
            id: 'albums',
            title: 'Albums',
            playable: false,
          ),
          const MediaItem(
            id: 'artists',
            title: 'Artists',
            playable: false,
          ),
          const MediaItem(
            id: 'playlists',
            title: 'Playlists',
            playable: false,
          ),
          const MediaItem(
            id: 'genres',
            title: 'Genres',
            playable: false,
          ),
          const MediaItem(
            id: 'favorites',
            title: 'Favorites',
            playable: false,
          ),
          const MediaItem(
            id: 'recent',
            title: 'Recently Played',
            playable: false,
          ),
          if (AppConfig.ytmEnabled) ...[
            const MediaItem(
              id: 'ytm_trending',
              title: 'YouTube Music: Trending',
              playable: false,
            ),
            const MediaItem(
              id: 'ytm_favorites',
              title: 'YouTube Music: Liked',
              playable: false,
            ),
          ],
        ];

      case 'songs':
      case 'root_songs':
        final songsRes = await _repository.getAllSongs();
        final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
        return list.map(_fastSongToMediaItem).toList();

      case 'albums':
      case 'root_albums':
        final albumsRes = await _repository.getAlbums();
        final list = albumsRes.fold((l) => <AlbumsTableData>[], (r) => r);
        return await _boundedParallelMap(list, (album) async {
          final artUri = await ArtworkUriResolver.getAlbumArtUri(album.id);
          return MediaItem(
            id: 'album_${album.id}',
            title: album.title,
            artist: album.artist,
            playable: false,
            artUri: artUri,
          );
        });

      case 'artists':
      case 'root_artists':
        final artistsRes = await _repository.getArtists();
        final list = artistsRes.fold((l) => <ArtistsTableData>[], (r) => r);
        return await _boundedParallelMap(list, (artist) async {
          final artUri = await ArtworkUriResolver.getArtistArtUri(artist.id);
          return MediaItem(
            id: 'artist_${artist.id}',
            title: artist.name,
            artist: '${artist.songCount} songs',
            playable: false,
            artUri: artUri,
          );
        });

      case 'playlists':
      case 'root_playlists':
        final playlistsRes = await _repository.getPlaylists();
        final list = playlistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);
        return list
            .map(
              (p) => MediaItem(
                id: 'playlist_${p.id}',
                title: p.name,
                playable: false,
              ),
            )
            .toList();

      case 'genres':
      case 'root_genres':
        final genresRes = await _repository.getGenres();
        final list = genresRes.fold((l) => <GenreItem>[], (r) => r);
        return list
            .map(
              (g) => MediaItem(
                id: 'genre_${g.name}',
                title: g.name,
                artist: '${g.songCount} songs',
                playable: false,
              ),
            )
            .toList();

      case 'favorites':
      case 'root_favorites':
        final favoritesRes = await _repository.getFavorites();
        final list = favoritesRes.fold((l) => <SongsTableData>[], (r) => r);
        return list.map(_fastSongToMediaItem).toList();

      default:
        if (parentMediaId.startsWith('album_')) {
          final albumId = int.tryParse(parentMediaId.substring(6));
          if (albumId == null) return [];
          final songsRes = await _repository.getAlbumSongs(albumId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId.startsWith('artist_')) {
          final artistId = int.tryParse(parentMediaId.substring(7));
          if (artistId == null) return [];
          final songsRes = await _repository.getArtistSongs(artistId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId.startsWith('playlist_')) {
          final playlistId = int.tryParse(parentMediaId.substring(9));
          if (playlistId == null) return [];
          final songsRes = await _repository.getPlaylistSongs(playlistId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId.startsWith('genre_')) {
          final genreName = parentMediaId.substring(6);
          if (genreName.isEmpty) return [];
          final songsRes = await _repository.getGenreSongs(genreName);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId == 'ytm_trending') {
          if (!AppConfig.ytmEnabled) return [];
          try {
            final ytmTracks = await _ytmService.search('trending music');
            return ytmTracks.map((t) {
              final song = t.toSongData();
              return _songToMediaItem(song,
                  t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null);
            }).toList();
          } catch (_) {
            return [];
          }
        }

        if (parentMediaId == 'ytm_favorites') {
          if (!AppConfig.ytmEnabled) return [];
          try {
            final favRes = await _repository.getFavorites();
            final allFavs = favRes.fold((l) => <SongsTableData>[], (r) => r);
            final ytmFavs = allFavs
                .where((s) =>
                    s.source == SongSource.youtube ||
                    (s.remoteId != null && s.remoteId!.isNotEmpty))
                .toList();
            return ytmFavs.map(_fastSongToMediaItem).toList();
          } catch (_) {
            return [];
          }
        }

        return [];
    }
  }

  Future<MediaItem?> getMediaItem(String mediaId) async {
    final id = int.tryParse(mediaId);
    if (id == null) return null;
    final songRes = await _repository.getSongById(id);
    final match = songRes.fold((l) => null, (r) => r);
    if (match == null) return null;
    final artUri = await ArtworkUriResolver.resolveArtworkUri(match);
    return _songToMediaItem(match, artUri);
  }

  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    final queueIndex = _songs.indexWhere(
        (s) => s.id.toString() == mediaId || s.remoteId == mediaId);
    if (queueIndex != -1) {
      await loadQueue(_songs, initialIndex: queueIndex);
      return;
    }

    final songId = int.tryParse(mediaId);
    if (songId != null) {
      final songsRes = await _repository.getAllSongs();
      final loaded = songsRes.fold((l) => false, (songs) {
        final index = songs.indexWhere((s) => s.id == songId);
        if (index != -1) {
          loadQueue(songs, initialIndex: index);
          return true;
        }
        return false;
      });
      if (loaded) return;
    }

    if (extras != null &&
        (extras['remoteId'] != null ||
            extras['source'] == SongSource.youtube ||
            mediaId.length == 11)) {
      final remoteId = (extras['remoteId'] as String?) ?? mediaId;
      final uniqueNegativeId = -(remoteId.hashCode.abs() % 1000000000 + 1);
      final onlineSong = SongsTableData(
        id: songId ?? uniqueNegativeId,
        title: extras['title'] as String? ?? 'Unknown',
        artist: extras['artist'] as String? ?? 'Unknown Artist',
        album: extras['album'] as String? ?? '',
        durationMs: (extras['durationMs'] as int?) ?? 0,
        path: extras['path'] as String? ?? '',
        source: extras['source'] as String? ?? SongSource.youtube,
        remoteId: remoteId,
        remoteArtworkUrl: extras['remoteArtworkUrl'] as String?,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      await loadQueue([onlineSong], initialIndex: 0);
      return;
    }

    if (mediaId.startsWith('album_')) {
      final albumId = int.tryParse(mediaId.substring(6));
      if (albumId != null) {
        final songsRes = await _repository.getAlbumSongs(albumId);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId.startsWith('artist_')) {
      final artistId = int.tryParse(mediaId.substring(7));
      if (artistId != null) {
        final songsRes = await _repository.getArtistSongs(artistId);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId.startsWith('playlist_')) {
      final playlistId = int.tryParse(mediaId.substring(9));
      if (playlistId != null) {
        final songsRes = await _repository.getPlaylistSongs(playlistId);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId.startsWith('genre_')) {
      final genreName = mediaId.substring(6);
      if (genreName.isNotEmpty) {
        final songsRes = await _repository.getGenreSongs(genreName);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId == 'songs' || mediaId == 'root_songs') {
      final songsRes = await _repository.getAllSongs();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }

    if (mediaId == 'favorites' || mediaId == 'root_favorites') {
      final songsRes = await _repository.getFavorites();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }

    if (mediaId == 'recent' ||
        mediaId == 'root_recent' ||
        mediaId == AudioService.recentRootId) {
      // External controllers (media resumption chip, Assistant, Wear/Auto
      // reconnect) address the "recent" root to auto-play recently played
      // music. Honoring it while a user queue is actively playing silently
      // replaced the running queue — and the player-screen queue view — with
      // the 20 most recently played tracks. Only honor it when nothing is
      // playing.
      if (_songs.isNotEmpty && _activePlayer.playing) return;
      final songsRes = await _repository.getRecentlyPlayed();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }
  }

  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return [];
    // Use the indexed FTS search instead of materializing and linear-scanning
    // the entire library on every Android Auto query.
    final songsRes = await _repository
        .watchAllSongs(searchQuery: query.trim(), limit: 50)
        .first;
    final matches = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    final results = <MediaItem>[
      for (final song in matches) _fastSongToMediaItem(song),
    ];

    if (results.isEmpty && AppConfig.ytmEnabled) {
      try {
        final ytmTracks = await _ytmService.search(query.trim(), limit: 10);
        for (final t in ytmTracks) {
          final song = t.toSongData();
          final artUri =
              t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null;
          results.add(_songToMediaItem(song, artUri));
        }
      } catch (_) {}
    }

    return results;
  }

  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return;
    final cleanQ = query.trim();
    // Indexed FTS search (title/artist/album) instead of a full-library scan.
    final songsRes = await _repository
        .watchAllSongs(searchQuery: cleanQ, limit: 50)
        .first;
    final matches = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    if (matches.isNotEmpty) {
      await loadQueue(matches);
      return;
    }

    // 5. Online YouTube Music Search fallback if enabled
    if (AppConfig.ytmEnabled) {
      try {
        final ytmTracks = await _ytmService.search(cleanQ, limit: 15);
        if (ytmTracks.isNotEmpty) {
          final songs = ytmTracks.map((t) => t.toSongData()).toList();
          await loadQueue(songs);
          return;
        }
      } catch (_) {}
    }
  }

}
