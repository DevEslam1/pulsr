// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'library_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LibraryState {
  List<SongsTableData> get songs;
  List<AlbumsTableData> get albums;
  List<ArtistsTableData> get artists;
  List<GenreItem> get genres;
  List<YearItem> get years;
  List<SongsTableData> get favorites;
  List<FolderItem> get folders;
  String get sortBy;
  bool get ascending;
  bool get isLoading;
  String? get errorMessage;
  Set<int> get selectedSongIds;
  bool get isMultiSelectMode;
  LibraryViewMode get viewMode;

  /// Create a copy of LibraryState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LibraryStateCopyWith<LibraryState> get copyWith =>
      _$LibraryStateCopyWithImpl<LibraryState>(
          this as LibraryState, _$identity);

  @override
  bool operator ==(Object other) {
    final _this = this as LibraryState;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LibraryState &&
            const DeepCollectionEquality().equals(other.songs, _this.songs) &&
            const DeepCollectionEquality().equals(other.albums, _this.albums) &&
            const DeepCollectionEquality()
                .equals(other.artists, _this.artists) &&
            const DeepCollectionEquality().equals(other.genres, _this.genres) &&
            const DeepCollectionEquality().equals(other.years, _this.years) &&
            const DeepCollectionEquality()
                .equals(other.favorites, _this.favorites) &&
            const DeepCollectionEquality()
                .equals(other.folders, _this.folders) &&
            (identical(other.sortBy, _this.sortBy) ||
                other.sortBy == _this.sortBy) &&
            (identical(other.ascending, _this.ascending) ||
                other.ascending == _this.ascending) &&
            (identical(other.isLoading, _this.isLoading) ||
                other.isLoading == _this.isLoading) &&
            (identical(other.errorMessage, _this.errorMessage) ||
                other.errorMessage == _this.errorMessage) &&
            const DeepCollectionEquality()
                .equals(other.selectedSongIds, _this.selectedSongIds) &&
            (identical(other.isMultiSelectMode, _this.isMultiSelectMode) ||
                other.isMultiSelectMode == _this.isMultiSelectMode) &&
            (identical(other.viewMode, _this.viewMode) ||
                other.viewMode == _this.viewMode));
  }

  @override
  int get hashCode {
    final _this = this as LibraryState;
    return Object.hash(
        runtimeType,
        const DeepCollectionEquality().hash(_this.songs),
        const DeepCollectionEquality().hash(_this.albums),
        const DeepCollectionEquality().hash(_this.artists),
        const DeepCollectionEquality().hash(_this.genres),
        const DeepCollectionEquality().hash(_this.years),
        const DeepCollectionEquality().hash(_this.favorites),
        const DeepCollectionEquality().hash(_this.folders),
        _this.sortBy,
        _this.ascending,
        _this.isLoading,
        _this.errorMessage,
        const DeepCollectionEquality().hash(_this.selectedSongIds),
        _this.isMultiSelectMode,
        _this.viewMode);
  }

  @override
  String toString() {
    final _this = this as LibraryState;
    return 'LibraryState(songs: ${_this.songs}, albums: ${_this.albums}, artists: ${_this.artists}, genres: ${_this.genres}, years: ${_this.years}, favorites: ${_this.favorites}, folders: ${_this.folders}, sortBy: ${_this.sortBy}, ascending: ${_this.ascending}, isLoading: ${_this.isLoading}, errorMessage: ${_this.errorMessage}, selectedSongIds: ${_this.selectedSongIds}, isMultiSelectMode: ${_this.isMultiSelectMode}, viewMode: ${_this.viewMode})';
  }
}

/// @nodoc
abstract mixin class $LibraryStateCopyWith<$Res> {
  factory $LibraryStateCopyWith(
          LibraryState value, $Res Function(LibraryState) _then) =
      _$LibraryStateCopyWithImpl;
  @useResult
  $Res call(
      {List<SongsTableData> songs,
      List<AlbumsTableData> albums,
      List<ArtistsTableData> artists,
      List<GenreItem> genres,
      List<YearItem> years,
      List<SongsTableData> favorites,
      List<FolderItem> folders,
      String sortBy,
      bool ascending,
      bool isLoading,
      String? errorMessage,
      Set<int> selectedSongIds,
      bool isMultiSelectMode,
      LibraryViewMode viewMode});
}

