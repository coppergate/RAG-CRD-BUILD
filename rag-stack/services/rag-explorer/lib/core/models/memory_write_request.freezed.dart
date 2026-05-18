// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_write_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemoryWriteRequest {

 String get content; String get type; double? get salience; int? get sessionId; String? get userId; Map<String, dynamic>? get metadata;
/// Create a copy of MemoryWriteRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoryWriteRequestCopyWith<MemoryWriteRequest> get copyWith => _$MemoryWriteRequestCopyWithImpl<MemoryWriteRequest>(this as MemoryWriteRequest, _$identity);

  /// Serializes this MemoryWriteRequest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemoryWriteRequest&&(identical(other.content, content) || other.content == content)&&(identical(other.type, type) || other.type == type)&&(identical(other.salience, salience) || other.salience == salience)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.userId, userId) || other.userId == userId)&&const DeepCollectionEquality().equals(other.metadata, metadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,content,type,salience,sessionId,userId,const DeepCollectionEquality().hash(metadata));

@override
String toString() {
  return 'MemoryWriteRequest(content: $content, type: $type, salience: $salience, sessionId: $sessionId, userId: $userId, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class $MemoryWriteRequestCopyWith<$Res>  {
  factory $MemoryWriteRequestCopyWith(MemoryWriteRequest value, $Res Function(MemoryWriteRequest) _then) = _$MemoryWriteRequestCopyWithImpl;
@useResult
$Res call({
 String content, String type, double? salience, int? sessionId, String? userId, Map<String, dynamic>? metadata
});




}
/// @nodoc
class _$MemoryWriteRequestCopyWithImpl<$Res>
    implements $MemoryWriteRequestCopyWith<$Res> {
  _$MemoryWriteRequestCopyWithImpl(this._self, this._then);

  final MemoryWriteRequest _self;
  final $Res Function(MemoryWriteRequest) _then;

/// Create a copy of MemoryWriteRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? content = null,Object? type = null,Object? salience = freezed,Object? sessionId = freezed,Object? userId = freezed,Object? metadata = freezed,}) {
  return _then(_self.copyWith(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,salience: freezed == salience ? _self.salience : salience // ignore: cast_nullable_to_non_nullable
as double?,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [MemoryWriteRequest].
extension MemoryWriteRequestPatterns on MemoryWriteRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemoryWriteRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemoryWriteRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemoryWriteRequest value)  $default,){
final _that = this;
switch (_that) {
case _MemoryWriteRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemoryWriteRequest value)?  $default,){
final _that = this;
switch (_that) {
case _MemoryWriteRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String content,  String type,  double? salience,  int? sessionId,  String? userId,  Map<String, dynamic>? metadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemoryWriteRequest() when $default != null:
return $default(_that.content,_that.type,_that.salience,_that.sessionId,_that.userId,_that.metadata);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String content,  String type,  double? salience,  int? sessionId,  String? userId,  Map<String, dynamic>? metadata)  $default,) {final _that = this;
switch (_that) {
case _MemoryWriteRequest():
return $default(_that.content,_that.type,_that.salience,_that.sessionId,_that.userId,_that.metadata);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String content,  String type,  double? salience,  int? sessionId,  String? userId,  Map<String, dynamic>? metadata)?  $default,) {final _that = this;
switch (_that) {
case _MemoryWriteRequest() when $default != null:
return $default(_that.content,_that.type,_that.salience,_that.sessionId,_that.userId,_that.metadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemoryWriteRequest implements MemoryWriteRequest {
  const _MemoryWriteRequest({required this.content, this.type = 'short', this.salience, this.sessionId, this.userId, final  Map<String, dynamic>? metadata}): _metadata = metadata;
  factory _MemoryWriteRequest.fromJson(Map<String, dynamic> json) => _$MemoryWriteRequestFromJson(json);

@override final  String content;
@override@JsonKey() final  String type;
@override final  double? salience;
@override final  int? sessionId;
@override final  String? userId;
 final  Map<String, dynamic>? _metadata;
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of MemoryWriteRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoryWriteRequestCopyWith<_MemoryWriteRequest> get copyWith => __$MemoryWriteRequestCopyWithImpl<_MemoryWriteRequest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemoryWriteRequestToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemoryWriteRequest&&(identical(other.content, content) || other.content == content)&&(identical(other.type, type) || other.type == type)&&(identical(other.salience, salience) || other.salience == salience)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.userId, userId) || other.userId == userId)&&const DeepCollectionEquality().equals(other._metadata, _metadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,content,type,salience,sessionId,userId,const DeepCollectionEquality().hash(_metadata));

@override
String toString() {
  return 'MemoryWriteRequest(content: $content, type: $type, salience: $salience, sessionId: $sessionId, userId: $userId, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class _$MemoryWriteRequestCopyWith<$Res> implements $MemoryWriteRequestCopyWith<$Res> {
  factory _$MemoryWriteRequestCopyWith(_MemoryWriteRequest value, $Res Function(_MemoryWriteRequest) _then) = __$MemoryWriteRequestCopyWithImpl;
@override @useResult
$Res call({
 String content, String type, double? salience, int? sessionId, String? userId, Map<String, dynamic>? metadata
});




}
/// @nodoc
class __$MemoryWriteRequestCopyWithImpl<$Res>
    implements _$MemoryWriteRequestCopyWith<$Res> {
  __$MemoryWriteRequestCopyWithImpl(this._self, this._then);

  final _MemoryWriteRequest _self;
  final $Res Function(_MemoryWriteRequest) _then;

/// Create a copy of MemoryWriteRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? content = null,Object? type = null,Object? salience = freezed,Object? sessionId = freezed,Object? userId = freezed,Object? metadata = freezed,}) {
  return _then(_MemoryWriteRequest(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,salience: freezed == salience ? _self.salience : salience // ignore: cast_nullable_to_non_nullable
as double?,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}

// dart format on
