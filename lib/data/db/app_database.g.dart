// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SongsTableTable extends SongsTable
    with TableInfo<$SongsTableTable, SongsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown Artist'));
  static const VerificationMeta _artistIdMeta =
      const VerificationMeta('artistId');
  @override
  late final GeneratedColumn<int> artistId = GeneratedColumn<int>(
      'artist_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
      'album', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown Album'));
  static const VerificationMeta _albumIdMeta =
      const VerificationMeta('albumId');
  @override
  late final GeneratedColumn<int> albumId = GeneratedColumn<int>(
      'album_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
      'uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _trackNumberMeta =
      const VerificationMeta('trackNumber');
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
      'track_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _discNumberMeta =
      const VerificationMeta('discNumber');
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
      'disc_number', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _dateAddedMeta =
      const VerificationMeta('dateAdded');
  @override
  late final GeneratedColumn<int> dateAdded = GeneratedColumn<int>(
      'date_added', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
      'genre', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isMissingMeta =
      const VerificationMeta('isMissing');
  @override
  late final GeneratedColumn<bool> isMissing = GeneratedColumn<bool>(
      'is_missing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_missing" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _replayGainMeta =
      const VerificationMeta('replayGain');
  @override
  late final GeneratedColumn<double> replayGain = GeneratedColumn<double>(
      'replay_gain', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _playCountMeta =
      const VerificationMeta('playCount');
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
      'play_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPlayedMeta =
      const VerificationMeta('lastPlayed');
  @override
  late final GeneratedColumn<int> lastPlayed = GeneratedColumn<int>(
      'last_played', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastPositionMsMeta =
      const VerificationMeta('lastPositionMs');
  @override
  late final GeneratedColumn<int> lastPositionMs = GeneratedColumn<int>(
      'last_position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _artworkUriMeta =
      const VerificationMeta('artworkUri');
  @override
  late final GeneratedColumn<String> artworkUri = GeneratedColumn<String>(
      'artwork_uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fileSizeMeta =
      const VerificationMeta('fileSize');
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
      'file_size', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(SongSource.local));
  static const VerificationMeta _remoteIdMeta =
      const VerificationMeta('remoteId');
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
      'remote_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _remoteArtworkUrlMeta =
      const VerificationMeta('remoteArtworkUrl');
  @override
  late final GeneratedColumn<String> remoteArtworkUrl = GeneratedColumn<String>(
      'remote_artwork_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pendingDownloadPathMeta =
      const VerificationMeta('pendingDownloadPath');
  @override
  late final GeneratedColumn<String> pendingDownloadPath =
      GeneratedColumn<String>('pending_download_path', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        artist,
        artistId,
        album,
        albumId,
        durationMs,
        path,
        uri,
        trackNumber,
        discNumber,
        year,
        dateAdded,
        genre,
        isFavorite,
        isMissing,
        replayGain,
        playCount,
        lastPlayed,
        lastPositionMs,
        artworkUri,
        fileSize,
        source,
        remoteId,
        remoteArtworkUrl,
        pendingDownloadPath
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(Insertable<SongsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    }
    if (data.containsKey('artist_id')) {
      context.handle(_artistIdMeta,
          artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta));
    }
    if (data.containsKey('album')) {
      context.handle(
          _albumMeta, album.isAcceptableOrUnknown(data['album']!, _albumMeta));
    }
    if (data.containsKey('album_id')) {
      context.handle(_albumIdMeta,
          albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('uri')) {
      context.handle(
          _uriMeta, uri.isAcceptableOrUnknown(data['uri']!, _uriMeta));
    }
    if (data.containsKey('track_number')) {
      context.handle(
          _trackNumberMeta,
          trackNumber.isAcceptableOrUnknown(
              data['track_number']!, _trackNumberMeta));
    }
    if (data.containsKey('disc_number')) {
      context.handle(
          _discNumberMeta,
          discNumber.isAcceptableOrUnknown(
              data['disc_number']!, _discNumberMeta));
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    }
    if (data.containsKey('date_added')) {
      context.handle(_dateAddedMeta,
          dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta));
    }
    if (data.containsKey('genre')) {
      context.handle(
          _genreMeta, genre.isAcceptableOrUnknown(data['genre']!, _genreMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    if (data.containsKey('is_missing')) {
      context.handle(_isMissingMeta,
          isMissing.isAcceptableOrUnknown(data['is_missing']!, _isMissingMeta));
    }
    if (data.containsKey('replay_gain')) {
      context.handle(
          _replayGainMeta,
          replayGain.isAcceptableOrUnknown(
              data['replay_gain']!, _replayGainMeta));
    }
    if (data.containsKey('play_count')) {
      context.handle(_playCountMeta,
          playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta));
    }
    if (data.containsKey('last_played')) {
      context.handle(
          _lastPlayedMeta,
          lastPlayed.isAcceptableOrUnknown(
              data['last_played']!, _lastPlayedMeta));
    }
    if (data.containsKey('last_position_ms')) {
      context.handle(
          _lastPositionMsMeta,
          lastPositionMs.isAcceptableOrUnknown(
              data['last_position_ms']!, _lastPositionMsMeta));
    }
    if (data.containsKey('artwork_uri')) {
      context.handle(
          _artworkUriMeta,
          artworkUri.isAcceptableOrUnknown(
              data['artwork_uri']!, _artworkUriMeta));
    }
    if (data.containsKey('file_size')) {
      context.handle(_fileSizeMeta,
          fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('remote_id')) {
      context.handle(_remoteIdMeta,
          remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta));
    }
    if (data.containsKey('remote_artwork_url')) {
      context.handle(
          _remoteArtworkUrlMeta,
          remoteArtworkUrl.isAcceptableOrUnknown(
              data['remote_artwork_url']!, _remoteArtworkUrlMeta));
    }
    if (data.containsKey('pending_download_path')) {
      context.handle(
          _pendingDownloadPathMeta,
          pendingDownloadPath.isAcceptableOrUnknown(
              data['pending_download_path']!, _pendingDownloadPathMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SongsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist'])!,
      artistId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}artist_id']),
      album: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album'])!,
      albumId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}album_id']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      uri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uri']),
      trackNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}track_number']),
      discNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}disc_number']),
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year']),
      dateAdded: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date_added']),
      genre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}genre']),
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
      isMissing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_missing'])!,
      replayGain: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}replay_gain']),
      playCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}play_count'])!,
      lastPlayed: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_played']),
      lastPositionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_position_ms'])!,
      artworkUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artwork_uri']),
      fileSize: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size']),
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      remoteId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}remote_id']),
      remoteArtworkUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}remote_artwork_url']),
      pendingDownloadPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}pending_download_path']),
    );
  }

  @override
  $SongsTableTable createAlias(String alias) {
    return $SongsTableTable(attachedDatabase, alias);
  }
}

class SongsTableData extends DataClass implements Insertable<SongsTableData> {
  final int id;
  final String title;
  final String artist;
  final int? artistId;
  final String album;
  final int? albumId;
  final int durationMs;
  final String path;
  final String? uri;
  final int? trackNumber;
  final int? discNumber;
  final int? year;

  /// Stored as timestamp (seconds or milliseconds since Unix epoch, consistent with MediaStore/on_audio_query).
  final int? dateAdded;
  final String? genre;
  final bool isFavorite;
  final bool isMissing;
  final double? replayGain;
  final int playCount;
  final int? lastPlayed;
  final int lastPositionMs;
  final String? artworkUri;
  final int? fileSize;

  /// See [SongSource]. Rows that are not [SongSource.local] have no file on
  /// disk, so scanner cleanup and every path-derived query must exclude them.
  final String source;

  /// YouTube video id. Kept after a download completes so the same video is
  /// not fetched twice.
  final String? remoteId;
  final String? remoteArtworkUrl;

