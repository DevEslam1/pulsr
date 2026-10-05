part of 'audio_handler.dart';

/// Localized labels for the Android Auto browse tree. Android Auto renders the
/// strings the service returns verbatim (the car has no access to the app's
/// `AppLocalizations`), so the handler mirrors them here for the languages the
/// app ships (English, Spanish, Arabic).
class _AutoBrowseStrings {
  static const Map<String, Map<String, String>> _values = {
    'en': {
      'root.songs': 'Songs',
      'root.albums': 'Albums',
      'root.artists': 'Artists',
      'root.playlists': 'Playlists',
      'root.genres': 'Genres',
      'root.favorites': 'Favorites',
      'root.downloaded': 'Downloaded',
      'root.mood': 'Browse by Mood',
      'root.recent': 'Recently Played',
      'root.settings': 'Sound Settings',
      'root.ytmTrending': 'YouTube Music: Trending',
      'root.ytmLiked': 'YouTube Music: Liked',
      'mood.chill': 'Chill & Relax',
      'mood.chill.sub': 'Acoustic, Ambient, Lo-Fi',
      'mood.workout': 'Workout & Energy',
      'mood.workout.sub': 'Electronic, Rock, High Tempo',
      'mood.focus': 'Focus & Study',
      'mood.focus.sub': 'Instrumental, Classical, Jazz',
      'mood.party': 'Party & Upbeat',
      'mood.party.sub': 'Pop, Dance, Upbeat Rhythms',
      'settings.bass': 'Bass Boost',
      'settings.virtualizer': 'Virtualizer',
      'settings.sleep': 'Sleep Timer (30m)',
      'state.enabled': 'Enabled',
      'state.disabled': 'Disabled',
      'state.active': 'Active',
      'state.off': 'Off',
    },
    'es': {
      'root.songs': 'Canciones',
      'root.albums': 'Álbumes',
      'root.artists': 'Artistas',
      'root.playlists': 'Listas de reproducción',
      'root.genres': 'Géneros',
      'root.favorites': 'Favoritos',
      'root.downloaded': 'Descargado',
      'root.mood': 'Explorar por ánimo',
      'root.recent': 'Reproducido recientemente',
      'root.settings': 'Ajustes de sonido',
      'root.ytmTrending': 'YouTube Music: Tendencias',
      'root.ytmLiked': 'YouTube Music: Me gusta',
      'mood.chill': 'Relax y calma',
      'mood.chill.sub': 'Acústico, ambiental, lo-fi',
      'mood.workout': 'Entrenamiento y energía',
      'mood.workout.sub': 'Electrónico, rock, tempo alto',
      'mood.focus': 'Concentración y estudio',
      'mood.focus.sub': 'Instrumental, clásica, jazz',
      'mood.party': 'Fiesta y animado',
      'mood.party.sub': 'Pop, dance, ritmos animados',
      'settings.bass': 'Refuerzo de graves',
      'settings.virtualizer': 'Virtualizador',
      'settings.sleep': 'Temporizador (30 min)',
      'state.enabled': 'Activado',
      'state.disabled': 'Desactivado',
      'state.active': 'Activo',
      'state.off': 'Inactivo',
    },
    'ar': {
      'root.songs': 'الأغاني',
      'root.albums': 'الألبومات',
      'root.artists': 'الفنانون',
      'root.playlists': 'قوائم التشغيل',
      'root.genres': 'الأنواع',
      'root.favorites': 'المفضلة',
      'root.downloaded': 'المحمّلة',
      'root.mood': 'تصفح حسب المزاج',
      'root.recent': 'تم تشغيله مؤخراً',
      'root.settings': 'إعدادات الصوت',
      'root.ytmTrending': 'يوتيوب ميوزيك: الرائج',
      'root.ytmLiked': 'يوتيوب ميوزيك: أعجبني',
      'mood.chill': 'هدوء واسترخاء',
      'mood.chill.sub': 'صوتي، هادئ، لو-فاي',
      'mood.workout': 'تمرين وطاقة',
      'mood.workout.sub': 'إلكتروني، روك، إيقاع سريع',
      'mood.focus': 'تركيز ودراسة',
      'mood.focus.sub': 'موسيقى، كلاسيكية، جاز',
      'mood.party': 'حفلة ونشاط',
      'mood.party.sub': 'بوب، رقص، إيقاعات مفعمة',
      'settings.bass': 'تعزيز الجهير',
      'settings.virtualizer': 'المجسّم الصوتي',
      'settings.sleep': 'مؤقّت النوم (30 د)',
      'state.enabled': 'مفعّل',
      'state.disabled': 'معطّل',
      'state.active': 'نشط',
      'state.off': 'متوقف',
    },
  };

