// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 's3_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$S3State {

 List<VirtualFile> get files; List<Tag> get availableTags; List<Session> get availableSessions; List<Tag> get selectedTags; Session? get selectedSession; Set<String> get selectedFilePaths; bool get isLoading; bool get isDeleting; String? get error;
/// Create a copy of S3State
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$S3StateCopyWith<S3State> get copyWith => _$S3StateCopyWithImpl<S3State>(this as S3State, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is S3State&&const DeepCollectionEquality().equals(other.files, files)&&const DeepCollectionEquality().equals(other.availableTags, availableTags)&&const DeepCollectionEquality().equals(other.availableSessions, availableSessions)&&const DeepCollectionEquality().equals(other.selectedTags, selectedTags)&&(identical(other.selectedSession, selectedSession) || other.selectedSession == selectedSession)&&const DeepCollectionEquality().equals(other.selectedFilePaths, selectedFilePaths)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isDeleting, isDeleting) || other.isDeleting == isDeleting)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(files),const DeepCollectionEquality().hash(availableTags),const DeepCollectionEquality().hash(availableSessions),const DeepCollectionEquality().hash(selectedTags),selectedSession,const DeepCollectionEquality().hash(selectedFilePaths),isLoading,isDeleting,error);

@override
String toString() {
  return 'S3State(files: $files, availableTags: $availableTags, availableSessions: $availableSessions, selectedTags: $selectedTags, selectedSession: $selectedSession, selectedFilePaths: $selectedFilePaths, isLoading: $isLoading, isDeleting: $isDeleting, error: $error)';
}


}

/// @nodoc
abstract mixin class $S3StateCopyWith<$Res>  {
  factory $S3StateCopyWith(S3State value, $Res Function(S3State) _then) = _$S3StateCopyWithImpl;
@useResult
$Res call({
 List<VirtualFile> files, List<Tag> availableTags, List<Session> availableSessions, List<Tag> selectedTags, Session? selectedSession, Set<String> selectedFilePaths, bool isLoading, bool isDeleting, String? error
});


$SessionCopyWith<$Res>? get selectedSession;

}
/// @nodoc
class _$S3StateCopyWithImpl<$Res>
    implements $S3StateCopyWith<$Res> {
  _$S3StateCopyWithImpl(this._self, this._then);

  final S3State _self;
  final $Res Function(S3State) _then;

/// Create a copy of S3State
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? files = null,Object? availableTags = null,Object? availableSessions = null,Object? selectedTags = null,Object? selectedSession = freezed,Object? selectedFilePaths = null,Object? isLoading = null,Object? isDeleting = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as List<VirtualFile>,availableTags: null == availableTags ? _self.availableTags : availableTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,availableSessions: null == availableSessions ? _self.availableSessions : availableSessions // ignore: cast_nullable_to_non_nullable
as List<Session>,selectedTags: null == selectedTags ? _self.selectedTags : selectedTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,selectedSession: freezed == selectedSession ? _self.selectedSession : selectedSession // ignore: cast_nullable_to_non_nullable
as Session?,selectedFilePaths: null == selectedFilePaths ? _self.selectedFilePaths : selectedFilePaths // ignore: cast_nullable_to_non_nullable
as Set<String>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isDeleting: null == isDeleting ? _self.isDeleting : isDeleting // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of S3State
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCopyWith<$Res>? get selectedSession {
    if (_self.selectedSession == null) {
    return null;
  }

  return $SessionCopyWith<$Res>(_self.selectedSession!, (value) {
    return _then(_self.copyWith(selectedSession: value));
  });
}
}


