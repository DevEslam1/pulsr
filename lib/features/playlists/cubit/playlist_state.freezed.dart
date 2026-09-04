// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playlist_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PlaylistState {
  List<PlaylistsTableData> get playlists;
  List<SongsTableData> get currentPlaylistSongs;
  Map<int, int> get smartPlaylistCounts;
  bool get isLoading;
  String? get errorMessage;

  /// Create a copy of PlaylistState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $PlaylistStateCopyWith<PlaylistState> get copyWith =>
      _$PlaylistStateCopyWithImpl<PlaylistState>(
          this as PlaylistState, _$identity);

  @override
  bool operator ==(Object other) {
    final _this = this as PlaylistState;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is PlaylistState &&
            const DeepCollectionEquality()
                .equals(other.playlists, _this.playlists) &&
            const DeepCollectionEquality().equals(
                other.currentPlaylistSongs, _this.currentPlaylistSongs) &&
            const DeepCollectionEquality()
                .equals(other.smartPlaylistCounts, _this.smartPlaylistCounts) &&
            (identical(other.isLoading, _this.isLoading) ||
                other.isLoading == _this.isLoading) &&
            (identical(other.errorMessage, _this.errorMessage) ||
                other.errorMessage == _this.errorMessage));
  }

  @override
  int get hashCode {
    final _this = this as PlaylistState;
    return Object.hash(
        runtimeType,
        const DeepCollectionEquality().hash(_this.playlists),
        const DeepCollectionEquality().hash(_this.currentPlaylistSongs),
        const DeepCollectionEquality().hash(_this.smartPlaylistCounts),
        _this.isLoading,
        _this.errorMessage);
  }

  @override
  String toString() {
    final _this = this as PlaylistState;
    return 'PlaylistState(playlists: ${_this.playlists}, currentPlaylistSongs: ${_this.currentPlaylistSongs}, smartPlaylistCounts: ${_this.smartPlaylistCounts}, isLoading: ${_this.isLoading}, errorMessage: ${_this.errorMessage})';
  }
}

/// @nodoc
abstract mixin class $PlaylistStateCopyWith<$Res> {
  factory $PlaylistStateCopyWith(
          PlaylistState value, $Res Function(PlaylistState) _then) =
      _$PlaylistStateCopyWithImpl;
  @useResult
  $Res call(
      {List<PlaylistsTableData> playlists,
      List<SongsTableData> currentPlaylistSongs,
      Map<int, int> smartPlaylistCounts,
      bool isLoading,
      String? errorMessage});
}

