// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_pack.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemoryPack {

 List<dynamic> get memories; Map<String, dynamic> get metadata;
/// Create a copy of MemoryPack
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoryPackCopyWith<MemoryPack> get copyWith => _$MemoryPackCopyWithImpl<MemoryPack>(this as MemoryPack, _$identity);

  /// Serializes this MemoryPack to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemoryPack&&const DeepCollectionEquality().equals(other.memories, memories)&&const DeepCollectionEquality().equals(other.metadata, metadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(memories),const DeepCollectionEquality().hash(metadata));

@override
String toString() {
  return 'MemoryPack(memories: $memories, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class $MemoryPackCopyWith<$Res>  {
  factory $MemoryPackCopyWith(MemoryPack value, $Res Function(MemoryPack) _then) = _$MemoryPackCopyWithImpl;
@useResult
$Res call({
 List<dynamic> memories, Map<String, dynamic> metadata
});




}
/// @nodoc
class _$MemoryPackCopyWithImpl<$Res>
    implements $MemoryPackCopyWith<$Res> {
  _$MemoryPackCopyWithImpl(this._self, this._then);

  final MemoryPack _self;
  final $Res Function(MemoryPack) _then;

/// Create a copy of MemoryPack
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? memories = null,Object? metadata = null,}) {
  return _then(_self.copyWith(
memories: null == memories ? _self.memories : memories // ignore: cast_nullable_to_non_nullable
as List<dynamic>,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [MemoryPack].
extension MemoryPackPatterns on MemoryPack {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemoryPack value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemoryPack() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemoryPack value)  $default,){
final _that = this;
switch (_that) {
case _MemoryPack():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemoryPack value)?  $default,){
final _that = this;
switch (_that) {
case _MemoryPack() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<dynamic> memories,  Map<String, dynamic> metadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemoryPack() when $default != null:
return $default(_that.memories,_that.metadata);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<dynamic> memories,  Map<String, dynamic> metadata)  $default,) {final _that = this;
switch (_that) {
case _MemoryPack():
return $default(_that.memories,_that.metadata);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<dynamic> memories,  Map<String, dynamic> metadata)?  $default,) {final _that = this;
switch (_that) {
case _MemoryPack() when $default != null:
return $default(_that.memories,_that.metadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemoryPack implements MemoryPack {
  const _MemoryPack({required final  List<dynamic> memories, required final  Map<String, dynamic> metadata}): _memories = memories,_metadata = metadata;
  factory _MemoryPack.fromJson(Map<String, dynamic> json) => _$MemoryPackFromJson(json);

 final  List<dynamic> _memories;
@override List<dynamic> get memories {
  if (_memories is EqualUnmodifiableListView) return _memories;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_memories);
}

 final  Map<String, dynamic> _metadata;
@override Map<String, dynamic> get metadata {
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_metadata);
}


/// Create a copy of MemoryPack
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoryPackCopyWith<_MemoryPack> get copyWith => __$MemoryPackCopyWithImpl<_MemoryPack>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemoryPackToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemoryPack&&const DeepCollectionEquality().equals(other._memories, _memories)&&const DeepCollectionEquality().equals(other._metadata, _metadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_memories),const DeepCollectionEquality().hash(_metadata));

@override
String toString() {
  return 'MemoryPack(memories: $memories, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class _$MemoryPackCopyWith<$Res> implements $MemoryPackCopyWith<$Res> {
  factory _$MemoryPackCopyWith(_MemoryPack value, $Res Function(_MemoryPack) _then) = __$MemoryPackCopyWithImpl;
@override @useResult
$Res call({
 List<dynamic> memories, Map<String, dynamic> metadata
});




}
/// @nodoc
class __$MemoryPackCopyWithImpl<$Res>
    implements _$MemoryPackCopyWith<$Res> {
  __$MemoryPackCopyWithImpl(this._self, this._then);

  final _MemoryPack _self;
  final $Res Function(_MemoryPack) _then;

/// Create a copy of MemoryPack
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? memories = null,Object? metadata = null,}) {
  return _then(_MemoryPack(
memories: null == memories ? _self._memories : memories // ignore: cast_nullable_to_non_nullable
as List<dynamic>,metadata: null == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

// dart format on