/// Adds pattern-matching-related methods to [S3State].
extension S3StatePatterns on S3State {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _S3State value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _S3State() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _S3State value)  $default,){
final _that = this;
switch (_that) {
case _S3State():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _S3State value)?  $default,){
final _that = this;
switch (_that) {
case _S3State() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<VirtualFile> files,  List<Tag> availableTags,  List<Session> availableSessions,  List<Tag> selectedTags,  Session? selectedSession,  Set<String> selectedFilePaths,  bool isLoading,  bool isDeleting,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _S3State() when $default != null:
return $default(_that.files,_that.availableTags,_that.availableSessions,_that.selectedTags,_that.selectedSession,_that.selectedFilePaths,_that.isLoading,_that.isDeleting,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<VirtualFile> files,  List<Tag> availableTags,  List<Session> availableSessions,  List<Tag> selectedTags,  Session? selectedSession,  Set<String> selectedFilePaths,  bool isLoading,  bool isDeleting,  String? error)  $default,) {final _that = this;
switch (_that) {
case _S3State():
return $default(_that.files,_that.availableTags,_that.availableSessions,_that.selectedTags,_that.selectedSession,_that.selectedFilePaths,_that.isLoading,_that.isDeleting,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<VirtualFile> files,  List<Tag> availableTags,  List<Session> availableSessions,  List<Tag> selectedTags,  Session? selectedSession,  Set<String> selectedFilePaths,  bool isLoading,  bool isDeleting,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _S3State() when $default != null:
return $default(_that.files,_that.availableTags,_that.availableSessions,_that.selectedTags,_that.selectedSession,_that.selectedFilePaths,_that.isLoading,_that.isDeleting,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _S3State implements S3State {
  const _S3State({final  List<VirtualFile> files = const [], final  List<Tag> availableTags = const [], final  List<Session> availableSessions = const [], final  List<Tag> selectedTags = const [], this.selectedSession, final  Set<String> selectedFilePaths = const {}, this.isLoading = false, this.isDeleting = false, this.error}): _files = files,_availableTags = availableTags,_availableSessions = availableSessions,_selectedTags = selectedTags,_selectedFilePaths = selectedFilePaths;
  

 final  List<VirtualFile> _files;
@override@JsonKey() List<VirtualFile> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

 final  List<Tag> _availableTags;
@override@JsonKey() List<Tag> get availableTags {
  if (_availableTags is EqualUnmodifiableListView) return _availableTags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableTags);
}

 final  List<Session> _availableSessions;
@override@JsonKey() List<Session> get availableSessions {
  if (_availableSessions is EqualUnmodifiableListView) return _availableSessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableSessions);
}

 final  List<Tag> _selectedTags;
@override@JsonKey() List<Tag> get selectedTags {
  if (_selectedTags is EqualUnmodifiableListView) return _selectedTags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedTags);
}

@override final  Session? selectedSession;
 final  Set<String> _selectedFilePaths;
@override@JsonKey() Set<String> get selectedFilePaths {
  if (_selectedFilePaths is EqualUnmodifiableSetView) return _selectedFilePaths;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_selectedFilePaths);
}

@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isDeleting;
@override final  String? error;

/// Create a copy of S3State
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$S3StateCopyWith<_S3State> get copyWith => __$S3StateCopyWithImpl<_S3State>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _S3State&&const DeepCollectionEquality().equals(other._files, _files)&&const DeepCollectionEquality().equals(other._availableTags, _availableTags)&&const DeepCollectionEquality().equals(other._availableSessions, _availableSessions)&&const DeepCollectionEquality().equals(other._selectedTags, _selectedTags)&&(identical(other.selectedSession, selectedSession) || other.selectedSession == selectedSession)&&const DeepCollectionEquality().equals(other._selectedFilePaths, _selectedFilePaths)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isDeleting, isDeleting) || other.isDeleting == isDeleting)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_files),const DeepCollectionEquality().hash(_availableTags),const DeepCollectionEquality().hash(_availableSessions),const DeepCollectionEquality().hash(_selectedTags),selectedSession,const DeepCollectionEquality().hash(_selectedFilePaths),isLoading,isDeleting,error);

@override
String toString() {
  return 'S3State(files: $files, availableTags: $availableTags, availableSessions: $availableSessions, selectedTags: $selectedTags, selectedSession: $selectedSession, selectedFilePaths: $selectedFilePaths, isLoading: $isLoading, isDeleting: $isDeleting, error: $error)';
}


}

/// @nodoc
abstract mixin class _$S3StateCopyWith<$Res> implements $S3StateCopyWith<$Res> {
  factory _$S3StateCopyWith(_S3State value, $Res Function(_S3State) _then) = __$S3StateCopyWithImpl;
@override @useResult
$Res call({
 List<VirtualFile> files, List<Tag> availableTags, List<Session> availableSessions, List<Tag> selectedTags, Session? selectedSession, Set<String> selectedFilePaths, bool isLoading, bool isDeleting, String? error
});


@override $SessionCopyWith<$Res>? get selectedSession;

}
/// @nodoc
class __$S3StateCopyWithImpl<$Res>
    implements _$S3StateCopyWith<$Res> {
  __$S3StateCopyWithImpl(this._self, this._then);

  final _S3State _self;
  final $Res Function(_S3State) _then;

/// Create a copy of S3State
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? files = null,Object? availableTags = null,Object? availableSessions = null,Object? selectedTags = null,Object? selectedSession = freezed,Object? selectedFilePaths = null,Object? isLoading = null,Object? isDeleting = null,Object? error = freezed,}) {
  return _then(_S3State(
files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<VirtualFile>,availableTags: null == availableTags ? _self._availableTags : availableTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,availableSessions: null == availableSessions ? _self._availableSessions : availableSessions // ignore: cast_nullable_to_non_nullable
as List<Session>,selectedTags: null == selectedTags ? _self._selectedTags : selectedTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,selectedSession: freezed == selectedSession ? _self.selectedSession : selectedSession // ignore: cast_nullable_to_non_nullable
as Session?,selectedFilePaths: null == selectedFilePaths ? _self._selectedFilePaths : selectedFilePaths // ignore: cast_nullable_to_non_nullable
as Set<String>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isDeleting: null == isDeleting ? _self.isDeleting : isDeleting // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of S3State
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCopyWith<$Res>? get selectedSession {
    if (_self.selectedSession == null) {
    return null;
  }

  return $SessionCopyWith<$Res>(_self.selectedSession!, (value) {
    return _then(_self.copyWith(selectedSession: value));
  });
}
}

// dart format on
