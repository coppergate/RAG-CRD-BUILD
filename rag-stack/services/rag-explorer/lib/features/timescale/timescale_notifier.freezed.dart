// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timescale_notifier.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimescaleState {

 List<Session> get sessions; List<Tag> get availableTags; Session? get selectedSession; SessionHealth? get currentHealth; List<AuditEntry>? get auditLogs; bool get isLoading; bool get isLoadingDetails;
/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimescaleStateCopyWith<TimescaleState> get copyWith => _$TimescaleStateCopyWithImpl<TimescaleState>(this as TimescaleState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimescaleState&&const DeepCollectionEquality().equals(other.sessions, sessions)&&const DeepCollectionEquality().equals(other.availableTags, availableTags)&&(identical(other.selectedSession, selectedSession) || other.selectedSession == selectedSession)&&(identical(other.currentHealth, currentHealth) || other.currentHealth == currentHealth)&&const DeepCollectionEquality().equals(other.auditLogs, auditLogs)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isLoadingDetails, isLoadingDetails) || other.isLoadingDetails == isLoadingDetails));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(sessions),const DeepCollectionEquality().hash(availableTags),selectedSession,currentHealth,const DeepCollectionEquality().hash(auditLogs),isLoading,isLoadingDetails);

@override
String toString() {
  return 'TimescaleState(sessions: $sessions, availableTags: $availableTags, selectedSession: $selectedSession, currentHealth: $currentHealth, auditLogs: $auditLogs, isLoading: $isLoading, isLoadingDetails: $isLoadingDetails)';
}


}

/// @nodoc
abstract mixin class $TimescaleStateCopyWith<$Res>  {
  factory $TimescaleStateCopyWith(TimescaleState value, $Res Function(TimescaleState) _then) = _$TimescaleStateCopyWithImpl;
@useResult
$Res call({
 List<Session> sessions, List<Tag> availableTags, Session? selectedSession, SessionHealth? currentHealth, List<AuditEntry>? auditLogs, bool isLoading, bool isLoadingDetails
});


$SessionCopyWith<$Res>? get selectedSession;$SessionHealthCopyWith<$Res>? get currentHealth;

}
/// @nodoc
class _$TimescaleStateCopyWithImpl<$Res>
    implements $TimescaleStateCopyWith<$Res> {
  _$TimescaleStateCopyWithImpl(this._self, this._then);

  final TimescaleState _self;
  final $Res Function(TimescaleState) _then;

/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessions = null,Object? availableTags = null,Object? selectedSession = freezed,Object? currentHealth = freezed,Object? auditLogs = freezed,Object? isLoading = null,Object? isLoadingDetails = null,}) {
  return _then(_self.copyWith(
sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<Session>,availableTags: null == availableTags ? _self.availableTags : availableTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,selectedSession: freezed == selectedSession ? _self.selectedSession : selectedSession // ignore: cast_nullable_to_non_nullable
as Session?,currentHealth: freezed == currentHealth ? _self.currentHealth : currentHealth // ignore: cast_nullable_to_non_nullable
as SessionHealth?,auditLogs: freezed == auditLogs ? _self.auditLogs : auditLogs // ignore: cast_nullable_to_non_nullable
as List<AuditEntry>?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isLoadingDetails: null == isLoadingDetails ? _self.isLoadingDetails : isLoadingDetails // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCopyWith<$Res>? get selectedSession {
    if (_self.selectedSession == null) {
    return null;
  }

  return $SessionCopyWith<$Res>(_self.selectedSession!, (value) {
    return _then(_self.copyWith(selectedSession: value));
  });
}/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionHealthCopyWith<$Res>? get currentHealth {
    if (_self.currentHealth == null) {
    return null;
  }

  return $SessionHealthCopyWith<$Res>(_self.currentHealth!, (value) {
    return _then(_self.copyWith(currentHealth: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimescaleState].
extension TimescaleStatePatterns on TimescaleState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimescaleState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimescaleState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimescaleState value)  $default,){
final _that = this;
switch (_that) {
case _TimescaleState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimescaleState value)?  $default,){
final _that = this;
switch (_that) {
case _TimescaleState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Session> sessions,  List<Tag> availableTags,  Session? selectedSession,  SessionHealth? currentHealth,  List<AuditEntry>? auditLogs,  bool isLoading,  bool isLoadingDetails)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimescaleState() when $default != null:
return $default(_that.sessions,_that.availableTags,_that.selectedSession,_that.currentHealth,_that.auditLogs,_that.isLoading,_that.isLoadingDetails);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Session> sessions,  List<Tag> availableTags,  Session? selectedSession,  SessionHealth? currentHealth,  List<AuditEntry>? auditLogs,  bool isLoading,  bool isLoadingDetails)  $default,) {final _that = this;
switch (_that) {
case _TimescaleState():
return $default(_that.sessions,_that.availableTags,_that.selectedSession,_that.currentHealth,_that.auditLogs,_that.isLoading,_that.isLoadingDetails);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Session> sessions,  List<Tag> availableTags,  Session? selectedSession,  SessionHealth? currentHealth,  List<AuditEntry>? auditLogs,  bool isLoading,  bool isLoadingDetails)?  $default,) {final _that = this;
switch (_that) {
case _TimescaleState() when $default != null:
return $default(_that.sessions,_that.availableTags,_that.selectedSession,_that.currentHealth,_that.auditLogs,_that.isLoading,_that.isLoadingDetails);case _:
  return null;

}
}

}

/// @nodoc


class _TimescaleState implements TimescaleState {
  const _TimescaleState({final  List<Session> sessions = const [], final  List<Tag> availableTags = const [], this.selectedSession, this.currentHealth, final  List<AuditEntry>? auditLogs, this.isLoading = false, this.isLoadingDetails = false}): _sessions = sessions,_availableTags = availableTags,_auditLogs = auditLogs;
  

 final  List<Session> _sessions;
@override@JsonKey() List<Session> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}

 final  List<Tag> _availableTags;
@override@JsonKey() List<Tag> get availableTags {
  if (_availableTags is EqualUnmodifiableListView) return _availableTags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableTags);
}

@override final  Session? selectedSession;
@override final  SessionHealth? currentHealth;
 final  List<AuditEntry>? _auditLogs;
@override List<AuditEntry>? get auditLogs {
  final value = _auditLogs;
  if (value == null) return null;
  if (_auditLogs is EqualUnmodifiableListView) return _auditLogs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isLoadingDetails;

/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimescaleStateCopyWith<_TimescaleState> get copyWith => __$TimescaleStateCopyWithImpl<_TimescaleState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimescaleState&&const DeepCollectionEquality().equals(other._sessions, _sessions)&&const DeepCollectionEquality().equals(other._availableTags, _availableTags)&&(identical(other.selectedSession, selectedSession) || other.selectedSession == selectedSession)&&(identical(other.currentHealth, currentHealth) || other.currentHealth == currentHealth)&&const DeepCollectionEquality().equals(other._auditLogs, _auditLogs)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isLoadingDetails, isLoadingDetails) || other.isLoadingDetails == isLoadingDetails));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessions),const DeepCollectionEquality().hash(_availableTags),selectedSession,currentHealth,const DeepCollectionEquality().hash(_auditLogs),isLoading,isLoadingDetails);