/// @nodoc
class _$LibraryStateCopyWithImpl<$Res> implements $LibraryStateCopyWith<$Res> {
  _$LibraryStateCopyWithImpl(this._self, this._then);

  final LibraryState _self;
  final $Res Function(LibraryState) _then;

  /// Create a copy of LibraryState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? songs = null,
    Object? albums = null,
    Object? artists = null,
    Object? genres = null,
    Object? years = null,
    Object? favorites = null,
    Object? folders = null,
    Object? sortBy = null,
    Object? ascending = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
    Object? selectedSongIds = null,
    Object? isMultiSelectMode = null,
    Object? viewMode = null,
  }) {
    return _then(LibraryState(
      songs: null == songs
          ? _self.songs
          : songs // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      albums: null == albums
          ? _self.albums
          : albums // ignore: cast_nullable_to_non_nullable
              as List<AlbumsTableData>,
      artists: null == artists
          ? _self.artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<ArtistsTableData>,
      genres: null == genres
          ? _self.genres
          : genres // ignore: cast_nullable_to_non_nullable
              as List<GenreItem>,
      years: null == years
          ? _self.years
          : years // ignore: cast_nullable_to_non_nullable
              as List<YearItem>,
      favorites: null == favorites
          ? _self.favorites
          : favorites // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      folders: null == folders
          ? _self.folders
          : folders // ignore: cast_nullable_to_non_nullable
              as List<FolderItem>,
      sortBy: null == sortBy
          ? _self.sortBy
          : sortBy // ignore: cast_nullable_to_non_nullable
              as String,
      ascending: null == ascending
          ? _self.ascending
          : ascending // ignore: cast_nullable_to_non_nullable
              as bool,
      isLoading: null == isLoading
          ? _self.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      selectedSongIds: null == selectedSongIds
          ? _self.selectedSongIds
          : selectedSongIds // ignore: cast_nullable_to_non_nullable
              as Set<int>,
      isMultiSelectMode: null == isMultiSelectMode
          ? _self.isMultiSelectMode
          : isMultiSelectMode // ignore: cast_nullable_to_non_nullable
              as bool,
      viewMode: null == viewMode
          ? _self.viewMode
          : viewMode // ignore: cast_nullable_to_non_nullable
              as LibraryViewMode,
    ));
  }
}

