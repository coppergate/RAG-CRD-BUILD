// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MemoryState {

 int? get sessionId; List<dynamic> get items; MemoryPack? get retrievedPack; bool get isLoading; String? get error;
/// Create a copy of MemoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoryStateCopyWith<MemoryState> get copyWith => _$MemoryStateCopyWithImpl<MemoryState>(this as MemoryState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemoryState&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.retrievedPack, retrievedPack) || other.retrievedPack == retrievedPack)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(items),retrievedPack,isLoading,error);

@override
String toString() {
  return 'MemoryState(sessionId: $sessionId, items: $items, retrievedPack: $retrievedPack, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class $MemoryStateCopyWith<$Res>  {
  factory $MemoryStateCopyWith(MemoryState value, $Res Function(MemoryState) _then) = _$MemoryStateCopyWithImpl;
@useResult
$Res call({
 int? sessionId, List<dynamic> items, MemoryPack? retrievedPack, bool isLoading, String? error
});


$MemoryPackCopyWith<$Res>? get retrievedPack;

}
/// @nodoc
class _$MemoryStateCopyWithImpl<$Res>
    implements $MemoryStateCopyWith<$Res> {
  _$MemoryStateCopyWithImpl(this._self, this._then);

  final MemoryState _self;
  final $Res Function(MemoryState) _then;

/// Create a copy of MemoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = freezed,Object? items = null,Object? retrievedPack = freezed,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<dynamic>,retrievedPack: freezed == retrievedPack ? _self.retrievedPack : retrievedPack // ignore: cast_nullable_to_non_nullable
as MemoryPack?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of MemoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MemoryPackCopyWith<$Res>? get retrievedPack {
    if (_self.retrievedPack == null) {
    return null;
  }

  return $MemoryPackCopyWith<$Res>(_self.retrievedPack!, (value) {
    return _then(_self.copyWith(retrievedPack: value));
  });
}
}


/// Adds pattern-matching-related methods to [MemoryState].
extension MemoryStatePatterns on MemoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemoryState value)  $default,){
final _that = this;
switch (_that) {
case _MemoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemoryState value)?  $default,){
final _that = this;
switch (_that) {
case _MemoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? sessionId,  List<dynamic> items,  MemoryPack? retrievedPack,  bool isLoading,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemoryState() when $default != null:
return $default(_that.sessionId,_that.items,_that.retrievedPack,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? sessionId,  List<dynamic> items,  MemoryPack? retrievedPack,  bool isLoading,  String? error)  $default,) {final _that = this;
switch (_that) {
case _MemoryState():
return $default(_that.sessionId,_that.items,_that.retrievedPack,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? sessionId,  List<dynamic> items,  MemoryPack? retrievedPack,  bool isLoading,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _MemoryState() when $default != null:
return $default(_that.sessionId,_that.items,_that.retrievedPack,_that.isLoading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _MemoryState implements MemoryState {
  const _MemoryState({this.sessionId, final  List<dynamic> items = const [], this.retrievedPack, this.isLoading = false, this.error}): _items = items;
  

@override final  int? sessionId;
 final  List<dynamic> _items;
@override@JsonKey() List<dynamic> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  MemoryPack? retrievedPack;
@override@JsonKey() final  bool isLoading;
@override final  String? error;

/// Create a copy of MemoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoryStateCopyWith<_MemoryState> get copyWith => __$MemoryStateCopyWithImpl<_MemoryState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemoryState&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.retrievedPack, retrievedPack) || other.retrievedPack == retrievedPack)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(_items),retrievedPack,isLoading,error);

@override
String toString() {
  return 'MemoryState(sessionId: $sessionId, items: $items, retrievedPack: $retrievedPack, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$MemoryStateCopyWith<$Res> implements $MemoryStateCopyWith<$Res> {
  factory _$MemoryStateCopyWith(_MemoryState value, $Res Function(_MemoryState) _then) = __$MemoryStateCopyWithImpl;
@override @useResult
$Res call({
 int? sessionId, List<dynamic> items, MemoryPack? retrievedPack, bool isLoading, String? error
});


@override $MemoryPackCopyWith<$Res>? get retrievedPack;

}
/// @nodoc
class __$MemoryStateCopyWithImpl<$Res>
    implements _$MemoryStateCopyWith<$Res> {
  __$MemoryStateCopyWithImpl(this._self, this._then);

  final _MemoryState _self;
  final $Res Function(_MemoryState) _then;

/// Create a copy of MemoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = freezed,Object? items = null,Object? retrievedPack = freezed,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_MemoryState(
sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<dynamic>,retrievedPack: freezed == retrievedPack ? _self.retrievedPack : retrievedPack // ignore: cast_nullable_to_non_nullable
as MemoryPack?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of MemoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MemoryPackCopyWith<$Res>? get retrievedPack {
    if (_self.retrievedPack == null) {
    return null;
  }

  return $MemoryPackCopyWith<$Res>(_self.retrievedPack!, (value) {
    return _then(_self.copyWith(retrievedPack: value));
  });
}
}

// dart format on