@override
String toString() {
  return 'TimescaleState(sessions: $sessions, availableTags: $availableTags, selectedSession: $selectedSession, currentHealth: $currentHealth, auditLogs: $auditLogs, isLoading: $isLoading, isLoadingDetails: $isLoadingDetails)';
}


}

/// @nodoc
abstract mixin class _$TimescaleStateCopyWith<$Res> implements $TimescaleStateCopyWith<$Res> {
  factory _$TimescaleStateCopyWith(_TimescaleState value, $Res Function(_TimescaleState) _then) = __$TimescaleStateCopyWithImpl;
@override @useResult
$Res call({
 List<Session> sessions, List<Tag> availableTags, Session? selectedSession, SessionHealth? currentHealth, List<AuditEntry>? auditLogs, bool isLoading, bool isLoadingDetails
});


@override $SessionCopyWith<$Res>? get selectedSession;@override $SessionHealthCopyWith<$Res>? get currentHealth;

}
/// @nodoc
class __$TimescaleStateCopyWithImpl<$Res>
    implements _$TimescaleStateCopyWith<$Res> {
  __$TimescaleStateCopyWithImpl(this._self, this._then);

  final _TimescaleState _self;
  final $Res Function(_TimescaleState) _then;

/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessions = null,Object? availableTags = null,Object? selectedSession = freezed,Object? currentHealth = freezed,Object? auditLogs = freezed,Object? isLoading = null,Object? isLoadingDetails = null,}) {
  return _then(_TimescaleState(
sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<Session>,availableTags: null == availableTags ? _self._availableTags : availableTags // ignore: cast_nullable_to_non_nullable
as List<Tag>,selectedSession: freezed == selectedSession ? _self.selectedSession : selectedSession // ignore: cast_nullable_to_non_nullable
as Session?,currentHealth: freezed == currentHealth ? _self.currentHealth : currentHealth // ignore: cast_nullable_to_non_nullable
as SessionHealth?,auditLogs: freezed == auditLogs ? _self._auditLogs : auditLogs // ignore: cast_nullable_to_non_nullable
as List<AuditEntry>?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isLoadingDetails: null == isLoadingDetails ? _self.isLoadingDetails : isLoadingDetails // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCopyWith<$Res>? get selectedSession {
    if (_self.selectedSession == null) {
    return null;
  }

  return $SessionCopyWith<$Res>(_self.selectedSession!, (value) {
    return _then(_self.copyWith(selectedSession: value));
  });
}/// Create a copy of TimescaleState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionHealthCopyWith<$Res>? get currentHealth {
    if (_self.currentHealth == null) {
    return null;
  }

  return $SessionHealthCopyWith<$Res>(_self.currentHealth!, (value) {
    return _then(_self.copyWith(currentHealth: value));
  });
}
}

// dart format on
