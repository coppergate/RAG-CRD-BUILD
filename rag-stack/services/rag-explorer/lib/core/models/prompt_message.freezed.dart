// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'prompt_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PromptMessage {

 String get prompt; String? get sessionId; String? get plannerModel; String? get executorModel; List<String>? get tags; String get memoryMode;
/// Create a copy of PromptMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptMessageCopyWith<PromptMessage> get copyWith => _$PromptMessageCopyWithImpl<PromptMessage>(this as PromptMessage, _$identity);

  /// Serializes this PromptMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptMessage&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.plannerModel, plannerModel) || other.plannerModel == plannerModel)&&(identical(other.executorModel, executorModel) || other.executorModel == executorModel)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.memoryMode, memoryMode) || other.memoryMode == memoryMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,prompt,sessionId,plannerModel,executorModel,const DeepCollectionEquality().hash(tags),memoryMode);

@override
String toString() {
  return 'PromptMessage(prompt: $prompt, sessionId: $sessionId, plannerModel: $plannerModel, executorModel: $executorModel, tags: $tags, memoryMode: $memoryMode)';
}


}

/// @nodoc
abstract mixin class $PromptMessageCopyWith<$Res>  {
  factory $PromptMessageCopyWith(PromptMessage value, $Res Function(PromptMessage) _then) = _$PromptMessageCopyWithImpl;
@useResult
$Res call({
 String prompt, String? sessionId, String? plannerModel, String? executorModel, List<String>? tags, String memoryMode
});




}
/// @nodoc
class _$PromptMessageCopyWithImpl<$Res>
    implements $PromptMessageCopyWith<$Res> {
  _$PromptMessageCopyWithImpl(this._self, this._then);

  final PromptMessage _self;
  final $Res Function(PromptMessage) _then;

/// Create a copy of PromptMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? prompt = null,Object? sessionId = freezed,Object? plannerModel = freezed,Object? executorModel = freezed,Object? tags = freezed,Object? memoryMode = null,}) {
  return _then(_self.copyWith(
prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,plannerModel: freezed == plannerModel ? _self.plannerModel : plannerModel // ignore: cast_nullable_to_non_nullable
as String?,executorModel: freezed == executorModel ? _self.executorModel : executorModel // ignore: cast_nullable_to_non_nullable
as String?,tags: freezed == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>?,memoryMode: null == memoryMode ? _self.memoryMode : memoryMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PromptMessage].
extension PromptMessagePatterns on PromptMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PromptMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PromptMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PromptMessage value)  $default,){
final _that = this;
switch (_that) {
case _PromptMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PromptMessage value)?  $default,){
final _that = this;
switch (_that) {
case _PromptMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String prompt,  String? sessionId,  String? plannerModel,  String? executorModel,  List<String>? tags,  String memoryMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PromptMessage() when $default != null:
return $default(_that.prompt,_that.sessionId,_that.plannerModel,_that.executorModel,_that.tags,_that.memoryMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String prompt,  String? sessionId,  String? plannerModel,  String? executorModel,  List<String>? tags,  String memoryMode)  $default,) {final _that = this;
switch (_that) {
case _PromptMessage():
return $default(_that.prompt,_that.sessionId,_that.plannerModel,_that.executorModel,_that.tags,_that.memoryMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String prompt,  String? sessionId,  String? plannerModel,  String? executorModel,  List<String>? tags,  String memoryMode)?  $default,) {final _that = this;
switch (_that) {
case _PromptMessage() when $default != null:
return $default(_that.prompt,_that.sessionId,_that.plannerModel,_that.executorModel,_that.tags,_that.memoryMode);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PromptMessage implements PromptMessage {
  const _PromptMessage({required this.prompt, this.sessionId, this.plannerModel, this.executorModel, final  List<String>? tags, this.memoryMode = 'off'}): _tags = tags;
  factory _PromptMessage.fromJson(Map<String, dynamic> json) => _$PromptMessageFromJson(json);

@override final  String prompt;
@override final  String? sessionId;
@override final  String? plannerModel;
@override final  String? executorModel;
 final  List<String>? _tags;
@override List<String>? get tags {
  final value = _tags;
  if (value == null) return null;
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override@JsonKey() final  String memoryMode;

/// Create a copy of PromptMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PromptMessageCopyWith<_PromptMessage> get copyWith => __$PromptMessageCopyWithImpl<_PromptMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PromptMessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PromptMessage&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.plannerModel, plannerModel) || other.plannerModel == plannerModel)&&(identical(other.executorModel, executorModel) || other.executorModel == executorModel)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.memoryMode, memoryMode) || other.memoryMode == memoryMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,prompt,sessionId,plannerModel,executorModel,const DeepCollectionEquality().hash(_tags),memoryMode);

@override
String toString() {
  return 'PromptMessage(prompt: $prompt, sessionId: $sessionId, plannerModel: $plannerModel, executorModel: $executorModel, tags: $tags, memoryMode: $memoryMode)';
}


}

/// @nodoc
abstract mixin class _$PromptMessageCopyWith<$Res> implements $PromptMessageCopyWith<$Res> {
  factory _$PromptMessageCopyWith(_PromptMessage value, $Res Function(_PromptMessage) _then) = __$PromptMessageCopyWithImpl;
@override @useResult
$Res call({
 String prompt, String? sessionId, String? plannerModel, String? executorModel, List<String>? tags, String memoryMode
});




}
/// @nodoc
class __$PromptMessageCopyWithImpl<$Res>
    implements _$PromptMessageCopyWith<$Res> {
  __$PromptMessageCopyWithImpl(this._self, this._then);

  final _PromptMessage _self;
  final $Res Function(_PromptMessage) _then;

/// Create a copy of PromptMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? prompt = null,Object? sessionId = freezed,Object? plannerModel = freezed,Object? executorModel = freezed,Object? tags = freezed,Object? memoryMode = null,}) {
  return _then(_PromptMessage(
prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,plannerModel: freezed == plannerModel ? _self.plannerModel : plannerModel // ignore: cast_nullable_to_non_nullable
as String?,executorModel: freezed == executorModel ? _self.executorModel : executorModel // ignore: cast_nullable_to_non_nullable
as String?,tags: freezed == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>?,memoryMode: null == memoryMode ? _self.memoryMode : memoryMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