/// @nodoc
class _$PlaylistStateCopyWithImpl<$Res>
    implements $PlaylistStateCopyWith<$Res> {
  _$PlaylistStateCopyWithImpl(this._self, this._then);

  final PlaylistState _self;
  final $Res Function(PlaylistState) _then;

  /// Create a copy of PlaylistState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? playlists = null,
    Object? currentPlaylistSongs = null,
    Object? smartPlaylistCounts = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
  }) {
    return _then(PlaylistState(
      playlists: null == playlists
          ? _self.playlists
          : playlists // ignore: cast_nullable_to_non_nullable
              as List<PlaylistsTableData>,
      currentPlaylistSongs: null == currentPlaylistSongs
          ? _self.currentPlaylistSongs
          : currentPlaylistSongs // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      smartPlaylistCounts: null == smartPlaylistCounts
          ? _self.smartPlaylistCounts
          : smartPlaylistCounts // ignore: cast_nullable_to_non_nullable
              as Map<int, int>,
      isLoading: null == isLoading
          ? _self.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [PlaylistState].
extension PlaylistStatePatterns on PlaylistState {
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
    TResult Function(_PlaylistState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _PlaylistState() when $default != null:
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
    TResult Function(_PlaylistState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlaylistState():
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
    TResult? Function(_PlaylistState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlaylistState() when $default != null:
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
            List<PlaylistsTableData> playlists,
            List<SongsTableData> currentPlaylistSongs,
            Map<int, int> smartPlaylistCounts,
            bool isLoading,
            String? errorMessage)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _PlaylistState() when $default != null:
        return $default(_that.playlists, _that.currentPlaylistSongs,
            _that.smartPlaylistCounts, _that.isLoading, _that.errorMessage);
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
            List<PlaylistsTableData> playlists,
            List<SongsTableData> currentPlaylistSongs,
            Map<int, int> smartPlaylistCounts,
            bool isLoading,
            String? errorMessage)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlaylistState():
        return $default(_that.playlists, _that.currentPlaylistSongs,
            _that.smartPlaylistCounts, _that.isLoading, _that.errorMessage);
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
            List<PlaylistsTableData> playlists,
            List<SongsTableData> currentPlaylistSongs,
            Map<int, int> smartPlaylistCounts,
            bool isLoading,
            String? errorMessage)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlaylistState() when $default != null:
        return $default(_that.playlists, _that.currentPlaylistSongs,
            _that.smartPlaylistCounts, _that.isLoading, _that.errorMessage);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _PlaylistState extends PlaylistState {
  const _PlaylistState(
      {List<PlaylistsTableData> playlists = const [],
      List<SongsTableData> currentPlaylistSongs = const [],
      Map<int, int> smartPlaylistCounts = const {},
      this.isLoading = false,
      this.errorMessage})
      : _playlists = playlists,
        _currentPlaylistSongs = currentPlaylistSongs,
        _smartPlaylistCounts = smartPlaylistCounts,
        super._();

  final List<PlaylistsTableData> _playlists;
  @override
  @JsonKey()
  List<PlaylistsTableData> get playlists {
    if (_playlists is EqualUnmodifiableListView) return _playlists;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_playlists);
  }

  final List<SongsTableData> _currentPlaylistSongs;
  @override
  @JsonKey()
  List<SongsTableData> get currentPlaylistSongs {
    if (_currentPlaylistSongs is EqualUnmodifiableListView)
      return _currentPlaylistSongs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_currentPlaylistSongs);
  }

  final Map<int, int> _smartPlaylistCounts;
  @override
  @JsonKey()
  Map<int, int> get smartPlaylistCounts {
    if (_smartPlaylistCounts is EqualUnmodifiableMapView)
      return _smartPlaylistCounts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_smartPlaylistCounts);
  }

  @override
  @JsonKey()
  final bool isLoading;
  @override
  final String? errorMessage;

  /// Create a copy of PlaylistState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$PlaylistStateCopyWith<_PlaylistState> get copyWith =>
      __$PlaylistStateCopyWithImpl<_PlaylistState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _PlaylistState &&
            const DeepCollectionEquality()
                .equals(other.playlists, _playlists) &&
            const DeepCollectionEquality()
                .equals(other.currentPlaylistSongs, _currentPlaylistSongs) &&
            const DeepCollectionEquality()
                .equals(other.smartPlaylistCounts, _smartPlaylistCounts) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @override
  int get hashCode {
    return Object.hash(
        runtimeType,
        const DeepCollectionEquality().hash(_playlists),
        const DeepCollectionEquality().hash(_currentPlaylistSongs),
        const DeepCollectionEquality().hash(_smartPlaylistCounts),
        isLoading,
        errorMessage);
  }

  @override
  String toString() {
    return 'PlaylistState(playlists: $playlists, currentPlaylistSongs: $currentPlaylistSongs, smartPlaylistCounts: $smartPlaylistCounts, isLoading: $isLoading, errorMessage: $errorMessage)';
  }
}

/// @nodoc
abstract mixin class _$PlaylistStateCopyWith<$Res>
    implements $PlaylistStateCopyWith<$Res> {
  factory _$PlaylistStateCopyWith(
          _PlaylistState value, $Res Function(_PlaylistState) _then) =
      __$PlaylistStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {List<PlaylistsTableData> playlists,
      List<SongsTableData> currentPlaylistSongs,
      Map<int, int> smartPlaylistCounts,
      bool isLoading,
      String? errorMessage});
}

/// @nodoc
class __$PlaylistStateCopyWithImpl<$Res>
    implements _$PlaylistStateCopyWith<$Res> {
  __$PlaylistStateCopyWithImpl(this._self, this._then);

  final _PlaylistState _self;
  final $Res Function(_PlaylistState) _then;

  /// Create a copy of PlaylistState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? playlists = null,
    Object? currentPlaylistSongs = null,
    Object? smartPlaylistCounts = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
  }) {
    return _then(_PlaylistState(
      playlists: null == playlists
          ? _self._playlists
          : playlists // ignore: cast_nullable_to_non_nullable
              as List<PlaylistsTableData>,
      currentPlaylistSongs: null == currentPlaylistSongs
          ? _self._currentPlaylistSongs
          : currentPlaylistSongs // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      smartPlaylistCounts: null == smartPlaylistCounts
          ? _self._smartPlaylistCounts
          : smartPlaylistCounts // ignore: cast_nullable_to_non_nullable
              as Map<int, int>,
      isLoading: null == isLoading
          ? _self.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
