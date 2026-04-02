// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory_pack.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MemoryPack _$MemoryPackFromJson(Map<String, dynamic> json) {
  return _MemoryPack.fromJson(json);
}

/// @nodoc
mixin _$MemoryPack {
  List<dynamic> get memories => throw _privateConstructorUsedError;
  Map<String, dynamic> get metadata => throw _privateConstructorUsedError;

  /// Serializes this MemoryPack to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MemoryPack
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MemoryPackCopyWith<MemoryPack> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MemoryPackCopyWith<$Res> {
  factory $MemoryPackCopyWith(
          MemoryPack value, $Res Function(MemoryPack) then) =
      _$MemoryPackCopyWithImpl<$Res, MemoryPack>;
  @useResult
  $Res call({List<dynamic> memories, Map<String, dynamic> metadata});
}

/// @nodoc
class _$MemoryPackCopyWithImpl<$Res, $Val extends MemoryPack>
    implements $MemoryPackCopyWith<$Res> {
  _$MemoryPackCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MemoryPack
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? memories = null,
    Object? metadata = null,
  }) {
    return _then(_value.copyWith(
      memories: null == memories
          ? _value.memories
          : memories // ignore: cast_nullable_to_non_nullable
              as List<dynamic>,
      metadata: null == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MemoryPackImplCopyWith<$Res>
    implements $MemoryPackCopyWith<$Res> {
  factory _$$MemoryPackImplCopyWith(
          _$MemoryPackImpl value, $Res Function(_$MemoryPackImpl) then) =
      __$$MemoryPackImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<dynamic> memories, Map<String, dynamic> metadata});
}

/// @nodoc
class __$$MemoryPackImplCopyWithImpl<$Res>
    extends _$MemoryPackCopyWithImpl<$Res, _$MemoryPackImpl>
    implements _$$MemoryPackImplCopyWith<$Res> {
  __$$MemoryPackImplCopyWithImpl(
      _$MemoryPackImpl _value, $Res Function(_$MemoryPackImpl) _then)
      : super(_value, _then);

  /// Create a copy of MemoryPack
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? memories = null,
    Object? metadata = null,
  }) {
    return _then(_$MemoryPackImpl(
      memories: null == memories
          ? _value._memories
          : memories // ignore: cast_nullable_to_non_nullable
              as List<dynamic>,
      metadata: null == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MemoryPackImpl implements _MemoryPack {
  const _$MemoryPackImpl(
      {required final List<dynamic> memories,
      required final Map<String, dynamic> metadata})
      : _memories = memories,
        _metadata = metadata;

  factory _$MemoryPackImpl.fromJson(Map<String, dynamic> json) =>
      _$$MemoryPackImplFromJson(json);

  final List<dynamic> _memories;
  @override
  List<dynamic> get memories {
    if (_memories is EqualUnmodifiableListView) return _memories;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_memories);
  }

  final Map<String, dynamic> _metadata;
  @override
  Map<String, dynamic> get metadata {
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_metadata);
  }

  @override
  String toString() {
    return 'MemoryPack(memories: $memories, metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MemoryPackImpl &&
            const DeepCollectionEquality().equals(other._memories, _memories) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_memories),
      const DeepCollectionEquality().hash(_metadata));

  /// Create a copy of MemoryPack
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MemoryPackImplCopyWith<_$MemoryPackImpl> get copyWith =>
      __$$MemoryPackImplCopyWithImpl<_$MemoryPackImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MemoryPackImplToJson(
      this,
    );
  }
}

abstract class _MemoryPack implements MemoryPack {
  const factory _MemoryPack(
      {required final List<dynamic> memories,
      required final Map<String, dynamic> metadata}) = _$MemoryPackImpl;

  factory _MemoryPack.fromJson(Map<String, dynamic> json) =
      _$MemoryPackImpl.fromJson;

  @override
  List<dynamic> get memories;
  @override
  Map<String, dynamic> get metadata;

  /// Create a copy of MemoryPack
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MemoryPackImplCopyWith<_$MemoryPackImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