  /// Destination a download is writing to, used to match the row MediaStore
  /// creates once the file lands.
  final String? pendingDownloadPath;
  const SongsTableData(
      {required this.id,
      required this.title,
      required this.artist,
      this.artistId,
      required this.album,
      this.albumId,
      required this.durationMs,
      required this.path,
      this.uri,
      this.trackNumber,
      this.discNumber,
      this.year,
      this.dateAdded,
      this.genre,
      required this.isFavorite,
      required this.isMissing,
      this.replayGain,
      required this.playCount,
      this.lastPlayed,
      required this.lastPositionMs,
      this.artworkUri,
      this.fileSize,
      required this.source,
      this.remoteId,
      this.remoteArtworkUrl,
      this.pendingDownloadPath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<int>(artistId);
    }
    map['album'] = Variable<String>(album);
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<int>(albumId);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || uri != null) {
      map['uri'] = Variable<String>(uri);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || dateAdded != null) {
      map['date_added'] = Variable<int>(dateAdded);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['is_missing'] = Variable<bool>(isMissing);
    if (!nullToAbsent || replayGain != null) {
      map['replay_gain'] = Variable<double>(replayGain);
    }
    map['play_count'] = Variable<int>(playCount);
    if (!nullToAbsent || lastPlayed != null) {
      map['last_played'] = Variable<int>(lastPlayed);
    }
    map['last_position_ms'] = Variable<int>(lastPositionMs);
    if (!nullToAbsent || artworkUri != null) {
      map['artwork_uri'] = Variable<String>(artworkUri);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    if (!nullToAbsent || remoteArtworkUrl != null) {
      map['remote_artwork_url'] = Variable<String>(remoteArtworkUrl);
    }
    if (!nullToAbsent || pendingDownloadPath != null) {
      map['pending_download_path'] = Variable<String>(pendingDownloadPath);
    }
    return map;
  }

  SongsTableCompanion toCompanion(bool nullToAbsent) {
    return SongsTableCompanion(
      id: Value(id),
      title: Value(title),
      artist: Value(artist),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      album: Value(album),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      durationMs: Value(durationMs),
      path: Value(path),
      uri: uri == null && nullToAbsent ? const Value.absent() : Value(uri),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      dateAdded: dateAdded == null && nullToAbsent
          ? const Value.absent()
          : Value(dateAdded),
      genre:
          genre == null && nullToAbsent ? const Value.absent() : Value(genre),
      isFavorite: Value(isFavorite),
      isMissing: Value(isMissing),
      replayGain: replayGain == null && nullToAbsent
          ? const Value.absent()
          : Value(replayGain),
      playCount: Value(playCount),
      lastPlayed: lastPlayed == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayed),
      lastPositionMs: Value(lastPositionMs),
      artworkUri: artworkUri == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUri),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      source: Value(source),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
      remoteArtworkUrl: remoteArtworkUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteArtworkUrl),
      pendingDownloadPath: pendingDownloadPath == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingDownloadPath),
    );
  }

  factory SongsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongsTableData(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      artistId: serializer.fromJson<int?>(json['artistId']),
      album: serializer.fromJson<String>(json['album']),
      albumId: serializer.fromJson<int?>(json['albumId']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      path: serializer.fromJson<String>(json['path']),
      uri: serializer.fromJson<String?>(json['uri']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      year: serializer.fromJson<int?>(json['year']),
      dateAdded: serializer.fromJson<int?>(json['dateAdded']),
      genre: serializer.fromJson<String?>(json['genre']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      isMissing: serializer.fromJson<bool>(json['isMissing']),
      replayGain: serializer.fromJson<double?>(json['replayGain']),
      playCount: serializer.fromJson<int>(json['playCount']),
      lastPlayed: serializer.fromJson<int?>(json['lastPlayed']),
      lastPositionMs: serializer.fromJson<int>(json['lastPositionMs']),
      artworkUri: serializer.fromJson<String?>(json['artworkUri']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      source: serializer.fromJson<String>(json['source']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
      remoteArtworkUrl: serializer.fromJson<String?>(json['remoteArtworkUrl']),
      pendingDownloadPath:
          serializer.fromJson<String?>(json['pendingDownloadPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'artistId': serializer.toJson<int?>(artistId),
      'album': serializer.toJson<String>(album),
      'albumId': serializer.toJson<int?>(albumId),
      'durationMs': serializer.toJson<int>(durationMs),
      'path': serializer.toJson<String>(path),
      'uri': serializer.toJson<String?>(uri),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'year': serializer.toJson<int?>(year),
      'dateAdded': serializer.toJson<int?>(dateAdded),
      'genre': serializer.toJson<String?>(genre),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'isMissing': serializer.toJson<bool>(isMissing),
      'replayGain': serializer.toJson<double?>(replayGain),
      'playCount': serializer.toJson<int>(playCount),
      'lastPlayed': serializer.toJson<int?>(lastPlayed),
      'lastPositionMs': serializer.toJson<int>(lastPositionMs),
      'artworkUri': serializer.toJson<String?>(artworkUri),
      'fileSize': serializer.toJson<int?>(fileSize),
      'source': serializer.toJson<String>(source),
      'remoteId': serializer.toJson<String?>(remoteId),
      'remoteArtworkUrl': serializer.toJson<String?>(remoteArtworkUrl),
      'pendingDownloadPath': serializer.toJson<String?>(pendingDownloadPath),
    };
  }

  SongsTableData copyWith(
          {int? id,
          String? title,
          String? artist,
          Value<int?> artistId = const Value.absent(),
          String? album,
          Value<int?> albumId = const Value.absent(),
          int? durationMs,
          String? path,
          Value<String?> uri = const Value.absent(),
          Value<int?> trackNumber = const Value.absent(),
          Value<int?> discNumber = const Value.absent(),
          Value<int?> year = const Value.absent(),
          Value<int?> dateAdded = const Value.absent(),
          Value<String?> genre = const Value.absent(),
          bool? isFavorite,
          bool? isMissing,
          Value<double?> replayGain = const Value.absent(),
          int? playCount,
          Value<int?> lastPlayed = const Value.absent(),
          int? lastPositionMs,
          Value<String?> artworkUri = const Value.absent(),
          Value<int?> fileSize = const Value.absent(),
          String? source,
          Value<String?> remoteId = const Value.absent(),
          Value<String?> remoteArtworkUrl = const Value.absent(),
          Value<String?> pendingDownloadPath = const Value.absent()}) =>
      SongsTableData(
        id: id ?? this.id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artistId: artistId.present ? artistId.value : this.artistId,
        album: album ?? this.album,
        albumId: albumId.present ? albumId.value : this.albumId,
        durationMs: durationMs ?? this.durationMs,
        path: path ?? this.path,
        uri: uri.present ? uri.value : this.uri,
        trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
        discNumber: discNumber.present ? discNumber.value : this.discNumber,
        year: year.present ? year.value : this.year,
        dateAdded: dateAdded.present ? dateAdded.value : this.dateAdded,
        genre: genre.present ? genre.value : this.genre,
        isFavorite: isFavorite ?? this.isFavorite,
        isMissing: isMissing ?? this.isMissing,
        replayGain: replayGain.present ? replayGain.value : this.replayGain,
        playCount: playCount ?? this.playCount,
        lastPlayed: lastPlayed.present ? lastPlayed.value : this.lastPlayed,
        lastPositionMs: lastPositionMs ?? this.lastPositionMs,
        artworkUri: artworkUri.present ? artworkUri.value : this.artworkUri,
        fileSize: fileSize.present ? fileSize.value : this.fileSize,
        source: source ?? this.source,
        remoteId: remoteId.present ? remoteId.value : this.remoteId,
        remoteArtworkUrl: remoteArtworkUrl.present
            ? remoteArtworkUrl.value
            : this.remoteArtworkUrl,
        pendingDownloadPath: pendingDownloadPath.present
            ? pendingDownloadPath.value
            : this.pendingDownloadPath,
      );
  SongsTableData copyWithCompanion(SongsTableCompanion data) {
    return SongsTableData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      album: data.album.present ? data.album.value : this.album,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      path: data.path.present ? data.path.value : this.path,
      uri: data.uri.present ? data.uri.value : this.uri,
      trackNumber:
          data.trackNumber.present ? data.trackNumber.value : this.trackNumber,
      discNumber:
          data.discNumber.present ? data.discNumber.value : this.discNumber,
      year: data.year.present ? data.year.value : this.year,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      genre: data.genre.present ? data.genre.value : this.genre,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
      isMissing: data.isMissing.present ? data.isMissing.value : this.isMissing,
      replayGain:
          data.replayGain.present ? data.replayGain.value : this.replayGain,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      lastPlayed:
          data.lastPlayed.present ? data.lastPlayed.value : this.lastPlayed,
      lastPositionMs: data.lastPositionMs.present
          ? data.lastPositionMs.value
          : this.lastPositionMs,
      artworkUri:
          data.artworkUri.present ? data.artworkUri.value : this.artworkUri,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      source: data.source.present ? data.source.value : this.source,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      remoteArtworkUrl: data.remoteArtworkUrl.present
          ? data.remoteArtworkUrl.value
          : this.remoteArtworkUrl,
      pendingDownloadPath: data.pendingDownloadPath.present
          ? data.pendingDownloadPath.value
          : this.pendingDownloadPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongsTableData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('durationMs: $durationMs, ')
          ..write('path: $path, ')
          ..write('uri: $uri, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('genre: $genre, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isMissing: $isMissing, ')
          ..write('replayGain: $replayGain, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('lastPositionMs: $lastPositionMs, ')
          ..write('artworkUri: $artworkUri, ')
          ..write('fileSize: $fileSize, ')
          ..write('source: $source, ')
          ..write('remoteId: $remoteId, ')
          ..write('remoteArtworkUrl: $remoteArtworkUrl, ')
          ..write('pendingDownloadPath: $pendingDownloadPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        title,
        artist,
        artistId,
        album,
        albumId,
        durationMs,
        path,
        uri,
        trackNumber,
        discNumber,
        year,
        dateAdded,
        genre,
        isFavorite,
        isMissing,
        replayGain,
        playCount,
        lastPlayed,
        lastPositionMs,
        artworkUri,
        fileSize,
        source,
        remoteId,
        remoteArtworkUrl,
        pendingDownloadPath
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongsTableData &&
          other.id == this.id &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.artistId == this.artistId &&
          other.album == this.album &&
          other.albumId == this.albumId &&
          other.durationMs == this.durationMs &&
          other.path == this.path &&
          other.uri == this.uri &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.year == this.year &&
          other.dateAdded == this.dateAdded &&
          other.genre == this.genre &&
          other.isFavorite == this.isFavorite &&
          other.isMissing == this.isMissing &&
          other.replayGain == this.replayGain &&
          other.playCount == this.playCount &&
          other.lastPlayed == this.lastPlayed &&
          other.lastPositionMs == this.lastPositionMs &&
          other.artworkUri == this.artworkUri &&
          other.fileSize == this.fileSize &&
          other.source == this.source &&
          other.remoteId == this.remoteId &&
          other.remoteArtworkUrl == this.remoteArtworkUrl &&
          other.pendingDownloadPath == this.pendingDownloadPath);
}

class SongsTableCompanion extends UpdateCompanion<SongsTableData> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> artist;
  final Value<int?> artistId;
  final Value<String> album;
  final Value<int?> albumId;
  final Value<int> durationMs;
  final Value<String> path;
  final Value<String?> uri;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<int?> year;
  final Value<int?> dateAdded;
  final Value<String?> genre;
  final Value<bool> isFavorite;
  final Value<bool> isMissing;
  final Value<double?> replayGain;
  final Value<int> playCount;
  final Value<int?> lastPlayed;
  final Value<int> lastPositionMs;
  final Value<String?> artworkUri;
  final Value<int?> fileSize;
  final Value<String> source;
  final Value<String?> remoteId;
  final Value<String?> remoteArtworkUrl;
  final Value<String?> pendingDownloadPath;
  const SongsTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.path = const Value.absent(),
    this.uri = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.genre = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isMissing = const Value.absent(),
    this.replayGain = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.artworkUri = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.source = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.remoteArtworkUrl = const Value.absent(),
    this.pendingDownloadPath = const Value.absent(),
  });
  SongsTableCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.durationMs = const Value.absent(),
    required String path,
    this.uri = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.genre = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isMissing = const Value.absent(),
    this.replayGain = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.artworkUri = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.source = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.remoteArtworkUrl = const Value.absent(),
    this.pendingDownloadPath = const Value.absent(),
  })  : title = Value(title),
        path = Value(path);
  static Insertable<SongsTableData> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<int>? artistId,
    Expression<String>? album,
    Expression<int>? albumId,
    Expression<int>? durationMs,
    Expression<String>? path,
    Expression<String>? uri,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<int>? year,
    Expression<int>? dateAdded,
    Expression<String>? genre,
    Expression<bool>? isFavorite,
    Expression<bool>? isMissing,
    Expression<double>? replayGain,
    Expression<int>? playCount,
    Expression<int>? lastPlayed,
    Expression<int>? lastPositionMs,
    Expression<String>? artworkUri,
    Expression<int>? fileSize,
    Expression<String>? source,
    Expression<String>? remoteId,
    Expression<String>? remoteArtworkUrl,
    Expression<String>? pendingDownloadPath,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (album != null) 'album': album,
      if (albumId != null) 'album_id': albumId,
      if (durationMs != null) 'duration_ms': durationMs,
      if (path != null) 'path': path,
      if (uri != null) 'uri': uri,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (year != null) 'year': year,
      if (dateAdded != null) 'date_added': dateAdded,
      if (genre != null) 'genre': genre,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isMissing != null) 'is_missing': isMissing,
      if (replayGain != null) 'replay_gain': replayGain,
      if (playCount != null) 'play_count': playCount,
      if (lastPlayed != null) 'last_played': lastPlayed,
      if (lastPositionMs != null) 'last_position_ms': lastPositionMs,
      if (artworkUri != null) 'artwork_uri': artworkUri,
      if (fileSize != null) 'file_size': fileSize,
      if (source != null) 'source': source,
      if (remoteId != null) 'remote_id': remoteId,
      if (remoteArtworkUrl != null) 'remote_artwork_url': remoteArtworkUrl,
      if (pendingDownloadPath != null)
        'pending_download_path': pendingDownloadPath,
    });
  }

  SongsTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? title,
      Value<String>? artist,
      Value<int?>? artistId,
      Value<String>? album,
      Value<int?>? albumId,
      Value<int>? durationMs,
      Value<String>? path,
      Value<String?>? uri,
      Value<int?>? trackNumber,
      Value<int?>? discNumber,
      Value<int?>? year,
      Value<int?>? dateAdded,
      Value<String?>? genre,
      Value<bool>? isFavorite,
      Value<bool>? isMissing,
      Value<double?>? replayGain,
      Value<int>? playCount,
      Value<int?>? lastPlayed,
      Value<int>? lastPositionMs,
      Value<String?>? artworkUri,
      Value<int?>? fileSize,
      Value<String>? source,
      Value<String?>? remoteId,
      Value<String?>? remoteArtworkUrl,
      Value<String?>? pendingDownloadPath}) {
    return SongsTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      durationMs: durationMs ?? this.durationMs,
      path: path ?? this.path,
      uri: uri ?? this.uri,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      dateAdded: dateAdded ?? this.dateAdded,
      genre: genre ?? this.genre,
      isFavorite: isFavorite ?? this.isFavorite,
      isMissing: isMissing ?? this.isMissing,
      replayGain: replayGain ?? this.replayGain,
      playCount: playCount ?? this.playCount,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      artworkUri: artworkUri ?? this.artworkUri,
      fileSize: fileSize ?? this.fileSize,
      source: source ?? this.source,
      remoteId: remoteId ?? this.remoteId,
      remoteArtworkUrl: remoteArtworkUrl ?? this.remoteArtworkUrl,
      pendingDownloadPath: pendingDownloadPath ?? this.pendingDownloadPath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<int>(artistId.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<int>(albumId.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<int>(dateAdded.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (isMissing.present) {
      map['is_missing'] = Variable<bool>(isMissing.value);
    }
    if (replayGain.present) {
      map['replay_gain'] = Variable<double>(replayGain.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (lastPlayed.present) {
      map['last_played'] = Variable<int>(lastPlayed.value);
    }
    if (lastPositionMs.present) {
      map['last_position_ms'] = Variable<int>(lastPositionMs.value);
    }
    if (artworkUri.present) {
      map['artwork_uri'] = Variable<String>(artworkUri.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (remoteArtworkUrl.present) {
      map['remote_artwork_url'] = Variable<String>(remoteArtworkUrl.value);
    }
    if (pendingDownloadPath.present) {
      map['pending_download_path'] =
          Variable<String>(pendingDownloadPath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('durationMs: $durationMs, ')
          ..write('path: $path, ')
          ..write('uri: $uri, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('genre: $genre, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isMissing: $isMissing, ')
          ..write('replayGain: $replayGain, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('lastPositionMs: $lastPositionMs, ')
          ..write('artworkUri: $artworkUri, ')
          ..write('fileSize: $fileSize, ')
          ..write('source: $source, ')
          ..write('remoteId: $remoteId, ')
          ..write('remoteArtworkUrl: $remoteArtworkUrl, ')
          ..write('pendingDownloadPath: $pendingDownloadPath')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTableTable extends AlbumsTable
    with TableInfo<$AlbumsTableTable, AlbumsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
      'artist', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown Artist'));
  static const VerificationMeta _artistIdMeta =
      const VerificationMeta('artistId');
  @override
  late final GeneratedColumn<int> artistId = GeneratedColumn<int>(
      'artist_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _songCountMeta =
      const VerificationMeta('songCount');
  @override
  late final GeneratedColumn<int> songCount = GeneratedColumn<int>(
      'song_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _artworkUriMeta =
      const VerificationMeta('artworkUri');
  @override
  late final GeneratedColumn<String> artworkUri = GeneratedColumn<String>(
      'artwork_uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, artist, artistId, songCount, artworkUri, year];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(Insertable<AlbumsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(_artistMeta,
          artist.isAcceptableOrUnknown(data['artist']!, _artistMeta));
    }
    if (data.containsKey('artist_id')) {
      context.handle(_artistIdMeta,
          artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta));
    }
    if (data.containsKey('song_count')) {
      context.handle(_songCountMeta,
          songCount.isAcceptableOrUnknown(data['song_count']!, _songCountMeta));
    }
    if (data.containsKey('artwork_uri')) {
      context.handle(
          _artworkUriMeta,
          artworkUri.isAcceptableOrUnknown(
              data['artwork_uri']!, _artworkUriMeta));
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlbumsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      artist: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist'])!,
      artistId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}artist_id']),
      songCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}song_count'])!,
      artworkUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artwork_uri']),
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year']),
    );
  }

  @override
  $AlbumsTableTable createAlias(String alias) {
    return $AlbumsTableTable(attachedDatabase, alias);
  }
}

class AlbumsTableData extends DataClass implements Insertable<AlbumsTableData> {
  final int id;
  final String title;
  final String artist;
  final int? artistId;
  final int songCount;
  final String? artworkUri;
  final int? year;
  const AlbumsTableData(
      {required this.id,
      required this.title,
      required this.artist,
      this.artistId,
      required this.songCount,
      this.artworkUri,
      this.year});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<int>(artistId);
    }
    map['song_count'] = Variable<int>(songCount);
    if (!nullToAbsent || artworkUri != null) {
      map['artwork_uri'] = Variable<String>(artworkUri);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    return map;
  }

  AlbumsTableCompanion toCompanion(bool nullToAbsent) {
    return AlbumsTableCompanion(
      id: Value(id),
      title: Value(title),
      artist: Value(artist),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      songCount: Value(songCount),
      artworkUri: artworkUri == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUri),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
    );
  }

  factory AlbumsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumsTableData(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      artistId: serializer.fromJson<int?>(json['artistId']),
      songCount: serializer.fromJson<int>(json['songCount']),
      artworkUri: serializer.fromJson<String?>(json['artworkUri']),
      year: serializer.fromJson<int?>(json['year']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'artistId': serializer.toJson<int?>(artistId),
      'songCount': serializer.toJson<int>(songCount),
      'artworkUri': serializer.toJson<String?>(artworkUri),
      'year': serializer.toJson<int?>(year),
    };
  }

  AlbumsTableData copyWith(
          {int? id,
          String? title,
          String? artist,
          Value<int?> artistId = const Value.absent(),
          int? songCount,
          Value<String?> artworkUri = const Value.absent(),
          Value<int?> year = const Value.absent()}) =>
      AlbumsTableData(
        id: id ?? this.id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artistId: artistId.present ? artistId.value : this.artistId,
        songCount: songCount ?? this.songCount,
        artworkUri: artworkUri.present ? artworkUri.value : this.artworkUri,
        year: year.present ? year.value : this.year,
      );
  AlbumsTableData copyWithCompanion(AlbumsTableCompanion data) {
    return AlbumsTableData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      songCount: data.songCount.present ? data.songCount.value : this.songCount,
      artworkUri:
          data.artworkUri.present ? data.artworkUri.value : this.artworkUri,
      year: data.year.present ? data.year.value : this.year,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsTableData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('songCount: $songCount, ')
          ..write('artworkUri: $artworkUri, ')
          ..write('year: $year')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, artist, artistId, songCount, artworkUri, year);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumsTableData &&
          other.id == this.id &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.artistId == this.artistId &&
          other.songCount == this.songCount &&
          other.artworkUri == this.artworkUri &&
          other.year == this.year);
}

class AlbumsTableCompanion extends UpdateCompanion<AlbumsTableData> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> artist;
  final Value<int?> artistId;
  final Value<int> songCount;
  final Value<String?> artworkUri;
  final Value<int?> year;
  const AlbumsTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.songCount = const Value.absent(),
    this.artworkUri = const Value.absent(),
    this.year = const Value.absent(),
  });
  AlbumsTableCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.artist = const Value.absent(),
    this.artistId = const Value.absent(),
    this.songCount = const Value.absent(),
    this.artworkUri = const Value.absent(),
    this.year = const Value.absent(),
  }) : title = Value(title);
  static Insertable<AlbumsTableData> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<int>? artistId,
    Expression<int>? songCount,
    Expression<String>? artworkUri,
    Expression<int>? year,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (songCount != null) 'song_count': songCount,
      if (artworkUri != null) 'artwork_uri': artworkUri,
      if (year != null) 'year': year,
    });
  }

  AlbumsTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? title,
      Value<String>? artist,
      Value<int?>? artistId,
      Value<int>? songCount,
      Value<String?>? artworkUri,
      Value<int?>? year}) {
    return AlbumsTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      songCount: songCount ?? this.songCount,
      artworkUri: artworkUri ?? this.artworkUri,
      year: year ?? this.year,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<int>(artistId.value);
    }
    if (songCount.present) {
      map['song_count'] = Variable<int>(songCount.value);
    }
    if (artworkUri.present) {
      map['artwork_uri'] = Variable<String>(artworkUri.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistId: $artistId, ')
          ..write('songCount: $songCount, ')
          ..write('artworkUri: $artworkUri, ')
          ..write('year: $year')
          ..write(')'))
        .toString();
  }
}

