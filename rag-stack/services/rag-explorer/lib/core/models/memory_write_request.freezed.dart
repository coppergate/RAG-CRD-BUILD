// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_write_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MemoryWriteRequest _$MemoryWriteRequestFromJson(Map<String, dynamic> json) {
  return _MemoryWriteRequest.fromJson(json);
}

/// @nodoc
mixin _$MemoryWriteRequest {
  String get content => throw _privateConstructorUsedError;
  String get type => throw _privateConstructorUsedError;
  double? get salience => throw _privateConstructorUsedError;
  String? get sessionId => throw _privateConstructorUsedError;
  String? get userId => throw _privateConstructorUsedError;
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;

  /// Serializes this MemoryWriteRequest to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MemoryWriteRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MemoryWriteRequestCopyWith<MemoryWriteRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MemoryWriteRequestCopyWith<$Res> {
  factory $MemoryWriteRequestCopyWith(
          MemoryWriteRequest value, $Res Function(MemoryWriteRequest) then) =
      _$MemoryWriteRequestCopyWithImpl<$Res, MemoryWriteRequest>;
  @useResult
  $Res call(
      {String content,
      String type,
      double? salience,
      String? sessionId,
      String? userId,
      Map<String, dynamic>? metadata});
}

/// @nodoc
class _$MemoryWriteRequestCopyWithImpl<$Res, $Val extends MemoryWriteRequest>
    implements $MemoryWriteRequestCopyWith<$Res> {
  _$MemoryWriteRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MemoryWriteRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? content = null,
    Object? type = null,
    Object? salience = freezed,
    Object? sessionId = freezed,
    Object? userId = freezed,
    Object? metadata = freezed,
  }) {
    return _then(_value.copyWith(
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      salience: freezed == salience
          ? _value.salience
          : salience // ignore: cast_nullable_to_non_nullable
              as double?,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      userId: freezed == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MemoryWriteRequestImplCopyWith<$Res>
    implements $MemoryWriteRequestCopyWith<$Res> {
  factory _$$MemoryWriteRequestImplCopyWith(_$MemoryWriteRequestImpl value,
          $Res Function(_$MemoryWriteRequestImpl) then) =
      __$$MemoryWriteRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String content,
      String type,
      double? salience,
      String? sessionId,
      String? userId,
      Map<String, dynamic>? metadata});
}

/// @nodoc
class __$$MemoryWriteRequestImplCopyWithImpl<$Res>
    extends _$MemoryWriteRequestCopyWithImpl<$Res, _$MemoryWriteRequestImpl>
    implements _$$MemoryWriteRequestImplCopyWith<$Res> {
  __$$MemoryWriteRequestImplCopyWithImpl(_$MemoryWriteRequestImpl _value,
      $Res Function(_$MemoryWriteRequestImpl) _then)
      : super(_value, _then);

  /// Create a copy of MemoryWriteRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? content = null,
    Object? type = null,
    Object? salience = freezed,
    Object? sessionId = freezed,
    Object? userId = freezed,
    Object? metadata = freezed,
  }) {
    return _then(_$MemoryWriteRequestImpl(
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      salience: freezed == salience
          ? _value.salience
          : salience // ignore: cast_nullable_to_non_nullable
              as double?,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      userId: freezed == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MemoryWriteRequestImpl implements _MemoryWriteRequest {
  const _$MemoryWriteRequestImpl(
      {required this.content,
      this.type = 'short',
      this.salience,
      this.sessionId,
      this.userId,
      final Map<String, dynamic>? metadata})
      : _metadata = metadata;

  factory _$MemoryWriteRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$MemoryWriteRequestImplFromJson(json);

  @override
  final String content;
  @override
  @JsonKey()
  final String type;
  @override
  final double? salience;
  @override
  final String? sessionId;
  @override
  final String? userId;
  final Map<String, dynamic>? _metadata;
  @override
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'MemoryWriteRequest(content: $content, type: $type, salience: $salience, sessionId: $sessionId, userId: $userId, metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MemoryWriteRequestImpl &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.salience, salience) ||
                other.salience == salience) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, content, type, salience,
      sessionId, userId, const DeepCollectionEquality().hash(_metadata));

  /// Create a copy of MemoryWriteRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MemoryWriteRequestImplCopyWith<_$MemoryWriteRequestImpl> get copyWith =>
      __$$MemoryWriteRequestImplCopyWithImpl<_$MemoryWriteRequestImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MemoryWriteRequestImplToJson(
      this,
    );
  }
}

abstract class _MemoryWriteRequest implements MemoryWriteRequest {
  const factory _MemoryWriteRequest(
      {required final String content,
      final String type,
      final double? salience,
      final String? sessionId,
      final String? userId,
      final Map<String, dynamic>? metadata}) = _$MemoryWriteRequestImpl;

  factory _MemoryWriteRequest.fromJson(Map<String, dynamic> json) =
      _$MemoryWriteRequestImpl.fromJson;

  @override
  String get content;
  @override
  String get type;
  @override
  double? get salience;
  @override
  String? get sessionId;
  @override
  String? get userId;
  @override
  Map<String, dynamic>? get metadata;

  /// Create a copy of MemoryWriteRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MemoryWriteRequestImplCopyWith<_$MemoryWriteRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
