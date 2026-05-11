// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'behavioral_rule.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BehavioralRule {

 int get id; String get actionType; String? get category; String get state; String get ruleContent; int get priority; bool get isActive; String get scope; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of BehavioralRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BehavioralRuleCopyWith<BehavioralRule> get copyWith => _$BehavioralRuleCopyWithImpl<BehavioralRule>(this as BehavioralRule, _$identity);

  /// Serializes this BehavioralRule to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BehavioralRule&&(identical(other.id, id) || other.id == id)&&(identical(other.actionType, actionType) || other.actionType == actionType)&&(identical(other.category, category) || other.category == category)&&(identical(other.state, state) || other.state == state)&&(identical(other.ruleContent, ruleContent) || other.ruleContent == ruleContent)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,actionType,category,state,ruleContent,priority,isActive,scope,createdAt,updatedAt);

@override
String toString() {
  return 'BehavioralRule(id: $id, actionType: $actionType, category: $category, state: $state, ruleContent: $ruleContent, priority: $priority, isActive: $isActive, scope: $scope, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BehavioralRuleCopyWith<$Res>  {
  factory $BehavioralRuleCopyWith(BehavioralRule value, $Res Function(BehavioralRule) _then) = _$BehavioralRuleCopyWithImpl;
@useResult
$Res call({
 int id, String actionType, String? category, String state, String ruleContent, int priority, bool isActive, String scope, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$BehavioralRuleCopyWithImpl<$Res>
    implements $BehavioralRuleCopyWith<$Res> {
  _$BehavioralRuleCopyWithImpl(this._self, this._then);

  final BehavioralRule _self;
  final $Res Function(BehavioralRule) _then;

/// Create a copy of BehavioralRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? actionType = null,Object? category = freezed,Object? state = null,Object? ruleContent = null,Object? priority = null,Object? isActive = null,Object? scope = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,actionType: null == actionType ? _self.actionType : actionType // ignore: cast_nullable_to_non_nullable
as String,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,ruleContent: null == ruleContent ? _self.ruleContent : ruleContent // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [BehavioralRule].
extension BehavioralRulePatterns on BehavioralRule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BehavioralRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BehavioralRule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BehavioralRule value)  $default,){
final _that = this;
switch (_that) {
case _BehavioralRule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BehavioralRule value)?  $default,){
final _that = this;
switch (_that) {
case _BehavioralRule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String actionType,  String? category,  String state,  String ruleContent,  int priority,  bool isActive,  String scope,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BehavioralRule() when $default != null:
return $default(_that.id,_that.actionType,_that.category,_that.state,_that.ruleContent,_that.priority,_that.isActive,_that.scope,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String actionType,  String? category,  String state,  String ruleContent,  int priority,  bool isActive,  String scope,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _BehavioralRule():
return $default(_that.id,_that.actionType,_that.category,_that.state,_that.ruleContent,_that.priority,_that.isActive,_that.scope,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String actionType,  String? category,  String state,  String ruleContent,  int priority,  bool isActive,  String scope,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _BehavioralRule() when $default != null:
return $default(_that.id,_that.actionType,_that.category,_that.state,_that.ruleContent,_that.priority,_that.isActive,_that.scope,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BehavioralRule implements BehavioralRule {
  const _BehavioralRule({required this.id, required this.actionType, this.category, required this.state, required this.ruleContent, required this.priority, required this.isActive, required this.scope, required this.createdAt, required this.updatedAt});
  factory _BehavioralRule.fromJson(Map<String, dynamic> json) => _$BehavioralRuleFromJson(json);

@override final  int id;
@override final  String actionType;
@override final  String? category;
@override final  String state;
@override final  String ruleContent;
@override final  int priority;
@override final  bool isActive;
@override final  String scope;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of BehavioralRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BehavioralRuleCopyWith<_BehavioralRule> get copyWith => __$BehavioralRuleCopyWithImpl<_BehavioralRule>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BehavioralRuleToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BehavioralRule&&(identical(other.id, id) || other.id == id)&&(identical(other.actionType, actionType) || other.actionType == actionType)&&(identical(other.category, category) || other.category == category)&&(identical(other.state, state) || other.state == state)&&(identical(other.ruleContent, ruleContent) || other.ruleContent == ruleContent)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,actionType,category,state,ruleContent,priority,isActive,scope,createdAt,updatedAt);

@override
String toString() {
  return 'BehavioralRule(id: $id, actionType: $actionType, category: $category, state: $state, ruleContent: $ruleContent, priority: $priority, isActive: $isActive, scope: $scope, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$BehavioralRuleCopyWith<$Res> implements $BehavioralRuleCopyWith<$Res> {
  factory _$BehavioralRuleCopyWith(_BehavioralRule value, $Res Function(_BehavioralRule) _then) = __$BehavioralRuleCopyWithImpl;
@override @useResult
$Res call({
 int id, String actionType, String? category, String state, String ruleContent, int priority, bool isActive, String scope, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$BehavioralRuleCopyWithImpl<$Res>
    implements _$BehavioralRuleCopyWith<$Res> {
  __$BehavioralRuleCopyWithImpl(this._self, this._then);

  final _BehavioralRule _self;
  final $Res Function(_BehavioralRule) _then;

/// Create a copy of BehavioralRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? actionType = null,Object? category = freezed,Object? state = null,Object? ruleContent = null,Object? priority = null,Object? isActive = null,Object? scope = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_BehavioralRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,actionType: null == actionType ? _self.actionType : actionType // ignore: cast_nullable_to_non_nullable
as String,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,ruleContent: null == ruleContent ? _self.ruleContent : ruleContent // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$ActionIdentifier {

 String get actionType; String get description; String get category;
/// Create a copy of ActionIdentifier
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionIdentifierCopyWith<ActionIdentifier> get copyWith => _$ActionIdentifierCopyWithImpl<ActionIdentifier>(this as ActionIdentifier, _$identity);

  /// Serializes this ActionIdentifier to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActionIdentifier&&(identical(other.actionType, actionType) || other.actionType == actionType)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,actionType,description,category);

@override
String toString() {
  return 'ActionIdentifier(actionType: $actionType, description: $description, category: $category)';
}


}

/// @nodoc
abstract mixin class $ActionIdentifierCopyWith<$Res>  {
  factory $ActionIdentifierCopyWith(ActionIdentifier value, $Res Function(ActionIdentifier) _then) = _$ActionIdentifierCopyWithImpl;
@useResult
$Res call({
 String actionType, String description, String category
});




}
/// @nodoc
class _$ActionIdentifierCopyWithImpl<$Res>
    implements $ActionIdentifierCopyWith<$Res> {
  _$ActionIdentifierCopyWithImpl(this._self, this._then);

  final ActionIdentifier _self;
  final $Res Function(ActionIdentifier) _then;

/// Create a copy of ActionIdentifier
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? actionType = null,Object? description = null,Object? category = null,}) {
  return _then(_self.copyWith(
actionType: null == actionType ? _self.actionType : actionType // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ActionIdentifier].
extension ActionIdentifierPatterns on ActionIdentifier {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActionIdentifier value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActionIdentifier() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActionIdentifier value)  $default,){
final _that = this;
switch (_that) {
case _ActionIdentifier():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActionIdentifier value)?  $default,){
final _that = this;
switch (_that) {
case _ActionIdentifier() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String actionType,  String description,  String category)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActionIdentifier() when $default != null:
return $default(_that.actionType,_that.description,_that.category);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String actionType,  String description,  String category)  $default,) {final _that = this;
switch (_that) {
case _ActionIdentifier():
return $default(_that.actionType,_that.description,_that.category);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String actionType,  String description,  String category)?  $default,) {final _that = this;
switch (_that) {
case _ActionIdentifier() when $default != null:
return $default(_that.actionType,_that.description,_that.category);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ActionIdentifier implements ActionIdentifier {
  const _ActionIdentifier({required this.actionType, required this.description, required this.category});
  factory _ActionIdentifier.fromJson(Map<String, dynamic> json) => _$ActionIdentifierFromJson(json);

@override final  String actionType;
@override final  String description;
@override final  String category;

/// Create a copy of ActionIdentifier
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionIdentifierCopyWith<_ActionIdentifier> get copyWith => __$ActionIdentifierCopyWithImpl<_ActionIdentifier>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ActionIdentifierToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActionIdentifier&&(identical(other.actionType, actionType) || other.actionType == actionType)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,actionType,description,category);

@override
String toString() {
  return 'ActionIdentifier(actionType: $actionType, description: $description, category: $category)';
}


}

/// @nodoc
abstract mixin class _$ActionIdentifierCopyWith<$Res> implements $ActionIdentifierCopyWith<$Res> {
  factory _$ActionIdentifierCopyWith(_ActionIdentifier value, $Res Function(_ActionIdentifier) _then) = __$ActionIdentifierCopyWithImpl;
@override @useResult
$Res call({
 String actionType, String description, String category
});




}
/// @nodoc
class __$ActionIdentifierCopyWithImpl<$Res>
    implements _$ActionIdentifierCopyWith<$Res> {
  __$ActionIdentifierCopyWithImpl(this._self, this._then);

  final _ActionIdentifier _self;
  final $Res Function(_ActionIdentifier) _then;

/// Create a copy of ActionIdentifier
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? actionType = null,Object? description = null,Object? category = null,}) {
  return _then(_ActionIdentifier(
actionType: null == actionType ? _self.actionType : actionType // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
