// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Session {

@JsonKey(name: 'created_at') DateTime get createdAt; String? get description; int get id;@JsonKey(name: 'last_active_at') DateTime get lastActiveAt; Map<String, dynamic>? get metadata; String? get name; List<Tag>? get tags;
/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCopyWith<Session> get copyWith => _$SessionCopyWithImpl<Session>(this as Session, _$identity);

  /// Serializes this Session to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Session&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.description, description) || other.description == description)&&(identical(other.id, id) || other.id == id)&&(identical(other.lastActiveAt, lastActiveAt) || other.lastActiveAt == lastActiveAt)&&const DeepCollectionEquality().equals(other.metadata, metadata)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.tags, tags));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,createdAt,description,id,lastActiveAt,const DeepCollectionEquality().hash(metadata),name,const DeepCollectionEquality().hash(tags));

@override
String toString() {
  return 'Session(createdAt: $createdAt, description: $description, id: $id, lastActiveAt: $lastActiveAt, metadata: $metadata, name: $name, tags: $tags)';
}


}

/// @nodoc
abstract mixin class $SessionCopyWith<$Res>  {
  factory $SessionCopyWith(Session value, $Res Function(Session) _then) = _$SessionCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'created_at') DateTime createdAt, String? description, int id,@JsonKey(name: 'last_active_at') DateTime lastActiveAt, Map<String, dynamic>? metadata, String? name, List<Tag>? tags
});




}
/// @nodoc
class _$SessionCopyWithImpl<$Res>
    implements $SessionCopyWith<$Res> {
  _$SessionCopyWithImpl(this._self, this._then);

  final Session _self;
  final $Res Function(Session) _then;

/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? createdAt = null,Object? description = freezed,Object? id = null,Object? lastActiveAt = null,Object? metadata = freezed,Object? name = freezed,Object? tags = freezed,}) {
  return _then(_self.copyWith(
createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,lastActiveAt: null == lastActiveAt ? _self.lastActiveAt : lastActiveAt // ignore: cast_nullable_to_non_nullable
as DateTime,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,tags: freezed == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<Tag>?,
  ));
}

}


/// Adds pattern-matching-related methods to [Session].
extension SessionPatterns on Session {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Session value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Session() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Session value)  $default,){
final _that = this;
switch (_that) {
case _Session():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Session value)?  $default,){
final _that = this;
switch (_that) {
case _Session() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'created_at')  DateTime createdAt,  String? description,  int id, @JsonKey(name: 'last_active_at')  DateTime lastActiveAt,  Map<String, dynamic>? metadata,  String? name,  List<Tag>? tags)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Session() when $default != null:
return $default(_that.createdAt,_that.description,_that.id,_that.lastActiveAt,_that.metadata,_that.name,_that.tags);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'created_at')  DateTime createdAt,  String? description,  int id, @JsonKey(name: 'last_active_at')  DateTime lastActiveAt,  Map<String, dynamic>? metadata,  String? name,  List<Tag>? tags)  $default,) {final _that = this;
switch (_that) {
case _Session():
return $default(_that.createdAt,_that.description,_that.id,_that.lastActiveAt,_that.metadata,_that.name,_that.tags);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'created_at')  DateTime createdAt,  String? description,  int id, @JsonKey(name: 'last_active_at')  DateTime lastActiveAt,  Map<String, dynamic>? metadata,  String? name,  List<Tag>? tags)?  $default,) {final _that = this;
switch (_that) {
case _Session() when $default != null:
return $default(_that.createdAt,_that.description,_that.id,_that.lastActiveAt,_that.metadata,_that.name,_that.tags);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Session implements Session {
  const _Session({@JsonKey(name: 'created_at') required this.createdAt, this.description, this.id = 0, @JsonKey(name: 'last_active_at') required this.lastActiveAt, final  Map<String, dynamic>? metadata, this.name, final  List<Tag>? tags}): _metadata = metadata,_tags = tags;
  factory _Session.fromJson(Map<String, dynamic> json) => _$SessionFromJson(json);

@override@JsonKey(name: 'created_at') final  DateTime createdAt;
@override final  String? description;
@override@JsonKey() final  int id;
@override@JsonKey(name: 'last_active_at') final  DateTime lastActiveAt;
 final  Map<String, dynamic>? _metadata;
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  String? name;
 final  List<Tag>? _tags;
@override List<Tag>? get tags {
  final value = _tags;
  if (value == null) return null;
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCopyWith<_Session> get copyWith => __$SessionCopyWithImpl<_Session>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Session&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.description, description) || other.description == description)&&(identical(other.id, id) || other.id == id)&&(identical(other.lastActiveAt, lastActiveAt) || other.lastActiveAt == lastActiveAt)&&const DeepCollectionEquality().equals(other._metadata, _metadata)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._tags, _tags));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,createdAt,description,id,lastActiveAt,const DeepCollectionEquality().hash(_metadata),name,const DeepCollectionEquality().hash(_tags));

@override
String toString() {
  return 'Session(createdAt: $createdAt, description: $description, id: $id, lastActiveAt: $lastActiveAt, metadata: $metadata, name: $name, tags: $tags)';
}


}

/// @nodoc
abstract mixin class _$SessionCopyWith<$Res> implements $SessionCopyWith<$Res> {
  factory _$SessionCopyWith(_Session value, $Res Function(_Session) _then) = __$SessionCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'created_at') DateTime createdAt, String? description, int id,@JsonKey(name: 'last_active_at') DateTime lastActiveAt, Map<String, dynamic>? metadata, String? name, List<Tag>? tags
});




}
/// @nodoc
class __$SessionCopyWithImpl<$Res>
    implements _$SessionCopyWith<$Res> {
  __$SessionCopyWithImpl(this._self, this._then);

  final _Session _self;
  final $Res Function(_Session) _then;

/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? createdAt = null,Object? description = freezed,Object? id = null,Object? lastActiveAt = null,Object? metadata = freezed,Object? name = freezed,Object? tags = freezed,}) {
  return _then(_Session(
createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,lastActiveAt: null == lastActiveAt ? _self.lastActiveAt : lastActiveAt // ignore: cast_nullable_to_non_nullable
as DateTime,metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,tags: freezed == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<Tag>?,
  ));
}


}

// dart format on
