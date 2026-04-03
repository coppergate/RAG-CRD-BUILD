// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'response_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ResponseMessage {
  String get content;
  String? get sessionId;
  String? get messageId;
  String? get role;
  Map<String, dynamic>? get metadata;
  DateTime? get timestamp;

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ResponseMessageCopyWith<ResponseMessage> get copyWith =>
      _$ResponseMessageCopyWithImpl<ResponseMessage>(
          this as ResponseMessage, _$identity);

  /// Serializes this ResponseMessage to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ResponseMessage &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.messageId, messageId) ||
                other.messageId == messageId) &&
            (identical(other.role, role) || other.role == role) &&
            const DeepCollectionEquality().equals(other.metadata, metadata) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, content, sessionId, messageId,
      role, const DeepCollectionEquality().hash(metadata), timestamp);

  @override
  String toString() {
    return 'ResponseMessage(content: $content, sessionId: $sessionId, messageId: $messageId, role: $role, metadata: $metadata, timestamp: $timestamp)';
  }
}

/// @nodoc
abstract mixin class $ResponseMessageCopyWith<$Res> {
  factory $ResponseMessageCopyWith(
          ResponseMessage value, $Res Function(ResponseMessage) _then) =
      _$ResponseMessageCopyWithImpl;
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
class _$ResponseMessageCopyWithImpl<$Res>
    implements $ResponseMessageCopyWith<$Res> {
  _$ResponseMessageCopyWithImpl(this._self, this._then);

  final ResponseMessage _self;
  final $Res Function(ResponseMessage) _then;

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
    return _then(_self.copyWith(
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _self.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      messageId: freezed == messageId
          ? _self.messageId
          : messageId // ignore: cast_nullable_to_non_nullable
              as String?,
      role: freezed == role
          ? _self.role
          : role // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _self.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      timestamp: freezed == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// Adds pattern-matching-related methods to [ResponseMessage].
extension ResponseMessagePatterns on ResponseMessage {
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

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_ResponseMessage value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ResponseMessage() when $default != null:
        return $default(_that);
      case _:
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

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_ResponseMessage value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResponseMessage():
        return $default(_that);
      case _:
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

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_ResponseMessage value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResponseMessage() when $default != null:
        return $default(_that);
      case _:
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

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(String content, String? sessionId, String? messageId,
            String? role, Map<String, dynamic>? metadata, DateTime? timestamp)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ResponseMessage() when $default != null:
        return $default(_that.content, _that.sessionId, _that.messageId,
            _that.role, _that.metadata, _that.timestamp);
      case _:
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

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(String content, String? sessionId, String? messageId,
            String? role, Map<String, dynamic>? metadata, DateTime? timestamp)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResponseMessage():
        return $default(_that.content, _that.sessionId, _that.messageId,
            _that.role, _that.metadata, _that.timestamp);
      case _:
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

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(String content, String? sessionId, String? messageId,
            String? role, Map<String, dynamic>? metadata, DateTime? timestamp)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ResponseMessage() when $default != null:
        return $default(_that.content, _that.sessionId, _that.messageId,
            _that.role, _that.metadata, _that.timestamp);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _ResponseMessage implements ResponseMessage {
  const _ResponseMessage(
      {required this.content,
      this.sessionId,
      this.messageId,
      this.role,
      final Map<String, dynamic>? metadata,
      this.timestamp})
      : _metadata = metadata;
  factory _ResponseMessage.fromJson(Map<String, dynamic> json) =>
      _$ResponseMessageFromJson(json);

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

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ResponseMessageCopyWith<_ResponseMessage> get copyWith =>
      __$ResponseMessageCopyWithImpl<_ResponseMessage>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ResponseMessageToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ResponseMessage &&
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

  @override
  String toString() {
    return 'ResponseMessage(content: $content, sessionId: $sessionId, messageId: $messageId, role: $role, metadata: $metadata, timestamp: $timestamp)';
  }
}

/// @nodoc
abstract mixin class _$ResponseMessageCopyWith<$Res>
    implements $ResponseMessageCopyWith<$Res> {
  factory _$ResponseMessageCopyWith(
          _ResponseMessage value, $Res Function(_ResponseMessage) _then) =
      __$ResponseMessageCopyWithImpl;
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
class __$ResponseMessageCopyWithImpl<$Res>
    implements _$ResponseMessageCopyWith<$Res> {
  __$ResponseMessageCopyWithImpl(this._self, this._then);

  final _ResponseMessage _self;
  final $Res Function(_ResponseMessage) _then;

  /// Create a copy of ResponseMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? content = null,
    Object? sessionId = freezed,
    Object? messageId = freezed,
    Object? role = freezed,
    Object? metadata = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_ResponseMessage(
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _self.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      messageId: freezed == messageId
          ? _self.messageId
          : messageId // ignore: cast_nullable_to_non_nullable
              as String?,
      role: freezed == role
          ? _self.role
          : role // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _self._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      timestamp: freezed == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

// dart format on
