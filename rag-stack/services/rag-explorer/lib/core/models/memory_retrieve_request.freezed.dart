// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_retrieve_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MemoryRetrieveRequest {

 String get query; String? get sessionId; String? get userId; int get limit; Map<String, dynamic>? get filters;
/// Create a copy of MemoryRetrieveRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoryRetrieveRequestCopyWith<MemoryRetrieveRequest> get copyWith => _$MemoryRetrieveRequestCopyWithImpl<MemoryRetrieveRequest>(this as MemoryRetrieveRequest, _$identity);

  /// Serializes this MemoryRetrieveRequest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemoryRetrieveRequest&&(identical(other.query, query) || other.query == query)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.limit, limit) || other.limit == limit)&&const DeepCollectionEquality().equals(other.filters, filters));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,query,sessionId,userId,limit,const DeepCollectionEquality().hash(filters));

@override
String toString() {
  return 'MemoryRetrieveRequest(query: $query, sessionId: $sessionId, userId: $userId, limit: $limit, filters: $filters)';
}


}

/// @nodoc
abstract mixin class $MemoryRetrieveRequestCopyWith<$Res>  {
  factory $MemoryRetrieveRequestCopyWith(MemoryRetrieveRequest value, $Res Function(MemoryRetrieveRequest) _then) = _$MemoryRetrieveRequestCopyWithImpl;
@useResult
$Res call({
 String query, String? sessionId, String? userId, int limit, Map<String, dynamic>? filters
});




}
/// @nodoc
class _$MemoryRetrieveRequestCopyWithImpl<$Res>
    implements $MemoryRetrieveRequestCopyWith<$Res> {
  _$MemoryRetrieveRequestCopyWithImpl(this._self, this._then);

  final MemoryRetrieveRequest _self;
  final $Res Function(MemoryRetrieveRequest) _then;

/// Create a copy of MemoryRetrieveRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? query = null,Object? sessionId = freezed,Object? userId = freezed,Object? limit = null,Object? filters = freezed,}) {
  return _then(_self.copyWith(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String?,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,filters: freezed == filters ? _self.filters : filters // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [MemoryRetrieveRequest].
extension MemoryRetrieveRequestPatterns on MemoryRetrieveRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemoryRetrieveRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemoryRetrieveRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemoryRetrieveRequest value)  $default,){
final _that = this;
switch (_that) {
case _MemoryRetrieveRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemoryRetrieveRequest value)?  $default,){
final _that = this;
switch (_that) {
case _MemoryRetrieveRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String query,  String? sessionId,  String? userId,  int limit,  Map<String, dynamic>? filters)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemoryRetrieveRequest() when $default != null:
return $default(_that.query,_that.sessionId,_that.userId,_that.limit,_that.filters);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String query,  String? sessionId,  String? userId,  int limit,  Map<String, dynamic>? filters)  $default,) {final _that = this;
switch (_that) {
case _MemoryRetrieveRequest():
return $default(_that.query,_that.sessionId,_that.userId,_that.limit,_that.filters);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String query,  String? sessionId,  String? userId,  int limit,  Map<String, dynamic>? filters)?  $default,) {final _that = this;
switch (_that) {
case _MemoryRetrieveRequest() when $default != null:
return $default(_that.query,_that.sessionId,_that.userId,_that.limit,_that.filters);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MemoryRetrieveRequest implements MemoryRetrieveRequest {
  const _MemoryRetrieveRequest({required this.query, this.sessionId, this.userId, this.limit = 10, final  Map<String, dynamic>? filters}): _filters = filters;
  factory _MemoryRetrieveRequest.fromJson(Map<String, dynamic> json) => _$MemoryRetrieveRequestFromJson(json);

@override final  String query;
@override final  String? sessionId;
@override final  String? userId;
@override@JsonKey() final  int limit;
 final  Map<String, dynamic>? _filters;
@override Map<String, dynamic>? get filters {
  final value = _filters;
  if (value == null) return null;
  if (_filters is EqualUnmodifiableMapView) return _filters;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of MemoryRetrieveRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoryRetrieveRequestCopyWith<_MemoryRetrieveRequest> get copyWith => __$MemoryRetrieveRequestCopyWithImpl<_MemoryRetrieveRequest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemoryRetrieveRequestToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemoryRetrieveRequest&&(identical(other.query, query) || other.query == query)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.limit, limit) || other.limit == limit)&&const DeepCollectionEquality().equals(other._filters, _filters));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,query,sessionId,userId,limit,const DeepCollectionEquality().hash(_filters));

@override
String toString() {
  return 'MemoryRetrieveRequest(query: $query, sessionId: $sessionId, userId: $userId, limit: $limit, filters: $filters)';
}


}

/// @nodoc
abstract mixin class _$MemoryRetrieveRequestCopyWith<$Res> implements $MemoryRetrieveRequestCopyWith<$Res> {
  factory _$MemoryRetrieveRequestCopyWith(_MemoryRetrieveRequest value, $Res Function(_MemoryRetrieveRequest) _then) = __$MemoryRetrieveRequestCopyWithImpl;
@override @useResult
$Res call({
 String query, String? sessionId, String? userId, int limit, Map<String, dynamic>? filters
});




}
/// @nodoc
class __$MemoryRetrieveRequestCopyWithImpl<$Res>
    implements _$MemoryRetrieveRequestCopyWith<$Res> {
  __$MemoryRetrieveRequestCopyWithImpl(this._self, this._then);

  final _MemoryRetrieveRequest _self;
  final $Res Function(_MemoryRetrieveRequest) _then;

/// Create a copy of MemoryRetrieveRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? query = null,Object? sessionId = freezed,Object? userId = freezed,Object? limit = null,Object? filters = freezed,}) {
  return _then(_MemoryRetrieveRequest(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String?,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,filters: freezed == filters ? _self._filters : filters // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}

// dart format on
