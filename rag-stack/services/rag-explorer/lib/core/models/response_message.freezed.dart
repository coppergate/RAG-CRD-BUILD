// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'response_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ResponseMessage _$ResponseMessageFromJson(Map<String, dynamic> json) {
  return _ResponseMessage.fromJson(json);
}

/// @nodoc
mixin _$ResponseMessage {
  String get content => throw _privateConstructorUsedError;
  String? get sessionId => throw _privateConstructorUsedError;
  String? get messageId => throw _privateConstructorUsedError;
  String? get role => throw _privateConstructorUsedError;
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;
  DateTime? get timestamp => throw _privateConstructorUsedError;

  /// Serializes this ResponseMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ResponseMessageCopyWith<ResponseMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ResponseMessageCopyWith<$Res> {
  factory $ResponseMessageCopyWith(
          ResponseMessage value, $Res Function(ResponseMessage) then) =
      _$ResponseMessageCopyWithImpl<$Res, ResponseMessage>;
  @useResult
  $Res call(
      {String content,
      String? sessionId,
      String? messageId,
      String? role,
      Map<String, dynamic>? metadata,
      DateTime? timestamp});
}

/// @nodoc
class _$ResponseMessageCopyWithImpl<$Res, $Val extends ResponseMessage>
    implements $ResponseMessageCopyWith<$Res> {
  _$ResponseMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? content = null,
    Object? sessionId = freezed,
    Object? messageId = freezed,
    Object? role = freezed,
    Object? metadata = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_value.copyWith(
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      messageId: freezed == messageId
          ? _value.messageId
          : messageId // ignore: cast_nullable_to_non_nullable
              as String?,
      role: freezed == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ResponseMessageImplCopyWith<$Res>
    implements $ResponseMessageCopyWith<$Res> {
  factory _$$ResponseMessageImplCopyWith(_$ResponseMessageImpl value,
          $Res Function(_$ResponseMessageImpl) then) =
      __$$ResponseMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String content,
      String? sessionId,
      String? messageId,
      String? role,
      Map<String, dynamic>? metadata,
      DateTime? timestamp});
}

/// @nodoc
class __$$ResponseMessageImplCopyWithImpl<$Res>
    extends _$ResponseMessageCopyWithImpl<$Res, _$ResponseMessageImpl>
    implements _$$ResponseMessageImplCopyWith<$Res> {
  __$$ResponseMessageImplCopyWithImpl(
      _$ResponseMessageImpl _value, $Res Function(_$ResponseMessageImpl) _then)
      : super(_value, _then);

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? content = null,
    Object? sessionId = freezed,
    Object? messageId = freezed,
    Object? role = freezed,
    Object? metadata = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_$ResponseMessageImpl(
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      messageId: freezed == messageId
          ? _value.messageId
          : messageId // ignore: cast_nullable_to_non_nullable
              as String?,
      role: freezed == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ResponseMessageImpl implements _ResponseMessage {
  const _$ResponseMessageImpl(
      {required this.content,
      this.sessionId,
      this.messageId,
      this.role,
      final Map<String, dynamic>? metadata,
      this.timestamp})
      : _metadata = metadata;

  factory _$ResponseMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ResponseMessageImplFromJson(json);

  @override
  final String content;
  @override
  final String? sessionId;
  @override
  final String? messageId;
  @override
  final String? role;
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
  final DateTime? timestamp;

  @override
  String toString() {
    return 'ResponseMessage(content: $content, sessionId: $sessionId, messageId: $messageId, role: $role, metadata: $metadata, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ResponseMessageImpl &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.messageId, messageId) ||
                other.messageId == messageId) &&
            (identical(other.role, role) || other.role == role) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, content, sessionId, messageId,
      role, const DeepCollectionEquality().hash(_metadata), timestamp);

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ResponseMessageImplCopyWith<_$ResponseMessageImpl> get copyWith =>
      __$$ResponseMessageImplCopyWithImpl<_$ResponseMessageImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ResponseMessageImplToJson(
      this,
    );
  }
}

abstract class _ResponseMessage implements ResponseMessage {
  const factory _ResponseMessage(
      {required final String content,
      final String? sessionId,
      final String? messageId,
      final String? role,
      final Map<String, dynamic>? metadata,
      final DateTime? timestamp}) = _$ResponseMessageImpl;

  factory _ResponseMessage.fromJson(Map<String, dynamic> json) =
      _$ResponseMessageImpl.fromJson;

  @override
  String get content;
  @override
  String? get sessionId;
  @override
  String? get messageId;
  @override
  String? get role;
  @override
  Map<String, dynamic>? get metadata;
  @override
  DateTime? get timestamp;

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ResponseMessageImplCopyWith<_$ResponseMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