/// Adds pattern-matching-related methods to [LibraryState].
extension LibraryStatePatterns on LibraryState {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_LibraryState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _LibraryState() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_LibraryState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LibraryState():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_LibraryState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LibraryState() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            List<SongsTableData> songs,
            List<AlbumsTableData> albums,
            List<ArtistsTableData> artists,
            List<GenreItem> genres,
            List<YearItem> years,
            List<SongsTableData> favorites,
            List<FolderItem> folders,
            String sortBy,
            bool ascending,
            bool isLoading,
            String? errorMessage,
            Set<int> selectedSongIds,
            bool isMultiSelectMode,
            LibraryViewMode viewMode)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _LibraryState() when $default != null:
        return $default(
            _that.songs,
            _that.albums,
            _that.artists,
            _that.genres,
            _that.years,
            _that.favorites,
            _that.folders,
            _that.sortBy,
            _that.ascending,
            _that.isLoading,
            _that.errorMessage,
            _that.selectedSongIds,
            _that.isMultiSelectMode,
            _that.viewMode);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            List<SongsTableData> songs,
            List<AlbumsTableData> albums,
            List<ArtistsTableData> artists,
            List<GenreItem> genres,
            List<YearItem> years,
            List<SongsTableData> favorites,
            List<FolderItem> folders,
            String sortBy,
            bool ascending,
            bool isLoading,
            String? errorMessage,
            Set<int> selectedSongIds,
            bool isMultiSelectMode,
            LibraryViewMode viewMode)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LibraryState():
        return $default(
            _that.songs,
            _that.albums,
            _that.artists,
            _that.genres,
            _that.years,
            _that.favorites,
            _that.folders,
            _that.sortBy,
            _that.ascending,
            _that.isLoading,
            _that.errorMessage,
            _that.selectedSongIds,
            _that.isMultiSelectMode,
            _that.viewMode);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            List<SongsTableData> songs,
            List<AlbumsTableData> albums,
            List<ArtistsTableData> artists,
            List<GenreItem> genres,
            List<YearItem> years,
            List<SongsTableData> favorites,
            List<FolderItem> folders,
            String sortBy,
            bool ascending,
            bool isLoading,
            String? errorMessage,
            Set<int> selectedSongIds,
            bool isMultiSelectMode,
            LibraryViewMode viewMode)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LibraryState() when $default != null:
        return $default(
            _that.songs,
            _that.albums,
            _that.artists,
            _that.genres,
            _that.years,
            _that.favorites,
            _that.folders,
            _that.sortBy,
            _that.ascending,
            _that.isLoading,
            _that.errorMessage,
            _that.selectedSongIds,
            _that.isMultiSelectMode,
            _that.viewMode);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _LibraryState extends LibraryState {
  const _LibraryState(
      {List<SongsTableData> songs = const [],
      List<AlbumsTableData> albums = const [],
      List<ArtistsTableData> artists = const [],
      List<GenreItem> genres = const [],
      List<YearItem> years = const [],
      List<SongsTableData> favorites = const [],
      List<FolderItem> folders = const [],
      this.sortBy = 'title',
      this.ascending = true,
      this.isLoading = false,
      this.errorMessage,
      Set<int> selectedSongIds = const {},
      this.isMultiSelectMode = false,
      this.viewMode = LibraryViewMode.list})
      : _songs = songs,
        _albums = albums,
        _artists = artists,
        _genres = genres,
        _years = years,
        _favorites = favorites,
        _folders = folders,
        _selectedSongIds = selectedSongIds,
        super._();

  final List<SongsTableData> _songs;
  @override
  @JsonKey()
  List<SongsTableData> get songs {
    if (_songs is EqualUnmodifiableListView) return _songs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_songs);
  }

  final List<AlbumsTableData> _albums;
  @override
  @JsonKey()
  List<AlbumsTableData> get albums {
    if (_albums is EqualUnmodifiableListView) return _albums;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_albums);
  }

  final List<ArtistsTableData> _artists;
  @override
  @JsonKey()
  List<ArtistsTableData> get artists {
    if (_artists is EqualUnmodifiableListView) return _artists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_artists);
  }

  final List<GenreItem> _genres;
  @override
  @JsonKey()
  List<GenreItem> get genres {
    if (_genres is EqualUnmodifiableListView) return _genres;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_genres);
  }

  final List<YearItem> _years;
  @override
  @JsonKey()
  List<YearItem> get years {
    if (_years is EqualUnmodifiableListView) return _years;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_years);
  }

  final List<SongsTableData> _favorites;
  @override
  @JsonKey()
  List<SongsTableData> get favorites {
    if (_favorites is EqualUnmodifiableListView) return _favorites;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_favorites);
  }

  final List<FolderItem> _folders;
  @override
  @JsonKey()
  List<FolderItem> get folders {
    if (_folders is EqualUnmodifiableListView) return _folders;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_folders);
  }

  @override
  @JsonKey()
  final String sortBy;
  @override
  @JsonKey()
  final bool ascending;
  @override
  @JsonKey()
  final bool isLoading;
  @override
  final String? errorMessage;
  final Set<int> _selectedSongIds;
  @override
  @JsonKey()
  Set<int> get selectedSongIds {
    if (_selectedSongIds is EqualUnmodifiableSetView) return _selectedSongIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_selectedSongIds);
  }

  @override
  @JsonKey()
  final bool isMultiSelectMode;
  @override
  @JsonKey()
  final LibraryViewMode viewMode;

  /// Create a copy of LibraryState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$LibraryStateCopyWith<_LibraryState> get copyWith =>
      __$LibraryStateCopyWithImpl<_LibraryState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _LibraryState &&
            const DeepCollectionEquality().equals(other.songs, _songs) &&
            const DeepCollectionEquality().equals(other.albums, _albums) &&
            const DeepCollectionEquality().equals(other.artists, _artists) &&
            const DeepCollectionEquality().equals(other.genres, _genres) &&
            const DeepCollectionEquality().equals(other.years, _years) &&
            const DeepCollectionEquality()
                .equals(other.favorites, _favorites) &&
            const DeepCollectionEquality().equals(other.folders, _folders) &&
            (identical(other.sortBy, sortBy) || other.sortBy == sortBy) &&
            (identical(other.ascending, ascending) ||
                other.ascending == ascending) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            const DeepCollectionEquality()
                .equals(other.selectedSongIds, _selectedSongIds) &&
            (identical(other.isMultiSelectMode, isMultiSelectMode) ||
                other.isMultiSelectMode == isMultiSelectMode) &&
            (identical(other.viewMode, viewMode) ||
                other.viewMode == viewMode));
  }

  @override
  int get hashCode {
    return Object.hash(
        runtimeType,
        const DeepCollectionEquality().hash(_songs),
        const DeepCollectionEquality().hash(_albums),
        const DeepCollectionEquality().hash(_artists),
        const DeepCollectionEquality().hash(_genres),
        const DeepCollectionEquality().hash(_years),
        const DeepCollectionEquality().hash(_favorites),
        const DeepCollectionEquality().hash(_folders),
        sortBy,
        ascending,
        isLoading,
        errorMessage,
        const DeepCollectionEquality().hash(_selectedSongIds),
        isMultiSelectMode,
        viewMode);
  }

  @override
  String toString() {
    return 'LibraryState(songs: $songs, albums: $albums, artists: $artists, genres: $genres, years: $years, favorites: $favorites, folders: $folders, sortBy: $sortBy, ascending: $ascending, isLoading: $isLoading, errorMessage: $errorMessage, selectedSongIds: $selectedSongIds, isMultiSelectMode: $isMultiSelectMode, viewMode: $viewMode)';
  }
}

