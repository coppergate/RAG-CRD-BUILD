// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'prompt_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

PromptMessage _$PromptMessageFromJson(Map<String, dynamic> json) {
  return _PromptMessage.fromJson(json);
}

/// @nodoc
mixin _$PromptMessage {
  String get prompt => throw _privateConstructorUsedError;
  String? get sessionId => throw _privateConstructorUsedError;
  String? get plannerModel => throw _privateConstructorUsedError;
  String? get executorModel => throw _privateConstructorUsedError;
  List<String>? get tags => throw _privateConstructorUsedError;
  String get memoryMode => throw _privateConstructorUsedError;

  /// Serializes this PromptMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PromptMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PromptMessageCopyWith<PromptMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PromptMessageCopyWith<$Res> {
  factory $PromptMessageCopyWith(
          PromptMessage value, $Res Function(PromptMessage) then) =
      _$PromptMessageCopyWithImpl<$Res, PromptMessage>;
  @useResult
  $Res call(
      {String prompt,
      String? sessionId,
      String? plannerModel,
      String? executorModel,
      List<String>? tags,
      String memoryMode});
}

/// @nodoc
class _$PromptMessageCopyWithImpl<$Res, $Val extends PromptMessage>
    implements $PromptMessageCopyWith<$Res> {
  _$PromptMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PromptMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? prompt = null,
    Object? sessionId = freezed,
    Object? plannerModel = freezed,
    Object? executorModel = freezed,
    Object? tags = freezed,
    Object? memoryMode = null,
  }) {
    return _then(_value.copyWith(
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      plannerModel: freezed == plannerModel
          ? _value.plannerModel
          : plannerModel // ignore: cast_nullable_to_non_nullable
              as String?,
      executorModel: freezed == executorModel
          ? _value.executorModel
          : executorModel // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: freezed == tags
          ? _value.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      memoryMode: null == memoryMode
          ? _value.memoryMode
          : memoryMode // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PromptMessageImplCopyWith<$Res>
    implements $PromptMessageCopyWith<$Res> {
  factory _$$PromptMessageImplCopyWith(
          _$PromptMessageImpl value, $Res Function(_$PromptMessageImpl) then) =
      __$$PromptMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String prompt,
      String? sessionId,
      String? plannerModel,
      String? executorModel,
      List<String>? tags,
      String memoryMode});
}

/// @nodoc
class __$$PromptMessageImplCopyWithImpl<$Res>
    extends _$PromptMessageCopyWithImpl<$Res, _$PromptMessageImpl>
    implements _$$PromptMessageImplCopyWith<$Res> {
  __$$PromptMessageImplCopyWithImpl(
      _$PromptMessageImpl _value, $Res Function(_$PromptMessageImpl) _then)
      : super(_value, _then);

  /// Create a copy of PromptMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? prompt = null,
    Object? sessionId = freezed,
    Object? plannerModel = freezed,
    Object? executorModel = freezed,
    Object? tags = freezed,
    Object? memoryMode = null,
  }) {
    return _then(_$PromptMessageImpl(
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      plannerModel: freezed == plannerModel
          ? _value.plannerModel
          : plannerModel // ignore: cast_nullable_to_non_nullable
              as String?,
      executorModel: freezed == executorModel
          ? _value.executorModel
          : executorModel // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: freezed == tags
          ? _value._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      memoryMode: null == memoryMode
          ? _value.memoryMode
          : memoryMode // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PromptMessageImpl implements _PromptMessage {
  const _$PromptMessageImpl(
      {required this.prompt,
      this.sessionId,
      this.plannerModel,
      this.executorModel,
      final List<String>? tags,
      this.memoryMode = 'off'})
      : _tags = tags;

  factory _$PromptMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$PromptMessageImplFromJson(json);

  @override
  final String prompt;
  @override
  final String? sessionId;
  @override
  final String? plannerModel;
  @override
  final String? executorModel;
  final List<String>? _tags;
  @override
  List<String>? get tags {
    final value = _tags;
    if (value == null) return null;
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  @JsonKey()
  final String memoryMode;

  @override
  String toString() {
    return 'PromptMessage(prompt: $prompt, sessionId: $sessionId, plannerModel: $plannerModel, executorModel: $executorModel, tags: $tags, memoryMode: $memoryMode)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PromptMessageImpl &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.plannerModel, plannerModel) ||
                other.plannerModel == plannerModel) &&
            (identical(other.executorModel, executorModel) ||
                other.executorModel == executorModel) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            (identical(other.memoryMode, memoryMode) ||
                other.memoryMode == memoryMode));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, prompt, sessionId, plannerModel,
      executorModel, const DeepCollectionEquality().hash(_tags), memoryMode);

  /// Create a copy of PromptMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PromptMessageImplCopyWith<_$PromptMessageImpl> get copyWith =>
      __$$PromptMessageImplCopyWithImpl<_$PromptMessageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PromptMessageImplToJson(
      this,
    );
  }
}

abstract class _PromptMessage implements PromptMessage {
  const factory _PromptMessage(
      {required final String prompt,
      final String? sessionId,
      final String? plannerModel,
      final String? executorModel,
      final List<String>? tags,
      final String memoryMode}) = _$PromptMessageImpl;

  factory _PromptMessage.fromJson(Map<String, dynamic> json) =
      _$PromptMessageImpl.fromJson;

  @override
  String get prompt;
  @override
  String? get sessionId;
  @override
  String? get plannerModel;
  @override
  String? get executorModel;
  @override
  List<String>? get tags;
  @override
  String get memoryMode;

  /// Create a copy of PromptMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PromptMessageImplCopyWith<_$PromptMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