class $ArtistsTableTable extends ArtistsTable
    with TableInfo<$ArtistsTableTable, ArtistsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtistsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _songCountMeta =
      const VerificationMeta('songCount');
  @override
  late final GeneratedColumn<int> songCount = GeneratedColumn<int>(
      'song_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _albumCountMeta =
      const VerificationMeta('albumCount');
  @override
  late final GeneratedColumn<int> albumCount = GeneratedColumn<int>(
      'album_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _artworkUriMeta =
      const VerificationMeta('artworkUri');
  @override
  late final GeneratedColumn<String> artworkUri = GeneratedColumn<String>(
      'artwork_uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, songCount, albumCount, artworkUri];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artists';
  @override
  VerificationContext validateIntegrity(Insertable<ArtistsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('song_count')) {
      context.handle(_songCountMeta,
          songCount.isAcceptableOrUnknown(data['song_count']!, _songCountMeta));
    }
    if (data.containsKey('album_count')) {
      context.handle(
          _albumCountMeta,
          albumCount.isAcceptableOrUnknown(
              data['album_count']!, _albumCountMeta));
    }
    if (data.containsKey('artwork_uri')) {
      context.handle(
          _artworkUriMeta,
          artworkUri.isAcceptableOrUnknown(
              data['artwork_uri']!, _artworkUriMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArtistsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArtistsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      songCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}song_count'])!,
      albumCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}album_count'])!,
      artworkUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artwork_uri']),
    );
  }

  @override
  $ArtistsTableTable createAlias(String alias) {
    return $ArtistsTableTable(attachedDatabase, alias);
  }
}

class ArtistsTableData extends DataClass
    implements Insertable<ArtistsTableData> {
  final int id;
  final String name;
  final int songCount;
  final int albumCount;
  final String? artworkUri;
  const ArtistsTableData(
      {required this.id,
      required this.name,
      required this.songCount,
      required this.albumCount,
      this.artworkUri});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['song_count'] = Variable<int>(songCount);
    map['album_count'] = Variable<int>(albumCount);
    if (!nullToAbsent || artworkUri != null) {
      map['artwork_uri'] = Variable<String>(artworkUri);
    }
    return map;
  }

  ArtistsTableCompanion toCompanion(bool nullToAbsent) {
    return ArtistsTableCompanion(
      id: Value(id),
      name: Value(name),
      songCount: Value(songCount),
      albumCount: Value(albumCount),
      artworkUri: artworkUri == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUri),
    );
  }

  factory ArtistsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArtistsTableData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      songCount: serializer.fromJson<int>(json['songCount']),
      albumCount: serializer.fromJson<int>(json['albumCount']),
      artworkUri: serializer.fromJson<String?>(json['artworkUri']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'songCount': serializer.toJson<int>(songCount),
      'albumCount': serializer.toJson<int>(albumCount),
      'artworkUri': serializer.toJson<String?>(artworkUri),
    };
  }

  ArtistsTableData copyWith(
          {int? id,
          String? name,
          int? songCount,
          int? albumCount,
          Value<String?> artworkUri = const Value.absent()}) =>
      ArtistsTableData(
        id: id ?? this.id,
        name: name ?? this.name,
        songCount: songCount ?? this.songCount,
        albumCount: albumCount ?? this.albumCount,
        artworkUri: artworkUri.present ? artworkUri.value : this.artworkUri,
      );
  ArtistsTableData copyWithCompanion(ArtistsTableCompanion data) {
    return ArtistsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      songCount: data.songCount.present ? data.songCount.value : this.songCount,
      albumCount:
          data.albumCount.present ? data.albumCount.value : this.albumCount,
      artworkUri:
          data.artworkUri.present ? data.artworkUri.value : this.artworkUri,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('songCount: $songCount, ')
          ..write('albumCount: $albumCount, ')
          ..write('artworkUri: $artworkUri')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, songCount, albumCount, artworkUri);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArtistsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.songCount == this.songCount &&
          other.albumCount == this.albumCount &&
          other.artworkUri == this.artworkUri);
}

