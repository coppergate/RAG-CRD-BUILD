// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'qdrant_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QdrantState {

 List<Map<String, dynamic>> get collections; bool get isLoading;
/// Create a copy of QdrantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QdrantStateCopyWith<QdrantState> get copyWith => _$QdrantStateCopyWithImpl<QdrantState>(this as QdrantState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QdrantState&&const DeepCollectionEquality().equals(other.collections, collections)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(collections),isLoading);

@override
String toString() {
  return 'QdrantState(collections: $collections, isLoading: $isLoading)';
}


}

/// @nodoc
abstract mixin class $QdrantStateCopyWith<$Res>  {
  factory $QdrantStateCopyWith(QdrantState value, $Res Function(QdrantState) _then) = _$QdrantStateCopyWithImpl;
@useResult
$Res call({
 List<Map<String, dynamic>> collections, bool isLoading
});




}
/// @nodoc
class _$QdrantStateCopyWithImpl<$Res>
    implements $QdrantStateCopyWith<$Res> {
  _$QdrantStateCopyWithImpl(this._self, this._then);

  final QdrantState _self;
  final $Res Function(QdrantState) _then;

/// Create a copy of QdrantState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collections = null,Object? isLoading = null,}) {
  return _then(_self.copyWith(
collections: null == collections ? _self.collections : collections // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [QdrantState].
extension QdrantStatePatterns on QdrantState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QdrantState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QdrantState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QdrantState value)  $default,){
final _that = this;
switch (_that) {
case _QdrantState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QdrantState value)?  $default,){
final _that = this;
switch (_that) {
case _QdrantState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Map<String, dynamic>> collections,  bool isLoading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QdrantState() when $default != null:
return $default(_that.collections,_that.isLoading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Map<String, dynamic>> collections,  bool isLoading)  $default,) {final _that = this;
switch (_that) {
case _QdrantState():
return $default(_that.collections,_that.isLoading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Map<String, dynamic>> collections,  bool isLoading)?  $default,) {final _that = this;
switch (_that) {
case _QdrantState() when $default != null:
return $default(_that.collections,_that.isLoading);case _:
  return null;

}
}

}

/// @nodoc


class _QdrantState implements QdrantState {
  const _QdrantState({final  List<Map<String, dynamic>> collections = const [], this.isLoading = false}): _collections = collections;
  

 final  List<Map<String, dynamic>> _collections;
@override@JsonKey() List<Map<String, dynamic>> get collections {
  if (_collections is EqualUnmodifiableListView) return _collections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_collections);
}

@override@JsonKey() final  bool isLoading;

/// Create a copy of QdrantState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QdrantStateCopyWith<_QdrantState> get copyWith => __$QdrantStateCopyWithImpl<_QdrantState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QdrantState&&const DeepCollectionEquality().equals(other._collections, _collections)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_collections),isLoading);

@override
String toString() {
  return 'QdrantState(collections: $collections, isLoading: $isLoading)';
}


}

/// @nodoc
abstract mixin class _$QdrantStateCopyWith<$Res> implements $QdrantStateCopyWith<$Res> {
  factory _$QdrantStateCopyWith(_QdrantState value, $Res Function(_QdrantState) _then) = __$QdrantStateCopyWithImpl;
@override @useResult
$Res call({
 List<Map<String, dynamic>> collections, bool isLoading
});




}
/// @nodoc
class __$QdrantStateCopyWithImpl<$Res>
    implements _$QdrantStateCopyWith<$Res> {
  __$QdrantStateCopyWithImpl(this._self, this._then);

  final _QdrantState _self;
  final $Res Function(_QdrantState) _then;

/// Create a copy of QdrantState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? collections = null,Object? isLoading = null,}) {
  return _then(_QdrantState(
collections: null == collections ? _self._collections : collections // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
