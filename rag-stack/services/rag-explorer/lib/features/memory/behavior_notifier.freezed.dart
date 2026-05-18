// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'behavior_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BehaviorState {

 List<BehavioralRule> get rules; List<ActionIdentifier> get identifiers; bool get isLoading; String? get error;
/// Create a copy of BehaviorState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BehaviorStateCopyWith<BehaviorState> get copyWith => _$BehaviorStateCopyWithImpl<BehaviorState>(this as BehaviorState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BehaviorState&&const DeepCollectionEquality().equals(other.rules, rules)&&const DeepCollectionEquality().equals(other.identifiers, identifiers)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(rules),const DeepCollectionEquality().hash(identifiers),isLoading,error);

@override
String toString() {
  return 'BehaviorState(rules: $rules, identifiers: $identifiers, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class $BehaviorStateCopyWith<$Res>  {
  factory $BehaviorStateCopyWith(BehaviorState value, $Res Function(BehaviorState) _then) = _$BehaviorStateCopyWithImpl;
@useResult
$Res call({
 List<BehavioralRule> rules, List<ActionIdentifier> identifiers, bool isLoading, String? error
});




}
/// @nodoc
class _$BehaviorStateCopyWithImpl<$Res>
    implements $BehaviorStateCopyWith<$Res> {
  _$BehaviorStateCopyWithImpl(this._self, this._then);

  final BehaviorState _self;
  final $Res Function(BehaviorState) _then;

/// Create a copy of BehaviorState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rules = null,Object? identifiers = null,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
rules: null == rules ? _self.rules : rules // ignore: cast_nullable_to_non_nullable
as List<BehavioralRule>,identifiers: null == identifiers ? _self.identifiers : identifiers // ignore: cast_nullable_to_non_nullable
as List<ActionIdentifier>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BehaviorState].
extension BehaviorStatePatterns on BehaviorState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BehaviorState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BehaviorState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BehaviorState value)  $default,){
final _that = this;
switch (_that) {
case _BehaviorState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BehaviorState value)?  $default,){
final _that = this;
switch (_that) {
case _BehaviorState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<BehavioralRule> rules,  List<ActionIdentifier> identifiers,  bool isLoading,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BehaviorState() when $default != null:
return $default(_that.rules,_that.identifiers,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<BehavioralRule> rules,  List<ActionIdentifier> identifiers,  bool isLoading,  String? error)  $default,) {final _that = this;
switch (_that) {
case _BehaviorState():
return $default(_that.rules,_that.identifiers,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<BehavioralRule> rules,  List<ActionIdentifier> identifiers,  bool isLoading,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _BehaviorState() when $default != null:
return $default(_that.rules,_that.identifiers,_that.isLoading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _BehaviorState implements BehaviorState {
  const _BehaviorState({final  List<BehavioralRule> rules = const [], final  List<ActionIdentifier> identifiers = const [], this.isLoading = false, this.error}): _rules = rules,_identifiers = identifiers;
  

 final  List<BehavioralRule> _rules;
@override@JsonKey() List<BehavioralRule> get rules {
  if (_rules is EqualUnmodifiableListView) return _rules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rules);
}

 final  List<ActionIdentifier> _identifiers;
@override@JsonKey() List<ActionIdentifier> get identifiers {
  if (_identifiers is EqualUnmodifiableListView) return _identifiers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_identifiers);
}

@override@JsonKey() final  bool isLoading;
@override final  String? error;

/// Create a copy of BehaviorState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BehaviorStateCopyWith<_BehaviorState> get copyWith => __$BehaviorStateCopyWithImpl<_BehaviorState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BehaviorState&&const DeepCollectionEquality().equals(other._rules, _rules)&&const DeepCollectionEquality().equals(other._identifiers, _identifiers)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_rules),const DeepCollectionEquality().hash(_identifiers),isLoading,error);

@override
String toString() {
  return 'BehaviorState(rules: $rules, identifiers: $identifiers, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$BehaviorStateCopyWith<$Res> implements $BehaviorStateCopyWith<$Res> {
  factory _$BehaviorStateCopyWith(_BehaviorState value, $Res Function(_BehaviorState) _then) = __$BehaviorStateCopyWithImpl;
@override @useResult
$Res call({
 List<BehavioralRule> rules, List<ActionIdentifier> identifiers, bool isLoading, String? error
});




}
/// @nodoc
class __$BehaviorStateCopyWithImpl<$Res>
    implements _$BehaviorStateCopyWith<$Res> {
  __$BehaviorStateCopyWithImpl(this._self, this._then);

  final _BehaviorState _self;
  final $Res Function(_BehaviorState) _then;

/// Create a copy of BehaviorState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rules = null,Object? identifiers = null,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_BehaviorState(
rules: null == rules ? _self._rules : rules // ignore: cast_nullable_to_non_nullable
as List<BehavioralRule>,identifiers: null == identifiers ? _self._identifiers : identifiers // ignore: cast_nullable_to_non_nullable
as List<ActionIdentifier>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