class ArtistsTableCompanion extends UpdateCompanion<ArtistsTableData> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> songCount;
  final Value<int> albumCount;
  final Value<String?> artworkUri;
  const ArtistsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.songCount = const Value.absent(),
    this.albumCount = const Value.absent(),
    this.artworkUri = const Value.absent(),
  });
  ArtistsTableCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.songCount = const Value.absent(),
    this.albumCount = const Value.absent(),
    this.artworkUri = const Value.absent(),
  }) : name = Value(name);
  static Insertable<ArtistsTableData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? songCount,
    Expression<int>? albumCount,
    Expression<String>? artworkUri,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (songCount != null) 'song_count': songCount,
      if (albumCount != null) 'album_count': albumCount,
      if (artworkUri != null) 'artwork_uri': artworkUri,
    });
  }

  ArtistsTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<int>? songCount,
      Value<int>? albumCount,
      Value<String?>? artworkUri}) {
    return ArtistsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      songCount: songCount ?? this.songCount,
      albumCount: albumCount ?? this.albumCount,
      artworkUri: artworkUri ?? this.artworkUri,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (songCount.present) {
      map['song_count'] = Variable<int>(songCount.value);
    }
    if (albumCount.present) {
      map['album_count'] = Variable<int>(albumCount.value);
    }
    if (artworkUri.present) {
      map['artwork_uri'] = Variable<String>(artworkUri.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('songCount: $songCount, ')
          ..write('albumCount: $albumCount, ')
          ..write('artworkUri: $artworkUri')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTableTable extends PlaylistsTable
    with TableInfo<$PlaylistsTableTable, PlaylistsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isSmartMeta =
      const VerificationMeta('isSmart');
  @override
  late final GeneratedColumn<bool> isSmart = GeneratedColumn<bool>(
      'is_smart', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_smart" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _smartCriteriaMeta =
      const VerificationMeta('smartCriteria');
  @override
  late final GeneratedColumn<String> smartCriteria = GeneratedColumn<String>(
      'smart_criteria', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, createdAt, updatedAt, isSmart, smartCriteria];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(Insertable<PlaylistsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('is_smart')) {
      context.handle(_isSmartMeta,
          isSmart.isAcceptableOrUnknown(data['is_smart']!, _isSmartMeta));
    }
    if (data.containsKey('smart_criteria')) {
      context.handle(
          _smartCriteriaMeta,
          smartCriteria.isAcceptableOrUnknown(
              data['smart_criteria']!, _smartCriteriaMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      isSmart: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_smart'])!,
      smartCriteria: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}smart_criteria']),
    );
  }

  @override
  $PlaylistsTableTable createAlias(String alias) {
    return $PlaylistsTableTable(attachedDatabase, alias);
  }
}

class PlaylistsTableData extends DataClass
    implements Insertable<PlaylistsTableData> {
  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSmart;
  final String? smartCriteria;
  const PlaylistsTableData(
      {required this.id,
      required this.name,
      required this.createdAt,
      required this.updatedAt,
      required this.isSmart,
      this.smartCriteria});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_smart'] = Variable<bool>(isSmart);
    if (!nullToAbsent || smartCriteria != null) {
      map['smart_criteria'] = Variable<String>(smartCriteria);
    }
    return map;
  }

  PlaylistsTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsTableCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isSmart: Value(isSmart),
      smartCriteria: smartCriteria == null && nullToAbsent
          ? const Value.absent()
          : Value(smartCriteria),
    );
  }

  factory PlaylistsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistsTableData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isSmart: serializer.fromJson<bool>(json['isSmart']),
      smartCriteria: serializer.fromJson<String?>(json['smartCriteria']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isSmart': serializer.toJson<bool>(isSmart),
      'smartCriteria': serializer.toJson<String?>(smartCriteria),
    };
  }

  PlaylistsTableData copyWith(
          {int? id,
          String? name,
          DateTime? createdAt,
          DateTime? updatedAt,
          bool? isSmart,
          Value<String?> smartCriteria = const Value.absent()}) =>
      PlaylistsTableData(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isSmart: isSmart ?? this.isSmart,
        smartCriteria:
            smartCriteria.present ? smartCriteria.value : this.smartCriteria,
      );
  PlaylistsTableData copyWithCompanion(PlaylistsTableCompanion data) {
    return PlaylistsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isSmart: data.isSmart.present ? data.isSmart.value : this.isSmart,
      smartCriteria: data.smartCriteria.present
          ? data.smartCriteria.value
          : this.smartCriteria,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isSmart: $isSmart, ')
          ..write('smartCriteria: $smartCriteria')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, createdAt, updatedAt, isSmart, smartCriteria);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isSmart == this.isSmart &&
          other.smartCriteria == this.smartCriteria);
}

class PlaylistsTableCompanion extends UpdateCompanion<PlaylistsTableData> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isSmart;
  final Value<String?> smartCriteria;
  const PlaylistsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isSmart = const Value.absent(),
    this.smartCriteria = const Value.absent(),
  });
  PlaylistsTableCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isSmart = const Value.absent(),
    this.smartCriteria = const Value.absent(),
  }) : name = Value(name);
  static Insertable<PlaylistsTableData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isSmart,
    Expression<String>? smartCriteria,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isSmart != null) 'is_smart': isSmart,
      if (smartCriteria != null) 'smart_criteria': smartCriteria,
    });
  }

  PlaylistsTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<bool>? isSmart,
      Value<String?>? smartCriteria}) {
    return PlaylistsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSmart: isSmart ?? this.isSmart,
      smartCriteria: smartCriteria ?? this.smartCriteria,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isSmart.present) {
      map['is_smart'] = Variable<bool>(isSmart.value);
    }
    if (smartCriteria.present) {
      map['smart_criteria'] = Variable<String>(smartCriteria.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isSmart: $isSmart, ')
          ..write('smartCriteria: $smartCriteria')
          ..write(')'))
        .toString();
  }
}

class $PlaylistEntriesTableTable extends PlaylistEntriesTable
    with TableInfo<$PlaylistEntriesTableTable, PlaylistEntriesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistEntriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _playlistIdMeta =
      const VerificationMeta('playlistId');
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
      'playlist_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<int> songId = GeneratedColumn<int>(
      'song_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _orderIndexMeta =
      const VerificationMeta('orderIndex');
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
      'order_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, playlistId, songId, orderIndex, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_entries';
  @override
  VerificationContext validateIntegrity(
      Insertable<PlaylistEntriesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
          _playlistIdMeta,
          playlistId.isAcceptableOrUnknown(
              data['playlist_id']!, _playlistIdMeta));
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(_songIdMeta,
          songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta));
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
          _orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(
              data['order_index']!, _orderIndexMeta));
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistEntriesTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistEntriesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      playlistId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}playlist_id'])!,
      songId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}song_id'])!,
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $PlaylistEntriesTableTable createAlias(String alias) {
    return $PlaylistEntriesTableTable(attachedDatabase, alias);
  }
}

