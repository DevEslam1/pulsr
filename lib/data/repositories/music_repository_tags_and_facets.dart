part of 'music_repository.dart';

/// Tag updates, audio-quality enrichment writes, and genre/year discovery
/// queries for [MusicRepository].
mixin _MusicRepositoryTagsAndFacets {
  AppDatabase get _db;

  Expression<bool> _notInExcludedFolders(List<String> excludedFolders);

  void _applyExcludedFolders(
    SimpleSelectStatement<$SongsTableTable, SongsTableData> query,
    List<String> excludedFolders,
  );

  Future<int?> _findOrCreateArtistId(String artistName);

  Future<int?> _findOrCreateAlbumId({
    required String albumTitle,
    required String artistName,
    int? artistId,
    String? artworkUri,
  });

  Future<void> _recalculateAlbumAndArtistCountsForIds({
    Iterable<int?> albumIds = const [],
    Iterable<int?> artistIds = const [],
  });

  Future<Result<void>> updateSongTags({
    required String path,
    required String title,
    required String artist,
    required String album,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
  }) async {
    try {
      final existing = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.path.lower().equals(path.toLowerCase()) &
                t.source.equals(SongSource.local) &
                t.cueStartMs.isNull()))
          .getSingleOrNull();
      if (existing != null) {
        // A reader that could not parse tags (or a failed tag write) reports
        // placeholders. Do not let that wipe real metadata that is already in
        // the library.
        final safeTitle = MetadataPlaceholders.isUnknownTitle(title) &&
                MetadataPlaceholders.isRealTitle(existing.title)
            ? existing.title
            : title;
        final safeArtist = MetadataPlaceholders.isUnknownArtist(artist) &&
                MetadataPlaceholders.isRealArtist(existing.artist)
            ? existing.artist
            : artist;
        final safeAlbum = MetadataPlaceholders.isUnknownAlbum(album) &&
                MetadataPlaceholders.isRealAlbum(existing.album)
            ? existing.album
            : album;
        await _db.transaction(() async {
          final oldAlbumId = existing.albumId;
          final oldArtistId = existing.artistId;
          final trimmedArtist = safeArtist.trim();
          final trimmedAlbum = safeAlbum.trim();

          // Rename single-owner artist/album rows in place so IDs stay stable,
          // while splitting out shared rows or resolving existing target rows
          // so other tracks and UNIQUE constraints are never corrupted.
          int? newArtistId;
          if (trimmedArtist.isNotEmpty) {
            final existingArtist = await (_db.select(_db.artistsTable)
                  ..where(
                      (t) => t.name.lower().equals(trimmedArtist.toLowerCase()))
                  ..limit(1))
                .getSingleOrNull();
            if (existingArtist != null) {
              newArtistId = existingArtist.id;
            } else if (oldArtistId != null) {
              final otherWithArtist = await (_db.select(_db.songsTable)
                    ..where((t) =>
                        t.artistId.equals(oldArtistId) &
                        t.id.equals(existing.id).not())
                    ..limit(1))
                  .getSingleOrNull();
              if (otherWithArtist == null) {
                await (_db.update(_db.artistsTable)
                      ..where((t) => t.id.equals(oldArtistId)))
                    .write(ArtistsTableCompanion(name: Value(trimmedArtist)));
                newArtistId = oldArtistId;
              } else {
                newArtistId = await _findOrCreateArtistId(safeArtist);
              }
            } else {
              newArtistId = await _findOrCreateArtistId(safeArtist);
            }
          }

          int? newAlbumId;
          if (trimmedAlbum.isNotEmpty) {
            final existingAlbum = await (_db.select(_db.albumsTable)
                  ..where((t) =>
                      t.title.lower().equals(trimmedAlbum.toLowerCase()) &
                      t.artist.lower().equals(trimmedArtist.toLowerCase()))
                  ..limit(1))
                .getSingleOrNull();
            if (existingAlbum != null) {
              newAlbumId = existingAlbum.id;
            } else if (oldAlbumId != null) {
              final otherWithAlbum = await (_db.select(_db.songsTable)
                    ..where((t) =>
                        t.albumId.equals(oldAlbumId) &
                        t.id.equals(existing.id).not())
                    ..limit(1))
                  .getSingleOrNull();
              if (otherWithAlbum == null) {
                await (_db.update(_db.albumsTable)
                      ..where((t) => t.id.equals(oldAlbumId)))
                    .write(AlbumsTableCompanion(
                  title: Value(trimmedAlbum),
                  artist: Value(trimmedArtist),
                  artistId: Value(newArtistId),
                ));
                newAlbumId = oldAlbumId;
              } else {
                newAlbumId = await _findOrCreateAlbumId(
                  albumTitle: safeAlbum,
                  artistName: safeArtist,
                  artistId: newArtistId,
                  artworkUri: existing.artworkUri,
                );
              }
            } else {
              newAlbumId = await _findOrCreateAlbumId(
                albumTitle: safeAlbum,
                artistName: safeArtist,
                artistId: newArtistId,
                artworkUri: existing.artworkUri,
              );
            }
          }

          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            SongsTableCompanion(
              title: Value(safeTitle),
              artist: Value(safeArtist),
              artistId: Value(newArtistId),
              album: Value(safeAlbum),
              albumId: Value(newAlbumId),
              genre: Value(genre),
              year: Value(year),
              trackNumber: Value(trackNumber),
              discNumber: Value(discNumber),
            ),
          );

          await _recalculateAlbumAndArtistCountsForIds(
            albumIds: [oldAlbumId, newAlbumId],
            artistIds: [oldArtistId, newArtistId],
          );
        });
      }
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update song tags', e));
    }
  }

  Future<Result<void>> updateAudioQualityBatch(
      List<
              ({
                int songId,
                String path,
                int? sampleRate,
                int? bitDepth,
                int? bitrateKbps,
                String? codec,
                double? loudnessRange
              })>
          updates) async {
    if (updates.isEmpty) return const Right(null);
    try {
      await _db.batch((batch) {
        for (final u in updates) {
          final companion = SongsTableCompanion(
            sampleRate: Value(u.sampleRate),
            bitDepth: Value(u.bitDepth),
            bitrateKbps: Value(u.bitrateKbps),
            codec: Value(u.codec),
            loudnessRange: Value(u.loudnessRange),
          );
          if (u.path.isNotEmpty) {
            batch.update(
              _db.songsTable,
              companion,
              where: (t) => t.path.equals(u.path),
            );
          } else {
            batch.update(
              _db.songsTable,
              companion,
              where: (t) => t.id.equals(u.songId),
            );
          }
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to batch update audio quality', e));
    }
  }

  Future<Result<void>> updateAudioQuality({
    required int songId,
    int? sampleRate,
    int? bitDepth,
    int? bitrateKbps,
    String? codec,
    double? loudnessRange,
  }) async {
    try {
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.id.equals(songId)))
          .getSingleOrNull();
      // A CUE image's virtual tracks all share the container's path, so push
      // the header fields to every row backed by the same file.
      final target = song != null && song.path.isNotEmpty
          ? (_db.update(_db.songsTable)..where((t) => t.path.equals(song.path)))
          : (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)));
      await target.write(
        SongsTableCompanion(
          sampleRate: Value(sampleRate),
          bitDepth: Value(bitDepth),
          bitrateKbps: Value(bitrateKbps),
          codec: Value(codec),
          loudnessRange: Value(loudnessRange),
        ),
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update audio quality', e));
    }
  }

  // --- GENRES ---
  Stream<Result<List<GenreItem>>> watchGenres({
    List<String> excludedFolders = const [],
  }) {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() &
            _db.songsTable.genre.equals('').not() &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()) &
            _notInExcludedFolders(excludedFolders))
        ..groupBy([_db.songsTable.genre])
        ..orderBy([OrderingTerm(expression: _db.songsTable.genre)]);

      return query.watch().map((rows) {
        final list = rows
            .map((row) {
              final genreName = row.read(_db.songsTable.genre) ?? '';
              final count = row.read(countExp) ?? 0;
              return GenreItem(name: genreName, songCount: count);
            })
            .where((g) => g.name.isNotEmpty)
            .toList();
        return Right<AppFailure, List<GenreItem>>(list);
      }).onResultError((e, st) => Left<AppFailure, List<GenreItem>>(
          DatabaseFailure('Failed to watch genres', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch genres', e)));
    }
  }

  Future<Result<List<GenreItem>>> getGenres({
    List<String> excludedFolders = const [],
  }) async {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() &
            _db.songsTable.genre.equals('').not() &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()) &
            _notInExcludedFolders(excludedFolders))
        ..groupBy([_db.songsTable.genre])
        ..orderBy([OrderingTerm(expression: _db.songsTable.genre)]);

      final rows = await query.get();
      final list = rows
          .map((row) {
            final genreName = row.read(_db.songsTable.genre) ?? '';
            final count = row.read(countExp) ?? 0;
            return GenreItem(name: genreName, songCount: count);
          })
          .where((g) => g.name.isNotEmpty)
          .toList();
      return Right(list);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get genres', e));
    }
  }

  Stream<Result<List<SongsTableData>>> watchGenreSongs(
    String genre, {
    List<String> excludedFolders = const [],
  }) {
    if (excludedFolders.isEmpty) {
      return _db
          .select(_db.excludedFoldersTable)
          .watch()
          .switchMap((rows) => _watchGenreSongsInternal(
                genre,
                rows.map((r) => r.folderPath).toList(growable: false),
              ));
    }
    return _watchGenreSongsInternal(genre, excludedFolders);
  }

  Stream<Result<List<SongsTableData>>> _watchGenreSongsInternal(
    String genre,
    List<String> excludedFolders,
  ) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.genre.equals(genre) &
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) => OrderingTerm(expression: t.title),
          (t) => OrderingTerm.asc(t.id),
        ]);
      _applyExcludedFolders(query, excludedFolders);
      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch genre songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch genre songs', e)));
    }
  }

  Future<Result<List<SongsTableData>>> getGenreSongs(
    String genre, {
    List<String> excludedFolders = const [],
  }) async {
    try {
      final effectiveExcluded = excludedFolders.isNotEmpty
          ? excludedFolders
          : (await _db.select(_db.excludedFoldersTable).get())
              .map((r) => r.folderPath)
              .toList(growable: false);
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.genre.equals(genre) &
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) => OrderingTerm(expression: t.title),
          (t) => OrderingTerm.asc(t.id),
        ]);
      _applyExcludedFolders(query, effectiveExcluded);
      final songs = await query.get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get genre songs', e));
    }
  }

  // --- YEARS ---
  Stream<Result<List<YearItem>>> watchYears({
    List<String> excludedFolders = const [],
  }) {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.year, countExp])
        ..where(_db.songsTable.year.isNotNull() &
            _db.songsTable.year.isBiggerThanValue(0) &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()) &
            _notInExcludedFolders(excludedFolders))
        ..groupBy([_db.songsTable.year])
        ..orderBy([
          OrderingTerm(expression: _db.songsTable.year, mode: OrderingMode.desc)
        ]);

      return query.watch().map((rows) {
        final list = rows
            .map((row) {
              final yr = row.read(_db.songsTable.year) ?? 0;
              final count = row.read(countExp) ?? 0;
              return YearItem(year: yr, songCount: count);
            })
            .where((y) => y.year > 0)
            .toList();
        return Right<AppFailure, List<YearItem>>(list);
      }).onResultError((e, st) => Left<AppFailure, List<YearItem>>(
          DatabaseFailure('Failed to watch years', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch years', e)));
    }
  }

  Stream<Result<List<SongsTableData>>> watchYearSongs(
    int year, {
    List<String> excludedFolders = const [],
  }) {
    if (excludedFolders.isEmpty) {
      return _db
          .select(_db.excludedFoldersTable)
          .watch()
          .switchMap((rows) => _watchYearSongsInternal(
                year,
                rows.map((r) => r.folderPath).toList(growable: false),
              ));
    }
    return _watchYearSongsInternal(year, excludedFolders);
  }

  Stream<Result<List<SongsTableData>>> _watchYearSongsInternal(
    int year,
    List<String> excludedFolders,
  ) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.year.equals(year) &
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) => OrderingTerm(expression: t.title),
          (t) => OrderingTerm.asc(t.id),
        ]);
      _applyExcludedFolders(query, excludedFolders);
      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch year songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch year songs', e)));
    }
  }
}
