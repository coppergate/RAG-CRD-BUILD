// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'db_op_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DbOpMessage {
  String get operation;
  String get table;
  Map<String, dynamic> get data;
  String? get condition;
  DateTime? get timestamp;

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DbOpMessageCopyWith<DbOpMessage> get copyWith =>
      _$DbOpMessageCopyWithImpl<DbOpMessage>(this as DbOpMessage, _$identity);

  /// Serializes this DbOpMessage to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DbOpMessage &&
            (identical(other.operation, operation) ||
                other.operation == operation) &&
            (identical(other.table, table) || other.table == table) &&
            const DeepCollectionEquality().equals(other.data, data) &&
            (identical(other.condition, condition) ||
                other.condition == condition) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, operation, table,
      const DeepCollectionEquality().hash(data), condition, timestamp);

  @override
  String toString() {
    return 'DbOpMessage(operation: $operation, table: $table, data: $data, condition: $condition, timestamp: $timestamp)';
  }
}

/// @nodoc
abstract mixin class $DbOpMessageCopyWith<$Res> {
  factory $DbOpMessageCopyWith(
          DbOpMessage value, $Res Function(DbOpMessage) _then) =
      _$DbOpMessageCopyWithImpl;
  @useResult
  $Res call(
      {String operation,
      String table,
      Map<String, dynamic> data,
      String? condition,
      DateTime? timestamp});
}

/// @nodoc
class _$DbOpMessageCopyWithImpl<$Res> implements $DbOpMessageCopyWith<$Res> {
  _$DbOpMessageCopyWithImpl(this._self, this._then);

  final DbOpMessage _self;
  final $Res Function(DbOpMessage) _then;

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? operation = null,
    Object? table = null,
    Object? data = null,
    Object? condition = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_self.copyWith(
      operation: null == operation
          ? _self.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      table: null == table
          ? _self.table
          : table // ignore: cast_nullable_to_non_nullable
              as String,
      data: null == data
          ? _self.data
          : data // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      condition: freezed == condition
          ? _self.condition
          : condition // ignore: cast_nullable_to_non_nullable
              as String?,
      timestamp: freezed == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// Adds pattern-matching-related methods to [DbOpMessage].
extension DbOpMessagePatterns on DbOpMessage {
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
    TResult Function(_DbOpMessage value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DbOpMessage() when $default != null:
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
    TResult Function(_DbOpMessage value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DbOpMessage():
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
    TResult? Function(_DbOpMessage value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DbOpMessage() when $default != null:
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
    TResult Function(String operation, String table, Map<String, dynamic> data,
            String? condition, DateTime? timestamp)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DbOpMessage() when $default != null:
        return $default(_that.operation, _that.table, _that.data,
            _that.condition, _that.timestamp);
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
    TResult Function(String operation, String table, Map<String, dynamic> data,
            String? condition, DateTime? timestamp)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DbOpMessage():
        return $default(_that.operation, _that.table, _that.data,
            _that.condition, _that.timestamp);
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
    TResult? Function(String operation, String table, Map<String, dynamic> data,
            String? condition, DateTime? timestamp)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DbOpMessage() when $default != null:
        return $default(_that.operation, _that.table, _that.data,
            _that.condition, _that.timestamp);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _DbOpMessage implements DbOpMessage {
  const _DbOpMessage(
      {required this.operation,
      required this.table,
      required final Map<String, dynamic> data,
      this.condition,
      this.timestamp})
      : _data = data;
  factory _DbOpMessage.fromJson(Map<String, dynamic> json) =>
      _$DbOpMessageFromJson(json);

  @override
  final String operation;
  @override
  final String table;
  final Map<String, dynamic> _data;
  @override
  Map<String, dynamic> get data {
    if (_data is EqualUnmodifiableMapView) return _data;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_data);
  }

  @override
  final String? condition;
  @override
  final DateTime? timestamp;

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DbOpMessageCopyWith<_DbOpMessage> get copyWith =>
      __$DbOpMessageCopyWithImpl<_DbOpMessage>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$DbOpMessageToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DbOpMessage &&
            (identical(other.operation, operation) ||
                other.operation == operation) &&
            (identical(other.table, table) || other.table == table) &&
            const DeepCollectionEquality().equals(other._data, _data) &&
            (identical(other.condition, condition) ||
                other.condition == condition) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, operation, table,
      const DeepCollectionEquality().hash(_data), condition, timestamp);

  @override
  String toString() {
    return 'DbOpMessage(operation: $operation, table: $table, data: $data, condition: $condition, timestamp: $timestamp)';
  }
}

/// @nodoc
abstract mixin class _$DbOpMessageCopyWith<$Res>
    implements $DbOpMessageCopyWith<$Res> {
  factory _$DbOpMessageCopyWith(
          _DbOpMessage value, $Res Function(_DbOpMessage) _then) =
      __$DbOpMessageCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String operation,
      String table,
      Map<String, dynamic> data,
      String? condition,
      DateTime? timestamp});
}

/// @nodoc
class __$DbOpMessageCopyWithImpl<$Res> implements _$DbOpMessageCopyWith<$Res> {
  __$DbOpMessageCopyWithImpl(this._self, this._then);

  final _DbOpMessage _self;
  final $Res Function(_DbOpMessage) _then;

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? operation = null,
    Object? table = null,
    Object? data = null,
    Object? condition = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_DbOpMessage(
      operation: null == operation
          ? _self.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      table: null == table
          ? _self.table
          : table // ignore: cast_nullable_to_non_nullable
              as String,
      data: null == data
          ? _self._data
          : data // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      condition: freezed == condition
          ? _self.condition
          : condition // ignore: cast_nullable_to_non_nullable
              as String?,
      timestamp: freezed == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

// dart format on