class PlaylistEntriesTableData extends DataClass
    implements Insertable<PlaylistEntriesTableData> {
  final int id;
  final int playlistId;
  final int songId;
  final int orderIndex;
  final DateTime addedAt;
  const PlaylistEntriesTableData(
      {required this.id,
      required this.playlistId,
      required this.songId,
      required this.orderIndex,
      required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<int>(playlistId);
    map['song_id'] = Variable<int>(songId);
    map['order_index'] = Variable<int>(orderIndex);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  PlaylistEntriesTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistEntriesTableCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      songId: Value(songId),
      orderIndex: Value(orderIndex),
      addedAt: Value(addedAt),
    );
  }

  factory PlaylistEntriesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistEntriesTableData(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<int>(json['playlistId']),
      songId: serializer.fromJson<int>(json['songId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<int>(playlistId),
      'songId': serializer.toJson<int>(songId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  PlaylistEntriesTableData copyWith(
          {int? id,
          int? playlistId,
          int? songId,
          int? orderIndex,
          DateTime? addedAt}) =>
      PlaylistEntriesTableData(
        id: id ?? this.id,
        playlistId: playlistId ?? this.playlistId,
        songId: songId ?? this.songId,
        orderIndex: orderIndex ?? this.orderIndex,
        addedAt: addedAt ?? this.addedAt,
      );
  PlaylistEntriesTableData copyWithCompanion(
      PlaylistEntriesTableCompanion data) {
    return PlaylistEntriesTableData(
      id: data.id.present ? data.id.value : this.id,
      playlistId:
          data.playlistId.present ? data.playlistId.value : this.playlistId,
      songId: data.songId.present ? data.songId.value : this.songId,
      orderIndex:
          data.orderIndex.present ? data.orderIndex.value : this.orderIndex,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntriesTableData(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('songId: $songId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playlistId, songId, orderIndex, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistEntriesTableData &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.songId == this.songId &&
          other.orderIndex == this.orderIndex &&
          other.addedAt == this.addedAt);
}

class PlaylistEntriesTableCompanion
    extends UpdateCompanion<PlaylistEntriesTableData> {
  final Value<int> id;
  final Value<int> playlistId;
  final Value<int> songId;
  final Value<int> orderIndex;
  final Value<DateTime> addedAt;
  const PlaylistEntriesTableCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.songId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  PlaylistEntriesTableCompanion.insert({
    this.id = const Value.absent(),
    required int playlistId,
    required int songId,
    required int orderIndex,
    this.addedAt = const Value.absent(),
  })  : playlistId = Value(playlistId),
        songId = Value(songId),
        orderIndex = Value(orderIndex);
  static Insertable<PlaylistEntriesTableData> custom({
    Expression<int>? id,
    Expression<int>? playlistId,
    Expression<int>? songId,
    Expression<int>? orderIndex,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (songId != null) 'song_id': songId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  PlaylistEntriesTableCompanion copyWith(
      {Value<int>? id,
      Value<int>? playlistId,
      Value<int>? songId,
      Value<int>? orderIndex,
      Value<DateTime>? addedAt}) {
    return PlaylistEntriesTableCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      songId: songId ?? this.songId,
      orderIndex: orderIndex ?? this.orderIndex,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<int>(songId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntriesTableCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('songId: $songId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $PlayHistoryTableTable extends PlayHistoryTable
    with TableInfo<$PlayHistoryTableTable, PlayHistoryTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayHistoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<int> songId = GeneratedColumn<int>(
      'song_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _playedAtMeta =
      const VerificationMeta('playedAt');
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
      'played_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
      'completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [id, songId, playedAt, completed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<PlayHistoryTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(_songIdMeta,
          songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta));
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('played_at')) {
      context.handle(_playedAtMeta,
          playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayHistoryTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayHistoryTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      songId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}song_id'])!,
      playedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}played_at'])!,
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completed'])!,
    );
  }

  @override
  $PlayHistoryTableTable createAlias(String alias) {
    return $PlayHistoryTableTable(attachedDatabase, alias);
  }
}

class PlayHistoryTableData extends DataClass
    implements Insertable<PlayHistoryTableData> {
  final int id;
  final int songId;
  final DateTime playedAt;
  final bool completed;
  const PlayHistoryTableData(
      {required this.id,
      required this.songId,
      required this.playedAt,
      required this.completed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<int>(songId);
    map['played_at'] = Variable<DateTime>(playedAt);
    map['completed'] = Variable<bool>(completed);
    return map;
  }

  PlayHistoryTableCompanion toCompanion(bool nullToAbsent) {
    return PlayHistoryTableCompanion(
      id: Value(id),
      songId: Value(songId),
      playedAt: Value(playedAt),
      completed: Value(completed),
    );
  }

  factory PlayHistoryTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayHistoryTableData(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<int>(json['songId']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
      completed: serializer.fromJson<bool>(json['completed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<int>(songId),
      'playedAt': serializer.toJson<DateTime>(playedAt),
      'completed': serializer.toJson<bool>(completed),
    };
  }

  PlayHistoryTableData copyWith(
          {int? id, int? songId, DateTime? playedAt, bool? completed}) =>
      PlayHistoryTableData(
        id: id ?? this.id,
        songId: songId ?? this.songId,
        playedAt: playedAt ?? this.playedAt,
        completed: completed ?? this.completed,
      );
  PlayHistoryTableData copyWithCompanion(PlayHistoryTableCompanion data) {
    return PlayHistoryTableData(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
      completed: data.completed.present ? data.completed.value : this.completed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryTableData(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('playedAt: $playedAt, ')
          ..write('completed: $completed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, songId, playedAt, completed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayHistoryTableData &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.playedAt == this.playedAt &&
          other.completed == this.completed);
}

class PlayHistoryTableCompanion extends UpdateCompanion<PlayHistoryTableData> {
  final Value<int> id;
  final Value<int> songId;
  final Value<DateTime> playedAt;
  final Value<bool> completed;
  const PlayHistoryTableCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.playedAt = const Value.absent(),
    this.completed = const Value.absent(),
  });
  PlayHistoryTableCompanion.insert({
    this.id = const Value.absent(),
    required int songId,
    this.playedAt = const Value.absent(),
    this.completed = const Value.absent(),
  }) : songId = Value(songId);
  static Insertable<PlayHistoryTableData> custom({
    Expression<int>? id,
    Expression<int>? songId,
    Expression<DateTime>? playedAt,
    Expression<bool>? completed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (playedAt != null) 'played_at': playedAt,
      if (completed != null) 'completed': completed,
    });
  }

  PlayHistoryTableCompanion copyWith(
      {Value<int>? id,
      Value<int>? songId,
      Value<DateTime>? playedAt,
      Value<bool>? completed}) {
    return PlayHistoryTableCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      playedAt: playedAt ?? this.playedAt,
      completed: completed ?? this.completed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<int>(songId.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryTableCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('playedAt: $playedAt, ')
          ..write('completed: $completed')
          ..write(')'))
        .toString();
  }
}

class $QueueItemsTableTable extends QueueItemsTable
    with TableInfo<$QueueItemsTableTable, QueueItemsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueItemsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<int> songId = GeneratedColumn<int>(
      'song_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _orderIndexMeta =
      const VerificationMeta('orderIndex');
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
      'order_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _isCurrentMeta =
      const VerificationMeta('isCurrent');
  @override
  late final GeneratedColumn<bool> isCurrent = GeneratedColumn<bool>(
      'is_current', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_current" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, songId, orderIndex, isCurrent, positionMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_items';
  @override
  VerificationContext validateIntegrity(
      Insertable<QueueItemsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(_songIdMeta,
          songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta));
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
          _orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(
              data['order_index']!, _orderIndexMeta));
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('is_current')) {
      context.handle(_isCurrentMeta,
          isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta));
    }
    if (data.containsKey('position_ms')) {
      context.handle(
          _positionMsMeta,
          positionMs.isAcceptableOrUnknown(
              data['position_ms']!, _positionMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueItemsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueItemsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      songId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}song_id'])!,
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
      isCurrent: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_current'])!,
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
    );
  }

  @override
  $QueueItemsTableTable createAlias(String alias) {
    return $QueueItemsTableTable(attachedDatabase, alias);
  }
}

class QueueItemsTableData extends DataClass
    implements Insertable<QueueItemsTableData> {
  final int id;
  final int songId;
  final int orderIndex;
  final bool isCurrent;
  final int positionMs;
  const QueueItemsTableData(
      {required this.id,
      required this.songId,
      required this.orderIndex,
      required this.isCurrent,
      required this.positionMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<int>(songId);
    map['order_index'] = Variable<int>(orderIndex);
    map['is_current'] = Variable<bool>(isCurrent);
    map['position_ms'] = Variable<int>(positionMs);
    return map;
  }

  QueueItemsTableCompanion toCompanion(bool nullToAbsent) {
    return QueueItemsTableCompanion(
      id: Value(id),
      songId: Value(songId),
      orderIndex: Value(orderIndex),
      isCurrent: Value(isCurrent),
      positionMs: Value(positionMs),
    );
  }

  factory QueueItemsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueItemsTableData(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<int>(json['songId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      isCurrent: serializer.fromJson<bool>(json['isCurrent']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<int>(songId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'isCurrent': serializer.toJson<bool>(isCurrent),
      'positionMs': serializer.toJson<int>(positionMs),
    };
  }

  QueueItemsTableData copyWith(
          {int? id,
          int? songId,
          int? orderIndex,
          bool? isCurrent,
          int? positionMs}) =>
      QueueItemsTableData(
        id: id ?? this.id,
        songId: songId ?? this.songId,
        orderIndex: orderIndex ?? this.orderIndex,
        isCurrent: isCurrent ?? this.isCurrent,
        positionMs: positionMs ?? this.positionMs,
      );
  QueueItemsTableData copyWithCompanion(QueueItemsTableCompanion data) {
    return QueueItemsTableData(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      orderIndex:
          data.orderIndex.present ? data.orderIndex.value : this.orderIndex,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
      positionMs:
          data.positionMs.present ? data.positionMs.value : this.positionMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueItemsTableData(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('positionMs: $positionMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, songId, orderIndex, isCurrent, positionMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueItemsTableData &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.orderIndex == this.orderIndex &&
          other.isCurrent == this.isCurrent &&
          other.positionMs == this.positionMs);
}

class QueueItemsTableCompanion extends UpdateCompanion<QueueItemsTableData> {
  final Value<int> id;
  final Value<int> songId;
  final Value<int> orderIndex;
  final Value<bool> isCurrent;
  final Value<int> positionMs;
  const QueueItemsTableCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.positionMs = const Value.absent(),
  });
  QueueItemsTableCompanion.insert({
    this.id = const Value.absent(),
    required int songId,
    required int orderIndex,
    this.isCurrent = const Value.absent(),
    this.positionMs = const Value.absent(),
  })  : songId = Value(songId),
        orderIndex = Value(orderIndex);
  static Insertable<QueueItemsTableData> custom({
    Expression<int>? id,
    Expression<int>? songId,
    Expression<int>? orderIndex,
    Expression<bool>? isCurrent,
    Expression<int>? positionMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (isCurrent != null) 'is_current': isCurrent,
      if (positionMs != null) 'position_ms': positionMs,
    });
  }

  QueueItemsTableCompanion copyWith(
      {Value<int>? id,
      Value<int>? songId,
      Value<int>? orderIndex,
      Value<bool>? isCurrent,
      Value<int>? positionMs}) {
    return QueueItemsTableCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      orderIndex: orderIndex ?? this.orderIndex,
      isCurrent: isCurrent ?? this.isCurrent,
      positionMs: positionMs ?? this.positionMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<int>(songId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<bool>(isCurrent.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueItemsTableCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('positionMs: $positionMs')
          ..write(')'))
        .toString();
  }
}

class $ExcludedFoldersTableTable extends ExcludedFoldersTable
    with TableInfo<$ExcludedFoldersTableTable, ExcludedFoldersTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExcludedFoldersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _folderPathMeta =
      const VerificationMeta('folderPath');
  @override
  late final GeneratedColumn<String> folderPath = GeneratedColumn<String>(
      'folder_path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, folderPath, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'excluded_folders';
  @override
  VerificationContext validateIntegrity(
      Insertable<ExcludedFoldersTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('folder_path')) {
      context.handle(
          _folderPathMeta,
          folderPath.isAcceptableOrUnknown(
              data['folder_path']!, _folderPathMeta));
    } else if (isInserting) {
      context.missing(_folderPathMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExcludedFoldersTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExcludedFoldersTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      folderPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}folder_path'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $ExcludedFoldersTableTable createAlias(String alias) {
    return $ExcludedFoldersTableTable(attachedDatabase, alias);
  }
}

class ExcludedFoldersTableData extends DataClass
    implements Insertable<ExcludedFoldersTableData> {
  final int id;
  final String folderPath;
  final DateTime addedAt;
  const ExcludedFoldersTableData(
      {required this.id, required this.folderPath, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['folder_path'] = Variable<String>(folderPath);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  ExcludedFoldersTableCompanion toCompanion(bool nullToAbsent) {
    return ExcludedFoldersTableCompanion(
      id: Value(id),
      folderPath: Value(folderPath),
      addedAt: Value(addedAt),
    );
  }

  factory ExcludedFoldersTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExcludedFoldersTableData(
      id: serializer.fromJson<int>(json['id']),
      folderPath: serializer.fromJson<String>(json['folderPath']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'folderPath': serializer.toJson<String>(folderPath),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  ExcludedFoldersTableData copyWith(
          {int? id, String? folderPath, DateTime? addedAt}) =>
      ExcludedFoldersTableData(
        id: id ?? this.id,
        folderPath: folderPath ?? this.folderPath,
        addedAt: addedAt ?? this.addedAt,
      );
  ExcludedFoldersTableData copyWithCompanion(
      ExcludedFoldersTableCompanion data) {
    return ExcludedFoldersTableData(
      id: data.id.present ? data.id.value : this.id,
      folderPath:
          data.folderPath.present ? data.folderPath.value : this.folderPath,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExcludedFoldersTableData(')
          ..write('id: $id, ')
          ..write('folderPath: $folderPath, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, folderPath, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExcludedFoldersTableData &&
          other.id == this.id &&
          other.folderPath == this.folderPath &&
          other.addedAt == this.addedAt);
}

class ExcludedFoldersTableCompanion
    extends UpdateCompanion<ExcludedFoldersTableData> {
  final Value<int> id;
  final Value<String> folderPath;
  final Value<DateTime> addedAt;
  const ExcludedFoldersTableCompanion({
    this.id = const Value.absent(),
    this.folderPath = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  ExcludedFoldersTableCompanion.insert({
    this.id = const Value.absent(),
    required String folderPath,
    this.addedAt = const Value.absent(),
  }) : folderPath = Value(folderPath);
  static Insertable<ExcludedFoldersTableData> custom({
    Expression<int>? id,
    Expression<String>? folderPath,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (folderPath != null) 'folder_path': folderPath,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  ExcludedFoldersTableCompanion copyWith(
      {Value<int>? id, Value<String>? folderPath, Value<DateTime>? addedAt}) {
    return ExcludedFoldersTableCompanion(
      id: id ?? this.id,
      folderPath: folderPath ?? this.folderPath,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (folderPath.present) {
      map['folder_path'] = Variable<String>(folderPath.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExcludedFoldersTableCompanion(')
          ..write('id: $id, ')
          ..write('folderPath: $folderPath, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SongsTableTable songsTable = $SongsTableTable(this);
  late final $AlbumsTableTable albumsTable = $AlbumsTableTable(this);
  late final $ArtistsTableTable artistsTable = $ArtistsTableTable(this);
  late final $PlaylistsTableTable playlistsTable = $PlaylistsTableTable(this);
  late final $PlaylistEntriesTableTable playlistEntriesTable =
      $PlaylistEntriesTableTable(this);
  late final $PlayHistoryTableTable playHistoryTable =
      $PlayHistoryTableTable(this);
  late final $QueueItemsTableTable queueItemsTable =
      $QueueItemsTableTable(this);
  late final $ExcludedFoldersTableTable excludedFoldersTable =
      $ExcludedFoldersTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        songsTable,
        albumsTable,
        artistsTable,
        playlistsTable,
        playlistEntriesTable,
        playHistoryTable,
        queueItemsTable,
        excludedFoldersTable
      ];
}

typedef $$SongsTableTableCreateCompanionBuilder = SongsTableCompanion Function({
  Value<int> id,
  required String title,
  Value<String> artist,
  Value<int?> artistId,
  Value<String> album,
  Value<int?> albumId,
  Value<int> durationMs,
  required String path,
  Value<String?> uri,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> year,
  Value<int?> dateAdded,
  Value<String?> genre,
  Value<bool> isFavorite,
  Value<bool> isMissing,
  Value<double?> replayGain,
  Value<int> playCount,
  Value<int?> lastPlayed,
  Value<int> lastPositionMs,
  Value<String?> artworkUri,
  Value<int?> fileSize,
  Value<String> source,
  Value<String?> remoteId,
  Value<String?> remoteArtworkUrl,
  Value<String?> pendingDownloadPath,
});
typedef $$SongsTableTableUpdateCompanionBuilder = SongsTableCompanion Function({
  Value<int> id,
  Value<String> title,
  Value<String> artist,
  Value<int?> artistId,
  Value<String> album,
  Value<int?> albumId,
  Value<int> durationMs,
  Value<String> path,
  Value<String?> uri,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int?> year,
  Value<int?> dateAdded,
  Value<String?> genre,
  Value<bool> isFavorite,
  Value<bool> isMissing,
  Value<double?> replayGain,
  Value<int> playCount,
  Value<int?> lastPlayed,
  Value<int> lastPositionMs,
  Value<String?> artworkUri,
  Value<int?> fileSize,
  Value<String> source,
  Value<String?> remoteId,
  Value<String?> remoteArtworkUrl,
  Value<String?> pendingDownloadPath,
});

class $$SongsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SongsTableTable> {
  $$SongsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get album => $composableBuilder(
      column: $table.album, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get albumId => $composableBuilder(
      column: $table.albumId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uri => $composableBuilder(
      column: $table.uri, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dateAdded => $composableBuilder(
      column: $table.dateAdded, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isMissing => $composableBuilder(
      column: $table.isMissing, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get replayGain => $composableBuilder(
      column: $table.replayGain, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPlayed => $composableBuilder(
      column: $table.lastPlayed, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSize => $composableBuilder(
      column: $table.fileSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remoteId => $composableBuilder(
      column: $table.remoteId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remoteArtworkUrl => $composableBuilder(
      column: $table.remoteArtworkUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pendingDownloadPath => $composableBuilder(
      column: $table.pendingDownloadPath,
      builder: (column) => ColumnFilters(column));
}

class $$SongsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SongsTableTable> {
  $$SongsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get album => $composableBuilder(
      column: $table.album, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get albumId => $composableBuilder(
      column: $table.albumId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uri => $composableBuilder(
      column: $table.uri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dateAdded => $composableBuilder(
      column: $table.dateAdded, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get genre => $composableBuilder(
      column: $table.genre, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isMissing => $composableBuilder(
      column: $table.isMissing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get replayGain => $composableBuilder(
      column: $table.replayGain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPlayed => $composableBuilder(
      column: $table.lastPlayed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSize => $composableBuilder(
      column: $table.fileSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remoteId => $composableBuilder(
      column: $table.remoteId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remoteArtworkUrl => $composableBuilder(
      column: $table.remoteArtworkUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pendingDownloadPath => $composableBuilder(
      column: $table.pendingDownloadPath,
      builder: (column) => ColumnOrderings(column));
}

class $$SongsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongsTableTable> {
  $$SongsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<int> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<int> get trackNumber => $composableBuilder(
      column: $table.trackNumber, builder: (column) => column);

  GeneratedColumn<int> get discNumber => $composableBuilder(
      column: $table.discNumber, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => column);

  GeneratedColumn<bool> get isMissing =>
      $composableBuilder(column: $table.isMissing, builder: (column) => column);

  GeneratedColumn<double> get replayGain => $composableBuilder(
      column: $table.replayGain, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get lastPlayed => $composableBuilder(
      column: $table.lastPlayed, builder: (column) => column);

  GeneratedColumn<int> get lastPositionMs => $composableBuilder(
      column: $table.lastPositionMs, builder: (column) => column);

  GeneratedColumn<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get remoteArtworkUrl => $composableBuilder(
      column: $table.remoteArtworkUrl, builder: (column) => column);

  GeneratedColumn<String> get pendingDownloadPath => $composableBuilder(
      column: $table.pendingDownloadPath, builder: (column) => column);
}

class $$SongsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SongsTableTable,
    SongsTableData,
    $$SongsTableTableFilterComposer,
    $$SongsTableTableOrderingComposer,
    $$SongsTableTableAnnotationComposer,
    $$SongsTableTableCreateCompanionBuilder,
    $$SongsTableTableUpdateCompanionBuilder,
    (
      SongsTableData,
      BaseReferences<_$AppDatabase, $SongsTableTable, SongsTableData>
    ),
    SongsTableData,
    PrefetchHooks Function()> {
  $$SongsTableTableTableManager(_$AppDatabase db, $SongsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> artist = const Value.absent(),
            Value<int?> artistId = const Value.absent(),
            Value<String> album = const Value.absent(),
            Value<int?> albumId = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            Value<String> path = const Value.absent(),
            Value<String?> uri = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<int?> dateAdded = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<bool> isMissing = const Value.absent(),
            Value<double?> replayGain = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int?> lastPlayed = const Value.absent(),
            Value<int> lastPositionMs = const Value.absent(),
            Value<String?> artworkUri = const Value.absent(),
            Value<int?> fileSize = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String?> remoteId = const Value.absent(),
            Value<String?> remoteArtworkUrl = const Value.absent(),
            Value<String?> pendingDownloadPath = const Value.absent(),
          }) =>
              SongsTableCompanion(
            id: id,
            title: title,
            artist: artist,
            artistId: artistId,
            album: album,
            albumId: albumId,
            durationMs: durationMs,
            path: path,
            uri: uri,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            dateAdded: dateAdded,
            genre: genre,
            isFavorite: isFavorite,
            isMissing: isMissing,
            replayGain: replayGain,
            playCount: playCount,
            lastPlayed: lastPlayed,
            lastPositionMs: lastPositionMs,
            artworkUri: artworkUri,
            fileSize: fileSize,
            source: source,
            remoteId: remoteId,
            remoteArtworkUrl: remoteArtworkUrl,
            pendingDownloadPath: pendingDownloadPath,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String title,
            Value<String> artist = const Value.absent(),
            Value<int?> artistId = const Value.absent(),
            Value<String> album = const Value.absent(),
            Value<int?> albumId = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            required String path,
            Value<String?> uri = const Value.absent(),
            Value<int?> trackNumber = const Value.absent(),
            Value<int?> discNumber = const Value.absent(),
            Value<int?> year = const Value.absent(),
            Value<int?> dateAdded = const Value.absent(),
            Value<String?> genre = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<bool> isMissing = const Value.absent(),
            Value<double?> replayGain = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int?> lastPlayed = const Value.absent(),
            Value<int> lastPositionMs = const Value.absent(),
            Value<String?> artworkUri = const Value.absent(),
            Value<int?> fileSize = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String?> remoteId = const Value.absent(),
            Value<String?> remoteArtworkUrl = const Value.absent(),
            Value<String?> pendingDownloadPath = const Value.absent(),
          }) =>
              SongsTableCompanion.insert(
            id: id,
            title: title,
            artist: artist,
            artistId: artistId,
            album: album,
            albumId: albumId,
            durationMs: durationMs,
            path: path,
            uri: uri,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            dateAdded: dateAdded,
            genre: genre,
            isFavorite: isFavorite,
            isMissing: isMissing,
            replayGain: replayGain,
            playCount: playCount,
            lastPlayed: lastPlayed,
            lastPositionMs: lastPositionMs,
            artworkUri: artworkUri,
            fileSize: fileSize,
            source: source,
            remoteId: remoteId,
            remoteArtworkUrl: remoteArtworkUrl,
            pendingDownloadPath: pendingDownloadPath,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SongsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SongsTableTable,
    SongsTableData,
    $$SongsTableTableFilterComposer,
    $$SongsTableTableOrderingComposer,
    $$SongsTableTableAnnotationComposer,
    $$SongsTableTableCreateCompanionBuilder,
    $$SongsTableTableUpdateCompanionBuilder,
    (
      SongsTableData,
      BaseReferences<_$AppDatabase, $SongsTableTable, SongsTableData>
    ),
    SongsTableData,
    PrefetchHooks Function()>;
typedef $$AlbumsTableTableCreateCompanionBuilder = AlbumsTableCompanion
    Function({
  Value<int> id,
  required String title,
  Value<String> artist,
  Value<int?> artistId,
  Value<int> songCount,
  Value<String?> artworkUri,
  Value<int?> year,
});
typedef $$AlbumsTableTableUpdateCompanionBuilder = AlbumsTableCompanion
    Function({
  Value<int> id,
  Value<String> title,
  Value<String> artist,
  Value<int?> artistId,
  Value<int> songCount,
  Value<String?> artworkUri,
  Value<int?> year,
});

class $$AlbumsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTableTable> {
  $$AlbumsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get songCount => $composableBuilder(
      column: $table.songCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));
}

class $$AlbumsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTableTable> {
  $$AlbumsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artist => $composableBuilder(
      column: $table.artist, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get artistId => $composableBuilder(
      column: $table.artistId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get songCount => $composableBuilder(
      column: $table.songCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));
}

class $$AlbumsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTableTable> {
  $$AlbumsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<int> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<int> get songCount =>
      $composableBuilder(column: $table.songCount, builder: (column) => column);

  GeneratedColumn<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);
}

class $$AlbumsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlbumsTableTable,
    AlbumsTableData,
    $$AlbumsTableTableFilterComposer,
    $$AlbumsTableTableOrderingComposer,
    $$AlbumsTableTableAnnotationComposer,
    $$AlbumsTableTableCreateCompanionBuilder,
    $$AlbumsTableTableUpdateCompanionBuilder,
    (
      AlbumsTableData,
      BaseReferences<_$AppDatabase, $AlbumsTableTable, AlbumsTableData>
    ),
    AlbumsTableData,
    PrefetchHooks Function()> {
  $$AlbumsTableTableTableManager(_$AppDatabase db, $AlbumsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> artist = const Value.absent(),
            Value<int?> artistId = const Value.absent(),
            Value<int> songCount = const Value.absent(),
            Value<String?> artworkUri = const Value.absent(),
            Value<int?> year = const Value.absent(),
          }) =>
              AlbumsTableCompanion(
            id: id,
            title: title,
            artist: artist,
            artistId: artistId,
            songCount: songCount,
            artworkUri: artworkUri,
            year: year,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String title,
            Value<String> artist = const Value.absent(),
            Value<int?> artistId = const Value.absent(),
            Value<int> songCount = const Value.absent(),
            Value<String?> artworkUri = const Value.absent(),
            Value<int?> year = const Value.absent(),
          }) =>
              AlbumsTableCompanion.insert(
            id: id,
            title: title,
            artist: artist,
            artistId: artistId,
            songCount: songCount,
            artworkUri: artworkUri,
            year: year,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AlbumsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlbumsTableTable,
    AlbumsTableData,
    $$AlbumsTableTableFilterComposer,
    $$AlbumsTableTableOrderingComposer,
    $$AlbumsTableTableAnnotationComposer,
    $$AlbumsTableTableCreateCompanionBuilder,
    $$AlbumsTableTableUpdateCompanionBuilder,
    (
      AlbumsTableData,
      BaseReferences<_$AppDatabase, $AlbumsTableTable, AlbumsTableData>
    ),
    AlbumsTableData,
    PrefetchHooks Function()>;
typedef $$ArtistsTableTableCreateCompanionBuilder = ArtistsTableCompanion
    Function({
  Value<int> id,
  required String name,
  Value<int> songCount,
  Value<int> albumCount,
  Value<String?> artworkUri,
});
typedef $$ArtistsTableTableUpdateCompanionBuilder = ArtistsTableCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<int> songCount,
  Value<int> albumCount,
  Value<String?> artworkUri,
});

class $$ArtistsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ArtistsTableTable> {
  $$ArtistsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get songCount => $composableBuilder(
      column: $table.songCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get albumCount => $composableBuilder(
      column: $table.albumCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => ColumnFilters(column));
}

class $$ArtistsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ArtistsTableTable> {
  $$ArtistsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get songCount => $composableBuilder(
      column: $table.songCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get albumCount => $composableBuilder(
      column: $table.albumCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => ColumnOrderings(column));
}

class $$ArtistsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArtistsTableTable> {
  $$ArtistsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get songCount =>
      $composableBuilder(column: $table.songCount, builder: (column) => column);

  GeneratedColumn<int> get albumCount => $composableBuilder(
      column: $table.albumCount, builder: (column) => column);

  GeneratedColumn<String> get artworkUri => $composableBuilder(
      column: $table.artworkUri, builder: (column) => column);
}

class $$ArtistsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ArtistsTableTable,
    ArtistsTableData,
    $$ArtistsTableTableFilterComposer,
    $$ArtistsTableTableOrderingComposer,
    $$ArtistsTableTableAnnotationComposer,
    $$ArtistsTableTableCreateCompanionBuilder,
    $$ArtistsTableTableUpdateCompanionBuilder,
    (
      ArtistsTableData,
      BaseReferences<_$AppDatabase, $ArtistsTableTable, ArtistsTableData>
    ),
    ArtistsTableData,
    PrefetchHooks Function()> {
  $$ArtistsTableTableTableManager(_$AppDatabase db, $ArtistsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtistsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtistsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtistsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> songCount = const Value.absent(),
            Value<int> albumCount = const Value.absent(),
            Value<String?> artworkUri = const Value.absent(),
          }) =>
              ArtistsTableCompanion(
            id: id,
            name: name,
            songCount: songCount,
            albumCount: albumCount,
            artworkUri: artworkUri,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<int> songCount = const Value.absent(),
            Value<int> albumCount = const Value.absent(),
            Value<String?> artworkUri = const Value.absent(),
          }) =>
              ArtistsTableCompanion.insert(
            id: id,
            name: name,
            songCount: songCount,
            albumCount: albumCount,
            artworkUri: artworkUri,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ArtistsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ArtistsTableTable,
    ArtistsTableData,
    $$ArtistsTableTableFilterComposer,
    $$ArtistsTableTableOrderingComposer,
    $$ArtistsTableTableAnnotationComposer,
    $$ArtistsTableTableCreateCompanionBuilder,
    $$ArtistsTableTableUpdateCompanionBuilder,
    (
      ArtistsTableData,
      BaseReferences<_$AppDatabase, $ArtistsTableTable, ArtistsTableData>
    ),
    ArtistsTableData,
    PrefetchHooks Function()>;
typedef $$PlaylistsTableTableCreateCompanionBuilder = PlaylistsTableCompanion
    Function({
  Value<int> id,
  required String name,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isSmart,
  Value<String?> smartCriteria,
});
typedef $$PlaylistsTableTableUpdateCompanionBuilder = PlaylistsTableCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isSmart,
  Value<String?> smartCriteria,
});

class $$PlaylistsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSmart => $composableBuilder(
      column: $table.isSmart, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get smartCriteria => $composableBuilder(
      column: $table.smartCriteria, builder: (column) => ColumnFilters(column));
}

class $$PlaylistsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSmart => $composableBuilder(
      column: $table.isSmart, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get smartCriteria => $composableBuilder(
      column: $table.smartCriteria,
      builder: (column) => ColumnOrderings(column));
}

class $$PlaylistsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isSmart =>
      $composableBuilder(column: $table.isSmart, builder: (column) => column);

  GeneratedColumn<String> get smartCriteria => $composableBuilder(
      column: $table.smartCriteria, builder: (column) => column);
}

class $$PlaylistsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaylistsTableTable,
    PlaylistsTableData,
    $$PlaylistsTableTableFilterComposer,
    $$PlaylistsTableTableOrderingComposer,
    $$PlaylistsTableTableAnnotationComposer,
    $$PlaylistsTableTableCreateCompanionBuilder,
    $$PlaylistsTableTableUpdateCompanionBuilder,
    (
      PlaylistsTableData,
      BaseReferences<_$AppDatabase, $PlaylistsTableTable, PlaylistsTableData>
    ),
    PlaylistsTableData,
    PrefetchHooks Function()> {
  $$PlaylistsTableTableTableManager(
      _$AppDatabase db, $PlaylistsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isSmart = const Value.absent(),
            Value<String?> smartCriteria = const Value.absent(),
          }) =>
              PlaylistsTableCompanion(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isSmart: isSmart,
            smartCriteria: smartCriteria,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isSmart = const Value.absent(),
            Value<String?> smartCriteria = const Value.absent(),
          }) =>
              PlaylistsTableCompanion.insert(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isSmart: isSmart,
            smartCriteria: smartCriteria,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlaylistsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaylistsTableTable,
    PlaylistsTableData,
    $$PlaylistsTableTableFilterComposer,
    $$PlaylistsTableTableOrderingComposer,
    $$PlaylistsTableTableAnnotationComposer,
    $$PlaylistsTableTableCreateCompanionBuilder,
    $$PlaylistsTableTableUpdateCompanionBuilder,
    (
      PlaylistsTableData,
      BaseReferences<_$AppDatabase, $PlaylistsTableTable, PlaylistsTableData>
    ),
    PlaylistsTableData,
    PrefetchHooks Function()>;
typedef $$PlaylistEntriesTableTableCreateCompanionBuilder
    = PlaylistEntriesTableCompanion Function({
  Value<int> id,
  required int playlistId,
  required int songId,
  required int orderIndex,
  Value<DateTime> addedAt,
});
typedef $$PlaylistEntriesTableTableUpdateCompanionBuilder
    = PlaylistEntriesTableCompanion Function({
  Value<int> id,
  Value<int> playlistId,
  Value<int> songId,
  Value<int> orderIndex,
  Value<DateTime> addedAt,
});

class $$PlaylistEntriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTableTable> {
  $$PlaylistEntriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playlistId => $composableBuilder(
      column: $table.playlistId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get songId => $composableBuilder(
      column: $table.songId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$PlaylistEntriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTableTable> {
  $$PlaylistEntriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playlistId => $composableBuilder(
      column: $table.playlistId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get songId => $composableBuilder(
      column: $table.songId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$PlaylistEntriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTableTable> {
  $$PlaylistEntriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get playlistId => $composableBuilder(
      column: $table.playlistId, builder: (column) => column);

  GeneratedColumn<int> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$PlaylistEntriesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaylistEntriesTableTable,
    PlaylistEntriesTableData,
    $$PlaylistEntriesTableTableFilterComposer,
    $$PlaylistEntriesTableTableOrderingComposer,
    $$PlaylistEntriesTableTableAnnotationComposer,
    $$PlaylistEntriesTableTableCreateCompanionBuilder,
    $$PlaylistEntriesTableTableUpdateCompanionBuilder,
    (
      PlaylistEntriesTableData,
      BaseReferences<_$AppDatabase, $PlaylistEntriesTableTable,
          PlaylistEntriesTableData>
    ),
    PlaylistEntriesTableData,
    PrefetchHooks Function()> {
  $$PlaylistEntriesTableTableTableManager(
      _$AppDatabase db, $PlaylistEntriesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistEntriesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistEntriesTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistEntriesTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> playlistId = const Value.absent(),
            Value<int> songId = const Value.absent(),
            Value<int> orderIndex = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              PlaylistEntriesTableCompanion(
            id: id,
            playlistId: playlistId,
            songId: songId,
            orderIndex: orderIndex,
            addedAt: addedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int playlistId,
            required int songId,
            required int orderIndex,
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              PlaylistEntriesTableCompanion.insert(
            id: id,
            playlistId: playlistId,
            songId: songId,
            orderIndex: orderIndex,
            addedAt: addedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlaylistEntriesTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $PlaylistEntriesTableTable,
        PlaylistEntriesTableData,
        $$PlaylistEntriesTableTableFilterComposer,
        $$PlaylistEntriesTableTableOrderingComposer,
        $$PlaylistEntriesTableTableAnnotationComposer,
        $$PlaylistEntriesTableTableCreateCompanionBuilder,
        $$PlaylistEntriesTableTableUpdateCompanionBuilder,
        (
          PlaylistEntriesTableData,
          BaseReferences<_$AppDatabase, $PlaylistEntriesTableTable,
              PlaylistEntriesTableData>
        ),
        PlaylistEntriesTableData,
        PrefetchHooks Function()>;
typedef $$PlayHistoryTableTableCreateCompanionBuilder
    = PlayHistoryTableCompanion Function({
  Value<int> id,
  required int songId,
  Value<DateTime> playedAt,
  Value<bool> completed,
});
typedef $$PlayHistoryTableTableUpdateCompanionBuilder
    = PlayHistoryTableCompanion Function({
  Value<int> id,
  Value<int> songId,
  Value<DateTime> playedAt,
  Value<bool> completed,
});

class $$PlayHistoryTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlayHistoryTableTable> {
  $$PlayHistoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get songId => $composableBuilder(
      column: $table.songId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
      column: $table.playedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnFilters(column));
}

class $$PlayHistoryTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayHistoryTableTable> {
  $$PlayHistoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get songId => $composableBuilder(
      column: $table.songId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
      column: $table.playedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnOrderings(column));
}

class $$PlayHistoryTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayHistoryTableTable> {
  $$PlayHistoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);
}

class $$PlayHistoryTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlayHistoryTableTable,
    PlayHistoryTableData,
    $$PlayHistoryTableTableFilterComposer,
    $$PlayHistoryTableTableOrderingComposer,
    $$PlayHistoryTableTableAnnotationComposer,
    $$PlayHistoryTableTableCreateCompanionBuilder,
    $$PlayHistoryTableTableUpdateCompanionBuilder,
    (
      PlayHistoryTableData,
      BaseReferences<_$AppDatabase, $PlayHistoryTableTable,
          PlayHistoryTableData>
    ),
    PlayHistoryTableData,
    PrefetchHooks Function()> {
  $$PlayHistoryTableTableTableManager(
      _$AppDatabase db, $PlayHistoryTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayHistoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayHistoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayHistoryTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> songId = const Value.absent(),
            Value<DateTime> playedAt = const Value.absent(),
            Value<bool> completed = const Value.absent(),
          }) =>
              PlayHistoryTableCompanion(
            id: id,
            songId: songId,
            playedAt: playedAt,
            completed: completed,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int songId,
            Value<DateTime> playedAt = const Value.absent(),
            Value<bool> completed = const Value.absent(),
          }) =>
              PlayHistoryTableCompanion.insert(
            id: id,
            songId: songId,
            playedAt: playedAt,
            completed: completed,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlayHistoryTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlayHistoryTableTable,
    PlayHistoryTableData,
    $$PlayHistoryTableTableFilterComposer,
    $$PlayHistoryTableTableOrderingComposer,
    $$PlayHistoryTableTableAnnotationComposer,
    $$PlayHistoryTableTableCreateCompanionBuilder,
    $$PlayHistoryTableTableUpdateCompanionBuilder,
    (
      PlayHistoryTableData,
      BaseReferences<_$AppDatabase, $PlayHistoryTableTable,
          PlayHistoryTableData>
    ),
    PlayHistoryTableData,
    PrefetchHooks Function()>;
typedef $$QueueItemsTableTableCreateCompanionBuilder = QueueItemsTableCompanion
    Function({
  Value<int> id,
  required int songId,
  required int orderIndex,
  Value<bool> isCurrent,
  Value<int> positionMs,
});
typedef $$QueueItemsTableTableUpdateCompanionBuilder = QueueItemsTableCompanion
    Function({
  Value<int> id,
  Value<int> songId,
  Value<int> orderIndex,
  Value<bool> isCurrent,
  Value<int> positionMs,
});

class $$QueueItemsTableTableFilterComposer
    extends Composer<_$AppDatabase, $QueueItemsTableTable> {
  $$QueueItemsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get songId => $composableBuilder(
      column: $table.songId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isCurrent => $composableBuilder(
      column: $table.isCurrent, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnFilters(column));
}

class $$QueueItemsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $QueueItemsTableTable> {
  $$QueueItemsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get songId => $composableBuilder(
      column: $table.songId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isCurrent => $composableBuilder(
      column: $table.isCurrent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnOrderings(column));
}

class $$QueueItemsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueueItemsTableTable> {
  $$QueueItemsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => column);

  GeneratedColumn<bool> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => column);
}

class $$QueueItemsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $QueueItemsTableTable,
    QueueItemsTableData,
    $$QueueItemsTableTableFilterComposer,
    $$QueueItemsTableTableOrderingComposer,
    $$QueueItemsTableTableAnnotationComposer,
    $$QueueItemsTableTableCreateCompanionBuilder,
    $$QueueItemsTableTableUpdateCompanionBuilder,
    (
      QueueItemsTableData,
      BaseReferences<_$AppDatabase, $QueueItemsTableTable, QueueItemsTableData>
    ),
    QueueItemsTableData,
    PrefetchHooks Function()> {
  $$QueueItemsTableTableTableManager(
      _$AppDatabase db, $QueueItemsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueItemsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueItemsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueItemsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> songId = const Value.absent(),
            Value<int> orderIndex = const Value.absent(),
            Value<bool> isCurrent = const Value.absent(),
            Value<int> positionMs = const Value.absent(),
          }) =>
              QueueItemsTableCompanion(
            id: id,
            songId: songId,
            orderIndex: orderIndex,
            isCurrent: isCurrent,
            positionMs: positionMs,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int songId,
            required int orderIndex,
            Value<bool> isCurrent = const Value.absent(),
            Value<int> positionMs = const Value.absent(),
          }) =>
              QueueItemsTableCompanion.insert(
            id: id,
            songId: songId,
            orderIndex: orderIndex,
            isCurrent: isCurrent,
            positionMs: positionMs,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$QueueItemsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $QueueItemsTableTable,
    QueueItemsTableData,
    $$QueueItemsTableTableFilterComposer,
    $$QueueItemsTableTableOrderingComposer,
    $$QueueItemsTableTableAnnotationComposer,
    $$QueueItemsTableTableCreateCompanionBuilder,
    $$QueueItemsTableTableUpdateCompanionBuilder,
    (
      QueueItemsTableData,
      BaseReferences<_$AppDatabase, $QueueItemsTableTable, QueueItemsTableData>
    ),
    QueueItemsTableData,
    PrefetchHooks Function()>;
typedef $$ExcludedFoldersTableTableCreateCompanionBuilder
    = ExcludedFoldersTableCompanion Function({
  Value<int> id,
  required String folderPath,
  Value<DateTime> addedAt,
});
typedef $$ExcludedFoldersTableTableUpdateCompanionBuilder
    = ExcludedFoldersTableCompanion Function({
  Value<int> id,
  Value<String> folderPath,
  Value<DateTime> addedAt,
});

class $$ExcludedFoldersTableTableFilterComposer
    extends Composer<_$AppDatabase, $ExcludedFoldersTableTable> {
  $$ExcludedFoldersTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get folderPath => $composableBuilder(
      column: $table.folderPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$ExcludedFoldersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ExcludedFoldersTableTable> {
  $$ExcludedFoldersTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get folderPath => $composableBuilder(
      column: $table.folderPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$ExcludedFoldersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExcludedFoldersTableTable> {
  $$ExcludedFoldersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get folderPath => $composableBuilder(
      column: $table.folderPath, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$ExcludedFoldersTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExcludedFoldersTableTable,
    ExcludedFoldersTableData,
    $$ExcludedFoldersTableTableFilterComposer,
    $$ExcludedFoldersTableTableOrderingComposer,
    $$ExcludedFoldersTableTableAnnotationComposer,
    $$ExcludedFoldersTableTableCreateCompanionBuilder,
    $$ExcludedFoldersTableTableUpdateCompanionBuilder,
    (
      ExcludedFoldersTableData,
      BaseReferences<_$AppDatabase, $ExcludedFoldersTableTable,
          ExcludedFoldersTableData>
    ),
    ExcludedFoldersTableData,
    PrefetchHooks Function()> {
  $$ExcludedFoldersTableTableTableManager(
      _$AppDatabase db, $ExcludedFoldersTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExcludedFoldersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExcludedFoldersTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExcludedFoldersTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> folderPath = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              ExcludedFoldersTableCompanion(
            id: id,
            folderPath: folderPath,
            addedAt: addedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String folderPath,
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              ExcludedFoldersTableCompanion.insert(
            id: id,
            folderPath: folderPath,
            addedAt: addedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExcludedFoldersTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $ExcludedFoldersTableTable,
        ExcludedFoldersTableData,
        $$ExcludedFoldersTableTableFilterComposer,
        $$ExcludedFoldersTableTableOrderingComposer,
        $$ExcludedFoldersTableTableAnnotationComposer,
        $$ExcludedFoldersTableTableCreateCompanionBuilder,
        $$ExcludedFoldersTableTableUpdateCompanionBuilder,
        (
          ExcludedFoldersTableData,
          BaseReferences<_$AppDatabase, $ExcludedFoldersTableTable,
              ExcludedFoldersTableData>
        ),
        ExcludedFoldersTableData,
        PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SongsTableTableTableManager get songsTable =>
      $$SongsTableTableTableManager(_db, _db.songsTable);
  $$AlbumsTableTableTableManager get albumsTable =>
      $$AlbumsTableTableTableManager(_db, _db.albumsTable);
  $$ArtistsTableTableTableManager get artistsTable =>
      $$ArtistsTableTableTableManager(_db, _db.artistsTable);
  $$PlaylistsTableTableTableManager get playlistsTable =>
      $$PlaylistsTableTableTableManager(_db, _db.playlistsTable);
  $$PlaylistEntriesTableTableTableManager get playlistEntriesTable =>
      $$PlaylistEntriesTableTableTableManager(_db, _db.playlistEntriesTable);
  $$PlayHistoryTableTableTableManager get playHistoryTable =>
      $$PlayHistoryTableTableTableManager(_db, _db.playHistoryTable);
  $$QueueItemsTableTableTableManager get queueItemsTable =>
      $$QueueItemsTableTableTableManager(_db, _db.queueItemsTable);
  $$ExcludedFoldersTableTableTableManager get excludedFoldersTable =>
      $$ExcludedFoldersTableTableTableManager(_db, _db.excludedFoldersTable);
}
