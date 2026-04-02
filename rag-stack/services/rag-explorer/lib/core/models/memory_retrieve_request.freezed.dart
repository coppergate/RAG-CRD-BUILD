// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_retrieve_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MemoryRetrieveRequest _$MemoryRetrieveRequestFromJson(
    Map<String, dynamic> json) {
  return _MemoryRetrieveRequest.fromJson(json);
}

/// @nodoc
mixin _$MemoryRetrieveRequest {
  String get query => throw _privateConstructorUsedError;
  String? get sessionId => throw _privateConstructorUsedError;
  String? get userId => throw _privateConstructorUsedError;
  int get limit => throw _privateConstructorUsedError;
  Map<String, dynamic>? get filters => throw _privateConstructorUsedError;

  /// Serializes this MemoryRetrieveRequest to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MemoryRetrieveRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MemoryRetrieveRequestCopyWith<MemoryRetrieveRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MemoryRetrieveRequestCopyWith<$Res> {
  factory $MemoryRetrieveRequestCopyWith(MemoryRetrieveRequest value,
          $Res Function(MemoryRetrieveRequest) then) =
      _$MemoryRetrieveRequestCopyWithImpl<$Res, MemoryRetrieveRequest>;
  @useResult
  $Res call(
      {String query,
      String? sessionId,
      String? userId,
      int limit,
      Map<String, dynamic>? filters});
}

/// @nodoc
class _$MemoryRetrieveRequestCopyWithImpl<$Res,
        $Val extends MemoryRetrieveRequest>
    implements $MemoryRetrieveRequestCopyWith<$Res> {
  _$MemoryRetrieveRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MemoryRetrieveRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? query = null,
    Object? sessionId = freezed,
    Object? userId = freezed,
    Object? limit = null,
    Object? filters = freezed,
  }) {
    return _then(_value.copyWith(
      query: null == query
          ? _value.query
          : query // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      userId: freezed == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String?,
      limit: null == limit
          ? _value.limit
          : limit // ignore: cast_nullable_to_non_nullable
              as int,
      filters: freezed == filters
          ? _value.filters
          : filters // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MemoryRetrieveRequestImplCopyWith<$Res>
    implements $MemoryRetrieveRequestCopyWith<$Res> {
  factory _$$MemoryRetrieveRequestImplCopyWith(
          _$MemoryRetrieveRequestImpl value,
          $Res Function(_$MemoryRetrieveRequestImpl) then) =
      __$$MemoryRetrieveRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String query,
      String? sessionId,
      String? userId,
      int limit,
      Map<String, dynamic>? filters});
}

/// @nodoc
class __$$MemoryRetrieveRequestImplCopyWithImpl<$Res>
    extends _$MemoryRetrieveRequestCopyWithImpl<$Res,
        _$MemoryRetrieveRequestImpl>
    implements _$$MemoryRetrieveRequestImplCopyWith<$Res> {
  __$$MemoryRetrieveRequestImplCopyWithImpl(_$MemoryRetrieveRequestImpl _value,
      $Res Function(_$MemoryRetrieveRequestImpl) _then)
      : super(_value, _then);

  /// Create a copy of MemoryRetrieveRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? query = null,
    Object? sessionId = freezed,
    Object? userId = freezed,
    Object? limit = null,
    Object? filters = freezed,
  }) {
    return _then(_$MemoryRetrieveRequestImpl(
      query: null == query
          ? _value.query
          : query // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      userId: freezed == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String?,
      limit: null == limit
          ? _value.limit
          : limit // ignore: cast_nullable_to_non_nullable
              as int,
      filters: freezed == filters
          ? _value._filters
          : filters // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MemoryRetrieveRequestImpl implements _MemoryRetrieveRequest {
  const _$MemoryRetrieveRequestImpl(
      {required this.query,
      this.sessionId,
      this.userId,
      this.limit = 10,
      final Map<String, dynamic>? filters})
      : _filters = filters;

  factory _$MemoryRetrieveRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$MemoryRetrieveRequestImplFromJson(json);

  @override
  final String query;
  @override
  final String? sessionId;
  @override
  final String? userId;
  @override
  @JsonKey()
  final int limit;
  final Map<String, dynamic>? _filters;
  @override
  Map<String, dynamic>? get filters {
    final value = _filters;
    if (value == null) return null;
    if (_filters is EqualUnmodifiableMapView) return _filters;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'MemoryRetrieveRequest(query: $query, sessionId: $sessionId, userId: $userId, limit: $limit, filters: $filters)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MemoryRetrieveRequestImpl &&
            (identical(other.query, query) || other.query == query) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.limit, limit) || other.limit == limit) &&
            const DeepCollectionEquality().equals(other._filters, _filters));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, query, sessionId, userId, limit,
      const DeepCollectionEquality().hash(_filters));

  /// Create a copy of MemoryRetrieveRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MemoryRetrieveRequestImplCopyWith<_$MemoryRetrieveRequestImpl>
      get copyWith => __$$MemoryRetrieveRequestImplCopyWithImpl<
          _$MemoryRetrieveRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MemoryRetrieveRequestImplToJson(
      this,
    );
  }
}

abstract class _MemoryRetrieveRequest implements MemoryRetrieveRequest {
  const factory _MemoryRetrieveRequest(
      {required final String query,
      final String? sessionId,
      final String? userId,
      final int limit,
      final Map<String, dynamic>? filters}) = _$MemoryRetrieveRequestImpl;

  factory _MemoryRetrieveRequest.fromJson(Map<String, dynamic> json) =
      _$MemoryRetrieveRequestImpl.fromJson;

  @override
  String get query;
  @override
  String? get sessionId;
  @override
  String? get userId;
  @override
  int get limit;
  @override
  Map<String, dynamic>? get filters;

  /// Create a copy of MemoryRetrieveRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MemoryRetrieveRequestImplCopyWith<_$MemoryRetrieveRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}