/// @nodoc
abstract mixin class _$LibraryStateCopyWith<$Res>
    implements $LibraryStateCopyWith<$Res> {
  factory _$LibraryStateCopyWith(
          _LibraryState value, $Res Function(_LibraryState) _then) =
      __$LibraryStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {List<SongsTableData> songs,
      List<AlbumsTableData> albums,
      List<ArtistsTableData> artists,
      List<GenreItem> genres,
      List<YearItem> years,
      List<SongsTableData> favorites,
      List<FolderItem> folders,
      String sortBy,
      bool ascending,
      bool isLoading,
      String? errorMessage,
      Set<int> selectedSongIds,
      bool isMultiSelectMode,
      LibraryViewMode viewMode});
}

/// @nodoc
class __$LibraryStateCopyWithImpl<$Res>
    implements _$LibraryStateCopyWith<$Res> {
  __$LibraryStateCopyWithImpl(this._self, this._then);

  final _LibraryState _self;
  final $Res Function(_LibraryState) _then;

  /// Create a copy of LibraryState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? songs = null,
    Object? albums = null,
    Object? artists = null,
    Object? genres = null,
    Object? years = null,
    Object? favorites = null,
    Object? folders = null,
    Object? sortBy = null,
    Object? ascending = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
    Object? selectedSongIds = null,
    Object? isMultiSelectMode = null,
    Object? viewMode = null,
  }) {
    return _then(_LibraryState(
      songs: null == songs
          ? _self._songs
          : songs // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      albums: null == albums
          ? _self._albums
          : albums // ignore: cast_nullable_to_non_nullable
              as List<AlbumsTableData>,
      artists: null == artists
          ? _self._artists
          : artists // ignore: cast_nullable_to_non_nullable
              as List<ArtistsTableData>,
      genres: null == genres
          ? _self._genres
          : genres // ignore: cast_nullable_to_non_nullable
              as List<GenreItem>,
      years: null == years
          ? _self._years
          : years // ignore: cast_nullable_to_non_nullable
              as List<YearItem>,
      favorites: null == favorites
          ? _self._favorites
          : favorites // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      folders: null == folders
          ? _self._folders
          : folders // ignore: cast_nullable_to_non_nullable
              as List<FolderItem>,
      sortBy: null == sortBy
          ? _self.sortBy
          : sortBy // ignore: cast_nullable_to_non_nullable
              as String,
      ascending: null == ascending
          ? _self.ascending
          : ascending // ignore: cast_nullable_to_non_nullable
              as bool,
      isLoading: null == isLoading
          ? _self.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      selectedSongIds: null == selectedSongIds
          ? _self._selectedSongIds
          : selectedSongIds // ignore: cast_nullable_to_non_nullable
              as Set<int>,
      isMultiSelectMode: null == isMultiSelectMode
          ? _self.isMultiSelectMode
          : isMultiSelectMode // ignore: cast_nullable_to_non_nullable
              as bool,
      viewMode: null == viewMode
          ? _self.viewMode
          : viewMode // ignore: cast_nullable_to_non_nullable
              as LibraryViewMode,
    ));
  }
}

// dart format on