  static String t(String lang, String key) =>
      _values[lang]?[key] ?? _values['en']![key]!;
}

mixin PulsrAudioMediaBrowser on BaseAudioHandler {
  // Android Auto honours content-style hints to pick list vs grid templates.
  // The root declares support; each browsable node advertises grid and each
  // playable song advertises a list.
  static const Map<String, dynamic> _kBrowseGridExtras = {
    AndroidContentStyle.browsableHintKey: AndroidContentStyle.gridItemHintValue,
  };
  static const Map<String, dynamic> _kBrowseListExtras = {
    AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
  };
  static const Map<String, dynamic> _kPlayListExtras = {
    AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
  };

  String _t(String key) => _AutoBrowseStrings.t(
        PulsrAudioHandler._browseLanguage,
        key,
      );

  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  MediaItem _container(
    String id,
    String title, {
    String? subtitle,
    Uri? artUri,
    Map<String, dynamic>? extras,
    Map<String, dynamic> style = _kBrowseGridExtras,
  }) {
    return MediaItem(
      id: id,
      title: title,
      artist: subtitle,
      displaySubtitle: subtitle,
      artUri: artUri,
      playable: false,
      extras: <String, dynamic>{...style, ...?extras},
    );
  }

  MediaItem _fastSongToMediaItem(SongsTableData song) {
    Uri? artUri = ArtworkUriResolver.getCachedArtworkUri(song.id);
    if (artUri == null && song.albumId != null) {
      artUri = ArtworkUriResolver.getCachedAlbumArtUri(song.albumId!);
    }
    if (artUri == null && song.artworkUri != null) {
      final parsed = Uri.tryParse(song.artworkUri!);
      if (parsed != null && parsed.hasScheme) artUri = parsed;
    }
    if (artUri == null && song.remoteArtworkUrl != null) {
      final parsed = Uri.tryParse(song.remoteArtworkUrl!);
      if (parsed != null && parsed.hasScheme) artUri = parsed;
    }
    final item = PulsrAudioHandler._songToMediaItem(song, artUri);
    // Content-style extras are browse-only; keep queue/metadata untouched.
    return item.copyWith(
      extras: <String, dynamic>{...?item.extras, ..._kPlayListExtras},
    );
  }

  MediaItem? _staticContainer(String id) {
    switch (id) {
      case 'songs':
      case 'root_songs':
        return _container('songs', _t('root.songs'));
      case 'albums':
      case 'root_albums':
        return _container('albums', _t('root.albums'));
      case 'artists':
      case 'root_artists':
        return _container('artists', _t('root.artists'));
      case 'playlists':
      case 'root_playlists':
        return _container('playlists', _t('root.playlists'));
      case 'genres':
      case 'root_genres':
        return _container('genres', _t('root.genres'));
      case 'favorites':
      case 'root_favorites':
        return _container('favorites', _t('root.favorites'));
      case 'downloaded':
      case 'root_downloaded':
        return _container('downloaded', _t('root.downloaded'));
      case 'browse_mood':
      case 'root_browse_mood':
        return _container('browse_mood', _t('root.mood'));
      case 'root_recent':
      case AudioService.recentRootId:
        return _container('recent', _t('root.recent'));
      case 'sound_settings':
      case 'root_sound_settings':
        return _container('sound_settings', _t('root.settings'),
            style: _kBrowseListExtras);
      case 'ytm_trending':
        return _container('ytm_trending', _t('root.ytmTrending'));
      case 'ytm_favorites':
        return _container('ytm_favorites', _t('root.ytmLiked'));
      default:
        if (id.startsWith('mood_')) {
          final mood = id.substring(5);
          return _container(
            id,
            _AutoBrowseStrings.t(PulsrAudioHandler._browseLanguage, 'mood.$mood'),
            subtitle: _AutoBrowseStrings.t(
                PulsrAudioHandler._browseLanguage, 'mood.$mood.sub'),
          );
        }
        return null;
    }
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AudioService.recentRootId:
      case 'root_recent':
        final recentRes = await _repository.getRecentlyPlayed();
        final list = recentRes.fold((l) => <SongsTableData>[], (r) => r);
        _warmArtworkAsync(list);
        return list.map(_fastSongToMediaItem).toList();

      case 'root':
      case 'android_auto_root':
      case '/':
      case '':
        return [
          _container('songs', _t('root.songs')),
          _container('albums', _t('root.albums')),
          _container('artists', _t('root.artists')),
          _container('playlists', _t('root.playlists')),
          _container('genres', _t('root.genres')),
          _container('favorites', _t('root.favorites')),
          _container('downloaded', _t('root.downloaded')),
          _container('browse_mood', _t('root.mood')),
          _container('recent', _t('root.recent')),
          _container('sound_settings', _t('root.settings'),
              style: _kBrowseListExtras),
          if (AppConfig.ytmEnabled) ...[
            _container('ytm_trending', _t('root.ytmTrending')),
            _container('ytm_favorites', _t('root.ytmLiked')),
          ],
        ];

      case 'songs':
      case 'root_songs':
        final songsRes = await _repository.getAllSongs();
        final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
        _warmArtworkAsync(list);
        return list.map(_fastSongToMediaItem).toList();

      case 'albums':
      case 'root_albums':
        final albumsRes = await _repository.getAlbums();
        final list = albumsRes.fold((l) => <AlbumsTableData>[], (r) => r);
        return await _boundedParallelMap(list, (album) async {
          final artUri = await ArtworkUriResolver.getAlbumArtUri(album.id);
          return _container(
            'album_${album.id}',
            album.title,
            subtitle: album.artist,
            artUri: artUri,
          );
        });

      case 'artists':
      case 'root_artists':
        final artistsRes = await _repository.getArtists();
        final list = artistsRes.fold((l) => <ArtistsTableData>[], (r) => r);
        return await _boundedParallelMap(list, (artist) async {
          final artUri = await ArtworkUriResolver.getArtistArtUri(artist.id);
          return _container(
            'artist_${artist.id}',
            artist.name,
            subtitle: '${artist.songCount} songs',
            artUri: artUri,
          );
        });

      case 'playlists':
      case 'root_playlists':
        final playlistsRes = await _repository.getPlaylists();
        final list = playlistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);
        return list
            .map(
              (p) => _container(
                'playlist_${p.id}',
                p.name,
                style: _kBrowseListExtras,
              ),
            )
            .toList();

      case 'genres':
      case 'root_genres':
        final genresRes = await _repository.getGenres();
        final list = genresRes.fold((l) => <GenreItem>[], (r) => r);
        return list
            .map(
              (g) => _container(
                'genre_${g.name}',
                g.name,
                subtitle: '${g.songCount} songs',
                style: _kBrowseListExtras,
              ),
            )
            .toList();

      case 'favorites':
      case 'root_favorites':
        final favoritesRes = await _repository.getFavorites();
        final list = favoritesRes.fold((l) => <SongsTableData>[], (r) => r);
        _warmArtworkAsync(list);
        return list.map(_fastSongToMediaItem).toList();

      case 'downloaded':
      case 'root_downloaded':
        final allSongsRes = await _repository.getAllSongs();
        final allList = allSongsRes.fold((l) => <SongsTableData>[], (r) => r);
        final downloaded = allList
            .where((s) => s.isDownloaded || s.source == SongSource.local)
            .toList();
        _warmArtworkAsync(downloaded);
        return downloaded.map(_fastSongToMediaItem).toList();

      case 'browse_mood':
      case 'root_browse_mood':
        return [
          _container('mood_chill', _t('mood.chill'),
              subtitle: _t('mood.chill.sub')),
          _container('mood_workout', _t('mood.workout'),
              subtitle: _t('mood.workout.sub')),
          _container('mood_focus', _t('mood.focus'),
              subtitle: _t('mood.focus.sub')),
          _container('mood_party', _t('mood.party'),
              subtitle: _t('mood.party.sub')),
        ];

      case 'sound_settings':
      case 'root_sound_settings':
        return [
          _container(
            'action_bass_boost',
            _t('settings.bass'),
            subtitle: _equalizerManager.currentPreset.bassBoost > 0.05
                ? _t('state.enabled')
                : _t('state.disabled'),
            style: _kBrowseListExtras,
          ),
          _container(
            'action_virtualizer',
            _t('settings.virtualizer'),
            subtitle: _equalizerManager.isVirtualizerEnabled
                ? _t('state.enabled')
                : _t('state.disabled'),
            style: _kBrowseListExtras,
          ),
          _container(
            'action_sleep_timer',
            _t('settings.sleep'),
            subtitle:
                _sleepTimerManager.isActive ? _t('state.active') : _t('state.off'),
            style: _kBrowseListExtras,
          ),
        ];

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
            final ytmTracks = await _ytmService.trending(limit: 30);
            return ytmTracks.map((t) {
              final song = t.toSongData();
              return PulsrAudioHandler._songToMediaItem(song,
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

        if (parentMediaId.startsWith('mood_')) {
          final allSongsRes = await _repository.getAllSongs();
          final allSongs =
              allSongsRes.fold((l) => <SongsTableData>[], (r) => r);
          final filtered = _filterByMood(allSongs, parentMediaId.substring(5));
          _warmArtworkAsync(filtered);
          return filtered.map(_fastSongToMediaItem).toList();
        }

        return [];
    }
  }

  static List<String> _moodKeywords(String mood) => switch (mood) {
        'chill' => [
            'chill',
            'relax',
            'acoustic',
            'ambient',
            'lofi',
            'calm',
            'peaceful'
          ],
        'workout' => [
            'workout',
            'energy',
            'power',
            'gym',
            'fast',
            'rock',
            'electronic',
            'dance'
          ],
        'focus' => [
            'focus',
            'study',
            'instrumental',
            'piano',
            'classical',
            'jazz',
            'ambient'
          ],
        'party' => [
            'party',
            'dance',
            'club',
            'pop',
            'disco',
            'house',
            'hip hop',
            'upbeat'
          ],
        _ => [mood],
      };

  List<SongsTableData> _filterByMood(List<SongsTableData> songs, String mood) {
    final keywords = _moodKeywords(mood.toLowerCase());
    return songs.where((s) {
      final text =
          '${s.title} ${s.artist} ${s.album} ${s.genre ?? ''}'.toLowerCase();
      return keywords.any(text.contains);
    }).toList();
  }

  Future<void> _loadSongsIfAny(List<SongsTableData> songs) async {
    if (songs.isNotEmpty) await loadQueue(songs);
  }

  List<SongsTableData> _unwrapSongs(dynamic res) =>
      res.fold((l) => <SongsTableData>[], (r) => r) as List<SongsTableData>;

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final id = int.tryParse(mediaId);
    if (id != null) {
      final songRes = await _repository.getSongById(id);
      final match = songRes.fold((l) => null, (r) => r);
      if (match == null) return null;
      final artUri = await ArtworkUriResolver.resolveArtworkUri(match);
      return PulsrAudioHandler._songToMediaItem(match, artUri);
    }

    // Resolve the dynamic browsable nodes so Android Auto can render album art
    // and subtitles for queue / "now playing" deep links instead of blanks.
    try {
      if (mediaId.startsWith('album_')) {
        final albumId = int.tryParse(mediaId.substring(6));
        if (albumId == null) return null;
        final albumsRes = await _repository.getAlbums();
        final albums = albumsRes.fold((l) => <AlbumsTableData>[], (r) => r);
        final match = _firstWhereOrNull(albums, (a) => a.id == albumId);
        if (match == null) return null;
        final artUri = await ArtworkUriResolver.getAlbumArtUri(match.id);
        return _container(mediaId, match.title,
            subtitle: match.artist, artUri: artUri);
      }

      if (mediaId.startsWith('artist_')) {
        final artistId = int.tryParse(mediaId.substring(7));
        if (artistId == null) return null;
        final artistsRes = await _repository.getArtists();
        final artists = artistsRes.fold((l) => <ArtistsTableData>[], (r) => r);
        final match = _firstWhereOrNull(artists, (a) => a.id == artistId);
        if (match == null) return null;
        final artUri = await ArtworkUriResolver.getArtistArtUri(match.id);
        return _container(mediaId, match.name,
            subtitle: '${match.songCount} songs', artUri: artUri);
      }

      if (mediaId.startsWith('playlist_')) {
        final playlistId = int.tryParse(mediaId.substring(9));
        if (playlistId == null) return null;
        final playlistsRes = await _repository.getPlaylists();
        final playlists =
            playlistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);
        final match = _firstWhereOrNull(playlists, (p) => p.id == playlistId);
        if (match == null) return null;
        return _container(mediaId, match.name, style: _kBrowseListExtras);
      }

      if (mediaId.startsWith('genre_')) {
        final name = mediaId.substring(6);
        if (name.isEmpty) return null;
        final genresRes = await _repository.getGenres();
        final genres = genresRes.fold((l) => <GenreItem>[], (r) => r);
        final match = _firstWhereOrNull(genres, (g) => g.name == name);
        return _container(mediaId, name,
            subtitle: match == null ? null : '${match.songCount} songs',
            style: _kBrowseListExtras);
      }

      if (mediaId == 'ytm_trending' || mediaId == 'ytm_favorites') {
        return _staticContainer(mediaId);
      }

      return _staticContainer(mediaId);
    } catch (_) {
      return _staticContainer(mediaId);
    }
  }

  /// Plays every song in a container node addressed by its browse id. Android
  /// Auto issues this for the "shuffle"/"play all" affordance on a folder.
  Future<bool> _playContainer(String mediaId) async {
    switch (mediaId) {
      case 'albums':
      case 'root_albums':
      case 'artists':
      case 'root_artists':
      case 'playlists':
      case 'root_playlists':
      case 'genres':
      case 'root_genres':
      case 'browse_mood':
      case 'root_browse_mood':
        await _loadSongsIfAny(_unwrapSongs(await _repository.getAllSongs()));
        return true;
      case 'songs':
      case 'root_songs':
        await _loadSongsIfAny(_unwrapSongs(await _repository.getAllSongs()));
        return true;
      case 'favorites':
      case 'root_favorites':
        await _loadSongsIfAny(_unwrapSongs(await _repository.getFavorites()));
        return true;
      case 'downloaded':
      case 'root_downloaded':
        final all = _unwrapSongs(await _repository.getAllSongs());
        await _loadSongsIfAny(all
            .where((s) => s.isDownloaded || s.source == SongSource.local)
            .toList());
        return true;
      case 'root_recent':
      case AudioService.recentRootId:
        if (_songs.isNotEmpty && _activePlayer.playing) return true;
        await _loadSongsIfAny(
            _unwrapSongs(await _repository.getRecentlyPlayed()));
        return true;
      case 'ytm_trending':
        if (!AppConfig.ytmEnabled) return false;
        try {
          final tracks = await _ytmService.trending(limit: 30);
          await _loadSongsIfAny(tracks.map((t) => t.toSongData()).toList());
          return true;
        } catch (_) {
          return false;
        }
      case 'ytm_favorites':
        if (!AppConfig.ytmEnabled) return false;
        final allFavs = _unwrapSongs(await _repository.getFavorites());
        await _loadSongsIfAny(allFavs
            .where((s) =>
                s.source == SongSource.youtube ||
                (s.remoteId != null && s.remoteId!.isNotEmpty))
            .toList());
        return true;
    }

    if (mediaId.startsWith('mood_')) {
      final all = _unwrapSongs(await _repository.getAllSongs());
      await _loadSongsIfAny(_filterByMood(all, mediaId.substring(5)));
      return true;
    }
    if (mediaId.startsWith('album_')) {
      final id = int.tryParse(mediaId.substring(6));
      if (id != null) {
        await _loadSongsIfAny(_unwrapSongs(await _repository.getAlbumSongs(id)));
        return true;
      }
    }
    if (mediaId.startsWith('artist_')) {
      final id = int.tryParse(mediaId.substring(7));
      if (id != null) {
        await _loadSongsIfAny(
            _unwrapSongs(await _repository.getArtistSongs(id)));
        return true;
      }
    }
    if (mediaId.startsWith('playlist_')) {
      final id = int.tryParse(mediaId.substring(9));
      if (id != null) {
        await _loadSongsIfAny(
            _unwrapSongs(await _repository.getPlaylistSongs(id)));
        return true;
      }
    }
    if (mediaId.startsWith('genre_')) {
      final name = mediaId.substring(6);
      if (name.isNotEmpty) {
        await _loadSongsIfAny(
            _unwrapSongs(await _repository.getGenreSongs(name)));
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    if (mediaId == 'action_bass_boost') {
      await _toggleBassBoost();
      return;
    }
    if (mediaId == 'action_virtualizer') {
      await _toggleVirtualizer();
      return;
    }
    if (mediaId == 'action_sleep_timer') {
      await _toggleSleepTimer30m();
      return;
    }

    final queueIndex = _songs
        .indexWhere((s) => s.id.toString() == mediaId || s.remoteId == mediaId);
    if (queueIndex != -1) {
      await loadQueue(_songs, initialIndex: queueIndex);
      return;
    }

    final songId = int.tryParse(mediaId);
    if (songId != null) {
      final songsRes = await _repository.getAllSongs();
      final all = songsRes.fold((l) => <SongsTableData>[], (r) => r);
      final index = all.indexWhere((s) => s.id == songId);
      if (index != -1) {
        await loadQueue(all, initialIndex: index);
        return;
      }
    }

    if (extras != null &&
        (extras['remoteId'] != null ||
            extras['source'] == SongSource.youtube ||
            mediaId.length == 11)) {
      final remoteId = (extras['remoteId'] as String?) ?? mediaId;
      final uniqueNegativeId = -(remoteId.hashCode.abs() % 1000000000 + 1);
      final onlineSong = SongsTableData(
        // Never reuse a positive library id for an online-only row: it could
        // collide with a real song and misattribute play history.
        id: uniqueNegativeId,
        title: extras['title'] as String? ?? 'Unknown',
        artist: extras['artist'] as String? ?? 'Unknown Artist',
        album: extras['album'] as String? ?? '',
        durationMs: (extras['durationMs'] as num?)?.toInt() ?? 0,
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

    // Anything left is a browsable container/folder: honor "play all".
    await _playContainer(mediaId);
  }

  /// Android Auto / Assistant can hand playback the raw content URI instead of
  /// a browse id (`ACTION_PLAY_FROM_URI`). Match it against the library first,
  /// then fall back to a transient row so streams still start.
  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    if (uri.toString().isEmpty) return;
    final uriStr = uri.toString();

    final all = _unwrapSongs(await _repository.getAllSongs());
    final idx = all.indexWhere((s) {
      if (s.uri != null && s.uri == uriStr) return true;
      if (s.path.isNotEmpty && uri.scheme == 'file') {
        try {
          return p.equals(s.path, uri.toFilePath());
        } catch (_) {
          return false;
        }
      }
      return false;
    });
    if (idx != -1) {
      await loadQueue(all, initialIndex: idx);
      return;
    }

    final fallbackName = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : (uri.host.isNotEmpty ? uri.host : uriStr);
    final title = (extras?['title'] as String?)?.trim().isNotEmpty == true
        ? extras!['title'] as String
        : p.basenameWithoutExtension(fallbackName);
    final remoteId = extras?['remoteId'] as String? ??
        (uri.scheme == 'pulsr' ? uri.host : null);
    final uniqueNegativeId =
        -((remoteId ?? uriStr).hashCode.abs() % 1000000000 + 1);

    final transient = SongsTableData(
      id: uniqueNegativeId,
      title: title.isEmpty ? 'Unknown' : title,
      artist: extras?['artist'] as String? ?? 'Unknown Artist',
      album: extras?['album'] as String? ?? '',
      durationMs: (extras?['durationMs'] as num?)?.toInt() ?? 0,
      path: uri.scheme == 'file' ? uri.toFilePath() : uriStr,
      uri: uriStr,
      source: extras?['source'] as String? ??
          (remoteId != null ? SongSource.youtube : SongSource.local),
      remoteId: remoteId,
      remoteArtworkUrl: extras?['remoteArtworkUrl'] as String?,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );
    await loadQueue([transient], initialIndex: 0);
  }

  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return [];
    // Use the indexed FTS search instead of materializing and linear-scanning
    // the entire library on every Android Auto query.
    List<SongsTableData> matches;
    try {
      final songsRes = await _repository
          .watchAllSongs(searchQuery: query.trim(), limit: 50)
          .first
          .timeout(const Duration(seconds: 5));
      matches = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    } catch (_) {
      matches = const <SongsTableData>[];
    }
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
          results.add(PulsrAudioHandler._songToMediaItem(song, artUri));
        }
      } catch (_) {}
    }

    return results;
  }

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return;
    var cleanQ = query.trim();
    // Honor Android Auto voice extras: "play [artist]" / genre / shuffle asks.
    var autoShuffle = false;
    try {
      final focus = extras?['android.media.extra.MEDIA_FOCUS'] as String?;
      if (focus != null && focus.contains('v16')) autoShuffle = true;
      final artist =
          extras?['android.media.extra.EXTRA_METADATA_ARTIST'] as String?;
      final album =
          extras?['android.media.extra.EXTRA_METADATA_ALBUM'] as String?;
      final genre =
          extras?['android.media.extra.EXTRA_METADATA_GENRE'] as String?;
      final title =
          extras?['android.media.extra.EXTRA_METADATA_TITLE'] as String?;
      final pick = title?.isNotEmpty == true
          ? title!
          : artist?.isNotEmpty == true
              ? artist!
              : album?.isNotEmpty == true
                  ? album!
                  : genre?.isNotEmpty == true
                      ? genre!
                      : cleanQ;
      if (pick.trim().isNotEmpty) cleanQ = pick.trim();
    } catch (_) {
      cleanQ = query.trim();
    }

    final lowerQ = cleanQ.toLowerCase();
    if (lowerQ.contains('boost the bass') ||
        lowerQ.contains('bass boost') ||
        lowerQ.contains('boost bass')) {
      await _toggleBassBoost(forceEnable: true);
      return;
    }
    if (lowerQ.contains('virtualizer') || lowerQ.contains('surround sound')) {
      await _toggleVirtualizer(forceEnable: true);
      return;
    }
    if (lowerQ.contains('sleep timer')) {
      await _toggleSleepTimer30m();
      return;
    }

    // Indexed FTS search (title/artist/album) instead of a full-library scan.
    List<SongsTableData> matches;
    try {
      final songsRes = await _repository
          .watchAllSongs(searchQuery: cleanQ, limit: 50)
          .first
          .timeout(const Duration(seconds: 5));
      matches = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    } catch (_) {
      matches = const <SongsTableData>[];
    }
    if (matches.isNotEmpty) {
      // Copy first: the repository list may be unmodifiable.
      final queueSongs = List<SongsTableData>.of(matches);
      if (autoShuffle) queueSongs.shuffle();
      await loadQueue(queueSongs);
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

  void _warmArtworkAsync(List<SongsTableData> songs, {int limit = 30}) {
    unawaited(() async {
      for (final song in songs.take(limit)) {
        if (ArtworkUriResolver.getCachedArtworkUri(song.id) == null) {
          await ArtworkUriResolver.resolveArtworkUri(song);
        }
      }
    }());
  }

  // Abstract contract supplied by the composing PulsrAudioHandler (same
  // library). Declaring these here keeps the mixin stateless and lets the
  // analyser type-check each mixin against the host's private members.
  AudioPlayer get _activePlayer;

  Future<List<R>> _boundedParallelMap<T, R>(
    List<T> items,
    Future<R> Function(T) mapper, {
    int concurrency = 6,
  });

  IMusicRepository get _repository;

  List<SongsTableData> get _songs;

  YtmService get _ytmService;

  EqualizerManager get _equalizerManager;

  SleepTimerManager get _sleepTimerManager;

  Future<void> _toggleBassBoost({bool? forceEnable}) async {
    final current = _equalizerManager.currentPreset.bassBoost;
    final enable = forceEnable ?? (current <= 0.05);
    await _equalizerManager.setBassBoost(enable ? 0.6 : 0.0);
  }

  Future<void> _toggleVirtualizer({bool? forceEnable}) async {
    final enable = forceEnable ?? !_equalizerManager.isVirtualizerEnabled;
    await _equalizerManager.setVirtualizerEnabled(enable);
    if (enable && _equalizerManager.virtualizerStrength <= 0.05) {
      await _equalizerManager.setVirtualizerStrength(0.5);
    }
  }

  Future<void> _toggleSleepTimer30m() async {
    if (_sleepTimerManager.isActive) {
      cancelSleepTimer();
    } else {
      // Go through the bridge: it wires onTimerExpired -> pause() and the
      // active-player fade-out, which the bare manager call did not.
      startSleepTimer(const Duration(minutes: 30));
    }
  }

  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0, Duration? initialPosition, bool autoPlay = true});

  /// Supplied by [PulsrAudioSleepBridge].
  void startSleepTimer(Duration duration, {bool fadeOut = true});
  void cancelSleepTimer();
}
