// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'smart_playlist_builder_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SmartPlaylistBuilderState {

 String get name; SmartCriteria get criteria; List<SongsTableData> get previewSongs; bool get isSubmitting; bool get isEditing; int? get editingPlaylistId; String? get errorMessage;
/// Create a copy of SmartPlaylistBuilderState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SmartPlaylistBuilderStateCopyWith<SmartPlaylistBuilderState> get copyWith => _$SmartPlaylistBuilderStateCopyWithImpl<SmartPlaylistBuilderState>(this as SmartPlaylistBuilderState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SmartPlaylistBuilderState&&(identical(other.name, name) || other.name == name)&&(identical(other.criteria, criteria) || other.criteria == criteria)&&const DeepCollectionEquality().equals(other.previewSongs, previewSongs)&&(identical(other.isSubmitting, isSubmitting) || other.isSubmitting == isSubmitting)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.editingPlaylistId, editingPlaylistId) || other.editingPlaylistId == editingPlaylistId)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,name,criteria,const DeepCollectionEquality().hash(previewSongs),isSubmitting,isEditing,editingPlaylistId,errorMessage);

@override
String toString() {
  return 'SmartPlaylistBuilderState(name: $name, criteria: $criteria, previewSongs: $previewSongs, isSubmitting: $isSubmitting, isEditing: $isEditing, editingPlaylistId: $editingPlaylistId, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $SmartPlaylistBuilderStateCopyWith<$Res>  {
  factory $SmartPlaylistBuilderStateCopyWith(SmartPlaylistBuilderState value, $Res Function(SmartPlaylistBuilderState) _then) = _$SmartPlaylistBuilderStateCopyWithImpl;
@useResult
$Res call({
 String name, SmartCriteria criteria, List<SongsTableData> previewSongs, bool isSubmitting, bool isEditing, int? editingPlaylistId, String? errorMessage
});




}
/// @nodoc
class _$SmartPlaylistBuilderStateCopyWithImpl<$Res>
    implements $SmartPlaylistBuilderStateCopyWith<$Res> {
  _$SmartPlaylistBuilderStateCopyWithImpl(this._self, this._then);

  final SmartPlaylistBuilderState _self;
  final $Res Function(SmartPlaylistBuilderState) _then;

/// Create a copy of SmartPlaylistBuilderState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? criteria = null,Object? previewSongs = null,Object? isSubmitting = null,Object? isEditing = null,Object? editingPlaylistId = freezed,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,criteria: null == criteria ? _self.criteria : criteria // ignore: cast_nullable_to_non_nullable
as SmartCriteria,previewSongs: null == previewSongs ? _self.previewSongs : previewSongs // ignore: cast_nullable_to_non_nullable
as List<SongsTableData>,isSubmitting: null == isSubmitting ? _self.isSubmitting : isSubmitting // ignore: cast_nullable_to_non_nullable
as bool,isEditing: null == isEditing ? _self.isEditing : isEditing // ignore: cast_nullable_to_non_nullable
as bool,editingPlaylistId: freezed == editingPlaylistId ? _self.editingPlaylistId : editingPlaylistId // ignore: cast_nullable_to_non_nullable
as int?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SmartPlaylistBuilderState].
extension SmartPlaylistBuilderStatePatterns on SmartPlaylistBuilderState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SmartPlaylistBuilderState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SmartPlaylistBuilderState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SmartPlaylistBuilderState value)  $default,){
final _that = this;
switch (_that) {
case _SmartPlaylistBuilderState():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SmartPlaylistBuilderState value)?  $default,){
final _that = this;
switch (_that) {
case _SmartPlaylistBuilderState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  SmartCriteria criteria,  List<SongsTableData> previewSongs,  bool isSubmitting,  bool isEditing,  int? editingPlaylistId,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SmartPlaylistBuilderState() when $default != null:
return $default(_that.name,_that.criteria,_that.previewSongs,_that.isSubmitting,_that.isEditing,_that.editingPlaylistId,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  SmartCriteria criteria,  List<SongsTableData> previewSongs,  bool isSubmitting,  bool isEditing,  int? editingPlaylistId,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _SmartPlaylistBuilderState():
return $default(_that.name,_that.criteria,_that.previewSongs,_that.isSubmitting,_that.isEditing,_that.editingPlaylistId,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  SmartCriteria criteria,  List<SongsTableData> previewSongs,  bool isSubmitting,  bool isEditing,  int? editingPlaylistId,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _SmartPlaylistBuilderState() when $default != null:
return $default(_that.name,_that.criteria,_that.previewSongs,_that.isSubmitting,_that.isEditing,_that.editingPlaylistId,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _SmartPlaylistBuilderState implements SmartPlaylistBuilderState {
  const _SmartPlaylistBuilderState({this.name = '', this.criteria = const SmartCriteria(), final  List<SongsTableData> previewSongs = const [], this.isSubmitting = false, this.isEditing = false, this.editingPlaylistId, this.errorMessage}): _previewSongs = previewSongs;
  

@override@JsonKey() final  String name;
@override@JsonKey() final  SmartCriteria criteria;
 final  List<SongsTableData> _previewSongs;
@override@JsonKey() List<SongsTableData> get previewSongs {
  if (_previewSongs is EqualUnmodifiableListView) return _previewSongs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_previewSongs);
}

@override@JsonKey() final  bool isSubmitting;
@override@JsonKey() final  bool isEditing;
@override final  int? editingPlaylistId;
@override final  String? errorMessage;

/// Create a copy of SmartPlaylistBuilderState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SmartPlaylistBuilderStateCopyWith<_SmartPlaylistBuilderState> get copyWith => __$SmartPlaylistBuilderStateCopyWithImpl<_SmartPlaylistBuilderState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SmartPlaylistBuilderState&&(identical(other.name, name) || other.name == name)&&(identical(other.criteria, criteria) || other.criteria == criteria)&&const DeepCollectionEquality().equals(other._previewSongs, _previewSongs)&&(identical(other.isSubmitting, isSubmitting) || other.isSubmitting == isSubmitting)&&(identical(other.isEditing, isEditing) || other.isEditing == isEditing)&&(identical(other.editingPlaylistId, editingPlaylistId) || other.editingPlaylistId == editingPlaylistId)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,name,criteria,const DeepCollectionEquality().hash(_previewSongs),isSubmitting,isEditing,editingPlaylistId,errorMessage);

@override
String toString() {
  return 'SmartPlaylistBuilderState(name: $name, criteria: $criteria, previewSongs: $previewSongs, isSubmitting: $isSubmitting, isEditing: $isEditing, editingPlaylistId: $editingPlaylistId, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$SmartPlaylistBuilderStateCopyWith<$Res> implements $SmartPlaylistBuilderStateCopyWith<$Res> {
  factory _$SmartPlaylistBuilderStateCopyWith(_SmartPlaylistBuilderState value, $Res Function(_SmartPlaylistBuilderState) _then) = __$SmartPlaylistBuilderStateCopyWithImpl;
@override @useResult
$Res call({
 String name, SmartCriteria criteria, List<SongsTableData> previewSongs, bool isSubmitting, bool isEditing, int? editingPlaylistId, String? errorMessage
});




}
/// @nodoc
class __$SmartPlaylistBuilderStateCopyWithImpl<$Res>
    implements _$SmartPlaylistBuilderStateCopyWith<$Res> {
  __$SmartPlaylistBuilderStateCopyWithImpl(this._self, this._then);

  final _SmartPlaylistBuilderState _self;
  final $Res Function(_SmartPlaylistBuilderState) _then;

/// Create a copy of SmartPlaylistBuilderState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? criteria = null,Object? previewSongs = null,Object? isSubmitting = null,Object? isEditing = null,Object? editingPlaylistId = freezed,Object? errorMessage = freezed,}) {
  return _then(_SmartPlaylistBuilderState(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,criteria: null == criteria ? _self.criteria : criteria // ignore: cast_nullable_to_non_nullable
as SmartCriteria,previewSongs: null == previewSongs ? _self._previewSongs : previewSongs // ignore: cast_nullable_to_non_nullable
as List<SongsTableData>,isSubmitting: null == isSubmitting ? _self.isSubmitting : isSubmitting // ignore: cast_nullable_to_non_nullable
as bool,isEditing: null == isEditing ? _self.isEditing : isEditing // ignore: cast_nullable_to_non_nullable
as bool,editingPlaylistId: freezed == editingPlaylistId ? _self.editingPlaylistId : editingPlaylistId // ignore: cast_nullable_to_non_nullable
as int?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
