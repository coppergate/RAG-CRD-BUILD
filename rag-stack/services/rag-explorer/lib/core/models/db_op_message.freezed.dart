// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'db_op_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DbOpMessage _$DbOpMessageFromJson(Map<String, dynamic> json) {
  return _DbOpMessage.fromJson(json);
}

/// @nodoc
mixin _$DbOpMessage {
  String get operation => throw _privateConstructorUsedError;
  String get table => throw _privateConstructorUsedError;
  Map<String, dynamic> get data => throw _privateConstructorUsedError;
  String? get condition => throw _privateConstructorUsedError;
  DateTime? get timestamp => throw _privateConstructorUsedError;

  /// Serializes this DbOpMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DbOpMessageCopyWith<DbOpMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DbOpMessageCopyWith<$Res> {
  factory $DbOpMessageCopyWith(
          DbOpMessage value, $Res Function(DbOpMessage) then) =
      _$DbOpMessageCopyWithImpl<$Res, DbOpMessage>;
  @useResult
  $Res call(
      {String operation,
      String table,
      Map<String, dynamic> data,
      String? condition,
      DateTime? timestamp});
}

/// @nodoc
class _$DbOpMessageCopyWithImpl<$Res, $Val extends DbOpMessage>
    implements $DbOpMessageCopyWith<$Res> {
  _$DbOpMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

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
    return _then(_value.copyWith(
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      table: null == table
          ? _value.table
          : table // ignore: cast_nullable_to_non_nullable
              as String,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      condition: freezed == condition
          ? _value.condition
          : condition // ignore: cast_nullable_to_non_nullable
              as String?,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DbOpMessageImplCopyWith<$Res>
    implements $DbOpMessageCopyWith<$Res> {
  factory _$$DbOpMessageImplCopyWith(
          _$DbOpMessageImpl value, $Res Function(_$DbOpMessageImpl) then) =
      __$$DbOpMessageImplCopyWithImpl<$Res>;
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
class __$$DbOpMessageImplCopyWithImpl<$Res>
    extends _$DbOpMessageCopyWithImpl<$Res, _$DbOpMessageImpl>
    implements _$$DbOpMessageImplCopyWith<$Res> {
  __$$DbOpMessageImplCopyWithImpl(
      _$DbOpMessageImpl _value, $Res Function(_$DbOpMessageImpl) _then)
      : super(_value, _then);

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
    return _then(_$DbOpMessageImpl(
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      table: null == table
          ? _value.table
          : table // ignore: cast_nullable_to_non_nullable
              as String,
      data: null == data
          ? _value._data
          : data // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      condition: freezed == condition
          ? _value.condition
          : condition // ignore: cast_nullable_to_non_nullable
              as String?,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DbOpMessageImpl implements _DbOpMessage {
  const _$DbOpMessageImpl(
      {required this.operation,
      required this.table,
      required final Map<String, dynamic> data,
      this.condition,
      this.timestamp})
      : _data = data;

  factory _$DbOpMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$DbOpMessageImplFromJson(json);

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

  @override
  String toString() {
    return 'DbOpMessage(operation: $operation, table: $table, data: $data, condition: $condition, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DbOpMessageImpl &&
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

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DbOpMessageImplCopyWith<_$DbOpMessageImpl> get copyWith =>
      __$$DbOpMessageImplCopyWithImpl<_$DbOpMessageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DbOpMessageImplToJson(
      this,
    );
  }
}

abstract class _DbOpMessage implements DbOpMessage {
  const factory _DbOpMessage(
      {required final String operation,
      required final String table,
      required final Map<String, dynamic> data,
      final String? condition,
      final DateTime? timestamp}) = _$DbOpMessageImpl;

  factory _DbOpMessage.fromJson(Map<String, dynamic> json) =
      _$DbOpMessageImpl.fromJson;

  @override
  String get operation;
  @override
  String get table;
  @override
  Map<String, dynamic> get data;
  @override
  String? get condition;
  @override
  DateTime? get timestamp;

  /// Create a copy of DbOpMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DbOpMessageImplCopyWith<_$DbOpMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
